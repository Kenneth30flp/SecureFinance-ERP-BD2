'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {once}=require('node:events');
const {randomUUID}=require('node:crypto');
const v=require('../src/modules/cotizaciones/validation');
const {createCotizacionService}=require('../src/modules/cotizaciones/service');
const {createApp}=require('../server');
const permissions=['COTIZACIONES_CONSULTAR','COTIZACIONES_CREAR','COTIZACIONES_CANCELAR','COTIZACIONES_CONVERTIR'];
const valid=()=>({ClienteId:1,OperacionId:randomUUID(),Vencimiento:'2026-11-01',Observaciones:'Prueba',Detalle:[{ProductoId:2,Cantidad:2,DescuentoPorcentaje:'10.25',PrecioUnitario:1}]});
test('Cotizaciones: validacion estricta, varios productos, UTC Guatemala y precios nunca aceptados',()=>{
 const d=v.creation({...valid(),UsuarioId:999});assert.equal(d.VenceEn.toISOString(),'2026-11-02T06:00:00.000Z');assert.deepEqual(d.Detalle,[{ProductoId:2,Cantidad:2,DescuentoPorcentaje:10.25}]);assert.equal(d.UsuarioId,undefined);
 assert.equal(v.creation({...valid(),Detalle:[{ProductoId:1,Cantidad:1},{ProductoId:2,Cantidad:3}]}).Detalle.length,2);
 assert.throws(()=>v.integer([1]),v.ValidationError);
 for(const change of [{ClienteId:0},{Vencimiento:''},{Vencimiento:'2026-02-30'},{Detalle:[]},{Detalle:[{ProductoId:0,Cantidad:1}]},{Detalle:[{ProductoId:1,Cantidad:0}]},{Detalle:[{ProductoId:1,Cantidad:1.2}]},{Detalle:[{ProductoId:1,Cantidad:1,DescuentoPorcentaje:101}]},{Detalle:[{ProductoId:1,Cantidad:1},{ProductoId:1,Cantidad:2}]},{Observaciones:'a'.repeat(1001)},{OperacionId:'invalid'}])assert.throws(()=>v.creation({...valid(),...change}),v.ValidationError);
});
test('Cotizaciones: filtros conservan limites exclusivos y rechazan entradas invalidas',()=>{
 const f=v.filters({numero:'COT-12',estado:'VENCIDA',desde:'2026-10-01',hasta:'2026-10-02',pagina:'2'});assert.equal(f.Desde.toISOString(),'2026-10-01T06:00:00.000Z');assert.equal(f.Hasta.toISOString(),'2026-10-03T06:00:00.000Z');
 for(const q of [{numero:'1; DROP TABLE'},{estado:'OTRO'},{desde:'2026-11-02',hasta:'2026-11-01'},{pagina:0},{pagina:100002},{desde:['2026-10-01']}])assert.throws(()=>v.filters(q));
});
test('Cotizaciones: servicio tipado usa TVP existente y actor separado sin precios web',async()=>{
 const calls=[],requests=[];const provider=async()=>({request:()=>{const p=[];requests.push(p);return {input(...a){p.push(a);return this;},async execute(name){calls.push(name);return {recordsets:[[{CotizacionId:1}],[],[]]};}};}});
 const s=createCotizacionService(provider),d=v.creation(valid());await s.create(42,d);const tvp=requests[0].find(p=>p[0]==='Detalle');assert.equal(tvp.length,2);assert.deepEqual(tvp[1].rows[0],[2,2,10.25]);assert.equal(tvp[1].columns.length,3);assert.equal(requests[0][0][2],42);
 await s.list(42,v.filters({cliente:"a' OR 1=1 --"}));await s.detail(42,1);await s.cancel(42,1,randomUUID(),'Motivo');assert.deepEqual(calls,['dbo.P3_COT_Crear','dbo.P3_COT_Consultar','dbo.P3_COT_Consultar','dbo.P3_COT_Cancelar']);
});
const doc={CotizacionId:1,Numero:'COT-1',Estado:'ACTIVA',ClienteNombre:'Cliente <script>bad</script>',ClienteNIT:'QA',Responsable:'QA',FechaCreacion:new Date(),VenceEn:new Date(),Subtotal:'200.00',Descuento:'0.00',SubtotalNeto:'200.00',IVA:'24.00',Total:'224.00',OperacionId:randomUUID()};
async function fixture(t,permisos=permissions){
 const calls=[],service={list:async(a,f)=>{calls.push(['list',a,f]);return [doc];},catalogs:async()=>({clientes:[{ClienteId:1,Nombre:'QA',NIT:'QA'}],productos:[{ProductoId:2,Codigo:'SKU',Descripcion:'Producto',Precio:'100.00',Stock:0}],politica:{MaxDescuento:10}}),create:async(a,d)=>{calls.push(['create',a,d]);return doc;},detail:async()=>({documento:doc,lineas:[],historial:[]}),cancel:async(...args)=>{calls.push(['cancel',...args]);return {...doc,Estado:'CANCELADA'};}};
 const app=createApp({secret:'cotizaciones-unit-test-secret-32-characters',production:false,cotizacionService:service,authService:{login:async()=>({codigo:0,usuario:{usuarioId:42,nombreUsuario:'QA',permisos,debeCambiarPassword:false}})}});
 const server=app.listen(0,'127.0.0.1');await once(server,'listening');t.after(()=>new Promise(r=>{server.close(r);server.closeAllConnections();}));const base='http://127.0.0.1:'+server.address().port;
 const login=await fetch(base+'/login',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'NombreUsuario=QA&Password=fixture',redirect:'manual'});const cookie=login.headers.get('set-cookie').split(';')[0];
 const request=(url,options={})=>fetch(base+url,{redirect:'manual',...options,headers:{Cookie:cookie,...options.headers}});
 const post=(url,body,csrf)=>request(url,{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':csrf||''},body:JSON.stringify(body)});
 return {base,request,post,calls,service};
}
test('Cotizaciones HTTP: navegacion, historial, detalle imprimible y escape',async t=>{
 const f=await fixture(t);for(const route of ['/cotizaciones','/cotizaciones/nueva','/cotizaciones/1']){const r=await f.request(route);assert.equal(r.status,200);const html=await r.text();assert.match(html,/Cotizaciones/);assert.doesNotMatch(html,/<script>bad<\/script>/);if(route==='/cotizaciones/1'){assert.match(html,/cot-print/);assert.match(html,/pendiente de aprobación/);assert.doesNotMatch(html,/id="cot-convert"/);}}
 assert.equal((await fetch(f.base+'/cotizaciones',{redirect:'manual'})).status,302);
});
test('Cotizaciones HTTP: RBAC y CSRF rechazan solicitudes manuales antes del servicio',async t=>{
 const f=await fixture(t,[]);for(const route of ['/cotizaciones','/cotizaciones/nueva','/cotizaciones/1'])assert.equal((await f.request(route)).status,403);
 assert.equal((await f.post('/cotizaciones',valid())).status,403);assert.equal((await f.post('/cotizaciones/1/cancelar',{})).status,403);assert.equal((await f.post('/cotizaciones/1/convertir',{})).status,404);assert(!f.calls.some(c=>c[0]==='create'));
 const g=await fixture(t);assert.equal((await g.post('/cotizaciones',valid(),'bad')).status,403);assert.equal((await g.post('/cotizaciones',valid(),'a'.repeat(64))).status,403);
});
test('Cotizaciones HTTP: creacion utiliza actor de sesion, referencia estable y mensajes SQL seguros',async t=>{
 const f=await fixture(t),html=await(await f.request('/cotizaciones/nueva')).text(),csrf=html.match(/name="csrf-token" content="([a-f0-9]+)"/)[1],b={...valid(),ActorUsuarioId:999};
 const r=await f.post('/cotizaciones',b,csrf);assert.equal(r.status,201);assert.equal((await r.json()).url,'/cotizaciones/1');const c=f.calls.find(c=>c[0]==='create');assert.equal(c[1],42);assert.equal(c[2].OperacionId,b.OperacionId);assert.equal(c[2].Detalle[0].PrecioUnitario,undefined);
 for(const [number,status] of [[54903,409],[54904,404],[54101,403],[54902,400],[12345,503]]){f.service.create=async()=>{throw Object.assign(Error('password SECRET'),{number});};const e=await f.post('/cotizaciones',b,csrf);assert.equal(e.status,status);assert.doesNotMatch(await e.text(),/SECRET/);}
});
test('Cotizaciones HTTP: cancelacion exige motivo y devuelve estado real del servicio',async t=>{
 const f=await fixture(t),html=await(await f.request('/cotizaciones/1')).text(),csrf=html.match(/name="csrf-token" content="([a-f0-9]+)"/)[1],operation=randomUUID();assert.equal((await f.post('/cotizaciones/1/cancelar',{Motivo:'',OperacionId:operation},csrf)).status,400);
 const r=await f.post('/cotizaciones/1/cancelar',{Motivo:'Cliente solicita',OperacionId:operation},csrf);assert.equal(r.status,200);assert.equal((await r.json()).documento.Estado,'CANCELADA');assert.equal(f.calls.find(c=>c[0]==='cancel')[1],42);
});
