'use strict';
// Narrow real-authentication check. Never substitutes authentication or changes credentials.
require('dotenv').config({quiet:true});
const database='SecureFinanceERP_Estabilizacion_20261021';
process.env.DB_NAME=database;
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {spawn}=require('node:child_process');
const {once}=require('node:events');
const net=require('node:net');
const {createApp}=require('../../server');
const {getPool,closePool}=require('../../src/config/database');
const routes=['/inventario','/productos','/facturacion','/notas-credito','/garantias'];
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const artifact='.data/login-access-result.json';
const result={checkedAt:new Date().toISOString(),database,authentication:'PENDING',credentialValuesDisclosed:false,credentialsModified:false,businessOperationsExecuted:false,checks:[]};
function credentials(){
 const file=process.env.ERP_QA_LOGIN_FILE||'.data/qa-login.local.json';
 if(fs.existsSync(file)){
  const c=JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
  if(typeof c.usuario!=='string'||!c.usuario||typeof c.password!=='string'||!c.password)throw Error('INVALID_LOCAL_CREDENTIAL_FILE');
  return c;
 }
 if(process.env.WEB_ADMIN_PASSWORD)return {usuario:process.env.WEB_ADMIN_USER||'admin',password:process.env.WEB_ADMIN_PASSWORD};
 return null;
}
async function main(){
 let server,browser,socket,profile,cdp;
 fs.mkdirSync('.data',{recursive:true});
 try{
  const pool=await getPool();
  if((await pool.request().query('SELECT DB_NAME() AS BaseActual')).recordset[0].BaseActual!==database)throw Error('WRONG_DATABASE');
  result.checks.push({check:'Actual SQL connection targets isolated database',status:'PASS'});
  const app=createApp({production:false}); // all default services, including real SQL authentication
  server=app.listen(0,'127.0.0.1');await once(server,'listening');
  const base='http://127.0.0.1:'+server.address().port;
  for(const route of routes){
   const r=await fetch(base+route,{redirect:'manual'});
   if(r.status!==302||r.headers.get('location')!=='/login')throw Error('ANONYMOUS_ACCESS_NOT_DENIED');
   result.checks.push({route,check:'Unauthenticated access denied',status:'PASS'});
  }
  const c=credentials();
  const manual=process.argv.includes('--manual')||!c;
  result.credentialSource=manual?'MANUAL_BROWSER_MEMORY_ONLY':'EXISTING_LOCAL_SOURCE';
  result.existingLocalCredentialsAvailable=Boolean(c);
  const executable=['C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(p=>fs.existsSync(p));
  if(!executable)throw Error('CHROMIUM_UNAVAILABLE');
  const reservation=net.createServer().listen(0,'127.0.0.1');await once(reservation,'listening');
  const port=reservation.address().port;await new Promise(r=>reservation.close(r));
  profile=fs.mkdtempSync(path.join(os.tmpdir(),'sf-real-login-'));
  browser=spawn(executable,[...(manual?['--new-window','--incognito']:['--headless=new']),'--disable-gpu','--no-first-run','--no-default-browser-check','--disable-sync','--disable-extensions','--disable-features=PasswordManagerOnboarding,PasswordLeakDetection','--remote-debugging-address=127.0.0.1','--remote-debugging-port='+port,'--user-data-dir='+profile,'about:blank'],{windowsHide:!manual,stdio:'ignore'});
  let pages;for(let i=0;i<100;i++){try{pages=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();if(pages.some(p=>p.type==='page'))break;}catch{}await delay(100);}
  socket=new WebSocket(pages.find(p=>p.type==='page').webSocketDebuggerUrl);await once(socket,'open');
  let seq=0;const pending=new Map(),responses=new Map();
  socket.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.method==='Network.responseReceived'&&m.params.type==='Document'){const r=m.params.response;responses.set(r.url,r.status);}const task=pending.get(m.id);if(task){pending.delete(m.id);clearTimeout(task.timer);m.error?task.reject(Error('CDP_COMMAND_FAILED')):task.resolve(m.result);}});
  cdp=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq;const timer=setTimeout(()=>{pending.delete(id);reject(Error('CDP_TIMEOUT'));},15000);pending.set(id,{resolve,reject,timer});socket.send(JSON.stringify({id,method,params}));});
  const evaluate=async expression=>{const r=await cdp('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error('BROWSER_EVALUATION_FAILED');return r.result.value;};
  const wait=async expression=>{for(let i=0;i<120;i++){if(await evaluate(expression))return;await delay(100);}throw Error('LOGIN_OR_PAGE_NOT_CONFIRMED');};
  const navigate=async route=>{await cdp('Page.navigate',{url:base+route});await wait('location.href==='+JSON.stringify(base+route)+'&&document.readyState==="complete"');};
  await cdp('Page.enable');await cdp('Runtime.enable');
  await navigate('/login');
  if(manual){
   console.log('MANUAL_LOGIN_READY: ventana privada de SecureFinance ERP abierta sobre la base aislada. Ingresa tu usuario y contrasena directamente en el navegador. No se capturan formularios ni trafico de login.');
   const deadline=Date.now()+15*60*1000;
   let authenticated=false;
   while(Date.now()<deadline){
    if(await evaluate('location.pathname==="/dashboard"&&document.readyState==="complete"')){authenticated=true;break;}
    if(await evaluate('location.pathname==="/cambiar-password"'))throw Error('EXISTING_ACCOUNT_REQUIRES_PASSWORD_CHANGE');
    await delay(1000);
   }
   if(!authenticated)throw Error('MANUAL_LOGIN_TIMEOUT');
  }else{
   await evaluate(`document.querySelector('[name=NombreUsuario]').value=${JSON.stringify(c.usuario)};document.querySelector('[name=Password]').value=${JSON.stringify(c.password)};document.querySelector('form').requestSubmit()`);
   await wait('location.pathname==="/dashboard"&&document.readyState==="complete"');
  }
  // Enable response tracking only after login; never collect credential POST traffic.
  await cdp('Network.enable');
  const cookies=await cdp('Network.getCookies',{urls:[base]});
  if(!cookies.cookies.some(c=>c.name==='securefinance.sid'&&c.httpOnly))throw Error('AUTHENTICATED_COOKIE_NOT_CONFIRMED');
  result.authentication='REAL_SQL_LOGIN_PASS';
  result.checks.push({check:'Real SQL login, dashboard and HttpOnly session cookie',status:'PASS'});
  const selectors={'/inventario':'.inventory-gate','/productos':'.catalog-toolbar','/facturacion':'#venta-form','/notas-credito':'.posventa-register','/garantias':'.posventa-register'};
  for(const route of routes){
   await navigate(route);
   if(responses.get(base+route)!==200||!await evaluate('Boolean(document.querySelector('+JSON.stringify(selectors[route])+'))'))throw Error('AUTHENTICATED_MODULE_UNAVAILABLE');
   result.checks.push({route,check:'Authenticated real SQL module rendered',status:'PASS',httpStatus:200});
  }
  result.status='PASS';
 }catch(e){result.status='FAIL';result.errorCode=/^[A-Z_]+$/.test(e.message)?e.message:'INTEGRATION_CHECK_FAILED';process.exitCode=1;}
 finally{
  if(socket?.readyState===WebSocket.OPEN&&cdp)await cdp('Browser.close').catch(()=>{});
  socket?.close();
  if(browser&&browser.exitCode===null){
   await Promise.race([once(browser,'exit'),delay(5000)]);
   if(browser.exitCode===null){
    const killer=spawn('taskkill',['/PID',String(browser.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});
    await once(killer,'exit');
   }
  }
  if(server)await new Promise(r=>{server.close(r);server.closeAllConnections();});await closePool().catch(()=>{});
  if(profile){
   const resolved=path.resolve(profile),root=path.resolve(os.tmpdir()),relative=path.relative(root,resolved);
   if(!relative.startsWith('..')&&!path.isAbsolute(relative)&&/^sf-real-login-/.test(path.basename(resolved))){
    try{await fs.promises.rm(resolved,{recursive:true,force:true,maxRetries:12,retryDelay:300});result.temporaryProfileRemoved=!fs.existsSync(resolved);}catch{result.temporaryProfileRemoved=false;}
   }else result.temporaryProfileRemoved=false;
   if(!result.temporaryProfileRemoved){result.status='FAIL';result.errorCode='TEMPORARY_PROFILE_CLEANUP_FAILED';process.exitCode=1;}
  }
  fs.mkdirSync('.data',{recursive:true});fs.writeFileSync(artifact,JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify(result));
 }
}
main();
