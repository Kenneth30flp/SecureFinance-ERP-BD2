'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {executeRestore,config}=require('../../../src/modules/dba/backups/worker');
const {createBackupsService}=require('../../../src/modules/dba/backups/service');
const {readFileSync}=require('node:fs');
const {runInNewContext}=require('node:vm');

test('UC13 PITR stops at first ONLINE, without replaying the later coverage log',async()=>{
 const queries=[],created=new Date('2026-01-01T00:00:00Z');
 const pool={request:()=>{const parameters={};return {input(k,t,v){parameters[k]=v;return this;},async query(text){queries.push({text,parameters});return {recordset:[{Id:21,Created:created,State:queries.length===2?'ONLINE':'RESTORING'}]};}};}};
 const result=await executeRestore(pool,{target:'SF_Recovery_test',when:'2026-01-01T01:00:00',chain:[{Type:'D'},{Type:'L'},{Type:'L'}]},['FULL;','LOG_ONE;','LOG_TWO;']);
 assert.equal(result.estado,'ONLINE');assert.equal(queries.length,2);
 assert.match(queries[0].text,/DB_ID\(@target\) IS NOT NULL/);
 assert.match(queries[1].text,/create_date=@createdAt AND state_desc='RESTORING'/);
 assert.equal(queries[1].parameters.createdId,21);assert.equal(queries[1].parameters.createdAt,created);
 assert.ok(queries.every(q=>q.text.includes("ISNULL(APPLOCK_MODE")));
});
test('UC13 PITR never forces RECOVERY when SQL did not reach STOPAT',async()=>{
 let calls=0;const pool={request:()=>({input(){return this;},async query(){calls++;return {recordset:[{Id:21,Created:new Date(),State:'RESTORING'}]};}})};
 await assert.rejects(executeRestore(pool,{target:'SF_Recovery_test',chain:[{Type:'D'},{Type:'L'}]},['FULL;','LOG;']),/no confirmó alcanzar STOPAT/);assert.equal(calls,2);
});
test('UC13 PITR aborts on existing target or lost lock without continuing',async()=>{
 let calls=0;const pool={request:()=>({input(){return this;},async query(){calls++;throw new Error('El destino ya existe.');}})};
 await assert.rejects(executeRestore(pool,{target:'SF_Recovery_test',chain:[{Type:'D'}]},['FULL;','LOG;']),/ya existe/);assert.equal(calls,1);
});
test('UC13 incompatible SQL responses cannot confirm queue submissions',async()=>{
 const req={input(){return this;},execute:async()=>({recordset:[]})};
 await assert.rejects(createBackupsService(async()=>({request:()=>req})).submit(1,{id:'12345678-1234-4234-8234-123456789012',type:'FULL'}),/no confirmada/);
 await assert.rejects(createBackupsService(async()=>({request:()=>req})).dashboard(1),/incompatible/);
});
test('UC13 config rejects malformed TLS switches and SQL ports',()=>{
 const env={BACKUPS_DB_USER:'worker',BACKUPS_DB_SERVER:'localhost',BACKUPS_DB_NAME:'fixture',BACKUPS_DB_PASSWORD:'test-only'};
 for(const patch of [{BACKUPS_DB_PORT:'0'},{BACKUPS_DB_PORT:'abc'},{BACKUPS_DB_ENCRYPT:'False'},{BACKUPS_DB_TRUST_SERVER_CERTIFICATE:'yes'}])assert.throws(()=>config({...env,...patch}));
 assert.equal(config(env).options.encrypt,true);assert.equal(config(env).options.trustServerCertificate,false);
});
test('UC13 actual ERP mounting serves page and protected static assets without SQL',async()=>{
 const {createApp}=require('../../../server');let writes=0;
 const app=createApp({secret:'uc13-isolated-test-session-secret-32-characters',authService:{login:async()=>({codigo:0,usuario:{usuarioId:8,nombreUsuario:'Test',permisos:['DBA_BACKUPS_CONSULTAR','DBA_BACKUPS_EJECUTAR','DBA_BACKUPS_RESTAURAR']}})},backupsService:{dashboard:async()=>({jobs:[],schedule:[{Enabled:false,AhoraUtc:new Date()}],catalog:[]}),submit:async(a,d)=>{assert.equal(a,8);writes++;return {Id:d.id,Estado:'PENDIENTE'};}}});
 const server=app.listen(0,'127.0.0.1');await require('node:events').once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
 try {
  const login=await fetch(base+'/login',{method:'POST',redirect:'manual',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'NombreUsuario=fixture&Password=fixture'});
  const cookie=login.headers.get('set-cookie').split(';')[0];
  const response=await fetch(base+'/dba/backups',{headers:{cookie}}),html=await response.text();assert.equal(response.status,200);
  assert.match(html,/Generar plan/);assert.match(html,/Solicitar respaldo/);assert.match(html,/incluyendo medianoche/);assert.match(html,/Continuidad y recuperación/);
  for(const route of ['/css/parte4/backups.css','/js/parte4/backups.js'])assert.equal((await fetch(base+route)).status,200);
  const csrf=html.match(/name="csrf-token" content="([^"]+)"/)[1];
  assert.equal((await fetch(base+'/dba/backups',{method:'POST',headers:{cookie,'Content-Type':'application/json','X-CSRF-Token':csrf},body:JSON.stringify({id:'12345678-1234-4234-8234-123456789012',type:'FULL',ActorUsuarioId:999})})).status,202);assert.equal(writes,1);
 }finally{await new Promise(r=>server.close(r));}
});
test('UC13 browser preserves uncertain payload, prevents double submit and confirms only matching ID',async()=>{
 let handler,resolve,calls=0;const bodies=[],button={},message={};
 const form={dataset:{},querySelector:()=>button,addEventListener:(event,fn)=>{if(event==='submit')handler=fn;}};
 const document={querySelectorAll:()=>[form],querySelector:()=>({content:'csrf'}),getElementById:()=>message};
 let type='FULL';const id='12345678-1234-4234-8234-123456789012';
 class FormData{*[Symbol.iterator](){yield ['type',type];}}
 runInNewContext(readFileSync('src/public/js/parte4/backups.js','utf8'),{document,FormData,crypto:{randomUUID:()=>id},window:{confirm:()=>true},fetch:async(u,o)=>{calls++;bodies.push(o.body);if(calls===1)return new Promise(r=>{resolve=r;});return {ok:true,json:async()=>({Id:id,Estado:'PENDIENTE'})};}});
 const event={preventDefault(){}};const first=handler(event);await handler(event);assert.equal(calls,1);
 resolve({ok:false,status:503,json:async()=>({error:'Incierto'})});await first;type='LOG';await handler(event);
 assert.equal(bodies[0],bodies[1]);assert.equal(button.disabled,true);assert.match(message.textContent,/registrada/);await handler(event);assert.equal(calls,2);
});
test('UC13 displayed plans escape SQL metadata and hide expired/used execution buttons',async()=>{
 const ejs=require('ejs'),now=new Date(),id='12345678-1234-4234-8234-123456789012';
 const job={Id:id,Tipo:'PLAN',Estado:'COMPLETADO',ActorUsuarioId:1,Creado:now,Fin:now,Resultado:'<script>bad()</script>'};
 const data={moduleAreas:require('../../../src/config/moduleCatalog').visibleAreas,usuario:{usuarioId:1,nombreUsuario:'Test',permisos:['DBA_BACKUPS_CONSULTAR','DBA_BACKUPS_RESTAURAR']},csrf:'test',schedule:[{AhoraUtc:now}],catalog:[],jobs:[job]};
 const render=()=>ejs.renderFile('src/views/dba/backups/index.ejs',data);
 let html=await render();assert.match(html,/Ejecutar este plan/);assert.ok(!html.includes('<script>bad()'));assert.match(html,/&lt;script&gt;/);
 job.Fin=new Date(now-31*60000);assert.doesNotMatch(await render(),/Ejecutar este plan/);
 job.Fin=now;data.jobs.push({...job,Tipo:'RESTORE',PlanId:id});assert.doesNotMatch(await render(),/Ejecutar este plan/);
});
