'use strict';
// Creates NEW synthetic ERP only. Never clones/backs up/restores the user's databases.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { randomBytes } = require('node:crypto');
const { runSql, queryJson, lit, ident, root } = require('./sqlcmd.cjs');
const { install } = require('./install.cjs');
const statePath = path.join(root, '.data', 'ldf-lab.json');
const pattern = /^SecureFinanceERP_P4_LDF_\d{14}_[a-f0-9]{8}$/;
function state() {
  const value = JSON.parse(fs.readFileSync(statePath, 'utf8'));
  assert.match(value.database, pattern); return value;
}
function useLab() {
  const s = state();
  Object.assign(process.env, { DB_SERVER: s.server, DB_PORT: '1433', DB_NAME: s.database,
    DB_USER: s.appLogin, DB_PASSWORD: s.appPassword, DB_ENCRYPT: 'true', DB_TRUST_SERVER_CERTIFICATE: 'true',
    LDF_DATABASE: s.database, LDF_EXPECTED_SERVER: s.expectedServer,
    LDF_ADMIN_USER: s.adminLogin, LDF_ADMIN_PASSWORD: s.adminPassword, SESSION_COOKIE_NAME: 'securefinance.ldf.sid',
    SESSION_SECRET: s.sessionSecret, PORT: '3004' });
  return s;
}
async function build({ simple = false } = {}) {
  const outputState = simple ? path.join(root, '.data', 'ldf-simple-lab.json') : statePath;
  assert(!fs.existsSync(outputState), 'Ya hay laboratorio: no sobrescribir estado ni credenciales.');
  const expectedServer = process.env.LDF_EXPECTED_SERVER;
  assert(expectedServer, 'Indica LDF_EXPECTED_SERVER tras comprobar la identidad SQL.');
  const server = 'localhost', stamp = new Date().toISOString().replace(/\D/g, '').slice(0, 14) + '_' + randomBytes(4).toString('hex');
  const database = 'SecureFinanceERP_P4_LDF_' + stamp;
  const s = { server, expectedServer, database, appLogin: 'P4_LDF_App_' + stamp, adminLogin: 'P4_LDF_Worker_' + stamp,
    appPassword: 'App!' + randomBytes(24).toString('base64url'), adminPassword: 'Dba!' + randomBytes(24).toString('base64url'),
    webPassword: 'Demo!' + randomBytes(15).toString('base64url'), sessionSecret: randomBytes(48).toString('hex'), phase: 'created', recovery: simple ? 'SIMPLE' : 'FULL' };
  const backup = await queryJson("SELECT CONVERT(nvarchar(1500),SERVERPROPERTY('InstanceDefaultBackupPath')) Directory", { server, expectedServer, database: 'master' });
  assert(backup[0]?.Directory, 'Configura primero un directorio del motor SQL.'); s.backupDirectory = backup[0].Directory;
  await runSql(`IF DB_ID(${lit(database)}) IS NOT NULL THROW 59010,'Destino existente',1;
CREATE DATABASE ${ident(database)};
CREATE LOGIN ${ident(s.appLogin)} WITH PASSWORD=${lit(s.appPassword)},CHECK_POLICY=ON,DEFAULT_DATABASE=${ident(database)};
CREATE LOGIN ${ident(s.adminLogin)} WITH PASSWORD=${lit(s.adminPassword)},CHECK_POLICY=ON,DEFAULT_DATABASE=${ident(database)};`, { ...s, database: 'master' });
  fs.mkdirSync(path.dirname(outputState), { recursive: true }); fs.writeFileSync(outputState, JSON.stringify(s, null, 2), { flag: 'wx' });
  const files = fs.readdirSync(path.join(root, 'database'));
  function source(n) {
    const found = files.filter(f => f.startsWith(n + '_') && f.endsWith('.sql') && !/Verificacion|Pruebas/.test(f));
    assert.equal(found.length, 1, 'Fuente ambigua ' + n); return render(found[0]);
  }
  function render(file) {
    let text = fs.readFileSync(path.join(root, 'database', file), 'utf8').replace(/^\uFEFF/, '');
    if (file === 'SecureFinanceERP_Full.sql') text = text.slice(text.indexOf('USE [SecureFinanceERP];'));
    text = text.replaceAll('USE [SecureFinanceERP];', 'USE ' + ident(database) + ';')
      .replaceAll("SUSER_ID(N'securefinance_app')", `SUSER_ID(${lit(s.appLogin)})`)
      .replaceAll('FOR LOGIN [securefinance_app]', 'FOR LOGIN ' + ident(s.appLogin));
    const code = text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/--[^\r\n]*/g, '');
    assert(!/\b(?:CREATE|ALTER|DROP)\s+(?:DATABASE|LOGIN|SERVER)\b/i.test(code), file);
    for (const m of code.matchAll(/\bUSE\s+\[?(\w+)\]?\s*;/gi)) assert.equal(m[1], database);
    return text;
  }
  await runSql(`ALTER DATABASE ${ident(database)} SET RECOVERY ${s.recovery};
DECLARE @L sysname=(SELECT name FROM sys.database_files WHERE type=1);
DECLARE @SQL nvarchar(max)=N'ALTER DATABASE '+QUOTENAME(DB_NAME())+N' MODIFY FILE (NAME='+QUOTENAME(@L)+N',SIZE=64MB,FILEGROWTH=64MB);'; EXEC(@SQL);`, s);
  let sql = `BEGIN TRANSACTION; CREATE USER securefinance_app FOR LOGIN ${ident(s.appLogin)};\nGO\n` + render('SecureFinanceERP_Full.sql') + '\nGO\n';
  for (let n = 15; n <= 44; n++) if (n < 27 || n > 29) sql += source(n) + '\nGO\n';
  sql += `DECLARE @id int; EXEC dbo.sp_RegistrarUsuario @NombreUsuario=N'admin',@Correo=N'ldf@example.invalid',@Password=${lit(s.webPassword)},@NombreCompleto=N'Dylan - Laboratorio LDF',@UsuarioId=@id OUTPUT;
IF @id IS NULL THROW 59010,'Fallo alta del actor sintetico',1;
UPDATE dbo.Usuario SET DebeCambiarPassword=0 WHERE UsuarioId=@id;
INSERT dbo.Usuario_Rol(UsuarioId,RolId) SELECT @id,RolId FROM dbo.Rol WHERE Nombre=N'Administrador';
INSERT dbo.Rol_Permiso(RolId,PermisoId) SELECT r.RolId,p.PermisoId FROM dbo.Rol r CROSS JOIN dbo.Permiso p WHERE r.Nombre=N'Administrador' AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=r.RolId AND rp.PermisoId=p.PermisoId);
DECLARE @Opening uniqueidentifier=NEWID(); EXEC dbo.sp_AbrirKardexInventario @Opening,@id,N'P4-LDF-LAB',N'Instalacion sintetica Parte IV'; EXEC dbo.sp_HabilitarKardexInventario @Opening,@id;
EXEC sys.sp_addextendedproperty @name=N'P4.Laboratorio',@value=${lit(database)};
EXEC sys.sp_set_session_context @key=N'P3_DDL.LaboratorioConfirmado',@value=${lit(database)};
EXEC sys.sp_set_session_context @key=N'P3_DDL.TextoExactoAutorizado',@value=${lit(database)};
GO
CREATE OR ALTER FUNCTION dbo.P3_INT_Destino() RETURNS nvarchar(128) AS BEGIN RETURN CASE WHEN DB_NAME()=${lit(database)} AND CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))=${lit(expectedServer)} THEN DB_NAME() ELSE N'!NO_AUTORIZADO!' END; END;
GO\n`;
  for (const n of [60,61,62,63,70,71,72,73,74,75,76,77,78,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,50,51,52,53,54,55]) {
    sql += source(n) + '\nGO\n'; if (n === 95) sql += 'GRANT EXECUTE ON dbo.P3_INT_Destino TO P3_DDL_Escritor;\nGO\n';
  }
  sql += `INSERT dbo.Rol_Permiso(RolId,PermisoId) SELECT r.RolId,p.PermisoId FROM dbo.Rol r CROSS JOIN dbo.Permiso p WHERE r.Nombre=N'Administrador' AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=r.RolId AND rp.PermisoId=p.PermisoId); COMMIT;`;
  await runSql(sql, s);
  await install({ ...s, authorized: true, role: 'Administrador' });
  const actor = await queryJson("SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'admin'", s); s.actor = actor[0].UsuarioId;
  s.phase = 'installed-no-full'; fs.writeFileSync(outputState, JSON.stringify(s, null, 2));
  if (!simple) fs.writeFileSync(path.join(root, '.data', 'ldf-acceso.txt'), `Laboratorio aislado Parte IV\nURL: http://localhost:3004/dba/ldf\nUsuario: admin\nClave: ${s.webPassword}\nBase: ${s.database}\nArranque: npm.cmd run start:ldf:lab\n`, { flag: 'wx' });
  console.log('Laboratorio LDF instalado:', database, '\nAcceso local: .data/ldf-acceso.txt. No se ha creado FULL: prueba de cadena ausente pendiente.');
  return s;
}
module.exports = { build, state, useLab, statePath, pattern };
if (require.main === module) build().catch(e => { console.error(e.message); process.exitCode = 1; });
