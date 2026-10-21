'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {once}=require('node:events');
const {randomUUID}=require('node:crypto');
const {createApp}=require('../server');
const v=require('../src/modules/edward/validations');
const {createEdwardService}=require('../src/modules/edward/services');
test('Edward validation rejects invalid quantities, duplicates, forged conditions and versions',()=>{
 const valid={FacturaId:1,OperacionId:randomUUID(),Motivo:'Falla',Detalles:[{DetalleFacturaId:2,Cantidad:1,Reingresar:false}]};
 assert.equal(v.devolucion(valid).Detalles[0].Cantidad,1);
 for(const Cantidad of [0,-1,1.5,'1e2',2147483648])assert.throws(()=>v.devolucion({...valid,Detalles:[{...valid.Detalles[0],Cantidad}]}));
 assert.throws(()=>v.devolucion({...valid,Detalles:[...valid.Detalles,...valid.Detalles]}));
 assert.throws(()=>v.devolucion({...valid,Detalles:[{...valid.Detalles[0],Reingresar:'false'}]}));
 assert.throws(()=>v.version('bad'));
 assert.throws(()=>v.filters({desde:'2026-02-30'}));
 assert.throws(()=>v.filters({desde:'2026-10-20',hasta:'2026-01-01'}));
 assert.throws(()=>v.state('CERRADO'));
});
test('Edward service uses typed SQL parameters, session actor and separate recordsets',async()=>{
 let call;
 const service=createEdwardService(async()=>({request(){return {params:[],input(...p){this.params.push(p);return this;},async execute(proc){call={proc,params:this.params};return {recordsets:[[{TicketId:1,Version:Buffer.from('0000000000000001','hex')}],[{Diagnostico:'Anterior'}]]};}};}}));
 const result=await service.garantias(9,{});
 assert.equal(call.proc,'dbo.sp_Edward_ConsultarGarantias');
 assert.equal(call.params[0][0],'ActorUsuarioId');assert.equal(call.params[0][2],9);
 assert.equal(result[0][0].Version,'0000000000000001');assert.equal(result[1][0].Diagnostico,'Anterior');
});
const permissions=['DEVOLUCIONES_CONSULTAR','DEVOLUCIONES_REGISTRAR','DEVOLUCIONES_AUTORIZAR','GARANTIAS_CONSULTAR','GARANTIAS_GESTIONAR','INVENTARIO_REGISTRAR'];
test('Edward HTTP: sessions, RBAC, CSRF, escaped views, returns and warranty conflict',async t=>{
 let writes=0,lastActor,failConflict=false;
 const service={
 devoluciones:async()=>[[],[]],garantias:async()=>[[],[]],
 factura:async(a,id)=>id===1?[[{FacturaId:1,Cliente:'<script>alert(1)</script>',Total:'12.00'}],[{DetalleFacturaId:3,Descripcion:'Producto',Cantidad:2,Devuelto:0,Disponible:2,PrecioUnitario:'6.00'}]]:[[],[]],
 devolver:async(a,b)=>{writes++;lastActor=a;assert.equal(b.Detalles[0].Cantidad,1);return {DevolucionId:7};},
 crear:async()=>({TicketId:8}),
 actualizar:async()=>{if(failConflict)throw Object.assign(new Error('stale'),{number:54603});return {TicketId:8};}
 };
 const app=createApp({secret:'edward-tests-only-session-secret-123456',production:false,edwardService:service,
 authService:{login:async name=>({codigo:0,usuario:{usuarioId:9,nombreUsuario:name,permisos:name==='lector'?['DEVOLUCIONES_CONSULTAR']:permissions,debeCambiarPassword:name==='cambio'}})}});
 const server=app.listen(0,'127.0.0.1');await once(server,'listening');t.after(()=>new Promise(r=>{server.close(r);server.closeAllConnections();}));
 const base='http://127.0.0.1:'+server.address().port;
 let cookie='';
 const request=(route,opts={})=>fetch(base+route,{redirect:'manual',...opts,headers:{cookie,...opts.headers}});
 const login=async name=>{if(cookie){await request('/logout');cookie='';}const r=await request('/login',{method:'POST',body:new URLSearchParams({NombreUsuario:name,Password:'test'})});cookie=r.headers.get('set-cookie').split(';')[0];};
 for(const route of ['/devoluciones','/notas-credito','/garantias'])assert.equal((await request(route)).status,302);
 await login('admin');
 let r=await request('/devoluciones?factura=1');assert.equal(r.status,200);const html=await r.text();
 assert.ok(html.includes('&lt;script&gt;alert(1)&lt;/script&gt;'));assert.ok(!html.includes('<script>alert(1)</script>'));
 const token=html.match(/name="csrf-token" content="([a-f0-9]+)"/)[1];
 const body={FacturaId:1,OperacionId:randomUUID(),Motivo:'Falla',ActorUsuarioId:999,Detalles:[{DetalleFacturaId:3,Cantidad:1,Reingresar:false}]};
 const post=(url,b,csrf=token)=>request(url,{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':csrf},body:JSON.stringify(b)});
 assert.equal((await post('/devoluciones',body,'bad')).status,403);assert.equal(writes,0);
 assert.equal((await post('/devoluciones',{...body,Detalles:[{DetalleFacturaId:3,Cantidad:0,Reingresar:false}]})).status,400);
 r=await post('/devoluciones',body);assert.equal(r.status,201);assert.equal((await r.json()).url,'/notas-credito?id=7');assert.equal(lastActor,9);
 r=await request('/devoluciones?factura=999');assert.match(await r.text(),/Factura no encontrada/);
 assert.equal((await post('/garantias',{DetalleFacturaId:3,OperacionId:randomUUID(),Motivo:'Falla'})).status,201);
 assert.equal((await post('/garantias/8/estado',{Version:'0000000000000001',Estado:'EN_REVISION',Diagnostico:'Revision'},'bad')).status,403);
 failConflict=true;
 assert.equal((await post('/garantias/8/estado',{Version:'0000000000000001',Estado:'EN_REVISION',Diagnostico:'Revision'})).status,409);
 await login('lector');
 assert.equal((await request('/garantias')).status,403);assert.equal((await post('/devoluciones',body)).status,403);
 await login('cambio');assert.equal((await request('/devoluciones')).headers.get('location'),'/cambiar-password');
});
