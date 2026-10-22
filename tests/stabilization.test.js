'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {once}=require('node:events');
const {randomUUID}=require('node:crypto');
const {createApp}=require('../server');
const {createInventarioService}=require('../src/services/inventarioService');
const {createEdwardService}=require('../src/modules/edward/services');
async function fixture(t,write=true){
 const calls=[];
 const perms=['DEVOLUCIONES_CONSULTAR',...(write?['NOTAS_CREDITO_APLICAR']:[])];
 const service={devoluciones:async()=>[[{DevolucionId:4,NotaCreditoId:7,FacturaId:2,Cliente:'QA',FechaHora:new Date(),Estado:'EMITIDA',EstadoCredito:'PARCIAL',Total:'100.00',Subtotal:'100.00',Descuento:'0.00',IVA:'0.00'}],[]],aplicaciones:async()=>[[{SaldoDisponible:'50.00',EstadoCredito:'PARCIAL'}],[{Monto:'50.00',SaldoPrevio:'100.00',SaldoFinal:'50.00',FechaHora:new Date(),ReferenciaDocumental:'COMPROBANTE-EXTERNO',Responsable:'QA',OperacionId:randomUUID()}]],aplicar:async(a,b)=>{calls.push([a,b]);return {AplicacionId:1};}};
 const app=createApp({secret:'stabilization-unit-session-32-characters',edwardService:service,authService:{login:async()=>({codigo:0,usuario:{usuarioId:42,nombreUsuario:'QA',permisos:perms}})}});
 const server=app.listen(0,'127.0.0.1');await once(server,'listening');t.after(()=>new Promise(resolve=>{server.close(resolve);server.closeAllConnections();}));
 const base='http://127.0.0.1:'+server.address().port;
 const login=await fetch(base+'/login',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'NombreUsuario=qa&Password=qa',redirect:'manual'});
 const cookie=login.headers.get('set-cookie').split(';')[0];
 const page=await fetch(base+'/notas-credito?id=4',{headers:{Cookie:cookie}});assert.equal(page.status,200);
 const html=await page.text();const csrf=html.match(/name="csrf-token" content="([a-f0-9]+)"/)[1];
 const post=(body,token=csrf)=>fetch(base+'/notas-credito/7/aplicaciones',{method:'POST',headers:{Cookie:cookie,'X-CSRF-Token':token,'Content-Type':'application/json'},body:JSON.stringify(body)});
 return {calls,service,html,post};
}
test('Crédito: saldo e historial reales del servicio, formulario autorizado y actor de sesión',async t=>{
 const f=await fixture(t);assert.match(f.html,/Saldo disponible: Q 50.00/);assert.match(f.html,/COMPROBANTE-EXTERNO/);assert.match(f.html,/no ejecuta transferencias bancarias/);
 const b={Monto:'25.00',ReferenciaDocumental:'EXT-123',OperacionId:randomUUID(),DevolucionId:4,ActorUsuarioId:999};
 const r=await f.post(b);assert.equal(r.status,201);assert.deepEqual(await r.json(),{url:'/notas-credito?id=4'});assert.equal(f.calls[0][0],42);assert.equal(f.calls[0][1].NotaCreditoId,7);
});
test('Crédito: RBAC y CSRF rechazan antes del servicio; consulta no ofrece escritura',async t=>{
 const read=await fixture(t,false);assert.doesNotMatch(read.html,/action="\/notas-credito\/7\/aplicaciones"/);assert.equal((await read.post({})).status,403);assert.equal(read.calls.length,0);
 const write=await fixture(t);assert.equal((await write.post({},'0'.repeat(64))).status,403);assert.equal(write.calls.length,0);
});
test('Crédito: montos inválidos, referencia ausente y errores SQL seguros',async t=>{
 const f=await fixture(t);const b={Monto:'25.00',ReferenciaDocumental:'EXT-1',OperacionId:randomUUID(),DevolucionId:4};
 for(const Monto of ['0','-1','1.001','Infinity',25])assert.equal((await f.post({...b,Monto})).status,400);
 assert.equal((await f.post({...b,ReferenciaDocumental:''})).status,400);assert.equal(f.calls.length,0);
 f.service.aplicar=async()=>{throw Object.assign(Error('SQL password=private'),{number:54804});};
 const r=await f.post(b);assert.equal(r.status,400);assert.match((await r.json()).error,/saldo disponible/);
});
test('Servicios: recepción y crédito usan procedimientos, tipos y referencias sin SQL concatenado',async()=>{
 const calls=[];const provider=async()=>({request(){const inputs=[];return {input(...v){inputs.push(v);return this;},async execute(proc){calls.push({proc,inputs});return {recordset:[{}],recordsets:[[{}]]};}};}});
 const operation=randomUUID();
 await createInventarioService(provider).receive(42,{id:4,ProveedorId:2,Cantidad:10,DocumentoRespaldo:"'; DROP TABLE Producto;--",Motivo:'Compra documentada',OperacionId:operation,CostoUnitario:null});
 assert.equal(calls[0].proc,'dbo.sp_RegistrarRecepcionCompra');assert.equal(calls[0].inputs.find(i=>i[0]==='CostoUnitario')[2],null);assert.equal(calls[0].inputs.find(i=>i[0]==='OperacionId')[2],operation);
 await createEdwardService(provider).aplicar(42,{NotaCreditoId:7,Monto:'25.00',ReferenciaDocumental:'EXT-1',OperacionId:operation});
 assert.equal(calls[1].proc,'dbo.sp_RegistrarAplicacionNotaCredito');assert.equal(calls[1].inputs[0][2],42);
});
