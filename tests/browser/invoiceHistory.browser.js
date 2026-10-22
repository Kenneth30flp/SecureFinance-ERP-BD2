'use strict';
// Real SQL services in the restored invoice lab; authentication alone is a QA fixture.
require('dotenv').config({ quiet: true });
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { spawn } = require('node:child_process');
const net = require('node:net');
const state = JSON.parse(fs.readFileSync('.data/facturas39-deployment.json','utf8').replace(/^\uFEFF/,''));
assert.match(state.lab,/^SecureFinanceERP_Facturas_\d+$/);
process.env.DB_NAME = process.argv.includes('--main')?'SecureFinanceERP':state.lab;
const { createApp } = require('../../server');
const { getPool, closePool, sql } = require('../../src/config/database');
const { createProductoService } = require('../../src/services/productoService');
const delay = ms => new Promise(resolve => setTimeout(resolve,ms));
async function main() {
 const pool = await getPool();
 const permisos = (await pool.request().input('UsuarioId',sql.Int,3).execute('dbo.sp_ObtenerPermisosUsuario')).recordset.map(p=>p.Codigo);
 const app = createApp({ production:false, authService:{login:async()=>({codigo:0,usuario:{usuarioId:3,nombreUsuario:'QA_INVOICE_SESSION_FIXTURE',permisos,debeCambiarPassword:false}})} });
 const server = app.listen(0,'127.0.0.1'); await once(server,'listening');
 const base = 'http://127.0.0.1:'+server.address().port;
 const profile = fs.mkdtempSync(path.join(os.tmpdir(),'sf-invoice-browser-'));
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
  socket.addEventListener('message',event=>{const m=JSON.parse(event.data);if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.text);const p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}});
  const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;const timer=setTimeout(()=>{pending.delete(id);reject(Error('CDP timeout '+method));},15000);pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params}));});
  const evaluate=async expression=>{const result=await cdp('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(result.exceptionDetails)throw Error(result.exceptionDetails.exception?.description||result.exceptionDetails.text);return result.result.value;};
  const wait=async expression=>{for(let i=0;i<120;i++){if(await evaluate(expression))return;await delay(100);}throw Error('DOM timeout '+expression);};
  const navigate=async route=>{await cdp('Page.navigate',{url:base+route});await wait('location.href==='+JSON.stringify(base+route)+'&&document.readyState==="complete"');};
  await cdp('Page.enable'); await cdp('Runtime.enable');await cdp('Network.enable');
  const salePosts=[];socket.addEventListener('message',event=>{const m=JSON.parse(event.data);if(m.method==='Network.requestWillBeSent'&&m.params.request.method==='POST'&&m.params.request.url.includes('/facturacion/procesar'))salePosts.push(m.params.request.url);});
  await cdp('Page.addScriptToEvaluateOnNewDocument',{source:"window.print=()=>{document.body.dataset.printCount=String(Number(document.body.dataset.printCount||0)+1)}"});
  await navigate('/login');
  await evaluate("document.querySelector('[name=NombreUsuario]').value='QA_INVOICE_SESSION_FIXTURE';document.querySelector('[name=Password]').value='fixture';document.querySelector('form').requestSubmit()");
  await wait('location.pathname===\"/dashboard\"&&document.readyState===\"complete\"');
  await navigate('/facturacion');
  assert.ok(await evaluate("[...document.querySelectorAll('.billing-tabs a')].some(a=>a.textContent==='Historial de facturas')"));
  await evaluate("[...document.querySelectorAll('.billing-tabs a')].find(a=>a.textContent==='Historial de facturas').click()");
  await wait('location.pathname===\"/facturacion/historial\"&&document.querySelector(\"#invoice-number\")');
  await evaluate("document.querySelector('#invoice-number').value='6010';document.querySelector('.invoice-filter-grid').requestSubmit()");
  await wait('document.querySelectorAll(\"tr[data-invoice]\").length===1');
  assert.ok(await evaluate("document.querySelector('tr[data-invoice]').textContent.includes('90.46')"));
  await evaluate("document.querySelector('tr[data-invoice] a').click()");
  await wait('location.pathname===\"/facturacion/facturas/6010\"&&document.querySelector(\"#invoice-total\")');
  const text=await evaluate('document.body.innerText');
  for(const v of ['Consumidor final DEMO','CF','Cable HDMI','35.90','26.93','9.69','Q 90.46','SAT/FEL'])assert.ok(text.includes(v),v);
  assert.equal(await evaluate("document.querySelector('tr[data-line] td:nth-child(2)').textContent"),'3');
  assert.ok(!await evaluate("!!document.querySelector('#venta-form')"));
  await evaluate("document.querySelector('#print-invoice').click()");assert.equal(await evaluate('document.body.dataset.printCount'),'1');
  const artifacts=path.resolve('.data/invoice-history');fs.mkdirSync(artifacts,{recursive:true});
  for(const width of [1366,768,390,320]){
   await cdp('Emulation.setDeviceMetricsOverride',{width,height:950,deviceScaleFactor:1,mobile:false});
   assert.ok(await evaluate('document.documentElement.scrollWidth<=innerWidth'),'Viewport '+width);
   fs.writeFileSync(path.join(artifacts,'invoice-6010-'+width+'.png'),Buffer.from((await cdp('Page.captureScreenshot',{})).data,'base64'));
  }
  await cdp('Emulation.setEmulatedMedia',{media:'print'});
  assert.equal(await evaluate("getComputedStyle(document.querySelector('.sidebar')).display"),'none');
  assert.notEqual(await evaluate("getComputedStyle(document.querySelector('#invoice-copy')).display"),'none');
  const pdf=await cdp('Page.printToPDF',{printBackground:false});const bytes=Buffer.from(pdf.data,'base64');assert.ok(bytes.length>1000);assert.equal(bytes.subarray(0,4).toString(),'%PDF');fs.writeFileSync(path.join(artifacts,'invoice-6010-copy.pdf'),bytes);
  await cdp('Emulation.setEmulatedMedia',{media:''});
  await navigate('/facturacion/facturas/6010?imprimir=1');await wait('document.body.dataset.printCount===\"1\"');
  await navigate('/facturacion/historial?numero=2147483647');assert.ok(await evaluate("document.body.innerText.includes('No hay facturas para esta búsqueda')"));
  await navigate('/facturacion/historial');assert.ok(await evaluate("document.querySelectorAll('tr[data-invoice]').length>0"));
  for(const width of [1366,390]){await cdp('Emulation.setDeviceMetricsOverride',{width,height:950,deviceScaleFactor:1,mobile:false});assert.ok(await evaluate('document.documentElement.scrollWidth<=innerWidth'));fs.writeFileSync(path.join(artifacts,'history-'+width+'.png'),Buffer.from((await cdp('Page.captureScreenshot',{})).data,'base64'));}
  assert.deepEqual(salePosts,[]);assert.deepEqual(errors,[]);
  console.log('PASS Chromium + SQL: historial, filtro #6010, 3 HDMI, Q90.46, impresion/PDF, copia automatica, vacios, 1366/768/390/320 y cero POST de venta');
  fs.writeFileSync('.data/facturas39-browser'+(process.argv.includes('--main')?'-main':'')+'.json',JSON.stringify({database:process.env.DB_NAME,passed:true,invoice6010:true,salePosts:0,authentication:'SESSION_FIXTURE_NOT_REAL_LOGIN'},null,2));
 } finally {
  socket?.close();const closed=browser.exitCode===null?once(browser,'exit'):Promise.resolve();browser.kill();await closed;
  // Only the private profile created above, inside the OS temporary directory.
  if(path.dirname(profile)!==os.tmpdir()||!path.basename(profile).startsWith('sf-invoice-browser-'))throw Error('Unexpected profile');
  fs.rmSync(profile,{recursive:true,force:true,maxRetries:5,retryDelay:200});
  await new Promise(r=>{server.close(r);server.closeAllConnections();});await closePool();
 }
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
