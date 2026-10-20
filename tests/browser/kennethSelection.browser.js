'use strict';
// Real SQL reads; writes are allowed only in the explicitly named isolated DB.
require('dotenv').config({quiet:true});
const previewActor=Number(process.env.KENNETH_PREVIEW_USER_ID);if(!Number.isSafeInteger(previewActor)||previewActor<1)throw new Error('Configura KENNETH_PREVIEW_USER_ID con el usuario autorizado del laboratorio.');

const assert=require('node:assert/strict');
const {once}=require('node:events');
const fs=require('node:fs/promises');
const db=require('../../src/config/database');
const before=process.argv.includes('--before');
const write=process.argv.includes('--write');
const writeDatabase=process.env.KENNETH_TEST_DATABASE;
if(write){if(!/^SecureFinanceERP_ParteII_Test_[A-Za-z0-9_]+$/.test(writeDatabase||''))throw new Error('KENNETH_TEST_DATABASE debe ser una base aislada con prefijo SecureFinanceERP_ParteII_Test_.');process.env.DB_NAME=writeDatabase;}
 const report={database:process.env.DB_NAME,before,checks:[],completed:false};
(async()=>{
 let server;
 try{
 const pool=await db.getPool();
 const database=(await pool.request().query('SELECT DB_NAME() n')).recordset[0].n;
 if(write)assert.equal(database,writeDatabase);
 const actor=previewActor;
 const permissions=(await pool.request().input('UsuarioId',db.sql.Int,actor).execute('dbo.sp_ObtenerPermisosUsuario')).recordset.map(x=>x.Codigo);
 server=require('../../server').createApp({production:false,authService:{login:async()=>({codigo:0,usuario:{usuarioId:actor,nombreUsuario:'admin',permisos:permissions,debeCambiarPassword:false}})}}).listen(0,'127.0.0.1');
 await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
 await require('./kennethCapture').withBrowser('docs/capturas/kenneth-final/'+(before?'antes':write?'aislado':'principal'),async b=>{
 await b.viewport(1366,768);await b.navigate(base+'/login');await b.evaluate("fetch('/login',{method:'POST',body:new URLSearchParams({NombreUsuario:'qa',Password:'isolated-session'})})");
 const clientService=require('../../src/services/clienteService').createClienteService(); const snapshotClients=()=>clientService.list(actor,{}); const clients=await snapshotClients();
 await b.navigate(base+'/clientes');await b.capture('clientes-1366');
 for(const id of [1,3,2,1]){
 const c=clients.find(x=>x.ClienteId===id);assert(c);
 // Click the NIT cell, as a directory row user does, not just the name link.
 await b.evaluate(`[...document.querySelectorAll("tr a")].find(a=>new URL(a.href).searchParams.get("id")===String(${id})).closest('tr').querySelector('td').click()`);
 if(before){await new Promise(r=>setTimeout(r,400));report.checks.push({id,expected:c.Nombre,actual:await b.evaluate('document.querySelector(".identity-heading h2").textContent'),url:await b.evaluate('location.search')});continue;}
 await b.wait(`document.querySelector('.identity-heading h2').textContent===${JSON.stringify(c.Nombre)}`);
 assert.equal(await b.evaluate('document.querySelector(".customer-identity .fiscal-number strong").textContent'),c.NIT);
 assert.equal(await b.evaluate('document.querySelector(".record-technical").textContent.includes("ClienteId: '+id+'")'),true);const facts=await b.evaluate('document.querySelector(".customer-identity .master-facts").textContent');
 for(const value of [c.Correo||'Sin registro',c.Telefono||'Sin registro'])assert(facts.includes(value));
 assert.equal(await b.evaluate('document.querySelector(".identity-heading .master-status").textContent'),c.Activo?'Activo':'Inactivo');
 assert.equal(await b.evaluate(`!!document.querySelector('tr.is-selected a[href*="id=${id}"]')`),true);
 for(const action of ['nit','inactivar'])if(c.Activo||action==='nit')assert.equal(await b.evaluate(`document.querySelector('form[action$="/${action}"]').getAttribute('action')`),`/clientes/${id}/${action}`);
 await b.evaluate('document.querySelector(".context-toolbar a").click()');await b.wait('!!document.querySelector(".master-drawer[open]")');
 assert.equal(await b.evaluate('document.querySelector(".master-drawer form").getAttribute("action")'),`/clientes/${id}/datos`);
 for(const field of ['Nombre','Correo','Telefono'])assert.equal(await b.evaluate(`document.querySelector('.master-drawer [name=${field}]').value`),c[field]||'');
 await b.capture('cliente-'+id+'-editor');
 if(write){
 const snapshot=await snapshotClients();
 const phone='5555-'+String(Date.now()).slice(-4);
 await b.evaluate(`document.querySelector('.master-drawer [name=Telefono]').value=${JSON.stringify(phone)};document.querySelector('.master-drawer form').requestSubmit()`);
 await b.wait('!document.querySelector(".master-drawer[open]") && !document.querySelector("#module-message").hidden');
 const after=await snapshotClients();
 assert.deepEqual(after.filter((row,i)=>JSON.stringify(row)!==JSON.stringify(snapshot[i])).map(x=>x.ClienteId),[id]);
 assert.equal(after.find(x=>x.ClienteId===id).Telefono,phone);c.Telefono=phone;
 }else{
 await b.evaluate("document.querySelector('.master-drawer [name=Nombre]').value='NO GUARDAR';[...document.querySelectorAll('.master-drawer a')].find(a=>a.textContent==='Cancelar').click()");await b.wait('!document.querySelector(".master-drawer[open]")');
 assert.equal((await snapshotClients()).find(row=>row.ClienteId===id).Nombre,c.Nombre);
 }
 await b.evaluate('new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))');report.checks.push({id,name:c.Nombre,result:'PASS',write,...(write?{sqlVerifiedChangedIds:[id]}:{cancelVerified:true})});
 }
 if(before)return;
 // Native keyboard activation, including Space, must use the same record link.
 await b.evaluate("[...document.querySelectorAll('tr a')].find(a=>new URL(a.href).searchParams.get('id')==='3').focus()");await b.cdp('Input.dispatchKeyEvent',{type:'keyDown',key:' ',code:'Space',windowsVirtualKeyCode:32});await b.cdp('Input.dispatchKeyEvent',{type:'keyUp',key:' ',code:'Space',windowsVirtualKeyCode:32});await b.wait('document.querySelector(".identity-heading h2").textContent.includes("Consumidor")');
 await b.evaluate("[...document.querySelectorAll('tr a')].find(a=>new URL(a.href).searchParams.get('id')==='2').focus()");await b.cdp('Input.dispatchKeyEvent',{type:'keyDown',key:'Enter',code:'Enter',windowsVirtualKeyCode:13});await b.cdp('Input.dispatchKeyEvent',{type:'keyUp',key:'Enter',code:'Enter',windowsVirtualKeyCode:13});await b.wait('document.querySelector(".identity-heading h2").textContent.includes("Horizonte")');
 await b.evaluate(`document.querySelector('.master-search input[name=buscar]').value=${JSON.stringify(clients.find(c=>c.ClienteId===2).Nombre)};document.querySelector('.master-search').requestSubmit()`);
 await b.wait('document.querySelectorAll("tr[data-record-id]").length===1 && !document.querySelector("#workspace[aria-busy]")');
 assert.equal(await b.evaluate('document.querySelector(".identity-heading h2").textContent'),clients.find(c=>c.ClienteId===2).Nombre);
 await b.navigate(base+'/clientes');
 if(!write){await b.evaluate("(()=>{const state=document.querySelector('#directory-state');state.value='inactivo';state.dispatchEvent(new Event('change'))})()");assert.equal(await b.evaluate('document.querySelector(".customer-identity").hidden'),true);await b.evaluate("(()=>{const state=document.querySelector('#directory-state');state.value='';state.dispatchEvent(new Event('change'))})()");assert.equal(await b.evaluate('document.querySelector(".customer-identity").hidden'),false);}
 for(const module of ['proveedores','productos','inventario']){
 await b.navigate(base+'/'+module);
 const links=await b.evaluate(`Array.from(document.querySelectorAll(${JSON.stringify(module==='proveedores'?'.supplier-entry':module==='inventario'?'.stock-entry':'.catalog-media')})).map(a=>a.getAttribute('href'))`);
 for(const href of links){
 await b.evaluate(`document.querySelector('a[href='+CSS.escape(${JSON.stringify(href)})+']').click()`);await b.wait(`location.search===new URL(${JSON.stringify(href)},location.href).search && !document.querySelector('#workspace[aria-busy]')`);
 const id=Number(new URL(href,base).searchParams.get('id'));
 const service=module==='proveedores'?require('../../src/services/proveedorService').createProveedorService():require('../../src/services/productoService').createProductoService();
 const record=(await service.list(actor,{id,costo:module==='productos',inventario:module==='inventario'}))[0];assert(record);
 if(module==='proveedores'){
 assert.equal(await b.evaluate('document.querySelector(".supplier-profile h2").textContent'),record.Nombre);
 await b.evaluate("document.querySelector('.supplier-profile a').focus()");await b.cdp('Input.dispatchKeyEvent',{type:'keyDown',key:'Enter',code:'Enter',windowsVirtualKeyCode:13});await b.cdp('Input.dispatchKeyEvent',{type:'keyUp',key:'Enter',code:'Enter',windowsVirtualKeyCode:13});await b.wait('!!document.querySelector(".master-drawer[open]")');
 for(const field of ['Nombre','NIT','Correo','Telefono','Direccion'])assert.equal(await b.evaluate(`document.querySelector('.master-drawer [name=${field}]').value`),record[field]||'');
 assert.equal(await b.evaluate('document.querySelector(".master-drawer form").getAttribute("action")'),'/proveedores/'+id);
 await b.evaluate("document.querySelector('.master-drawer a').click()");await b.wait('!document.querySelector(".master-drawer[open]")');
 }else if(module==='productos'){
 for(const [field,value] of Object.entries({Codigo:record.Codigo,Descripcion:record.Descripcion,ProveedorId:String(record.ProveedorId??'')}))assert.equal(await b.evaluate(`document.querySelector('.master-editor [name=${field}]').value`),value);
 assert.equal(Number(await b.evaluate('document.querySelector(".master-editor [name=Precio]").value')),Number(record.Precio));
 assert.equal(await b.evaluate('document.querySelector(".stock-readonly strong").textContent'),String(record.Stock));
 assert.equal(await b.evaluate('document.querySelector(".master-editor form").getAttribute("action")'),'/productos/'+id);
 assert.equal(await b.evaluate('!!document.querySelector(".master-editor [name=Stock]")'),false);
 if(record.Fotografia)assert.equal(await b.evaluate('document.querySelector("#photo-preview").getAttribute("src")'),'/fotografias/'+record.Fotografia);
 await b.evaluate("document.querySelector('.view-switch a').click()");await b.wait('!!document.querySelector(".product-table") && !document.querySelector("#workspace[aria-busy]")');
 assert.equal(await b.evaluate('document.querySelector(".master-editor [name=Codigo]").value'),record.Codigo);
 await b.evaluate("document.querySelector('.view-switch a:last-child').click()");await b.wait('!!document.querySelector(".catalog-grid") && !document.querySelector("#workspace[aria-busy]")');
 }else{
 assert.equal(await b.evaluate('document.querySelector(".stock-heading h2").textContent'),record.Descripcion);
 assert.equal(await b.evaluate('document.querySelector(".stock-total strong").textContent'),String(record.Stock));
 assert.equal(await b.evaluate('document.querySelector("[name=ProductoId]").value'),String(id));
 const history=await require('../../src/services/inventarioService').createInventarioService().history(actor,{id});
 assert.equal(await b.evaluate('document.querySelectorAll(".kardex-table tbody tr").length'),Math.min(50,history.length));
 }
 }
 report.checks.push({module,selections:links.length,result:'PASS'});
 }
 for(const [width,height] of [[1366,768],[1920,1080],[390,844]]){await b.viewport(width,height);for(const module of ['clientes','proveedores','productos','inventario']){await b.navigate(base+'/'+module);assert.equal(await b.evaluate('document.documentElement.scrollWidth>innerWidth'),false,module+' overflow '+width);await b.evaluate('Promise.all([...document.images].map(img=>{img.loading="eager";return img.decode().catch(()=>null)}))');if(module==='productos'&&!write)assert.equal(await b.evaluate('[...document.querySelectorAll(".catalog-media img")].every(img=>img.complete&&img.naturalWidth>0)'),true);await b.capture(module+'-'+width);}await b.navigate(base+'/clientes?id=2&editar=1');await b.wait('!!document.querySelector(".master-drawer[open]")');await b.capture('clientes-drawer-'+width);}
 for(const width of [1024,768,320]){await b.viewport(width,844);for(const module of ['clientes','proveedores','productos','inventario']){await b.navigate(base+'/'+module);assert.equal(await b.evaluate('document.documentElement.scrollWidth>innerWidth'),false,module+' overflow '+width);}}
 await b.viewport(1366,768);await b.navigate(base+'/clientes?id=2&editar=1');await b.wait('!!document.querySelector(".master-drawer[open]")');await b.evaluate('document.documentElement.style.zoom="2"');assert.equal(await b.evaluate('document.documentElement.scrollWidth>innerWidth'),false,'Drawer zoom 200%');await b.capture('clientes-drawer-zoom200');
 report.responsiveWidths=[1920,1366,1024,768,390,320];report.drawerZoom='200% PASS';
 assert.deepEqual(b.errors,[]);
 report.completed=true;
 });
 }finally{if(server){server.closeAllConnections();await new Promise(r=>server.close(r));}await db.closePool();await fs.writeFile('docs/ParteIIFinal'+(before?'Antes':write?'Aislado':'Principal')+'.json',JSON.stringify(report,null,2)+'\n');}
})().catch(e=>{console.error(e);process.exitCode=1;});
