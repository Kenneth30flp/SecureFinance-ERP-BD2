/*
 PROHIBIDO ejecutar en SecureFinanceERP principal o en bases del sistema.
 Solo laboratorio: DBA confirma externamente el destino REAL y solo despues
 establece SESSION_CONTEXT(N'P3_DDL.LaboratorioConfirmado') = DB_NAME().
 Instalador: 90 -> 91 -> 92, abortar al PRIMER error, SET XACT_ABORT ON,
 envolver TODOS los GO de cada archivo en una transaccion EXTERNA en la MISMA
 conexion. COMMIT solo con exito completo; ROLLBACK ante cualquier error.
 No se crean usuarios/logins ni se alteran permisos de otros modulos.
 Las unicas escrituras de datos son el permiso nuevo y sus asignaciones.
 No hay captura DDL, comandos almacenados ni aprobacion de politica TSQL.
 Revision DBA obligatoria de privilegios efectivos, grupos Windows, permisos
 de servidor, impersonacion, firmas de modulos y cadenas entre bases. Estas
 comprobaciones locales no prueban ausencia de toda via de elevacion; DENY
 no limita dbo/sysadmin ni sustituye esa revision. La inmutabilidad es para
 la app: no se habilitan escritores, y un DBA aun puede cambiar el esquema.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF DB_ID() IS NULL OR DB_ID() <= 4
 OR DB_NAME() COLLATE Latin1_General_100_CI_AS = N'SecureFinanceERP'
 OR DB_NAME() IN (N'master', N'tempdb', N'model', N'msdb', N'mssqlsystemresource')
 THROW 54990, 'Destino prohibido: solo laboratorio confirmado, nunca la base principal.', 1;
IF ISNULL(TRY_CONVERT(nvarchar(128), SESSION_CONTEXT(N'P3_DDL.LaboratorioConfirmado')), N'')
 COLLATE Latin1_General_100_BIN2 <> DB_NAME() COLLATE Latin1_General_100_BIN2
 THROW 54990, 'Falta confirmacion externa del laboratorio por el DBA en esta conexion.', 1;
IF @@TRANCOUNT = 0 OR XACT_STATE() <> 1
 THROW 54990, 'El instalador debe abrir una transaccion externa y abortar al primer error.', 1;
IF ISNULL(HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'VIEW DEFINITION'), 0) <> 1
 THROW 54990, 'Sin visibilidad completa no se pueden validar dependencias y privilegios.', 1;
IF OBJECT_ID(N'dbo.Bitacora_DDL', N'U') IS NULL
 OR OBJECT_ID(N'dbo.P3_DDL_ConsultarBitacora', N'P') IS NULL
 OR OBJECT_ID(N'dbo.P3_DDL_ConsultarDetalle', N'P') IS NULL
 OR OBJECT_ID(N'dbo.sp_ParteII_ValidarPermiso', N'P') IS NULL
 OR OBJECT_ID(N'dbo.Permiso', N'U') IS NULL
 OR OBJECT_ID(N'dbo.Rol', N'U') IS NULL
 OR OBJECT_ID(N'dbo.Rol_Permiso', N'U') IS NULL
 THROW 54990, 'Requiere estructura 90, consultas 91 y catalogos de seguridad existentes.', 1;

DECLARE @AppId int, @AppSid varbinary(85), @Login sysname;
SELECT @AppId = principal_id, @AppSid = sid
FROM sys.database_principals
WHERE name = N'securefinance_app' AND type IN (N'S', N'U');
IF @AppId IS NULL OR @AppId <= 4 OR @AppSid IS NULL
 OR @AppSid = (SELECT sid FROM sys.database_principals WHERE name = N'dbo')
 THROW 54990, 'securefinance_app debe ser un usuario existente y no dbo.', 1;
SET @Login = SUSER_SNAME(@AppSid);
IF @Login IS NULL
 OR ISNULL(IS_SRVROLEMEMBER(N'sysadmin', @Login), 1) <> 0
 OR ISNULL(IS_SRVROLEMEMBER(N'securityadmin', @Login), 1) <> 0
 THROW 54990, 'Login privilegiado o privilegios de servidor no verificables; requiere revision DBA.', 1;

DECLARE @Riesgo bit = 0, @Impersonado bit = 0;
DECLARE @Tokens TABLE (PrincipalId int NOT NULL);
BEGIN TRY
 EXECUTE AS USER = N'securefinance_app';
 SET @Impersonado = 1;
 IF ISNULL(IS_MEMBER(N'db_owner'), 1) <> 0
  OR ISNULL(IS_MEMBER(N'db_securityadmin'), 1) <> 0
  OR ISNULL(IS_MEMBER(N'db_ddladmin'), 1) <> 0
  OR ISNULL(IS_MEMBER(N'db_datareader'), 1) <> 0
  OR ISNULL(IS_MEMBER(N'db_datawriter'), 1) <> 0
  OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'CONTROL'), 1) <> 0
  OR ISNULL(HAS_PERMS_BY_NAME(DB_NAME(), N'DATABASE', N'ALTER'), 1) <> 0
  OR ISNULL(HAS_PERMS_BY_NAME(N'dbo', N'SCHEMA', N'CONTROL'), 1) <> 0
  OR ISNULL(HAS_PERMS_BY_NAME(N'dbo', N'SCHEMA', N'ALTER'), 1) <> 0
  OR EXISTS (SELECT 1 FROM sys.fn_my_permissions(NULL, N'DATABASE')
     WHERE permission_name IN (N'ALTER ANY ROLE', N'ALTER ANY USER', N'ALTER ANY SCHEMA',
      N'ALTER ANY APPLICATION ROLE', N'IMPERSONATE ANY USER', N'TAKE OWNERSHIP'))
  SET @Riesgo = 1;
 INSERT @Tokens (PrincipalId) SELECT principal_id FROM sys.user_token;
 REVERT;
 SET @Impersonado = 0;
END TRY
BEGIN CATCH
 IF @Impersonado = 1 REVERT;
 THROW;
END CATCH;
IF @Riesgo = 1
 THROW 54990, 'La app tiene roles amplios, elevacion o CONTROL/ALTER; no aplicar permisos parciales.', 1;
-- Se inspeccionan objetos con visibilidad del instalador, no de la app sin grants.
IF NOT EXISTS (SELECT 1 FROM @Tokens WHERE PrincipalId = @AppId)
 OR EXISTS (
  SELECT 1 FROM sys.database_permissions p JOIN @Tokens t ON t.PrincipalId = p.grantee_principal_id
  WHERE p.state IN (N'G', N'W') AND p.permission_name IN (N'CONTROL', N'ALTER', N'TAKE OWNERSHIP')
   AND ((p.class = 3 AND p.major_id = SCHEMA_ID(N'dbo'))
    OR (p.class = 1 AND p.major_id IN (OBJECT_ID(N'dbo.Bitacora_DDL'),
     OBJECT_ID(N'dbo.P3_DDL_ConsultarBitacora'), OBJECT_ID(N'dbo.P3_DDL_ConsultarDetalle'))))
 )
 OR EXISTS (
  SELECT 1 FROM sys.objects o JOIN @Tokens t ON t.PrincipalId = o.principal_id
  WHERE o.object_id IN (OBJECT_ID(N'dbo.Bitacora_DDL'),
   OBJECT_ID(N'dbo.P3_DDL_ConsultarBitacora'), OBJECT_ID(N'dbo.P3_DDL_ConsultarDetalle'))
 )
 OR EXISTS (
  SELECT 1 FROM sys.schemas s JOIN @Tokens t ON t.PrincipalId = s.principal_id
  WHERE s.name = N'dbo'
 )
 THROW 54990, 'Token no verificable o privilegios/propiedad sobre objetos de auditoria.', 1;
-- En SQL Server un GRANT de columna puede prevalecer sobre un DENY de tabla.
IF EXISTS (
 SELECT 1 FROM sys.database_permissions p JOIN @Tokens t ON t.PrincipalId = p.grantee_principal_id
 WHERE p.class = 1 AND p.major_id = OBJECT_ID(N'dbo.Bitacora_DDL')
  AND p.minor_id > 0 AND p.state IN (N'G', N'W')
)
 THROW 54990, 'Hay grants de columna heredados sobre la bitacora; requiere revision DBA.', 1;

DECLARE @AdministradorId int, @AuditorId int, @PermisoId int;
IF (SELECT COUNT(*) FROM dbo.Rol WITH (UPDLOCK, HOLDLOCK)
    WHERE Nombre = N'Administrador' AND Activo = 1) <> 1
 OR (SELECT COUNT(*) FROM dbo.Rol WITH (UPDLOCK, HOLDLOCK)
    WHERE Nombre = N'Auditor' AND Activo = 1) <> 1
 THROW 54990, 'Se requieren los roles Administrador y Auditor activos y unicos.', 1;
SELECT @AdministradorId = RolId FROM dbo.Rol WHERE Nombre = N'Administrador' AND Activo = 1;
SELECT @AuditorId = RolId FROM dbo.Rol WHERE Nombre = N'Auditor' AND Activo = 1;

IF (SELECT COUNT(*) FROM dbo.Permiso WITH (UPDLOCK, HOLDLOCK)
    WHERE Codigo = N'AUDITORIA_DDL_CONSULTAR') > 1
 OR EXISTS (SELECT 1 FROM dbo.Permiso WITH (UPDLOCK, HOLDLOCK)
    WHERE Codigo = N'AUDITORIA_DDL_CONSULTAR' AND (Activo IS NULL OR Activo <> 1))
 THROW 54990, 'Permiso existente incompatible o inactivo; no se reactiva silenciosamente.', 1;

INSERT dbo.Permiso (Codigo, Descripcion, Activo)
SELECT N'AUDITORIA_DDL_CONSULTAR', N'Consultar metadatos de auditoria DDL sin comandos TSQL', 1
WHERE NOT EXISTS (SELECT 1 FROM dbo.Permiso WITH (UPDLOCK, HOLDLOCK)
 WHERE Codigo = N'AUDITORIA_DDL_CONSULTAR');
SELECT @PermisoId = PermisoId FROM dbo.Permiso
WHERE Codigo = N'AUDITORIA_DDL_CONSULTAR' AND Activo = 1;
IF @PermisoId IS NULL
 THROW 54990, 'No se pudo acreditar el permiso activo.', 1;
IF EXISTS (SELECT 1 FROM dbo.Rol_Permiso WITH (UPDLOCK, HOLDLOCK)
 WHERE PermisoId = @PermisoId AND RolId NOT IN (@AdministradorId, @AuditorId))
 THROW 54990, 'El permiso ya esta asignado a otros roles; no se revocan asignaciones existentes.', 1;

INSERT dbo.Rol_Permiso (RolId, PermisoId)
SELECT r.RolId, @PermisoId FROM (VALUES (@AdministradorId), (@AuditorId)) r(RolId)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Rol_Permiso p WITH (UPDLOCK, HOLDLOCK)
 WHERE p.RolId = r.RolId AND p.PermisoId = @PermisoId);

GRANT EXECUTE ON OBJECT::dbo.P3_DDL_ConsultarBitacora TO securefinance_app;
GRANT EXECUTE ON OBJECT::dbo.P3_DDL_ConsultarDetalle TO securefinance_app;
DENY SELECT, INSERT, UPDATE, DELETE ON OBJECT::dbo.Bitacora_DDL TO securefinance_app;
GO
