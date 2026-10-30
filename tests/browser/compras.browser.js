'use strict';
// Real Chromium, simulated authenticated services. NEVER opens a SQL connection.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),net=require('node:net');
const {spawn}=require('node:child_process'),{once}=require('node:events');
const {createApp}=require('../../server');
const {mockCompras,permissions}=require('../helpers/comprasFixture');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function main(){
 const mock=mockCompras(),profile=fs.mkdtempSync(path.join(os.tmpdir(),'sf-com-browser-')),artifacts=path.resolve('.data/compras-ui');fs.mkdirSync(artifacts,{recursive:true});
 const app=createApp({secret:'compras-browser-fixture-secret-longer-than-32',comprasService:mock.service,authService:{login:async()=>({codigo:0,usuario:{usuarioId:42,nombreUsuario:'Operador DEMO',permisos:permissions,debeCambiarPassword:false}})}});
 let server,browser,socket;
 try{
  server=app.listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
  const chrome=['C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(fs.existsSync);assert.ok(chrome,'Chromium instalado requerido');
  const reserve=net.createServer().listen(0,'127.0.0.1');await once(reserve,'listening');const port=reserve.address().port;await new Promise(r=>reserve.close(r));
  browser=spawn(chrome,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+port,'--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});
  let page;for(let i=0;i<100;i++){try{page=(await(await fetch('http://127.0.0.1:'+port+'/json/list')).json()).find(p=>p.type==='page');if(page)break;}catch{}await delay(100);}assert.ok(page);
  socket=new WebSocket(page.webSocketDebuggerUrl);await once(socket,'open');let sequence=0;const pending=new Map(),errors=[];
  socket.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.exception?.description||m.params.exceptionDetails.text);const p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}});
  const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence,timer=setTimeout(()=>{pending.delete(id);reject(Error('CDP timeout '+method));},15000);pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params}));});
  const evaluate=async expression=>{const r=await cdp('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.text);return r.result.value;};
  const wait=async expression=>{for(let i=0;i<100;i++){if(await evaluate(expression))return;await delay(50);}throw Error('Timeout: '+expression+'; '+JSON.stringify(await evaluate('({status:document.querySelector("#com-product-status")?.textContent,supplier:document.querySelector("#com-supplier")?.value})'))+'; '+JSON.stringify(errors));};
  await cdp('Page.enable');await cdp('Runtime.enable');
  const go=async route=>{await evaluate('window.__leavingComprasTest=true');await cdp('Page.navigate',{url:base+route});await wait('!window.__leavingComprasTest && document.readyState==="complete" && location.pathname==='+JSON.stringify(route.split('?')[0]));};
  const size=width=>cdp('Emulation.setDeviceMetricsOverride',{width,height:950,deviceScaleFactor:1,mobile:false});
  const capture=async name=>{const r=await cdp('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(path.join(artifacts,name+'.png'),Buffer.from(r.data,'base64'));};
  await go('/login');await evaluate(`fetch('/login',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'NombreUsuario=demo&Password=demo'}).then(()=>true)`);
  for(const width of [1440,1024,768,390]){
   await size(width);
   for(const [name,url] of [['list','/compras'],['new','/compras/nueva'],['detail','/compras/7'],['valuation','/compras/valoracion/3']]){
    await go(url);assert.equal(await evaluate('document.documentElement.scrollWidth<=innerWidth'),true,name+' overflow '+width);await capture(name+'-'+width);
   }
  }
  console.log('PASS UI: cuatro pantallas en 1440, 1024, 768 y 390 px; sin desbordamiento horizontal.');
  await size(1440);await go('/compras/nueva');
  await wait('document.querySelector("#com-supplier").options.length===2');
  await evaluate('document.querySelector("#com-supplier").value="2";document.querySelector("#com-supplier").dispatchEvent(new Event("change"))');await wait('document.querySelector("#com-product").options.length===2');
  await evaluate('document.querySelector("#com-product").value="3";document.querySelector("#com-quantity").value="20";document.querySelector("#com-cost").value="110.1234";document.querySelector("#com-add").click()');
  await evaluate('document.querySelector("#com-add").click()');assert.equal(await evaluate('document.querySelectorAll("#com-lines tr").length'),1);
  assert.equal(await evaluate('document.querySelector("#com-total").textContent'),'Q 2,202.4680');assert.equal(await evaluate('document.querySelector("#com-supplier").disabled'),true);await capture('new-filled');
  await evaluate('document.querySelector("#com-create button[type=submit]").focus();document.querySelector("#com-create").requestSubmit()');await wait('document.querySelector("#com-confirm").open');
  await cdp('Input.dispatchKeyEvent',{type:'keyDown',key:'Tab',code:'Tab',windowsVirtualKeyCode:9});await cdp('Input.dispatchKeyEvent',{type:'keyUp',key:'Tab',code:'Tab',windowsVirtualKeyCode:9});assert.ok(await evaluate('document.querySelector("#com-confirm").contains(document.activeElement)'));
  // The open flag clears before the asynchronous close event releases the submit guard.
  await evaluate('(window.comDialogClosed=new Promise(resolve=>document.querySelector("#com-confirm").addEventListener("close",()=>resolve(true),{once:true}))) && true');
  await cdp('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await cdp('Input.dispatchKeyEvent',{type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await evaluate('window.comDialogClosed.then(()=>new Promise(resolve=>setTimeout(resolve,0)))');await wait('!document.querySelector("#com-confirm").open');assert.equal(mock.calls.filter(c=>c[0]==='create').length,0);
  await evaluate('document.querySelector("#com-create").requestSubmit()');await wait('document.querySelector("#com-confirm").open');await evaluate('document.querySelector("#com-confirm [value=confirm]").click()');await wait('location.pathname==="/compras/7" && document.readyState==="complete"');assert.equal(mock.calls.filter(c=>c[0]==='create').length,1);
  console.log('PASS UI: catálogo, selección, importes exactos, diálogo accesible y creación simulada.');

  const originalSearch=mock.service.search;
  let catalogCalls=[];
  mock.service.search=async(actor,kind,provider,q,page)=>{
    catalogCalls.push({kind,provider,q,page});
    if(q==='lento'){await delay(600);return {rows:[{Id:99,Nombre:'Antiguo',Referencia:'OLD'}],pagina:page,next:false};}
    if(q==='permiso'){const e=Error('denied');e.number=54101;throw e;}
    if(q==='sql')throw Error('SQL unavailable');
    if(q==='estructura')return {rows:null};
    if(q==='vacio')return {rows:[],pagina:page,next:false};
    if(kind==='proveedores')return {rows:page===1?[{Id:2,Nombre:'Proveedor A',Referencia:'NIT-A'},{Id:4,Nombre:'Proveedor B',Referencia:'NIT-B'}]:[{Id:6,Nombre:'Proveedor C',Referencia:'NIT-C'}],pagina:page,next:page===1};
    if(provider===2)await delay(400);
    return {rows:provider===4?[]:[{Id:page===1?3:5,Nombre:'Producto A',Referencia:'SKU-A'}],pagina:page,next:provider===2&&page===1};
  };
  await go('/compras/nueva');await wait('document.querySelector("#com-supplier").options.length===3');
  assert.equal(catalogCalls.length,1,'automatic initial request');
  await evaluate('document.querySelector("#com-supplier").focus()');
  await cdp('Input.dispatchKeyEvent',{type:'keyDown',key:'ArrowDown',code:'ArrowDown',windowsVirtualKeyCode:40});
  await cdp('Input.dispatchKeyEvent',{type:'keyUp',key:'ArrowDown',code:'ArrowDown',windowsVirtualKeyCode:40});
  await wait('document.querySelector("#com-supplier").value==="2"');
  await evaluate('document.querySelector("#com-product-search").click();document.querySelector("#com-product-search").click()');
  await wait('document.querySelector("#com-product").options.length===2');
  assert.equal(catalogCalls.filter(c=>c.kind==='productos').length,1,'deduplicates pending requests');
  await evaluate('document.querySelector("#com-product-pages button").click()');
  await wait('document.querySelector("#com-product-status").textContent.includes("2 resultados") || document.querySelector("#com-product").options[1]?.value==="5"');
  assert.equal(catalogCalls.at(-1).page,2);
  await evaluate('document.querySelector("#com-product-query").value="SKU-A";document.querySelector("#com-product-query").dispatchEvent(new Event("input"))');
  await wait('document.querySelector("#com-product").options[1]?.value==="3"');
  assert.equal(catalogCalls.at(-1).q,'SKU-A');

  await evaluate('document.querySelector("#com-supplier-pages button").click()');await wait('document.querySelector("#com-supplier-status").textContent.includes("Página 2")');
  assert.equal(await evaluate('document.querySelector("#com-supplier").value'),'2','selection retained across pages');
  assert.equal(await evaluate('document.querySelector("#com-product").options.length'),2);
  await evaluate('document.querySelector("#com-supplier-pages button").click()');await wait('document.querySelector("#com-supplier-status").textContent.includes("Página 1")');
  await evaluate('document.querySelector("#com-supplier").value="";document.querySelector("#com-supplier").dispatchEvent(new Event("change"));document.querySelector("#com-supplier").value="2";document.querySelector("#com-supplier").dispatchEvent(new Event("change"))');
  await delay(50);
  await evaluate('document.querySelector("#com-supplier").value="4";document.querySelector("#com-supplier").dispatchEvent(new Event("change"))');
  await wait('document.querySelector("#com-product-status").textContent.includes("No hay productos activos")');await delay(450);
  assert.equal(await evaluate('document.querySelector("#com-product").options.length'),1,'late supplier products discarded');
  assert.equal(await evaluate('document.querySelector("#com-product-manage").hidden'),false);
  const query=async value=>evaluate('document.querySelector("#com-supplier-query").value='+JSON.stringify(value)+';document.querySelector("#com-supplier-query").dispatchEvent(new Event("input"))');
  await query('lento');await delay(300);await query('vacio');
  await wait('document.querySelector("#com-supplier-status").textContent.includes("Sin coincidencias")');await delay(400);
  assert.equal(await evaluate('[...document.querySelector("#com-supplier").options].some(o=>o.value==="99")'),false);
  assert.equal(await evaluate('document.activeElement.id'),'com-supplier','background requests do not steal focus');
  for(const [q,text] of [['permiso','HTTP 403'],['sql','HTTP 503'],['estructura','inesperada']]){
    await query(q);await wait('document.querySelector("#com-supplier-status").textContent.includes('+JSON.stringify(text)+')');
  }
  mock.service.search=async()=>({rows:[],pagina:1,next:false});
  await go('/compras/nueva');await wait('document.querySelector("#com-supplier-status").textContent.includes("No hay proveedores activos")');
  mock.service.search=originalSearch;
  console.log('PASS UI: carga automática, teclado, paginación, selección conservada, debounce, solicitudes duplicadas, cambio rápido, vacíos, HTTP 403/503 y contrato inválido.');
  mock.orden.Estado='APROBADA';await go('/compras/7');
  await evaluate('document.querySelector("#com-document").value="DOC-DEMO";document.querySelector("#com-receive-reason").value="Entrega verificada";document.querySelector("[data-quantity]").value="21";document.querySelector("[data-receive-form]").requestSubmit()');
  assert.equal(await evaluate('document.querySelector("[data-quantity]").validity.rangeOverflow'),true);assert.equal(mock.calls.filter(c=>c[0]==='receive').length,0);
  await evaluate('document.querySelector("[data-quantity]").value="10";document.querySelector("[data-cost]").value="100.1234";document.querySelector("[data-receive-form]").requestSubmit()');await wait('document.querySelector("#com-confirm").open');await capture('receive-confirmation');await evaluate('document.querySelector("#com-confirm [value=confirm]").click()');await wait('document.body.innerText.includes("Recepción parcial") && !document.querySelector("#com-confirm").open');
  assert.equal(mock.calls.filter(c=>c[0]==='receive').length,1);assert.equal(mock.detalle[0].Pendiente,'10');await capture('partial-received');
  await cdp('Emulation.setEmulatedMedia',{media:'print'});assert.equal(await evaluate('getComputedStyle(document.querySelector(".sidebar")).display'),'none');const pdf=await cdp('Page.printToPDF',{printBackground:false,preferCSSPageSize:true});fs.writeFileSync(path.join(artifacts,'order.pdf'),Buffer.from(pdf.data,'base64'));await cdp('Emulation.setEmulatedMedia',{media:''});
  console.log('PASS UI: límite de entrega en formulario, recepción parcial simulada, historial e impresión PDF.');
  const originalCreate=mock.service.create;let lost=true;
  mock.service.create=async(actor,data)=>{const result=await originalCreate(actor,data);if(lost){lost=false;throw Error('Simulated lost confirmation');}return result;};
  await go('/compras/nueva');
  await wait('document.querySelector("#com-supplier").options.length===2');
  await evaluate('document.querySelector("#com-supplier").value="2";document.querySelector("#com-supplier").dispatchEvent(new Event("change"))');await wait('document.querySelector("#com-product").options.length===2');
  await evaluate('document.querySelector("#com-product").value="3";document.querySelector("#com-cost").value="0.1234";document.querySelector("#com-add").click();document.querySelector("#com-create").requestSubmit()');await wait('document.querySelector("#com-confirm").open');await evaluate('document.querySelector("#com-confirm [value=confirm]").click()');await wait('document.querySelector("#com-message").textContent.includes("No se pudo confirmar")');
  const uncertain=mock.calls.filter(c=>c[0]==='create').at(-1)[2];await go('/compras/nueva');
  assert.ok(await evaluate('document.querySelector("#com-create").noValidate'));
  await evaluate('document.querySelector("#com-create").requestSubmit()');await wait('document.querySelector("#com-confirm").open');await evaluate('document.querySelector("#com-confirm [value=confirm]").click()');await wait('location.pathname==="/compras/7"');
  assert.deepEqual(mock.calls.filter(c=>c[0]==='create').at(-1)[2],uncertain);
  console.log('PASS UI: respuesta incierta y recarga conservan UUID y contenido exacto en el reintento.');
  assert.deepEqual(errors,[]);console.log('PASS UI: sin excepciones JavaScript. Evidencia sintética: '+artifacts);
 }finally{socket?.close();if(browser){browser.kill();await once(browser,'exit').catch(()=>{});}if(server)await new Promise(r=>{server.close(r);server.closeAllConnections();});/* Profile retained in OS temp; no user data. */}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
