'use strict';
const fs=require('fs'),path=require('path'),os=require('os'),net=require('net'),assert=require('assert/strict'),{spawn}=require('child_process'),{once}=require('events'),{randomBytes,randomUUID}=require('crypto');
const lab=require('../../database/tests/promocionesLab');const dir='docs/parte3/integracion-dylan/evidencias/chrome';fs.mkdirSync(dir,{recursive:true});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{let browser,socket;const checks=[],errors=[];const base='http://127.0.0.1:3107';try{
 const state=lab.readState();assert.equal((await lab.labJson('SELECT dbo.P3_INT_Destino() A'))[0].A,state.lab);
 const chrome=['C:/Program Files/Google/Chrome/Application/chrome.exe','C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'].find(fs.existsSync);assert.ok(chrome,'Chromium missing');
 const reserve=net.createServer().listen(0,'127.0.0.1');await once(reserve,'listening');const port=reserve.address().port;await new Promise(r=>reserve.close(r));
 browser=spawn(chrome,['--headless=new','--disable-gpu','--no-first-run','--remote-debugging-port='+port,'--user-data-dir='+fs.mkdtempSync(path.join(os.tmpdir(),'sf-integration-chrome-')),'about:blank'],{windowsHide:true,stdio:'ignore'});
 let page;for(let i=0;i<100;i++){try{page=(await(await fetch('http://127.0.0.1:'+port+'/json/list')).json()).find(p=>p.type==='page');if(page)break;}catch{}await sleep(100);}assert.ok(page);
 socket=new WebSocket(page.webSocketDebuggerUrl);await once(socket,'open');let id=0;const pending=new Map();socket.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.exception?.description||m.params.exceptionDetails.text);const p=pending.get(m.id);if(p){pending.delete(m.id);clearTimeout(p.timer);m.error?p.no(Error(m.error.message)):p.ok(m.result);}});
 const cdp=(method,params={})=>new Promise((ok,no)=>{const n=++id;const timer=setTimeout(()=>no(Error('CDP '+method)),20000);pending.set(n,{ok,no,timer});socket.send(JSON.stringify({id:n,method,params}));});
 const evaluate=async expression=>{const r=await cdp('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(r.exceptionDetails.text);return r.result.value;};
 const wait=async expr=>{for(let i=0;i<100;i++){if(await evaluate(expr))return;await sleep(100);}throw Error('DOM wait '+expr);};
 const navigate=async route=>{await cdp('Page.navigate',{url:base+route});await wait('location.pathname==='+JSON.stringify(route)+'&&document.readyState==="complete"');};
 await cdp('Page.enable');await cdp('Runtime.enable');
 await navigate('/login');
 const before=await evaluate('fetch("/creditos",{redirect:"manual"}).then(r=>r.type)');assert.equal(before,'opaqueredirect');checks.push('anonymous redirects to login');
 const creds=JSON.parse(fs.readFileSync('.data/integration-ui.json'));
 const login=async(c)=>{await navigate('/login');await evaluate(`document.querySelector('[name=NombreUsuario]').value=${JSON.stringify(c.username)};document.querySelector('[name=Password]').value=${JSON.stringify(c.password)};document.querySelector('form').requestSubmit();`);await wait('location.pathname==="/dashboard"&&document.readyState==="complete"');};
 await login(creds);checks.push('real SQL login and session: administrator');
 for(const width of [1366,768,390,320]){
 await cdp('Emulation.setDeviceMetricsOverride',{width,height:1000,deviceScaleFactor:1,mobile:width<500});
 for(const route of ['/modulos','/cotizaciones','/promociones','/creditos','/multibodega','/auditoria/ddl']){
 const status=await evaluate('fetch('+JSON.stringify(route)+').then(r=>r.status)');assert.equal(status,200,route);
 await navigate(route);const overflow=await evaluate('document.documentElement.scrollWidth>innerWidth+1');assert.equal(overflow,false,route+' overflow '+width);
 const html=await evaluate('document.body.innerText');assert(!/No fue posible|Error interno|no disponible en este entorno/i.test(html),route+' SQL availability');
 if(route==='/modulos')assert.equal(await evaluate('document.querySelectorAll(".module-area").length'),6);
 const image=await cdp('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(dir+'/'+route.replaceAll('/','-').slice(1)+'-'+width+'.png',Buffer.from(image.data,'base64'));checks.push(route+' HTTP200, real SQL, no overflow '+width);
 }
 }
 await navigate('/creditos');
 const profile=(await lab.labJson("SELECT TOP(1) c.ClienteId,CONVERT(VARCHAR(16),CONVERT(BINARY(8),c.Version),2) Version FROM dbo.Credito_Cliente c JOIN dbo.Cliente cl ON cl.ClienteId=c.ClienteId WHERE cl.Nombre=N'Matriz sintetica integrada' ORDER BY c.ClienteId DESC"))[0];
 assert.ok(profile,'run matrix-qa first');
 const mutate=async(route,body)=>evaluate('fetch('+JSON.stringify(route)+',{method:"POST",headers:{"Content-Type":"application/json","X-CSRF-Token":document.querySelector("meta[name=csrf-token]").content},body:'+JSON.stringify(JSON.stringify(body))+'}).then(async r=>({status:r.status,data:await r.json()}))');
 const updated=await mutate('/creditos/perfil',{ClienteId:String(profile.ClienteId),Activo:'1',Limite:'10000.00',PlazoDias:'30',VersionEsperada:profile.Version,Motivo:'QA Chrome sint?tico',OperacionId:randomUUID()});assert.equal(updated.status,200,JSON.stringify(updated));checks.push('real HTTP credit profile mutation with CSRF and rowversion');
 const account=(await lab.labJson('SELECT TOP(1) FacturaId FROM dbo.P3_CRE_Cuenta WHERE ClienteId='+profile.ClienteId+' AND Saldo>50 ORDER BY FacturaId DESC'))[0];
 const paid=await mutate('/creditos/abonos',{ClienteId:String(profile.ClienteId),FacturaId:String(account.FacturaId),Monto:'50.00',Referencia:'QA Chrome sint?tico',OperacionId:randomUUID()});assert.equal(paid.status,200,JSON.stringify(paid));
 assert.equal(await evaluate('fetch('+JSON.stringify(paid.data.url)+').then(r=>r.status)'),200);checks.push('real HTTP payment Q50, SQL receipt rendered');
 const limitedPassword='Qa#'+randomBytes(20).toString('base64url'),username='QA_AUD_'+Date.now();
 await lab.labQuery(`DECLARE @U INT; EXEC dbo.sp_RegistrarUsuario N'${username}',N'${username}@example.invalid',N'${limitedPassword}',N'Auditor sintetico',@U OUTPUT; INSERT dbo.Usuario_Rol(UsuarioId,RolId) SELECT @U,RolId FROM dbo.Rol WHERE Nombre=N'Auditor';UPDATE dbo.Usuario SET DebeCambiarPassword=0 WHERE UsuarioId=@U;`);
 await evaluate('fetch("/logout")');await login({username,password:limitedPassword});
 for(const [route,status] of [['/auditoria/ddl',200],['/creditos',200],['/multibodega',200],['/promociones',403]])assert.equal(await evaluate('fetch('+JSON.stringify(route)+').then(r=>r.status)'),status,route+' Auditor');
 await navigate('/creditos');assert.equal(await evaluate('fetch("/creditos/abonos",{method:"POST",headers:{"Content-Type":"application/json","X-CSRF-Token":document.querySelector("meta[name=csrf-token]").content},body:"{}"}).then(r=>r.status)'),403);
 await navigate('/multibodega');assert.equal(await evaluate('fetch("/multibodega/transferencias",{method:"POST",headers:{"Content-Type":"application/json","X-CSRF-Token":document.querySelector("meta[name=csrf-token]").content},body:"{}"}).then(r=>r.status)'),403);
 checks.push('real auditor login; DDL/credit/warehouse read allowed; valid-CSRF mutations and promotions denied');assert.equal(errors.length,0,errors.join('\n'));
 fs.writeFileSync(dir+'/results.json',JSON.stringify({database:state.lab,url:base,authentication:'REAL_SQL_LOGIN',browser:path.basename(chrome),checks,errors},null,2));console.log('CHROME PASS '+checks.length+' checks');
 }finally{socket?.close();browser?.kill();}
})().catch(e=>{console.error('CHROME FAIL',e.message);process.exitCode=1;});
