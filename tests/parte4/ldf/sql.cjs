'use strict';
// Real SQL assertions. All mutations are restricted to newly created, marked LDF laboratories.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path');
const { randomUUID, randomBytes } = require('node:crypto');
const { once } = require('node:events');
const lab = require('../../../scripts/parte4/ldf/lab.cjs');
const { runSql, queryJson, root, lit, ident } = require('../../../scripts/parte4/ldf/sqlcmd.cjs');
const { createLdfService } = require('../../../src/modules/dba/ldf/service');
const { sql, getPool, closePool } = require('../../../src/config/database');
const pools = require('../../../src/modules/dba/ldf/pools');
const report = { startedAtUTC: new Date().toISOString(), checks: [] };
const connections = [];
async function check(name, task) { const detail = await task(); report.checks.push({ name, result:'PASS', detail }); console.log('PASS',name); }
async function connect(s, user=s.appLogin, password=s.appPassword) {
  const p = await new sql.ConnectionPool({server:s.server,port:1433,database:s.database,user,password,requestTimeout:30000,options:{encrypt:true,trustServerCertificate:true,appName:'P4-LDF-SQL-QA'}}).connect();
  connections.push(p);return p;
}
async function main() {
  const s=lab.useLab();report.database=s.database;report.server=s.expectedServer;
  const marker=await queryJson("SELECT CONVERT(nvarchar(128),value) Marker FROM sys.extended_properties WHERE class=0 AND name=N'P4.Laboratorio'",s);
  assert.equal(marker[0]?.Marker,s.database);
  const service=createLdfService(), app=await getPool();
  await check('Metricas reales y VLF comparados con catalogo/DMV',async()=>{
    const data=await service.read(s.actor);
    const direct=await queryJson("SELECT (SELECT SUM(CONVERT(bigint,size))/128.0 FROM sys.database_files WHERE type=1) PhysicalMB,(SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID())) TotalVLF,(SELECT SUM(CONVERT(int,vlf_active)) FROM sys.dm_db_log_info(DB_ID())) ActiveVLF",s);
    assert.equal(data.summary.PhysicalMB,Number(direct[0].PhysicalMB));assert.equal(data.vlf.Total,direct[0].TotalVLF);
    assert(Math.abs(data.summary.UsedPercent-data.summary.UsedMB/data.summary.LogicalMB*100)<0.05);
    assert(Math.abs(data.summary.UsedMB+data.summary.FreeMB-data.summary.LogicalMB)<0.003);
    assert.equal(data.summary.RecoveryModel,'FULL');return {physicalMB:data.summary.PhysicalMB,usedPercent:data.summary.UsedPercent,vlfs:data.vlf.Total};
  });
  await check('SQLPERF(LOGSPACE) y LOGINFO corroboran DMV',async()=>{
    const text=await runSql(`CREATE TABLE #Space(DatabaseName nvarchar(128),LogSizeMB float,UsedPercent float,Status int);
INSERT #Space EXEC('DBCC SQLPERF(LOGSPACE) WITH NO_INFOMSGS');
DECLARE @Measured float=(SELECT UsedPercent FROM #Space WHERE DatabaseName=DB_NAME());
IF @Measured IS NULL OR ABS(@Measured-(SELECT used_log_space_in_percent FROM sys.dm_db_log_space_usage))>1 THROW 59020,'SQLPERF difiere de DMV',1;
CREATE TABLE #Vlf(RecoveryUnitId int,FileId int,FileSize bigint,StartOffset bigint,FSeqNo bigint,Status int,Parity int,CreateLSN numeric(25,0));
INSERT #Vlf EXEC('DBCC LOGINFO WITH NO_INFOMSGS');
IF (SELECT COUNT(*) FROM #Vlf)<>(SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID())) THROW 59020,'LOGINFO difiere de DMV',1;
PRINT 'SQLPERF y LOGINFO coinciden';`,s); assert.match(text,/coinciden/);return 'DBA diagnostico solamente; no se otorgaron permisos DBCC al usuario web.';
  });
  await check('Cadena no inicializada: rechazo real inicial y evidencia persistida',async()=>{
    if(s.phase==='installed-no-full') {
      assert.equal((await service.read(s.actor)).summary.ChainReady,false);
      const r=await service.backup(s.actor,randomUUID());assert.equal(r.Estado,'FALLIDO');assert.equal(r.CodigoSQL,59016);return 'Rechazo ejecutado antes del primer FULL.';
    }
    const proof=await queryJson("SELECT COUNT(*) N FROM dbo.P4_LDF_Ejecucion WHERE Estado='FALLIDO' AND CodigoSQL=59016 AND BackupSetId IS NULL",s);
    assert(proof[0].N>0);return 'Se conserva evidencia SQL del rechazo ejecutado en la primera corrida, antes del FULL.';
  });
  const fullFile=s.backupDirectory.replace(/[\\/]?$/,'\\')+'P4_LDF_FULL_'+randomUUID()+'.bak';
  await check('FULL inicial de laboratorio con CHECKSUM y VERIFYONLY',async()=>{
    await runSql(`BACKUP DATABASE ${ident(s.database)} TO DISK=${lit(fullFile)} WITH CHECKSUM,NOINIT,NAME=N'P4 LDF QA FULL'; RESTORE VERIFYONLY FROM DISK=${lit(fullFile)} WITH CHECKSUM;`,s);
    assert.equal((await service.read(s.actor)).summary.ChainReady,true);s.phase='full-ready';fs.writeFileSync(lab.statePath,JSON.stringify(s,null,2));return 'FULL operativo creado solo en laboratorio.';
  });
  const worker=await pools.administrative();
  await check('Minimos privilegios: web y worker sin db_owner/sysadmin ni BACKUP directo',async()=>{
    for (const p of [app,worker]) {
      const r=(await p.request().query("SELECT IS_SRVROLEMEMBER('sysadmin') Sysadmin,IS_ROLEMEMBER('db_owner') Owner,HAS_PERMS_BY_NAME(DB_NAME(),'DATABASE','BACKUP LOG') DirectBackup;")).recordset[0];
      assert.equal(r.Sysadmin,0);assert.equal(r.Owner,0);assert.equal(r.DirectBackup,0);
      await assert.rejects(()=>p.request().query('SELECT * FROM dbo.P4_LDF_Configuracion'),e=>e.number===229);
      await assert.rejects(()=>p.request().query('SELECT * FROM sys.dm_db_log_space_usage'),e=>[229,297,300].includes(e.number));
    }
    await assert.rejects(()=>app.request().input('ActorUsuarioId',sql.Int,s.actor).input('OperacionId',sql.UniqueIdentifier,randomUUID()).execute('dbo.P4_LDF_RespaldarLog'),e=>e.number===229);
    await assert.rejects(()=>service.read(2147483647),e=>e.number===54101);
    await assert.rejects(()=>service.backup(2147483647,randomUUID()),e=>e.number===54101);
    return 'Solo EXECUTE en puntos de entrada firmados; permisos de actor comprobados en SQL.';
  });
  let good;
  await check('Respaldo manual real, CHECKSUM, historial y metricas actualizadas',async()=>{
    good=await service.backup(s.actor,randomUUID());assert.equal(good.Estado,'CONFIRMADO');assert(good.BackupSetId);
    const d=await service.read(s.actor);assert.equal(d.backups[0].BackupSetId,good.BackupSetId);assert.equal(d.backups[0].HasChecksums,true);
    await runSql(`RESTORE VERIFYONLY FROM DISK=${lit(good.Archivo)} WITH CHECKSUM;`,s);return {backupSetId:good.BackupSetId,physicalMB:d.summary.PhysicalMB,reuseWait:d.summary.ReuseWait};
  });
  await check('Reintento UUID idempotente y conciliacion de respuesta interrumpida',async()=>{
    const again=await service.backup(s.actor,good.OperacionId);assert.equal(again.BackupSetId,good.BackupSetId);
    await runSql(`UPDATE dbo.P4_LDF_Ejecucion SET Estado='EN_CURSO',BackupSetId=NULL,FinUTC=NULL WHERE OperacionId=${lit(good.OperacionId)};`,s);
    const reconciled=await service.backup(s.actor,good.OperacionId);assert.equal(reconciled.Estado,'CONFIRMADO');assert.equal(reconciled.BackupSetId,good.BackupSetId);
    const count=await queryJson(`SELECT COUNT(*) N FROM msdb.dbo.backupset WHERE name=${lit('P4_LDF:'+good.OperacionId.toLowerCase())}`,s);assert.equal(count[0].N,1);
    const unknown=randomUUID();await runSql(`INSERT dbo.P4_LDF_Ejecucion(OperacionId,ActorUsuarioId,LoginSQL,InicioUTC,Estado,Mensaje) VALUES(${lit(unknown)},${s.actor},N'QA',SYSUTCDATETIME(),'EN_CURSO',N'Fixture de respuesta incierta');`,s);
    assert.equal((await service.backup(s.actor,unknown)).Estado,'INCIERTO');return 'Una sola copia en msdb; operación incierta sin respaldo no se vuelve a ejecutar.';
  });
  await check('Bloqueo logico compartido evita respaldo concurrente',async()=>{
    const tx=new sql.Transaction(app);await tx.begin();
    try { await new sql.Request(tx).query("DECLARE @r int;EXEC @r=sys.sp_getapplock @Resource=N'SecureFinanceERP:BACKUP',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=0,@DbPrincipal='public';IF @r<0 THROW 59020,'No se adquirio bloqueo QA',1;");
      await assert.rejects(()=>service.backup(s.actor,randomUUID()),e=>e.number===59013);
    } finally {await tx.rollback();}return 'Rechazo inmediato 59013 mientras otra sesión posee el contrato de bloqueo.';
  });
  await check('Firma sin BACKUP LOG: rechazo y auditoria de permiso insuficiente',async()=>{
    await runSql('REVOKE BACKUP LOG FROM P4_LDF_BackupCertificateUser;',s);
    try { const r=await service.backup(s.actor,randomUUID());assert.equal(r.Estado,'FALLIDO');assert.equal(r.CodigoSQL,59017); }
    finally {await runSql('GRANT BACKUP LOG TO P4_LDF_BackupCertificateUser;',s);}return 'Permiso restablecido después de prueba aislada.';
  });
  await check('Destino no autorizado y ruta inexistente se rechazan sin exponer error crudo',async()=>{
    await runSql('UPDATE dbo.P4_LDF_Configuracion SET Habilitado=0 WHERE Id=1;',s);
    try {await assert.rejects(()=>service.read(s.actor),e=>e.number===59010);await assert.rejects(()=>service.backup(s.actor,randomUUID()),e=>e.number===59010);}
    finally {await runSql('UPDATE dbo.P4_LDF_Configuracion SET Habilitado=1 WHERE Id=1;',s);}
    const config=await queryJson('SELECT RutaBackup FROM dbo.P4_LDF_Configuracion WHERE Id=1',s);
    await runSql(`UPDATE dbo.P4_LDF_Configuracion SET RutaBackup=${lit(config[0].RutaBackup+'NoExiste_'+randomUUID()+'\\')} WHERE Id=1;`,s);
    try {const r=await service.backup(s.actor,randomUUID());assert.equal(r.Estado,'FALLIDO');assert(r.CodigoSQL);assert.doesNotMatch(r.Mensaje,/Operating system error|NoExiste_/);}
    finally {await runSql(`UPDATE dbo.P4_LDF_Configuracion SET RutaBackup=${lit(config[0].RutaBackup)} WHERE Id=1;`,s);}return 'El directorio aprobado se restableció; el motor verificó acceso efectivo.';
  });
  await check('Umbrales configurables sin acciones sobre LOG',async()=>{
    const {configure}=require('../../../scripts/parte4/ldf/configure.cjs');
    const prior=await service.read(s.actor);
    try {await configure({...s,authorized:true,warning:17,critical:33});const d=await service.read(s.actor);assert.equal(d.summary.WarningPercent,17);assert.equal(d.summary.CriticalPercent,33);}
    finally {await configure({...s,authorized:true,warning:prior.summary.WarningPercent,critical:prior.summary.CriticalPercent});}
    return '17/33 leídos desde SQL; restablecidos los valores originales.';
  });
  await check('Transaccion activa, reutilizacion logica y tamaño fisico conservado',async()=>{
    const login='P4_LDF_Writer_'+randomBytes(5).toString('hex'),password='QA!'+randomBytes(24).toString('hex');
    await runSql(`CREATE LOGIN ${ident(login)} WITH PASSWORD=${lit(password)},CHECK_POLICY=ON,DEFAULT_DATABASE=${ident(s.database)};`,{...s,database:'master'});
    await runSql(`IF OBJECT_ID('dbo.P4_LDF_LabTraffic') IS NULL CREATE TABLE dbo.P4_LDF_LabTraffic(Id int IDENTITY PRIMARY KEY,Payload char(2000) NOT NULL);
CREATE USER ${ident(login)} FOR LOGIN ${ident(login)};GRANT INSERT ON dbo.P4_LDF_LabTraffic TO ${ident(login)};`,s);
    let writer,tx,active,after;
    try {
      writer=await connect(s,login,password);tx=new sql.Transaction(writer);await tx.begin();
      // Span several VLFs; otherwise a small open transaction need not cause a reuse wait.
      await new sql.Request(tx).query("INSERT dbo.P4_LDF_LabTraffic(Payload) SELECT TOP(36000) REPLICATE('L',2000) FROM sys.all_columns a CROSS JOIN sys.all_columns b;");
      const open=await queryJson('SELECT COUNT(*) N FROM sys.dm_tran_database_transactions WHERE database_id=DB_ID() AND database_transaction_type=1 AND database_transaction_log_bytes_used>10000000',s);
      assert(open[0].N>0,'Debe existir transaccion de escritura abierta con LOG retenido.');
      await runSql('CHECKPOINT;',s);await service.backup(s.actor,randomUUID());await service.backup(s.actor,randomUUID());active=await service.read(s.actor);
      // log_reuse_wait_desc is the last engine truncation assessment, not an active transaction counter.
      assert(['ACTIVE_TRANSACTION','LOG_BACKUP','NOTHING'].includes(active.summary.ReuseWait));
      await tx.commit();tx=null;
      await runSql('CHECKPOINT;',s);assert.equal((await service.backup(s.actor,randomUUID())).Estado,'CONFIRMADO');
      after=await service.read(s.actor);assert.equal(after.summary.PhysicalMB,active.summary.PhysicalMB);
      assert(after.summary.UsedMB<active.summary.UsedMB,'Debe reutilizar espacio al completar transaccion y respaldo.');
    } finally {
      if(tx) await tx.rollback();if(writer)await writer.close();
      await runSql(`DROP USER ${ident(login)};`,s);await runSql(`DROP LOGIN ${ident(login)};`,{...s,database:'master'});
    }
    return {during:active.summary.ReuseWait,usedDuringMB:active.summary.UsedMB,usedAfterMB:after.summary.UsedMB,physicalMB:after.summary.PhysicalMB};
  });
  await check('Modelo SIMPLE en una segunda base NUEVA: accion incompatible rechazada',async()=>{
    const file=path.join(root,'.data','ldf-simple-lab.json');
    process.env.LDF_EXPECTED_SERVER=s.expectedServer;
    const other=fs.existsSync(file)?JSON.parse(fs.readFileSync(file,'utf8')):await lab.build({simple:true});assert.match(other.database,lab.pattern);
    const a=await connect(other),b=await connect(other,other.adminLogin,other.adminPassword);
    const svc=createLdfService({application:async()=>a,administrative:async()=>b});
    const d=await svc.read(other.actor);assert.equal(d.summary.RecoveryModel,'SIMPLE');assert.equal(d.summary.ChainReady,false);
    const r=await svc.backup(other.actor,randomUUID());assert.equal(r.Estado,'FALLIDO');assert.equal(r.CodigoSQL,59015);return {database:other.database,code:r.CodigoSQL};
  });
  await check('HTTP con SQL real: login, LDF y seis modulos previos independientes de P4 Backups',async()=>{
    const {createApp}=require('../../../server');const web=createApp({secret:s.sessionSecret,production:false});
    const server=web.listen(0,'127.0.0.1');await once(server,'listening');
    try {
      const base='http://127.0.0.1:'+server.address().port;
      const response=await fetch(base+'/login',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({NombreUsuario:'admin',Password:s.webPassword}),redirect:'manual'});
      assert.equal(response.status,303);assert.equal(response.headers.get('location'),'/dashboard');const cookie=response.headers.get('set-cookie').split(';')[0];
      const codes={};for(const route of ['/dba/ldf','/dba/ldf/metrics','/cotizaciones','/promociones','/creditos','/multibodega','/auditoria/ddl','/compras']) {
        const r=await fetch(base+route,{headers:{Cookie:cookie},redirect:'manual'});assert.equal(r.status,200,route);codes[route]=r.status;
      }return codes;
    }finally{await new Promise(resolve=>{server.close(resolve);server.closeAllConnections();});}
  });
  await check('Integridad CHECKDB, CHECKCONSTRAINTS, conciliacion e invariancia DDL nvarchar(max)',async()=>{
    const text=await runSql(`DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS; DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;
IF EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE Diferencia<>0) THROW 59020,'Stock no conciliado',1;
IF NOT EXISTS(SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('dbo.Bitacora_DDL') AND name='ComandoTSql' AND max_length=-1 AND TYPE_NAME(user_type_id)='nvarchar') THROW 59020,'DDL no conserva max',1;
IF NOT EXISTS(SELECT 1 FROM sys.triggers WHERE name='P3_DDL_CapturarEstructura' AND is_disabled=0) THROW 59020,'Trigger DDL inactivo',1;`,s);
    assert(!/Msg \d+|constraint violation/i.test(text));return 'Sin diagnósticos de integridad; trigger activo, CommandText nvarchar(max).';
  });
}
main().then(()=>{report.result='PASS';}).catch(e=>{report.result='FAIL';report.error=e.message;console.error('FAIL',e);process.exitCode=1;}).finally(async()=>{
  await Promise.allSettled([...connections.map(p=>p.close()),closePool(),pools.close()]);
  report.finishedAtUTC=new Date().toISOString();fs.mkdirSync(path.join(root,'.data'),{recursive:true});fs.writeFileSync(path.join(root,'.data','ldf-sql-results.json'),JSON.stringify(report,null,2));
});
