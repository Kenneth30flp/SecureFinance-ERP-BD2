-- Execute only in SQLCMD mode, from this worktree database directory.
-- Dylan explicitly authorized execution of proposal76 ONLY in this fresh lab.
-- This does not approve shared production integration with Promotions63.
:ON ERROR EXIT
SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT<>0
 THROW 57000, 'Instalador exclusivo de laboratorio sin transaccion previa.', 1;
BEGIN TRANSACTION;
GO
:r 70_P3_CRE_Estructura.sql
GO
:r 71_P3_CRE_Perfiles.sql
GO
:r 72_P3_CRE_Financiacion.sql
GO
:r 73_P3_CRE_Abonos.sql
GO
:r 74_P3_CRE_Consultas.sql
GO
:r 75_P3_CRE_Seguridad.sql
GO
:r 76_P3_CRE_Ventas_PROPUESTA.sql
GO
:r 77_P3_CRE_ConversionPublica.sql
GO
:r 78_P3_CRE_AjustesConsultas.sql
GO
:r 78_P3_CRE_Verificacion.sql
GO
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT<>1 OR XACT_STATE()<>1
 THROW 57000, 'Instalacion financiera no confirmable.', 1;
COMMIT;
SELECT N'PASS instalacion 70-78 solo laboratorio' Resultado;
