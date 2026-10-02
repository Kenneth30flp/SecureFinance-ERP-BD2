USE [SecureFinanceERP];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT <> 0 THROW 52300, 'Run without an outer transaction.', 1;
DECLARE @Usuario INT = (SELECT MIN(UsuarioId) FROM dbo.Usuario WHERE Activo = 1),
        @Caso INT = 1, @Cliente INT, @P1 INT, @P2 INT, @Factura INT,
        @Error INT, @Esperado INT, @Porcentaje DECIMAL(5,2),
        @Descuento DECIMAL(19,2), @Bruto DECIMAL(19,2), @Neto DECIMAL(19,2),
        @IVA DECIMAL(19,2), @Detalle dbo.TipoDetalleVentaDescuento;
DECLARE @Facturas BIGINT = (SELECT COUNT_BIG(*) FROM dbo.Factura),
        @Detalles BIGINT = (SELECT COUNT_BIG(*) FROM dbo.DetalleFactura),
        @Caja BIGINT = (SELECT COUNT_BIG(*) FROM dbo.MovimientoCaja),
        @Auditoria BIGINT = (SELECT COUNT_BIG(*) FROM dbo.Bitacora_Transacciones);
SELECT ProductoId, Stock INTO #StockDescuentos FROM dbo.Producto;
BEGIN TRY
 WHILE @Caso <= 9
 BEGIN
  DELETE @Detalle;
  SELECT @Factura = NULL, @Error = NULL, @Esperado = NULL;
  SET @Porcentaje = CASE @Caso WHEN 1 THEN 0 WHEN 2 THEN 10 WHEN 3 THEN 7.50
      WHEN 4 THEN 100 WHEN 5 THEN -1 WHEN 6 THEN 100.01 ELSE 10 END;
  BEGIN TRANSACTION;
  DECLARE @Tag NVARCHAR(36) = CONVERT(NVARCHAR(36), NEWID());
  INSERT dbo.Cliente (NIT, Nombre) VALUES (LEFT(@Tag,25), N'Discount test');
  SET @Cliente = SCOPE_IDENTITY();
  INSERT dbo.Producto (Codigo, Descripcion, Precio, Stock) VALUES (@Tag, N'Cable HDMI', 35.90, 10);
  SET @P1 = SCOPE_IDENTITY();
  INSERT dbo.Producto (Codigo, Descripcion, Precio, Stock) VALUES (@Tag + '-2', N'Other', 10.25, 10);
  SET @P2 = SCOPE_IDENTITY();
  INSERT @Detalle VALUES (@P1, 1, @Porcentaje);
  IF @Caso IN (5,6) SET @Esperado = 52011;
  IF @Caso = 7 INSERT @Detalle VALUES (@P2, 2, 7.50);
  IF @Caso = 8
  BEGIN
   ALTER TABLE dbo.MovimientoCaja WITH NOCHECK ADD CONSTRAINT CK_Caja_DiscountRollback CHECK (Monto < 0);
   SET @Esperado = 547;
  END;
  IF @Caso = 9
  BEGIN
   INSERT @Detalle VALUES (@P2, 11, 100);
   SET @Esperado = 52010;
  END;
  BEGIN TRY
   EXEC dbo.sp_ProcesarVentaTransaccional @Cliente, @Usuario, @Detalle, @Factura OUTPUT;
  END TRY BEGIN CATCH
   SET @Error = ERROR_NUMBER();
  END CATCH;
  IF @Esperado IS NOT NULL
  BEGIN
   IF @Error IS NULL OR @Error <> @Esperado OR @Factura IS NOT NULL OR @@TRANCOUNT <> 0
    THROW 52301, 'Expected complete rollback and business error.', 1;
  END
  ELSE
  BEGIN
   IF @Error IS NOT NULL THROW 52302, 'Valid discounted sale failed.', 1;
   -- Literal expectations, independent of the implementation formula.
   SET @Bruto = CASE WHEN @Caso = 7 THEN 56.40 ELSE 35.90 END;
   SET @Descuento = CASE @Caso WHEN 1 THEN 0 WHEN 2 THEN 3.59 WHEN 3 THEN 2.69
       WHEN 4 THEN 35.90 WHEN 7 THEN 5.13 END;
   SET @Neto = @Bruto - @Descuento;
   SET @IVA = CASE @Caso WHEN 1 THEN 4.31 WHEN 2 THEN 3.88 WHEN 3 THEN 3.99
       WHEN 4 THEN 0 WHEN 7 THEN 6.15 END;
   IF NOT EXISTS (SELECT 1 FROM dbo.Factura WHERE FacturaId = @Factura AND Subtotal = @Bruto
       AND DescuentoTotal = @Descuento AND IVA = @IVA AND Total = @Neto + @IVA)
    THROW 52303, 'Invoice discount, net VAT or total incorrect.', 1;
   IF NOT EXISTS (SELECT 1 FROM dbo.DetalleFactura WHERE FacturaId = @Factura AND ProductoId = @P1
       AND PrecioUnitario = 35.90 AND Subtotal = 35.90 AND DescuentoPorcentaje = @Porcentaje
       AND DescuentoMonto = CASE @Caso WHEN 1 THEN 0 WHEN 3 THEN 2.69 WHEN 4 THEN 35.90 ELSE 3.59 END
       AND SubtotalNeto = Subtotal - DescuentoMonto)
    THROW 52304, 'Persisted line discount incorrect.', 1;
   IF @Caso = 7 AND NOT EXISTS (SELECT 1 FROM dbo.DetalleFactura WHERE FacturaId = @Factura
       AND ProductoId = @P2 AND Cantidad = 2 AND DescuentoPorcentaje = 7.50 AND DescuentoMonto = 1.54 AND SubtotalNeto = 18.96)
    THROW 52305, 'Second line incorrect.', 1;
   IF NOT EXISTS (SELECT 1 FROM dbo.MovimientoCaja WHERE FacturaId = @Factura AND Monto = @Neto + @IVA)
    THROW 52306, 'Cash movement incorrect.', 1;
   IF (SELECT Stock FROM dbo.Producto WHERE ProductoId = @P1) <> 9
       OR (SELECT Stock FROM dbo.Producto WHERE ProductoId = @P2) <> CASE WHEN @Caso = 7 THEN 8 ELSE 10 END
    THROW 52307, 'Stock incorrect.', 1;
   IF NOT EXISTS (SELECT 1 FROM dbo.fn_ObtenerHistoricoVentas(NULL,NULL,NULL) WHERE Factura = @Factura
       AND Subtotal = @Bruto AND Descuento = @Descuento AND SubtotalNeto = @Neto AND Total = @Neto + @IVA)
    THROW 52308, 'History incorrect.', 1;
   IF NOT EXISTS (SELECT 1 FROM dbo.Bitacora_Transacciones WHERE TablaAfectada = 'Factura'
       AND IdentificadorRegistro = CONVERT(NVARCHAR(4000), @Factura)
       AND CONVERT(DECIMAL(19,2), JSON_VALUE(ValorNuevo, '$.DescuentoTotal')) = @Descuento)
    THROW 52309, 'Audit discount missing.', 1;
   ROLLBACK TRANSACTION;
  END;
  IF (SELECT COUNT_BIG(*) FROM dbo.Factura) <> @Facturas
      OR (SELECT COUNT_BIG(*) FROM dbo.DetalleFactura) <> @Detalles
      OR (SELECT COUNT_BIG(*) FROM dbo.MovimientoCaja) <> @Caja
      OR (SELECT COUNT_BIG(*) FROM dbo.Bitacora_Transacciones) <> @Auditoria
      OR EXISTS (SELECT ProductoId, Stock FROM #StockDescuentos EXCEPT SELECT ProductoId, Stock FROM dbo.Producto)
   THROW 52310, 'Rollback left partial sale, cash, audit or stock.', 1;
  PRINT CONCAT('OK: discount case ', @Caso);
  SET @Caso += 1;
 END;
 -- NOT NULL is enforced by the TVP before procedure execution.
 BEGIN TRY
  INSERT @Detalle VALUES (@P1, 1, NULL);
  THROW 52311, 'NULL discount accepted.', 1;
 END TRY BEGIN CATCH
  IF ERROR_NUMBER() <> 515 THROW;
 END CATCH;
 DROP TABLE #StockDescuentos;
END TRY BEGIN CATCH
 IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
 DROP TABLE IF EXISTS #StockDescuentos;
 THROW;
END CATCH;
GO
