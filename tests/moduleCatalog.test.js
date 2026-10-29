'use strict';
const {test}=require('node:test');const assert=require('node:assert/strict');
const {areas,modules,visibleAreas}=require('../src/config/moduleCatalog');
test('catálogo: seis áreas, identificadores únicos y rutas reales solo para disponibles',()=>{
 assert.equal(areas.length,6);assert.equal(new Set(modules.map(m=>m.id)).size,modules.length);
 modules.forEach(m=>{assert.ok(areas.some(a=>a.id===m.area));assert.equal(Boolean(m.route),m.available);});
});
test('catálogo: perfiles sin permisos y módulos futuros no exponen enlaces operativos',()=>{
 const rows=visibleAreas({permisos:[]}).flatMap(a=>a.modules);
 assert.deepEqual(rows.map(m=>m.id),['dashboard','password']);assert.ok(rows.every(m=>m.available));
});
test('catálogo: creación sin consulta usa alta, consulta conserva historial',()=>{
 const find=permissions=>visibleAreas({permisos:permissions}).flatMap(a=>a.modules).find(m=>m.id==='cotizaciones');
 assert.equal(find(['COTIZACIONES_CREAR']).route,'/cotizaciones/nueva');assert.equal(find(['COTIZACIONES_CONSULTAR']).route,'/cotizaciones');
});
test('catálogo: cada permiso habilita únicamente módulos con ese permiso o públicos autenticados',()=>{
 for(const permission of new Set(modules.flatMap(m=>m.permissions))){
  const visible=visibleAreas({permisos:[permission]}).flatMap(a=>a.modules);
  assert.ok(visible.every(m=>!m.permissions.length||m.permissions.includes(permission)));
  assert.equal(visible.length,modules.filter(m=>m.available&&(!m.permissions.length||m.permissions.includes(permission))).length);
 }
});
test('vigencia comercial conserva límite SQL exclusivo y no inventa días completos',async()=>{
 const ejs=require('ejs');
 const render=value=>ejs.renderFile('src/views/partials/commercial-validity.ejs',{value});
 assert.match(await render('2026-10-29T06:00:00.000Z'),/28\/10\/2026, inclusive/);
 assert.match(await render('2026-10-29T17:00:00.000Z'),/Vence el.*29\/10\/2026/s);
});
test('Centro de módulos exige sesión; perfil sin permisos no recibe enlaces restringidos',async()=>{
 const {createApp}=require('../server');const {once}=require('node:events');
 const app=createApp({secret:'test-module-center-secret-at-least-32-characters',authService:{}});
 const server=app.listen(0,'127.0.0.1');await once(server,'listening');
 try{const response=await fetch('http://127.0.0.1:'+server.address().port+'/modulos',{redirect:'manual'});assert.equal(response.status,302);assert.equal(response.headers.get('location'),'/login');}
 finally{await new Promise(r=>server.close(r));}
 const ejs=require('ejs'),html=await ejs.renderFile('src/views/modulos.ejs',{moduleAreas:visibleAreas,usuario:{nombreUsuario:'Consulta',permisos:[]}});
 assert.ok(html.includes('Tu cuenta no tiene funciones habilitadas'));
 for(const route of ['/facturacion','/cotizaciones','/usuarios','/auditoria'])assert.ok(!html.includes('href="'+route+'"'));
});
test('catalogo: visibilidad DDL independiente del permiso de auditoria DML',()=>{
 const visible=permisos=>visibleAreas({permisos}).flatMap(area=>area.modules);
 for(const permisos of [[],['AUDITORIA_CONSULTAR'],['USUARIOS_ADMINISTRAR']]){
  assert.ok(!visible(permisos).some(module=>module.id==='auditoria-ddl'));
 }
 const ddl=visible(['AUDITORIA_DDL_CONSULTAR']);
 assert.equal(ddl.find(module=>module.id==='auditoria-ddl').route,'/auditoria/ddl');
 assert.ok(!ddl.some(module=>module.id==='auditoria'));
 const both=visible(['AUDITORIA_CONSULTAR','AUDITORIA_DDL_CONSULTAR']);
 assert.deepEqual(both.filter(module=>['auditoria','auditoria-ddl'].includes(module.id)).map(module=>module.route).sort(),['/auditoria','/auditoria/ddl']);
});
