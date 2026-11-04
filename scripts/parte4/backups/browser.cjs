'use strict';
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),net=require('node:net'),assert=require('node:assert/strict');
const {spawn}=require('node:child_process'),{once}=require('node:events');
const {randomBytes}=require('node:crypto');
const {runSql,lit}=require('../ldf/sqlcmd.cjs');
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function browser(s){
 const q={server:s.server,expectedServer:s.expectedServer,database:s.target};
 assert.match(q.database,/^SecureFinanceERP_LDF_Rehearsal_\d{14}$/);
 const c=JSON.parse(fs.readFileSync(s.privateFile));
 const username='P4_QA_'+Date.now(),password=randomBytes(24).toString('base64url')+'Aa1!';
 await runSql(`DECLARE @id int;EXEC dbo.sp_RegistrarUsuario @NombreUsuario=${lit(username)},@Correo=${lit(username+'@example.invalid')},@Password=${lit(password)},@NombreCompleto=N'Parte IV isolated browser QA',@UsuarioId=@id OUTPUT;
IF @id IS NULL THROW 58010,'QA registration failed',1;
UPDATE dbo.Usuario SET DebeCambiarPassword=0 WHERE UsuarioId=@id;
INSERT dbo.Usuario_Rol(UsuarioId,RolId) SELECT @id,RolId FROM dbo.Rol WHERE Nombre=N'Administrador';`,q);
 await runSql(`ALTER LOGIN [${c.ldf}] ENABLE;`,{...q,database:'master'});
 Object.assign(process.env,{DB_NAME:q.database,LDF_DATABASE:q.database,LDF_EXPECTED_SERVER:q.expectedServer,LDF_ADMIN_USER:c.ldf,LDF_ADMIN_PASSWORD:c.password,SESSION_COOKIE_NAME:'p4.lab.qa',SESSION_SECRET:randomBytes(48).toString('hex')});
 const artifacts='docs/parte4/integracion-final/evidencias';fs.mkdirSync(artifacts,{recursive:true});
 const profile=fs.mkdtempSync(path.join(os.tmpdir(),'sf-p4-browser-'));
 let server,chrome,socket,seq=0;const pending=new Map(),errors=[];
 try{
  server=require('../../../server').createApp().listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
  const binary=['C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(fs.existsSync);assert(binary,'Browser missing');
  const reserve=net.createServer().listen(0,'127.0.0.1');await once(reserve,'listening');const port=reserve.address().port;await new Promise(r=>reserve.close(r));
  chrome=spawn(binary,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+port,'--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});
  let page;for(let i=0;i<100;i++){try{page=(await(await fetch('http://127.0.0.1:'+port+'/json/list')).json()).find(p=>p.type==='page');if(page)break;}catch{}await pause(100);}assert(page,'Browser did not start');
  socket=new WebSocket(page.webSocketDebuggerUrl);await once(socket,'open');socket.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.text);const p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}});
  const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq,timer=setTimeout(()=>reject(Error('CDP timeout')),20000);pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params}));});
  const evaluate=async expression=>{const r=await cdp('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.exception?.description||r.exceptionDetails.text);return r.result.value;};
  const go=async route=>{await evaluate('window.__p4Leaving=true');await cdp('Page.navigate',{url:base+route});for(let i=0;i<200;i++){if(await evaluate('!window.__p4Leaving&&document.readyState==="complete"'))return;await pause(50);}throw Error('Navigation timeout');};
  await cdp('Page.enable');await cdp('Runtime.enable');await go('/login');
  const anon=await evaluate("fetch('/dba/backups').then(r=>new URL(r.url).pathname)");assert.equal(anon,'/login');
  const login=await evaluate(`fetch('/login',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams(${JSON.stringify({NombreUsuario:username,Password:password})})}).then(r=>({status:r.status,path:new URL(r.url).pathname}))`);assert.equal(login.status,200);assert.notEqual(login.path,'/login');
  const checks=[];
  for(const width of [1440,768,390]){
   await cdp('Emulation.setDeviceMetricsOverride',{width,height:1000,deviceScaleFactor:1,mobile:false});
   for(const route of ['/dba/backups','/dba/ldf','/cotizaciones','/compras','/creditos','/promociones','/multibodega','/auditoria/ddl']){
    await go(route);const r=await evaluate(`({path:location.pathname,title:document.title,overflow:document.documentElement.scrollWidth>innerWidth,error:!!document.querySelector('.ldf-error'),account:document.querySelector('.account-menu summary')?.getAttribute('aria-label'),text:document.body.innerText.slice(0,1200)})`);
    if(r.path!==route||r.error||!r.account?.includes(username)||r.overflow)console.error('BROWSER_FAILURE',JSON.stringify({width,route,...r}));
    assert.equal(r.path,route);assert.equal(r.error,false,route);assert(r.account?.includes(username),route);assert.equal(r.overflow,false,route+' overflow '+width);checks.push({width,route,title:r.title});
    if(route.startsWith('/dba/')){const shot=await cdp('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(path.join(artifacts,route.endsWith('ldf')?'ldf-'+width+'.png':'backups-'+width+'.png'),Buffer.from(shot.data,'base64'));}
   }
  }
  await go('/dba/backups');
  const csrf=await evaluate("fetch('/dba/backups',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:crypto.randomUUID(),type:'LOG'})}).then(r=>r.status)");assert.equal(csrf,403);
  const valid=await evaluate("fetch('/dba/backups',{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content},body:JSON.stringify({id:crypto.randomUUID(),type:'LOG'})}).then(async r=>({status:r.status,body:await r.json()}))");assert.equal(valid.status,202);assert.equal(valid.body.Estado,'PENDIENTE');
  await go('/dba/ldf');assert.equal(await evaluate("fetch('/dba/ldf/metrics').then(r=>r.status)"),200);
  assert.deepEqual(errors,[]);const report={atUTC:new Date().toISOString(),database:q.database,realSQL:true,user:username,checks,csrfRejected:csrf,queue:valid,errors,result:'PASS'};
  fs.writeFileSync(path.join(artifacts,'browser-lab.json'),JSON.stringify(report,null,2));console.log('PASS Chromium real + SQL: 8 routes, 3 widths, login, session, CSRF, queue, LDF metrics');return report;
 }finally{socket?.close();for(const p of pending.values())clearTimeout(p.timer);chrome?.kill();if(server)await new Promise(r=>server.close(r));await require('../../../src/config/database').closePool();await require('../../../src/modules/dba/ldf/pools').close();await runSql(`ALTER LOGIN [${c.ldf}] DISABLE;`,{...q,database:'master'});}
}
module.exports={browser};
