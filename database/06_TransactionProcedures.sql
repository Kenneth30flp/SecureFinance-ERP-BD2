USE [SecureFinanceERP];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
-- Política compartida por la preparación y el COMMIT. Sin roles del navegador.
CREATE OR ALTER FUNCTION dbo.fn_ObtenerPoliticaVenta (@UsuarioId INT)
RETURNS TABLE
AS RETURN
    SELECT CONVERT(BIT, COALESCE(MAX(CASE WHEN p.Codigo = N'VENTAS_REGISTRAR' THEN 1 ELSE 0 END), 0)) AS PuedeVender,
        CONVERT(DECIMAL(5,2), CASE WHEN MAX(CASE WHEN r.Nombre = N'Administrador'
            AND p.Codigo = N'VENTAS_REGISTRAR' THEN 1 ELSE 0 END) = 1 THEN 100 ELSE 10 END) AS MaxDescuento
    FROM dbo.Usuario u WITH (HOLDLOCK)
    INNER JOIN dbo.Usuario_Rol ur WITH (HOLDLOCK) ON ur.UsuarioId = u.UsuarioId
    INNER JOIN dbo.Rol r WITH (HOLDLOCK) ON r.RolId = ur.RolId AND r.Activo = 1
    INNER JOIN dbo.Rol_Permiso rp WITH (HOLDLOCK) ON rp.RolId = r.RolId
    INNER JOIN dbo.Permiso p WITH (HOLDLOCK) ON p.PermisoId = rp.PermisoId AND p.Activo = 1
    WHERE u.UsuarioId = @UsuarioId AND u.Activo = 1;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ObtenerPoliticaVenta @UsuarioId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = @UsuarioId AND Activo = 1)
        THROW 52007, 'El usuario no existe o está inactivo.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_ObtenerPoliticaVenta(@UsuarioId) WHERE PuedeVender = 1)
        THROW 52013, 'No tienes permiso para registrar ventas.', 1;
    SELECT MaxDescuento FROM dbo.fn_ObtenerPoliticaVenta(@UsuarioId);
END;
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
    @Detalle dbo.TipoDetalleVentaDescuento READONLY,
    @FacturaId INT = NULL OUTPUT,
    @MotivoDescuento NVARCHAR(80) = NULL
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

        IF EXISTS (SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje IS NULL OR DescuentoPorcentaje < 0 OR DescuentoPorcentaje > 100)
            THROW 52011, 'El descuento debe estar entre 0.00 y 100.00.', 1;

        DECLARE @Activo BIT, @ClienteNombre NVARCHAR(150), @NIT NVARCHAR(25), @Cajero NVARCHAR(50);
        SELECT @Activo = Activo, @ClienteNombre = Nombre, @NIT = NIT
        FROM dbo.Cliente WITH (HOLDLOCK) WHERE ClienteId = @ClienteId;
        IF @Activo IS NULL THROW 52005, 'El cliente no existe.', 1;
        IF @Activo = 0 THROW 52006, 'El cliente está inactivo.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WITH (HOLDLOCK) WHERE UsuarioId = @UsuarioId AND Activo = 1)
            THROW 52007, 'El usuario no existe o está inactivo.', 1;
        DECLARE @MaxDescuento DECIMAL(5,2), @PuedeVender BIT;
        SELECT @MaxDescuento = MaxDescuento, @PuedeVender = PuedeVender
        FROM dbo.fn_ObtenerPoliticaVenta(@UsuarioId);
        IF @PuedeVender = 0 THROW 52013, 'No tienes permiso para registrar ventas.', 1;
        IF EXISTS (SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje > @MaxDescuento)
            THROW 52012, 'El descuento máximo autorizado para tu rol es 10%.', 1;
        SET @MotivoDescuento = NULLIF(LTRIM(RTRIM(@MotivoDescuento)), N'');
        IF @MotivoDescuento IS NOT NULL AND @MotivoDescuento NOT IN
            (N'Promoción', N'Cliente frecuente', N'Ajuste comercial', N'Autorización administrativa', N'Otro')
            THROW 52014, 'Selecciona un motivo de descuento válido.', 1;
        IF NOT EXISTS (SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje > 0) SET @MotivoDescuento = NULL;
        SELECT @Cajero = NombreUsuario FROM dbo.Usuario WITH (HOLDLOCK) WHERE UsuarioId = @UsuarioId;

        DECLARE @Lineas TABLE (ProductoId INT PRIMARY KEY, Cantidad INT,
            PrecioUnitario DECIMAL(12,2), Subtotal DECIMAL(19,2),
            DescuentoPorcentaje DECIMAL(5,2), DescuentoMonto DECIMAL(19,2), SubtotalNeto DECIMAL(19,2),
            Descripcion NVARCHAR(200));
        DECLARE @ProductoId INT = 0, @Siguiente INT, @Cantidad INT,
                @Precio DECIMAL(12,2), @Stock INT, @Porcentaje DECIMAL(5,2),
                @Bruto DECIMAL(19,2), @MontoDescuento DECIMAL(19,2), @Descripcion NVARCHAR(200);
        -- Acceso puntual por PK en orden ascendente, independiente del orden del TVP.
        -- UPDLOCK + HOLDLOCK conserva precio/stock hasta COMMIT y serializa ventas
        -- del mismo producto. No se reintentan ventas automáticamente tras un timeout.
        WHILE 1 = 1
        BEGIN
            SELECT @Siguiente = MIN(ProductoId) FROM @Detalle WHERE ProductoId > @ProductoId;
            IF @Siguiente IS NULL BREAK;
            SET @ProductoId = @Siguiente;
            SELECT @Cantidad = Cantidad, @Porcentaje = DescuentoPorcentaje FROM @Detalle WHERE ProductoId = @ProductoId;
            SELECT @Precio = NULL, @Stock = NULL, @Activo = NULL;
            SELECT @Precio = Precio, @Stock = Stock, @Activo = Activo, @Descripcion = Descripcion
            FROM dbo.Producto WITH (UPDLOCK, HOLDLOCK) WHERE ProductoId = @ProductoId;
            IF @Precio IS NULL THROW 52008, 'Un producto no existe.', 1;
            IF @Activo = 0 THROW 52009, 'Un producto está inactivo.', 1;
            IF @Stock < @Cantidad THROW 52010, 'Stock insuficiente para uno de los productos.', 1;
            SET @Bruto = @Precio * CONVERT(DECIMAL(10,0), @Cantidad);
            SET @MontoDescuento = ROUND(@Bruto * @Porcentaje / CONVERT(DECIMAL(5,2), 100), 2);
            INSERT @Lineas VALUES (@ProductoId, @Cantidad, @Precio, @Bruto,
                @Porcentaje, @MontoDescuento, @Bruto - @MontoDescuento, @Descripcion);
            UPDATE dbo.Producto SET Stock = Stock - @Cantidad WHERE ProductoId = @ProductoId;
        END;

        -- Descuento por línea e IVA sobre el neto global, redondeados a centavos.
        -- ROUND: mitades hacia arriba para importes no negativos; solo DECIMAL.
        DECLARE @Descuento DECIMAL(19,2), @SubtotalNeto DECIMAL(19,2),
                @Subtotal DECIMAL(19,2), @IVA DECIMAL(19,2), @Total DECIMAL(19,2),
                @FechaHora DATETIME2(3) = SYSUTCDATETIME();
        SELECT @Subtotal = SUM(Subtotal), @Descuento = SUM(DescuentoMonto),
            @SubtotalNeto = SUM(SubtotalNeto) FROM @Lineas;
        SET @IVA = ROUND(@SubtotalNeto * CONVERT(DECIMAL(3,2), 0.12), 2);
        SET @Total = @SubtotalNeto + @IVA;
        INSERT dbo.Factura (ClienteId, UsuarioId, FechaHora, Subtotal, DescuentoTotal, IVA, Total, MotivoDescuento)
        VALUES (@ClienteId, @UsuarioId, @FechaHora, @Subtotal, @Descuento, @IVA, @Total, @MotivoDescuento);
        SET @FacturaId = CONVERT(INT, SCOPE_IDENTITY());
        INSERT dbo.DetalleFactura (FacturaId, ProductoId, Cantidad, PrecioUnitario, Subtotal, DescuentoPorcentaje, DescuentoMonto)
        SELECT @FacturaId, ProductoId, Cantidad, PrecioUnitario, Subtotal, DescuentoPorcentaje, DescuentoMonto FROM @Lineas;
        INSERT dbo.MovimientoCaja (FacturaId, Monto, FechaHora) VALUES (@FacturaId, @Total, @FechaHora);
        COMMIT TRANSACTION;
        -- Strings monetarios evitan pérdida de centavos al convertir DECIMAL(19,2) a JS Number.
        SELECT @FacturaId AS FacturaId, @FechaHora AS FechaHora,
            CONVERT(VARCHAR(21), @Subtotal) AS Subtotal,
            CONVERT(VARCHAR(21), @Descuento) AS Descuento,
            CONVERT(VARCHAR(21), @SubtotalNeto) AS SubtotalNeto,
            CONVERT(VARCHAR(21), @IVA) AS IVA, CONVERT(VARCHAR(21), @Total) AS Total,
            @ClienteNombre AS Cliente, @NIT AS NIT, @Cajero AS Cajero, @MotivoDescuento AS MotivoDescuento;
        SELECT ProductoId, Descripcion, Cantidad,
            CONVERT(VARCHAR(21), PrecioUnitario) AS PrecioUnitario,
            CONVERT(VARCHAR(21), Subtotal) AS Subtotal,
            CONVERT(VARCHAR(6), DescuentoPorcentaje) AS DescuentoPorcentaje,
            CONVERT(VARCHAR(21), DescuentoMonto) AS DescuentoMonto,
            CONVERT(VARCHAR(21), SubtotalNeto) AS SubtotalNeto
        FROM @Lineas ORDER BY ProductoId;
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

-- Adaptador para integraciones que conservan el TVP anterior.
CREATE OR ALTER PROCEDURE dbo.sp_ProcesarVentaSinDescuento
    @ClienteId INT, @UsuarioId INT, @Detalle dbo.TipoDetalleVenta READONLY,
    @FacturaId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Nuevo dbo.TipoDetalleVentaDescuento;
    INSERT @Nuevo (ProductoId, Cantidad, DescuentoPorcentaje)
    SELECT ProductoId, Cantidad, 0 FROM @Detalle;
    EXEC dbo.sp_ProcesarVentaTransaccional @ClienteId, @UsuarioId, @Nuevo, @FacturaId OUTPUT;
END;
GO
