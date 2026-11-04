'use strict';
// Real Chromium + real SQL, dedicated laboratory only. No personal browser profile.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict'),net=require('node:net');
const {spawn}=require('node:child_process'),{once}=require('node:events');
const lab=require('../../../scripts/parte4/ldf/lab.cjs');
const {root,queryJson,lit}=require('../../../scripts/parte4/ldf/sqlcmd.cjs');
const {closePool}=require('../../../src/config/database'),{close}=require('../../../src/modules/dba/ldf/pools');
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function main(){
 const s=lab.useLab();assert.match(s.database,lab.pattern);
 const artifacts=path.join(root,'docs/parte4/ldf/evidencias');fs.mkdirSync(artifacts,{recursive:true});
 const profile=fs.mkdtempSync(path.join(os.tmpdir(),'sf-ldf-browser-'));
 let server,browser,socket;
 const errors=[],responses=[],requests=[];let seq=0;const pending=new Map();
 try{
  server=require('../../../server').createApp({secret:s.sessionSecret,production:false}).listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
  const chrome=['C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(fs.existsSync);assert(chrome,'Chrome o Edge requerido.');
  const reserve=net.createServer().listen(0,'127.0.0.1');await once(reserve,'listening');const port=reserve.address().port;await new Promise(r=>reserve.close(r));
  browser=spawn(chrome,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+port,'--user-data-dir='+profile,'about:blank'],{windowsHide:true,stdio:'ignore'});
  let page;for(let i=0;i<100;i++){try{page=(await(await fetch('http://127.0.0.1:'+port+'/json/list')).json()).find(p=>p.type==='page');if(page)break;}catch{}await pause(100);}assert(page,'Chromium no inició.');
  socket=new WebSocket(page.webSocketDebuggerUrl);await once(socket,'open');
  socket.addEventListener('message',event=>{const m=JSON.parse(event.data);if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.text);
   if(m.method==='Network.responseReceived')responses.push({url:m.params.response.url,status:m.params.response.status});
   if(m.method==='Network.requestWillBeSent')requests.push({url:m.params.request.url,method:m.params.request.method});
   const p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}});
  const cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq,timer=setTimeout(()=>{pending.delete(id);reject(Error('CDP timeout '+method));},30000);pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params}));});
  const evaluate=async expression=>{const r=await cdp('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.exception?.description||r.exceptionDetails.text);return r.result.value;};
  const wait=async expression=>{for(let i=0;i<200;i++){if(await evaluate(expression))return;await pause(50);}throw Error('Timeout '+expression);};
  await cdp('Page.enable');await cdp('Runtime.enable');await cdp('Network.enable');
  const go=async url=>{await evaluate('window.__ldfLeaving=true');await cdp('Page.navigate',{url:base+url});await wait('!window.__ldfLeaving && document.readyState==="complete" && location.pathname==='+JSON.stringify(url.split('?')[0].split('#')[0]));};
  const size=width=>cdp('Emulation.setDeviceMetricsOverride',{width,height:1000,deviceScaleFactor:1,mobile:false});
  const capture=async file=>{const r=await cdp('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(path.join(artifacts,file+'.png'),Buffer.from(r.data,'base64'));};
  await go('/login');
  assert.equal(await evaluate(`fetch('/login',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams(${JSON.stringify({NombreUsuario:'admin',Password:s.webPassword})})}).then(r=>r.status)`),200);
  for(const width of [1440,1024,768,390]){
   await size(width);await go('/dba/ldf');assert.equal(await evaluate('document.documentElement.scrollWidth<=innerWidth'),true,'Desbordamiento '+width);
   assert.equal(await evaluate('!!document.querySelector(".ldf-capacity")'),true);await capture('panel-'+width);
   await evaluate('document.querySelector(".ldf-vlf").scrollIntoView()');await capture('vlf-'+width);
  }
  await size(1440);await go('/dba/ldf');
  const oldSample=await evaluate('document.querySelector(".ldf-sampled").textContent');
  await evaluate('window.__ldfLeaving=true; document.querySelector("#ldf-refresh").click()');await wait('!window.__ldfLeaving && document.readyState==="complete"');
  assert.notEqual(await evaluate('document.querySelector(".ldf-sampled").textContent'),oldSample);
  const op=await evaluate('document.querySelector("#ldf-backup-form").elements.OperacionId.value');
  const countBefore=requests.filter(x=>x.url.endsWith('/dba/ldf/backup')&&x.method==='POST').length;
  await evaluate('window.__ldfLeaving=true; const f=document.querySelector("#ldf-backup-form");f.requestSubmit();f.requestSubmit();');
  await wait('!window.__ldfLeaving && document.readyState==="complete" && location.hash==="#log-history"');
  assert.equal(requests.filter(x=>x.url.endsWith('/dba/ldf/backup')&&x.method==='POST').length,countBefore+1);
  assert.equal(await evaluate(`[...document.querySelectorAll('[data-ldf-operation]')].find(r=>r.dataset.ldfOperation===${JSON.stringify(op)})?.dataset.ldfState`),'CONFIRMADO');
  await capture('respaldo-confirmado');
  await go('/dba/ldf');
  const uncertain=await evaluate('document.querySelector("#ldf-backup-form").elements.OperacionId.value');
  // Engine finishes the real backup; simulate losing only the response on the client.
  await evaluate('window.__realFetch=window.fetch;window.fetch=async(...a)=>{const r=await window.__realFetch(...a);if(String(a[0]).endsWith("/dba/ldf/backup"))throw Error("QA lost response");return r;};document.querySelector("#ldf-backup-form").requestSubmit();');
  await wait('document.querySelector("#ldf-message").textContent.includes("Se interrumpió")');await capture('respuesta-incierta');
  await go('/dba/ldf');
  assert.equal(await evaluate('Object.keys(sessionStorage).filter(k=>k.startsWith("ldf-pending:")).length'),0);
  const count=await queryJson(`SELECT COUNT(*) N FROM msdb.dbo.backupset WHERE name=${lit('P4_LDF:'+uncertain)}`,s);assert.equal(count[0].N,1);
  // Storage failure blocks a new request, rather than losing its idempotency reference.
  const before=requests.filter(x=>x.url.endsWith('/dba/ldf/backup')&&x.method==='POST').length;
  await evaluate('Storage.prototype.setItem=function(){throw Error("QA denied storage")};document.querySelector("#ldf-backup-form").requestSubmit();');
  await wait('document.querySelector("#ldf-message").textContent.includes("No se envió")');
  assert.equal(requests.filter(x=>x.url.endsWith('/dba/ldf/backup')&&x.method==='POST').length,before);
  assert.deepEqual(errors,[]);
  assert(!responses.some(r=>r.status>=400&&r.url.includes('/dba/ldf')));
  const result={atUTC:new Date().toISOString(),database:s.database,widths:[1440,1024,768,390],realSQL:true,manualBackup:op,
   doubleClick:'one POST',lostResponse:'one backup in msdb; reconciled on reload',storageFailure:'no POST',javascriptErrors:errors,result:'PASS'};
  fs.writeFileSync(path.join(artifacts,'browser-results.json'),JSON.stringify(result,null,2));console.log('PASS Chromium + SQL real, 4 anchos, respaldo, doble clic, incertidumbre y almacenamiento. Evidencias:',artifacts);
 } finally{
  socket?.close();for(const p of pending.values())clearTimeout(p.timer);
  if(browser){const exited=once(browser,'exit').catch(()=>{});browser.kill();await exited;}
  if(server)await new Promise(r=>{server.close(r);server.closeAllConnections();});await closePool();await close();
  try{fs.rmSync(profile,{recursive:true,force:true,maxRetries:2});}catch{/* Windows puede retener archivos del perfil temporal. */}
 }
}
main().catch(e=>{console.error(e);process.exitCode=1;});
