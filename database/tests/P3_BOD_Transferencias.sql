-- Prueba SQL REAL preparada, NO ejecutada. Exige fixture separado e instalacion 80..89.
-- Cada escenario revierte su transaccion; ningun dato se presenta como evidencia ejecutada.
SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'SecureFinanceERP_Lab_Dylan' OR DATALENGTH(DB_NAME())<>DATALENGTH(N'SecureFinanceERP_Lab_Dylan') OR @@TRANCOUNT<>0
 THROW 58000,'Prueba exclusiva del laboratorio Dylan sin transaccion previa.',1;
DECLARE @Actor INT=TRY_CONVERT(INT,SESSION_CONTEXT(N'P3_BOD.TestActor')),
 @P INT=(SELECT ProductoId FROM dbo.Producto WHERE Codigo=N'P3BOD-QA-100'),
 @O INT=(SELECT CentralId FROM dbo.P3_BOD_Configuracion WHERE ConfiguracionId=1),@D INT,
 @Id INT,@V BINARY(8),@Op UNIQUEIDENTIFIER=NEWID(),@Desp UNIQUEIDENTIFIER=NEWID(),@Rec UNIQUEIDENTIFIER=NEWID();
SELECT @D=MIN(BodegaId) FROM dbo.P3_BOD_Bodega WHERE Activo=1 AND BodegaId<>@O;
EXEC dbo.P3_BOD_Autorizar @Actor,N'TRANSFERENCIAS_CREAR';
EXEC dbo.P3_BOD_Autorizar @Actor,N'TRANSFERENCIAS_DESPACHAR';
EXEC dbo.P3_BOD_Autorizar @Actor,N'TRANSFERENCIAS_RECIBIR';
IF @P IS NULL OR @D IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.Producto WHERE ProductoId=@P AND Stock=100)
 OR NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Stock WHERE ProductoId=@P AND BodegaId=@O AND Cantidad=100)
 OR EXISTS(SELECT 1 FROM dbo.P3_BOD_Transferencia WHERE ProductoId=@P)
 THROW 58000,'Requiere fixture 100 limpio y snapshot inicial instalado.',1;
DECLARE @Out TABLE(Respuesta NVARCHAR(MAX));
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT @Out EXEC dbo.sp_TransferirStockBodegas @Actor,@Op,@P,@O,@D,5,N'QA propuesta';
 SELECT @Id=TRY_CONVERT(INT,JSON_VALUE(Respuesta,'$.TransferenciaId')) FROM @Out;
 IF @Id IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Stock WHERE ProductoId=@P AND BodegaId=@O AND Cantidad=100)
  OR EXISTS(SELECT 1 FROM dbo.P3_BOD_Ledger WHERE TransferenciaId=@Id) THROW 58100,'PREPARAR no debe cambiar stock ni ledger.',1;
 DELETE @Out;
 INSERT @Out EXEC dbo.sp_TransferirStockBodegas @Actor,@Op,@P,@O,@D,5,N'QA propuesta';
 IF (SELECT COUNT(*) FROM dbo.P3_BOD_Transferencia WHERE ProductoId=@P)<>1 THROW 58100,'Replay duplico propuesta.',1;
 SELECT @V=Version FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=@Id;
 DELETE @Out;
 INSERT @Out EXEC dbo.P3_BOD_AvanzarTransferencia @Actor,@Desp,@Id,'DESPACHAR',@V,N'QA despacho';
 IF NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE ProductoId=@P AND Stock=100 AND StockLocal=95 AND Transito=5 AND Diferencia=0)
  OR NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Stock WHERE ProductoId=@P AND BodegaId=@O AND Cantidad=95)
  OR NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Stock WHERE ProductoId=@P AND BodegaId=@D AND Cantidad=0) THROW 58100,'Despacho no conserva 95+0+5=100.',1;
 -- El replay usa la version ORIGINAL y debe devolver la misma respuesta persistida.
 DECLARE @Primera NVARCHAR(MAX)=(SELECT Respuesta FROM @Out);
 DELETE @Out;
 INSERT @Out EXEC dbo.P3_BOD_AvanzarTransferencia @Actor,@Desp,@Id,'DESPACHAR',@V,N'QA despacho';
 IF NOT EXISTS(SELECT 1 FROM @Out WHERE CONVERT(VARBINARY(MAX),Respuesta)=CONVERT(VARBINARY(MAX),@Primera)) THROW 58100,'Replay no devuelve el mismo recibo.',1;
 SELECT @V=Version FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=@Id;
 DELETE @Out;
 INSERT @Out EXEC dbo.P3_BOD_AvanzarTransferencia @Actor,@Rec,@Id,'RECIBIR',@V,N'QA recepcion';
 DELETE @Out;
 INSERT @Out EXEC dbo.P3_BOD_AvanzarTransferencia @Actor,@Rec,@Id,'RECIBIR',@V,N'QA recepcion';
 IF NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE ProductoId=@P AND Stock=100 AND StockLocal=100 AND Transito=0 AND Diferencia=0)
  OR NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Stock WHERE ProductoId=@P AND BodegaId=@D AND Cantidad=5)
  OR (SELECT COUNT(*) FROM dbo.P3_BOD_Ledger WHERE TransferenciaId=@Id)<>2 THROW 58100,'Recepcion/replay no conserva 95+5+0=100.',1;
 IF EXISTS(SELECT 1 FROM dbo.Kardex_Inventario WHERE OperacionId IN(@Op,@Desp,@Rec)) THROW 58100,'Transferencia duplico movimientos globales.',1;
 IF SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NOT NULL THROW 58100,'Fuga de contexto.',1;
 ROLLBACK;
 PRINT 'PASS preparado/despachado/recibido, replay y stock global (ejecucion manual).';
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;

-- Fallos independientes: los SP revierten TODA la transaccion externa en error.
DECLARE @Caso INT=1,@Esperado INT,@Error INT,@Nueva UNIQUEIDENTIFIER;
WHILE @Caso<=8
BEGIN
 SET @Error=NULL; SET @Op=NEWID(); SET @Nueva=NEWID();
 BEGIN TRY
  BEGIN TRANSACTION;
  IF @Caso=1
  BEGIN SET @Esperado=58002; EXEC dbo.sp_TransferirStockBodegas @Actor,@Op,@P,@O,@D,0,N'Cantidad cero'; END;
  IF @Caso=2
  BEGIN SET @Esperado=58002; EXEC dbo.sp_TransferirStockBodegas @Actor,@Op,@P,@O,@O,5,N'Igual origen'; END;
  IF @Caso=3
  BEGIN SET @Esperado=58005; EXEC dbo.sp_TransferirStockBodegas @Actor,@Op,@P,@O,@D,101,N'Exceso'; END;
  IF @Caso>=4
  BEGIN
   DELETE @Out;
   INSERT @Out EXEC dbo.sp_TransferirStockBodegas @Actor,@Op,@P,@O,@D,5,N'QA fallo';
   SELECT @Id=TRY_CONVERT(INT,JSON_VALUE(Respuesta,'$.TransferenciaId')) FROM @Out;
   SELECT @V=Version FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=@Id;
   SET @Esperado=58003;
   IF @Caso=4 EXEC dbo.P3_BOD_AvanzarTransferencia @Actor,@Nueva,@Id,'RECIBIR',@V,N'No despachada';
   IF @Caso=5 EXEC dbo.sp_TransferirStockBodegas @Actor,@Op,@P,@O,@D,6,N'QA fallo';
   IF @Caso=6
   BEGIN SET @V=0x0000000000000000; EXEC dbo.P3_BOD_AvanzarTransferencia @Actor,@Nueva,@Id,'DESPACHAR',@V,N'Version vieja'; END;
   IF @Caso=7
   BEGIN
    SET @Desp=NEWID(); SET @Rec=NEWID();
    EXEC dbo.P3_BOD_AvanzarTransferencia @Actor,@Desp,@Id,'DESPACHAR',@V,N'QA despacho';
    SELECT @V=Version FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=@Id;
    EXEC dbo.P3_BOD_AvanzarTransferencia @Actor,@Rec,@Id,'RECIBIR',@V,N'QA recepcion';
    SELECT @V=Version FROM dbo.P3_BOD_Transferencia WHERE TransferenciaId=@Id;
    EXEC dbo.P3_BOD_AvanzarTransferencia @Actor,@Nueva,@Id,'RECIBIR',@V,N'Doble recepcion';
   END;
   IF @Caso=8
   BEGIN
    SET @Esperado=58005;
    UPDATE dbo.P3_BOD_Stock SET Cantidad=0 WHERE ProductoId=@P AND BodegaId=@O; -- solo corrupcion SINTETICA dentro del rollback.
    EXEC dbo.P3_BOD_AvanzarTransferencia @Actor,@Nueva,@Id,'DESPACHAR',@V,N'Stock consumido despues de preparar';
   END;
  END;
  IF XACT_STATE()<>0 ROLLBACK;
 END TRY
 BEGIN CATCH
  SET @Error=ERROR_NUMBER();
  IF XACT_STATE()<>0 ROLLBACK;
 END CATCH;
 IF @Error IS NULL OR @Error<>@Esperado THROW 58100,'Un escenario de fallo no rechazo como se esperaba.',1;
 IF EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE ProductoId=@P AND Diferencia<>0) THROW 58100,'Fallo dejo stock sin conciliar.',1;
 SET @Caso+=1;
END;
PRINT 'PASS ocho rechazos y rollback (ejecucion manual; no acredita concurrencia).';
