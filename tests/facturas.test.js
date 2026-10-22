'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {once}=require('node:events');
const {createApp}=require('../server');
const {createFacturaService}=require('../src/services/facturaService');
const {filters}=require('../src/controllers/facturaController');
const invoice={FacturaId:6010,Cliente:'Consumidor <script>final</script>',NIT:'CF',Responsable:'operador',FechaHora:'2026-10-22T04:19:00Z',Subtotal:'107.70',Descuento:'26.93',SubtotalNeto:'80.77',IVA:'9.69',Total:'90.46',Estado:'EMITIDA',TotalFilas:41};
const line={DetalleFacturaId:6013,Codigo:'CABLE',Descripcion:'Cable HDMI',Cantidad:3,PrecioUnitario:'35.90',Subtotal:'107.70',DescuentoPorcentaje:'25.00',DescuentoMonto:'26.93',SubtotalNeto:'80.77',ReferenciaCatalogo:true};
async function fixture(t,permisos=['FACTURAS_CONSULTAR']){
 const calls=[];let error=null;
 const service={list:async(a,f)=>{calls.push(['list',a,f]);if(error)throw error;return f.numero===999?[]:[invoice];},detail:async(a,id)=>{calls.push(['detail',a,id]);if(error)throw error;return {factura:id===6010?invoice:null,detalle:[line]};}};
 const app=createApp({secret:'invoice-history-tests-session-secret-12345',production:false,facturaService:service,
  authService:{login:async()=>({codigo:0,usuario:{usuarioId:3,nombreUsuario:'QA',permisos,debeCambiarPassword:false}})},
  ventaService:{procesarVenta:async()=>{throw Error('History must never register a sale');}}});
 const server=app.listen(0,'127.0.0.1');await once(server,'listening');
 t.after(()=>new Promise(r=>{server.close(r);server.closeAllConnections();}));
 const base='http://127.0.0.1:'+server.address().port;let cookie='';
 const request=(route,options={})=>fetch(base+route,{redirect:'manual',...options,headers:{cookie,...options.headers}});
 return {calls,request,setError:e=>{error=e;},login:async()=>{const r=await request('/login',{method:'POST',body:new URLSearchParams({NombreUsuario:'QA',Password:'fixture'})});cookie=r.headers.get('set-cookie').split(';')[0];}};
}
test('Facturas: permiso independiente de auditoria y ventas, consulta sin alta y acceso anonimo denegado',async t=>{
 const f=await fixture(t);for(const route of ['/facturacion/historial','/facturacion/facturas/6010'])assert.equal((await f.request(route)).status,302);
 assert.equal(f.calls.length,0);await f.login();
 assert.equal((await f.request('/facturacion')).headers.get('location'),'/facturacion/historial');
 assert.equal((await f.request('/facturacion/historial')).status,200);
 assert.equal((await f.request('/facturacion/procesar',{method:'POST'})).status,403);
 const history=await(await f.request('/facturacion/historial')).text();assert.ok(!history.includes('href="/auditoria"'));
 assert.match(history,/Historial de facturas/);assert.doesNotMatch(history,/href="\/facturacion">Nueva venta/);
 for(const permisos of [['AUDITORIA_CONSULTAR'],['VENTAS_REGISTRAR'],[]]){
  const denied=await fixture(t,permisos);await denied.login();
  for(const route of ['/facturacion/historial','/facturacion/facturas/6010?imprimir=1'])assert.equal((await denied.request(route)).status,403);
  assert.equal(denied.calls.length,0);
 }
});
test('Facturas: filtros, paginacion, escape, datos persistidos y copia imprimible solo GET',async t=>{
 const f=await fixture(t,['FACTURAS_CONSULTAR','VENTAS_REGISTRAR']);await f.login();
 const response=await f.request('/facturacion/historial?numero=6010&cliente=CF&desde=2026-10-21&hasta=2026-10-21&pagina=2');assert.equal(response.status,200);
 const html=await response.text();assert.match(html,/Consumidor &lt;script&gt;final&lt;\/script&gt;/);assert.match(html,/21\/10\/2026, 22:19:00/);
 assert.match(html,/Anterior/);assert.match(html,/Siguiente/);assert.match(html,/cliente=CF/);
 assert.equal(f.calls[0][1],3);assert.equal(f.calls[0][2].pagina,2);
 for(const route of ['/facturacion/facturas/6010','/facturacion/facturas/6010?imprimir=1']){
  const copy=await f.request(route);assert.equal(copy.status,200);const text=await copy.text();
  for(const value of ['CABLE','Cable HDMI','35.90','26.93','9.69','Q 90.46','25.00','SAT/FEL','Imprimir copia','referencia del catálogo'])assert.ok(text.includes(value),value);
  assert.match(text,/>3<\/td>/);assert.doesNotMatch(text,/facturacion\.js|venta-form|<script>final/);
 }
 assert.equal((await f.request('/facturacion/facturas/999')).status,404);
 const empty=await(await f.request('/facturacion/historial?numero=999')).text();assert.match(empty,/No hay facturas para esta búsqueda/);
 assert.equal((await f.request('/facturacion/facturas/6010',{method:'POST'})).status,404);
});
test('Facturas: validacion y errores SQL seguros, revocacion efectiva reflejada',async t=>{
 const f=await fixture(t);await f.login();
 for(const query of ['numero=0','numero=2147483648','numero=6010 OR 1=1','pagina=1000001','cliente=a&cliente=b','desde=2026-02-30','desde=0000-01-01','hasta=9999-12-31','desde=2026-10-22&hasta=2026-10-21']){
  assert.equal((await f.request('/facturacion/historial?'+query)).status,400,query);
 }
 assert.equal(f.calls.length,0);
 for(const [number,status]of[[54101,403],[2812,503]]){f.setError(Object.assign(Error('SQL password secreto'),{number}));const r=await f.request('/facturacion/historial');assert.equal(r.status,status);assert.doesNotMatch(await r.text(),/SQL password|secreto|2812/);}
});
test('Facturas: parametros tipados y dias de Guatemala conservan importes SQL sin recalcular',async()=>{
 const calls=[];const provider=async()=>({request(){const params=[];return {input(...p){params.push(p);return this;},async execute(proc){calls.push({proc,params});return {recordset:[invoice],recordsets:[[invoice],[line]]};}};}});
 const service=createFacturaService(provider);const f=filters({numero:'6010',cliente:"CF'; DROP TABLE Factura;--",desde:'2026-10-21',hasta:'2026-10-21',pagina:'2'});
 assert.deepEqual(await service.list(3,f),[invoice]);const p=Object.fromEntries(calls[0].params.map(([name,type,value])=>[name,value]));
 assert.equal(p.Desde.toISOString(),'2026-10-21T06:00:00.000Z');assert.equal(p.Hasta.toISOString(),'2026-10-22T06:00:00.000Z');
 assert.equal(p.Desplazamiento,20);assert.equal(p.Limite,20);assert.equal(p.Cliente,f.cliente);
 assert.equal(calls[0].proc,'dbo.sp_ERP_ConsultarFacturas');
 assert.deepEqual(await service.detail(3,6010),{factura:invoice,detalle:[line]});assert.equal(calls[1].proc,'dbo.sp_ERP_ConsultarComprobante');
});
