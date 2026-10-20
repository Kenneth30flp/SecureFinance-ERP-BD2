-- Kenneth: mantenimiento de clientes. Incremental despues de 22.
-- Contexto seleccionado por el DBA; no altera Kardex ni facturacion.
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
IF DB_NAME() IN ('master','model','msdb','tempdb') THROW 54523,'Seleccione la base de aplicacion.',1;
IF OBJECT_ID('dbo.sp_ConsultarClientesWeb','P') IS NULL OR COL_LENGTH('dbo.Cliente','Version')<>8
 THROW 54523,'Requiere migracion 22 y ROWVERSION.',1;
IF EXISTS(SELECT 1 FROM (VALUES('tr_Cliente_Auditar_Insert'),('tr_Cliente_Auditar_Update')) t(n) WHERE NOT EXISTS(SELECT 1 FROM sys.triggers WHERE object_id=OBJECT_ID('dbo.'+t.n) AND is_disabled=0))
 THROW 54523,'Se requieren los triggers DML existentes activos.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.Permiso(Codigo,Descripcion)
 SELECT s.Codigo,N'Parte II Kenneth: '+s.Codigo FROM (VALUES(N'CLIENTES_REGISTRAR'),(N'CLIENTES_EDITAR')) s(Codigo)
 WHERE NOT EXISTS(SELECT 1 FROM dbo.Permiso WITH(UPDLOCK,HOLDLOCK) WHERE Codigo=s.Codigo);
 IF NOT EXISTS(SELECT 1 FROM dbo.Rol WHERE Nombre=N'Administrador' AND Activo=1) THROW 54523,'Falta Administrador activo.',1;
 INSERT dbo.Rol_Permiso(RolId,PermisoId)
 SELECT r.RolId,p.PermisoId FROM dbo.Rol r CROSS JOIN dbo.Permiso p
 WHERE r.Nombre=N'Administrador' AND r.Activo=1 AND p.Codigo IN(N'CLIENTES_REGISTRAR',N'CLIENTES_EDITAR') AND p.Activo=1
 AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=r.RolId AND rp.PermisoId=p.PermisoId);
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_RegistrarCliente
 @ActorUsuarioId INT,@NIT NVARCHAR(MAX),@Nombre NVARCHAR(MAX),@Correo NVARCHAR(MAX)=NULL,@Telefono NVARCHAR(MAX)=NULL
 AS
 BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''CLIENTES_REGISTRAR'';
 IF @NIT IS NULL OR DATALENGTH(@NIT)>50 OR @Nombre IS NULL OR DATALENGTH(@Nombre)>300 OR DATALENGTH(@Correo)>508 OR DATALENGTH(@Telefono)>50 THROW 54102,''Longitud o datos de cliente invalidos.'',1;
 SET @NIT=UPPER(REPLACE(LTRIM(RTRIM(@NIT)),N''-'',N''''));
 SET @Nombre=LTRIM(RTRIM(@Nombre)); SET @Correo=NULLIF(LTRIM(RTRIM(@Correo)),N''''); SET @Telefono=NULLIF(LTRIM(RTRIM(@Telefono)),N'''');
 IF LEN(@NIT)=0 OR @NIT COLLATE Latin1_General_100_BIN2 LIKE N''%[^A-Z0-9]%'' OR LEN(@Nombre)=0
 OR @Nombre LIKE N''%''+NCHAR(9)+N''%'' OR @Nombre LIKE N''%''+NCHAR(10)+N''%'' OR @Nombre LIKE N''%''+NCHAR(13)+N''%''
 OR (@Correo IS NOT NULL AND (@Correo NOT LIKE N''%_@_%._%'' OR @Correo LIKE N''% %'' OR @Correo LIKE N''%''+NCHAR(9)+N''%'' OR @Correo LIKE N''%''+NCHAR(10)+N''%'' OR @Correo LIKE N''%''+NCHAR(13)+N''%'' OR LEN(@Correo)-LEN(REPLACE(@Correo,N''@'',N''''))<>1))
 OR (@Telefono IS NOT NULL AND (@Telefono COLLATE Latin1_General_100_BIN2 LIKE N''%[^-+(). /0-9]%'' OR @Telefono NOT LIKE N''%[0-9]%'')) THROW 54102,''Nombre, NIT o contacto invalidos.'',1;
 IF EXISTS(SELECT 1 FROM dbo.Cliente WITH(UPDLOCK,HOLDLOCK) WHERE NITNormalizado=@NIT) THROW 54114,''NIT ya registrado.'',1;
 DECLARE @Operacion UNIQUEIDENTIFIER=NEWID(),@Id INT;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@ActorUsuarioId;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=@Operacion;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=N''Registro de cliente'';
 INSERT dbo.Cliente(NIT,Nombre,Correo,Telefono) VALUES(@NIT,@Nombre,@Correo,@Telefono);
 SET @Id=CONVERT(INT,SCOPE_IDENTITY());
 SELECT ClienteId,NIT,Nombre,Correo,Telefono,Activo,FechaCreacion,Version FROM dbo.Cliente WHERE ClienteId=@Id;
 COMMIT TRANSACTION;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 END TRY BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 THROW;
 END CATCH;
 END;';
 EXEC sys.sp_executesql N'CREATE OR ALTER PROCEDURE dbo.sp_ActualizarDatosCliente
 @ActorUsuarioId INT,@ClienteId INT,@VersionEsperada BINARY(8),@Nombre NVARCHAR(MAX),@Correo NVARCHAR(MAX)=NULL,@Telefono NVARCHAR(MAX)=NULL
 AS
 BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N''CLIENTES_EDITAR'';
 IF @Nombre IS NULL OR DATALENGTH(@Nombre)>300 OR DATALENGTH(@Correo)>508 OR DATALENGTH(@Telefono)>50 THROW 54102,''Longitud o datos de cliente invalidos.'',1;
 SET @Nombre=LTRIM(RTRIM(@Nombre)); SET @Correo=NULLIF(LTRIM(RTRIM(@Correo)),N''''); SET @Telefono=NULLIF(LTRIM(RTRIM(@Telefono)),N'''');
 IF LEN(@Nombre)=0 OR @Nombre LIKE N''%''+NCHAR(9)+N''%'' OR @Nombre LIKE N''%''+NCHAR(10)+N''%'' OR @Nombre LIKE N''%''+NCHAR(13)+N''%''
 OR (@Correo IS NOT NULL AND (@Correo NOT LIKE N''%_@_%._%'' OR @Correo LIKE N''% %'' OR @Correo LIKE N''%''+NCHAR(9)+N''%'' OR @Correo LIKE N''%''+NCHAR(10)+N''%'' OR @Correo LIKE N''%''+NCHAR(13)+N''%'' OR LEN(@Correo)-LEN(REPLACE(@Correo,N''@'',N''''))<>1))
 OR (@Telefono IS NOT NULL AND (@Telefono COLLATE Latin1_General_100_BIN2 LIKE N''%[^-+(). /0-9]%'' OR @Telefono NOT LIKE N''%[0-9]%'')) THROW 54102,''Nombre o contacto invalidos.'',1;
 IF @VersionEsperada IS NULL OR NOT EXISTS(SELECT 1 FROM dbo.Cliente WITH(UPDLOCK,HOLDLOCK) WHERE ClienteId=@ClienteId AND Version=@VersionEsperada) THROW 54103,''Cliente inexistente o version obsoleta.'',1;
 DECLARE @Operacion UNIQUEIDENTIFIER=NEWID();
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=@ActorUsuarioId;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=@Operacion;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=N''Actualizacion de datos de contacto'';
 UPDATE dbo.Cliente SET Nombre=@Nombre,Correo=@Correo,Telefono=@Telefono WHERE ClienteId=@ClienteId AND Version=@VersionEsperada;
 SELECT ClienteId,NIT,Nombre,Correo,Telefono,Activo,FechaCreacion,Version FROM dbo.Cliente WHERE ClienteId=@ClienteId;
 COMMIT TRANSACTION;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 END TRY BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 EXEC sys.sp_set_session_context @key=N''ParteII.Actor'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Operacion'',@value=NULL;
 EXEC sys.sp_set_session_context @key=N''ParteII.Motivo'',@value=NULL;
 THROW;
 END CATCH;
 END;';
 IF DATABASE_PRINCIPAL_ID(N'securefinance_app') IS NULL THROW 54523,'Falta usuario SQL dedicado.',1;
 IF IS_ROLEMEMBER('db_owner','securefinance_app')=1 OR IS_ROLEMEMBER('db_datawriter','securefinance_app')=1 THROW 54523,'La cuenta de aplicacion tiene privilegios amplios.',1;
 GRANT EXECUTE ON OBJECT::dbo.sp_RegistrarCliente TO securefinance_app;
 GRANT EXECUTE ON OBJECT::dbo.sp_ActualizarDatosCliente TO securefinance_app;
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
