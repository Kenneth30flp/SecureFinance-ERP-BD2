:ON ERROR EXIT
SET XACT_ABORT ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT<>0
 THROW 57000,'Solo ajustes incrementales del laboratorio.',1;
BEGIN TRANSACTION;
GO
:r 78_P3_CRE_AjustesConsultas.sql
GO
IF @@TRANCOUNT<>1 OR XACT_STATE()<>1 THROW 57000,'Ajustes no confirmables.',1;
COMMIT;
SELECT N'PASS ajustes de consultas, morosidad y recibos' Resultado;
