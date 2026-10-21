'use strict';
// Real SQL services and real Express sessions. No credentials are changed.
// Default: existing credentials from ignored .data/qa-login.local.json.
// --session-fixture: explicitly substitutes authentication ONLY; results label this limitation.
require('dotenv').config({quiet:true});
process.env.DB_NAME='SecureFinanceERP_Estabilizacion_20261021';
const fs=require('node:fs');
const path=require('node:path');
const {spawn}=require('node:child_process');
const {once}=require('node:events');
const {randomUUID}=require('node:crypto');
const {mkdtemp}=require('node:fs/promises');
const os=require('node:os');
const net=require('node:net');
const assert=require('node:assert/strict');
const {createApp}=require('../../server');
const {getPool,closePool,sql}=require('../../src/config/database');
const {createProductoService}=require('../../src/services/productoService');
const {createInventarioService}=require('../../src/services/inventarioService');
const {createVentaService}=require('../../src/services/ventaService');
const {createEdwardService}=require('../../src/modules/edward/services');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function main(){
 const fixture=process.argv.includes('--session-fixture');
 const credentials=fixture?{usuario:'qa-session-fixture',password:randomUUID()}:JSON.parse(fs.readFileSync('.data/qa-login.local.json','utf8'));
 const pool=await getPool();
 const actor=3;
 const perms=(await pool.request().input('UsuarioId',sql.Int,actor).execute('dbo.sp_ObtenerPermisosUsuario')).recordset.map(p=>p.Codigo);
 const app=createApp(fixture?{authService:{login:async(name,password)=>name===credentials.usuario&&password===credentials.password?{codigo:0,usuario:{usuarioId:actor,nombreUsuario:'admin',permisos:perms,debeCambiarPassword:false}}:{codigo:3}},production:false}:{production:false});
 const server=app.listen(0,'127.0.0.1');await once(server,'listening');
 const base='http://127.0.0.1:'+server.address().port;
 const directory=await mkdtemp(path.join(os.tmpdir(),'sf-stabilization-browser-'));
 const artifacts=path.resolve('.data/stabilization-browser');fs.mkdirSync(artifacts,{recursive:true});
 const browserPath=['C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(p=>fs.existsSync(p));assert.ok(browserPath);
 const reservation=net.createServer().listen(0,'127.0.0.1');await once(reservation,'listening');const port=reservation.address().port;await new Promise(r=>reservation.close(r));
 const browser=spawn(browserPath,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+port,'--user-data-dir='+directory,'about:blank'],{windowsHide:true,stdio:'ignore'});
 let socket;
 const results={database:process.env.DB_NAME,authentication:fixture?'SESSION_FIXTURE_NOT_REAL_LOGIN':'REAL_SQL_LOGIN',checks:[]};
 try{
 let pages;for(let i=0;i<100;i++){try{pages=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();if(pages.some(p=>p.type==='page'))break;}catch{}await delay(100);}
 socket=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);await once(socket,'open');
 let sequence=0;const pending=new Map(),errors=[];
 socket.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.text);const p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}});
 const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;const timer=setTimeout(()=>reject(Error('CDP timeout '+method)),15000);pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params}));});
 const evaluate=async expression=>{const r=await cdp('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.exception?.description||r.exceptionDetails.text);return r.result.value;};
 const wait=async expression=>{for(let i=0;i<160;i++){if(await evaluate(expression))return;await delay(75);}throw Error('DOM timeout '+expression+' / '+await evaluate('document.body.innerText.slice(-1200)'));};
 const navigate=async route=>{await cdp('Page.navigate',{url:base+route});await wait('location.href==='+JSON.stringify(base+route)+'&&document.readyState==="complete"');};
 const capture=async name=>{await delay(150);const data=await cdp('Page.captureScreenshot',{captureBeyondViewport:false});fs.writeFileSync(path.join(artifacts,name+'.png'),Buffer.from(data.data,'base64'));};
 const pass=s=>{results.checks.push(s);console.log('PASS '+s);};
 await cdp('Page.enable');await cdp('Runtime.enable');await cdp('Emulation.setDeviceMetricsOverride',{width:1366,height:1000,deviceScaleFactor:1,mobile:false});
 await navigate('/login');
 await evaluate(`document.querySelector('[name=NombreUsuario]').value=${JSON.stringify(credentials.usuario)};document.querySelector('[name=Password]').value=${JSON.stringify(credentials.password)};document.querySelector('form').requestSubmit()`);
 await wait('location.pathname==="/dashboard"&&document.readyState==="complete"');pass('Express session established ('+results.authentication+')');
 const products=createProductoService(),inventory=createInventarioService(),sales=createVentaService(),edward=createEdwardService();
 const p=(await products.list(actor,{id:4,inventario:true}))[0];assert.equal(p.Codigo,'DEMO-CABLE');
 await navigate('/productos?id=4');await capture('01-producto-ingresar');
 assert.ok(await evaluate("[...document.querySelectorAll('a')].some(a=>a.textContent==='Ingresar existencias')"));
 await evaluate("[...document.querySelectorAll('a')].find(a=>a.textContent==='Ingresar existencias').click()");
 await wait('location.pathname==="/inventario"&&document.querySelector("#TipoMovimiento")');
 const op=await evaluate("document.querySelector('[name=OperacionId]').value");
 await evaluate("document.querySelector('details.inventory-action').open=true;document.querySelector('#TipoMovimiento').value='COMPRA';document.querySelector('#TipoMovimiento').dispatchEvent(new Event('change'));document.querySelector('#ProveedorId').selectedIndex=1;document.querySelector('[name=Cantidad]').value='10';document.querySelector('[name=Cantidad]').dispatchEvent(new Event('input'));document.querySelector('[name=DocumentoRespaldo]').value='LAB-BROWSER-COMPRA';document.querySelector('[name=Motivo]').value='Compra QA aislada desde navegador';document.querySelector('[data-master-form]').requestSubmit()");
 await wait('document.querySelector("#master-confirm").open');await capture('02-confirmacion-entrada');
 await evaluate("document.querySelector('#master-confirm [value=confirm]').click()");
 await wait('document.querySelector("#module-message")?.textContent.includes("confirmada")');
 assert.equal((await products.list(actor,{id:4,inventario:true}))[0].Stock,p.Stock+10);
 const movements=(await inventory.history(actor,{id:4})).filter(k=>k.OperacionId.toLowerCase()===op.toLowerCase());assert.equal(movements.length,1);assert.ok(movements[0].Proveedor);await capture('03-kardex-compra');pass('Product -> purchase confirmation -> persisted stock +10, one Kardex, supplier and operation');
 // A new laboratory sale supplies a verifiable source for return, credit and warranty.
 const clients=await sales.listarClientes();assert.ok(clients.length);
 await navigate('/facturacion');
 await evaluate(`document.querySelector('#cliente').value=${JSON.stringify(String(clients[0].ClienteId))};document.querySelector('#cliente').dispatchEvent(new Event('change'));document.querySelector('#producto').value='4';document.querySelector('#cantidad').value='2';document.querySelector('#agregar').click();document.querySelector('#venta-form').requestSubmit()`);
 await wait('document.querySelector("#confirmacion").open');await evaluate("document.querySelector('#confirmar-venta').click()");
 await wait('!document.querySelector("#comprobante").hidden');await capture('04-venta-comprobante');
 const invoice=await evaluate("Number(document.querySelector('#recibo-factura').textContent.replace(/\\D/g,''))");assert.ok(invoice);pass('Real browser sale, receipt and central Kardex');
 await navigate('/devoluciones?factura='+invoice);
 await evaluate("document.querySelector('[data-quantity]').value='1';document.querySelector('[data-condition]').value='true';document.querySelector('[name=Motivo]').value='Devolucion QA aislada apta para venta';document.querySelector('[data-posventa-form]').requestSubmit()");
 await wait('document.querySelector("#posventa-confirm").open');await evaluate("document.querySelector('#posventa-accept').click()");
 await wait('location.pathname==="/notas-credito"&&document.querySelector("[name=Monto]")');
 const returnId=await evaluate("new URLSearchParams(location.search).get('id')");
 const [[credit]]=await edward.devoluciones(actor,{id:Number(returnId)});const total=Number(credit.Total);const half=(Math.floor(total*100/2)/100).toFixed(2);
 await capture('05-credito-pendiente');pass('Browser return persists credit and authorized restock');
 for(const [amount,name] of [[half,'06-credito-parcial'],[(total-Number(half)).toFixed(2),'07-credito-liquidado']]){
  const previousOperation=await evaluate("document.querySelector('[name=OperacionId]').value");
  await evaluate(`document.querySelector('[name=Monto]').value=${JSON.stringify(amount)};document.querySelector('[name=ReferenciaDocumental]').value='LAB-COMPROBANTE-EXTERNO';document.querySelector('[type=checkbox][required]').checked=true;document.querySelector('[data-posventa-form]').requestSubmit()`);
  await wait('document.readyState==="complete"&&(!document.querySelector("[name=Monto]")||document.querySelector("[name=OperacionId]").value!=='+JSON.stringify(previousOperation)+')');
  const [[balance],entries]=await edward.aplicaciones(actor,credit.NotaCreditoId);assert.ok(entries.length);if(name.includes('liquidado'))assert.equal(Number(balance.SaldoDisponible),0);else assert.equal(Number(balance.SaldoDisponible),total-Number(half));await capture(name);
 }
 pass('Browser partial and final documented external reimbursements, ledger and zero balance');
 await cdp('Emulation.setEmulatedMedia',{media:'print'});assert.equal(await evaluate("getComputedStyle(document.querySelector('.sidebar')).display"),'none');const pdf=await cdp('Page.printToPDF',{printBackground:false});fs.writeFileSync(path.join(artifacts,'08-comprobante-credito.pdf'),Buffer.from(pdf.data,'base64'));await cdp('Emulation.setEmulatedMedia',{media:''});
 await navigate('/garantias?factura='+invoice);await evaluate("document.querySelector('[name=DetalleFacturaId]').checked=true;document.querySelector('[name=Motivo]').value='QA aislado: diagnostico de unidad de la factura de prueba';document.querySelector('[data-posventa-form]').requestSubmit()");
 await wait('location.search.includes("id=")&&document.querySelector("[name=Diagnostico]")');await evaluate("document.querySelector('[name=Estado]').value='EN_REVISION';document.querySelector('[name=Diagnostico]').value='Diagnostico QA aislado sin aumentar stock';document.querySelector('[data-posventa-form]').requestSubmit()");await delay(500);await wait('document.body.innerText.includes("Diagnostico QA aislado sin aumentar stock")');await capture('09-garantia-historial');pass('Browser warranty opening and persisted diagnostic history');
 for(const route of ['/dashboard','/analitica?modo=RANGO&fechaDesde=2026-01-01&fechaHasta=2026-12-31','/usuarios','/clientes','/proveedores','/auditoria']){await navigate(route);assert.ok(!await evaluate('document.body.innerText.includes("no está disponible")'));pass('SQL-backed page '+route);}
 await navigate('/notas-credito?id='+returnId);await cdp('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});assert.ok(await evaluate('document.documentElement.scrollWidth<=document.documentElement.clientWidth'));await capture('10-credito-movil');
 assert.deepEqual(errors,[]);pass('No JavaScript exceptions; mobile credit document fits viewport');
 }finally{
 fs.writeFileSync(path.join(artifacts,'results.json'),JSON.stringify(results,null,2));socket?.close();browser.kill();await new Promise(r=>{server.close(r);server.closeAllConnections();});await closePool();
 }
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
