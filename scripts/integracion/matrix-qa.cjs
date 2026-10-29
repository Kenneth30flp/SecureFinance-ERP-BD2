'use strict';
const fs=require('fs'),assert=require('assert/strict'),{randomUUID}=require('crypto'),lab=require('../../database/tests/promocionesLab');const state=lab.useLab();const {sql,getPool,closePool}=require('../../src/config/database');
const {createProductoService}=require('../../src/services/productoService'),{createClienteService}=require('../../src/services/clienteService'),{createInventarioService}=require('../../src/services/inventarioService'),{createCreditoService}=require('../../src/modules/creditos/service'),{createPromocionService}=require('../../src/modules/promociones/service');
const checks=[];const actor=state.actor;
(async()=>{try{
 const pool=await getPool();assert.equal((await pool.request().query('SELECT DB_NAME() N')).recordset[0].N,state.lab);
 const supplier=(await lab.labJson('SELECT TOP(1) ProveedorId FROM dbo.Proveedor WHERE Activo=1'))[0];
 const client=(await createClienteService().save(actor,{NIT:'QM'+Date.now(),Nombre:'Matriz sintetica integrada',Correo:null,Telefono:null}))[0];
 const p=(await createProductoService().save(actor,{CodigoAutomatico:true,Codigo:null,Descripcion:'QA matriz integrada '+randomUUID(),Precio:'100.00',PrecioCosto:'40.00',ProveedorId:supplier.ProveedorId,StockMinimo:1,PuntoReorden:2,GarantiaMeses:0,Fotografia:null}))[0];
 await createInventarioService().receive(actor,{id:p.ProductoId,ProveedorId:supplier.ProveedorId,Cantidad:30,DocumentoRespaldo:'QA MATRIZ',Motivo:'Fixture sintetico',OperacionId:randomUUID(),CostoUnitario:'40.00'});
 await createCreditoService().profile(actor,{ClienteId:client.ClienteId,Activo:true,Limite:'10000.00',PlazoDias:30,VersionEsperada:null,Motivo:'QA matriz',OperacionId:randomUUID()});
 const promos=createPromocionService();const pr=await promos.create(actor,{OperacionId:randomUUID(),Codigo:'QM'+Date.now(),Nombre:'QA matriz 10%',Descripcion:null,TipoCodigo:'PORCENTAJE',Porcentaje:'10.00',CantidadMinima:null,TopeDescuento:null,VigenteDesde:new Date(Date.now()-86400000),VigenteHasta:new Date(Date.now()+86400000),Productos:[p.ProductoId],Categorias:[],Motivo:'Fixture sintetico'});await promos.setState(actor,pr.PromocionId,{Activa:true,Version:pr.Version,OperacionId:randomUUID(),Motivo:'QA matriz'});
 const b=(await lab.labJson('SELECT CentralId FROM dbo.P3_BOD_Configuracion WHERE ConfiguracionId=1'))[0].CentralId;
 async function sell(credit,promo,warehouse,op=randomUUID(),plan=credit?30:null){
 const d=new sql.Table('dbo.TipoDetalleVentaDescuento');d.columns.add('ProductoId',sql.Int,{nullable:false});d.columns.add('Cantidad',sql.Int,{nullable:false});d.columns.add('DescuentoPorcentaje',sql.Decimal(5,2),{nullable:false});d.rows.add(p.ProductoId,1,0);
 const r=pool.request().input('C',sql.Int,client.ClienteId).input('A',sql.Int,actor).input('D',d).input('O',sql.UniqueIdentifier,op).input('Cr',sql.Bit,credit).input('Pr',sql.Bit,promo).input('B',sql.Int,warehouse?b:null).input('Plan',sql.Int,plan);
 const result=await r.query(`BEGIN TRY
 EXEC sys.sp_set_session_context @key=N'P3_BOD.BodegaId',@value=@B;
 EXEC dbo.sp_ERP_ProcesarVenta @ClienteId=@C,@UsuarioId=@A,@Detalle=@D,@OperacionId=@O,@P3AplicarPromociones=@Pr,@P3Credito=@Cr,@P3PlazoDias=@Plan;
 EXEC sys.sp_set_session_context @key=N'P3_BOD.BodegaId',@value=NULL;
 END TRY BEGIN CATCH EXEC sys.sp_set_session_context @key=N'P3_BOD.BodegaId',@value=NULL;THROW;END CATCH;`);
 return result.recordsets[0][0];
 }
 for(const credit of [false,true])for(const promo of [false,true])for(const warehouse of [false,true]){
 const op=randomUUID(),before=(await lab.labJson(`SELECT Stock FROM dbo.Producto WHERE ProductoId=${p.ProductoId}`))[0].Stock;
 const sale=await sell(credit,promo,warehouse,op);assert.equal(sale.Total,promo?'100.80':'112.00');assert.equal((await sell(credit,promo,warehouse,op)).FacturaId,sale.FacturaId);
 const summary=(await lab.labJson(`SELECT (SELECT COUNT(*) FROM dbo.MovimientoCaja WHERE FacturaId=${sale.FacturaId}) Caja,(SELECT COUNT(*) FROM dbo.P3_CRE_Cuenta WHERE FacturaId=${sale.FacturaId}) Credito,(SELECT COUNT(*) FROM dbo.P3_PRO_AplicacionFactura WHERE FacturaId=${sale.FacturaId}) Promo,(SELECT Stock FROM dbo.Producto WHERE ProductoId=${p.ProductoId}) Stock`))[0];assert.equal(summary.Caja,credit?0:1);assert.equal(summary.Credito,credit?1:0);assert.equal(summary.Promo,promo?1:0);assert.equal(summary.Stock,before-1);
 await assert.rejects(()=>sell(!credit,promo,warehouse,op),e=>e.number===54803);await assert.rejects(()=>sell(credit,!promo,warehouse,op),e=>e.number===54803);
 checks.push({credit,promo,warehouse,total:sale.Total,caja:summary.Caja,replay:'same invoice',stockDelta:-1});
 }
 await assert.rejects(()=>sell(false,false,false,randomUUID(),30),e=>e.number===57002);checks.push({cashWithCreditPlan:'rejected 57002'});
 await assert.rejects(()=>pool.request().query('SELECT TOP(1) ComandoTSql FROM dbo.Bitacora_DDL'),e=>e.number===229);checks.push({ddlTextDirectSelect:'denied 229'});
 await lab.labQuery("DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;IF EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE Diferencia<>0) THROW 58100,'Descuadre',1;");
 fs.writeFileSync('docs/parte3/integracion-dylan/evidencias/matriz.json',JSON.stringify({lab:state.lab,checks},null,2));console.log('MATRIX PASS '+checks.length);
 }finally{await closePool();}})().catch(e=>{console.error('MATRIX FAIL',e.number,e.message);process.exitCode=1;});
