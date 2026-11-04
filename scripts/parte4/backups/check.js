'use strict';
const {readdirSync,readFileSync}=require('node:fs');
const assert=require('node:assert/strict');
const {join}=require('node:path');
const {execFileSync}=require('node:child_process');
for(const dir of ['src/modules/dba/backups','scripts/parte4/backups','src/public/js/parte4','tests/parte4/backups']){
 for(const file of readdirSync(dir).filter(f=>f.endsWith('.js')))execFileSync(process.execPath,['--check',join(dir,file)],{stdio:'inherit'});
}
const ddl=readFileSync('database/parte4/backups/01_backups.sql','utf8');
const grants=readFileSync('database/parte4/backups/02_permissions.sql','utf8');
const worker=readFileSync('src/modules/dba/backups/worker.js','utf8');
const planner=readFileSync('src/modules/dba/backups/planner.js','utf8');
assert.match(ddl,/CREATE OR ALTER PROCEDURE dbo\.sp_EjecutarBackupEstrategico/);
for(const token of ['WITH CHECKSUM','RESTORE VERIFYONLY','NO_COMPRESSION','sp_getapplock','UX_BackupsSlot'])assert.ok(ddl.includes(token),token);
for(const permission of ['DBA_BACKUPS_CONSULTAR','DBA_BACKUPS_EJECUTAR','DBA_BACKUPS_RESTAURAR'])assert.ok(ddl.includes(permission));
assert.match(grants,/GRANT BACKUP DATABASE,BACKUP LOG/);assert.match(grants,/GRANT CREATE ANY DATABASE/);assert.match(grants,/@WebSid=@WorkerSid/);
assert.ok(!/WITH\s+REPLACE|DROP\s+DATABASE|ALTER\s+DATABASE/i.test(ddl+worker+planner));
assert.match(worker,/DB_ID\(@target\) IS NOT NULL/);assert.match(worker,/create_date=@createdAt/);
assert.match(planner,/r.Type==='L'\?'RECOVERY':'NORECOVERY'/);
if(process.platform==='win32')execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',"$allErrors=@(); Get-ChildItem scripts/parte4/backups/*.ps1 | ForEach-Object { $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors) | Out-Null; $allErrors += $errors }; if($allErrors.Count){ $allErrors; exit 1 }"],{stdio:'inherit'});
console.log('UC13: sintaxis JS/PowerShell y contratos estáticos SQL revisados; sin ejecutar SQL ni tareas.');
