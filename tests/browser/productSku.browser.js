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
const state = JSON.parse(fs.readFileSync('.data/product-sku-lab.json','utf8').replace(/^\uFEFF/,''));
assert.match(state.database,/^SecureFinanceERP_SKU_\d+$/);
process.env.DB_NAME = state.database;
const { createApp } = require('../../server');
const { getPool, closePool, sql } = require('../../src/config/database');
const { createProductoService } = require('../../src/services/productoService');
const delay = ms => new Promise(resolve => setTimeout(resolve,ms));
async function main() {
 const pool = await getPool();
 const permisos = (await pool.request().input('UsuarioId',sql.Int,3).execute('dbo.sp_ObtenerPermisosUsuario')).recordset.map(p=>p.Codigo);
 const app = createApp({ production:false, authService:{login:async()=>({codigo:0,usuario:{usuarioId:3,nombreUsuario:'QA_SKU_SESSION_FIXTURE',permisos,debeCambiarPassword:false}})} });
 const server = app.listen(0,'127.0.0.1'); await once(server,'listening');
 const base = 'http://127.0.0.1:'+server.address().port;
 const profile = fs.mkdtempSync(path.join(os.tmpdir(),'sf-sku-browser-'));
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
  await cdp('Page.enable'); await cdp('Runtime.enable');
  await navigate('/login');
  await evaluate("document.querySelector('[name=NombreUsuario]').value='QA_SKU_SESSION_FIXTURE';document.querySelector('[name=Password]').value='fixture';document.querySelector('form').requestSubmit()");
  await wait('location.pathname==="/dashboard"&&document.readyState==="complete"');
  const fill = "(()=>{const values={Descripcion:'QA SKU navegador aislado',Precio:'12.00',PrecioCosto:'5.00',StockMinimo:'1',PuntoReorden:'2',GarantiaMeses:'6'};for(const [k,v]of Object.entries(values))document.querySelector('[name='+k+']').value=v;document.querySelector('#ProveedorId').selectedIndex=1;})()";
  await navigate('/productos?nuevo=1');
  assert.equal(await evaluate("document.querySelector('#ModoCodigo').value"),'AUTOMATICO');
  assert.equal(await evaluate("document.querySelector('#Codigo').disabled"),true);
  await evaluate(fill); await evaluate("document.querySelector('[data-master-form]').requestSubmit()");
  await wait('!document.querySelector("#ModoCodigo")&&location.search.includes("id=")&&document.querySelector("#module-message").textContent.includes("SKU:")');
  const automatic = await evaluate("document.querySelector('#Codigo').value"); assert.match(automatic,/^PRD-\d{6,}$/);
  assert.ok(await evaluate('document.querySelector("#module-message").textContent.includes('+JSON.stringify(automatic)+')'));
  const id=await evaluate("Number(new URLSearchParams(location.search).get('id'))");
  assert.equal((await createProductoService().list(3,{id}))[0].Codigo,automatic);
  console.log('PASS Chromium + SQL: alta automatica sin escribir SKU y confirmacion del codigo persistido');
  await navigate('/productos?nuevo=1');
  await evaluate("document.querySelector('#ModoCodigo').value='MANUAL';document.querySelector('#ModoCodigo').dispatchEvent(new Event('change'))");
  assert.equal(await evaluate("document.querySelector('#Codigo').disabled"),false);
  assert.equal(await evaluate("document.querySelector('#Codigo').required"),true);
  await evaluate(fill); await evaluate('document.querySelector("#Codigo").value='+JSON.stringify(automatic));
  await evaluate("document.querySelector('[data-master-form]').requestSubmit()");
  await wait('document.querySelector(".form-feedback").textContent.includes("ya está registrado")');
  assert.equal(await evaluate("document.querySelector('#Codigo').value"),automatic);
  const manual='EMPRESA-'+Date.now();
  await evaluate('document.querySelector("#Codigo").value='+JSON.stringify(manual));
  await evaluate("document.querySelector('[data-master-form]').requestSubmit()");
  await wait('!document.querySelector("#ModoCodigo")&&document.querySelector("#module-message").textContent.includes('+JSON.stringify(manual)+')');
  assert.equal(await evaluate("document.querySelector('#Codigo').value"),manual);
  assert.deepEqual(errors,[]);
  console.log('PASS Chromium + SQL: opcion manual, duplicado visible sin perder campos y alta manual confirmada');
  fs.writeFileSync('.data/product-sku-browser.json',JSON.stringify({database:state.database,authentication:'SESSION_FIXTURE_NOT_REAL_LOGIN',automatic,manual,passed:true},null,2));
 } finally {
  socket?.close();const closed=browser.exitCode===null?once(browser,'exit'):Promise.resolve();browser.kill();await closed;
  // Only the private profile created above, inside the OS temporary directory.
  if(path.dirname(profile)!==os.tmpdir()||!path.basename(profile).startsWith('sf-sku-browser-'))throw Error('Unexpected profile');
  fs.rmSync(profile,{recursive:true,force:true,maxRetries:5,retryDelay:200});
  await new Promise(r=>{server.close(r);server.closeAllConnections();});await closePool();
 }
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
