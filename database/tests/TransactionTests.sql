USE [SecureFinanceERP];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
-- Cuenta de desarrollo, después de 01-06. Ejecutar en una base de pruebas sin
-- escritores concurrentes. No crea/modifica usuarios, roles ni permisos.
-- Cada caso usa datos propios y ROLLBACK; los contadores IDENTITY pueden avanzar.
IF @@TRANCOUNT <> 0 THROW 52100, 'Ejecuta las pruebas sin una transacción externa.', 1;
DECLARE @UsuarioId INT = (SELECT MIN(UsuarioId) FROM dbo.Usuario WHERE Activo = 1);
IF @UsuarioId IS NULL THROW 52100, 'Se necesita un usuario activo existente (semilla 04).', 1;
IF EXISTS (SELECT 1 FROM dbo.Producto WHERE ProductoId = 2147483647)
   OR EXISTS (SELECT 1 FROM dbo.Cliente WHERE ClienteId = 2147483647)
   OR EXISTS (SELECT 1 FROM dbo.Usuario WHERE UsuarioId = 2147483647)
    THROW 52100, 'El ID reservado para pruebas inexistentes está ocupado.', 1;

DECLARE @Clientes BIGINT = (SELECT COUNT_BIG(*) FROM dbo.Cliente),
        @Productos BIGINT = (SELECT COUNT_BIG(*) FROM dbo.Producto),
        @Facturas BIGINT = (SELECT COUNT_BIG(*) FROM dbo.Factura),
        @Detalles BIGINT = (SELECT COUNT_BIG(*) FROM dbo.DetalleFactura),
        @Movimientos BIGINT = (SELECT COUNT_BIG(*) FROM dbo.MovimientoCaja);
SELECT ProductoId, Stock, Precio, Activo INTO #StockAnterior FROM dbo.Producto;
DECLARE @Caso INT = 1, @Cliente INT, @P1 INT, @P2 INT, @Factura INT,
        @ClienteEntrada INT, @UsuarioEntrada INT, @Esperado INT, @Error INT,
        @Tag NVARCHAR(36), @Detalle dbo.TipoDetalleVenta;

BEGIN TRY
    WHILE @Caso <= 15
    BEGIN
        DELETE FROM @Detalle;
        SET @Esperado = NULL;
        SET @Error = NULL;
        SET @Factura = NULL;
        SET @Tag = CONVERT(NVARCHAR(36), NEWID());
        BEGIN TRANSACTION;
        INSERT dbo.Cliente (NIT, Nombre) VALUES (LEFT(@Tag, 25), N'Cliente prueba transaccional');
        SET @Cliente = CONVERT(INT, SCOPE_IDENTITY());
        INSERT dbo.Producto (Codigo, Descripcion, Precio, Stock) VALUES (@Tag + N'-1', N'Producto prueba uno', 10.25, 10);
        SET @P1 = CONVERT(INT, SCOPE_IDENTITY());
        INSERT dbo.Producto (Codigo, Descripcion, Precio, Stock) VALUES (@Tag + N'-2', N'Producto prueba dos', 3.10, 10);
        SET @P2 = CONVERT(INT, SCOPE_IDENTITY());
        SELECT @ClienteEntrada = @Cliente, @UsuarioEntrada = @UsuarioId;
        INSERT @Detalle VALUES (@P1, 2);
        IF @Caso = 2 INSERT @Detalle VALUES (@P2, 3);
        IF @Caso = 3 BEGIN INSERT @Detalle VALUES (@P2, 11); SET @Esperado = 52010; END;
        IF @Caso = 4 BEGIN INSERT @Detalle VALUES (2147483647, 1); SET @Esperado = 52008; END;
        IF @Caso = 5 SELECT @ClienteEntrada = 2147483647, @Esperado = 52005;
        IF @Caso = 6 BEGIN UPDATE @Detalle SET Cantidad = 0; SET @Esperado = 52003; END;
        IF @Caso = 7 SELECT @UsuarioEntrada = 2147483647, @Esperado = 52007;
        IF @Caso = 8 BEGIN DELETE FROM @Detalle; SET @Esperado = 52001; END;
        IF @Caso = 9 BEGIN INSERT @Detalle VALUES (@P1, 1); SET @Esperado = 52004; END;
        IF @Caso = 10 BEGIN UPDATE dbo.Cliente SET Activo = 0 WHERE ClienteId = @Cliente; SET @Esperado = 52006; END;
        IF @Caso = 11
        BEGIN
            UPDATE dbo.Producto SET Activo = 0 WHERE ProductoId = @P2;
            INSERT @Detalle VALUES (@P2, 1);
            SET @Esperado = 52009;
        END;
        IF @Caso = 12
        BEGIN
            -- Falla al final, DESPUÉS de factura/detalles/descuento. El DDL pertenece
            -- a esta transacción y también desaparece con el rollback del SP.
            ALTER TABLE dbo.MovimientoCaja WITH NOCHECK
                ADD CONSTRAINT CK_MovimientoCaja_PruebaRollback CHECK (Monto < 0);
            SET @Esperado = 547;
        END;
        IF @Caso = 13 BEGIN UPDATE @Detalle SET Cantidad = -1; SET @Esperado = 52003; END;
        IF @Caso = 14
        BEGIN
            WHILE (SELECT COUNT(*) FROM @Detalle) < 101 INSERT @Detalle VALUES (@P1, 1);
            SET @Esperado = 52002;
        END;
        IF @Caso = 15
        BEGIN
            UPDATE dbo.Producto SET Precio = 9999999999.99, Stock = 2147483647 WHERE ProductoId = @P1;
            UPDATE @Detalle SET Cantidad = 2147483647;
            SET @Esperado = 8115; -- Desbordamiento DECIMAL: nunca guardar importes truncados.
        END;

        BEGIN TRY
            -- No INSERT EXEC: SQL Server no permite ROLLBACK dentro de INSERT EXEC.
            EXEC dbo.sp_ProcesarVentaTransaccional @ClienteEntrada, @UsuarioEntrada, @Detalle, @Factura OUTPUT;
        END TRY
        BEGIN CATCH
            SET @Error = ERROR_NUMBER();
        END CATCH;
        IF @Esperado IS NOT NULL
        BEGIN
            IF @Error IS NULL OR @Error <> @Esperado THROW 52101, 'No se recibió el error esperado.', 1;
            IF @@TRANCOUNT <> 0 OR XACT_STATE() <> 0 THROW 52102, 'La transacción fallida quedó abierta.', 1;
            IF @Factura IS NOT NULL THROW 52103, 'Una venta fallida devolvió FacturaId.', 1;
        END
        ELSE
        BEGIN
            IF @Error IS NOT NULL THROW 52104, 'Una venta válida falló.', 1;
            IF @@TRANCOUNT <> 1 THROW 52105, 'El SP no conservó la transacción externa de prueba.', 1;
            DECLARE @Subtotal DECIMAL(19,2) = CASE @Caso WHEN 1 THEN 20.50 ELSE 29.80 END,
                    @IVA DECIMAL(19,2) = CASE @Caso WHEN 1 THEN 2.46 ELSE 3.58 END;
            IF @Factura IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Factura WHERE FacturaId = @Factura
                AND ClienteId = @Cliente AND UsuarioId = @UsuarioId AND Estado = 'EMITIDA'
                AND Subtotal = @Subtotal AND IVA = @IVA AND Total = @Subtotal + @IVA)
                THROW 52106, 'Factura o importes incorrectos.', 1;
            IF (SELECT COUNT(*) FROM dbo.DetalleFactura WHERE FacturaId = @Factura) <> @Caso
                THROW 52107, 'Cantidad de líneas incorrecta.', 1;
            IF NOT EXISTS (SELECT 1 FROM dbo.DetalleFactura WHERE FacturaId = @Factura AND ProductoId = @P1
                AND Cantidad = 2 AND PrecioUnitario = 10.25 AND Subtotal = 20.50)
                THROW 52108, 'Primer detalle incorrecto.', 1;
            IF @Caso = 2 AND NOT EXISTS (SELECT 1 FROM dbo.DetalleFactura WHERE FacturaId = @Factura AND ProductoId = @P2
                AND Cantidad = 3 AND PrecioUnitario = 3.10 AND Subtotal = 9.30)
                THROW 52109, 'Segundo detalle incorrecto.', 1;
            IF (SELECT Stock FROM dbo.Producto WHERE ProductoId = @P1) <> 8
                OR (SELECT Stock FROM dbo.Producto WHERE ProductoId = @P2) <> CASE @Caso WHEN 1 THEN 10 ELSE 7 END
                THROW 52110, 'Descuento de stock incorrecto.', 1;
            IF NOT EXISTS (SELECT 1 FROM dbo.MovimientoCaja WHERE FacturaId = @Factura
                AND TipoMovimiento = 'INGRESO' AND Monto = @Subtotal + @IVA)
                THROW 52111, 'Movimiento económico incorrecto.', 1;
            IF (SELECT COUNT_BIG(*) FROM dbo.Factura) <> @Facturas + 1
                OR (SELECT COUNT_BIG(*) FROM dbo.DetalleFactura) <> @Detalles + @Caso
                OR (SELECT COUNT_BIG(*) FROM dbo.MovimientoCaja) <> @Movimientos + 1
                THROW 52112, 'Filas adicionales inesperadas.', 1;
            ROLLBACK TRANSACTION;
        END;
        IF (SELECT COUNT_BIG(*) FROM dbo.Cliente) <> @Clientes
            OR (SELECT COUNT_BIG(*) FROM dbo.Producto) <> @Productos
            OR (SELECT COUNT_BIG(*) FROM dbo.Factura) <> @Facturas
            OR (SELECT COUNT_BIG(*) FROM dbo.DetalleFactura) <> @Detalles
            OR (SELECT COUNT_BIG(*) FROM dbo.MovimientoCaja) <> @Movimientos
            THROW 52113, 'Quedaron filas parciales después de rollback.', 1;
        IF EXISTS (SELECT ProductoId, Stock, Precio, Activo FROM #StockAnterior
                   EXCEPT SELECT ProductoId, Stock, Precio, Activo FROM dbo.Producto)
            OR EXISTS (SELECT ProductoId, Stock, Precio, Activo FROM dbo.Producto
                       EXCEPT SELECT ProductoId, Stock, Precio, Activo FROM #StockAnterior)
            THROW 52114, 'Stock/precio/estado no restaurados.', 1;
        IF OBJECT_ID(N'dbo.CK_MovimientoCaja_PruebaRollback', N'C') IS NOT NULL
            THROW 52115, 'La restricción temporal no se revirtió.', 1;
        PRINT CONCAT(N'OK: caso transaccional ', @Caso);
        SET @Caso += 1;
    END;
    DROP TABLE #StockAnterior;
    PRINT N'OK: Transacciones de venta y control ACID validados.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    DROP TABLE IF EXISTS #StockAnterior;
    THROW;
END CATCH;
GO
