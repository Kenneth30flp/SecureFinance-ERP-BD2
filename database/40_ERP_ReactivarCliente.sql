-- Incremental after 39. Installation never changes a client's business state.
SET XACT_ABORT ON; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON;
IF OBJECT_ID('dbo.sp_ERP_ConsultarComprobante','P') IS NULL
 OR NOT EXISTS(SELECT 1 FROM sys.triggers WHERE object_id=OBJECT_ID('dbo.tr_Cliente_Auditar_Update') AND is_disabled=0)
 THROW 54800,'Requiere migracion 39 y auditoria activa de clientes.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 IF OBJECT_ID('dbo.ReactivacionCliente','U') IS NULL
 CREATE TABLE dbo.ReactivacionCliente(
  OperacionId uniqueidentifier NOT NULL PRIMARY KEY,
  ClienteId int NOT NULL REFERENCES dbo.Cliente(ClienteId),
  UsuarioId int NOT NULL REFERENCES dbo.Usuario(UsuarioId),
  VersionAnterior binary(8) NOT NULL,VersionPosterior binary(8) NOT NULL,
  Motivo nvarchar(250) NOT NULL CHECK(LEN(LTRIM(RTRIM(Motivo)))>0),
  FechaHora datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME()
 );
 IF ISNULL(COL_LENGTH('dbo.ReactivacionCliente','OperacionId'),-1)<>16
 OR ISNULL(COL_LENGTH('dbo.ReactivacionCliente','VersionAnterior'),-1)<>8
 OR ISNULL(COL_LENGTH('dbo.ReactivacionCliente','VersionPosterior'),-1)<>8
 OR ISNULL(COL_LENGTH('dbo.ReactivacionCliente','Motivo'),-1)<>500
 THROW 54800,'Libro de reactivaciones incompatible; revisar sin borrar.',1;
 INSERT dbo.Permiso(Codigo,Descripcion)
 SELECT N'CLIENTES_REACTIVAR',N'Reactivar administrativamente clientes con motivo y auditoria'
 WHERE NOT EXISTS(SELECT 1 FROM dbo.Permiso WITH(UPDLOCK,HOLDLOCK) WHERE Codigo=N'CLIENTES_REACTIVAR');
 DECLARE @Rol int=(SELECT RolId FROM dbo.Rol WHERE Nombre=N'Administrador' AND Activo=1);
 IF @Rol IS NULL THROW 54800,'Falta rol Administrador activo.',1;
 INSERT dbo.Rol_Permiso(RolId,PermisoId)
 SELECT @Rol,PermisoId FROM dbo.Permiso p WHERE Codigo=N'CLIENTES_REACTIVAR'
 AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=@Rol AND rp.PermisoId=p.PermisoId);
 COMMIT;
END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK; THROW; END CATCH;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ReactivarCliente
 @ActorUsuarioId int,@ClienteId int,@VersionEsperada binary(8),@Motivo nvarchar(max),@OperacionId uniqueidentifier
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
 EXEC sys.sp_set_session_context @key=N'ParteII.Actor',@value=NULL;
 EXEC sys.sp_set_session_context @key=N'ParteII.Operacion',@value=NULL;
 EXEC sys.sp_set_session_context @key=N'ParteII.Motivo',@value=NULL;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'CLIENTES_REACTIVAR';
  SET @Motivo=LTRIM(RTRIM(@Motivo));
  IF @ClienteId IS NULL OR @ClienteId<1 OR @VersionEsperada IS NULL OR @OperacionId IS NULL
   OR @Motivo IS NULL OR LEN(@Motivo)=0 OR DATALENGTH(@Motivo)>500
   THROW 54102,'Cliente, version, operacion y motivo de hasta 250 caracteres requeridos.',1;
  DECLARE @Lock int,@Resource nvarchar(255)=CONCAT(N'ERP.Cliente.Reactivar.',@OperacionId),@Existe bit=0,
   @MotivoContexto nvarchar(250)=@Motivo;
  EXEC @Lock=sys.sp_getapplock @Resource=@Resource,@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
  IF @Lock<0 THROW 54103,'Operacion ocupada; conserva su referencia y reintenta.',1;
  IF EXISTS(SELECT 1 FROM dbo.ReactivacionCliente WITH(UPDLOCK,HOLDLOCK) WHERE OperacionId=@OperacionId)
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM dbo.ReactivacionCliente WHERE OperacionId=@OperacionId
    AND ClienteId=@ClienteId AND UsuarioId=@ActorUsuarioId AND VersionAnterior=@VersionEsperada
    AND Motivo COLLATE Latin1_General_100_BIN2=@Motivo COLLATE Latin1_General_100_BIN2 AND DATALENGTH(Motivo)=DATALENGTH(@Motivo))
    THROW 54103,'La referencia ya se uso con otros datos.',1;
   SET @Existe=1;
  END;
  DECLARE @Activo bit,@Version binary(8);
  SELECT @Activo=Activo,@Version=Version FROM dbo.Cliente WITH(UPDLOCK,HOLDLOCK) WHERE ClienteId=@ClienteId;
  IF @Version IS NULL THROW 54104,'Cliente inexistente.',1;
  IF @Existe=1
  BEGIN
   -- An old retry must never reactivate a subsequent inactivation.
   IF @Activo<>1 THROW 54103,'El cliente cambio despues de esta reactivacion.',1;
  END
  ELSE
  BEGIN
   IF @Version<>@VersionEsperada OR @Activo<>0 THROW 54103,'El cliente debe estar inactivo y conservar la version esperada.',1;
   EXEC sys.sp_set_session_context @key=N'ParteII.Actor',@value=@ActorUsuarioId;
   EXEC sys.sp_set_session_context @key=N'ParteII.Operacion',@value=@OperacionId;
   EXEC sys.sp_set_session_context @key=N'ParteII.Motivo',@value=@MotivoContexto;
   UPDATE dbo.Cliente SET Activo=1 WHERE ClienteId=@ClienteId AND Version=@VersionEsperada AND Activo=0;
   IF @@ROWCOUNT<>1 THROW 54103,'El cliente cambio; actualiza la ficha.',1;
   IF (SELECT COUNT_BIG(*) FROM dbo.Bitacora_Transacciones WHERE TablaAfectada=N'Cliente' AND Operacion='UPDATE' AND OperacionId=@OperacionId AND ActorUsuarioId=@ActorUsuarioId)<>1
    THROW 54800,'No se pudo acreditar un unico evento de auditoria; operacion revertida.',1;
   INSERT dbo.ReactivacionCliente(OperacionId,ClienteId,UsuarioId,VersionAnterior,VersionPosterior,Motivo)
   SELECT @OperacionId,@ClienteId,@ActorUsuarioId,@VersionEsperada,Version,@Motivo FROM dbo.Cliente WHERE ClienteId=@ClienteId;
  END;
  SELECT ClienteId,NIT,Nombre,Activo,Version FROM dbo.Cliente WHERE ClienteId=@ClienteId;
  COMMIT;
  EXEC sys.sp_set_session_context @key=N'ParteII.Actor',@value=NULL;
  EXEC sys.sp_set_session_context @key=N'ParteII.Operacion',@value=NULL;
  EXEC sys.sp_set_session_context @key=N'ParteII.Motivo',@value=NULL;
 END TRY BEGIN CATCH
  IF XACT_STATE()<>0 ROLLBACK;
  EXEC sys.sp_set_session_context @key=N'ParteII.Actor',@value=NULL;
  EXEC sys.sp_set_session_context @key=N'ParteII.Operacion',@value=NULL;
  EXEC sys.sp_set_session_context @key=N'ParteII.Motivo',@value=NULL;
  THROW;
 END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_ConsultarHistorialEstadoCliente @ActorUsuarioId int,@ClienteId int AS
BEGIN
 SET NOCOUNT ON;
 EXEC dbo.sp_ParteII_ValidarPermiso @ActorUsuarioId,N'CLIENTES_CONSULTAR';
 IF @ClienteId IS NULL OR @ClienteId<1 THROW 54102,'Cliente invalido.',1;
 SELECT TOP(20) b.FechaHora,
 CASE WHEN j.Anterior='true' THEN N'Activo' ELSE N'Inactivo' END EstadoAnterior,
 CASE WHEN j.Nuevo='true' THEN N'Activo' ELSE N'Inactivo' END EstadoNuevo,
 COALESCE(b.Motivo,CASE WHEN j.Nuevo='false' THEN JSON_VALUE(j.DocumentoNuevo,'$.MotivoInactivacion') END,N'Sin motivo historico registrado') Motivo,
 COALESCE(u.NombreUsuario,N'No registrado') Responsable,b.OperacionId
 FROM dbo.Bitacora_Transacciones b LEFT JOIN dbo.Usuario u ON u.UsuarioId=b.ActorUsuarioId
 CROSS APPLY(SELECT CASE WHEN ISJSON(b.ValorAnterior)=1 THEN b.ValorAnterior ELSE N'{}' END A,
 CASE WHEN ISJSON(b.ValorNuevo)=1 THEN b.ValorNuevo ELSE N'{}' END N) d
 CROSS APPLY(SELECT JSON_VALUE(d.A,'$.Activo') Anterior,JSON_VALUE(d.N,'$.Activo') Nuevo,d.N DocumentoNuevo) j
 WHERE b.TablaAfectada=N'Cliente' AND b.Operacion='UPDATE' AND b.IdentificadorRegistro=CONVERT(nvarchar(20),@ClienteId)
 AND j.Anterior<>j.Nuevo ORDER BY b.FechaHora DESC,b.BitacoraTransaccionId DESC;
END;
GO
CREATE OR ALTER TRIGGER dbo.tr_ReactivacionCliente_Inmutable ON dbo.ReactivacionCliente INSTEAD OF UPDATE,DELETE AS
BEGIN
 THROW 54805,'El libro de reactivaciones es inmutable.',1;
END;
GO
GRANT EXECUTE ON dbo.sp_ReactivarCliente TO securefinance_app;
GRANT EXECUTE ON dbo.sp_ConsultarHistorialEstadoCliente TO securefinance_app;
DENY SELECT,INSERT,UPDATE,DELETE ON dbo.ReactivacionCliente TO securefinance_app;
GO
