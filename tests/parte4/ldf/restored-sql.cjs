'use strict';
// Real SQL regression on an explicitly authorized restored ERP copy only. No original writes.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
require('dotenv').config({quiet:true});
const {runSql,queryJson,lit,ident,root}=require('../../../scripts/parte4/ldf/sqlcmd.cjs');
const {withRestoredAuthorization}=require('../../../scripts/parte4/ldf/restored-copy.cjs');
const {install}=require('../../../scripts/parte4/ldf/install.cjs');
const {createLdfService}=require('../../../src/modules/dba/ldf/service');
const sql=require('mssql');
const report={startedAtUTC:new Date().toISOString(),checks:[]};
const pools=[];
let trialActivationAttempted=false;
const statePath=(flag,fallback)=>path.resolve(root,process.argv.find(a=>a.startsWith(flag+'='))?.slice(flag.length+1)||fallback);
const backupState=statePath('--backup-state','.data/ldf-original-backup-result.json');
const trialState=statePath('--trial-state','.data/ldf-original-trial-private.json');
async function check(name,task){const detail=await task();report.checks.push({name,result:'PASS',detail});console.log('PASS',name);}
async function snapshot(o){
 const tables=await queryJson("SELECT SCHEMA_NAME(schema_id) S,name N FROM sys.tables WHERE is_ms_shipped=0 ORDER BY schema_id,name",o);
 const rows=Object.fromEntries(tables.map(t=>[t.S+'.'+t.N,[]]));
 const union=tables.map(t=>`SELECT ${lit(t.S+'.'+t.N)} T,CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),(SELECT t.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES))),2) H FROM ${ident(t.S)}.${ident(t.N)} t`).join('\nUNION ALL\n');
 for(const r of await queryJson('SELECT T,H FROM ('+union+') snapshots',o))rows[r.T].push({H:r.H});
 return rows;
}
function preserve(before,after){
 for(const [table,rows] of Object.entries(before)){
  const counts=new Map();for(const r of after[table]||[])counts.set(r.H,(counts.get(r.H)||0)+1);
  for(const r of rows){assert((counts.get(r.H)||0)>0,'Historical row modified/lost: '+table);counts.set(r.H,counts.get(r.H)-1);}
 }
}
async function main(){
 assert(process.argv.includes('--authorize-restored-copy'),'Explicit command authorization required');
 const b=JSON.parse(fs.readFileSync(backupState));
 const s=JSON.parse(fs.readFileSync(trialState));
 assert.equal(s.database,b.target);assert.equal(s.expectedServer,b.expectedServer);
 const o={server:s.server,expectedServer:s.expectedServer,database:s.database,timeout:240000};
 report.database=o.database;
 const guid=(await queryJson('SELECT CONVERT(varchar(36),database_guid) G FROM sys.database_recovery_status WHERE database_id=DB_ID()',o))[0].G;
 await check('Original FULL remains verifiable',()=>runSql(`RESTORE VERIFYONLY FROM DISK=${lit(b.backup)} WITH CHECKSUM;`,{...o,database:'master'}));
 const before=await snapshot(o);
 const definitions=await queryJson("SELECT object_id O,definition D FROM sys.sql_modules ORDER BY object_id",o);
 const authorization={...o,authorized:true,sourceDatabase:b.database,databaseGuid:guid,evidenceName:'ldf-restored-authorization-'+Date.now()};
 await withRestoredAuthorization(authorization,async()=>{
  trialActivationAttempted=true;
  await runSql(`ALTER LOGIN ${ident(s.adminLogin)} ENABLE;`,{...o,database:'master'});
  await check('Official LDF installer completes with DDL capture enabled',()=>install({...o,adminLogin:s.adminLogin,backupDirectory:s.backupDirectory,authorized:true,role:'Administrador'}));
  const connect=async(user,password)=>{const p=await new sql.ConnectionPool({server:process.env.DB_SERVER,port:Number(process.env.DB_PORT||1433),database:o.database,user,password,options:{encrypt:true,trustServerCertificate:true},requestTimeout:30000}).connect();pools.push(p);return p;};
  const app=await connect(process.env.DB_USER,process.env.DB_PASSWORD),worker=await connect(s.adminLogin,s.password);
  const actor=(await queryJson("SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'admin' AND Activo=1",o))[0].UsuarioId;
  const service=createLdfService({application:async()=>app,administrative:async()=>worker});
  await check('LDF metrics, VLF and SQL history match real catalogs',async()=>{
   const d=await service.read(actor),direct=(await queryJson('SELECT (SELECT SUM(CONVERT(bigint,size))/128.0 FROM sys.database_files WHERE type=1) MB,(SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID())) VLF',o))[0];
   assert.equal(d.summary.PhysicalMB,Number(direct.MB));assert.equal(d.vlf.Total,direct.VLF);
   report.metrics={summary:d.summary,vlf:d.vlf,backupRows:d.backups.length,historyRows:d.history.length};return report.metrics;
  });
  await check('Effective least privileges and invalid actor rejection',async()=>{
   for(const p of [app,worker]){
    const r=(await p.request().query("SELECT IS_SRVROLEMEMBER('sysadmin') SA,IS_ROLEMEMBER('db_owner') Owner,HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','BACKUP LOG') DirectBackup")).recordset[0];
    assert.equal(r.SA,0);assert.equal(r.Owner,0);assert.equal(r.DirectBackup,0);
    await assert.rejects(()=>p.request().query('SELECT * FROM dbo.P4_LDF_Configuracion'),e=>e.number===229);
    await assert.rejects(()=>p.request().query('SELECT * FROM sys.dm_db_log_space_usage'),e=>[229,297,300].includes(e.number));
   }
   assert.equal((await worker.request().query("SELECT HAS_DBACCESS('SecureFinanceERP') A")).recordset[0].A,0);
   await assert.rejects(()=>service.read(2147483647),e=>e.number===54101);
   await assert.rejects(()=>app.request().input('ActorUsuarioId',sql.Int,actor).input('OperacionId',sql.UniqueIdentifier,randomUUID()).execute('dbo.P4_LDF_RespaldarLog'),e=>e.number===229);
   await assert.rejects(()=>app.request().query('CREATE TABLE dbo.P4_Unauthorized (Id int)'),e=>[229,262].includes(e.number));
   const grants=await queryJson(`SELECT permission_name P FROM sys.server_permissions WHERE grantee_principal_id=SUSER_ID(${lit(s.adminLogin)})`,{...o,database:'master'});
   assert(grants.every(r=>r.P==='CONNECT SQL'));
   assert.equal((await queryJson(`SELECT COUNT(*) N FROM sys.server_role_members WHERE member_principal_id=SUSER_ID(${lit(s.adminLogin)})`,{...o,database:'master'}))[0].N,0);
  });
  await check('LDF signatures, certificates and actor role permissions',()=>runSql(`
IF (SELECT COUNT(*) FROM sys.crypt_properties WHERE major_id IN(OBJECT_ID('dbo.P4_LDF_Consultar'),OBJECT_ID('dbo.P4_LDF_RespaldarLog')))<>3 THROW 59020,'Missing LDF signatures',1;
IF EXISTS(SELECT 1 FROM sys.certificates WHERE name IN('P4_LDF_ReadCertificate','P4_LDF_BackupCertificate') AND pvt_key_encryption_type_desc<>'NO_PRIVATE_KEY') THROW 59020,'Private signing key retained',1;
IF (SELECT COUNT(*) FROM dbo.Rol_Permiso rp JOIN dbo.Rol r ON r.RolId=rp.RolId JOIN dbo.Permiso p ON p.PermisoId=rp.PermisoId WHERE r.Nombre=N'Administrador' AND p.Codigo IN('DBA_LDF_CONSULTAR','DBA_LDF_RESPALDAR_LOG'))<>2 THROW 59020,'Missing application permissions',1;
`,o));
  await check('Six DDL events retain exact long Unicode commands and attribution',async()=>{
   const commands=['CREATE TABLE dbo.P4_DDL_Exact (Id int)','ALTER TABLE dbo.P4_DDL_Exact ADD Label nvarchar(10)','DROP TABLE dbo.P4_DDL_Exact',"CREATE PROCEDURE dbo.P4_DDL_ExactProc AS SELECT N'áé 中文 & < >' V; /*"+'texto Unicode á '.repeat(1000)+'*/','ALTER PROCEDURE dbo.P4_DDL_ExactProc AS SELECT 2 V','DROP PROCEDURE dbo.P4_DDL_ExactProc'];
   const body=commands.map(cmd=>`SET @Cut=(SELECT ISNULL(MAX(BitacoraDdlId),0) FROM dbo.Bitacora_DDL); EXEC(${lit(cmd)});
IF NOT EXISTS(SELECT 1 FROM dbo.Bitacora_DDL WHERE BitacoraDdlId>@Cut AND CONVERT(varbinary(max),ComandoTSql)=CONVERT(varbinary(max),${lit(cmd)}) AND LoginOriginal=ORIGINAL_LOGIN() AND BaseDatos=DB_NAME() AND EstadoComando='EXACTO_EVENTDATA') THROW 59020,'DDL text or attribution mismatch',1;`).join('\n');
   return runSql('DECLARE @Cut bigint;\n'+body,o);
  });
  await check('Revoked binding rejects DDL with 54993 and rolls back',()=>runSql(`BEGIN TRY BEGIN TRANSACTION;
EXEC sys.sp_updateextendedproperty @name=N'P3.Despliegue.Autorizacion',@value=N'REVOKED_QA';
EXEC(N'CREATE TABLE dbo.P4_MustNotExist (Id int)');
THROW 59020,'Unauthorized DDL accepted',1;
END TRY BEGIN CATCH DECLARE @E int=ERROR_NUMBER();IF XACT_STATE()<>0 ROLLBACK;IF @E<>54993 THROW;END CATCH;
IF OBJECT_ID('dbo.P4_MustNotExist') IS NOT NULL OR dbo.P3_INT_Destino()<>DB_NAME() THROW 59020,'Unauthorized DDL rollback failed',1;`,o));
  await check('Existing quote, promotion, credit, warehouse and DDL workflows with rollback',()=>require('../../../scripts/deployment/validate-original.cjs').validate(o.database,{state:{clone:o.database,source:b.database},persist:false,evidencePath:path.join(root,'.data/ldf-six-modules-validation.json'),query:(q,db)=>queryJson(q,{...o,database:db}),exec:(q,db)=>runSql(q,{...o,database:db})}));
  await check('Purchases: approval, partial/full receipts, replay, stock and valuation with rollback',()=>runSql('BEGIN TRANSACTION;\n'+require('../../../scripts/deployment/compras-operations.cjs').success+'\nROLLBACK;',o));
  await check('Historical rows and previous role memberships preserved',async()=>{preserve(before,await snapshot(o));return Object.keys(before).length+' preexisting tables checked';});
  await check('Previous SQL modules including trigger/function unchanged',async()=>{
   const after=await queryJson('SELECT object_id O,definition D FROM sys.sql_modules ORDER BY object_id',o);
   for(const d of definitions)assert.equal(after.find(a=>a.O===d.O)?.D,d.D,'Previous module changed: '+d.O);
  });
  await check('CHECKDB, constraints, reconciliation and enabled trigger',()=>runSql(`DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS; DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;
IF EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE Diferencia<>0) THROW 59020,'Stock mismatch',1;
IF NOT EXISTS(SELECT 1 FROM sys.triggers WHERE name='P3_DDL_CapturarEstructura' AND is_disabled=0) THROW 59020,'DDL capture disabled',1;`,o));
 });
 await check('Rehearsal authorization removed; copied source policy restored',()=>runSql(`IF dbo.P3_INT_Destino()=DB_NAME() THROW 59020,'Copy still authorized',1;`,o));
 report.result='PASS';report.logBackupTest='Not executed';report.originalChanged=false;
}
main().catch(e=>{report.result='FAIL';report.error=e.message;console.error('FAIL',e.message);process.exitCode=1;}).finally(async()=>{
 await Promise.allSettled(pools.map(p=>p.close()));
 if(trialActivationAttempted)try {const s=JSON.parse(fs.readFileSync(trialState));await runSql(`ALTER LOGIN ${ident(s.adminLogin)} DISABLE;`,{...s,database:'master'});report.trialLoginDisabled=true;}catch(e){report.loginCleanupError=e.message;process.exitCode=1;}
 report.finishedAtUTC=new Date().toISOString();fs.writeFileSync(path.join(root,'.data/ldf-restored-sql-results.json'),JSON.stringify(report,null,2));
});
