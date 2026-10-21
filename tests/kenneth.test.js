'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {once}=require('node:events');
const fs=require('node:fs/promises');
const os=require('node:os');
const path=require('node:path');
const sharp=require('sharp');
const {createApp}=require('../server');
const {createFotografiaService}=require('../src/services/fotografiaService');
const {createProductoService}=require('../src/services/productoService');
const {createProveedorService}=require('../src/services/proveedorService');
const {createClienteService}=require('../src/services/clienteService');
const {createInventarioService}=require('../src/services/inventarioService');
const validation=require('../src/controllers/kennethValidation');
const permissions=['CLIENTES_REGISTRAR','CLIENTES_EDITAR','PRODUCTOS_CONSULTAR','PRODUCTOS_ADMINISTRAR','PROVEEDORES_CONSULTAR','PROVEEDORES_ADMINISTRAR','CLIENTES_CONSULTAR','CLIENTES_ACTUALIZAR_NIT','CLIENTES_INACTIVAR','INVENTARIO_CONSULTAR','INVENTARIO_REGISTRAR','INVENTARIO_AJUSTAR','AUDITORIA_CONSULTAR'];
const product={ProductoId:1,Codigo:'PR-TEST',Descripcion:'Producto <script>test</script>',Precio:25,PrecioCosto:10,Stock:4,StockMinimo:5,PuntoReorden:8,GarantiaMeses:12,ProveedorId:1,Proveedor:'Proveedor de prueba',Activo:true,Version:'0000000000000001'};
const supplier={ProveedorId:1,NIT:'TEST1',Nombre:'Proveedor de prueba',Activo:true,Version:product.Version};
const customer={ClienteId:1,NIT:'CLIENTE1',Nombre:'Cliente de prueba',Activo:true,Version:product.Version,FechaCreacion:new Date('2026-10-01')};
async function fixture(t,permisos=permissions){
 const calls=[], directory=await fs.mkdtemp(path.join(os.tmpdir(),'sf-photo-unit-'));
 const services={productos:{relations:async()=>[],list:async(a,f)=>{calls.push(['products',a,f]);return[product];},save:async(a,d)=>{calls.push(['product-save',a,d]);return[product];}},proveedores:{list:async()=>[supplier],save:async(a,d)=>{calls.push(['supplier-save',a,d]);return[supplier];}},clientes:{list:async()=>[customer],save:async(a,d)=>{calls.push(['client-save',a,d]);return[customer];},update:async(a,d,inactive)=>{calls.push(['client',a,d,inactive]);return[customer];}},inventario:{state:async()=>[{Habilitado:false}],history:async()=>[],receive:async(a,d)=>{calls.push(['receive',a,d]);return[{KardexId:7}];},move:async(a,d)=>{calls.push(['move',a,d]);return[{KardexId:7}];}},photos:createFotografiaService(directory)};
 const app=createApp({secret:'isolated-test-session-secret-32-characters',kennethServices:services,authService:{login:async()=>({codigo:0,usuario:{usuarioId:42,nombreUsuario:'Pruebas',permisos,debeCambiarPassword:false}})}});
 const server=app.listen(0,'127.0.0.1');await once(server,'listening');
 t.after(async()=>{await new Promise(resolve=>{server.close(resolve);server.closeAllConnections();});await fs.rm(directory,{recursive:true,force:true});});
 const base='http://127.0.0.1:'+server.address().port;
 const login=await fetch(base+'/login',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'NombreUsuario=test&Password=test',redirect:'manual'});
 const cookie=login.headers.get('set-cookie').split(';')[0];
 const request=(url,options={})=>fetch(base+url,{redirect:'manual',...options,headers:{Cookie:cookie,...options.headers}});
 const html=await(await request('/productos')).text();const csrf=html.match(/name="csrf-token" content="([a-f0-9]+)"/)?.[1];
 const post=(url,body,token=csrf)=>request(url,{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':token||''},body:JSON.stringify(body)});
 return{calls,services,request,post,csrf,html,base,directory};
}
test('Kenneth: vistas reales, escape EJS, navegación y Kardex deshabilitado',async t=>{
 const f=await fixture(t);for(const route of ['/productos','/productos?nuevo=1','/productos?id=1','/proveedores','/proveedores?nuevo=1','/clientes','/inventario']){
  const r=await f.request(route);assert.equal(r.status,200,route);const html=await r.text();assert.match(html,/meta name="csrf-token"/);assert.doesNotMatch(html,/<script>test<\/script>/);
  if(route==='/inventario'){assert.match(html,/Kardex deshabilitado/);assert.match(html,/<fieldset disabled>/);assert.doesNotMatch(html,/habilitar automáticamente/);}
  if(route==='/clientes')assert.match(html,/\/auditoria\?vista=ventas&amp;cliente=Cliente%20de%20prueba/);
 }assert.match(f.html,/href="\/inventario"/);
});
test('Kenneth: todas las rutas requieren sesión y permisos, sin escrituras',async t=>{
 const f=await fixture(t,[]);for(const route of ['/productos','/inventario','/proveedores','/clientes']){assert.equal((await fetch(f.base+route,{redirect:'manual'})).status,302);assert.equal((await f.request(route)).status,403);}assert.equal((await f.post('/productos',{})).status,403);assert(!f.calls.some(c=>c[0].endsWith('save')));
});
test('Kenneth: CSRF aislado y rechazo antes del servicio',async t=>{
 const f=await fixture(t);assert.equal((await f.post('/productos',{},'bad')).status,403);assert.equal((await f.post('/clientes/1/nit',{},'a'.repeat(64))).status,403);assert(!f.calls.some(c=>c[0].endsWith('save')||c[0]==='client'));
});
const validProduct={Codigo:'PR1',Descripcion:'Producto',Precio:'12.30',PrecioCosto:'5.10',ProveedorId:'1',StockMinimo:'2',PuntoReorden:'3',GarantiaMeses:'12'};
test('Clientes: cada seleccion y drawer conserva su identidad y destino de edicion',async t=>{
 const f=await fixture(t);
 const clients=[1,2,3].map(id=>({...customer,ClienteId:id,Nombre:'Cliente '+id,NIT:'NIT'+id,Correo:'c'+id+'@example.invalid',Telefono:'5555-000'+id}));
 f.services.clientes.list=async(actor,filter)=>filter.id?clients.filter(c=>c.ClienteId===filter.id):clients;
 for(const id of [1,3,2,1]){
  const response=await f.request('/clientes?id='+id+'&editar=1');assert.equal(response.status,200);
  const html=await response.text();
  assert.match(html,new RegExp('data-record-id="'+id+'"[^>]*class="is-selected"'));
  assert.match(html,new RegExp('action="/clientes/'+id+'/datos"'));
  assert.match(html,new RegExp('action="/clientes/'+id+'/nit"'));
  assert.match(html,new RegExp('action="/clientes/'+id+'/inactivar"'));
  assert.match(html,new RegExp('value="Cliente '+id+'"'));
  assert.match(html,new RegExp('value="c'+id+'@example.invalid"'));
  await f.post('/clientes/'+id+'/datos',{Nombre:'Editado '+id,Correo:'c'+id+'@example.invalid',Telefono:'5555-000'+id,Version:customer.Version,ClienteId:999});
  assert.equal(f.calls.filter(c=>c[0]==='client-save').at(-1)[2].id,id);
 }
});
test('Kenneth: actor de sesión, sin Stock editable ni fotografía libre',async t=>{
 const f=await fixture(t);assert.equal((await f.post('/productos',{...validProduct,Stock:999,UsuarioId:666,Fotografia:'../../x'})).status,201);
 const c=f.calls.find(c=>c[0]==='product-save');assert.equal(c[1],42);assert.equal(c[2].Fotografia,null);assert.equal(c[2].Stock,undefined);assert.equal(c[2].UsuarioId,undefined);
});
test('Kenneth: validación de precio, proveedor, versión, cantidades y NIT',async t=>{
 const f=await fixture(t);
 for(const patch of [{Precio:'-1'},{PrecioCosto:'1.999'},{ProveedorId:'x'},{PuntoReorden:'1'},{GarantiaMeses:'32768'},{Codigo:''}])assert.equal((await f.post('/productos',{...validProduct,...patch})).status,400);
 assert.equal((await f.post('/productos/1',{...validProduct,Activo:'1',Version:'x'})).status,400);
 assert.equal((await f.post('/clientes/1/nit',{Version:product.Version,Motivo:'Cambio',NIT:'  '})).status,400);
 assert.equal((await f.post('/clientes/1/inactivar',{Version:product.Version,Motivo:''})).status,400);
 assert(!f.calls.some(c=>c[0]==='product-save'||c[0]==='client'));
});
test('Kenneth: NIT normalizado e inactivación por procedimiento, sin DELETE',async t=>{
 const f=await fixture(t);assert.equal((await f.post('/clientes/1/nit',{Version:product.Version,NIT:'1234-k',Motivo:'Corrección',UsuarioId:9})).status,200);assert.equal((await f.post('/clientes/1/inactivar',{Version:product.Version,Motivo:'Solicitud'})).status,200);
 const writes=f.calls.filter(c=>c[0]==='client');assert.equal(writes[0][1],42);assert.equal(writes[0][2].NIT,'1234K');assert.equal(writes[1][3],true);
});
test('Kenneth: cada acción fiscal y ajuste exige permiso específico',async t=>{
 const f=await fixture(t,['PRODUCTOS_CONSULTAR','CLIENTES_CONSULTAR','INVENTARIO_CONSULTAR']);assert.equal((await f.post('/clientes/1/nit',{})).status,403);assert.equal((await f.post('/clientes/1/inactivar',{})).status,403);assert.equal((await f.post('/inventario/movimientos',{TipoMovimiento:'AJUSTE_EGRESO'})).status,403);assert(!f.calls.some(c=>c[0]==='move'||c[0]==='client'));
});
test('Kenneth: conflicto y error SQL se presentan sin detalles privados',async t=>{
 const f=await fixture(t);for(const [number,status]of[[54103,409],[2627,400],[54101,403],[99999,503]]){
  f.services.productos.save=async()=>{throw Object.assign(new Error('password=privado SQL interno'),{number});};
  const r=await f.post('/productos',validProduct);assert.equal(r.status,status);assert.doesNotMatch(await r.text(),/password|privado|SQL interno/);
 }
 f.services.productos.list=async()=>{throw new Error('password=privado SQL interno');};const response=await f.request('/productos');assert.equal(response.status,503);const html=await response.text();assert.match(html,/No fue posible cargar la informaci/);assert.doesNotMatch(html,/password=|SQL interno/);
});
test('Kenneth: operación Kardex estable rechaza cambios en el reintento',async t=>{
 const f=await fixture(t);const html=await(await f.request('/inventario?id=1')).text();const op=html.match(/name="OperacionId" value="([a-f0-9-]+)"/)[1];const b={ProductoId:'1',Version:product.Version,TipoMovimiento:'COMPRA',ProveedorId:'1',Cantidad:'2',DocumentoRespaldo:'COMPRA-1',Motivo:'Ingreso',OperacionId:op};
 assert.equal((await f.post('/inventario/movimientos',b)).status,201);assert.equal((await f.post('/inventario/movimientos',b)).status,201);assert.equal((await f.post('/inventario/movimientos',{...b,Cantidad:'3'})).status,409);assert.equal(f.calls.filter(c=>c[0]==='receive').length,2);
});
test('Kenneth: fotografías reales, MIME, decodificación y cancelación segura',async t=>{
 const f=await fixture(t);const png=await sharp({create:{width:8,height:8,channels:3,background:'#445566'}}).png().toBuffer();
 const upload=async(body,type='image/png',name='photo.png')=>f.request('/productos/fotografias',{method:'POST',headers:{'Content-Type':type,'X-File-Name':name,'X-CSRF-Token':f.csrf},body});
 for(const [buffer,type,name]of[[Buffer.from('<svg></svg>'),'image/png','x.png'],[png,'image/jpeg','x.jpg'],[png.subarray(0,24),'image/png','x.png']])assert.equal((await upload(buffer,type,name)).status,400);
 const r=await upload(png);assert.equal(r.status,201);const photo=await r.json();assert.match(photo.url,/\/fotografias\/[a-f0-9-]{36}\.png$/);assert.equal((await f.request(photo.url)).status,200);
 assert.equal((await f.request('/productos/fotografias/'+photo.token,{method:'DELETE',headers:{'X-CSRF-Token':f.csrf}})).status,204);assert.equal((await f.request(photo.url)).status,404);
 assert.equal((await f.post('/productos',{...validProduct,UploadToken:photo.token})).status,400);
});
test('Kenneth: formatos, tamaño, ruta controlada y asociación de fotografía',async t=>{
 const f=await fixture(t);const png=await sharp({create:{width:2,height:2,channels:3,background:'#123456'}}).png().toBuffer();
 await assert.rejects(f.services.photos.read('../private'),/Referencia/);await assert.rejects(f.services.photos.upload(Buffer.alloc(3*1024*1024+1),'p.png','image/png'),/3 MB/);
 const uploaded=await f.request('/productos/fotografias',{method:'POST',headers:{'Content-Type':'image/png','X-File-Name':'../../photo.png','X-CSRF-Token':f.csrf},body:png});assert.equal(uploaded.status,201);const data=await uploaded.json();assert.equal((await f.post('/productos',{...validProduct,UploadToken:data.token})).status,201);assert.match(f.calls.find(c=>c[0]==='product-save')[2].Fotografia,/^[a-f0-9-]{36}\.png$/);
 assert.equal((await f.request('/productos/fotografias/'+data.token,{method:'DELETE',headers:{'X-CSRF-Token':f.csrf}})).status,204);assert.equal((await f.request(data.url)).status,200);
 const jpeg=await sharp(png).jpeg().toBuffer();const ref=await f.services.photos.upload(jpeg,'photo.jpeg','image/jpeg');assert.match(ref,/\.jpg$/);assert.equal((await sharp(await f.services.photos.read(ref)).metadata()).format,'jpeg');
});
test('Kenneth: servicios usan parámetros tipados y procedimientos reales',async()=>{
 const calls=[];const pool={request(){const values=[];return{input(...v){values.push(v);return this;},async execute(procedure){calls.push({procedure,values});return{recordset:[{Version:Buffer.from('0000000000000001','hex')}]};}};}};
 const provider=async()=>pool;
 const ps=createProductoService(provider),ss=createProveedorService(provider),cs=createClienteService(provider),is=createInventarioService(provider);
 assert.equal((await ps.list(42,{buscar:"'; DROP TABLE Producto;--"}))[0].Version,product.Version);
 await ps.save(42,validProduct);await ss.list(42);await ss.save(42,{NIT:'T1',Nombre:'Proveedor'});await cs.list(42);await cs.update(42,{id:1,Version:product.Version,Motivo:'Solicitud'},true);await is.state(42);await is.history(42,{id:1,hasta:'2026-10-18'});await is.move(42,{id:1,Version:product.Version,TipoMovimiento:'AJUSTE_INGRESO',Cantidad:1,OperacionId:'11111111-1111-4111-8111-111111111111'});
 assert.equal(calls.length,9);assert(calls.every(c=>c.procedure.startsWith('dbo.sp_')&&c.values[0][0]==='ActorUsuarioId'&&c.values[0][2]===42));assert.equal(calls[0].values[1][2],"'; DROP TABLE Producto;--");assert(calls.some(c=>c.procedure==='dbo.sp_ERP_RegistrarAjuste'));assert(calls.some(c=>c.procedure==='dbo.sp_InactivarCliente'));
});
test('Kenneth: fechas reales y búsqueda no escalar rechazadas',()=>{for(const q of[{buscar:[]},{desde:'2026-02-30'},{desde:'2026-10-20',hasta:'2026-10-01'},{offset:'-1'}])assert.throws(()=>validation.filters(q));});

test('Kenneth: alta y edicion de clientes con actor de sesion, sin cambio fiscal general',async t=>{
 const f=await fixture(t),contact={NIT:'9876-k',Nombre:'Cliente',Correo:'persona@example.invalid',Telefono:'+502 5555-0101',UsuarioId:999};
 assert.equal((await f.post('/clientes',contact)).status,201);
 assert.equal((await f.post('/clientes/1/datos',{...contact,NIT:'INJECT',ClienteId:8,Version:product.Version})).status,200);
 const calls=f.calls.filter(c=>c[0]==='client-save');assert.equal(calls[0][1],42);assert.equal(calls[0][2].NIT,'9876K');assert.equal(calls[1][2].NIT,undefined);assert.equal(calls[1][2].id,1);assert.equal(calls[1][2].UsuarioId,undefined);
 for(const patch of [{Nombre:''},{Correo:'invalido'},{Telefono:'abcdef'},{Telefono:'++'},{Nombre:'x'.repeat(151)}])assert.equal((await f.post('/clientes',{...contact,...patch})).status,400);
 assert.equal((await f.post('/clientes/1/datos',{...contact,Version:'obsoleta'})).status,400);
 assert.equal((await f.post('/clientes',contact,'bad')).status,403);
});
test('Kenneth: permisos de alta y edicion separados de consulta e identidad fiscal',async t=>{
 const f=await fixture(t,['PRODUCTOS_CONSULTAR','CLIENTES_CONSULTAR','CLIENTES_ACTUALIZAR_NIT']);
 assert.equal((await f.post('/clientes',{})).status,403);assert.equal((await f.post('/clientes/1/datos',{})).status,403);
 const html=await(await f.request('/clientes')).text();assert.doesNotMatch(html,/Nuevo cliente|Editar datos/);assert.match(html,/Cambiar NIT/);
});
test('Kenneth: proveedor vacio, drawer y producto sin proveedores activos',async t=>{
 const f=await fixture(t);f.services.proveedores.list=async()=>[];
 let html=await(await f.request('/proveedores')).text();assert.match(html,/Aún no hay proveedores registrados/);assert.match(html,/Registrar primer proveedor/);assert.doesNotMatch(html,/Sin proveedores coincidentes/);
 html=await(await f.request('/proveedores?buscar=otro')).text();assert.match(html,/Sin proveedores coincidentes/);
 html=await(await f.request('/proveedores?nuevo=1')).text();assert.match(html,/master-drawer/);assert.match(html,/action="\/proveedores"/);
 html=await(await f.request('/productos?nuevo=1')).text();assert.match(html,/No hay proveedores activos/);assert.match(html,/data-requires-supplier disabled/);assert.doesNotMatch(html,/name="Stock"/);
});
test('Kenneth: tabla de productos oculta costo sin permiso y Kardex muestra ocho columnas',async t=>{
 const f=await fixture(t,['PRODUCTOS_CONSULTAR','INVENTARIO_CONSULTAR']);
 const html=await(await f.request('/productos?vista=tabla')).text();assert.match(html,/Catálogo empresarial/);assert.doesNotMatch(html,/Costo Q/);assert.match(html,/Venta Q/);
 const inv=await(await f.request('/inventario')).text();for(const title of ['Fecha UTC','Movimiento','Documento','Actor','Ingreso','Egreso','Anterior','Resultante'])assert(inv.includes('>'+title+'</th>'));
 assert.match(inv,/UTC\+00:00/);
});
test('Kenneth: servicio de clientes parametriza alta y edicion sin enviar NIT en edicion',async()=>{
 const calls=[],provider=async()=>({request(){const values=[];return{input(...v){values.push(v);return this;},async execute(procedure){calls.push({procedure,values});return{recordset:[]};}};}});
 const service=createClienteService(provider),contact={Nombre:'Cliente',NIT:'123K',Correo:null,Telefono:null};await service.save(42,contact);await service.save(42,{...contact,id:1,Version:product.Version});
 assert.equal(calls[0].procedure,'dbo.sp_RegistrarCliente');assert.equal(calls[1].procedure,'dbo.sp_ActualizarDatosCliente');assert.equal(calls[0].values[0][2],42);assert(!calls[1].values.some(v=>v[0]==='NIT'));
});
