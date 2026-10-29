-- PREPARED ONLY / REAL SQL NOT RUN. DBA in an already prepared Dylan lab, NOT migration installer.
-- Every scenario builds private synthetic data and rolls back. Errors may roll back the WHOLE transaction.
-- Run as DBA; actor is an existing active Administrator with the documented permissions, no passwords.
-- Client/product INSERTs and overdue/inactive flags are synthetic fixtures. NEVER insert a Factura here:
-- P3_COT_Crear -> P3_CRE_ConvertirCotizacionCredito -> the extended 43 engine creates it.
SET NOCOUNT ON; SET XACT_ABORT ON;
SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON;
SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME() <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT<>0
 THROW 57000,'Solo laboratorio exacto Dylan, sin transaccion previa; no ejecutar sobre principal.',1;
IF SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NOT NULL THROW 57009,'Contexto de prueba ocupado; no se modifica.',1;
IF OBJECT_ID('dbo.P3_CRE_ConvertirCotizacionCredito','P') IS NULL
 OR NOT EXISTS(SELECT 1 FROM dbo.ConfiguracionInventario WHERE ConfiguracionId=1 AND Habilitado=1 AND IntegracionVersion=2 AND AperturaId IS NOT NULL)
 THROW 57000,'Requiere 70-77 revisados y apertura Kardex aprobada en laboratorio.',1;
DECLARE @Actor INT=(SELECT MIN(u.UsuarioId) FROM dbo.Usuario u JOIN dbo.Usuario_Rol ur ON ur.UsuarioId=u.UsuarioId
 JOIN dbo.Rol r ON r.RolId=ur.RolId WHERE u.Activo=1 AND r.Activo=1 AND r.Nombre=N'Administrador');
IF @Actor IS NULL THROW 57000,'Prepare actor Administrador sin modificar credenciales.',1;
DECLARE @Scenario INT=1,@Expected INT,@Caught INT,@Cliente INT,@Producto INT,@Cotizacion INT,@Factura INT,@Version BINARY(8),
 @Id UNIQUEIDENTIFIER,@PerfilOp UNIQUEIDENTIFIER,@CotOp UNIQUEIDENTIFIER,@VentaOp UNIQUEIDENTIFIER,@AbonoOp UNIQUEIDENTIFIER,
 @Vence DATETIME2(3),@Nit NVARCHAR(25),@Codigo NVARCHAR(40),@Limite DECIMAL(19,2),@Abono BIGINT,
 @PlazoSolicitud INT,@ContextoPrueba BIT,@Porcentaje DECIMAL(5,2);
WHILE @Scenario<=24
BEGIN
 SET @Expected=NULL; SET @Caught=NULL; SET @Factura=NULL; SET @Abono=NULL; SET @PlazoSolicitud=30; SET @ContextoPrueba=0;
 SELECT @Id=NEWID(),@PerfilOp=NEWID(),@CotOp=NEWID(),@VentaOp=NEWID(),@AbonoOp=NEWID();
 SET @Nit=N'CRE'+LEFT(REPLACE(CONVERT(NVARCHAR(36),@Id),'-',''),20);
 SET @Codigo=N'P3-CRE-'+REPLACE(CONVERT(NVARCHAR(36),@Id),'-','');
 BEGIN TRY
  BEGIN TRANSACTION;
  INSERT dbo.Cliente(NIT,Nombre) VALUES(@Nit,N'Sintetico P3 CRE rollback');
  SET @Cliente=CONVERT(INT,SCOPE_IDENTITY());
  -- New zero-stock fixture; actual stock enters ONLY through the central Kardex API.
  INSERT dbo.Producto(Codigo,Descripcion,Precio,Stock) VALUES(@Codigo,N'Sintetico P3 CRE rollback',1785.71,0);
  SET @Producto=CONVERT(INT,SCOPE_IDENTITY());
  SELECT @Version=Version FROM dbo.Producto WHERE ProductoId=@Producto;
  EXEC dbo.sp_RegistrarMovimientoKardex @ProductoId=@Producto,@TipoMovimiento='AJUSTE_INGRESO',@Cantidad=1,
   @ActorUsuarioId=@Actor,@DocumentoRespaldo=N'P3_CRE_PRUEBA_ROLLBACK',@OperacionId=@Id,@LineaOperacion=1,
   @Motivo=N'Fixture sintetico aislado',@VersionEsperada=@Version,@DevolverResultado=0;
  SET @Limite=CASE WHEN @Scenario=7 THEN 1000 ELSE 5000 END;
  EXEC dbo.P3_CRE_AdministrarCredito @Actor,@Cliente,1,@Limite,30,NULL,N'Prueba sintetica',@PerfilOp;
  IF (SELECT Limite FROM dbo.Credito_Cliente WHERE ClienteId=@Cliente)<>@Limite
   OR EXISTS(SELECT 1 FROM dbo.P3_CRE_Cuenta WHERE ClienteId=@Cliente) THROW 57999,'Disponible inicial no coincide.',1;
  -- Identical authorization replay must succeed even though the row now has a version.
  EXEC dbo.P3_CRE_AdministrarCredito @Actor,@Cliente,1,@Limite,30,NULL,N'Prueba sintetica',@PerfilOp;
  DECLARE @Detalle dbo.TipoDetalleVentaDescuento;
  SET @Porcentaje=CASE WHEN @Scenario IN(22,23) THEN 100 ELSE 0 END;
  DELETE @Detalle; INSERT @Detalle VALUES(@Producto,1,@Porcentaje);
  SET @Vence=DATEADD(DAY,1,SYSUTCDATETIME());
  IF @Scenario=9 SET @Vence=DATEADD(SECOND,3,SYSUTCDATETIME());
  EXEC dbo.P3_COT_Crear @Actor,@Cliente,@Vence,@Detalle,@CotOp,N'Fixture credito rollback';
  SELECT @Cotizacion=CotizacionId FROM dbo.P3_COT_Cotizacion WHERE OperacionId=@CotOp;
  IF NOT EXISTS(SELECT 1 FROM dbo.P3_COT_Cotizacion WHERE CotizacionId=@Cotizacion AND Subtotal=1785.71
    AND IVA=CASE WHEN @Porcentaje=100 THEN 0 ELSE 214.29 END AND Total=CASE WHEN @Porcentaje=100 THEN 0 ELSE 2000 END)
   OR NOT EXISTS(SELECT 1 FROM dbo.P3_COT_Detalle WHERE CotizacionId=@Cotizacion AND ProductoId=@Producto AND PrecioUnitario=1785.71)
   THROW 57999,'Pacto SQL esperado 1785.71 + IVA 214.29 = 2000.00.',1;
  IF @Scenario=7 SET @Expected=57005;
  IF @Scenario=22 SET @Expected=57005; -- Credit must never finance a zero total.
  IF @Scenario=23
  BEGIN
   -- Exercise DEFAULT cash UC09: original 43 allows a zero-total sale with an authorized 100% discount.
   EXEC dbo.sp_ConvertirCotizacionAFactura @CotizacionId=@Cotizacion,@ActorUsuarioId=@Actor,@OperacionId=@VentaOp;
   SELECT @Factura=FacturaId FROM dbo.P3_COT_Cotizacion WHERE CotizacionId=@Cotizacion;
   IF @Factura IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.Factura WHERE FacturaId=@Factura AND Total=0 AND IVA=0)
    OR (SELECT COUNT(*) FROM dbo.MovimientoCaja WHERE FacturaId=@Factura AND Monto=0)<>1
    OR EXISTS(SELECT 1 FROM dbo.P3_CRE_Cuenta WHERE FacturaId=@Factura)
    THROW 57999,'Default contado cero incompatible con 43.',1;
   EXEC dbo.sp_ConvertirCotizacionAFactura @CotizacionId=@Cotizacion,@ActorUsuarioId=@Actor,@OperacionId=@VentaOp;
   IF (SELECT COUNT(*) FROM dbo.MovimientoCaja WHERE FacturaId=@Factura)<>1 OR (SELECT Stock FROM dbo.Producto WHERE ProductoId=@Producto)<>0
    THROW 57999,'Replay contado cero duplico caja o stock.',1;
   ROLLBACK;
   IF EXISTS(SELECT 1 FROM dbo.Cliente WHERE NIT=@Nit) THROW 57999,'Rollback contado dejo fixture.',1;
   SELECT @Scenario Escenario,N'PASS (solo si este script se ejecuto realmente)' Resultado;
   SET @Scenario+=1; CONTINUE;
  END;
  IF @Scenario=8
  BEGIN
   SET @Id=NEWID(); EXEC dbo.P3_COT_Cancelar @Actor,@Cotizacion,@Id,N'Prueba cancelacion'; SET @Expected=54903;
  END;
  IF @Scenario=9 BEGIN WAITFOR DELAY '00:00:04'; SET @Expected=54910; END;
  IF @Scenario=15
  BEGIN
   SET @Id=NEWID(); SELECT @Version=Version FROM dbo.Credito_Cliente WHERE ClienteId=@Cliente;
   EXEC dbo.P3_CRE_AdministrarCredito @Actor,@Cliente,0,5000,30,@Version,N'Inactivar credito de fixture',@Id;
   SET @Expected=57005;
  END;
  IF @Scenario=16
  BEGIN
   UPDATE dbo.Cliente SET Activo=0 WHERE ClienteId=@Cliente; -- Only this synthetic client.
   SET @Expected=57004;
  END;
  IF @Scenario=19 BEGIN SET @PlazoSolicitud=31; SET @Expected=57005; END;
  IF @Scenario=21
  BEGIN
   EXEC sys.sp_set_session_context @key=N'P3_BOD.BodegaId',@value=999;
   SET @ContextoPrueba=1; SET @Expected=57009;
  END;
  IF @Scenario=13
  BEGIN
   SET @Id=NEWID(); SELECT @Version=Version FROM dbo.Producto WHERE ProductoId=@Producto;
   EXEC dbo.sp_RegistrarMovimientoKardex @ProductoId=@Producto,@TipoMovimiento='AJUSTE_EGRESO',@Cantidad=1,
    @ActorUsuarioId=@Actor,@DocumentoRespaldo=N'P3_CRE_PRUEBA_ROLLBACK',@OperacionId=@Id,@LineaOperacion=1,
    @Motivo=N'Fixture stock insuficiente',@VersionEsperada=@Version,@DevolverResultado=0;
   SET @Expected=52010;
  END;
  EXEC dbo.P3_CRE_ConvertirCotizacionCredito @Actor,@Cotizacion,@VentaOp,@PlazoSolicitud,3,NULL;
  SELECT @Factura=FacturaId FROM dbo.P3_COT_Cotizacion WHERE CotizacionId=@Cotizacion;
  IF @Factura IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.P3_CRE_Cuenta WHERE FacturaId=@Factura AND ClienteId=@Cliente AND Total=2000 AND Saldo=2000 AND NumeroCuotas=3 AND PlazoDias=30)
   THROW 57999,'Venta y plan esperados 2000.00, 30 dias, 3 cuotas.',1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Factura WHERE FacturaId=@Factura AND Subtotal=1785.71 AND IVA=214.29 AND Total=2000)
   OR EXISTS(SELECT ProductoId,Cantidad,PrecioUnitario,DescuentoPorcentaje,Subtotal,DescuentoMonto FROM dbo.DetalleFactura WHERE FacturaId=@Factura
    EXCEPT SELECT ProductoId,Cantidad,PrecioUnitario,DescuentoPorcentaje,Subtotal,DescuentoMonto FROM dbo.P3_COT_Detalle WHERE CotizacionId=@Cotizacion)
   THROW 57999,'Factura no conserva los importes y lineas pactados.',1;
  IF EXISTS(SELECT 1 FROM dbo.MovimientoCaja WHERE FacturaId=@Factura) THROW 57999,'Credito no debe generar caja de contado.',1;
  IF (SELECT SUM(Importe) FROM dbo.P3_CRE_Cuota WHERE FacturaId=@Factura)<>2000 THROW 57999,'Plan no concilia centavos.',1;
  IF (SELECT Limite FROM dbo.Credito_Cliente WHERE ClienteId=@Cliente)-(SELECT SUM(Saldo) FROM dbo.P3_CRE_Cuenta WHERE ClienteId=@Cliente)<>3000
   THROW 57999,'Disponible despues de venta debe ser 3000.',1;
  IF @Scenario=14
  BEGIN
   -- Age ONLY this rollback fixture to test computed overdue state without a scheduler.
   UPDATE dbo.P3_CRE_Cuota SET VenceEn=DATEADD(DAY,-1,SYSUTCDATETIME()) WHERE FacturaId=@Factura AND Numero=1;
   IF NOT EXISTS(SELECT 1 FROM dbo.P3_CRE_EstadoCuenta WHERE FacturaId=@Factura AND Estado='VENCIDA')
    THROW 57999,'Cuenta debe vencer por una cuota impaga.',1;
  END;
  IF @Scenario=12
  BEGIN
   SET @Expected=54803; EXEC dbo.P3_CRE_ConvertirCotizacionCredito @Actor,@Cotizacion,@VentaOp,30,2,NULL;
  END;
  IF @Scenario=20
  BEGIN SET @Expected=54803; EXEC dbo.P3_CRE_ConvertirCotizacionCredito @Actor,@Cotizacion,@VentaOp,29,3,NULL; END;
  IF @Scenario=24
  BEGIN
   SET @Expected=54803;
   EXEC dbo.sp_ConvertirCotizacionAFactura @CotizacionId=@Cotizacion,@ActorUsuarioId=@Actor,@OperacionId=@VentaOp;
  END;
  -- Conversion replay must not create another invoice or stock movement.
  EXEC dbo.P3_CRE_ConvertirCotizacionCredito @Actor,@Cotizacion,@VentaOp,30,3,NULL;
  IF (SELECT COUNT(*) FROM dbo.P3_CRE_Cuenta WHERE ClienteId=@Cliente)<>1 OR (SELECT Stock FROM dbo.Producto WHERE ProductoId=@Producto)<>0
   THROW 57999,'Conversion repetida duplico efectos.',1;
  IF @Scenario=10
  BEGIN
   SET @Expected=57003; SET @Id=NEWID();
   EXEC dbo.P3_CRE_AdministrarCredito @Actor,@Cliente,1,5000,30,0x0000000000000000,N'Version obsoleta',@Id;
  END;
  IF @Scenario=18
  BEGIN
   SET @Id=NEWID(); SELECT @Version=Version FROM dbo.Credito_Cliente WHERE ClienteId=@Cliente;
   SET @Expected=57005; EXEC dbo.P3_CRE_AdministrarCredito @Actor,@Cliente,1,1000,30,@Version,N'Limite inferior a deuda',@Id;
  END;
  IF @Scenario=17
  BEGIN
   SET @Id=NEWID(); SELECT @Version=Version FROM dbo.Credito_Cliente WHERE ClienteId=@Cliente;
   EXEC dbo.P3_CRE_AdministrarCredito @Actor,@Cliente,0,5000,30,@Version,N'Inactivar despues de venta',@Id;
   UPDATE dbo.Cliente SET Activo=0 WHERE ClienteId=@Cliente; -- Repayment must still work.
   EXEC dbo.P3_CRE_ConvertirCotizacionCredito @Actor,@Cotizacion,@VentaOp,30,3,NULL; -- Confirmed replay only.
  END;
  IF @Scenario IN(2,3,4,5)
  BEGIN
   SET @Expected=CASE WHEN @Scenario=2 THEN 57006 WHEN @Scenario IN(3,4) THEN 57002 ELSE 57004 END;
   DECLARE @Monto DECIMAL(19,2)=CASE @Scenario WHEN 2 THEN 2000.01 WHEN 3 THEN 0 WHEN 4 THEN -1 ELSE 500 END;
   DECLARE @OtroCliente INT=CASE WHEN @Scenario=5 THEN -1 ELSE @Cliente END;
   -- Wrong positive client exercises invoice ownership rather than just input validation.
   IF @Scenario=5
   BEGIN
    DECLARE @OtroNit NVARCHAR(25)=N'X'+@Nit;
    INSERT dbo.Cliente(NIT,Nombre) VALUES(@OtroNit,N'Sintetico otro cliente'); SET @OtroCliente=CONVERT(INT,SCOPE_IDENTITY());
    SET @Id=NEWID(); EXEC dbo.P3_CRE_AdministrarCredito @Actor,@OtroCliente,1,5000,30,NULL,N'Otro cliente',@Id;
   END;
   EXEC dbo.sp_RegistrarAbonoCliente @Actor,@OtroCliente,@Factura,@Monto,N'Prueba negativa',@AbonoOp;
  END;
  EXEC dbo.sp_RegistrarAbonoCliente @Actor,@Cliente,@Factura,500,N'Pago inicial',@AbonoOp;
  SELECT @Abono=AbonoId FROM dbo.Abono_Factura WHERE OperacionId=@AbonoOp;
  IF (SELECT Saldo FROM dbo.P3_CRE_Cuenta WHERE FacturaId=@Factura)<>1500 THROW 57999,'Saldo esperado 1500.',1;
  IF (SELECT Limite FROM dbo.Credito_Cliente WHERE ClienteId=@Cliente)-(SELECT SUM(Saldo) FROM dbo.P3_CRE_Cuenta WHERE ClienteId=@Cliente)<>3500
   THROW 57999,'Disponible despues de abono debe ser 3500.',1;
  IF (SELECT SUM(Abonado) FROM dbo.P3_CRE_Cuota WHERE FacturaId=@Factura)<>500 THROW 57999,'Cuotas no actualizadas.',1;
  IF (SELECT Abonado FROM dbo.P3_CRE_Cuota WHERE FacturaId=@Factura AND Numero=1)<>500 THROW 57999,'FIFO no aplicado.',1;
  IF @Scenario=14 AND NOT EXISTS(SELECT 1 FROM dbo.P3_CRE_EstadoCuota WHERE FacturaId=@Factura AND Numero=1 AND Estado='VENCIDA')
   THROW 57999,'Cuota vencida parcialmente abonada debe seguir vencida.',1;
  EXEC dbo.sp_RegistrarAbonoCliente @Actor,@Cliente,@Factura,500,N'Pago inicial',@AbonoOp;
  IF (SELECT COUNT(*) FROM dbo.P3_CRE_ReciboCaja WHERE AbonoId=@Abono)<>1 OR (SELECT Saldo FROM dbo.P3_CRE_Cuenta WHERE FacturaId=@Factura)<>1500
   THROW 57999,'Reintento duplico abono o recibo.',1;
  IF @Scenario=6
  BEGIN SET @Expected=57003; EXEC dbo.sp_RegistrarAbonoCliente @Actor,@Cliente,@Factura,501,N'Pago inicial',@AbonoOp; END;
  IF @Scenario=11
  BEGIN SET @Expected=57007; UPDATE dbo.P3_CRE_ReciboCaja SET Monto=Monto WHERE AbonoId=@Abono; END;
  SET @Id=NEWID(); EXEC dbo.sp_RegistrarAbonoCliente @Actor,@Cliente,@Factura,1500,N'Liquidacion',@Id;
  IF (SELECT Saldo FROM dbo.P3_CRE_Cuenta WHERE FacturaId=@Factura)<>0
   OR (SELECT Limite FROM dbo.Credito_Cliente WHERE ClienteId=@Cliente)-(SELECT SUM(Saldo) FROM dbo.P3_CRE_Cuenta WHERE ClienteId=@Cliente)<>5000
   OR EXISTS(SELECT 1 FROM dbo.P3_CRE_EstadoCuota WHERE FacturaId=@Factura AND Estado<>'PAGADA')
   THROW 57999,'Liquidacion no dejo saldo cero y disponible 5000.',1;
  EXEC dbo.sp_RegistrarAbonoCliente @Actor,@Cliente,@Factura,500,N'Pago inicial',@AbonoOp;
  IF (SELECT SaldoPosterior FROM dbo.Abono_Factura WHERE AbonoId=@Abono)<>1500
   OR (SELECT Saldo FROM dbo.P3_CRE_Cuenta WHERE FacturaId=@Factura)<>0
   OR (SELECT COUNT(*) FROM dbo.Abono_Factura WHERE FacturaId=@Factura)<>2
   THROW 57999,'Replay antiguo debe conservar recibo original sin reabrir deuda.',1;
  IF (SELECT SUM(r.Monto) FROM dbo.P3_CRE_ReciboCaja r JOIN dbo.Abono_Factura a ON a.AbonoId=r.AbonoId WHERE a.FacturaId=@Factura)<>2000
   OR EXISTS(SELECT 1 FROM dbo.MovimientoCaja WHERE FacturaId=@Factura)
   THROW 57999,'Efectivo de esta venta debe ser solo abonos 500 + 1500; deuda no es ingreso.',1;
  IF @Expected IS NOT NULL THROW 57999,'El escenario negativo no fue rechazado.',1;
  ROLLBACK;
 END TRY BEGIN CATCH
  SET @Caught=ERROR_NUMBER();
  IF XACT_STATE()<>0 ROLLBACK;
  IF @ContextoPrueba=1
  BEGIN
   IF SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NULL OR TRY_CONVERT(INT,SESSION_CONTEXT(N'P3_BOD.BodegaId'))<>999
    THROW 57999,'77 modifico un contexto ajeno.',1;
   EXEC sys.sp_set_session_context @key=N'P3_BOD.BodegaId',@value=NULL; -- The harness owns this fixture, not 77.
   SET @ContextoPrueba=0;
  END;
  IF @Expected IS NULL OR @Caught<>@Expected THROW;
 END CATCH;
 IF EXISTS(SELECT 1 FROM dbo.Cliente WHERE NIT=@Nit) OR EXISTS(SELECT 1 FROM dbo.SolicitudVentaERP WHERE OperacionId=@VentaOp)
  OR EXISTS(SELECT 1 FROM dbo.Abono_Factura WHERE OperacionId=@AbonoOp)
  THROW 57999,'Rollback dejo datos sinteticos persistidos.',1;
 SELECT @Scenario Escenario,N'PASS (solo si este script se ejecuto realmente)' Resultado,@Caught CodigoEsperado;
 SET @Scenario+=1;
END;
