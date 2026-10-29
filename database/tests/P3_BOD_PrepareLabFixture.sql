-- Explicit synthetic fixture and global opening ONLY in Dylan's newly created lab.
:ON ERROR EXIT
SET NOCOUNT ON; SET XACT_ABORT ON;
SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON;
SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT<>0
 THROW 58000, 'Destino de fixture no autorizado.', 1;
DECLARE @SetupActor int = (SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'P3_DYLAN_QA_ADMIN');
IF @SetupActor IS NULL THROW 58000, 'Requiere actor sintetico de la preparacion controlada.', 1;
EXEC sys.sp_set_session_context @key=N'P3_BOD.TestActor', @value=@SetupActor;
GO
:r tests/P3_BOD_Fixture100.sql
GO
DECLARE @SetupActor int = TRY_CONVERT(int, SESSION_CONTEXT(N'P3_BOD.TestActor'));
DECLARE @Supplier int = (SELECT ProveedorId FROM dbo.Proveedor WHERE NIT=N'P3BODQA100');
DECLARE @Product int = (SELECT ProductoId FROM dbo.Producto WHERE Codigo=N'P3BOD-QA-100');
EXEC dbo.sp_AsociarProductoProveedor @SetupActor,@Product,@Supplier,1;
SET @Product=(SELECT ProductoId FROM dbo.Producto WHERE Codigo=N'P3BOD-QA-COST0');
EXEC dbo.sp_AsociarProductoProveedor @SetupActor,@Product,@Supplier,1;
DECLARE @Opening uniqueidentifier=NEWID();
EXEC dbo.sp_AbrirKardexInventario @Opening,@SetupActor,N'P3_DYLAN_QA_APERTURA',N'Apertura exclusiva de datos sinteticos del laboratorio autorizado';
EXEC dbo.sp_HabilitarKardexInventario @Opening,@SetupActor;
EXEC sys.sp_set_session_context @key=N'P3_BOD.TestActor',@value=NULL;
SELECT N'PASS fixture sintetico y apertura Kardex solo laboratorio' Resultado;
