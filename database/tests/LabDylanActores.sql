-- Synthetic SQL authorization actors only. No usable password or login is created.
:ON ERROR EXIT
SET NOCOUNT ON; SET XACT_ABORT ON;
IF DB_NAME() COLLATE Latin1_General_100_BIN2 <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT <> 0
 THROW 54980, 'Destino de fixtures no autorizado.', 1;
IF EXISTS (SELECT 1 FROM dbo.Usuario WHERE NombreUsuario IN (N'P3_DYLAN_QA_ADMIN', N'P3_DYLAN_QA_AUDITOR', N'P3_DYLAN_QA_DENEGADO'))
 THROW 54980, 'Actores QA ya existen: no se modifican credenciales.', 1;
BEGIN TRANSACTION;
INSERT dbo.Usuario(NombreUsuario,NombreCompleto,Correo,PasswordHash,DebeCambiarPassword)
VALUES (N'P3_DYLAN_QA_ADMIN',N'Actor sintetico laboratorio Dylan',N'qa-admin@example.invalid',CRYPT_GEN_RANDOM(64),1),
 (N'P3_DYLAN_QA_AUDITOR',N'Auditor sintetico laboratorio Dylan',N'qa-auditor@example.invalid',CRYPT_GEN_RANDOM(64),1),
 (N'P3_DYLAN_QA_DENEGADO',N'Actor sin permisos laboratorio Dylan',N'qa-denegado@example.invalid',CRYPT_GEN_RANDOM(64),1);
INSERT dbo.Usuario_Rol(UsuarioId,RolId)
SELECT u.UsuarioId,r.RolId FROM dbo.Usuario u JOIN dbo.Rol r
 ON (u.NombreUsuario=N'P3_DYLAN_QA_ADMIN' AND r.Nombre=N'Administrador')
 OR (u.NombreUsuario=N'P3_DYLAN_QA_AUDITOR' AND r.Nombre=N'Auditor');
-- Only lab catalog authorization; no server permissions or real identities.
INSERT dbo.Rol_Permiso(RolId,PermisoId)
SELECT r.RolId,p.PermisoId FROM dbo.Rol r CROSS JOIN dbo.Permiso p
WHERE r.Nombre=N'Administrador' AND r.Activo=1 AND p.Activo=1
 AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=r.RolId AND rp.PermisoId=p.PermisoId);
COMMIT;
SELECT N'PASS actores sinteticos sin credenciales utilizables; solo laboratorio' Resultado;
