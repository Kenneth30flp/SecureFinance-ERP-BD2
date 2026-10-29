:ON ERROR EXIT
SET NOCOUNT ON; SET XACT_ABORT ON;
SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON;
SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT<>0
 THROW 58000, 'Destino de pruebas no autorizado.', 1;
DECLARE @QaActor int=(SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'P3_DYLAN_QA_ADMIN');
IF @QaActor IS NULL THROW 58000, 'Falta actor sintetico.', 1;
EXEC sys.sp_set_session_context @key=N'P3_BOD.TestActor',@value=@QaActor;
GO
:r tests/P3_BOD_Transferencias.sql
GO
:r tests/P3_BOD_Integraciones.sql
GO
IF @@TRANCOUNT<>0 OR EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE Diferencia<>0)
 THROW 58100, 'Quedo transaccion o saldo sin conciliar.', 1;
EXEC sys.sp_set_session_context @key=N'P3_BOD.TestActor',@value=NULL;
SELECT N'PASS suites reales de transferencias e integraciones; sin descuadres' Resultado;
