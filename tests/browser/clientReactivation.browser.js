'use strict';
// Real SQL services in the dedicated SKU lab; authentication alone is a QA fixture.
require('dotenv').config({ quiet: true });
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { spawn } = require('node:child_process');
const net = require('node:net');
const state = JSON.parse(fs.readFileSync('.data/clientes40-deployment.json','utf8').replace(/^\uFEFF/,''));
assert.match(state.lab,/^SecureFinanceERP_Clientes_\d+$/);
const mainMode=process.argv.includes('--main');process.env.DB_NAME=mainMode?'SecureFinanceERP':state.lab;
const { createApp } = require('../../server');
const { getPool, closePool, sql } = require('../../src/config/database');
const customers=require('../../src/services/clienteService').createClienteService();
const delay = ms => new Promise(resolve => setTimeout(resolve,ms));
async function main() {
 const pool = await getPool();
 const permisos = (await pool.request().input('UsuarioId',sql.Int,3).execute('dbo.sp_ObtenerPermisosUsuario')).recordset.map(p=>p.Codigo);
 const app = createApp({ production:false, authService:{login:async()=>({codigo:0,usuario:{usuarioId:3,nombreUsuario:'QA_REACTIVATION_SESSION_FIXTURE',permisos,debeCambiarPassword:false}})} });
 const server = app.listen(0,'127.0.0.1'); await once(server,'listening');
 const base = 'http://127.0.0.1:'+server.address().port;
 const profile = fs.mkdtempSync(path.join(os.tmpdir(),'sf-reactivation-browser-'));
 const browserPath = ['C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(fs.existsSync);
 assert.ok(browserPath);
 const reservation = net.createServer().listen(0,'127.0.0.1'); await once(reservation,'listening');
 const port = reservation.address().port; await new Promise(r=>reservation.close(r));
 const browser = spawn(browserPath,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+port,'--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});
 let socket;
 try {
  let page;
  for(let i=0;i<100;i++){try{page=(await(await fetch('http://127.0.0.1:'+port+'/json/list')).json()).find(p=>p.type==='page');if(page)break;}catch{}await delay(100);}
  assert.ok(page); socket = new WebSocket(page.webSocketDebuggerUrl); await once(socket,'open');
  let sequence=0;const pending=new Map(),errors=[];
  socket.addEventListener('message',event=>{const m=JSON.parse(event.data);if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.exception?.description||m.params.exceptionDetails.text);const p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}});
  const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;const timer=setTimeout(()=>{pending.delete(id);reject(Error('CDP timeout '+method));},15000);pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params}));});
  const evaluate=async expression=>{const result=await cdp('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(result.exceptionDetails)throw Error(result.exceptionDetails.exception?.description||result.exceptionDetails.text);return result.result.value;};
  const wait=async expression=>{for(let i=0;i<120;i++){if(await evaluate(expression))return;await delay(100);}throw Error('DOM timeout '+expression+' / '+JSON.stringify(errors)+' / '+await evaluate('location.pathname+location.search+" / "+document.body.innerText.slice(-1800)'));};
  const navigate=async route=>{await cdp('Page.navigate',{url:base+route});await wait('location.href==='+JSON.stringify(base+route)+'&&document.readyState==="complete"');};
  await cdp('Page.enable');await cdp('Runtime.enable');await cdp('Network.enable');
  const posts=[];socket.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.method==='Network.requestWillBeSent'&&m.params.request.method==='POST'&&m.params.request.url.includes('/clientes/'))posts.push(m.params.request.url);});
  await navigate('/login');await evaluate("document.querySelector('[name=NombreUsuario]').value='QA_REACTIVATION_SESSION_FIXTURE';document.querySelector('[name=Password]').value='fixture';document.querySelector('form').requestSubmit()");
  await wait('location.pathname===\"/dashboard\"&&document.readyState===\"complete\"');
  const result=JSON.parse(fs.readFileSync('.data/clientes40-sql.json','utf8'));
  const id=mainMode?3:result.clientId;assert.ok(mainMode||id!==3);
  if(!mainMode){
   const current=(await customers.list(3,{id}))[0];
   if(!current.Activo)await customers.reactivate(3,{id,Version:current.Version,Motivo:'Preparacion QA de navegador aislado',OperacionId:require('node:crypto').randomUUID()});
   await navigate('/clientes?id='+id);
   await evaluate("(()=>{const f=document.querySelector('form[action$=\"/inactivar\"]');f.closest('details').open=true;f.querySelector('[name=Motivo]').value='Inactivacion QA navegador';f.requestSubmit(f.querySelector('button'));})()");
   await wait('document.querySelector(\"#master-confirm\").open');
   await evaluate("document.querySelector('#master-confirm [value=cancel]').click()");await wait('!document.querySelector(\"#master-confirm\").open');
   assert.equal((await customers.list(3,{id}))[0].Activo,true);
   await wait("document.activeElement===document.querySelector('form[action$=\"/inactivar\"] button')");
   await evaluate("document.querySelector('form[action$=\"/inactivar\"]').requestSubmit()");await wait('document.querySelector(\"#master-confirm\").open');await evaluate("document.querySelector('#master-confirm [value=confirm]').click()");
   await wait('document.querySelector(\"#customer-detail .master-status\").textContent.trim()===\"Inactivo\"');
  }
  await navigate('/clientes?id='+id+'&estado=inactivo');
  assert.ok(await evaluate("!!document.querySelector('form[action$=\"/reactivar\"]')"));
  assert.ok(!await evaluate("!!document.querySelector('form[action$=\"/inactivar\"]')"));
  await evaluate("document.querySelector('form[action$=\"/reactivar\"]').closest('details').open=true");
  const artifacts=path.resolve('.data/client-reactivation');fs.mkdirSync(artifacts,{recursive:true});
  for(const width of [1366,768,390,320]){await cdp('Emulation.setDeviceMetricsOverride',{width,height:950,deviceScaleFactor:1,mobile:false});assert.ok(await evaluate('document.documentElement.scrollWidth<=innerWidth'));fs.writeFileSync(path.join(artifacts,'reactivate-'+(mainMode?'main-':'lab-')+width+'.png'),Buffer.from((await cdp('Page.captureScreenshot',{})).data,'base64'));}
  if(mainMode){assert.deepEqual(posts,[]);assert.equal((await customers.list(3,{id:3}))[0].Activo,false);console.log('PASS Chromium principal SOLO LECTURA: opcion Reactivar y motivo visibles, historial, cliente 3 Inactivo y cero POST');}
  else{
   const payload=await evaluate("Object.fromEntries(new FormData(document.querySelector('form[action$=\"/reactivar\"]')))");payload.Motivo='Reactivacion QA navegador';
   const csrf=await evaluate("document.querySelector('meta[name=csrf-token]').content");
   await evaluate("(()=>{const f=document.querySelector('form[action$=\"/reactivar\"]');f.querySelector('[name=Motivo]').value='Reactivacion QA navegador';f.requestSubmit(f.querySelector('button'));})()");
   await wait('document.querySelector(\"#master-confirm\").open');assert.ok(await evaluate("document.querySelector('#confirm-description').textContent.includes('Reactivar')"));
   await evaluate("document.querySelector('#master-confirm [value=cancel]').click()");await wait('!document.querySelector(\"#master-confirm\").open');
   assert.equal((await customers.list(3,{id}))[0].Activo,false);
   await wait("document.activeElement===document.querySelector('form[action$=\"/reactivar\"] button')");
   await evaluate("document.querySelector('form[action$=\"/reactivar\"]').requestSubmit()");await wait('document.querySelector(\"#master-confirm\").open');await evaluate("document.querySelector('#master-confirm [value=confirm]').click()");
   await wait('document.querySelector(\"#customer-detail .master-status\").textContent.trim()===\"Activo\"&&document.querySelector(\"#module-message\").textContent.includes(\"reactivado\")');
   assert.ok(!await evaluate("new URLSearchParams(location.search).has('estado')"));
   assert.ok(await evaluate("!!document.querySelector('form[action$=\"/inactivar\"]')"));
   const retry=await evaluate('fetch('+JSON.stringify('/clientes/'+id+'/reactivar')+',{method:\"POST\",headers:{\"Content-Type\":\"application/json\",\"X-CSRF-Token\":'+JSON.stringify(csrf)+'},body:'+JSON.stringify(JSON.stringify(payload))+'}).then(r=>r.status)');assert.equal(retry,200);
   const history=await customers.stateHistory(3,id);assert.equal(history.filter(h=>h.OperacionId?.toLowerCase()===payload.OperacionId.toLowerCase()).length,1);
   assert.equal((await customers.list(3,{id:3}))[0].Activo,false);
   console.log('PASS Chromium laboratorio: inactivar/reactivar, cancelar/confirmar, filtro inactivo limpiado, ficha actualizada y reintento sin duplicar auditoria');
  }
  assert.deepEqual(errors,[]);fs.writeFileSync('.data/clientes40-browser'+(mainMode?'-main':'')+'.json',JSON.stringify({database:process.env.DB_NAME,passed:true,mainClient3Inactive:true,authentication:'SESSION_FIXTURE_NOT_REAL_LOGIN'},null,2));
 } finally {
  socket?.close();const closed=browser.exitCode===null?once(browser,'exit'):Promise.resolve();browser.kill();await closed;
  // Only the private profile created above, inside the OS temporary directory.
  if(path.dirname(profile)!==os.tmpdir()||!path.basename(profile).startsWith('sf-reactivation-browser-'))throw Error('Unexpected profile');
  fs.rmSync(profile,{recursive:true,force:true,maxRetries:5,retryDelay:200});
  await new Promise(r=>{server.close(r);server.closeAllConnections();});await closePool();
 }
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
