:ON ERROR EXIT
SET XACT_ABORT ON;
SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON;
SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'SecureFinanceERP_Lab_Dylan' OR DATALENGTH(DB_NAME())<>DATALENGTH(N'SecureFinanceERP_Lab_Dylan') OR @@TRANCOUNT<>0
 THROW 58000, 'Destino de pruebas no autorizado.', 1;
BEGIN TRANSACTION;
GO
:r 82_P3_BOD_Transferencias.sql
GO
:r 83_P3_BOD_Administracion.sql
GO
IF @@TRANCOUNT<>1 OR XACT_STATE()<>1 THROW 58000, 'Procedimientos no confirmables.', 1;
COMMIT;
SELECT N'PASS procs 82/83 reinstalados con Version rowversion -> hex 16 chars' Resultado;
