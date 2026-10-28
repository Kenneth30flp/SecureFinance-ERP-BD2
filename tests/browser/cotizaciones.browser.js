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
const {createProductoService}=require('../../src/services/productoService');
const {createClienteService}=require('../../src/services/clienteService');
const {createInventarioService}=require('../../src/services/inventarioService');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function run(){
 let server,browser,socket;
 const results={authentication:'SESSION_FIXTURE_NOT_REAL_LOGIN',database:'ISOLATED_P3_COT_LAB',checks:[],conversion:'NOT_RUN',faultInjection:'One post-COMMIT service response fails with HTTP 503; all business operations use real SQL'};
 const artifacts='docs/parte3/cotizaciones/redisenio/evidencias-pruebas';fs.mkdirSync(artifacts,{recursive:true});
 try{
 const pool=await getPool();assert.equal((await pool.request().query('SELECT DB_NAME() N')).recordset[0].N,state.lab);
 const permisos=(await pool.request().input('UsuarioId',sql.Int,state.actor).execute('dbo.sp_ObtenerPermisosUsuario')).recordset.map(p=>p.Codigo);
 const realService=createCotizacionService();let loseResponseFor=null,lostResponse=false;
 const cotizacionService={...realService,async convert(actor,id,operation){const result=await realService.convert(actor,id,operation);if(id===loseResponseFor&&!lostResponse){lostResponse=true;throw Error('QA respuesta perdida despues de COMMIT');}return result;}};
 const app=createApp({production:false,cotizacionService,authService:{login:async()=>({codigo:0,usuario:{usuarioId:state.actor,nombreUsuario:'QA_COT_SESSION_FIXTURE',permisos,debeCambiarPassword:false}})}});
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
 const wait=async expression=>{for(let i=0;i<100;i++){if(await evaluate(expression))return;await delay(100);}throw Error('DOM timeout '+expression+' / '+JSON.stringify(errors)+' / '+await evaluate('document.body.innerText.slice(-1200)'));};
 const navigate=async route=>{await cdp('Page.navigate',{url:base+route});await wait('location.href==='+JSON.stringify(base+route)+'&&document.readyState==="complete"');};
 const capture=async name=>{const r=await cdp('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(path.join(artifacts,name+'.png'),Buffer.from(r.data,'base64'));};
 const pass=name=>{results.checks.push(name);console.log('PASS BROWSER '+name);};
 async function selectPicker(kind,id){
  const item=kind==='clientes'?(await createClienteService().list(state.actor,{id}))[0]:(await createProductoService().list(state.actor,{id,costo:true}))[0];
  const selector=kind==='clientes'?'#cot-client-search':'#cot-search',term=kind==='clientes'?item.NIT:item.Codigo;
  await evaluate('(()=>{const i=document.querySelector('+JSON.stringify(selector)+');i.focus();i.value='+JSON.stringify(term)+';i.dispatchEvent(new Event("input",{bubbles:true}));})()');
  await wait('Boolean(document.querySelector(\'[data-picker="'+kind+'"] .cot-option[data-id="'+id+'"]\'))');
  const index=await evaluate('[...document.querySelectorAll(\'[data-picker="'+kind+'"] .cot-option\')].findIndex(e=>e.dataset.id==='+JSON.stringify(String(id))+')');
  for(let i=0;i<=index;i++)await cdp('Input.dispatchKeyEvent',{type:'keyDown',key:'ArrowDown',code:'ArrowDown',windowsVirtualKeyCode:40});
  await cdp('Input.dispatchKeyEvent',{type:'keyDown',key:'Enter',code:'Enter',windowsVirtualKeyCode:13});
  assert.equal(await evaluate('document.querySelector('+JSON.stringify(kind==='clientes'?'#cot-client':'#cot-product')+').value'),String(id));
 }
 await cdp('Page.enable');await cdp('Runtime.enable');await cdp('Emulation.setDeviceMetricsOverride',{width:1366,height:900,deviceScaleFactor:1,mobile:false});
 await navigate('/login');await evaluate("document.querySelector('[name=NombreUsuario]').value='QA_COT_SESSION_FIXTURE';document.querySelector('[name=Password]').value='fixture';document.querySelector('form').requestSubmit()");await wait('location.pathname==="/dashboard"&&document.readyState==="complete"');
 await navigate('/cotizaciones/nueva');assert.ok(await evaluate('Boolean(document.querySelector(\'a[aria-label="Cotizaciones"]\'))'));
 await selectPicker('clientes',sqlResult.clientId);await selectPicker('productos',sqlResult.productId);
 await evaluate(`document.querySelector('#cot-quantity').value='2';document.querySelector('#cot-discount').value='10';document.querySelector('#cot-expiry').value=${JSON.stringify(new Date(Date.now()+2*86400000).toISOString().slice(0,10))};document.querySelector('#cot-notes').value='QA navegador SQL real: documento interno de laboratorio';document.querySelector('#cot-add').click();`);
 assert.match(await evaluate("document.querySelector('#cot-total').textContent"),/241\.92/);await capture('01-nueva-cotizacion-desktop');pass('menu, cliente, producto, descuento y calculo preliminar real');
 await evaluate("document.querySelector('#cot-create').requestSubmit()");await wait('/^\\/cotizaciones\\/\\d+$/.test(location.pathname)&&document.readyState==="complete"');
 const id=await evaluate('Number(location.pathname.split("/").pop())');const service=createCotizacionService(),document=await service.detail(state.actor,id);assert.equal(document.documento.Total,'241.92');assert.equal(document.lineas[0].Cantidad,2);await capture('02-detalle-cotizacion-desktop');pass('alta HTTP y documento persistido SQL con totales definitivos');
 await cdp('Emulation.setEmulatedMedia',{media:'print'});assert.equal(await evaluate("getComputedStyle(document.querySelector('.sidebar')).display"),'none');const pdf=await cdp('Page.printToPDF',{printBackground:false});fs.writeFileSync(path.join(artifacts,'03-comprobante-interno.pdf'),Buffer.from(pdf.data,'base64'));await cdp('Emulation.setEmulatedMedia',{media:''});pass('comprobante imprimible sin presentar factura tributaria');
 await navigate('/cotizaciones?numero='+document.documento.Numero);assert.ok(await evaluate('document.body.innerText.includes('+JSON.stringify(document.documento.Numero)+')'));await capture('04-historial-filtrado-desktop');pass('historial y busqueda por numero');
 for(const width of [1024,768,390,320]){await cdp('Emulation.setDeviceMetricsOverride',{width,height:900,deviceScaleFactor:1,mobile:false});for(const route of ['/cotizaciones','/cotizaciones/nueva','/cotizaciones/'+id]){await navigate(route);assert.ok(await evaluate('document.documentElement.scrollWidth<=document.documentElement.clientWidth'),route+' width '+width);}await capture('05-detalle-'+width);pass('sin desborde global en listado, alta y detalle a '+width+'px');}
 await cdp('Page.setInterceptFileChooserDialog',{enabled:false});
 // Confirm dialog is handled explicitly; cancellation is the only document mutation here.
 await evaluate("document.querySelector('.cot-cancel-panel').open=true;document.querySelector('#cot-reason').value='Cancelacion QA navegador';document.querySelector('#cot-cancel').requestSubmit();");await wait('document.querySelector("#cot-confirm").open');await evaluate('document.querySelector(\'#cot-confirm [value="confirm"]\').click()');await wait('document.body.innerText.includes("CANCELADA")&&!document.querySelector("#cot-cancel")');assert.equal((await service.detail(state.actor,id)).documento.Estado,'CANCELADA');await capture('06-cancelacion-movil');pass('confirmacion y cancelacion persistida con historial');
 const uc09=JSON.parse(fs.readFileSync('.data/uc09-sql.json','utf8'));assert.equal(uc09.lab,state.lab);
 // Fresh browser-owned fixture permits repeat runs without rewriting previous SQL evidence.
 const fixtureProducts=createProductoService(),template=(await fixtureProducts.list(state.actor,{id:uc09.productId,costo:true}))[0];
 const fresh=(await fixtureProducts.save(state.actor,{CodigoAutomatico:true,Codigo:null,Descripcion:'QA UI UC09 '+Date.now(),Precio:'100.00',PrecioCosto:'40.00',ProveedorId:template.ProveedorId,StockMinimo:1,PuntoReorden:2,GarantiaMeses:0,Fotografia:null}))[0];
 uc09.productId=fresh.ProductoId;
 await createInventarioService().receive(state.actor,{id:fresh.ProductoId,ProveedorId:template.ProveedorId,Cantidad:12,DocumentoRespaldo:'QA UI UC09',Motivo:'Fixture exclusiva navegador en QA',OperacionId:require('node:crypto').randomUUID(),CostoUnitario:'40.00'});
 await cdp('Emulation.setDeviceMetricsOverride',{width:1366,height:900,deviceScaleFactor:1,mobile:false});await navigate('/cotizaciones/nueva');
 await selectPicker('clientes',uc09.clientId);await selectPicker('productos',uc09.productId);
 await evaluate(`document.querySelector('#cot-quantity').value='2';document.querySelector('#cot-discount').value='10';document.querySelector('#cot-expiry').value=${JSON.stringify(new Date(Date.now()+2*86400000).toISOString().slice(0,10))};document.querySelector('#cot-notes').value='QA UC09: precio pactado 100 y conversion de contado';document.querySelector('#cot-add').click();document.querySelector('#cot-create').requestSubmit();`);
 await wait('/^\\/cotizaciones\\/\\d+$/.test(location.pathname)&&document.readyState==="complete"&&Boolean(document.querySelector("#cot-convert"))');
 const conversionId=await evaluate('Number(location.pathname.split("/").pop())'),operation=await evaluate('document.querySelector("#cot-convert").dataset.operation');
 const productService=createProductoService(),current=(await productService.list(state.actor,{id:uc09.productId,costo:true}))[0];
 const beforeStock=current.Stock;await productService.save(state.actor,{...current,id:current.ProductoId,Precio:'120.00',Fotografia:null});
 await capture('07-conversion-precio-pactado-100');
 async function submitConfirmation(accept){await wait('!document.querySelector("#cot-convert button").disabled&&document.querySelector("#cot-convert button").getAttribute("aria-busy")!=="true"');await evaluate('document.querySelector("#cot-convert").requestSubmit()');await wait('document.querySelector("#cot-confirm").open');await evaluate('document.querySelector(\'#cot-confirm [value="'+(accept?'confirm':'cancel')+'"]\').click()');await wait('!document.querySelector("#cot-confirm").open');}
 await submitConfirmation(false);assert.equal((await service.detail(state.actor,conversionId)).documento.Estado,'ACTIVA');pass('cancelar confirmacion de conversion no genera factura');
 loseResponseFor=conversionId;await submitConfirmation(true);
 await wait('!document.querySelector("#cot-message").hidden&&document.querySelector("#cot-message").innerText.includes("Referencia conservada")');
 assert.equal((await service.detail(state.actor,conversionId)).documento.Estado,'PROCESADA');assert.equal(await evaluate('document.querySelector("#cot-convert").dataset.operation'),operation);await capture('08-respuesta-incierta-referencia-conservada');pass('HTTP 503 inyectado despues de COMMIT mantiene UUID y permite recuperar resultado real');
 await submitConfirmation(true);await wait('document.readyState==="complete"&&document.body.innerText.includes("PROCESADA")&&!document.querySelector("#cot-convert")');
 const converted=await service.detail(state.actor,conversionId),invoice=converted.documento.FacturaId;assert.ok(invoice);await capture('09-cotizacion-procesada');
 await navigate('/facturacion/facturas/'+invoice);assert.ok(await evaluate('document.body.innerText.includes("100.00")&&document.body.innerText.includes("201.60")'));await capture('10-factura-precio-historico');
 const afterProduct=(await productService.list(state.actor,{id:uc09.productId,costo:true}))[0];assert.equal(Number(afterProduct.Precio),120);assert.equal(afterProduct.Stock,beforeStock-2);pass('conversion desde UI y reintento generan factura a 100, catalogo 120 y una salida de dos unidades');
 await navigate('/inventario?id='+uc09.productId);assert.ok(await evaluate('document.body.innerText.includes("VENTA")'));await capture('11-kardex-salida-unica');pass('Kardex real accesible desde navegador');
 await navigate('/cotizaciones/'+conversionId);const manual=await evaluate(`(async()=>{const r=await fetch('/cotizaciones/${conversionId}/convertir',{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name="csrf-token"]').content},body:JSON.stringify({OperacionId:${JSON.stringify(operation)}})});return {status:r.status,data:await r.json()};})()`);assert.equal(manual.status,200);assert.equal(manual.data.documento.FacturaId,invoice);
 const badCsrf=await evaluate(`(async()=>{const r=await fetch('/cotizaciones/${conversionId}/convertir',{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':'bad'},body:JSON.stringify({OperacionId:${JSON.stringify(operation)}})});return r.status;})()`);assert.equal(badCsrf,403);pass('HTTP real: reintento idempotente y CSRF invalido rechazado');
 for(const width of [390,320]){await cdp('Emulation.setDeviceMetricsOverride',{width,height:900,deviceScaleFactor:1,mobile:false});await navigate('/cotizaciones/'+conversionId);assert.ok(await evaluate('document.documentElement.scrollWidth<=document.documentElement.clientWidth'));await capture('12-procesada-'+width);await navigate('/facturacion/facturas/'+invoice);assert.ok(await evaluate('document.documentElement.scrollWidth<=document.documentElement.clientWidth'));await capture('13-factura-'+width);}
 pass('cotizacion procesada y factura en movil 390/320 sin desborde');results.conversion='PASS';results.quoteId=conversionId;results.invoiceId=invoice;results.priceInvoice='100.00';results.priceCatalog='120.00';results.stockBefore=beforeStock;results.stockAfter=afterProduct.Stock;
 assert.deepEqual(errors,[]);pass('cero excepciones JavaScript');
 }finally{
 fs.writeFileSync(path.join(artifacts,'navegador.json'),JSON.stringify(results,null,2));socket?.close();browser?.kill();if(server)await new Promise(r=>{server.close(r);server.closeAllConnections();});await closePool();
 }
}
run().catch(e=>{console.error('BROWSER FAIL',e.message);process.exitCode=1;});
