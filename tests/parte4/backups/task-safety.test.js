'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {execFileSync}=require('node:child_process');
test('Windows UC13 maintenance: permanent isolated PowerShell regressions (no real tasks/accounts/SQL)',{skip:process.platform!=='win32'},()=>{
 // Only this disposable test process permits our in-memory fixtures. No Set-ExecutionPolicy.
 const text=execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'task-safety.fixtures.ps1')],{encoding:'utf8',windowsHide:true,timeout:45000});
 assert.match(text,/TASK_SAFETY_PASS/);process.stdout.write(text);
});
test('UC13/UC14 still share the same database/public exclusive Session backup lock',()=>{
 const sources=['database/parte4/backups/01_backups.sql','database/parte4/ldf/003_backup.sql'].map(p=>fs.readFileSync(p,'utf8'));
 for(const sql of sources){assert.match(sql,/@Resource\s*=\s*N?'SecureFinanceERP:BACKUP'/);assert.match(sql,/@LockMode\s*=\s*'Exclusive'/);assert.match(sql,/@LockOwner\s*=\s*'Session'/);assert.match(sql,/@DbPrincipal\s*=\s*'public'/);assert.match(sql,/sp_releaseapplock/);}
});
