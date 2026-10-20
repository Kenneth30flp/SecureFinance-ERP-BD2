'use strict';
// Real Chromium against an already isolated application supplied by the SQL executor.
const assert=require('node:assert/strict');
const {spawn}=require('node:child_process');
const {once}=require('node:events');
const fs=require('node:fs/promises');
const {existsSync}=require('node:fs');
const path=require('node:path');
const net=require('node:net');
const sharp=require('sharp');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function runKennethBrowser({base,username,password,product,supplier,customer,activeCustomer,directory}){
 const browserPath=['C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(existsSync);
 assert(browserPath,'Chromium no disponible');
 const profile=path.join(directory,'browser-profile');await fs.mkdir(profile);
 const artifacts=path.resolve(__dirname,'../../docs/capturas/kenneth');await fs.mkdir(artifacts,{recursive:true});
 const reservation=net.createServer().listen(0,'127.0.0.1');await once(reservation,'listening');const port=reservation.address().port;await new Promise(r=>reservation.close(r));
 const browser=spawn(browserPath,['--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check','--remote-debugging-port='+port,'--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});
 let socket;
 try{
  let page;for(let i=0;i<100;i++){try{page=(await(await fetch('http://127.0.0.1:'+port+'/json/list')).json()).find(p=>p.type==='page');if(page)break;}catch{}await delay(100);}assert(page,'Chromium no inició');
  socket=new WebSocket(page.webSocketDebuggerUrl);await once(socket,'open');let sequence=0;const pending=new Map(),errors=[];
  socket.addEventListener('message',event=>{const m=JSON.parse(event.data);if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.text);const p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(new Error(m.error.message)):p.resolve(m.result);}});
  const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++sequence;const timer=setTimeout(()=>{pending.delete(id);reject(new Error('CDP timeout: '+method));},10000);pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params}));});
  const evaluate=async expression=>{const r=await cdp('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw new Error(r.exceptionDetails.exception?.description||'Error en navegador');return r.result.value;};
  const wait=async expression=>{for(let i=0;i<100;i++){if(await evaluate(expression))return;await delay(100);}throw new Error('Estado esperado no encontrado: '+expression);};
  const navigate=async(route,selector)=>{await cdp('Page.navigate',{url:base+route});await wait('location.href==='+JSON.stringify(base+route)+' && document.readyState==="complete" && !!document.querySelector('+JSON.stringify(selector)+')');};
  const screenshot=async name=>{await delay(200);const {cssContentSize}=await cdp('Page.getLayoutMetrics');await fs.writeFile(path.join(artifacts,name+'.png'),Buffer.from((await cdp('Page.captureScreenshot',{captureBeyondViewport:true,clip:{x:0,y:0,width:cssContentSize.width,height:cssContentSize.height,scale:1}})).data,'base64'));};
  const viewport=async(width,height=900)=>cdp('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
    const contrast = async (label) => {
      await delay(250);
      const failures = await evaluate(`(() => {
        const rgb = value => (value.match(/[\\d.]+/g) || []).map(Number);
        const blend = (front, back) => { const alpha = front[3] ?? 1; return front.slice(0,3).map((n,i) => n*alpha + back[i]*(1-alpha)); };
        const luminance = color => color.slice(0,3).map(n => { n/=255; return n<=.04045 ? n/12.92 : ((n+.055)/1.055)**2.4; }).reduce((sum,n,i) => sum+n*[.2126,.7152,.0722][i],0);
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); const failed=[]; let node;
        while ((node=walker.nextNode())) {
          const el=node.parentElement, text=node.textContent.trim();
          if (!text || el.closest('script,style,option,[aria-hidden=true]') || !el.getClientRects().length) continue;
          const style=getComputedStyle(el); if (style.visibility==='hidden') continue;
          const ancestors=[]; for(let p=el;p;p=p.parentElement) ancestors.unshift(p);
          let background=[255,255,255]; for(const p of ancestors) background=blend(rgb(getComputedStyle(p).backgroundColor),background);
          const fg=luminance(blend(rgb(style.color),background)), bg=luminance(background);
          const ratio=(Math.max(fg,bg)+.05)/(Math.min(fg,bg)+.05);
          const large=parseFloat(style.fontSize)>=24 || (parseFloat(style.fontSize)>=18.66 && parseInt(style.fontWeight)>=700);
          if(ratio<(large?3:4.5)-.02) failed.push({text:text.slice(0,65),ratio:ratio.toFixed(2),color:style.color});
        }
        return failed.slice(0,20);
      })()`);
      assert.deepEqual(failures, [], 'Text contrast ' + label);
    };
  await cdp('Page.enable');await cdp('Runtime.enable');await viewport(1366);
  await navigate('/login','form');
  await evaluate(`fetch('/login',{method:'POST',body:new URLSearchParams({NombreUsuario:${JSON.stringify(username)},Password:${JSON.stringify(password)}})})`);
  const routes={inventario:'/inventario?id='+product,productos:'/productos',proveedores:'/proveedores?id='+supplier,clientes:'/clientes?id='+customer};
  const checked=[];
  for(const width of[1920,1366,1024,768,390,320]){
   await viewport(width,width<500?844:900);
   for(const[module,route]of Object.entries(routes)){
    await navigate(route,'#workspace');
    assert.equal(await evaluate('document.documentElement.scrollWidth<=document.documentElement.clientWidth'),true,module+' overflow '+width);
    assert.equal(await evaluate("[...document.querySelectorAll('input:not([type=hidden]),select')].every(e=>e.id&&document.querySelector('label[for=\"'+e.id+'\"]'))"),true,module+' labels');
    assert.equal(await evaluate('(()=>{const ids=[...document.querySelectorAll("[id]")].map(e=>e.id);return ids.length===new Set(ids).size;})()'),true,module+' identificadores únicos');
    if(width===1366)await contrast(module);
    if(width===1366||width===390)await screenshot(module+'-'+width);
    checked.push(module+' '+width);
   }
   if(width===390||width===320){await navigate('/productos?id='+product,'#product-photo');assert.equal(await evaluate('document.documentElement.scrollWidth<=document.documentElement.clientWidth'),true,'product editor '+width);await evaluate('document.querySelector(".editor-jump").click()');assert.equal(await evaluate('document.activeElement.id==="product-editor-title"'),true);if(width===390)await screenshot('producto-editor-390');}
  }
  await viewport(1366);
  await navigate('/productos?nuevo=1','[data-master-form]');
  const sku='BROWSER-'+Date.now();
  await evaluate(`(()=>{const v={Codigo:${JSON.stringify(sku)},Descripcion:'Producto creado desde navegador de pruebas',Precio:'12.50',PrecioCosto:'7.00',ProveedorId:${JSON.stringify(String(supplier))},StockMinimo:'1',PuntoReorden:'2',GarantiaMeses:'6'};for(const[name,value]of Object.entries(v))document.querySelector('[name="'+name+'"]').value=value;})()`);
  const png=path.join(directory,'browser-upload.png');await sharp({create:{width:100,height:70,channels:3,background:'#37485c'}}).png().toFile(png);
  const doc=await cdp('DOM.getDocument');const input=await cdp('DOM.querySelector',{nodeId:doc.root.nodeId,selector:'#product-photo'});await cdp('DOM.setFileInputFiles',{nodeId:input.nodeId,files:[png]});
  await wait('!!document.querySelector("[name=UploadToken]").value');
  await evaluate('document.querySelector("[data-master-form]").requestSubmit()');
  await wait('location.pathname==="/productos" && location.search.startsWith("?id=") && document.readyState==="complete" && document.querySelector("[name=Codigo]")?.value==='+JSON.stringify(sku));
  assert.equal(await evaluate('document.querySelector("#photo-preview").naturalWidth>0'),true);
  await contrast('product-editor');await screenshot('producto-editor-1366');
  await evaluate('document.getElementById("supplier-search").value="Abastecimiento";document.getElementById("supplier-find").click()');await wait('document.getElementById("module-message").textContent.includes("Consulta de proveedores")');
  await navigate('/inventario?id='+product,'#Cantidad');await evaluate('document.querySelector(".inventory-action").open=true;document.getElementById("Cantidad").value="999";document.getElementById("DocumentoRespaldo").value="WEB-BROWSER-FAIL";document.getElementById("Motivo").value="Rechazo esperado";document.getElementById("TipoMovimiento").value="AJUSTE_EGRESO";document.querySelector("[data-master-form]").requestSubmit()');
  await wait('document.getElementById("module-message").textContent.includes("Stock insuficiente")');await screenshot('inventario-error-1366');
  await navigate('/productos?buscar=Equipo','article.catalog-item');assert.equal(await evaluate('document.querySelector(".catalog-item h2").textContent.includes("Equipo")'),true);
  // The SQL case already inactivated customer. Verify visible state and that no new action appears.
  await navigate('/clientes?id='+customer,'.customer-identity');assert.equal(await evaluate('document.querySelector(".customer-identity").textContent.includes("Inactivo")'),true);assert.equal(await evaluate('!!document.querySelector("[data-confirm]")'),false);
  if(activeCustomer){
   await navigate('/clientes?id='+activeCustomer,'form[data-confirm]');
   const openConfirm='(()=>{const f=document.querySelector("form[data-confirm]");f.closest("details").open=true;f.querySelector("[name=Motivo]").value="Solicitud desde navegador de pruebas";f.requestSubmit(f.querySelector("button[type=submit]"));})()';
   await evaluate(openConfirm);await wait('document.getElementById("master-confirm").open');
   await screenshot('cliente-confirmacion-1366');
   await cdp('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await cdp('Input.dispatchKeyEvent',{type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await wait('!document.getElementById("master-confirm").open');
   assert.equal(await evaluate('document.activeElement===document.querySelector("form[data-confirm] button[type=submit]")'),true);
   await evaluate(openConfirm);await wait('document.getElementById("master-confirm").open');await evaluate('document.querySelector("#master-confirm [value=confirm]").click()');
   await wait('document.readyState==="complete" && !document.querySelector("form[data-confirm]") && document.querySelector(".customer-identity")?.textContent.includes("Inactivo")');
  }
  // Zoom equivalence at 1366/2 and reduced motion.
  await viewport(683,384);await navigate('/inventario?id='+product,'#workspace');assert.equal(await evaluate('document.documentElement.scrollWidth<=innerWidth'),true);
  await cdp('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'reduce'}]});assert.equal(await evaluate('matchMedia("(prefers-reduced-motion:reduce)").matches'),true);
  await evaluate('document.querySelector(".skip-link").focus()');assert.equal(await evaluate('document.activeElement.classList.contains("skip-link")'),true);
  assert.deepEqual(errors,[]);
  return{viewports:checked,realPhotoUpload:true,realProductCreated:true,stockError:true,inactiveCustomer:true,reducedMotion:true,zoomEffectiveViewport:'683x384',artifacts:'docs/capturas/kenneth'};
 }finally{
  socket?.close();const closed=browser.exitCode===null?once(browser,'exit'):Promise.resolve();browser.kill();await closed;
  // Only this newly created browser profile; no user Chrome processes are touched.
 }
}
module.exports={runKennethBrowser};
