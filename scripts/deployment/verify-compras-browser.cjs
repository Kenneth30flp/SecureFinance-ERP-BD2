'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert/strict'),{once}=require('events'),d=require('./compras-upgrade.cjs');
async function verify(){
 const config=JSON.parse(fs.readFileSync(path.join(d.PRIVATE,'browser.json'),'utf8'));
 const pages=await(await fetch('http://127.0.0.1:'+config.port+'/json/list')).json();
 const page=pages.find(x=>x.type==='page'&&x.url.startsWith('http://localhost:3000/'));assert(page,'Original app tab unavailable');
 const socket=new WebSocket(page.webSocketDebuggerUrl);await once(socket,'open');let id=0;const pending=new Map();
 socket.addEventListener('message',e=>{const m=JSON.parse(e.data),p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}});
 const cdp=(method,params={})=>new Promise((resolve,reject)=>{const n=++id,timer=setTimeout(()=>reject(Error('CDP timeout')),15000);pending.set(n,{resolve,reject,timer});socket.send(JSON.stringify({id:n,method,params}));});
 try{
  const location=await cdp('Runtime.evaluate',{expression:'location.pathname',returnByValue:true});
  if(location.result.value==='/login'){console.log('PENDING_USER_LOGIN: enter admin credentials personally; no password or form values inspected.');return false;}
  const result=await cdp('Runtime.evaluate',{expression:`(async()=>{
   const paths=['/cotizaciones','/compras','/promociones','/creditos','/multibodega','/auditoria/ddl'],checks=[];
   for(const path of ['/modulos',...paths,'/compras/nueva']){const r=await fetch(path),body=await r.text();const doc=new DOMParser().parseFromString(body,'text/html');checks.push({path,status:r.status,loginRedirect:r.url.endsWith('/login'),error:/No fue posible|Error interno|no disponible en este entorno/.test(body),account:doc.querySelector('.account-menu summary strong')?.textContent});}
   const mod=await(await fetch('/modulos')).text(),doc=new DOMParser().parseFromString(mod,'text/html');
   return {checks,links:paths.map(path=>({path,present:Array.from(doc.querySelectorAll('a[href]')).some(a=>a.getAttribute('href')===path)}))};
  })()`,returnByValue:true,awaitPromise:true});
  assert(!result.exceptionDetails,'Browser evaluation failed');const evidence=result.result.value;
  for(const x of evidence.checks){assert.equal(x.status,200,x.path);assert.equal(x.loginRedirect,false,x.path);assert.equal(x.error,false,x.path);assert.equal(x.account,'admin',x.path);}
  for(const x of evidence.links)assert(x.present,x.path);
  const log=await d.query("SELECT TOP(1) u.NombreUsuario,b.Resultado FROM dbo.Bitacora_Acceso b JOIN dbo.Usuario u ON u.UsuarioId=b.UsuarioId ORDER BY b.FechaHora DESC",'SecureFinanceERP');assert.equal(log[0]?.NombreUsuario,'admin');assert.equal(log[0]?.Resultado,'EXITOSO');
  fs.writeFileSync(path.join(d.privateDir,'browser-validation.json'),JSON.stringify({date:new Date().toISOString(),url:'http://localhost:3000',database:'SecureFinanceERP',passwordRead:false,...evidence},null,2));
  const s=d.state();s.browserPassed=true;s.browserVerifiedAt=new Date().toISOString();d.save(s);
  console.log('PASS personal admin login, six real module routes, module links and purchase form; no password captured.');return true;
 }finally{socket.close();}
}
module.exports={verify};if(require.main===module)verify().catch(e=>{console.error('BROWSER BLOCKED',e.message);process.exitCode=1;});
