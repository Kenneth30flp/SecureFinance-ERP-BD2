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
async function main(){
 const browserPath=[process.argv[2],'C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(p=>p&&existsSync(p));
 assert.ok(browserPath,'Chromium required');
 const directory=await mkdtemp(path.join(tmpdir(),'edward-ui-'));
 const artifacts=path.resolve('.data/edward-ui');await mkdir(artifacts,{recursive:true});
 let returns=0,tickets=0,updates=0;
 const p=['DEVOLUCIONES_CONSULTAR','DEVOLUCIONES_REGISTRAR','DEVOLUCIONES_AUTORIZAR','GARANTIAS_CONSULTAR','GARANTIAS_GESTIONAR','INVENTARIO_REGISTRAR'];
 const returned={DevolucionId:1,NotaCreditoId:1,FacturaId:1,Cliente:'Cliente de prueba',FechaHora:'2026-10-20T10:00:00Z',Estado:'EMITIDA',EstadoCredito:'PENDIENTE',Subtotal:'10.00',Descuento:'1.00',IVA:'1.08',Total:'10.08',Motivo:'Defecto',Responsable:'operador',OperacionId:'00000000-0000-0000-0000-000000000001'};
 const ticket={TicketId:1,FacturaId:1,Cliente:'Cliente de prueba',Descripcion:'Producto de prueba',FechaApertura:'2026-10-20T10:00:00Z',Estado:'RECIBIDO',Cobertura:'NO_VERIFICADA',Motivo:'Falla',Responsable:'operador',Version:'0000000000000001'};
 const app=createApp({secret:'edward-browser-test-session-secret-1234',production:false,
 authService:{login:async()=>({codigo:0,usuario:{usuarioId:1,nombreUsuario:'operador',permisos:p}})},
 edwardService:{
 factura:async()=>[[{FacturaId:1,Cliente:'Cliente de prueba',NIT:'CF',Total:'20.16'}],[{DetalleFacturaId:1,Descripcion:'Producto de prueba',Cantidad:2,Devuelto:returns,Disponible:2-returns,PrecioUnitario:'10.00'}]],
 devoluciones:async()=>returns?[[returned],[{Descripcion:'Producto de prueba',Cantidad:1,PrecioUnitario:'10.00',Descuento:'1.00',IVA:'1.08',Total:'10.08',Reingresar:false}]]:[[],[]],
 garantias:async()=>tickets?[[ticket],[{EstadoAnterior:null,EstadoNuevo:'RECIBIDO',Diagnostico:'Falla',FechaHora:ticket.FechaApertura,Responsable:'operador'}]]:[[],[]],
 devolver:async(actor,body)=>{assert.equal(actor,1);assert.equal(body.Detalles[0].Cantidad,1);returns++;return {DevolucionId:1};},
 crear:async()=>{tickets++;return {TicketId:1};},
 actualizar:async()=>{updates++;throw Object.assign(new Error('stale'),{number:54603});}
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
 await cdp('Page.enable');await cdp('Runtime.enable');
 await navigate('/login');await evaluate("fetch('/login',{method:'POST',body:new URLSearchParams({NombreUsuario:'operador',Password:'test'}),redirect:'manual'})");
 await navigate('/devoluciones?factura=1');
 for(const width of [1366,768,390,320]){
 await cdp('Emulation.setDeviceMetricsOverride',{width,height:900,deviceScaleFactor:1,mobile:false});
 assert.equal(await evaluate('document.documentElement.scrollWidth<=document.documentElement.clientWidth'),true,'Responsive '+width);
 const shot=await cdp('Page.captureScreenshot');await writeFile(path.join(artifacts,'devoluciones-'+width+'.png'),Buffer.from(shot.data,'base64'));
 }
 await evaluate("document.querySelector('[data-quantity]').value='1';document.querySelector('[name=Motivo]').value='Defecto';document.querySelector('[data-posventa-form]').requestSubmit()");
 assert.equal(await evaluate("document.getElementById('posventa-confirm').open"),true);assert.equal(returns,0);
 await evaluate("document.getElementById('posventa-cancel').click()");assert.equal(returns,0);
 await evaluate("document.querySelector('[data-posventa-form]').requestSubmit();document.getElementById('posventa-accept').click()");
 await wait('location.pathname==="/notas-credito" && document.readyState==="complete"');
 assert.equal(returns,1);assert.match(await evaluate('document.body.innerText'),/No se ha registrado un reembolso/);
 await cdp('Emulation.setEmulatedMedia',{media:'print'});assert.equal(await evaluate("getComputedStyle(document.querySelector('.sidebar')).display"),'none');await cdp('Emulation.setEmulatedMedia',{media:''});
 await navigate('/garantias?factura=1');
 await evaluate("document.querySelector('[name=DetalleFacturaId]').checked=true;document.querySelector('[name=Motivo]').value='Falla';document.querySelector('[data-posventa-form]').requestSubmit()");
 await wait('location.search==="?id=1" && document.readyState==="complete"');assert.equal(tickets,1);
 await evaluate("document.querySelector('[name=Estado]').value='EN_REVISION';document.querySelector('[name=Diagnostico]').value='Borrador técnico';document.querySelector('[data-posventa-form]').requestSubmit()");
 await wait("document.getElementById('posventa-message').textContent.includes('registro cambió')");
 assert.equal(updates,1);assert.equal(await evaluate("document.querySelector('[name=Diagnostico]').value"),'Borrador técnico');
 assert.equal(await evaluate("document.activeElement.id"),'posventa-message');
 assert.deepEqual(errors,[]);
 console.log('PASS Edward Chromium: responsive 1366/768/390/320, confirmation/cancel, receipt, print, ticket creation, conflict retains diagnosis and focus.');
 console.log('Screenshots: '+artifacts);
 }finally{
 socket?.close();await new Promise(r=>{server.close(r);server.closeAllConnections();});
 if(browser.exitCode===null){const closed=once(browser,'exit');browser.kill();await closed;}
 }
}
main().catch(e=>{console.error(e.stack);process.exitCode=1;});
