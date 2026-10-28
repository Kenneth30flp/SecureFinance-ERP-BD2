'use strict';
require('dotenv').config({quiet:true});
const fs=require('node:fs');const assert=require('node:assert/strict');
const {execFile}=require('node:child_process');const {promisify}=require('node:util');
const state=JSON.parse(fs.readFileSync('.data/facturas39-deployment.json','utf8').replace(/^\uFEFF/,''));
const main=process.argv.includes('--main');assert.match(state.lab,/^SecureFinanceERP_Facturas_\d+$/);
process.env.DB_NAME=main?'SecureFinanceERP':state.lab;
const db=require('../../src/config/database');const service=require('../../src/services/facturaService').createFacturaService();
const run=promisify(execFile);
async function admin(query){const {stdout}=await run('sqlcmd',['-S','localhost','-E','-C','-b','-d',state.lab,'-h','-1','-y','8000','-w','65535','-Q','SET NOCOUNT ON; '+query],{windowsHide:true});return stdout.trim();}
async function checks(){
 const f={numero:null,cliente:'',desde:'',hasta:'',pagina:1};const rows=await service.list(3,f);assert.ok(rows.length>=15);
 const {factura,detalle}=await service.detail(3,6010);
 assert.equal(factura.FacturaId,6010);assert.equal(factura.Cliente,'Consumidor final DEMO');assert.equal(factura.NIT,'CF');
 assert.equal(factura.Subtotal,'107.70');assert.equal(factura.Descuento,'26.93');assert.equal(factura.IVA,'9.69');assert.equal(factura.Total,'90.46');
 assert.equal(detalle.length,1);assert.equal(detalle[0].Cantidad,3);assert.equal(detalle[0].Descripcion,'Cable HDMI');
 assert.equal(detalle[0].PrecioUnitario,'35.90');assert.equal(detalle[0].DescuentoPorcentaje,'25.00');assert.equal(detalle[0].SubtotalNeto,'80.77');
 assert.equal((await service.list(3,{...f,numero:6010,cliente:'CF',desde:'2026-10-21',hasta:'2026-10-21'}))[0].FacturaId,6010);
 assert.equal((await service.list(3,{...f,numero:2147483647})).length,0);
 for(const row of rows.slice(0,3)){const d=await service.detail(3,row.FacturaId);assert.equal(d.factura.Total,row.Total);assert.ok(d.detalle.length);}
 await assert.rejects(service.detail(1003,6010),e=>e.number===54101);
 const pool=await db.getPool();await assert.rejects(pool.request().query('SELECT TOP(1) * FROM dbo.Factura'),e=>e.number===229);
 console.log('PASS SQL real: #6010, otras facturas, filtros locales, RBAC y tablas denegadas ('+process.env.DB_NAME+')');
 if(main){
  assert.equal(Number(rows[0].TotalFilas),Number(state.baseline.Factura.split(':')[0]));
  const audit=await require('../../src/services/auditoriaService').createAuditoriaService().getHistoricoVentas();
  assert.equal(audit.length,Number(rows[0].TotalFilas));assert.ok(audit.some(r=>r.Factura===6010&&String(r.Total)==='90.46'));
  console.log('PASS principal de solo lectura: mismo total de facturas que Auditoria y #6010 intacta');return;
 }
 // The following writes are authorized ONLY in the name-guarded restored laboratory.
 const products=require('../../src/services/productoService').createProductoService();
 const suppliers=require('../../src/services/proveedorService').createProveedorService();
 const sales=require('../../src/services/ventaService').createVentaService();
 const inventory=require('../../src/services/inventarioService').createInventarioService();
 const supplier=(await suppliers.list(3,{})).find(s=>s.Activo);
 const client=(await sales.listarClientes())[0];
 let p=(await products.save(3,{Descripcion:'QA Archivo histórico',Precio:'10.00',PrecioCosto:'5.00',ProveedorId:supplier.ProveedorId,StockMinimo:1,PuntoReorden:2,GarantiaMeses:6}))[0];
 const code=p.Codigo;await inventory.receive(3,{id:p.ProductoId,ProveedorId:supplier.ProveedorId,Cantidad:20,DocumentoRespaldo:'LAB-ARCHIVO',Motivo:'QA copia aislada',OperacionId:require('node:crypto').randomUUID()});
 const operation=require('node:crypto').randomUUID();const line=[{ProductoId:p.ProductoId,Cantidad:1,DescuentoPorcentaje:10}];
 const invoice=await sales.procesarVenta(client.ClienteId,3,line,'Otro',operation);
 const retry=await sales.procesarVenta(client.ClienteId,3,line,'Otro',operation);assert.equal(retry.FacturaId,invoice.FacturaId);
 const original=await service.detail(3,invoice.FacturaId);assert.equal(original.detalle[0].ReferenciaCatalogo,false);
 p=(await products.list(3,{id:p.ProductoId,costo:true}))[0];
 await products.save(3,{...p,id:p.ProductoId,Codigo:'QA-REFERENCIA-'+Date.now(),Descripcion:'Nombre actual diferente',Precio:'999.99'});
 const preserved=await service.detail(3,invoice.FacturaId);
 assert.equal(preserved.detalle[0].Codigo,code);assert.equal(preserved.detalle[0].Descripcion,'QA Archivo histórico');
 assert.equal(preserved.detalle[0].PrecioUnitario,'10.00');assert.equal(preserved.factura.Total,original.factura.Total);
 for(let i=0;i<5;i++)await sales.procesarVenta(client.ClienteId,3,line,'Otro');
 const first=await service.list(3,f),second=await service.list(3,{...f,pagina:2});
 assert.equal(first.length,20);assert.ok(second.length);assert.ok(!second.some(b=>first.some(a=>a.FacturaId===b.FacturaId)));
 const before=await admin("SELECT (SELECT COUNT_BIG(*) FROM dbo.Factura) F,(SELECT SUM(CONVERT(bigint,Stock)) FROM dbo.Producto) S,(SELECT COUNT_BIG(*) FROM dbo.MovimientoCaja) C,(SELECT COUNT_BIG(*) FROM dbo.Kardex_Inventario) K FOR JSON PATH");
 await service.detail(3,6010);await service.detail(3,6010);await service.list(3,f);
 assert.equal(await admin("SELECT (SELECT COUNT_BIG(*) FROM dbo.Factura) F,(SELECT SUM(CONVERT(bigint,Stock)) FROM dbo.Producto) S,(SELECT COUNT_BIG(*) FROM dbo.MovimientoCaja) C,(SELECT COUNT_BIG(*) FROM dbo.Kardex_Inventario) K FOR JSON PATH"),before);
 console.log('PASS laboratorio: snapshot de emision, precios historicos, idempotencia, paginacion SQL y consulta sin escrituras');
 fs.writeFileSync('.data/facturas39-sql.json',JSON.stringify({database:state.lab,passed:true,invoice6010:true}));
}
checks().catch(e=>{console.error(e.stderr||e.message);process.exitCode=1;}).finally(db.closePool);
