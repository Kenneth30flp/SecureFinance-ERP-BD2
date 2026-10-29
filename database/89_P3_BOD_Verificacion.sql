SET NOCOUNT ON; SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'SecureFinanceERP_Lab_Dylan' OR DATALENGTH(DB_NAME())<>DATALENGTH(N'SecureFinanceERP_Lab_Dylan') OR @@TRANCOUNT=0 OR XACT_STATE()<>1 THROW 58000,'Laboratorio y transaccion externa requeridos.',1;
IF (SELECT COUNT(*) FROM dbo.P3_BOD_Bodega WHERE IsCentral=1 AND Activo=1)<>1
 OR NOT EXISTS(SELECT 1 FROM dbo.P3_BOD_Configuracion c JOIN dbo.P3_BOD_Bodega b ON b.BodegaId=c.CentralId AND b.IsCentral=1 AND b.Activo=1 WHERE c.ConfiguracionId=1)
 THROW 58000,'Configuracion central inconsistente.',1;
IF EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE Diferencia<>0) THROW 58000,'Snapshot local no concilia.',1;
IF (SELECT COUNT_BIG(*) FROM dbo.P3_BOD_Snapshot)<>(SELECT COUNT_BIG(*) FROM dbo.Producto) THROW 58000,'Snapshot incompleto.',1;
IF EXISTS(SELECT 1 FROM sys.check_constraints WHERE parent_object_id IN(OBJECT_ID('dbo.P3_BOD_Stock'),OBJECT_ID('dbo.P3_BOD_Ledger'),OBJECT_ID('dbo.P3_BOD_Transferencia')) AND (is_disabled=1 OR is_not_trusted=1)) THROW 58000,'Restricciones no confiables.',1;
IF NOT EXISTS(SELECT 1 FROM sys.triggers WHERE object_id=OBJECT_ID('dbo.P3_BOD_EspejoKardex') AND is_disabled=0)
 OR NOT EXISTS(SELECT 1 FROM sys.triggers WHERE object_id=OBJECT_ID('dbo.tr_Kardex_Auditar_Insert') AND is_disabled=0) THROW 58000,'Faltan triggers de integracion/auditoria.',1;
IF OBJECT_ID('dbo.P3_BOD_ValidarBodegaVenta','P') IS NULL
 OR (SELECT COUNT(*) FROM sys.parameters WHERE object_id=OBJECT_ID('dbo.P3_BOD_ValidarBodegaVenta') AND system_type_id=56 AND is_output=0 AND name IN(N'@ActorUsuarioId',N'@BodegaId'))<>2
 OR (SELECT COUNT(*) FROM sys.parameters WHERE object_id=OBJECT_ID('dbo.P3_BOD_ValidarBodegaVenta'))<>2
 THROW 58000,'Falta helper interno compatible con Creditos 76/77.',1;
SELECT N'Mod5 preparado en transaccion externa; el instalador decide COMMIT.' Resultado,DB_NAME() BaseDatos;
