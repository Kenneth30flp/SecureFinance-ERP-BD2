USE [SecureFinanceERP];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ListarClientes
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ClienteId, NIT, Nombre FROM dbo.Cliente WHERE Activo = 1 ORDER BY Nombre, ClienteId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ListarProductosDisponibles
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ProductoId, Codigo, Descripcion, Precio, Stock
    FROM dbo.Producto WHERE Activo = 1 ORDER BY Descripcion, ProductoId;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ProcesarVentaTransaccional
    @ClienteId INT,
    @UsuarioId INT,
    @Detalle dbo.TipoDetalleVenta READONLY,
    @FacturaId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @FacturaId = NULL;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF NOT EXISTS (SELECT 1 FROM @Detalle)
            THROW 52001, 'La venta debe contener productos.', 1;
        IF (SELECT COUNT_BIG(*) FROM @Detalle) > 100
            THROW 52002, 'La venta admite hasta 100 productos.', 1;
        IF EXISTS (SELECT 1 FROM @Detalle WHERE Cantidad <= 0 OR ProductoId <= 0)
            THROW 52003, 'Producto o cantidad inválidos.', 1;
        IF EXISTS (SELECT ProductoId FROM @Detalle GROUP BY ProductoId HAVING COUNT(*) > 1)
            THROW 52004, 'No se permiten productos repetidos.', 1;

        DECLARE @Activo BIT;
        SELECT @Activo = Activo FROM dbo.Cliente WITH (HOLDLOCK) WHERE ClienteId = @ClienteId;
        IF @Activo IS NULL THROW 52005, 'El cliente no existe.', 1;
        IF @Activo = 0 THROW 52006, 'El cliente está inactivo.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WITH (HOLDLOCK) WHERE UsuarioId = @UsuarioId AND Activo = 1)
            THROW 52007, 'El usuario no existe o está inactivo.', 1;

        DECLARE @Lineas TABLE (ProductoId INT PRIMARY KEY, Cantidad INT,
            PrecioUnitario DECIMAL(12,2), Subtotal DECIMAL(19,2));
        DECLARE @ProductoId INT = 0, @Siguiente INT, @Cantidad INT,
                @Precio DECIMAL(12,2), @Stock INT;
        -- Acceso puntual por PK en orden ascendente, independiente del orden del TVP.
        -- UPDLOCK + HOLDLOCK conserva precio/stock hasta COMMIT y serializa ventas
        -- del mismo producto. No se reintentan ventas automáticamente tras un timeout.
        WHILE 1 = 1
        BEGIN
            SELECT @Siguiente = MIN(ProductoId) FROM @Detalle WHERE ProductoId > @ProductoId;
            IF @Siguiente IS NULL BREAK;
            SET @ProductoId = @Siguiente;
            SELECT @Cantidad = Cantidad FROM @Detalle WHERE ProductoId = @ProductoId;
            SELECT @Precio = NULL, @Stock = NULL, @Activo = NULL;
            SELECT @Precio = Precio, @Stock = Stock, @Activo = Activo
            FROM dbo.Producto WITH (UPDLOCK, HOLDLOCK) WHERE ProductoId = @ProductoId;
            IF @Precio IS NULL THROW 52008, 'Un producto no existe.', 1;
            IF @Activo = 0 THROW 52009, 'Un producto está inactivo.', 1;
            IF @Stock < @Cantidad THROW 52010, 'Stock insuficiente para uno de los productos.', 1;
            INSERT @Lineas VALUES (@ProductoId, @Cantidad, @Precio,
                @Precio * CONVERT(DECIMAL(10,0), @Cantidad));
            UPDATE dbo.Producto SET Stock = Stock - @Cantidad WHERE ProductoId = @ProductoId;
        END;

        -- Punto de integración futuro con las funciones de José. Redondeo del IVA
        -- sobre el subtotal global, a dos decimales; nunca FLOAT ni importes del cliente.
        DECLARE @Subtotal DECIMAL(19,2), @IVA DECIMAL(19,2), @Total DECIMAL(19,2),
                @FechaHora DATETIME2(3) = SYSUTCDATETIME();
        SELECT @Subtotal = SUM(Subtotal) FROM @Lineas;
        SET @IVA = ROUND(@Subtotal * CONVERT(DECIMAL(3,2), 0.12), 2);
        SET @Total = @Subtotal + @IVA;
        INSERT dbo.Factura (ClienteId, UsuarioId, FechaHora, Subtotal, IVA, Total)
        VALUES (@ClienteId, @UsuarioId, @FechaHora, @Subtotal, @IVA, @Total);
        SET @FacturaId = CONVERT(INT, SCOPE_IDENTITY());
        INSERT dbo.DetalleFactura (FacturaId, ProductoId, Cantidad, PrecioUnitario, Subtotal)
        SELECT @FacturaId, ProductoId, Cantidad, PrecioUnitario, Subtotal FROM @Lineas;
        INSERT dbo.MovimientoCaja (FacturaId, Monto, FechaHora) VALUES (@FacturaId, @Total, @FechaHora);
        COMMIT TRANSACTION;
        -- Strings monetarios evitan pérdida de centavos al convertir DECIMAL(19,2) a JS Number.
        SELECT @FacturaId AS FacturaId, @FechaHora AS FechaHora,
            CONVERT(VARCHAR(21), @Subtotal) AS Subtotal,
            CONVERT(VARCHAR(21), @IVA) AS IVA, CONVERT(VARCHAR(21), @Total) AS Total;
    END TRY
    BEGIN CATCH
        -- Sin SAVEPOINT: la venta debe revertirse completa. Si el llamador abrió
        -- una transacción, también se revierte; Node llama el SP en autocommit.
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        SET @FacturaId = NULL;
        THROW;
    END CATCH;
END;
GO
