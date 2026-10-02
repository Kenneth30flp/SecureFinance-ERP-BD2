-- Existing database migration. No tables, history or previous TVP are deleted.
-- Stop the Node application during deployment; execute with an administrator.
-- Idempotent and atomic, including procedures, audit and grants.
USE [SecureFinanceERP];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC sys.sp_executesql N'IF COL_LENGTH(''dbo.Factura'', ''DescuentoTotal'') IS NULL ALTER TABLE dbo.Factura ADD DescuentoTotal DECIMAL(19,2) NOT NULL CONSTRAINT DF_Factura_DescuentoTotal DEFAULT (0) WITH VALUES;';
    EXEC sys.sp_executesql N'IF COL_LENGTH(''dbo.DetalleFactura'', ''DescuentoPorcentaje'') IS NULL ALTER TABLE dbo.DetalleFactura ADD DescuentoPorcentaje DECIMAL(5,2) NOT NULL CONSTRAINT DF_DetalleFactura_DescuentoPorcentaje DEFAULT (0) WITH VALUES;';
    EXEC sys.sp_executesql N'IF COL_LENGTH(''dbo.DetalleFactura'', ''DescuentoMonto'') IS NULL ALTER TABLE dbo.DetalleFactura ADD DescuentoMonto DECIMAL(19,2) NOT NULL CONSTRAINT DF_DetalleFactura_DescuentoMonto DEFAULT (0) WITH VALUES;';
    EXEC sys.sp_executesql N'IF COL_LENGTH(''dbo.DetalleFactura'', ''SubtotalNeto'') IS NULL ALTER TABLE dbo.DetalleFactura ADD SubtotalNeto AS (Subtotal - DescuentoMonto) PERSISTED;';
    EXEC sys.sp_executesql N'IF OBJECT_ID(''dbo.CK_Factura_Importes'', ''C'') IS NOT NULL ALTER TABLE dbo.Factura DROP CONSTRAINT CK_Factura_Importes;
ALTER TABLE dbo.Factura WITH CHECK ADD CONSTRAINT CK_Factura_Importes CHECK (Subtotal >= 0 AND DescuentoTotal BETWEEN 0 AND Subtotal AND IVA >= 0 AND Total = Subtotal - DescuentoTotal + IVA);';
    EXEC sys.sp_executesql N'IF OBJECT_ID(''dbo.CK_DetalleFactura_Descuento'', ''C'') IS NULL ALTER TABLE dbo.DetalleFactura WITH CHECK ADD CONSTRAINT CK_DetalleFactura_Descuento CHECK (DescuentoPorcentaje BETWEEN 0 AND 100 AND DescuentoMonto BETWEEN 0 AND Subtotal AND DescuentoMonto = ROUND(Subtotal * DescuentoPorcentaje / CONVERT(DECIMAL(5,2), 100), 2));';
    EXEC sys.sp_executesql N'IF TYPE_ID(''dbo.TipoDetalleVentaDescuento'') IS NULL EXEC(N''CREATE TYPE dbo.TipoDetalleVentaDescuento AS TABLE (ProductoId INT NOT NULL, Cantidad INT NOT NULL, DescuentoPorcentaje DECIMAL(5,2) NOT NULL DEFAULT (0));'');';
    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ProcesarVentaTransaccional
    @ClienteId INT,
    @UsuarioId INT,
    @Detalle dbo.TipoDetalleVentaDescuento READONLY,
    @FacturaId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @FacturaId = NULL;
    BEGIN TRY
        BEGIN TRANSACTION;
        IF NOT EXISTS (SELECT 1 FROM @Detalle)
            THROW 52001, ''La venta debe contener productos.'', 1;
        IF (SELECT COUNT_BIG(*) FROM @Detalle) > 100
            THROW 52002, ''La venta admite hasta 100 productos.'', 1;
        IF EXISTS (SELECT 1 FROM @Detalle WHERE Cantidad <= 0 OR ProductoId <= 0)
            THROW 52003, ''Producto o cantidad inválidos.'', 1;
        IF EXISTS (SELECT ProductoId FROM @Detalle GROUP BY ProductoId HAVING COUNT(*) > 1)
            THROW 52004, ''No se permiten productos repetidos.'', 1;

        IF EXISTS (SELECT 1 FROM @Detalle WHERE DescuentoPorcentaje IS NULL OR DescuentoPorcentaje < 0 OR DescuentoPorcentaje > 100)
            THROW 52011, ''El descuento debe estar entre 0.00 y 100.00.'', 1;

        DECLARE @Activo BIT;
        SELECT @Activo = Activo FROM dbo.Cliente WITH (HOLDLOCK) WHERE ClienteId = @ClienteId;
        IF @Activo IS NULL THROW 52005, ''El cliente no existe.'', 1;
        IF @Activo = 0 THROW 52006, ''El cliente está inactivo.'', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WITH (HOLDLOCK) WHERE UsuarioId = @UsuarioId AND Activo = 1)
            THROW 52007, ''El usuario no existe o está inactivo.'', 1;

        DECLARE @Lineas TABLE (ProductoId INT PRIMARY KEY, Cantidad INT,
            PrecioUnitario DECIMAL(12,2), Subtotal DECIMAL(19,2),
            DescuentoPorcentaje DECIMAL(5,2), DescuentoMonto DECIMAL(19,2), SubtotalNeto DECIMAL(19,2));
        DECLARE @ProductoId INT = 0, @Siguiente INT, @Cantidad INT,
                @Precio DECIMAL(12,2), @Stock INT, @Porcentaje DECIMAL(5,2),
                @Bruto DECIMAL(19,2), @MontoDescuento DECIMAL(19,2);
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
            SELECT @Precio = Precio, @Stock = Stock, @Activo = Activo
            FROM dbo.Producto WITH (UPDLOCK, HOLDLOCK) WHERE ProductoId = @ProductoId;
            IF @Precio IS NULL THROW 52008, ''Un producto no existe.'', 1;
            IF @Activo = 0 THROW 52009, ''Un producto está inactivo.'', 1;
            IF @Stock < @Cantidad THROW 52010, ''Stock insuficiente para uno de los productos.'', 1;
            SET @Bruto = @Precio * CONVERT(DECIMAL(10,0), @Cantidad);
            SET @MontoDescuento = ROUND(@Bruto * @Porcentaje / CONVERT(DECIMAL(5,2), 100), 2);
            INSERT @Lineas VALUES (@ProductoId, @Cantidad, @Precio, @Bruto,
                @Porcentaje, @MontoDescuento, @Bruto - @MontoDescuento);
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
        INSERT dbo.Factura (ClienteId, UsuarioId, FechaHora, Subtotal, DescuentoTotal, IVA, Total)
        VALUES (@ClienteId, @UsuarioId, @FechaHora, @Subtotal, @Descuento, @IVA, @Total);
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
            CONVERT(VARCHAR(21), @IVA) AS IVA, CONVERT(VARCHAR(21), @Total) AS Total;
    END TRY
    BEGIN CATCH
        -- Sin SAVEPOINT: la venta debe revertirse completa. Si el llamador abrió
        -- una transacción, también se revierte; Node llama el SP en autocommit.
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        SET @FacturaId = NULL;
        THROW;
    END CATCH;
END;';
    EXEC sys.sp_executesql N'-- Adaptador para integraciones que conservan el TVP anterior.
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
END;';
    EXEC sys.sp_executesql N'CREATE OR ALTER FUNCTION dbo.fn_ObtenerHistoricoVentas
(
    @FechaInicial DATETIME2(3) = NULL,
    @FechaFinal DATETIME2(3) = NULL,
    @Cliente NVARCHAR(150) = NULL
)
RETURNS TABLE
AS
RETURN
    SELECT f.FacturaId AS Factura, f.FechaHora AS Fecha,
           c.Nombre AS Cliente, u.NombreUsuario AS Usuario,
           f.Subtotal, f.IVA, f.Total, f.DescuentoTotal AS Descuento,
           f.Subtotal - f.DescuentoTotal AS SubtotalNeto
    FROM dbo.Factura AS f
    INNER JOIN dbo.Cliente AS c ON c.ClienteId = f.ClienteId
    INNER JOIN dbo.Usuario AS u ON u.UsuarioId = f.UsuarioId
    WHERE (@FechaInicial IS NULL OR f.FechaHora >= @FechaInicial)
      AND (@FechaFinal IS NULL OR f.FechaHora <= @FechaFinal)
      AND (@Cliente IS NULL OR CHARINDEX(@Cliente, c.Nombre) > 0);';
    EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ConsultarHistoricoVentas
    @FechaInicial DATETIME2(3) = NULL,
    @FechaFinal DATETIME2(3) = NULL,
    @Cliente NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Factura, Fecha, Cliente, Usuario, Subtotal, IVA, Total, Descuento, SubtotalNeto
    FROM dbo.fn_ObtenerHistoricoVentas(@FechaInicial, @FechaFinal, @Cliente)
    ORDER BY Fecha DESC, Factura DESC;
END;';
    EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_Factura_Auditar_Insert
ON dbo.Factura
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Bitacora_Transacciones
        (TablaAfectada, Operacion, UsuarioSQL, HostName, AppName,
         IdentificadorRegistro, ValorAnterior, ValorNuevo)
    SELECT N''Factura'', ''INSERT'', SUSER_SNAME(), HOST_NAME(), APP_NAME(),
           CONVERT(NVARCHAR(4000), i.FacturaId),
           NULL,
           (SELECT i.FacturaId, i.ClienteId, i.UsuarioId, i.FechaHora, i.Subtotal, i.DescuentoTotal, i.IVA, i.Total, i.Estado FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM inserted AS i;
END;';
    EXEC sys.sp_executesql N'IF DATABASE_PRINCIPAL_ID(N''securefinance_app'') IS NOT NULL
BEGIN
 GRANT EXECUTE, REFERENCES ON TYPE::dbo.TipoDetalleVentaDescuento TO [securefinance_app];
 GRANT EXECUTE ON OBJECT::dbo.sp_ProcesarVentaTransaccional TO [securefinance_app];
 GRANT EXECUTE ON OBJECT::dbo.sp_ProcesarVentaSinDescuento TO [securefinance_app];
END;';
    COMMIT TRANSACTION;
    PRINT N'OK: sales discounts migration applied.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
