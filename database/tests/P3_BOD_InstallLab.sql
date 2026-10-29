-- SOLO SQLCMD, desde database/. PREPARADO; NO ejecutado ni autorizado en esta entrega.
-- Requiere aprobacion escrita de Kenneth para el trigger 84, respaldo y escritores detenidos.
:ON ERROR EXIT
SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'SecureFinanceERP_Lab_Dylan' OR DATALENGTH(DB_NAME())<>DATALENGTH(N'SecureFinanceERP_Lab_Dylan') OR @@TRANCOUNT<>0
 THROW 58000,'Instalador exclusivo del laboratorio Dylan; requiere conexion sin transaccion.',1;
BEGIN TRANSACTION;
GO
:r 80_P3_BOD_Estructura.sql
GO
:r 81_P3_BOD_Contratos.sql
GO
:r 82_P3_BOD_Transferencias.sql
GO
:r 83_P3_BOD_Administracion.sql
GO
:r 84_P3_BOD_EspejoKardex.sql
GO
:r 85_P3_BOD_Integraciones.sql
GO
:r 86_P3_BOD_Consultas.sql
GO
:r 87_P3_BOD_Permisos.sql
GO
:r 88_P3_BOD_SnapshotInicial.sql
GO
:r 89_P3_BOD_Complementos.sql
GO
:r 89_P3_BOD_Verificacion.sql
GO
IF DB_NAME() COLLATE Latin1_General_100_BIN2<>N'SecureFinanceERP_Lab_Dylan' OR DATALENGTH(DB_NAME())<>DATALENGTH(N'SecureFinanceERP_Lab_Dylan') OR @@TRANCOUNT<>1 OR XACT_STATE()<>1
 THROW 58000,'No se puede confirmar instalacion incompleta.',1;
COMMIT TRANSACTION;
GO
