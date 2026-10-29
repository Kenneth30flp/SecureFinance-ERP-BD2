-- Pruebas SQL reales PREPARADAS, NO ejecutadas. Requieren autorizacion y apertura global
-- SEPARADA mediante el procedimiento original. Este archivo JAMAS abre/habilita inventario.
SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'SecureFinanceERP_Lab_Dylan' OR DATALENGTH(DB_NAME())<>DATALENGTH(N'SecureFinanceERP_Lab_Dylan') OR @@TRANCOUNT<>0
 THROW 58000,'Prueba exclusiva del laboratorio Dylan sin transaccion previa.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.ConfiguracionInventario WHERE ConfiguracionId=1 AND Habilitado=1 AND IntegracionVersion=2 AND AperturaId IS NOT NULL)
 THROW 58000,'Requiere apertura/habilitacion global previamente autorizada. No se realiza automaticamente.',1;
DECLARE @Actor INT=TRY_CONVERT(INT,SESSION_CONTEXT(N'P3_BOD.TestActor')),
 @P INT=(SELECT ProductoId FROM dbo.Producto WHERE Codigo=N'P3BOD-QA-100'),
 @P0 INT=(SELECT ProductoId FROM dbo.Producto WHERE Codigo=N'P3BOD-QA-COST0'),
 @O INT=(SELECT CentralId FROM dbo.P3_BOD_Configuracion WHERE ConfiguracionId=1),@D INT,@Proveedor INT,
 @Op UNIQUEIDENTIFIER=NEWID(),@Costo DECIMAL(12,2),@V BINARY(8),@T INT,@E INT;
SELECT @D=MIN(BodegaId) FROM dbo.P3_BOD_Bodega WHERE Activo=1 AND BodegaId<>@O;
SELECT @Proveedor=ProveedorId,@Costo=PrecioCosto FROM dbo.Producto WHERE ProductoId=@P AND Stock=100;
IF @Proveedor IS NULL OR @D IS NULL OR @Costo<>20.00 OR @Costo IS NULL
 OR NOT EXISTS(SELECT 1 FROM dbo.Producto WHERE ProductoId=@P0 AND Stock=0 AND PrecioCosto IS NULL)
 OR SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NOT NULL THROW 58000,'Requiere fixture 100@20 y stock cero limpios, y contexto raiz disponible.',1;
EXEC dbo.P3_BOD_Autorizar @Actor,N'INVENTARIO_REGISTRAR';
EXEC dbo.sp_ParteII_ValidarPermiso @Actor,N'INVENTARIO_AJUSTAR';
BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.P3_BOD_RegistrarCompra @Actor,@Op,@D,@P,@Proveedor,25,N'QA compra bodega',N'QA recepcion ponderada',30.00;
 DECLARE @ReciboOriginal NVARCHAR(MAX)=(SELECT Respuesta FROM dbo.P3_BOD_Operacion WHERE OperacionId=@Op);
 EXEC dbo.P3_BOD_RegistrarCompra @Actor,@Op,@D,@P,@Proveedor,25,N'QA compra bodega',N'QA recepcion ponderada',30.00;
 IF NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE ProductoId=@P AND Stock=125 AND StockLocal=125 AND Transito=0 AND Diferencia=0)
  OR NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Stock WHERE ProductoId=@P AND BodegaId=@D AND Cantidad=25)
  OR (SELECT COUNT(*) FROM dbo.P3_BOD_Ledger WHERE OperacionId=@Op)<>1
  OR (SELECT PrecioCosto FROM dbo.Producto WHERE ProductoId=@P)<>22.00 THROW 58100,'100@20 + 25@30 no resulto en 125@22, o replay duplico efectos.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.RecepcionCompra r JOIN dbo.DetalleRecepcionCompra d ON d.RecepcionId=r.RecepcionId
  WHERE r.OperacionId=@Op AND d.Cantidad=25 AND d.CostoUnitario=30.00) THROW 58100,'Se perdio el costo unitario documental original.',1;
 IF @ReciboOriginal IS NULL OR ISNULL(JSON_VALUE(@ReciboOriginal,'$.CostoPromedio'),N'')<>'22.00'
  OR ISNULL(JSON_VALUE(@ReciboOriginal,'$.CostoUnitario'),N'')<>'30.00'
  OR ISNULL(JSON_VALUE(@ReciboOriginal,'$.PoliticaCosto'),N'')<>'PONDERADO'
  OR NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Operacion WHERE OperacionId=@Op AND CONVERT(VARBINARY(MAX),Respuesta)=CONVERT(VARBINARY(MAX),@ReciboOriginal)) THROW 58100,'Recibo ponderado o replay inconsistente.',1;
 IF (SELECT COUNT(*) FROM dbo.Bitacora_Transacciones WHERE TablaAfectada=N'Producto' AND Operacion='UPDATE'
  AND OperacionId=@Op AND ActorUsuarioId=@Actor AND Motivo=N'QA recepcion ponderada'
  AND TRY_CONVERT(DECIMAL(12,2),JSON_VALUE(ValorAnterior,'$.PrecioCosto'))=20.00 AND TRY_CONVERT(DECIMAL(12,2),JSON_VALUE(ValorNuevo,'$.PrecioCosto'))=22.00)<>1
  THROW 58100,'El cambio de costo no tiene una unica auditoria DML con actor y operacion.',1;
 IF SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NOT NULL THROW 58100,'Compra dejo contexto en conexion.',1;
 ROLLBACK;
 PRINT 'PASS 100@20 + 25@30 = 125@22, documento 30 y replay unico (solo si se ejecuta manualmente).';
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;

-- Casos de valoracion independientes; todos se revierten y no habilitan inventario.
DECLARE @CasoCosto INT=1,@Entrada DECIMAL(19,2),@Esperado DECIMAL(12,2);
WHILE @CasoCosto<=7
BEGIN
 SET @Op=NEWID(); SET @E=NULL;
 BEGIN TRY
  BEGIN TRANSACTION;
  IF @CasoCosto=1
  BEGIN
   EXEC dbo.P3_BOD_RegistrarCompra @Actor,@Op,@D,@P,@Proveedor,25,N'QA sin costo',N'QA sin promedio',NULL;
   IF (SELECT PrecioCosto FROM dbo.Producto WHERE ProductoId=@P)<>20.00
    OR NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Operacion WHERE OperacionId=@Op AND JSON_VALUE(Respuesta,'$.CostoPromedio') IS NULL
     AND JSON_VALUE(Respuesta,'$.CostoPromedioAplicado')='false' AND JSON_VALUE(Respuesta,'$.PoliticaCosto')='SIN_COSTO_RECEPCION')
    THROW 58100,'Costo desconocido se valoro como cero o como promedio.',1;
  END;
  IF @CasoCosto=2
  BEGIN
   EXEC dbo.P3_BOD_RegistrarCompra @Actor,@Op,@D,@P0,@Proveedor,25,N'QA costo inicial',N'QA stock cero',30.00;
   IF NOT EXISTS(SELECT 1 FROM dbo.Producto WHERE ProductoId=@P0 AND Stock=25 AND PrecioCosto=30.00)
    OR NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Operacion WHERE OperacionId=@Op AND JSON_VALUE(Respuesta,'$.PoliticaCosto')='INICIAL')
    THROW 58100,'Stock cero no adopto costo conocido.',1;
  END;
  IF @CasoCosto IN(3,4)
  BEGIN
   SET @Entrada=CASE WHEN @CasoCosto=3 THEN 20.50 ELSE 20.51 END;
   SET @Esperado=CASE WHEN @CasoCosto=3 THEN 20.00 ELSE 20.01 END;
   EXEC dbo.P3_BOD_RegistrarCompra @Actor,@Op,@D,@P,@Proveedor,1,N'QA redondeo',N'QA centavo exacto',@Entrada;
   IF NOT EXISTS(SELECT 1 FROM dbo.Producto WHERE ProductoId=@P AND Stock=101 AND PrecioCosto=@Esperado) THROW 58100,'Redondeo cerca de medio centavo incorrecto.',1;
  END;
  IF @CasoCosto=5
  BEGIN
   UPDATE dbo.Producto SET PrecioCosto=NULL WHERE ProductoId=@P; -- setup sintetico, solo dentro de rollback.
   EXEC dbo.P3_BOD_RegistrarCompra @Actor,@Op,@D,@P,@Proveedor,25,N'QA costo previo nulo',N'QA rechazo valoracion',30.00;
  END;
  IF @CasoCosto=6 EXEC dbo.P3_BOD_RegistrarCompra @Actor,@Op,@D,@P0,@Proveedor,1,N'QA costo inicial overflow',N'QA rechazo rango',10000000000.00;
  IF @CasoCosto=7 EXEC dbo.P3_BOD_RegistrarCompra @Actor,@Op,@D,@P,@Proveedor,1,N'QA promedio overflow',N'QA rechazo rango',99999999999999999.99;
  IF XACT_STATE()<>0 ROLLBACK;
 END TRY
 BEGIN CATCH
  SET @E=ERROR_NUMBER();
  IF XACT_STATE()<>0 ROLLBACK;
 END CATCH;
 IF (@CasoCosto<=4 AND @E IS NOT NULL) OR (@CasoCosto>=5 AND (@E IS NULL OR @E<>58008)) THROW 58100,'Escenario de costo no cumplio su resultado esperado.',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Producto WHERE ProductoId=@P AND Stock=100 AND PrecioCosto=20.00)
  OR EXISTS(SELECT 1 FROM dbo.P3_BOD_Operacion WHERE OperacionId=@Op) THROW 58100,'Escenario de costo no revirtio completamente.',1;
 SET @CasoCosto+=1;
END;

-- El global tiene 100 pero central solo 95: salida global de 96 debe revertirse por espejo local.
DECLARE @Out TABLE(Respuesta NVARCHAR(MAX));
SET @E=NULL; SET @Op=NEWID();
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT @Out EXEC dbo.sp_TransferirStockBodegas @Actor,@Op,@P,@O,@D,5,N'QA transito';
 SELECT @T=TRY_CONVERT(INT,JSON_VALUE(Respuesta,'$.TransferenciaId')) FROM @Out;
 SELECT @V=Version FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=@T;
 SET @Op=NEWID();
 EXEC dbo.P3_BOD_AvanzarTransferencia @Actor,@Op,@T,'DESPACHAR',@V,N'QA transito';
 SELECT @V=Version FROM dbo.Producto WHERE ProductoId=@P;
 SET @Op=NEWID();
 EXEC dbo.sp_RegistrarMovimientoKardex @ProductoId=@P,@TipoMovimiento='AJUSTE_EGRESO',@Cantidad=96,
  @ActorUsuarioId=@Actor,@DocumentoRespaldo=N'QA no consumir transito',@OperacionId=@Op,@LineaOperacion=1,
  @Motivo=N'QA rechazo local atomico',@VersionEsperada=@V,@DevolverResultado=0;
 IF XACT_STATE()<>0 ROLLBACK;
END TRY
BEGIN CATCH
 SET @E=ERROR_NUMBER();
 IF XACT_STATE()<>0 ROLLBACK;
END CATCH;
IF @E IS NULL OR @E<>58005 THROW 58100,'El espejo no rechazo salida superior al disponible local.',1;
IF NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE ProductoId=@P AND Stock=100 AND StockLocal=100 AND Transito=0 AND Diferencia=0)
 OR EXISTS(SELECT 1 FROM dbo.Kardex_Inventario WHERE OperacionId=@Op) THROW 58100,'Rechazo local no revirtio la transaccion completa.',1;

-- Contexto ajeno: rechazar sin sobreescribirlo, y el propietario lo limpia explicitamente.
SET @E=NULL; SET @Op=NEWID();
EXEC sys.sp_set_session_context @key=N'P3_BOD.BodegaId',@value=@O;
BEGIN TRY
 EXEC dbo.P3_BOD_RegistrarCompra @Actor,@Op,@D,@P,@Proveedor,2,N'QA contexto',N'QA contexto',NULL;
END TRY
BEGIN CATCH
 SET @E=ERROR_NUMBER();
END CATCH;
DECLARE @Conservado INT=TRY_CONVERT(INT,SESSION_CONTEXT(N'P3_BOD.BodegaId'));
EXEC sys.sp_set_session_context @key=N'P3_BOD.BodegaId',@value=NULL;
IF @E IS NULL OR @E<>58003 OR @Conservado<>@O THROW 58100,'Wrapper sobreescribio contexto ajeno.',1;
PRINT 'PASS rechazo local atomico y propiedad del contexto (ejecucion manual, no concurrencia).';
