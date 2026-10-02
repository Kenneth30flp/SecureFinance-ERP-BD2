USE [SecureFinanceERP];
GO
-- Temporary test database only. Own fixtures are removed at the end.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @@TRANCOUNT <> 0 THROW 52600, 'Run without an outer transaction.', 1;
DECLARE @Tag NVARCHAR(16) = LEFT(REPLACE(CONVERT(NVARCHAR(36), NEWID()), '-', ''), 16),
 @Admin INT, @Cashier INT, @Auditor INT, @Client INT, @Product INT, @Code INT,
 @Name NVARCHAR(50), @Mail NVARCHAR(254), @Factura INT, @Actor INT,
 @Detalle dbo.TipoDetalleVentaDescuento, @Caso INT = 1, @Error INT, @Expected INT,
 @Discount DECIMAL(5,2), @Motivo NVARCHAR(80), @Quantity INT;
BEGIN TRY
 BEGIN TRANSACTION;
 SET @Name = N'ops_admin_' + @Tag; SET @Mail = @Name + N'@example.invalid';
 EXEC @Code = dbo.sp_RegistrarUsuario @Name, @Mail, N'Test_Operations_2026!', N'Operations test', @Admin OUTPUT;
 IF @Code <> 0 THROW 52601, 'Could not create admin fixture.', 1;
 SET @Name = N'ops_cashier_' + @Tag; SET @Mail = @Name + N'@example.invalid';
 EXEC @Code = dbo.sp_RegistrarUsuario @Name, @Mail, N'Test_Operations_2026!', N'Operations test', @Cashier OUTPUT;
 IF @Code <> 0 THROW 52601, 'Could not create cashier fixture.', 1;
 SET @Name = N'ops_auditor_' + @Tag; SET @Mail = @Name + N'@example.invalid';
 EXEC @Code = dbo.sp_RegistrarUsuario @Name, @Mail, N'Test_Operations_2026!', N'Operations test', @Auditor OUTPUT;
 IF @Code <> 0 THROW 52601, 'Could not create auditor fixture.', 1;
 INSERT dbo.Usuario_Rol (UsuarioId, RolId)
 SELECT @Admin, RolId FROM dbo.Rol WHERE Nombre = N'Administrador'
 UNION ALL SELECT @Cashier, RolId FROM dbo.Rol WHERE Nombre = N'Cajero'
 UNION ALL SELECT @Auditor, RolId FROM dbo.Rol WHERE Nombre = N'Auditor';
 INSERT dbo.Cliente (NIT, Nombre) VALUES (@Tag, N'Operations test'); SET @Client = SCOPE_IDENTITY();
 INSERT dbo.Producto (Codigo, Descripcion, Precio, Stock) VALUES (@Tag, N'Cable HDMI', 35.90, 10); SET @Product = SCOPE_IDENTITY();
 COMMIT;
 IF NOT EXISTS (SELECT 1 FROM dbo.fn_ObtenerPoliticaVenta(@Admin) WHERE PuedeVender = 1 AND MaxDescuento = 100)
  OR NOT EXISTS (SELECT 1 FROM dbo.fn_ObtenerPoliticaVenta(@Cashier) WHERE PuedeVender = 1 AND MaxDescuento = 10)
  OR NOT EXISTS (SELECT 1 FROM dbo.fn_ObtenerPoliticaVenta(@Auditor) WHERE PuedeVender = 0)
  THROW 52602, 'Role policy incorrect.', 1;
 DECLARE @F BIGINT = (SELECT COUNT_BIG(*) FROM dbo.Factura),
  @D BIGINT = (SELECT COUNT_BIG(*) FROM dbo.DetalleFactura),
  @M BIGINT = (SELECT COUNT_BIG(*) FROM dbo.MovimientoCaja),
  @A BIGINT = (SELECT COUNT_BIG(*) FROM dbo.Bitacora_Transacciones);
 WHILE @Caso <= 14
 BEGIN
  DELETE @Detalle;
  SELECT @Error = NULL, @Expected = NULL, @Factura = NULL, @Motivo = NULL, @Quantity = 1;
  SET @Actor = CASE WHEN @Caso IN (7,8,11,12,14) THEN @Admin WHEN @Caso = 9 THEN @Auditor ELSE @Cashier END;
  SET @Discount = CASE @Caso WHEN 1 THEN 0 WHEN 2 THEN 10 WHEN 3 THEN 7.50 WHEN 4 THEN 10.01
    WHEN 5 THEN 25 WHEN 6 THEN 100 WHEN 7 THEN 100 WHEN 8 THEN 25 WHEN 9 THEN 0 WHEN 10 THEN 0 ELSE 25 END;
  IF @Caso IN (4,5,6,14) SET @Expected = 52012;
  IF @Caso IN (9,10) SET @Expected = 52013;
  IF @Caso = 11 BEGIN SET @Motivo = N'Not an approved reason'; SET @Expected = 52014; END;
  IF @Caso IN (8,12,13) BEGIN SET @Motivo = N'Cliente frecuente'; SET @Quantity = 2; END;
  INSERT @Detalle VALUES (@Product, @Quantity, @Discount);
  BEGIN TRANSACTION;
  IF @Caso = 10 DELETE dbo.Usuario_Rol WHERE UsuarioId = @Cashier;
  IF @Caso = 12
  BEGIN
   ALTER TABLE dbo.MovimientoCaja WITH NOCHECK ADD CONSTRAINT CK_Operations_Rollback CHECK (Monto < 0);
   SET @Expected = 547;
  END;
  IF @Caso = 13 INSERT dbo.Usuario_Rol (UsuarioId, RolId) SELECT @Cashier, RolId FROM dbo.Rol WHERE Nombre = N'Administrador';
  IF @Caso = 14
  BEGIN
   DELETE dbo.Usuario_Rol WHERE UsuarioId = @Admin;
   INSERT dbo.Usuario_Rol (UsuarioId, RolId) SELECT @Admin, RolId FROM dbo.Rol WHERE Nombre = N'Cajero';
  END;
  BEGIN TRY
   EXEC dbo.sp_ProcesarVentaTransaccional @Client, @Actor, @Detalle, @Factura OUTPUT, @Motivo;
  END TRY BEGIN CATCH SET @Error = ERROR_NUMBER(); END CATCH;
  IF @Expected IS NOT NULL
  BEGIN
   IF @Error IS NULL OR @Error <> @Expected OR @Factura IS NOT NULL OR @@TRANCOUNT <> 0
    THROW 52603, 'Policy/rollback expected error missing.', 1;
  END
  ELSE
  BEGIN
   IF @Error IS NOT NULL OR @Factura IS NULL THROW 52604, 'Authorized sale rejected.', 1;
   DECLARE @Amount DECIMAL(19,2) = CASE @Caso WHEN 1 THEN 0 WHEN 2 THEN 3.59 WHEN 3 THEN 2.69 WHEN 7 THEN 35.90 ELSE 17.95 END;
   IF NOT EXISTS (SELECT 1 FROM dbo.Factura WHERE FacturaId = @Factura AND DescuentoTotal = @Amount
     AND Subtotal = 35.90 * @Quantity AND (MotivoDescuento = @Motivo OR (MotivoDescuento IS NULL AND @Motivo IS NULL)))
    THROW 52605, 'Persisted reason or amounts incorrect.', 1;
   IF @Caso IN (8,13) AND NOT EXISTS (SELECT 1 FROM dbo.Factura WHERE FacturaId = @Factura AND Total = 60.31 AND IVA = 6.46)
    THROW 52606, 'Confirmation control example incorrect.', 1;
   IF @Motivo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Bitacora_Transacciones
     WHERE TablaAfectada = N'Factura' AND IdentificadorRegistro = CONVERT(NVARCHAR(4000), @Factura)
       AND JSON_VALUE(ValorNuevo, '$.MotivoDescuento') = @Motivo
       AND CONVERT(DECIMAL(19,2), JSON_VALUE(ValorNuevo, '$.DescuentoTotal')) = @Amount)
    THROW 52607, 'Reason/discount audit missing.', 1;
   ROLLBACK;
  END;
  IF (SELECT COUNT_BIG(*) FROM dbo.Factura) <> @F OR (SELECT COUNT_BIG(*) FROM dbo.DetalleFactura) <> @D
    OR (SELECT COUNT_BIG(*) FROM dbo.MovimientoCaja) <> @M OR (SELECT COUNT_BIG(*) FROM dbo.Bitacora_Transacciones) <> @A
    OR (SELECT Stock FROM dbo.Producto WHERE ProductoId = @Product) <> 10
   THROW 52608, 'Partial stock, sale, cash or audit after rollback.', 1;
  PRINT CONCAT('OK: Operations Desk policy case ', @Caso);
  SET @Caso += 1;
 END;
 DELETE dbo.Usuario_Rol WHERE UsuarioId IN (@Admin, @Cashier, @Auditor);
 DELETE dbo.Usuario WHERE UsuarioId IN (@Admin, @Cashier, @Auditor);
 DELETE dbo.Cliente WHERE ClienteId = @Client;
 DELETE dbo.Producto WHERE ProductoId = @Product;
 PRINT 'OK: Operations Desk role policy, reason, audit and ACID.';
END TRY BEGIN CATCH
 IF XACT_STATE() <> 0 ROLLBACK;
 THROW;
END CATCH;
GO
