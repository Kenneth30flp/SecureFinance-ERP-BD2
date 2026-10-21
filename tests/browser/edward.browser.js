'use strict';
const assert=require('node:assert/strict');
const {spawn}=require('node:child_process');
const {once}=require('node:events');
const {mkdtemp,mkdir,writeFile}=require('node:fs/promises');
const {existsSync}=require('node:fs');
const {tmpdir}=require('node:os');
const path=require('node:path');
const net=require('node:net');
const {createApp}=require('../../server');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
function inspectContrast(){
 const rgb=v=>(v.match(/[\d.]+/g)||[]).map(Number);
 const blend=(front,back)=>front.slice(0,3).map((n,i)=>n*(front[3]??1)+back[i]*(1-(front[3]??1)));
 const lum=c=>c.slice(0,3).map(n=>{n/=255;return n<=.04045?n/12.92:((n+.055)/1.055)**2.4;}).reduce((s,n,i)=>s+n*[.2126,.7152,.0722][i],0);
 const walker=document.createTreeWalker(document.querySelector('.posventa-workspace'),NodeFilter.SHOW_TEXT);let node;const failures=[];
 while((node=walker.nextNode())){
  const el=node.parentElement,text=node.textContent.trim();if(!text||el.closest('script,style,option,[aria-hidden=true]')||!el.getClientRects().length||getComputedStyle(el).visibility==='hidden')continue;
  const ancestors=[];for(let p=el;p;p=p.parentElement)ancestors.unshift(p);
  let bg=[255,255,255];for(const p of ancestors)bg=blend(rgb(getComputedStyle(p).backgroundColor),bg);
  const style=getComputedStyle(el),a=lum(blend(rgb(style.color),bg)),b=lum(bg),ratio=(Math.max(a,b)+.05)/(Math.min(a,b)+.05);
  const large=parseFloat(style.fontSize)>=24||(parseFloat(style.fontSize)>=18.66&&parseInt(style.fontWeight)>=700);
  if(ratio<(large?3:4.5)-.02)failures.push({text:text.slice(0,50),ratio:ratio.toFixed(2)});
 }
 return failures;
}
async function main(){
 const browserPath=[process.argv[2],'C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(p=>p&&existsSync(p));
 assert.ok(browserPath,'Chromium required');
 const directory=await mkdtemp(path.join(tmpdir(),'edward-ui-'));
 const stage=process.env.POSVENTA_CAPTURE_STAGE||'after';
 const artifacts=path.resolve('.data/posventa-final',stage);await mkdir(artifacts,{recursive:true});
 let returns=0,tickets=0,updates=0;
 const p=['DEVOLUCIONES_CONSULTAR','DEVOLUCIONES_REGISTRAR','DEVOLUCIONES_AUTORIZAR','GARANTIAS_CONSULTAR','GARANTIAS_GESTIONAR','INVENTARIO_REGISTRAR'];
 const returned={DevolucionId:1,NotaCreditoId:1,FacturaId:1,Cliente:'Cliente de prueba',FechaHora:'2026-10-20T10:00:00Z',Estado:'EMITIDA',EstadoCredito:'PENDIENTE',Subtotal:'10.00',Descuento:'1.00',IVA:'1.08',Total:'10.08',Motivo:'Defecto',Responsable:'operador',OperacionId:'00000000-0000-0000-0000-000000000001'};
 const ticket={TicketId:1,FacturaId:1,Cliente:'Cliente de prueba',Descripcion:'Producto de prueba',FechaApertura:'2026-10-20T10:00:00Z',Estado:'RECIBIDO',Cobertura:'NO_VERIFICADA',Motivo:'Falla',Responsable:'operador',Version:'0000000000000001'};
 const app=createApp({secret:'edward-browser-test-session-secret-1234',production:false,
 authService:{login:async name=>({codigo:0,usuario:{usuarioId:1,nombreUsuario:name,permisos:name==='lector'?['DEVOLUCIONES_CONSULTAR']:p}})},
 edwardService:{
 factura:async(a,id)=>id===999?[[],[]]:[[{FacturaId:1,Cliente:'Cliente de prueba',NIT:'CF',Total:'20.16'}],[{DetalleFacturaId:1,Descripcion:'Producto de prueba',Cantidad:2,Devuelto:returns,Disponible:2-returns,PrecioUnitario:'10.00'}]],
 devoluciones:async()=>returns?[[returned],[{Descripcion:'Producto de prueba',Cantidad:1,PrecioUnitario:'10.00',Descuento:'1.00',IVA:'1.08',Total:'10.08',Reingresar:false}]]:[[],[]],
 garantias:async(a,f)=>{if(f.buscar==='fallo-servicio')throw Error('Fixture unavailable');if(f.buscar==='sin-coincidencias'||f.id===999)return[[],[]];return tickets?[[ticket],[{EstadoAnterior:null,EstadoNuevo:'RECIBIDO',Diagnostico:'Falla',FechaHora:ticket.FechaApertura,Responsable:'operador'}]]:[[],[]];},
 devolver:async(actor,body)=>{assert.equal(actor,1);assert.equal(body.Detalles[0].Cantidad,1);returns++;return {DevolucionId:1};},
 crear:async()=>{tickets++;return {TicketId:1};},
 actualizar:async()=>{updates++;await delay(120);throw Object.assign(new Error('stale'),{number:54603});}
 }});
 const server=app.listen(0,'127.0.0.1');await once(server,'listening');
 const base='http://127.0.0.1:'+server.address().port;
 const reservation=net.createServer().listen(0,'127.0.0.1');await once(reservation,'listening');
 const port=reservation.address().port;await new Promise(r=>reservation.close(r));
 const browser=spawn(browserPath,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+port,'--user-data-dir='+path.join(directory,'profile'),'about:blank'],{windowsHide:true,stdio:'ignore'});
 let socket;
 try{
 let pages;for(let i=0;i<100;i++){try{pages=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();if(pages.some(p=>p.type==='page'))break;}catch{}await delay(100);}
 socket=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);await once(socket,'open');
 let seq=0;const pending=new Map(),errors=[];
 socket.addEventListener('message',event=>{const m=JSON.parse(event.data);if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.text);const task=pending.get(m.id);if(task){pending.delete(m.id);clearTimeout(task.timer);m.error?task.reject(Error(m.error.message)):task.resolve(m.result);}});
 const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq;const timer=setTimeout(()=>{pending.delete(id);reject(Error('CDP timeout'));},10000);pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params}));});
 const evaluate=async expression=>{const r=await cdp('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.text);return r.result.value;};
 const wait=async expression=>{for(let i=0;i<100;i++){if(await evaluate(expression))return;await delay(50);}throw Error('DOM timeout: '+expression);};
 const navigate=async route=>{await cdp('Page.navigate',{url:base+route});await wait('location.href==='+JSON.stringify(base+route)+' && document.readyState==="complete"');};
 const capture=async name=>{
  for(const [width,height] of [[1920,1080],[1366,768],[768,900],[390,844],[320,740]]){
   await cdp('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});await delay(180);
   assert.equal(await evaluate('document.documentElement.scrollWidth<=document.documentElement.clientWidth'),true,name+' responsive '+width);
   if(stage!=='before')assert.deepEqual(await evaluate('('+inspectContrast.toString()+')()'),[],name+' contrast '+width);
   const {cssContentSize}=await cdp('Page.getLayoutMetrics');
   const shot=await cdp('Page.captureScreenshot',{captureBeyondViewport:true,clip:{x:0,y:0,width:await evaluate('window.innerWidth'),height:cssContentSize.height,scale:1}});
   await writeFile(path.join(artifacts,name+'-'+width+'.png'),Buffer.from(shot.data,'base64'));
  }
 };
 await cdp('Page.enable');await cdp('Runtime.enable');
 await navigate('/login');await evaluate("fetch('/login',{method:'POST',body:new URLSearchParams({NombreUsuario:'operador',Password:'test'}),redirect:'manual'})");
 for(const route of ['devoluciones','notas-credito','garantias']){await navigate('/'+route);await capture(route+'-empty');}
 await navigate('/devoluciones?factura=999');await capture('invoice-not-found');
 await navigate('/devoluciones?factura=1');
 await capture('devoluciones-form');
 for(const width of [1366,768,390,320]){
 await cdp('Emulation.setDeviceMetricsOverride',{width,height:900,deviceScaleFactor:1,mobile:false});
 assert.equal(await evaluate('document.documentElement.scrollWidth<=document.documentElement.clientWidth'),true,'Responsive '+width);
 const shot=await cdp('Page.captureScreenshot');await writeFile(path.join(artifacts,'devoluciones-'+width+'.png'),Buffer.from(shot.data,'base64'));
 }
 await evaluate("document.querySelector('[data-quantity]').value='1';document.querySelector('[name=Motivo]').value='Defecto';document.querySelector('[data-posventa-form]').requestSubmit()");
 assert.equal(await evaluate("document.getElementById('posventa-confirm').open"),true);assert.equal(returns,0);
 if(stage!=='before')assert.equal(await evaluate('document.activeElement.id'),'posventa-cancel');
 if(stage!=='before'){
  await cdp('Input.dispatchKeyEvent',{type:'keyDown',key:'Tab',code:'Tab',windowsVirtualKeyCode:9});
  await cdp('Input.dispatchKeyEvent',{type:'keyUp',key:'Tab',code:'Tab',windowsVirtualKeyCode:9});
  assert.equal(await evaluate('document.activeElement.id'),'posventa-accept');
 }
 await capture('devoluciones-confirm');
 await evaluate("document.getElementById('posventa-cancel').click()");assert.equal(returns,0);
 if(stage!=='before'){
  await wait("document.activeElement===document.querySelector('[data-posventa-form] button[type=submit]')");
  await evaluate("document.querySelector('[data-posventa-form]').requestSubmit()");
  await cdp('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});
  await cdp('Input.dispatchKeyEvent',{type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});
  await wait("!document.getElementById('posventa-confirm').open");assert.equal(returns,0);
 }
 await evaluate("document.querySelector('[data-posventa-form]').requestSubmit();document.getElementById('posventa-accept').click()");
 await wait('location.pathname==="/notas-credito" && document.readyState==="complete"');
 assert.equal(returns,1);assert.match(await evaluate('document.body.innerText'),/No se ha registrado un reembolso/);
 await capture('notas-credito-detail');
 if(stage!=='before')assert.equal(await evaluate("window.__printCalls=0;window.print=()=>window.__printCalls++;document.querySelector('[data-print]').click();window.__printCalls"),1);
 await cdp('Emulation.setDeviceMetricsOverride',{width:794,height:1123,deviceScaleFactor:1,mobile:false});
 await cdp('Emulation.setEmulatedMedia',{media:'print'});assert.equal(await evaluate("getComputedStyle(document.querySelector('.sidebar')).display"),'none');
 if(stage!=='before'){
  assert.equal(await evaluate("getComputedStyle(document.querySelector('#comprobante')).backgroundColor"),'rgb(255, 255, 255)');
  assert.equal(await evaluate("document.querySelector('#comprobante .posventa-table').scrollWidth<=document.documentElement.clientWidth"),true,'Print table fits A4');
  const pdf=await cdp('Page.printToPDF',{printBackground:true,preferCSSPageSize:true});await writeFile(path.join(artifacts,'nota-credito-a4.pdf'),Buffer.from(pdf.data,'base64'));
 }
 await cdp('Emulation.setEmulatedMedia',{media:''});
 await navigate('/garantias?factura=1');
 await capture('garantias-form');
 await evaluate("document.querySelector('[name=DetalleFacturaId]').checked=true;document.querySelector('[name=Motivo]').value='Falla';document.querySelector('[data-posventa-form]').requestSubmit()");
 await wait('location.search==="?id=1" && document.readyState==="complete"');assert.equal(tickets,1);
 await capture('garantias-history');
 await evaluate("document.querySelector('[name=Estado]').value='EN_REVISION';document.querySelector('[name=Diagnostico]').value='Borrador técnico';document.querySelector('[data-posventa-form]').requestSubmit()"+(stage==='before'?'':";document.querySelector('[data-posventa-form]').requestSubmit()"));
 await wait("document.getElementById('posventa-message').textContent.includes('registro cambió')");
 assert.equal(updates,1);assert.equal(await evaluate("document.querySelector('[name=Diagnostico]').value"),'Borrador técnico');
 assert.equal(await evaluate("document.activeElement.id"),'posventa-message');
 if(stage!=='before'){
  await capture('garantias-conflict');
  await navigate('/garantias?buscar=sin-coincidencias');assert.match(await evaluate('document.body.innerText'),/Sin coincidencias/);await capture('filtered-empty');
  await navigate('/garantias?id=999');assert.match(await evaluate('document.body.innerText'),/Registro no encontrado/);
  const failure=await evaluate("fetch('/garantias?buscar=fallo-servicio').then(async r=>({status:r.status,body:await r.text()}))");assert.equal(failure.status,503);assert(failure.body.includes('Posventa no disponible'));assert(!failure.body.includes('Sin solicitudes de garantía'));
  await navigate('/garantias');assert.equal(await evaluate("document.querySelectorAll('.posventa-tabs [aria-current=page]').length"),1);
  await cdp('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'reduce'}]});
  assert.equal(await evaluate("getComputedStyle(document.querySelector('.posventa-tabs a')).transitionDuration"),'0s');
  await cdp('Emulation.setDeviceMetricsOverride',{width:683,height:384,deviceScaleFactor:1,mobile:false});assert.equal(await evaluate('document.documentElement.scrollWidth<=document.documentElement.clientWidth'),true,'200% equivalent viewport');
  await evaluate("fetch('/logout').then(()=>fetch('/login',{method:'POST',body:new URLSearchParams({NombreUsuario:'lector',Password:'test'}),redirect:'manual'}))");
  await navigate('/devoluciones?factura=1');assert.equal(await evaluate("document.querySelectorAll('.posventa-tabs a').length"),2);assert.equal(await evaluate("document.querySelector('[data-posventa-form] button[type=submit]')===null"),true);assert.equal(await evaluate("document.querySelector('[data-condition] option[value=true]')===null"),true);
 }
 assert.deepEqual(errors,[]);
 console.log('PASS Edward Chromium: 1920/1366/768/390/320, confirmation/cancel, receipt, print, ticket creation, conflict retains diagnosis and focus; final checks include Escape, double-submit, RBAC, filters, service errors, reduced motion and 200% equivalent viewport.');
 console.log('Screenshots: '+artifacts);
 }finally{
 socket?.close();await new Promise(r=>{server.close(r);server.closeAllConnections();});
 if(browser.exitCode===null){const closed=once(browser,'exit');browser.kill();await closed;}
 }
}
main().catch(e=>{console.error(e.stack);process.exitCode=1;});
