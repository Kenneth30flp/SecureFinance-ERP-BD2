'use strict';
// Ejecutar con autenticacion Windows: npm run test:sql:usuarios -- localhost
// Solo crea y elimina su base temporal; no usa .env ni modifica la base de la aplicacion.
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const { readFile, writeFile, mkdtemp, rm } = require('node:fs/promises');
const { tmpdir } = require('node:os');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const execute = promisify(execFile);
async function main() {
  const instance = process.argv[2];
  if (!instance) throw new Error('Indica una instancia SQL Server de pruebas con autenticacion Windows.');
  const database = 'SecureFinanceERP_UserRolesTest_' + randomBytes(8).toString('hex');
  const directory = await mkdtemp(path.join(tmpdir(), 'securefinance-user-roles-'));
  const args = ['-S', instance, '-E', '-C', '-b', '-l', '10', '-t', '60', '-f', '65001'];
  let created = false;
  let sequence = 0;
  async function run(text) {
    const file = path.join(directory, String(sequence++) + '.sql');
    await writeFile(file, text, 'utf8');
    return (await execute('sqlcmd', [...args, '-i', file], { windowsHide: true, timeout: 90000, maxBuffer: 1024*1024 })).stdout;
  }
  try {
    await run('CREATE DATABASE [' + database + '];'); created = true;
    const full = await readFile(path.join(__dirname, '../SecureFinanceERP_Full.sql'), 'utf8');
    await run(full.replaceAll('[SecureFinanceERP]', '[' + database + ']'));
    // Los cuatro paquetes anteriores tambien se ejecutan sobre el instalador completo.
    for (const name of ['SecurityTests.sql','AuthenticationTests.sql','TransactionTests.sql','AuditTests.sql','PasswordRecoveryTests.sql','UserAdministrationTests.sql','DashboardSummaryTests.sql']) {
      const source = await readFile(path.join(__dirname, name), 'utf8');
      await run('USE [' + database + '];\nGO\n' + source.replaceAll('[SecureFinanceERP]', '[' + database + ']'));
      console.log('OK: ' + name);
    }
    const tokenSetup = "USE [" + database + "]; DECLARE @Hash VARBINARY(64)=HASHBYTES('SHA2_512',CONVERT(VARBINARY(MAX),REPLICATE('9',64))); EXEC dbo.sp_SolicitarRecuperacionPassword N'password_test',@Hash;";
    await run(tokenSetup);
    const tokenReset = "USE [" + database + "]; DECLARE @Hash VARBINARY(64)=HASHBYTES('SHA2_512',CONVERT(VARBINARY(MAX),REPLICATE('9',64))); EXEC dbo.sp_RestablecerPassword @Hash,N'Concurrent_2026!';";
    const resets = await Promise.allSettled([run(tokenReset), run(tokenReset)]);
    if (resets.filter(result => result.status === 'fulfilled').length !== 1
        || !resets.some(result => result.status === 'rejected' && /54001/.test(result.reason.stdout)))
      throw new Error('Dos solicitudes pudieron consumir el mismo token de recuperacion.');
    console.log('OK: concurrencia de recuperacion, un token permite exactamente un cambio.');
    const setup = await run("USE [" + database + "]; SET NOCOUNT ON; DECLARE @Admin INT=(SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'admin'), @Other INT=(SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'cajero'); DECLARE @Roles dbo.TipoRolUsuario; INSERT @Roles SELECT RolId FROM dbo.Rol WHERE Nombre=N'Administrador'; EXEC dbo.sp_ActualizarRolesUsuario @Admin, @Roles, @Other; SELECT CONCAT('IDS:',@Admin,':',@Other);");
    const ids = setup.match(/IDS:(\d+):(\d+)/);
    if (!ids) throw new Error('No se obtuvieron usuarios de prueba.');
    const results = await Promise.allSettled(ids.slice(1).map(id => run('USE [' + database + ']; DECLARE @Roles dbo.TipoRolUsuario; EXEC dbo.sp_ActualizarRolesUsuario ' + id + ', @Roles, ' + id + ';')));
    if (results.filter(r => r.status === 'fulfilled').length !== 1
      || !results.some(r => r.status === 'rejected' && /53003/.test(r.reason.stdout))) throw new Error('Fallo de proteccion del ultimo administrador con solicitudes concurrentes.');
    console.log('OK: concurrencia, solo una de dos revocaciones simultaneas puede completarse.');
  } finally {
    if (created) await run('USE [master]; ALTER DATABASE [' + database + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [' + database + '];');
    await rm(directory, { recursive: true, force: true });
  }
}
main().catch(error => { console.error([error.stdout, error.stderr, error.message].filter(Boolean).join('\n')); process.exitCode = 1; });
