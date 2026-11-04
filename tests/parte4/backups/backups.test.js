'use strict';
const {test}=require('node:test');const assert=require('node:assert/strict');
const v=require('../../../src/modules/dba/backups/validation');
const {plan,commands}=require('../../../src/modules/dba/backups/planner');
const {slots,config,inspect}=require('../../../src/modules/dba/backups/worker');
const id='12345678-1234-4234-8234-123456789012';
function row(values){return {DatabaseName:'ERP',Checksum:true,Damaged:false,RecoveryModel:'FULL',Bulk:false,Position:1,Path:'D:\\Backups\\a.bak',Family:'f',Fork:'r',FirstFork:'r',CopyOnly:false,Start:'2026-01-01T00:00:00',Finish:'2026-01-01T00:01:00',Type:'D',FirstLSN:'90071992547409930',LastLSN:'90071992547409940',CheckpointLSN:'90071992547409935',...values};}
const full=row({}),diff=row({Type:'I',BaseLSN:full.CheckpointLSN,LastLSN:'90071992547409950',Finish:'2026-01-01T01:00:00'});
const log=row({Type:'L',FirstLSN:diff.LastLSN,LastLSN:'90071992547409960',Start:'2026-01-01T02:15:00',Finish:'2026-01-01T02:16:00'});
test('UC13 valida tipos, fechas reales, destino protegido y rutas',()=>{
 for(const x of ['full','FULL;DROP',null])assert.throws(()=>v.type(x));
 for(const x of ['2026-02-30T12:00:00','2026-01-01T25:00:00','2026-01-01'])assert.throws(()=>v.point(x));
 assert.equal(v.point('2026-01-01T12:00:00'),'2026-01-01T12:00:00');
 for(const x of ['ERP','master','SF_Recovery_foo];DROP DATABASE','SF_Recovery_'])assert.throws(()=>v.target(x));
 for(const x of ['D:\\Backups\\..\\','\\\\remote\\share\\','D:\\Backups'])assert.throws(()=>v.directory(x));
 assert.equal(v.directory('D:\\Backups\\'),'D:\\Backups\\');
});
test('UC13 plan FULL/DIFF/LOG conserva LSN superiores a precisión Number',()=>{
 const p=plan([full,diff,log],'2026-01-01T02:00:00','SF_Recovery_test','ERP');assert.deepEqual(p.chain,[full,diff,log]);
 p.fileToken=id;
 const c=commands(p,[{LogicalName:'Data',Type:'D',IsPresent:true},{LogicalName:'Log',Type:'L',IsPresent:true}],'E:\\Recovery\\');
 assert.equal(c.length,3);assert.match(c[0],/MOVE.*\.mdf.*MOVE.*\.ldf/);assert.ok(c.every(x=>!x.includes('REPLACE')));assert.match(c[1],/NORECOVERY.*STOPAT/);assert.match(c[2],/CHECKSUM, RECOVERY, STOPAT/);assert.ok(!c.some(x=>/WITH RECOVERY;/.test(x)));
});
test('UC13 rechaza brechas, ramas distintas, medios dañados y futuro sin cobertura',()=>{
 for(const change of [{FirstLSN:'90071992547409951'},{Fork:'otra'},{Family:'otra'},{Checksum:false},{Damaged:true},{Bulk:true},{RecoveryModel:'BULK_LOGGED'},{Start:'2026-01-01T01:59:00'}])assert.throws(()=>plan([full,diff,{...log,...change}],'2026-01-01T02:00:00','SF_Recovery_test','ERP'));
 assert.throws(()=>plan([full,diff,log],'2025-12-31T00:00:00','SF_Recovery_test','ERP'));
 assert.throws(()=>plan([full,diff,log],'2026-01-01T02:00:00','SF_Recovery_test','SF_Recovery_test'));
});
test('UC13 DIFF ajena no puede cerrar una brecha de logs',()=>{assert.throws(()=>plan([full,{...diff,BaseLSN:'123'},log],'2026-01-01T02:00:00','SF_Recovery_test','ERP'));});
test('UC13 conserva milisegundos SQL en los limites temporales PITR',()=>{
 assert.throws(()=>plan([{...full,Finish:'2026-01-01T02:00:00.003'},log],'2026-01-01T02:00:00','SF_Recovery_test','ERP'),/FULL/);
 assert.throws(()=>plan([full,diff,{...log,Start:'2026-01-01T02:00:00.000'}],'2026-01-01T02:00:00','SF_Recovery_test','ERP'),/Cadena/);
});
test('UC13 programación semanal/diaria y LOG sin perder medianoche',()=>{
 const s=slots(new Date('2026-11-07T23:44:00Z'),new Date('2026-11-08T00:00:05Z'));assert.deepEqual(s.map(x=>x.type),['LOG','FULL','DIFF','LOG']);assert.equal(s[0].missed,true);assert.equal(s[1].missed,false);
 assert.deepEqual(slots(new Date('2026-11-08T23:59:00Z'),new Date('2026-11-09T00:00:05Z')).map(x=>x.type),['DIFF','LOG']);
 assert.deepEqual(slots(new Date('2026-11-08T00:00:01Z'),new Date('2026-11-08T00:14:00Z')),[]);
});
test('UC13 ejecutor rechaza sa y la cuenta web',()=>{
 const env={BACKUPS_DB_USER:'sa'};assert.throws(()=>config(env));env.BACKUPS_DB_USER='erp';env.DB_USER='ERP';assert.throws(()=>config(env));
});
test('UC13 verifica identidad de medios antes de restaurar',async()=>{
 const p={source:'ERP',chain:[{...full,UUID:'expected'}]};let called=0;
 const pool={request:()=>({query:async()=>{called++;return {recordset:[{Position:1,BackupSetGUID:'changed',DatabaseName:'ERP',HasBackupChecksums:true}]};}})};
 await assert.rejects(inspect(pool,p,'D:\\Backups\\'),/no coincide/);assert.equal(called,1);
});
test('UC13 conserva MOVE del FULL cuando LOG solo contiene archivos de log',async()=>{
 const files=[{LogicalName:'Data',Type:'D',UniqueID:'data',IsPresent:true},{LogicalName:'Log',Type:'L',UniqueID:'log',IsPresent:true}];
 let fileReads=0;
 const pool={request:()=>({query:async text=>({recordset:text.startsWith('RESTORE HEADERONLY')?[{Position:1,BackupSetGUID:'same',DatabaseName:'ERP',HasBackupChecksums:true}]:text.startsWith('RESTORE FILELISTONLY')?(fileReads++===0?files:[files[1]]):[]})})};
 const result=await inspect(pool,{source:'ERP',chain:[{...full,UUID:'same'},{...log,UUID:'same'}]},'D:\\Backups\\');assert.deepEqual(result,files);
});
test('UC13 ejecutor ocupado no altera cola ni agenda',async()=>{
 const {run}=require('../../../src/modules/dba/backups/worker');const queries=[];
 const pool={request:()=>({query:async text=>{queries.push(text);return {recordset:[text.includes('IS_SRVROLEMEMBER')?{Db:'ERP',IsAdmin:0}:{Code:-1}]};}})};
 assert.deepEqual(await run(pool,{BACKUPS_ROOT:'D:\\Backups\\',BACKUPS_RESTORE_ROOT:'E:\\Recovery\\'}),{busy:true});assert.equal(queries.length,2);assert.ok(!queries.some(x=>/UPDATE|INSERT|RESTORE/.test(x)));
});
test('UC13 servicio liga actor y solicitudes como parámetros tipados',async()=>{
 const {createBackupsService}=require('../../../src/modules/dba/backups/service');const inputs=[];
 const request={input:(...args)=>{inputs.push(args);return request;},execute:async proc=>{assert.equal(proc,'dbo.sp_BackupsSolicitar');return {recordset:[{Id:id,Estado:'PENDIENTE'}]};}};
 const result=await createBackupsService(async()=>({request:()=>request})).submit(77,{id,type:'RESTORE',planId:id});
 assert.equal(result.Estado,'PENDIENTE');assert.equal(inputs.find(x=>x[0]==='ActorUsuarioId')[2],77);assert.equal(inputs.find(x=>x[0]==='PlanId')[2],id);
});
test('UC13 HTTP exige sesión, permisos y CSRF; encola sin ejecutar SQL DBA',async()=>{
 const express=require('express'),session=require('express-session');const {createBackupsRoutes}=require('../../../src/modules/dba/backups/routes');
 const app=express();app.use(express.json());app.use(session({secret:'uc13-test-secret-long-enough-for-tests',resave:false,saveUninitialized:false}));
 let calls=0;app.get('/session/:permission',(req,res)=>{req.session.usuario={usuarioId:1,permisos:['DBA_BACKUPS_CONSULTAR',req.params.permission]};req.session.backupsCsrf='a'.repeat(64);res.end('ok');});
 app.use(createBackupsRoutes({submit:async()=>{calls++;return {Id:id,Estado:'PENDIENTE'};}}));
 const server=app.listen(0,'127.0.0.1');await require('node:events').once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
 try{
  assert.equal((await fetch(base+'/dba/backups',{redirect:'manual'})).status,302);
  let cookie=(await fetch(base+'/session/DBA_BACKUPS_EJECUTAR')).headers.get('set-cookie').split(';')[0];
  const send=(data,csrf)=>fetch(base+'/dba/backups',{method:'POST',headers:{cookie,'Content-Type':'application/json',...(csrf?{'X-CSRF-Token':csrf}:{})},body:JSON.stringify(data)});
  assert.equal((await send({id,type:'FULL'})).status,403);
  assert.equal((await send({id,type:'FULL'},'a'.repeat(64))).status,202);
  assert.equal((await send({id,type:'INVALID'},'a'.repeat(64))).status,400);
  assert.equal((await send({id,type:'RESTORE',planId:id},'a'.repeat(64))).status,403);
  cookie=(await fetch(base+'/session/NONE')).headers.get('set-cookie').split(';')[0];assert.equal((await send({id,type:'FULL'},'a'.repeat(64))).status,403);assert.equal(calls,1);
 }finally{await new Promise(r=>server.close(r));}
});
test('UC13 EJS renderiza estado vacío real y escapa resultados',async()=>{
 const ejs=require('ejs');const html=await ejs.renderFile('src/views/dba/backups/index.ejs',{moduleAreas:require('../../../src/config/moduleCatalog').visibleAreas,usuario:{usuarioId:1,nombreUsuario:'DBA',permisos:['DBA_BACKUPS_CONSULTAR']},csrf:'x',jobs:[],schedule:[],catalog:[]});
 assert.match(html,/No hay solicitudes registradas/);assert.match(html,/Sin señal reciente/);assert.doesNotMatch(html,/Solicitar respaldo/);
});
