'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),{once}=require('node:events'),{randomUUID}=require('node:crypto');
const {createApp}=require('../server');
const {mockCompras,permissions}=require('./helpers/comprasFixture');
const {createComprasService}=require('../src/modules/compras/service');
const ui=require('../src/public/js/compras');
const v=require('../src/modules/compras/validation');
async function fixture(t,permisos=permissions){
 const f=mockCompras();
 const app=createApp({secret:'compras-http-test-session-secret-long-enough',comprasService:f.service,authService:{login:async()=>({codigo:0,usuario:{usuarioId:42,nombreUsuario:'Operador DEMO',permisos,debeCambiarPassword:false}})}});
 const server=app.listen(0,'127.0.0.1');await once(server,'listening');t.after(()=>new Promise(resolve=>{server.close(resolve);server.closeAllConnections();}));
 const base='http://127.0.0.1:'+server.address().port;
 const login=await fetch(base+'/login',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'NombreUsuario=test&Password=test',redirect:'manual'}),cookie=login.headers.get('set-cookie').split(';')[0];
 const get=(url,options={})=>fetch(base+url,{redirect:'manual',...options,headers:{Cookie:cookie,...options.headers}});
 const html=await(await get(permisos.includes('COMPRAS_CONSULTAR')?'/compras':'/compras/nueva')).text(),csrf=html.match(/name="csrf-token" content="([a-f0-9]+)"/)?.[1];
 const post=(url,data,token=csrf)=>get(url,{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':token||''},body:JSON.stringify(data)});
 return{...f,base,get,post,html};
}
const change=()=>({OperacionId:randomUUID(),Version:'0000000000000001',Motivo:'Prueba de contrato'});
test('Compras web: vistas, navegación, escape, contexto global y precisión',async t=>{
 const f=await fixture(t);f.orden.ProveedorNombre='<script>hostile()</script>';
 for(const url of ['/compras','/compras/nueva','/compras/7','/compras/valoracion/3']){const r=await f.get(url);assert.equal(r.status,200,url);assert.equal(r.headers.get('cache-control'),'no-store');const html=await r.text();assert.match(html,/Inventario global/);assert.match(html,/\/css\/compras.css/);assert.doesNotMatch(html,/<script>hostile\(\)<\/script>/);assert.doesNotMatch(html,/name="ActorUsuarioId"|name="BodegaId"/);}
 assert.match(f.html,/aria-label="Órdenes de compra"/);
 const detail=await(await f.get('/compras/7')).text();assert.match(detail,/2,200\.0000/);assert.match(detail,/data-print/);assert.match(detail,/data-receive-form/);
});
test('Compras web: autenticación y permisos bloquean acceso antes de servicios',async t=>{
 const f=await fixture(t,[]);for(const route of ['/compras','/compras/nueva','/compras/7','/compras/valoracion/3']){assert.equal((await fetch(f.base+route,{redirect:'manual'})).status,302);assert.equal((await f.get(route)).status,403);}
 for(const route of ['/compras','/compras/7/enviar','/compras/7/aprobar','/compras/7/cancelar','/compras/7/recibir','/compras/valoracion/3/actualizar'])assert.equal((await f.post(route,{})).status,403);assert.equal(f.calls.length,0);
});
test('Compras web: CSRF, actor de sesión y aprobación separada',async t=>{
 const f=await fixture(t);const d={...change(),ActorUsuarioId:999,OrdenCompraId:999};
 for(const token of ['', 'bad','a'.repeat(64)])assert.equal((await f.post('/compras/7/aprobar',d,token)).status,403);
 assert.equal((await f.post('/compras/7/aprobar',d)).status,200);
 const c=f.calls.find(x=>x[0]==='approve');assert.equal(c[1],42);assert.equal(c[2].OrdenCompraId,7);assert.equal(c[2].ActorUsuarioId,undefined);
 const denied=await fixture(t,['COMPRAS_CREAR','COMPRAS_CONSULTAR']);assert.equal((await denied.post('/compras/7/aprobar',change())).status,403);
 f.service.approve=async()=>{throw Object.assign(Error('internal private SQL'),{number:55001});};const own=await f.post('/compras/7/aprobar',change());assert.equal(own.status,403);assert.doesNotMatch(await own.text(),/internal private/);
 f.orden.Estado='PENDIENTE_APROBACION';f.orden.CreadorUsuarioId=42;assert.doesNotMatch(await(await f.get('/compras/7')).text(),/data-action="aprobar"/);
});
test('Compras web: recepción exige ambos permisos y valida entrega antes de servicio',async t=>{
 const f=await fixture(t);const d={...change(),DocumentoRespaldo:'COM-001',Detalle:[{ProductoId:3,Cantidad:10,CostoUnitario:'100.1234'}]};
 for(const patch of [{Detalle:[]},{Detalle:[{ProductoId:3,Cantidad:1.5,CostoUnitario:'1'}]},{DocumentoRespaldo:''},{Version:'bad'},{BodegaId:1}])assert.equal((await f.post('/compras/7/recibir',{...d,...patch})).status,400);
 assert.equal((await f.post('/compras/7/recibir',d)).status,200);const c=f.calls.find(x=>x[0]==='receive');assert.equal(c[1],42);assert.equal(c[2].Detalle[0].CostoUnitario,'100.1234');
 for(const missing of ['COMPRAS_RECIBIR','INVENTARIO_REGISTRAR']){const denied=await fixture(t,permissions.filter(p=>p!==missing));assert.equal((await denied.post('/compras/7/recibir',d)).status,403);}
 f.service.receive=async()=>{throw Object.assign(Error('SQL'),{number:55006});};assert.equal((await f.post('/compras/7/recibir',d)).status,409);
});
test('Compras web: errores inciertos, filtros, campos y 100 líneas sin truncar',async t=>{
 const f=await fixture(t);for(const url of ['/compras?pagina=0','/compras?pagina=20002','/compras?estado=UNKNOWN','/compras/abc','/compras/buscar/productos?proveedor=1e2'])assert.equal((await f.get(url)).status,400);
 const d={ProveedorId:2,OperacionId:randomUUID(),Detalle:Array.from({length:100},(_,i)=>({ProductoId:i+1,Cantidad:2147483647,CostoUnitario:'999999999999999.9999'}))};
 assert.equal((await f.post('/compras',d)).status,201);assert.equal(f.calls.find(x=>x[0]==='create')[2].Detalle.length,100);
 f.service.create=async()=>{throw Error('Private connection password');};const r=await f.post('/compras',d);assert.equal(r.status,503);const error=await r.json();assert.equal(error.incierto,true);assert.doesNotMatch(error.error,/Private connection password/);
});
test('Compras: recepción ignora resultados intermedios y exige confirmación final',async()=>{
 const d={...change(),OrdenCompraId:7,DocumentoRespaldo:'DOC',Detalle:[{ProductoId:3,Cantidad:1,CostoUnitario:'1.1234'}]},calls=[];
 const final={OrdenCompraId:7,OperacionId:d.OperacionId,Estado:'PARCIALMENTE_RECIBIDA',Version:Buffer.alloc(8)};
 const build=sets=>createComprasService(async()=>({request(){return{input(...p){calls.push(p);return this;},execute:async()=>({recordsets:sets})};}}));
 const result=await build([[{RecepcionId:'1',OperacionId:randomUUID(),StockResultante:1}],[final]]).receive(42,d);assert.equal(result.Estado,'PARCIALMENTE_RECIBIDA');
 assert.equal(JSON.parse(calls.find(p=>p[0]==='Detalle')[2])[0].CostoUnitario,'1.1234');
 await assert.rejects(build([[{RecepcionId:'1'}]]).receive(42,d),/incompatible/);
 await assert.rejects(build([[{...final,OperacionId:randomUUID()}]]).receive(42,d),/incompatible/);
});
test('Compras: dinero de formularios y presentación exacto en extremos',()=>{
 const lines=[{Cantidad:2147483647,CostoUnitario:'999999999999999.9999'}];assert.equal(ui.total(lines),2147483647n*9999999999999999999n);
 assert.equal(ui.money(ui.total([{Cantidad:10,CostoUnitario:'100'},{Cantidad:10,CostoUnitario:'120'}])),'Q 2,200.0000');
 assert.equal(ui.money(ui.total([{Cantidad:3,CostoUnitario:'0.0001'}])),'Q 0.0003');
 for(const value of ['-1','1e2','1.00001','01','1,20'])assert.throws(()=>ui.cost(value));
 assert.throws(()=>ui.quantity('1.5'));assert.throws(()=>ui.quantity('2147483648'));
 assert.throws(()=>v.create({ProveedorId:2,OperacionId:randomUUID(),BodegaId:1,Detalle:[]}));
 const {money}=require('../src/modules/compras/format');assert.equal(money(null),'Sin valorar');assert.equal(money('110.00000000'),'Q 110.00000000');
});
test('Compras: catálogo habilitado y creación independiente de consulta',()=>{
 const {visibleAreas,modules}=require('../src/config/moduleCatalog');assert.equal(modules.filter(m=>m.id==='compras-p3').length,1);
 const find=p=>visibleAreas({permisos:p}).flatMap(a=>a.modules).find(m=>m.id==='compras-p3');assert.equal(find(['COMPRAS_CREAR']).route,'/compras/nueva');assert.equal(find(['COMPRAS_CONSULTAR']).route,'/compras');assert.equal(find([]),undefined);
});
test('Compras: paginación independiente de entregas e historial',async t=>{
 const f=await fixture(t),calls=[];
 f.service.detail=async(actor,id,offset)=>{calls.push(['detail',actor,id,offset]);return{orden:f.orden,detalle:f.detalle,recepciones:Array.from({length:51},()=>({DocumentoRespaldo:'DEMO',Cantidad:1,CostoDocumentado:'1.0000'}))};};
 f.service.history=async(actor,id,offset)=>{calls.push(['history',actor,id,offset]);return Array.from({length:51},()=>({EstadoNuevo:'APROBADA',Motivo:'DEMO'}));};
 const r=await f.get('/compras/7?entregas=2&historial=3');assert.equal(r.status,200);const html=await r.text();
 assert.deepEqual(calls,[['detail',42,7,50],['history',42,7,100]]);assert.match(html,/entregas=3&amp;historial=3/);assert.match(html,/entregas=2&amp;historial=4/);
 assert.equal((await f.get('/compras/7?historial=-1')).status,400);
});
test('Compras: extensiones SQL conservan escritor de inventario único (inspección estática)',()=>{
 const fs=require('node:fs'),path=require('node:path'),root=path.join(__dirname,'../database');
 for(const n of [52,53,54,55]){const file=fs.readdirSync(root).find(f=>f.startsWith(n+'_')),s=fs.readFileSync(path.join(root,file),'utf8');
  assert.doesNotMatch(s,/\b(?:UPDATE|ALTER\s+TABLE|INSERT(?:\s+INTO)?|DELETE\s+FROM)\s+dbo\.(?:Producto|Proveedor|Kardex_Inventario|RecepcionCompra|DetalleRecepcionCompra)\b/i);
  for(const m of s.matchAll(/CREATE OR ALTER (?:PROCEDURE|TRIGGER) dbo\.([A-Za-z_][A-Za-z0-9_]*)/g))assert.ok(m[1].startsWith('P3_COM_'));
  assert.doesNotMatch(s,/EXEC\s+dbo\.sp_RegistrarMovimientoKardex/i);
  if(n===52){assert.equal([...s.matchAll(/EXEC dbo\.sp_RegistrarRecepcionCompra/g)].length,1);assert.match(s,/ROUND\(@Cost,2,1\)/);}
 }
});
