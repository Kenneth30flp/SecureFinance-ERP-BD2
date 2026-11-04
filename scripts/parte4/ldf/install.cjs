'use strict';
// Explicit operator installation. Does not change recovery model or create a FULL backup.
const fs = require('node:fs');
const path = require('node:path');
const { randomBytes, createHash } = require('node:crypto');
const { runSql, lit, ident, root } = require('./sqlcmd.cjs');
function validateOptions(o) {
  if (!o.database || !o.expectedServer || !o.adminLogin || !o.backupDirectory || !o.authorized) throw Error('Falta autorizacion, destino, servidor esperado, login DBA o directorio.');
  if (['master', 'model', 'msdb', 'tempdb'].includes(o.database.toLowerCase())) throw Error('Base de sistema prohibida.');
  const dir = o.backupDirectory;
  if (dir.length > 1450 || dir.includes('..') || /[\r\n\0]/.test(dir) || !(/^[A-Za-z]:\\/.test(dir) || /^\/[^/]/.test(dir))) throw Error('Usa directorio absoluto local al servidor SQL, sin .. ni UNC.');
  const warning = Number(o.warning ?? 70), critical = Number(o.critical ?? 85);
  if (!Number.isFinite(warning) || !Number.isFinite(critical) || warning <= 0 || warning >= critical || critical > 100) throw Error('Umbrales invalidos.');
  return { ...o, backupDirectory: /[\\/]$/.test(dir) ? dir : dir + (dir.startsWith('/') ? '/' : '\\'), warning, critical };
}
function installationSql(options) {
  const o = validateOptions(options), key = randomBytes(32).toString('hex');
  const cert = 'P4_LDF_Read_' + createHash('sha256').update(o.expectedServer + '|' + o.database).digest('hex').slice(0, 16);
  const sources = (o.upgrade ? ['002_monitor.sql', '003_backup.sql'] : ['001_schema.sql', '002_monitor.sql', '003_backup.sql']).map(f => fs.readFileSync(path.join(root, 'database/parte4/ldf', f), 'utf8'));
  const copyCertificate = db => `DECLARE @Public varbinary(max)=CERTENCODED(CERT_ID(N'P4_LDF_ReadCertificate')); DECLARE @Create nvarchar(max)=N'USE ${ident(db)}; CREATE CERTIFICATE ${ident(cert)} FROM BINARY = '+CONVERT(nvarchar(max),@Public,1)+N';'; EXEC sys.sp_executesql @Create;`;
  return `IF SUSER_ID(${lit(o.adminLogin)}) IS NULL THROW 59010,'Crear primero el login administrativo dedicado.',1;
IF IS_SRVROLEMEMBER('sysadmin',${lit(o.adminLogin)})=1 OR IS_SRVROLEMEMBER('securityadmin',${lit(o.adminLogin)})=1 THROW 59010,'Login administrativo demasiado privilegiado.',1;
IF EXISTS(SELECT 1 FROM sys.server_role_members WHERE member_principal_id=SUSER_ID(${lit(o.adminLogin)}))
 OR EXISTS(SELECT 1 FROM sys.server_permissions WHERE grantee_principal_id=SUSER_ID(${lit(o.adminLogin)}) AND state IN('G','W') AND permission_name NOT IN(N'CONNECT SQL',N'VIEW ANY DATABASE'))
 THROW 59010,'Login DBA debe ser dedicado y sin roles ni permisos amplios de servidor.',1;
IF SUSER_SID(${lit(o.adminLogin)})=(SELECT sid FROM sys.database_principals WHERE name=N'securefinance_app')
 OR IS_ROLEMEMBER('db_owner','securefinance_app')=1
 THROW 59010,'Separar identidad web y DBA; web sin db_owner.',1;
BEGIN TRANSACTION;
EXEC sys.sp_set_session_context @key=N'P4_LDF.InstallTarget',@value=${lit(o.expectedServer + '|' + o.database)};
GO
${o.upgrade ? `IF NOT EXISTS(SELECT 1 FROM dbo.P4_LDF_Configuracion c JOIN sys.database_recovery_status r ON r.database_id=DB_ID() AND r.database_guid=c.DatabaseGuid WHERE c.Id=1 AND c.Servidor=${lit(o.expectedServer)} AND c.BaseDatos=DB_NAME()) THROW 59010,'Upgrade fuera del destino instalado.',1;
DROP SIGNATURE FROM dbo.P4_LDF_Consultar BY CERTIFICATE P4_LDF_ReadCertificate;
DROP SIGNATURE FROM dbo.P4_LDF_RespaldarLog BY CERTIFICATE P4_LDF_ReadCertificate;
DROP SIGNATURE FROM dbo.P4_LDF_RespaldarLog BY CERTIFICATE P4_LDF_BackupCertificate;
DROP USER P4_LDF_ReadCertificateUser; DROP USER P4_LDF_BackupCertificateUser;
DROP CERTIFICATE P4_LDF_ReadCertificate; DROP CERTIFICATE P4_LDF_BackupCertificate;
EXEC(N'USE msdb; DROP USER ${ident(cert)}; DROP CERTIFICATE ${ident(cert)};');
EXEC(N'USE master; DROP LOGIN ${ident(cert)}; DROP CERTIFICATE ${ident(cert)};');
GO` : ''}
${sources.join('\nGO\n')}
${o.upgrade ? '' : `INSERT dbo.P4_LDF_Configuracion (Id,Servidor,BaseDatos,DatabaseGuid,Habilitado,RutaBackup,Advertencia,Critico)
SELECT 1,${lit(o.expectedServer)},DB_NAME(),database_guid,1,${lit(o.backupDirectory)},${o.warning},${o.critical}
FROM sys.database_recovery_status WHERE database_id=DB_ID();
IF @@ROWCOUNT<>1 THROW 59010,'No se pudo fijar identidad de destino.',1;`}
CREATE CERTIFICATE P4_LDF_ReadCertificate ENCRYPTION BY PASSWORD=${lit(key)} WITH SUBJECT=N'P4 LDF: metricas acotadas y lectura de msdb';
CREATE USER P4_LDF_ReadCertificateUser FROM CERTIFICATE P4_LDF_ReadCertificate;
IF CONVERT(int,SERVERPROPERTY('ProductMajorVersion'))>=16
 EXEC(N'GRANT VIEW DATABASE PERFORMANCE STATE TO P4_LDF_ReadCertificateUser;');
ELSE GRANT VIEW DATABASE STATE TO P4_LDF_ReadCertificateUser;
${copyCertificate('master')}
EXEC(N'USE master; CREATE LOGIN ${ident(cert)} FROM CERTIFICATE ${ident(cert)}; GRANT VIEW ANY DATABASE TO ${ident(cert)};');
IF CONVERT(int,SERVERPROPERTY('ProductMajorVersion'))>=16
 EXEC(N'USE master; GRANT VIEW SERVER PERFORMANCE STATE TO ${ident(cert)};');
ELSE EXEC(N'USE master; GRANT VIEW SERVER STATE TO ${ident(cert)};');
GO
${copyCertificate('msdb')}
EXEC(N'USE msdb; CREATE USER ${ident(cert)} FROM CERTIFICATE ${ident(cert)}; GRANT SELECT ON dbo.backupset TO ${ident(cert)}; GRANT SELECT ON dbo.backupmediafamily TO ${ident(cert)};');
ADD SIGNATURE TO dbo.P4_LDF_Consultar BY CERTIFICATE P4_LDF_ReadCertificate WITH PASSWORD=${lit(key)};
ADD SIGNATURE TO dbo.P4_LDF_RespaldarLog BY CERTIFICATE P4_LDF_ReadCertificate WITH PASSWORD=${lit(key)};
ALTER CERTIFICATE P4_LDF_ReadCertificate REMOVE PRIVATE KEY;
CREATE CERTIFICATE P4_LDF_BackupCertificate ENCRYPTION BY PASSWORD=${lit(key)} WITH SUBJECT=N'P4 LDF: BACKUP LOG solo dentro del procedimiento firmado';
CREATE USER P4_LDF_BackupCertificateUser FROM CERTIFICATE P4_LDF_BackupCertificate;
GRANT BACKUP LOG TO P4_LDF_BackupCertificateUser;
ADD SIGNATURE TO dbo.P4_LDF_RespaldarLog BY CERTIFICATE P4_LDF_BackupCertificate WITH PASSWORD=${lit(key)};
ALTER CERTIFICATE P4_LDF_BackupCertificate REMOVE PRIVATE KEY;
${o.upgrade ? `IF NOT EXISTS(SELECT 1 FROM sys.database_principals WHERE name=N'P4_LDF_BackupService' AND sid=SUSER_SID(${lit(o.adminLogin)})) THROW 59010,'Login DBA diferente del instalado.',1;` : `CREATE USER P4_LDF_BackupService FOR LOGIN ${ident(o.adminLogin)};`}
GRANT EXECUTE ON dbo.P4_LDF_Consultar TO securefinance_app;
GRANT EXECUTE ON dbo.P4_LDF_RespaldarLog TO P4_LDF_BackupService;
${o.role ? `IF NOT EXISTS(SELECT 1 FROM dbo.Rol WHERE Nombre=${lit(o.role)} AND Activo=1) THROW 59010,'Rol de aplicacion no encontrado.',1;
INSERT dbo.Rol_Permiso(RolId,PermisoId) SELECT r.RolId,p.PermisoId FROM dbo.Rol r CROSS JOIN dbo.Permiso p
WHERE r.Nombre=${lit(o.role)} AND p.Codigo IN(N'DBA_LDF_CONSULTAR',N'DBA_LDF_RESPALDAR_LOG')
AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=r.RolId AND rp.PermisoId=p.PermisoId);` : ''}
IF @@TRANCOUNT<>1 THROW 59010,'Transaccion de instalacion inconsistente.',1;
COMMIT;
PRINT 'P4_LDF instalado: cuenta web consulta; servicio DBA ejecuta solo respaldo firmado.';`;
}
async function install(options) { return runSql(installationSql(options), options); }
module.exports = { install, installationSql, validateOptions };
if (require.main === module) {
  const e = process.env;
  install({ authorized: process.argv.includes('--authorize-install'), upgrade: process.argv.includes('--upgrade'), database: e.LDF_INSTALL_DATABASE,
    server: e.LDF_INSTALL_SERVER || 'localhost', expectedServer: e.LDF_EXPECTED_SERVER,
    adminLogin: e.LDF_ADMIN_USER, backupDirectory: e.LDF_BACKUP_DIRECTORY,
    warning: e.LDF_WARNING_PERCENT, critical: e.LDF_CRITICAL_PERCENT, role: e.LDF_GRANT_ROLE })
    .then(console.log).catch(error => { console.error(error.message); process.exitCode = 1; });
}
