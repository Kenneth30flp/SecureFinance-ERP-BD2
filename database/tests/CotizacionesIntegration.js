'use strict';
// REAL SQL: only the isolated lab written by PrepareCotizacionesLab.ps1.
require('dotenv').config({quiet:true});
const fs=require('node:fs');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const state=JSON.parse(fs.readFileSync('.data/cotizaciones-lab.json','utf8').replace(/^\uFEFF/,''));
assert.match(state.lab,/^SecureFinanceERP_P3_COT_\d{14}_[a-f0-9]{8}$/);
process.env.DB_NAME=state.lab;
const {getPool,closePool,sql}=require('../../src/config/database');
const {createCotizacionService}=require('../../src/modules/cotizaciones/service');
const {createProductoService}=require('../../src/services/productoService');
const {createProveedorService}=require('../../src/services/proveedorService');
const {createClienteService}=require('../../src/services/clienteService');
const service=createCotizacionService(),actor=state.actor,results=[];
const pass=name=>{results.push(name);console.log('PASS SQL '+name);};
async function reject(fn,number){await assert.rejects(fn,e=>e.number===number);}
async function run(){
 try{
  const pool=await getPool();const identity=(await pool.request().query('SELECT DB_NAME() N')).recordset[0].N;assert.equal(identity,state.lab);
  const suppliers=await createProveedorService().list(actor,{}),supplier=suppliers.find(s=>s.Activo);assert.ok(supplier);
  const products=createProductoService();
  const product=(await products.save(actor,{CodigoAutomatico:true,Codigo:null,Descripcion:'QA COTIZACION '+randomUUID(),Precio:'100.00',PrecioCosto:'40.00',ProveedorId:supplier.ProveedorId,StockMinimo:1,PuntoReorden:2,GarantiaMeses:0,Fotografia:null}))[0];
  const customers=createClienteService();
  const client=(await customers.save(actor,{NIT:'QACOT'+Date.now(),Nombre:'Cliente QA Cotizaciones - Laboratorio',Correo:null,Telefono:null}))[0];assert.ok(client);
  let catalogs=await service.catalogs(actor);
  const p=catalogs.productos.find(p=>p.ProductoId===product.ProductoId);assert.ok(p);assert.equal(p.Precio,'100.00');assert.equal(p.Stock,0);
  const stockBefore=catalogs.productos.map(p=>[p.ProductoId,p.Stock]);
  const data=()=>({ClienteId:client.ClienteId,VenceEn:new Date(Date.now()+86400000),OperacionId:randomUUID(),Observaciones:'QA exclusiva de laboratorio',Detalle:[{ProductoId:p.ProductoId,Cantidad:2,DescuentoPorcentaje:10}]});
  const d=data(),quote=await service.create(actor,d),detail=await service.detail(actor,quote.CotizacionId);
  assert.equal(detail.documento.Subtotal,'200.00');assert.equal(detail.documento.Descuento,'20.00');assert.equal(detail.documento.IVA,'21.60');assert.equal(detail.documento.Total,'201.60');assert.equal(detail.lineas[0].PrecioUnitario,'100.00');assert.equal(detail.historial.length,1);pass('creacion valida, precio SQL y totales DECIMAL');
  assert.deepEqual((await service.catalogs(actor)).productos.map(p=>[p.ProductoId,p.Stock]),stockBefore);pass('emision no modifica stock (producto propio sin existencias)');
  const retry=await service.create(actor,d);assert.equal(retry.CotizacionId,quote.CotizacionId);await reject(()=>service.create(actor,{...d,Observaciones:'cambio'}),54903);pass('reintento identico y conflicto por referencia reutilizada');
  const identical=data(),simultaneous=await Promise.all([service.create(actor,identical),service.create(actor,identical)]);assert.equal(simultaneous[0].CotizacionId,simultaneous[1].CotizacionId);pass('dos emisiones simultaneas con la misma referencia: un documento');
  const p2=catalogs.productos.find(x=>x.ProductoId!==p.ProductoId);assert.ok(p2);
  const multi=await service.create(actor,{...data(),Detalle:[{ProductoId:p.ProductoId,Cantidad:1,DescuentoPorcentaje:0},{ProductoId:p2.ProductoId,Cantidad:3,DescuentoPorcentaje:0}]});assert.equal((await service.detail(actor,multi.CotizacionId)).lineas.length,2);pass('cotizacion de varios productos');
  const source=(await products.list(actor,{id:p.ProductoId,costo:true}))[0];
  await products.save(actor,{...source,id:source.ProductoId,Precio:'120.00',Fotografia:null});
  assert.equal((await service.detail(actor,quote.CotizacionId)).lineas[0].PrecioUnitario,'100.00');assert.equal((await service.catalogs(actor)).productos.find(x=>x.ProductoId===p.ProductoId).Precio,'120.00');pass('snapshot cotizacion 100 permanece tras cambiar catalogo a 120 (conversion pendiente)');
  const f={numero:quote.Numero,cliente:client.Nombre,estado:'ACTIVA',pagina:1};const found=await service.list(actor,f);assert.equal(found.length,1);assert.equal(found[0].CotizacionId,quote.CotizacionId);pass('historial y filtros por numero, cliente y estado');
  await reject(()=>service.create(actor,{...data(),ClienteId:2147483647}),54904);
  await reject(()=>service.create(actor,{...data(),Detalle:[{ProductoId:2147483647,Cantidad:1,DescuentoPorcentaje:0}]}),54904);
  await reject(()=>service.create(actor,{...data(),Detalle:[]}),54902);
  await reject(()=>service.create(actor,{...data(),Detalle:[{ProductoId:p.ProductoId,Cantidad:0,DescuentoPorcentaje:0}]}),54902);
  await reject(()=>service.create(actor,{...data(),VenceEn:new Date(Date.now()-86400000)}),54902);
  await reject(()=>service.create(actor,{...data(),VenceEn:new Date(Date.now()+91*86400000)}),54902);
  await reject(()=>service.create(-1,data()),54101);pass('rechazos SQL: cliente/producto inexistente, sin lineas, cantidad, vigencia y RBAC');
  const inactive=(await customers.save(actor,{NIT:'QAINA'+Date.now(),Nombre:'Cliente QA Inactivo Cotizaciones',Correo:null,Telefono:null}))[0];
  await customers.update(actor,{id:inactive.ClienteId,Version:inactive.Version,Motivo:'QA aislamiento cliente inactivo'},true);
  await reject(()=>service.create(actor,{...data(),ClienteId:inactive.ClienteId}),54904);pass('cliente inactivo rechazado por SQL');
  await assert.rejects(()=>pool.request().query('SELECT TOP(1) * FROM dbo.P3_COT_Cotizacion'),e=>e.number===229);pass('cuenta de aplicacion sin SELECT directo sobre documentos');
  const bad=data();bad.Detalle.push({ProductoId:2147483647,Cantidad:1,DescuentoPorcentaje:0});await reject(()=>service.create(actor,bad),54904);
  assert.equal((await service.list(actor,{cliente:'',estado:'',numero:'',pagina:1})).filter(q=>q.OperacionId===bad.OperacionId).length,0);pass('rollback de emision con error en producto posterior');
  const op=randomUUID();await service.cancel(actor,quote.CotizacionId,op,'QA cancelacion');await service.cancel(actor,quote.CotizacionId,op,'QA cancelacion');
  const cancelled=await service.detail(actor,quote.CotizacionId);assert.equal(cancelled.documento.Estado,'CANCELADA');assert.equal(cancelled.historial.length,2);await reject(()=>service.cancel(actor,quote.CotizacionId,randomUUID(),'otra'),54903);pass('cancelacion auditada, idempotente y sin transicion repetida');
  const expiry=await service.create(actor,{...data(),VenceEn:new Date(Date.now()+1500)});await new Promise(r=>setTimeout(r,1700));const expired=await service.detail(actor,expiry.CotizacionId);assert.equal(expired.documento.Estado,'VENCIDA');assert.equal(expired.historial.length,1);assert.equal((await service.detail(actor,expiry.CotizacionId)).documento.Estado,'VENCIDA');await reject(()=>service.cancel(actor,expiry.CotizacionId,randomUUID(),'no vigente'),54903);pass('TVF expira con reloj SQL sin modificar historial');
  for(let i=0;i<21;i++)await service.create(actor,data());
  const page1=await service.list(actor,{cliente:client.NIT,pagina:1}),page2=await service.list(actor,{cliente:client.NIT,pagina:2});
  assert.equal(page1.length,21);assert.ok(page2.length>0);assert.equal(page1[20].CotizacionId,page2[0].CotizacionId);assert(!page1.slice(0,20).some(q=>page2.some(r=>r.CotizacionId===q.CotizacionId)));pass('paginacion SQL de 20 filas y una adicional sin duplicados entre paginas');
  // Dedicated records for real browser capture, without changing the principal.
  const browserQuote=await service.create(actor,{...data(),Detalle:[{ProductoId:p.ProductoId,Cantidad:2,DescuentoPorcentaje:0}],Observaciones:'QA navegador real SQL - no es documento operativo'});
  fs.writeFileSync('.data/cotizaciones-sql.json',JSON.stringify({lab:state.lab,actor,productId:p.ProductoId,clientId:client.ClienteId,browserQuote:browserQuote.CotizacionId,passed:results,conversion:'NOT_IMPLEMENTED_PENDING_CONTRACT_APPROVAL'},null,2));
 } finally{await closePool();}
}
run().catch(e=>{console.error('SQL FAIL',e.number||e.code||e.name,e.number?e.message:'');process.exitCode=1;});
