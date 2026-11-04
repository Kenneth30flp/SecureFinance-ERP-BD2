'use strict';
// Optional deeper validation: restore the laboratory FULL + LOG chain to a NEW database, never REPLACE.
const assert=require('node:assert/strict'),path=require('node:path'),fs=require('node:fs');
const {randomBytes}=require('node:crypto');
const lab=require('../../../scripts/parte4/ldf/lab.cjs');
const {runSql,queryJson,root,lit,ident}=require('../../../scripts/parte4/ldf/sqlcmd.cjs');
async function main(){
 const s=lab.state();assert.match(s.database,lab.pattern);
 const full=(await queryJson(`SELECT TOP(1) b.backup_set_id Id,CONVERT(varchar(30),b.last_lsn) LastLSN,m.physical_device_name Path
FROM msdb.dbo.backupset b JOIN msdb.dbo.backupmediafamily m ON m.media_set_id=b.media_set_id
WHERE b.database_guid=(SELECT database_guid FROM sys.database_recovery_status WHERE database_id=DB_ID()) AND b.type='D' AND b.name=N'P4 LDF QA FULL' AND b.backup_finish_date IS NOT NULL ORDER BY b.backup_set_id DESC`,s))[0];assert(full,'Ejecuta primero test:sql:ldf.');
 const logs=await queryJson(`SELECT b.backup_set_id Id,m.physical_device_name Path FROM msdb.dbo.backupset b JOIN msdb.dbo.backupmediafamily m ON m.media_set_id=b.media_set_id
WHERE b.database_guid=(SELECT database_guid FROM sys.database_recovery_status WHERE database_id=DB_ID()) AND b.last_recovery_fork_guid=(SELECT recovery_fork_guid FROM sys.database_recovery_status WHERE database_id=DB_ID())
AND b.type='L' AND b.is_copy_only=0 AND b.backup_finish_date IS NOT NULL AND b.last_lsn>CONVERT(numeric(25,0),${lit(full.LastLSN)}) ORDER BY b.backup_set_id`,s);assert(logs.length,'Falta LOG posterior al FULL.');
 const target='SecureFinanceERP_P4_LDF_Restore_'+new Date().toISOString().replace(/\D/g,'').slice(0,14)+'_'+randomBytes(4).toString('hex');
 const paths=(await queryJson("SELECT CONVERT(nvarchar(1500),SERVERPROPERTY('InstanceDefaultDataPath')) DataPath,CONVERT(nvarchar(1500),SERVERPROPERTY('InstanceDefaultLogPath')) LogPath",{...s,database:'master'}))[0];
 const files=await queryJson('SELECT name, type FROM sys.database_files ORDER BY file_id',s);assert.equal(files.length,2);
 const move=files.map(f=>'MOVE '+lit(f.name)+' TO '+lit(path.win32.join(f.type===1?paths.LogPath:paths.DataPath,target+(f.type===1?'.ldf':'.mdf')))).join(',');
 await runSql(`IF DB_ID(${lit(target)}) IS NOT NULL THROW 59010,'Destino restore existente',1;
RESTORE DATABASE ${ident(target)} FROM DISK=${lit(full.Path)} WITH NORECOVERY,${move};
${logs.map(l=>`RESTORE LOG ${ident(target)} FROM DISK=${lit(l.Path)} WITH NORECOVERY;`).join('\n')}
RESTORE DATABASE ${ident(target)} WITH RECOVERY;`,{...s,database:'master',timeout:240000});
 await runSql('DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;',{...s,database:target});
 const result={atUTC:new Date().toISOString(),source:s.database,restoredTo:target,fullBackupId:full.Id,logBackupIds:logs.map(l=>l.Id),result:'PASS',integrity:'CHECKDB sin errores',note:'Base nueva; sin REPLACE. La identidad restaurada no queda autorizada para el módulo LDF.'};
 fs.writeFileSync(path.join(root,'.data/ldf-restore-results.json'),JSON.stringify(result,null,2));console.log('PASS FULL +',logs.length,'LOG restaurados en',target);
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
