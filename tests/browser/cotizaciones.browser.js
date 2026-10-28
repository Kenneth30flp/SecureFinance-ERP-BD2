'use strict';
// SQL real in an isolated lab. Authentication alone is a labeled in-memory fixture.
require('dotenv').config({quiet:true});
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),net=require('node:net');
const assert=require('node:assert/strict');
const {once}=require('node:events');
const {spawn}=require('node:child_process');
const state=JSON.parse(fs.readFileSync('.data/cotizaciones-lab.json','utf8').replace(/^\uFEFF/,''));
const sqlResult=JSON.parse(fs.readFileSync('.data/cotizaciones-sql.json','utf8'));
assert.match(state.lab,/^SecureFinanceERP_P3_COT_\d{14}_[a-f0-9]{8}$/);assert.equal(sqlResult.lab,state.lab);
process.env.DB_NAME=state.lab;
const {getPool,closePool,sql}=require('../../src/config/database');
const {createApp}=require('../../server');
const {createCotizacionService}=require('../../src/modules/cotizaciones/service');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function run(){
 let server,browser,socket;
 const results={authentication:'SESSION_FIXTURE_NOT_REAL_LOGIN',database:'ISOLATED_P3_COT_LAB',checks:[],conversion:'PENDING_CONTRACT_APPROVAL'};
 const artifacts='docs/parte3/cotizaciones/evidencias';fs.mkdirSync(artifacts,{recursive:true});
 try{
 const pool=await getPool();assert.equal((await pool.request().query('SELECT DB_NAME() N')).recordset[0].N,state.lab);
 const permisos=(await pool.request().input('UsuarioId',sql.Int,state.actor).execute('dbo.sp_ObtenerPermisosUsuario')).recordset.map(p=>p.Codigo);
 const app=createApp({production:false,authService:{login:async()=>({codigo:0,usuario:{usuarioId:state.actor,nombreUsuario:'QA_COT_SESSION_FIXTURE',permisos,debeCambiarPassword:false}})}});
 server=app.listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
 const chrome=['C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(fs.existsSync);assert.ok(chrome,'Chromium instalado');
 const reserve=net.createServer().listen(0,'127.0.0.1');await once(reserve,'listening');const port=reserve.address().port;await new Promise(r=>reserve.close(r));
 const profile=fs.mkdtempSync(path.join(os.tmpdir(),'sf-cot-browser-'));
 browser=spawn(chrome,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+port,'--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});
 let page;for(let i=0;i<80;i++){try{page=(await(await fetch('http://127.0.0.1:'+port+'/json/list')).json()).find(p=>p.type==='page');if(page)break;}catch{}await delay(100);}assert.ok(page);
 socket=new WebSocket(page.webSocketDebuggerUrl);await once(socket,'open');let seq=0;const pending=new Map(),errors=[];
 socket.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.exception?.description||m.params.exceptionDetails.text);const p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}});
 const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq,timer=setTimeout(()=>{pending.delete(id);reject(Error('CDP timeout '+method));},15000);pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params}));});
 const evaluate=async expression=>{const r=await cdp('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.exception?.description||r.exceptionDetails.text);return r.result.value;};
 const wait=async expression=>{for(let i=0;i<100;i++){if(await evaluate(expression))return;await delay(100);}throw Error('DOM timeout '+expression+' / '+await evaluate('document.body.innerText.slice(-1200)'));};
 const navigate=async route=>{await cdp('Page.navigate',{url:base+route});await wait('location.href==='+JSON.stringify(base+route)+'&&document.readyState==="complete"');};
 const capture=async name=>{const r=await cdp('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(path.join(artifacts,name+'.png'),Buffer.from(r.data,'base64'));};
 const pass=name=>{results.checks.push(name);console.log('PASS BROWSER '+name);};
 await cdp('Page.enable');await cdp('Runtime.enable');await cdp('Emulation.setDeviceMetricsOverride',{width:1366,height:900,deviceScaleFactor:1,mobile:false});
 await navigate('/login');await evaluate("document.querySelector('[name=NombreUsuario]').value='QA_COT_SESSION_FIXTURE';document.querySelector('[name=Password]').value='fixture';document.querySelector('form').requestSubmit()");await wait('location.pathname==="/dashboard"&&document.readyState==="complete"');
 await navigate('/cotizaciones/nueva');assert.ok(await evaluate('Boolean(document.querySelector(\'a[aria-label="Cotizaciones"]\'))'));
 await evaluate(`document.querySelector('#cot-client').value=${JSON.stringify(String(sqlResult.clientId))};document.querySelector('#cot-product').value=${JSON.stringify(String(sqlResult.productId))};document.querySelector('#cot-quantity').value='2';document.querySelector('#cot-discount').value='10';document.querySelector('#cot-expiry').value=${JSON.stringify(new Date(Date.now()+2*86400000).toISOString().slice(0,10))};document.querySelector('#cot-notes').value='QA navegador SQL real: documento interno de laboratorio';document.querySelector('#cot-add').click();`);
 assert.match(await evaluate("document.querySelector('#cot-total').textContent"),/241\.92/);await capture('01-nueva-cotizacion-desktop');pass('menu, cliente, producto, descuento y calculo preliminar real');
 await evaluate("document.querySelector('#cot-create').requestSubmit()");await wait('/^\\/cotizaciones\\/\\d+$/.test(location.pathname)&&document.readyState==="complete"');
 const id=await evaluate('Number(location.pathname.split("/").pop())');const service=createCotizacionService(),document=await service.detail(state.actor,id);assert.equal(document.documento.Total,'241.92');assert.equal(document.lineas[0].Cantidad,2);await capture('02-detalle-cotizacion-desktop');pass('alta HTTP y documento persistido SQL con totales definitivos');
 await cdp('Emulation.setEmulatedMedia',{media:'print'});assert.equal(await evaluate("getComputedStyle(document.querySelector('.sidebar')).display"),'none');const pdf=await cdp('Page.printToPDF',{printBackground:false});fs.writeFileSync(path.join(artifacts,'03-comprobante-interno.pdf'),Buffer.from(pdf.data,'base64'));await cdp('Emulation.setEmulatedMedia',{media:''});pass('comprobante imprimible sin presentar factura tributaria');
 await navigate('/cotizaciones?numero='+document.documento.Numero);assert.ok(await evaluate('document.body.innerText.includes('+JSON.stringify(document.documento.Numero)+')'));await capture('04-historial-filtrado-desktop');pass('historial y busqueda por numero');
 for(const width of [768,390,320]){await cdp('Emulation.setDeviceMetricsOverride',{width,height:900,deviceScaleFactor:1,mobile:false});for(const route of ['/cotizaciones','/cotizaciones/nueva','/cotizaciones/'+id]){await navigate(route);assert.ok(await evaluate('document.documentElement.scrollWidth<=document.documentElement.clientWidth'),route+' width '+width);}await capture('05-detalle-'+width);pass('sin desborde global en listado, alta y detalle a '+width+'px');}
 await cdp('Page.setInterceptFileChooserDialog',{enabled:false});
 // Confirm dialog is handled explicitly; cancellation is the only document mutation here.
 await cdp('Page.enable');let dialogResolve;const dialog=new Promise(r=>{dialogResolve=r;});socket.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.method==='Page.javascriptDialogOpening')dialogResolve();});
 const submit=evaluate("document.querySelector('#cot-reason').value='Cancelacion QA navegador';document.querySelector('#cot-cancel').requestSubmit();true");await dialog;await cdp('Page.handleJavaScriptDialog',{accept:true});await submit;await wait('document.body.innerText.includes("CANCELADA")&&!document.querySelector("#cot-cancel")');assert.equal((await service.detail(state.actor,id)).documento.Estado,'CANCELADA');await capture('06-cancelacion-movil');pass('confirmacion y cancelacion persistida con historial');
 assert.deepEqual(errors,[]);pass('cero excepciones JavaScript');
 }finally{
 fs.writeFileSync(path.join(artifacts,'navegador.json'),JSON.stringify(results,null,2));socket?.close();browser?.kill();if(server)await new Promise(r=>{server.close(r);server.closeAllConnections();});await closePool();
 }
}
run().catch(e=>{console.error('BROWSER FAIL',e.message);process.exitCode=1;});
