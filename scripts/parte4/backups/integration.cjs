'use strict';
// Explicit operator tool. Does not run on HTTP startup or npm test.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {runSql,queryJson,lit,ident}=require('../ldf/sqlcmd.cjs');
const o={server:'localhost',expectedServer:'9U8ICS2VLMRUE',database:'SecureFinanceERP',timeout:240000};
const state='.data/p4-integration.json';
const sql=require('mssql'),{randomBytes,randomUUID}=require('node:crypto'),os=require('node:os');
require('dotenv').config({quiet:true});
const worker=require('../../../src/modules/dba/backups/worker');
const {withRestoredAuthorization}=require('../ldf/restored-copy.cjs');
const reportPath='.data/p4-lab-results.json';
async function laboratory(){
 if(fs.existsSync(reportPath))fs.renameSync(reportPath,reportPath+'.previous-'+Date.now());
 const s=JSON.parse(fs.readFileSync(state)),q={...o,database:s.target};
 assert.match(s.target,/^SecureFinanceERP_LDF_Rehearsal_\d{14}$/);
 const report={startedUTC:new Date().toISOString(),database:q.database,checks:[]};
 const save=()=>fs.writeFileSync(reportPath,JSON.stringify(report,null,2));
 const check=async(name,task)=>{const detail=await task();report.checks.push({name,result:'PASS',detail});save();console.log('PASS',name);return detail;};
 const before=await snapshot(q),definitions=await queryJson('SELECT object_id O,definition D FROM sys.sql_modules ORDER BY object_id',q);
 const privateFile=path.join(os.tmpdir(),'sf-uc13-lab-'+s.target+'.json');
 assert(!fs.existsSync(privateFile),'Existing trial: inspect before retry');
 const credentials={worker:'sf_uc13_trial_'+Date.now(),ldf:'sf_uc14_trial_'+Date.now(),password:randomBytes(36).toString('base64url')+'aA1!'};
 fs.writeFileSync(privateFile,JSON.stringify(credentials),{flag:'wx'});s.privateFile=privateFile;fs.writeFileSync(state,JSON.stringify(s,null,2));
 const pools=[];
 const connect=async(user,password)=>{const p=await new sql.ConnectionPool({server:process.env.DB_SERVER,port:Number(process.env.DB_PORT||1433),database:q.database,user,password,pool:{max:1,min:1},requestTimeout:240000,options:{encrypt:true,trustServerCertificate:true,useUTC:true}}).connect();pools.push(p);return p;};
 try{await withRestoredAuthorization({...q,authorized:true,sourceDatabase:o.database,databaseGuid:s.copy.G,evidenceName:'p4-copy-authorization-'+Date.now()},async()=>{
  await check('Incremental install twice with active DDL capture',async()=>{
   const ddl=fs.readFileSync('database/parte4/backups/01_backups.sql','utf8').replace(/^:ON ERROR EXIT\s*$/mg,'');
   await runSql('BEGIN TRANSACTION;\n'+ddl+'\nCOMMIT;',q);await runSql('BEGIN TRANSACTION;\n'+ddl+'\nCOMMIT;',q);
   await runSql(`UPDATE dbo.P4_LDF_Configuracion SET BaseDatos=DB_NAME(),DatabaseGuid=CONVERT(uniqueidentifier,${lit(s.copy.G)}) WHERE Id=1;
INSERT dbo.BackupsConfig(Id,Ruta) VALUES(1,${lit(s.BackupPath+'\\')});
INSERT dbo.Rol_Permiso(RolId,PermisoId) SELECT r.RolId,p.PermisoId FROM dbo.Rol r CROSS JOIN dbo.Permiso p WHERE r.Nombre=N'Administrador' AND p.Codigo LIKE 'DBA_BACKUPS_%' AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso x WHERE x.RolId=r.RolId AND x.PermisoId=p.PermisoId);`,q);
  });
  await check('Separate trial identities and least privilege deployment',async()=>{
   for(const login of [credentials.worker,credentials.ldf])await runSql(`CREATE LOGIN ${ident(login)} WITH PASSWORD=${lit(credentials.password)},CHECK_POLICY=ON,DEFAULT_DATABASE=${ident(q.database)};`,{...q,database:'master'});
   await runSql(`CREATE USER ${ident(credentials.worker)} FOR LOGIN ${ident(credentials.worker)};CREATE USER ${ident(credentials.ldf)} FOR LOGIN ${ident(credentials.ldf)}; GRANT EXECUTE ON dbo.P4_LDF_RespaldarLog TO ${ident(credentials.ldf)};`,q);
   let permissions=fs.readFileSync('database/parte4/backups/02_permissions.sql','utf8').replace(/^:ON ERROR EXIT\s*$/mg,'');
   for(const [k,v] of Object.entries({ErpDatabase:q.database,WebUser:process.env.DB_USER,WorkerLogin:credentials.worker,WorkerUser:credentials.worker}))permissions=permissions.replaceAll('$('+k+')',v);
   await runSql(permissions,q);
  });
  const wp=await connect(credentials.worker,credentials.password),lp=await connect(credentials.ldf,credentials.password),app=await connect(process.env.DB_USER,process.env.DB_PASSWORD);
  const actor=(await queryJson("SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'admin' AND Activo=1",q))[0].UsuarioId;
  const backup=async(type)=>wp.request().input('TipoBackup',sql.VarChar(4),type).input('RutaDestino',sql.NVarChar(240),s.BackupPath+'\\').execute('dbo.sp_EjecutarBackupEstrategico');
  const ldf=()=>lp.request().input('ActorUsuarioId',sql.Int,actor).input('OperacionId',sql.UniqueIdentifier,randomUUID()).execute('dbo.P4_LDF_RespaldarLog');
  await check('Permissions reject web backup and worker administrative roles',async()=>{
   await assert.rejects(()=>app.request().query('SELECT * FROM dbo.BackupsJob'),e=>e.number===229);
   await assert.rejects(()=>app.request().input('TipoBackup',sql.VarChar(4),'FULL').input('RutaDestino',sql.NVarChar(240),s.BackupPath+'\\').execute('dbo.sp_EjecutarBackupEstrategico'),e=>e.number===229);
   const p=(await wp.request().query("SELECT IS_SRVROLEMEMBER('sysadmin') SA,IS_ROLEMEMBER('db_owner') Owner")).recordset[0];assert.equal(p.SA,0);assert.equal(p.Owner,0);
  });
  await check('Prior SQL modules and signed LDF unchanged',async()=>{const after=await queryJson('SELECT object_id O,definition D FROM sys.sql_modules ORDER BY object_id',q);for(const d of definitions)assert.equal(after.find(a=>a.O===d.O)?.D,d.D);assert.equal((await queryJson("SELECT COUNT(*) N FROM sys.crypt_properties WHERE major_id IN(OBJECT_ID('dbo.P4_LDF_Consultar'),OBJECT_ID('dbo.P4_LDF_RespaldarLog'))",q))[0].N,3);});
  await runSql('CREATE TABLE dbo.P4_UC13_PitrProbe(Id int NOT NULL PRIMARY KEY,Label nvarchar(100) NOT NULL);',q);
  for(const t of ['FULL','DIFF','LOG'])await check(t+' CHECKSUM and VERIFYONLY on real SQL',async()=>{const r=(await backup(t)).recordset[0];assert.equal(r.Estado,'VERIFICADO');return r;});
  await check('Mutual exclusion UC13 and UC14, independent worker lock, error release',async()=>{
   const lock="DECLARE @r int;EXEC @r=sys.sp_getapplock @Resource=N'SecureFinanceERP:BACKUP',@LockMode='Exclusive',@LockOwner='Session',@DbPrincipal='public',@LockTimeout=0;SELECT @r Code;";
   const release="EXEC sys.sp_releaseapplock @Resource=N'SecureFinanceERP:BACKUP',@LockOwner='Session',@DbPrincipal='public';";
   assert((await lp.request().query(lock)).recordset[0].Code>=0);try{await assert.rejects(()=>backup('LOG'),e=>e.number===58002);}finally{await lp.request().query(release);}
   assert((await wp.request().query(lock)).recordset[0].Code>=0);try{await assert.rejects(ldf,e=>e.number===59013);}finally{await wp.request().query(release);}
   const r=(await ldf()).recordset[0];assert.equal(r.Estado,'CONFIRMADO');
   assert.equal((await wp.request().query("SELECT APPLOCK_MODE('public','SecureFinanceERP:BACKUP','Session') Mode")).recordset[0].Mode,'NoLock');return {ldfOperation:r.OperacionId,ldfMedia:r.Archivo};
  });
  const env={BACKUPS_ROOT:s.BackupPath+'\\',BACKUPS_RESTORE_ROOT:s.DataPath};
  const submit=async(type,extra={})=>{const id=randomUUID(),r=app.request().input('ActorUsuarioId',sql.Int,actor).input('Id',sql.UniqueIdentifier,id).input('Tipo',sql.VarChar(10),type);for(const [k,t,v] of Object.values(extra))r.input(k,t,v);await r.execute('dbo.sp_BackupsSolicitar');return id;};
  await check('Worker independent run, real manual queue and automatic 15 minute slot',async()=>{
   const id=await submit('LOG');await worker.run(wp,env);
   assert.equal((await queryJson(`SELECT Estado FROM dbo.BackupsJob WHERE Id=${lit(id)}`,q))[0].Estado,'COMPLETADO');
   await runSql('UPDATE dbo.BackupsSchedule SET Enabled=1,CursorUtc=DATEADD(minute,-16,SYSUTCDATETIME()) WHERE Id=1;',q);
   try{await worker.run(wp,env);const jobs=await queryJson("SELECT Tipo,Estado,Slot FROM dbo.BackupsJob WHERE Slot IS NOT NULL",q);assert(jobs.some(j=>j.Tipo==='LOG'&&j.Estado==='COMPLETADO'));return jobs;}finally{await runSql('UPDATE dbo.BackupsSchedule SET Enabled=0 WHERE Id=1;',q);}
  });
  await runSql("INSERT dbo.P4_UC13_PitrProbe VALUES(1,N'BEFORE_STOPAT'); WAITFOR DELAY '00:00:02';",q);
  const point=(await queryJson('SELECT CONVERT(varchar(19),GETDATE(),126) P',q))[0].P;
  await runSql("WAITFOR DELAY '00:00:02'; INSERT dbo.P4_UC13_PitrProbe VALUES(2,N'AFTER_STOPAT');",q);
  await check('UC14 LOG contributes to shared PITR chain',async()=>{const r=(await ldf()).recordset[0];assert.equal(r.Estado,'CONFIRMADO');return r;});
  const target='SF_Recovery_UC13_'+Date.now();
  await check('PITR verified before/after transactions in separate database',async()=>{
   const planId=await submit('PLAN',{point:['Punto',sql.VarChar(19),point],target:['Destino',sql.NVarChar(128),target]});await worker.run(wp,env);
   const job=(await queryJson(`SELECT Estado,PlanJson,Resultado FROM dbo.BackupsJob WHERE Id=${lit(planId)}`,q))[0];assert.equal(job.Estado,'COMPLETADO',job.Resultado);
   const p=JSON.parse(job.PlanJson);assert(p.chain.some(r=>r.Type==='L'&&r.Path.includes('P4_LDF_')),'LDF media missing from PITR');
   const restoreId=await submit('RESTORE',{plan:['PlanId',sql.UniqueIdentifier,planId]});await worker.run(wp,env);
   const restored=(await queryJson(`SELECT Estado,Resultado FROM dbo.BackupsJob WHERE Id=${lit(restoreId)}`,q))[0];assert.equal(restored.Estado,'COMPLETADO',restored.Resultado);
   const rows=await queryJson('SELECT Id,Label FROM dbo.P4_UC13_PitrProbe ORDER BY Id',{...q,database:target});assert.deepEqual(rows,[{Id:1,Label:'BEFORE_STOPAT'}]);
   await runSql('DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;',{...q,database:target});return {point,target,rows,chain:p.chain.map(r=>({Id:r.Id,Type:r.Type,Path:r.Path,FirstLSN:r.FirstLSN,LastLSN:r.LastLSN,Family:r.Family,Fork:r.Fork}))};
  });
  await check('Original restore rejected, request idempotence and actor SQL authorization',async()=>{
   await assert.rejects(()=>submit('PLAN',{point:['Punto',sql.VarChar(19),point],target:['Destino',sql.NVarChar(128),o.database]}),e=>e.number===58001);
   await assert.rejects(()=>app.request().input('ActorUsuarioId',sql.Int,2147483647).execute('dbo.sp_BackupsConsultar'),e=>e.number===54101);
   const id=randomUUID();for(let i=0;i<2;i++)await app.request().input('ActorUsuarioId',sql.Int,actor).input('Id',sql.UniqueIdentifier,id).input('Tipo',sql.VarChar(10),'LOG').execute('dbo.sp_BackupsSolicitar');
   assert.equal((await queryJson(`SELECT COUNT(*) N FROM dbo.BackupsJob WHERE Id=${lit(id)}`,q))[0].N,1);
  });
  await check('Six earlier modules real SQL rollback regressions',async()=>{
   await require('../../deployment/validate-original.cjs').validate(q.database,{state:{clone:q.database,source:o.database},persist:false,evidencePath:'.data/p4-six-modules.json',query:(query,db)=>queryJson(query,{...q,database:db}),exec:(query,db)=>runSql(query,{...q,database:db})});
   await runSql('BEGIN TRANSACTION;\n'+require('../../deployment/compras-operations.cjs').success+'\nROLLBACK;',q);
  });
  await check('Historical row multiset preserved except lab-only configuration binding',async()=>{const after=await snapshot(q);delete before['dbo.P4_LDF_Configuracion'];preserve(before,after);return Object.keys(before).length;});
  await check('Final CHECKDB and enabled DDL trigger',()=>runSql("DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;IF EXISTS(SELECT 1 FROM sys.triggers WHERE name='P3_DDL_CapturarEstructura' AND is_disabled=1) THROW 58010,'Trigger disabled',1;",q));
 });report.result='PASS';
 }catch(e){report.result='FAIL';report.error=e.message;throw e;}
 finally{await Promise.allSettled(pools.map(p=>p.close()));for(const login of [credentials.worker,credentials.ldf])if((await queryJson(`SELECT name FROM sys.sql_logins WHERE name=${lit(login)}`,{...o,database:'master'})).length)await runSql(`ALTER LOGIN ${ident(login)} DISABLE;`,{...o,database:'master'});report.finishedUTC=new Date().toISOString();save();}
}
async function snapshot(options){
 const tables=await queryJson('SELECT SCHEMA_NAME(schema_id) S,name N FROM sys.tables WHERE is_ms_shipped=0 ORDER BY schema_id,name',options);
 const rows=Object.fromEntries(tables.map(t=>[t.S+'.'+t.N,[]]));
 const union=tables.map(t=>`SELECT ${lit(t.S+'.'+t.N)} T,CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),(SELECT t.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES))),2) H FROM ${ident(t.S)}.${ident(t.N)} t`).join('\nUNION ALL\n');
 for(const r of await queryJson('SELECT T,H FROM ('+union+') snapshots',options))rows[r.T].push(r.H);
 for(const hashes of Object.values(rows))hashes.sort();
 return rows;
}
function preserve(before,after){for(const [t,hashes] of Object.entries(before)){const counts=new Map();for(const h of after[t]||[])counts.set(h,(counts.get(h)||0)+1);for(const h of hashes){assert(counts.get(h)>0,'Historical row changed: '+t);counts.set(h,counts.get(h)-1);}}}
async function prepare(){
 if(process.argv.includes('--new-trial')&&fs.existsSync(state))fs.renameSync(state,state+'.previous-'+Date.now());
 assert(!fs.existsSync(state),'Inspect existing state before another preparation');
 const identity=(await queryJson("SELECT DB_NAME() Db,dbo.P3_INT_Destino() DdlTarget,CONVERT(varchar(36),database_guid) G FROM sys.database_recovery_status WHERE database_id=DB_ID()",o))[0];
 assert.equal(identity.DdlTarget,o.database);
 const p=(await queryJson("SELECT CONVERT(nvarchar(1500),SERVERPROPERTY('InstanceDefaultBackupPath')) BackupPath,CONVERT(nvarchar(1500),SERVERPROPERTY('InstanceDefaultDataPath')) DataPath,CONVERT(nvarchar(1500),SERVERPROPERTY('InstanceDefaultLogPath')) LogPath",o))[0];
 const stamp=new Date().toISOString().replace(/\D/g,'').slice(0,14),target='SecureFinanceERP_LDF_Rehearsal_'+stamp;
 const backup=path.win32.join(p.BackupPath,'SecureFinanceERP_PreUC13_'+stamp+'.bak');
 const files=await queryJson('SELECT name,type,file_id FROM sys.database_files ORDER BY file_id',o);
 const s={startedUTC:new Date().toISOString(),...o,...p,target,backup,identity,checks:[]};
 fs.writeFileSync(state,JSON.stringify(s,null,2),{flag:'wx'});
 await runSql(`BACKUP DATABASE [SecureFinanceERP] TO DISK=${lit(backup)} WITH COPY_ONLY,CHECKSUM,NOINIT; RESTORE VERIFYONLY FROM DISK=${lit(backup)} WITH CHECKSUM;`,o);
 const moves=files.map(f=>'MOVE '+lit(f.name)+' TO '+lit(path.win32.join(f.type===1?p.LogPath:p.DataPath,target+'_'+f.file_id+(f.type===1?'.ldf':'.mdf')))).join(',');
 await runSql(`IF DB_ID(${lit(target)}) IS NOT NULL THROW 58010,'Target exists',1; RESTORE DATABASE ${ident(target)} FROM DISK=${lit(backup)} WITH CHECKSUM,RECOVERY,${moves};`,{...o,database:'master'});
 await runSql('DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;',{...o,database:target});
 s.checks.push('Original COPY_ONLY FULL CHECKSUM','VERIFYONLY CHECKSUM','Independent RESTORE without REPLACE','Restored CHECKDB');
 s.copy=(await queryJson("SELECT dbo.P3_INT_Destino() DdlTarget,CONVERT(varchar(36),database_guid) G,(SELECT is_disabled FROM sys.triggers WHERE name='P3_DDL_CapturarEstructura') TriggerDisabled FROM sys.database_recovery_status WHERE database_id=DB_ID()",{...o,database:target}))[0];
 assert.equal(s.copy.TriggerDisabled,false);assert.notEqual(s.copy.DdlTarget,target);
 fs.writeFileSync(state,JSON.stringify(s,null,2));console.log(JSON.stringify(s));
}
async function debugWorker(){
 const s=JSON.parse(fs.readFileSync(state)),c=JSON.parse(fs.readFileSync(s.privateFile));let p;
 try{await runSql(`ALTER LOGIN ${ident(c.worker)} ENABLE;`,{...o,database:'master'});
 p=await new sql.ConnectionPool({server:process.env.DB_SERVER,port:1433,database:s.target,user:c.worker,password:c.password,pool:{max:1,min:1},options:{encrypt:true,trustServerCertificate:true}}).connect();
 const request=p.request.bind(p);p.request=()=>{const r=request(),query=r.query.bind(r);r.query=async text=>{try{return await query(text);}catch(e){console.error('FAILED_LAB_QUERY',text);throw e;}};return r;};
 console.log(await worker.run(p,{BACKUPS_ROOT:s.BackupPath+'\\',BACKUPS_RESTORE_ROOT:s.DataPath}));
 }catch(e){console.error(JSON.stringify({message:e.message,number:e.number,line:e.lineNumber,procedure:e.procName,stack:e.stack}));throw e;}
 finally{await p?.close();await runSql(`ALTER LOGIN ${ident(c.worker)} DISABLE;`,{...o,database:'master'});}
}
async function deploy(){
 const lab=JSON.parse(fs.readFileSync(reportPath)),s=JSON.parse(fs.readFileSync(state));
 const browser=JSON.parse(fs.readFileSync('docs/parte4/integracion-final/evidencias/browser-lab.json'));
 assert.equal(lab.result,'PASS');assert.equal(browser.result,'PASS');assert.equal(lab.database,s.target);assert.equal(browser.database,s.target);
 const runtime=path.join(process.env.ProgramData||'C:/ProgramData','SecureFinanceERP','UC13');
 assert(fs.existsSync(runtime),'Run Prepare-Production.ps1 elevated first');
 const output='.data/p4-production-results.json';assert(!fs.existsSync(output),'Existing production state: stop and inspect');
 const report={startedUTC:new Date().toISOString(),database:o.database,server:o.expectedServer,checks:[],automaticSchedule:'DISABLED',runtime};
 const save=()=>fs.writeFileSync(output,JSON.stringify(report,null,2));
 const check=async(name,task)=>{const detail=await task();report.checks.push({name,result:'PASS',detail});save();console.log('PASS',name);return detail;};
 let pool,createdLogin=false;
 const login='securefinance_uc13_worker',password=randomBytes(40).toString('base64url')+'Aa1!';
 save();
 try{
  const identity=(await queryJson("SELECT dbo.P3_INT_Destino() DdlTarget,CONVERT(varchar(36),database_guid) G,(SELECT is_disabled FROM sys.triggers WHERE name='P3_DDL_CapturarEstructura') TriggerDisabled,(SELECT COUNT(*) FROM sys.objects WHERE name LIKE 'Backups%' OR name IN('sp_EjecutarBackupEstrategico','sp_BackupsConsultar','sp_BackupsSolicitar','sp_BackupsRutas')) Uc13Objects FROM sys.database_recovery_status WHERE database_id=DB_ID()",o))[0];
  assert.equal(identity.G.toLowerCase(),s.identity.G.toLowerCase());assert.equal(identity.DdlTarget,o.database);assert.equal(identity.TriggerDisabled,false);assert.equal(identity.Uc13Objects,0);
  const free=(await queryJson('SELECT DISTINCT vs.volume_mount_point Mount,CONVERT(varchar(30),vs.available_bytes) FreeBytes FROM sys.database_files f CROSS APPLY sys.dm_os_volume_stats(DB_ID(),f.file_id) vs',o));
  assert(free.every(r=>BigInt(r.FreeBytes)>10n*1024n**3n),'At least 10 GiB free required for deployment rehearsal');report.capacity=free;save();
  await check('Original CHECKDB before incremental installation',()=>runSql('DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;',o));
  const stamp=new Date().toISOString().replace(/\D/g,'').slice(0,14),target='SecureFinanceERP_PreUC13_Verify_'+stamp;
  const backup=path.win32.join(s.BackupPath,'SecureFinanceERP_PreUC13_Production_'+stamp+'.bak');
  report.backup=backup;report.verificationDatabase=target;save();
  await check('Fresh coordinated COPY_ONLY CHECKSUM, VERIFYONLY, independent restore and CHECKDB',async()=>{
   await runSql(`DECLARE @r int;EXEC @r=sys.sp_getapplock @Resource=N'SecureFinanceERP:BACKUP',@LockMode='Exclusive',@LockOwner='Session',@DbPrincipal='public',@LockTimeout=0;IF @r<0 THROW 58010,'Another backup active',1;
BACKUP DATABASE [SecureFinanceERP] TO DISK=${lit(backup)} WITH COPY_ONLY,CHECKSUM,NOINIT;RESTORE VERIFYONLY FROM DISK=${lit(backup)} WITH CHECKSUM;EXEC sys.sp_releaseapplock @Resource=N'SecureFinanceERP:BACKUP',@LockOwner='Session',@DbPrincipal='public';`,o);
   const files=await queryJson('SELECT name,type,file_id FROM sys.database_files ORDER BY file_id',o);
   const moves=files.map(f=>'MOVE '+lit(f.name)+' TO '+lit(path.win32.join(f.type===1?s.LogPath:s.DataPath,target+'_'+f.file_id+(f.type===1?'.ldf':'.mdf')))).join(',');
   await runSql(`IF DB_ID(${lit(target)}) IS NOT NULL THROW 58010,'Target exists',1;RESTORE DATABASE ${ident(target)} FROM DISK=${lit(backup)} WITH CHECKSUM,RECOVERY,${moves};`,{...o,database:'master'});
   await runSql('DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;',{...o,database:target});return {backup,target};
  });
  const before=await snapshot(o),definitions=await queryJson('SELECT object_id O,definition D FROM sys.sql_modules ORDER BY object_id',o),signatures=await queryJson('SELECT major_id,thumbprint,crypt_type FROM sys.crypt_properties ORDER BY major_id,thumbprint',o);
  fs.writeFileSync('.data/p4-original-before.json',JSON.stringify({before,definitions,signatures}),{flag:'wx'});
  await runSql(`IF SUSER_ID(${lit(login)}) IS NOT NULL THROW 58010,'Worker login already exists',1;CREATE LOGIN ${ident(login)} WITH PASSWORD=${lit(password)},CHECK_POLICY=ON,DEFAULT_DATABASE=[SecureFinanceERP];`,{...o,database:'master'});createdLogin=true;
  await check('Atomic incremental UC13 objects, dedicated permissions and Administrator role additions',async()=>{
   const ddl=fs.readFileSync('database/parte4/backups/01_backups.sql','utf8').replace(/^:ON ERROR EXIT\s*$/mg,'');
   let permissions=fs.readFileSync('database/parte4/backups/02_permissions.sql','utf8').replace(/^:ON ERROR EXIT\s*$/mg,'');for(const [k,v] of Object.entries({ErpDatabase:o.database,WebUser:process.env.DB_USER,WorkerLogin:login,WorkerUser:login}))permissions=permissions.replaceAll('$('+k+')',v);
   await runSql(`BEGIN TRANSACTION;CREATE USER ${ident(login)} FOR LOGIN ${ident(login)};\nGO\n`+ddl+'\n'+permissions+`\nUSE [SecureFinanceERP];\nINSERT dbo.BackupsConfig(Id,Ruta) VALUES(1,${lit(s.BackupPath+'\\')});
INSERT dbo.Rol_Permiso(RolId,PermisoId) SELECT r.RolId,p.PermisoId FROM dbo.Rol r CROSS JOIN dbo.Permiso p WHERE r.Nombre=N'Administrador' AND p.Codigo IN('DBA_BACKUPS_CONSULTAR','DBA_BACKUPS_EJECUTAR','DBA_BACKUPS_RESTAURAR') AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso x WHERE x.RolId=r.RolId AND x.PermisoId=p.PermisoId);
IF @@TRANCOUNT<>1 THROW 58010,'Invalid deployment transaction',1;COMMIT;`,o);
   report.installed=true;save();
  });
  await check('All historical rows, SQL modules and LDF signatures preserved',async()=>{
   preserve(before,await snapshot(o));const after=await queryJson('SELECT object_id O,definition D FROM sys.sql_modules ORDER BY object_id',o);for(const d of definitions)assert.equal(after.find(a=>a.O===d.O)?.D,d.D);
   assert.deepEqual(await queryJson('SELECT major_id,thumbprint,crypt_type FROM sys.crypt_properties ORDER BY major_id,thumbprint',o),signatures);return Object.keys(before).length+' tables checked with SHA-256 multisets';
  });
  await check('External isolated worker runtime and secrets prepared',async()=>{
   fs.mkdirSync(path.join(runtime,'logs'));fs.mkdirSync(path.join(runtime,'lib'));
   for(const f of ['worker.js','planner.js','validation.js'])fs.copyFileSync(path.join('src/modules/dba/backups',f),path.join(runtime,'lib',f));
   fs.cpSync('node_modules',path.join(runtime,'node_modules'),{recursive:true});
   const env={BACKUPS_DB_SERVER:process.env.DB_SERVER,BACKUPS_DB_PORT:process.env.DB_PORT||'1433',BACKUPS_DB_NAME:o.database,BACKUPS_DB_USER:login,BACKUPS_DB_PASSWORD:password,BACKUPS_DB_ENCRYPT:'true',BACKUPS_DB_TRUST_SERVER_CERTIFICATE:process.env.DB_TRUST_SERVER_CERTIFICATE||'false',BACKUPS_ROOT:s.BackupPath+'\\',BACKUPS_RESTORE_ROOT:s.DataPath};
   fs.writeFileSync(path.join(runtime,'backups.env'),Object.entries(env).map(([k,v])=>k+"='"+v+"'").join('\n'),{flag:'wx'});
   fs.writeFileSync(path.join(runtime,'run.cjs'),`'use strict';const fs=require('node:fs'),path=require('node:path');require('dotenv').config({path:path.join(__dirname,'backups.env'),quiet:true});const sql=require('mssql'),{config,run}=require('./lib/worker');(async()=>{let p;try{p=await new sql.ConnectionPool(config()).connect();const result=await run(p);fs.appendFileSync(path.join(__dirname,'logs','worker.jsonl'),JSON.stringify({atUTC:new Date().toISOString(),identity:require('node:os').userInfo().username,result})+'\\n');}catch(e){fs.appendFileSync(path.join(__dirname,'logs','worker.jsonl'),JSON.stringify({atUTC:new Date().toISOString(),error:e.number||e.code||e.name})+'\\n');process.exitCode=1;}finally{await p?.close();}})();`,{flag:'wx'});
   return {login,windowsIdentity:'sf_backup_runner',runtime,secretPublished:false};
  });
  pool=await new sql.ConnectionPool(worker.config({BACKUPS_DB_SERVER:process.env.DB_SERVER,BACKUPS_DB_PORT:process.env.DB_PORT||'1433',BACKUPS_DB_NAME:o.database,BACKUPS_DB_USER:login,BACKUPS_DB_PASSWORD:password,BACKUPS_DB_TRUST_SERVER_CERTIFICATE:process.env.DB_TRUST_SERVER_CERTIFICATE,DB_USER:process.env.DB_USER})).connect();
  await check('Real production worker catalog and disabled automatic policy',async()=>{const r=await worker.run(pool,{BACKUPS_ROOT:s.BackupPath+'\\',BACKUPS_RESTORE_ROOT:s.DataPath});assert.equal((await queryJson('SELECT Enabled FROM dbo.BackupsSchedule WHERE Id=1',o))[0].Enabled,false);return r;});
  await check('Production CHECKDB and original DDL policy still enabled',()=>runSql("DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;IF dbo.P3_INT_Destino()<>DB_NAME() OR EXISTS(SELECT 1 FROM sys.triggers WHERE name='P3_DDL_CapturarEstructura' AND is_disabled=1) THROW 58010,'DDL policy changed',1;",o));
  report.result='PASS';
 }catch(e){report.result='FAIL';report.error=e.message;if(createdLogin&&!report.installed)await runSql(`ALTER LOGIN ${ident(login)} DISABLE;`,{...o,database:'master'});throw e;}
 finally{await pool?.close();report.finishedUTC=new Date().toISOString();save();}
}
async function browserAuthorized(){const s=JSON.parse(fs.readFileSync(state));return withRestoredAuthorization({...o,database:s.target,authorized:true,sourceDatabase:o.database,databaseGuid:s.copy.G,evidenceName:'p4-browser-authorization-'+Date.now()},()=>require('./browser.cjs').browser(s));}
async function originalContracts(){
 assert.equal(process.env.DB_NAME,o.database);const output='.data/p4-original-web-contract.json';
 const {createBackupsService}=require('../../../src/modules/dba/backups/service'),{createLdfService}=require('../../../src/modules/dba/ldf/service');
 const db=require('../../../src/config/database'),ldfPools=require('../../../src/modules/dba/ldf/pools');
 const report=fs.existsSync(output)?JSON.parse(fs.readFileSync(output)):{atUTC:new Date().toISOString(),database:o.database,user:'admin',authentication:'SQL actor authorization; usual-password browser login still pending',jobs:[]};
 try{
  const actor=(await queryJson("SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'admin' AND Activo=1",o))[0].UsuarioId;
  const service=createBackupsService();
  if(process.argv.includes('--ldf-log')){
   report.ldfOperationId ||= randomUUID();fs.writeFileSync(output,JSON.stringify(report,null,2));
   const result=await createLdfService().backup(actor,report.ldfOperationId);assert.equal(result.Estado,'CONFIRMADO');report.ldfLog={id:result.OperacionId,state:result.Estado,backupSetId:result.BackupSetId,file:result.Archivo};
  }
  if(!process.argv.includes('--read-only')){assert(!report.jobs.length,'Existing requests: inspect rather than resubmit');for(const type of ['FULL','DIFF','LOG']){const id=randomUUID(),r=await service.submit(actor,{id,type});report.jobs.push({id,type,state:r.Estado});}}
  const dashboard=await service.dashboard(actor),ldf=await createLdfService().read(actor);
  for(const j of report.jobs){const row=dashboard.jobs.find(r=>r.Id.toLowerCase()===j.id);assert(row,'Missing production request');j.state=row.Estado;j.result=row.Resultado;}
  report.ldf={database:ldf.summary.DatabaseName,recovery:ldf.summary.RecoveryModel,vlf:ldf.vlf.Total,historyRows:ldf.backups.length};
  report.automaticPolicy=dashboard.schedule[0].Enabled;assert.equal(report.automaticPolicy,false);assert.equal(report.ldf.database,o.database);assert(report.ldf.vlf>0);
  const catalog=JSON.parse(dashboard.catalog[0].JsonData);report.catalogRows=catalog.length;report.uc14LogsInCatalog=catalog.filter(r=>r.Type==='L'&&r.Path.includes('P4_LDF_')).length;assert(report.uc14LogsInCatalog>0);
  report.result=report.jobs.every(j=>j.state==='COMPLETADO')?'PASS':'PENDING_WORKER';
  fs.writeFileSync(output,JSON.stringify(report,null,2));console.log(JSON.stringify(report));
 }finally{await db.closePool();await ldfPools.close();}
}
async function finalAudit(){
 const before=JSON.parse(fs.readFileSync('.data/p4-original-before.json'));
 preserve(before.before,await snapshot(o));const definitions=await queryJson('SELECT object_id O,definition D FROM sys.sql_modules ORDER BY object_id',o);for(const d of before.definitions)assert.equal(definitions.find(a=>a.O===d.O)?.D,d.D);
 assert.deepEqual(await queryJson('SELECT major_id,thumbprint,crypt_type FROM sys.crypt_properties ORDER BY major_id,thumbprint',o),before.signatures);
 await runSql('DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;',o);
 const policy=(await queryJson("SELECT dbo.P3_INT_Destino() DdlTarget,(SELECT is_disabled FROM sys.triggers WHERE name='P3_DDL_CapturarEstructura') TriggerDisabled,(SELECT Enabled FROM dbo.BackupsSchedule WHERE Id=1) AutoEnabled",o))[0];assert.equal(policy.DdlTarget,o.database);assert.equal(policy.TriggerDisabled,false);assert.equal(policy.AutoEnabled,false);
 let secretDenied=false,secretDenialCode;try{fs.accessSync(path.join(process.env.ProgramData,'SecureFinanceERP','UC13','backups.env'),fs.constants.R_OK);}catch(e){assert(['EACCES','EPERM'].includes(e.code));secretDenied=true;secretDenialCode=e.code;}assert(secretDenied,'Unelevated web identity can read worker secret');
 const result={atUTC:new Date().toISOString(),database:o.database,historicalTables:Object.keys(before.before).length,historicalRowsPreserved:true,previousSqlDefinitionsPreserved:true,ldfSignaturesPreserved:true,checkdb:'PASS',policy,workerSecretDeniedToUnelevatedWebIdentity:true,secretDenialCode,result:'PASS'};
 fs.writeFileSync('.data/p4-original-final-audit.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
}
async function independentLocks(){
 const s=JSON.parse(fs.readFileSync(state)),c=JSON.parse(fs.readFileSync(s.privateFile)),pools=[];
 const connect=async(login)=>{const p=await new sql.ConnectionPool({server:process.env.DB_SERVER,port:1433,database:s.target,user:login,password:c.password,pool:{max:1,min:1},options:{encrypt:true,trustServerCertificate:true}}).connect();pools.push(p);return p;};
 try{
  for(const login of [c.worker,c.ldf])await runSql(`ALTER LOGIN ${ident(login)} ENABLE;`,{...o,database:'master'});
  const p=await connect(c.worker),other=await connect(c.ldf);
  await other.request().query("DECLARE @r int;EXEC @r=sys.sp_getapplock @Resource=N'UC13_WORKER',@LockMode='Exclusive',@LockOwner='Session',@DbPrincipal='public',@LockTimeout=0;IF @r<0 THROW 58010,'Worker test lock busy',1;");
  const busy=await worker.run(p,{BACKUPS_ROOT:s.BackupPath+'\\',BACKUPS_RESTORE_ROOT:s.DataPath});assert.deepEqual(busy,{busy:true});
  const backup=(await p.request().input('TipoBackup',sql.VarChar(4),'LOG').input('RutaDestino',sql.NVarChar(240),s.BackupPath+'\\').execute('dbo.sp_EjecutarBackupEstrategico')).recordset[0];assert.equal(backup.Estado,'VERIFICADO');
  await other.request().query("EXEC sys.sp_releaseapplock @Resource=N'UC13_WORKER',@LockOwner='Session',@DbPrincipal='public';");
  const result={atUTC:new Date().toISOString(),database:s.target,secondWorker:busy,backupLockIndependent:true,backup,result:'PASS'};fs.writeFileSync('.data/p4-independent-locks.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));
 }finally{await Promise.allSettled(pools.map(p=>p.close()));for(const login of [c.worker,c.ldf])await runSql(`ALTER LOGIN ${ident(login)} DISABLE;`,{...o,database:'master'});}
}
if(require.main===module){const action=process.argv[2];(action==='prepare'?prepare():action==='lab'?laboratory():action==='debug-worker'?debugWorker():action==='browser'?browserAuthorized():action==='deploy'?deploy():action==='original-contracts'?originalContracts():action==='final-audit'?finalAudit():action==='independent-locks'?independentLocks():Promise.reject(Error('Unknown action'))).catch(e=>{console.error(e.message);process.exitCode=1;});}
module.exports={o,state,snapshot,preserve};
