'use strict';
require('dotenv').config({quiet:true});
const previewActor=Number(process.env.KENNETH_PREVIEW_USER_ID);if(!Number.isSafeInteger(previewActor)||previewActor<1)throw new Error('Configura KENNETH_PREVIEW_USER_ID con el usuario autorizado del laboratorio.');

const {once}=require('node:events');
const db=require('../../src/config/database');
(async()=>{
 let server;
 try{
 const p=await db.getPool();
 const permissions=(await p.request().input('UsuarioId',db.sql.Int,previewActor).execute('dbo.sp_ObtenerPermisosUsuario')).recordset.map(x=>x.Codigo);
 // Solo lectura con sesion aislada: no prueba la contrasena real de admin.
 server=require('../../server').createApp({production:false,authService:{login:async()=>({codigo:0,usuario:{usuarioId:previewActor,nombreUsuario:'admin',permisos:permissions,debeCambiarPassword:false}})}}).listen(0,'127.0.0.1');
 await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
 await require('./kennethCapture').withBrowser('docs/capturas/kenneth-refinamiento/'+(process.argv.includes('--before')?'antes':'principal'),async b=>{
 await b.viewport(1366,900);await b.navigate(base+'/login');
 await b.evaluate("fetch('/login',{method:'POST',body:new URLSearchParams({NombreUsuario:'readonly',Password:'isolated-session'})})");
 for(const route of ['clientes','proveedores','productos','inventario']){await b.navigate(base+'/'+route);await b.capture(route+'-1366');}
 if(process.argv.includes('--final')){
  const routes={clientes:'/clientes',proveedores:'/proveedores',productos:'/productos',inventario:'/inventario?id=1','clientes-nuevo':'/clientes?nuevo=1','clientes-editar':'/clientes?id=1&editar=1','proveedores-nuevo':'/proveedores?nuevo=1','productos-tabla':'/productos?vista=tabla','productos-editar':'/productos?id=1','productos-nuevo':'/productos?nuevo=1'};
  for(const width of [1366,390]){await b.viewport(width,width===390?844:900);for(const[name,route]of Object.entries(routes)){await b.navigate(base+route);if(route.includes('nuevo=')&&name!=='productos-nuevo')await b.wait('!!document.querySelector(".master-drawer[open]")');if(name==='inventario'){await b.evaluate('document.querySelector(".inventory-action").open=true');}await b.capture(name+'-'+width);if(await b.evaluate('document.documentElement.scrollWidth>document.documentElement.clientWidth'))throw new Error('Overflow '+name+' '+width);}}
  await b.viewport(1366,900);
  for(const route of Object.values(routes)){
   await b.navigate(base+route);
   const failures=await b.evaluate(`(()=>{
    const rgb=v=>(v.match(/[\\d.]+/g)||[]).map(Number),blend=(f,b)=>f.slice(0,3).map((v,i)=>v*(f[3]??1)+b[i]*(1-(f[3]??1)));
    const lum=c=>c.slice(0,3).map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((s,v,i)=>s+v*[.2126,.7152,.0722][i],0);
    const scope=document.querySelector('.master-drawer[open]')||document.querySelector('#workspace'),walker=document.createTreeWalker(scope,NodeFilter.SHOW_TEXT),bad=[];let n;
    while((n=walker.nextNode())){const e=n.parentElement,text=n.textContent.trim();if(!text||e.closest('script,style,option,[aria-hidden=true],.visually-hidden')||!e.getClientRects().length)continue;const style=getComputedStyle(e);if(style.visibility==='hidden')continue;let bg=[14,17,23],parents=[];for(let p=e;p;p=p.parentElement)parents.unshift(p);for(const p of parents)bg=blend(rgb(getComputedStyle(p).backgroundColor),bg);const fg=lum(blend(rgb(style.color),bg)),back=lum(bg),ratio=(Math.max(fg,back)+.05)/(Math.min(fg,back)+.05),large=parseFloat(style.fontSize)>=24||(parseFloat(style.fontSize)>=18.66&&parseInt(style.fontWeight)>=700);if(ratio<(large?3:4.5)-.02)bad.push({text:text.slice(0,45),ratio});}return bad;
   })()`);
   if(failures.length)throw new Error('Contraste '+route+': '+JSON.stringify(failures));
  }
  await b.navigate(base+'/clientes?nuevo=1');await b.wait('!!document.querySelector(".master-drawer[open]")');await b.evaluate('document.documentElement.style.zoom="2"');if(await b.evaluate('document.documentElement.scrollWidth>document.documentElement.clientWidth'))throw new Error('Overflow zoom 200%');await b.capture('clientes-zoom200-css');
  console.log('PASS: principal, cuatro modulos y formularios, 1366/390, contraste textual y zoom CSS 200%, solo lectura; autenticacion de preview aislada.');
 }
 if(process.argv.includes('--diagnose')){await b.viewport(768,900);await b.navigate(base+'/productos?vista=tabla');await b.capture('productos-tabla-768');console.log(await b.evaluate('JSON.stringify({inner:innerWidth,doc:document.documentElement.scrollWidth,body:document.body.scrollWidth,items:[...document.querySelectorAll("#workspace,.catalog-layout,.master-table-scroll,.catalog-layout>section")].map(e=>({cls:e.className,w:e.getBoundingClientRect().width,sw:e.scrollWidth,overflow:getComputedStyle(e).overflowX}))})')); console.log(await b.evaluate('JSON.stringify([...document.querySelectorAll("body *")].filter(e=>e.getBoundingClientRect().right>innerWidth+1).map(e=>({tag:e.tagName,cls:e.className,width:e.getBoundingClientRect().width,right:e.getBoundingClientRect().right})).slice(0,30))'));}
 });
 }catch(e){console.error(e);process.exitCode=1;}
 finally{if(server)await new Promise(r=>server.close(r));await db.closePool();}
})();
