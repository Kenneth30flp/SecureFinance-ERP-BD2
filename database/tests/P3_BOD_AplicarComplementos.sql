:ON ERROR EXIT
SET XACT_ABORT ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT<>0 THROW 58000,'Destino no autorizado.',1;
BEGIN TRANSACTION;
GO
:r 89_P3_BOD_Complementos.sql
GO
IF @@TRANCOUNT<>1 OR XACT_STATE()<>1 THROW 58000,'Complementos no confirmables.',1;
COMMIT;
SELECT N'PASS catalogo completo, versiones y filtros SKU/estado' Resultado;
