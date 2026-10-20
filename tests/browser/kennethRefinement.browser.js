'use strict';
const assert=require('node:assert/strict');
const {withBrowser}=require('./kennethCapture');
async function run({base,username,password,client,supplier,product,tag}){
 await withBrowser('docs/capturas/kenneth-refinamiento/aislado',async b=>{
  await b.viewport(1366,900);await b.navigate(base+'/login');
  await b.evaluate(`fetch('/login',{method:'POST',body:new URLSearchParams({NombreUsuario:${JSON.stringify(username)},Password:${JSON.stringify(password)}})})`);
  await b.navigate(base+'/clientes?buscar=Cliente');
  await b.evaluate('window.refinementMarker=123;document.querySelector(".master-heading a").click()');
  await b.wait('!!document.querySelector(".master-drawer[open]")');
  assert.equal(await b.evaluate('(()=>{const i=document.querySelector(".master-drawer [name=Telefono]");i.value="abc";const invalid=i.validity.patternMismatch;i.value="+502 5555-0101";return invalid&&!i.validity.patternMismatch;})()'),true,'Validacion telefonica HTML');
  await b.capture('clientes-nuevo-1366');
  const fill=async values=>b.evaluate(`(()=>{const f=document.querySelector('.master-drawer form');for(const [key,value] of Object.entries(${JSON.stringify(values)}))f.elements[key].value=value;})()`);
  await fill({NIT:tag+'B',Nombre:'Cliente navegador aislado',Correo:'browser@example.invalid',Telefono:'+502 5555-0404'});
  await b.evaluate('document.querySelector(".master-drawer form").requestSubmit(document.querySelector(".master-drawer button[type=submit]"))');
  await b.wait('!document.querySelector(".master-drawer") && !!document.querySelector("#module-message.success")');
  assert.equal(await b.evaluate('window.refinementMarker'),123,'Sin recarga de documento');
  assert.equal(await b.evaluate('new URL(location.href).searchParams.get("buscar")'),'Cliente');
  await b.evaluate('[...document.querySelectorAll(".context-toolbar a")].find(a=>a.textContent.includes("Editar datos")).click()');
  await b.wait('!!document.querySelector(".master-drawer[open]")');
  assert.equal(await b.evaluate('!!document.querySelector(".master-drawer input[name=NIT]")'),false);
  await fill({Nombre:'Cliente navegador editado',Correo:'editado@example.invalid',Telefono:'5555-0505'});
  await b.capture('clientes-editar-1366');
  await b.evaluate('document.querySelector(".master-drawer form").requestSubmit(document.querySelector(".master-drawer button[type=submit]"))');
  await b.wait('!document.querySelector(".master-drawer") && document.querySelector(".customer-identity h2").textContent==="Cliente navegador editado"');
  // Conflicto visible sin descartar campos: otra escritura real en la base aislada.
  await b.evaluate('[...document.querySelectorAll(".context-toolbar a")].find(a=>a.textContent.includes("Editar datos")).click()');await b.wait('!!document.querySelector(".master-drawer[open]")');
  await b.evaluate(`(async()=>{const f=document.querySelector('.master-drawer form'),token=document.querySelector('meta[name="csrf-token"]').content;await fetch(f.action,{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':token},body:JSON.stringify({Nombre:'Cambio concurrente aislado',Correo:'concurrente@example.invalid',Telefono:'5555',Version:f.elements.Version.value})});f.elements.Nombre.value='Borrador conservado';f.requestSubmit(f.querySelector('button[type=submit]'));})()`);
  await b.wait('!document.querySelector(".form-feedback").hidden');
  assert.equal(await b.evaluate('document.querySelector(".master-drawer [name=Nombre]").value'),'Borrador conservado');
  await b.capture('clientes-conflicto-1366');
  await b.navigate(base+'/proveedores?id='+supplier+'&editar=1');await b.wait('!!document.querySelector(".master-drawer[open]")');
  await b.capture('proveedores-editar-1366');
  await b.evaluate('document.querySelector(".master-drawer [name=Activo]").value="0";document.querySelector(".master-drawer form").requestSubmit(document.querySelector(".master-drawer button[type=submit]"))');
  await b.wait('document.querySelector("#master-confirm").open');await b.capture('proveedores-confirmacion-1366');
  await b.evaluate('document.querySelector("#master-confirm button[value=cancel]").click()');
  await b.wait('!document.querySelector("#master-confirm").open && document.activeElement.type==="submit"');
  assert.equal(await b.evaluate('document.activeElement.type'),'submit','Retorno del foco');
  const routes={clientes:'/clientes?id='+client,proveedores:'/proveedores?id='+supplier,productos:'/productos',inventario:'/inventario?id='+product};
  for(const width of [1920,1366,1024,768,390,320]){
   await b.viewport(width,width<500?844:900);
   for(const [module,route]of Object.entries(routes)){
    await b.navigate(base+route);
    assert.equal(await b.evaluate('document.documentElement.scrollWidth<=document.documentElement.clientWidth'),true,module+' overflow '+width);
    assert.equal(await b.evaluate('(()=>{const ids=[...document.querySelectorAll("[id]")].map(x=>x.id);return ids.length===new Set(ids).size;})()'),true,module+' IDs');
    if(width===1366||width===390)await b.capture(module+'-'+width);
   }
   for(const route of ['/clientes?nuevo=1','/proveedores?nuevo=1','/productos?nuevo=1','/productos?vista=tabla']){
    await b.navigate(base+route);await b.wait('!!document.querySelector("#workspace")');
    assert.equal(await b.evaluate('document.documentElement.scrollWidth<=document.documentElement.clientWidth'),true,route+' overflow '+width);
    assert.equal(await b.evaluate('[...document.querySelectorAll("input:not([type=hidden]),select")].every(e=>e.id&&document.querySelector("label[for=\\\""+e.id+"\\\"]"))'),true,route+' labels');
    if(width===1366||width===390)await b.capture(route.includes('tabla')?'productos-tabla-'+width:route.split('?')[0].slice(1)+'-formulario-'+width);
   }
  }
  await b.viewport(1366,900);await b.navigate(base+'/clientes?nuevo=1');await b.wait('!!document.querySelector(".master-drawer[open]")');
  await b.cdp('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await b.cdp('Input.dispatchKeyEvent',{type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});await b.wait('!document.querySelector(".master-drawer")');
  await b.cdp('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'reduce'}]});await b.navigate(base+'/clientes?nuevo=1');await b.wait('!!document.querySelector(".master-drawer[open]")');assert.equal(await b.evaluate('getComputedStyle(document.querySelector(".master-drawer")).animationName'),'none');
  await b.viewport(683,450);await b.capture('clientes-zoom200-equivalente');
  assert.deepEqual(b.errors,[],'Sin excepciones JavaScript');
 });
}
module.exports={run};
