'use strict';
require('dotenv').config({quiet:true});
const fs=require('node:fs'),assert=require('node:assert/strict');
const state=JSON.parse(fs.readFileSync('.data/cotizaciones-lab.json','utf8').replace(/^\uFEFF/,''));
assert.match(state.lab,/^SecureFinanceERP_P3_COT_\d{14}_[a-f0-9]{8}$/);process.env.DB_NAME=state.lab;
const {getPool,closePool}=require('../../src/config/database');
const {createCotizacionService}=require('../../src/modules/cotizaciones/service');
const {labAdmin}=require('./cotizacionesLabAdmin');
const {createClienteService}=require('../../src/services/clienteService');
async function run(){
 const admin=labAdmin(),passed=[];const pass=n=>{passed.push(n);console.log('PASS BUSQUEDA '+n);};
 const snapshot=async()=>await admin.query("SELECT o.name,CONVERT(VARCHAR(64),HASHBYTES('SHA2_256',m.definition),2) H FROM sys.objects o JOIN sys.sql_modules m ON m.object_id=o.object_id WHERE o.name IN('sp_ConvertirCotizacionAFactura','sp_ERP_ProcesarVenta','sp_ProcesarVentaTransaccional','sp_RegistrarMovimientoKardex') ORDER BY o.name; SELECT (SELECT COUNT(*) FROM dbo.Factura) F,(SELECT COUNT(*) FROM dbo.MovimientoCaja) C,(SELECT COUNT(*) FROM dbo.Kardex_Inventario) K;");
 try{
  const pool=await getPool();assert.equal((await pool.request().query('SELECT DB_NAME() N')).recordset[0].N,state.lab);
  const before=await snapshot();
  for(const batch of fs.readFileSync('database/44_P3_COT_BusquedaComercial.sql','utf8').split(/^\s*GO\s*\r?$/im)){if(batch.trim())await admin.query(batch);}
  assert.deepEqual(await snapshot(),before);pass('reaplicacion 44 no cambia motor UC09, caja, Kardex ni facturas');
  const service=createCotizacionService(),actor=state.actor;
  const form=await service.form(actor);assert.ok(form.politica.Ahora);assert.equal(form.clientes,undefined);assert.equal(form.productos,undefined);pass('formulario recibe politica y reloj SQL sin cargar catalogos completos');
  const stamp=Date.now(),prefix='Cliente QA Busqueda '+stamp;
  for(let i=0;i<9;i++)await createClienteService().save(actor,{NIT:'QABUS'+stamp+i,Nombre:prefix+' '+i,Correo:null,Telefono:null});
  for(const type of ['clientes','productos']){
   const term=type==='clientes'?prefix:'';
   const a=await service.search(actor,type,term,1),b=await service.search(actor,type,term,2);assert.ok(a.rows.length<=8);assert.ok(b.rows.length<=8);assert(!a.rows.some(x=>b.rows.some(y=>x.Id===y.Id)));assert.equal(a.next,true);
   const selected=a.rows[0],byName=await service.search(actor,type,selected.Nombre.slice(0,30),1),byCode=await service.search(actor,type,selected.Referencia,1);assert.ok(byName.rows.length);assert.ok(byCode.rows.some(x=>x.Id===selected.Id));
  }
  pass('clientes/productos paginados, estables, por nombre y NIT/SKU');
  assert.equal((await service.search(actor,'productos',"' OR 1=1 --",1)).rows.length,0);assert.equal((await service.search(actor,'clientes','BUSQUEDA_INEXISTENTE_COT_999999',1)).rows.length,0);pass('texto parametrizado y estados vacios reales');
  await assert.rejects(()=>service.search(-1,'productos','',1),e=>e.number===54101);pass('permiso SQL vigente requerido para buscar');
  const zero=(await admin.query('SELECT TOP(1) Codigo FROM dbo.Producto WHERE Activo=1 AND Stock=0 ORDER BY ProductoId'))[0][0];assert.ok(zero);
  const result=await service.search(actor,'productos',zero.Codigo,1);assert.ok(result.rows.some(r=>r.Stock===0));pass('stock cero identificado sin ocultar registros por prefijo');
  assert.deepEqual(await snapshot(),before);pass('consultas no generan efectos financieros o de inventario');
  fs.mkdirSync('docs/parte3/cotizaciones/redisenio',{recursive:true});fs.writeFileSync('docs/parte3/cotizaciones/redisenio/busqueda-sql.json',JSON.stringify({lab:state.lab,passed},null,2));
 }finally{admin.close();await closePool();}
}
run().catch(e=>{console.error('BUSQUEDA FAIL',e.number||e.code||e.name,e.message);process.exitCode=1;});
