'use strict';
// All writes are guarded by the dedicated lab name; no main DB fallback.
require('dotenv').config({quiet:true});
const fs=require('node:fs'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const state=JSON.parse(fs.readFileSync('.data/cotizaciones-lab.json','utf8').replace(/^\uFEFF/,''));
assert.match(state.lab,/^SecureFinanceERP_P3_COT_\d{14}_[a-f0-9]{8}$/);
process.env.DB_NAME=state.lab;
const {sql,getPool,closePool}=require('../../src/config/database');
const {labAdmin}=require('./cotizacionesLabAdmin');
const {createCotizacionService}=require('../../src/modules/cotizaciones/service');
const {createProductoService}=require('../../src/services/productoService');
const {createClienteService}=require('../../src/services/clienteService');
const {createProveedorService}=require('../../src/services/proveedorService');
const {createInventarioService}=require('../../src/services/inventarioService');
const {createVentaService}=require('../../src/services/ventaService');
const {createFacturaService}=require('../../src/services/facturaService');
const admin=labAdmin(),service=createCotizacionService(),products=createProductoService(),customers=createClienteService();
const actor=state.actor,passed=[],lit=s=>"N'"+String(s).replaceAll("'","''")+"'";
const pass=name=>{passed.push(name);console.log('PASS UC09 '+name);};
const query=async s=>(await admin.query(s))[0];
const reject=async(fn,numbers)=>assert.rejects(fn,e=>[].concat(numbers).includes(e.number));
const migration=()=>fs.readFileSync('database/43_P3_COT_ConversionFactura.sql','utf8').split(/^\s*GO\s*\r?$/im).filter(s=>s.trim());
async function apply(){await admin.query('BEGIN TRANSACTION;');try{for(const s of migration())await admin.query(s);await admin.query('COMMIT;');}catch(e){await admin.query('IF @@TRANCOUNT>0 ROLLBACK;');throw e;}}
async function fingerprint(table,key,max){return (await query(`SELECT CONVERT(VARCHAR(64),HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),(SELECT * FROM dbo.${table} WHERE ${key}<=${max} ORDER BY ${key} FOR JSON PATH,INCLUDE_NULL_VALUES))),2) H`))[0].H;}
async function run(){
 try{
 const pool=await getPool();assert.equal((await pool.request().query('SELECT DB_NAME() N')).recordset[0].N,state.lab);
 const baselineFile='.data/uc09-baseline.json';let baseline;
 if(fs.existsSync(baselineFile))baseline=JSON.parse(fs.readFileSync(baselineFile));
 if(baseline?.lab!==state.lab){
  baseline={lab:state.lab,tables:[]};
  for(const [table,key] of [['Factura','FacturaId'],['DetalleFactura','DetalleFacturaId'],['MovimientoCaja','MovimientoCajaId'],['Kardex_Inventario','KardexId']]){
   const max=(await query(`SELECT ISNULL(MAX(${key}),0) M FROM dbo.${table}`))[0].M;
   baseline.tables.push({table,key,max,hash:await fingerprint(table,key,max)});
  }
  fs.writeFileSync(baselineFile,JSON.stringify(baseline));
 }
 const supplier=(await createProveedorService().list(actor,{})).find(p=>p.Activo);assert.ok(supplier);
 const client=(await customers.save(actor,{NIT:'QAUC09'+Date.now(),Nombre:'Cliente QA UC09 - Laboratorio',Correo:null,Telefono:null}))[0];
 async function product(stock=10,price='100.00'){
  const p=(await products.save(actor,{CodigoAutomatico:true,Codigo:null,Descripcion:'QA UC09 '+randomUUID(),Precio:price,PrecioCosto:'40.00',ProveedorId:supplier.ProveedorId,StockMinimo:1,PuntoReorden:2,GarantiaMeses:0,Fotografia:null}))[0];
  if(stock)await createInventarioService().receive(actor,{id:p.ProductoId,ProveedorId:supplier.ProveedorId,Cantidad:stock,DocumentoRespaldo:'QA UC09 LAB',Motivo:'Ingreso de prueba aislada UC09',OperacionId:randomUUID(),CostoUnitario:'40.00'});
  return p.ProductoId;
 }
 async function quote(p,qty=1,discount=0,validMs=86400000,creator=actor){return service.create(creator,{ClienteId:client.ClienteId,VenceEn:new Date(Date.now()+validMs),OperacionId:randomUUID(),Observaciones:'QA UC09 laboratorio',Detalle:[{ProductoId:p,Cantidad:qty,DescuentoPorcentaje:discount}]});}
 const stock=async p=>(await query(`SELECT Stock,CONVERT(VARCHAR(21),Precio) Precio FROM dbo.Producto WHERE ProductoId=${p}`))[0];
 const totals=async()=> (await query('SELECT (SELECT COUNT(*) FROM dbo.Factura) F,(SELECT COUNT(*) FROM dbo.DetalleFactura) D,(SELECT COUNT(*) FROM dbo.MovimientoCaja) C,(SELECT COUNT(*) FROM dbo.Kardex_Inventario) K,(SELECT COUNT(*) FROM dbo.SolicitudVentaERP) S'))[0];
 async function wrapper(q,operation,changes={}){
  const detail=await service.detail(actor,q.CotizacionId),d=detail.documento,table=new sql.Table('dbo.TipoDetalleVentaDescuento');
  table.columns.add('ProductoId',sql.Int,{nullable:false});table.columns.add('Cantidad',sql.Int,{nullable:false});table.columns.add('DescuentoPorcentaje',sql.Decimal(5,2),{nullable:false});
  for(const l of detail.lineas)table.rows.add(l.ProductoId,changes.qty??l.Cantidad,Number(l.DescuentoPorcentaje));
  return (await pool.request().input('ClienteId',sql.Int,changes.client??d.ClienteId).input('UsuarioId',sql.Int,changes.actor??actor)
   .input('Detalle',table).input('OperacionId',sql.UniqueIdentifier,operation).input('MotivoDescuento',sql.NVarChar(80),changes.reason??(detail.lineas.some(l=>Number(l.DescuentoPorcentaje)>0)?'Ajuste comercial':null))
   .input('P3CotizacionId',sql.Int,changes.id??q.CotizacionId).execute('dbo.sp_ERP_ProcesarVenta')).recordsets;
 }
 // Establish a genuine request on the pre-extension wrapper and retain it across reruns.
 let legacy;const legacyPath='.data/uc09-legacy.json';if(fs.existsSync(legacyPath))legacy=JSON.parse(fs.readFileSync(legacyPath));
 if(legacy?.lab!==state.lab){
  const p=await product(5),operation=randomUUID(),lines=[{ProductoId:p,Cantidad:1,DescuentoPorcentaje:0}];
  const pre43=(await query("SELECT COUNT(*) N FROM sys.parameters WHERE object_id=OBJECT_ID('dbo.sp_ERP_ProcesarVenta') AND name='@P3CotizacionId'"))[0].N===0;
  const sale=await createVentaService().procesarVenta(client.ClienteId,actor,lines,null,operation);
  const record=(await query(`SELECT SolicitudHash,Comprobante,Detalle FROM dbo.SolicitudVentaERP WHERE OperacionId=${lit(operation)}`))[0];
  legacy={lab:state.lab,pre43,p,client:client.ClienteId,operation,lines,sale,record};fs.writeFileSync(legacyPath,JSON.stringify(legacy));
 }
 assert.equal(legacy.pre43,true,'La venta de regresion debe haberse emitido antes de instalar 43');
 await apply();pass('instalacion atomica de migracion 43 y firma opcional');
 const ready=await service.readiness(actor,1);assert.equal(ready.installed,true);assert.equal(ready.executable,true);pass('DB_NAME y EXECUTE efectivo de UC09 y wrapper verificados');
 const beforeReplay=await totals();const historical=await createVentaService().procesarVenta(legacy.client,actor,legacy.lines,null,legacy.operation);
 assert.equal(historical.FacturaId,legacy.sale.FacturaId);assert.deepEqual(await totals(),beforeReplay);
 assert.deepEqual((await query(`SELECT SolicitudHash,Comprobante,Detalle FROM dbo.SolicitudVentaERP WHERE OperacionId=${lit(legacy.operation)}`))[0],legacy.record);pass('reintento de venta pre-43 conserva factura, hash y JSON historicos');
 const p=await product(10),q=await quote(p,2,10),before=await totals();
 const src=(await products.list(actor,{id:p,costo:true}))[0];await products.save(actor,{...src,id:p,Precio:'120.00',Descripcion:'QA UC09 descripcion al facturar',Fotografia:null});
 const operation=randomUUID(),converted=await service.convert(actor,q.CotizacionId,operation),f=converted.documento.FacturaId;
 assert.equal(converted.factura.Detalle[0].PrecioUnitario,'100.00');assert.equal(converted.factura.Total,'201.60');assert.deepEqual(await stock(p),{Stock:8,Precio:'120.00'});
 const ledger=(await query(`SELECT f.Subtotal,f.DescuentoTotal,f.IVA,f.Total,d.Cantidad,d.PrecioUnitario,(SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE DetalleFacturaId=d.DetalleFacturaId) K,(SELECT COUNT(*) FROM dbo.MovimientoCaja WHERE FacturaId=f.FacturaId) C,(SELECT Monto FROM dbo.MovimientoCaja WHERE FacturaId=f.FacturaId) Caja FROM dbo.Factura f JOIN dbo.DetalleFactura d ON d.FacturaId=f.FacturaId WHERE f.FacturaId=${f}`))[0];
 assert.deepEqual(ledger,{Subtotal:'200.00',DescuentoTotal:'20.00',IVA:'21.60',Total:'201.60',Cantidad:2,PrecioUnitario:'100.00',K:1,C:1,Caja:'201.60'});
 assert.equal((await service.detail(actor,q.CotizacionId)).documento.Estado,'PROCESADA');
 const receipt=await createFacturaService().detail(actor,f);
 assert.equal(receipt.detalle[0].Descripcion,'QA UC09 descripcion al facturar');
 assert.notEqual((await service.detail(actor,q.CotizacionId)).lineas[0].Descripcion,receipt.detalle[0].Descripcion);
 assert.equal((await totals()).F,before.F+1);pass('Q100 x2 con descuento 10%, catalogo Q120: factura Q201.60, stock 8, Kardex y caja unicos');
 const after=await totals();assert.equal((await service.convert(actor,q.CotizacionId,operation)).documento.FacturaId,f);assert.deepEqual(await totals(),after);
 await reject(()=>service.convert(actor,q.CotizacionId,randomUUID()),54903);pass('reintento confirmado y rechazo de otra referencia en procesada');
 const other=await quote(p);await reject(()=>service.convert(actor,other.CotizacionId,operation),54803);pass('UUID no reutilizable con otra cotizacion');
 const direct=await quote(p);await wrapper(direct,randomUUID());assert.equal((await service.detail(actor,direct.CotizacionId)).documento.Estado,'PROCESADA');pass('wrapper directo valido cierra documento atomico');
 const altered=await quote(p);await reject(()=>wrapper(altered,randomUUID(),{qty:2}),54912);await reject(()=>wrapper(altered,randomUUID(),{id:2147483647}),54904);await reject(()=>wrapper(altered,randomUUID(),{client:2147483647}),54912);await reject(()=>wrapper(altered,randomUUID(),{reason:'Otro'}),54912);pass('wrapper rechaza origen inventado y cliente, motivo o lineas alteradas');
 const expired=await quote(p,1,0,1400);await new Promise(r=>setTimeout(r,1600));await reject(()=>service.convert(actor,expired.CotizacionId,randomUUID()),54910);
 const cancelled=await quote(p);await service.cancel(actor,cancelled.CotizacionId,randomUUID(),'QA UC09 cancelacion');await reject(()=>service.convert(actor,cancelled.CotizacionId,randomUUID()),54903);pass('vencida y cancelada rechazadas');
 const poor=await product(1),insufficient=await quote(poor,2);const beforeInsufficient=await totals();await reject(()=>service.convert(actor,insufficient.CotizacionId,randomUUID()),52010);assert.deepEqual(await totals(),beforeInsufficient);assert.equal((await stock(poor)).Stock,1);pass('stock insuficiente sin efectos parciales');
 const inactiveProduct=await product(2),iq=await quote(inactiveProduct),ip=(await products.list(actor,{id:inactiveProduct,costo:true}))[0];await products.save(actor,{...ip,id:inactiveProduct,Activo:false,Fotografia:null});await reject(()=>service.convert(actor,iq.CotizacionId,randomUUID()),52009);pass('producto inactivo rechazado');
 const inactiveClient=(await customers.save(actor,{NIT:'QAUCINA'+Date.now(),Nombre:'QA UC09 cliente inactivo',Correo:null,Telefono:null}))[0];
 const cq=await service.create(actor,{ClienteId:inactiveClient.ClienteId,VenceEn:new Date(Date.now()+86400000),OperacionId:randomUUID(),Detalle:[{ProductoId:p,Cantidad:1,DescuentoPorcentaje:0}]});await customers.update(actor,{id:inactiveClient.ClienteId,Version:inactiveClient.Version,Motivo:'QA UC09'},true);await reject(()=>service.convert(actor,cq.CotizacionId,randomUUID()),52006);pass('cliente inactivo rechazado');
 await reject(()=>service.convert(-1,altered.CotizacionId,randomUUID()),54101);await reject(()=>pool.request().query('EXEC dbo.sp_ProcesarVentaTransaccional'),229);pass('RBAC SQL y acceso directo al nucleo denegado');
 const actors=(await query(`DECLARE @Name NVARCHAR(50)=CONCAT(N'QA_COT_',REPLACE(CONVERT(VARCHAR(36),NEWID()),'-','')); INSERT dbo.Usuario(NombreUsuario,NombreCompleto,Correo,PasswordHash) VALUES(@Name,N'QA UC09 segundo actor',CONCAT(@Name,N'@example.invalid'),CRYPT_GEN_RANDOM(64)); DECLARE @Id INT=SCOPE_IDENTITY(); INSERT dbo.Usuario_Rol(UsuarioId,RolId) SELECT @Id,RolId FROM dbo.Rol WHERE Nombre=N'Administrador'; SELECT @Id Id;`))[0];
 const raceP=await product(3),raceQ=await quote(raceP);const race=await Promise.allSettled([service.convert(actor,raceQ.CotizacionId,randomUUID()),service.convert(actors.Id,raceQ.CotizacionId,randomUUID())]);assert.equal(race.filter(r=>r.status==='fulfilled').length,1);assert.equal(race.find(r=>r.status==='rejected').reason.number,54903);assert.equal((await stock(raceP)).Stock,2);pass('dos usuarios administradores simultaneos: una factura');
 const sameQ=await quote(raceP),sameOp=randomUUID(),same=await Promise.all([service.convert(actor,sameQ.CotizacionId,sameOp),service.convert(actor,sameQ.CotizacionId,sameOp)]);assert.equal(same[0].documento.FacturaId,same[1].documento.FacturaId);pass('dos solicitudes simultaneas de la misma referencia: mismo comprobante');
 const last=await product(1),a=await quote(last),b=await quote(last);const competition=await Promise.allSettled([service.convert(actor,a.CotizacionId,randomUUID()),service.convert(actor,b.CotizacionId,randomUUID())]);assert.equal(competition.filter(r=>r.status==='fulfilled').length,1);assert.equal(competition.find(r=>r.status==='rejected').reason.number,52010);assert.equal((await stock(last)).Stock,0);pass('dos cotizaciones por ultima unidad: un egreso, sin stock negativo');
 const rollbackP=await product(3),rollbackQ=await quote(rollbackP),rollbackOp=randomUUID(),beforeRollback=await totals();
 await admin.query(`CREATE OR ALTER TRIGGER dbo.P3_COT_QA_FalloKardex ON dbo.Kardex_Inventario AFTER INSERT AS BEGIN IF EXISTS(SELECT 1 FROM inserted WHERE ProductoId=${rollbackP} AND TipoMovimiento='VENTA') THROW 54998,'QA falla despues de Factura en Kardex',1; END;`);
 try{await reject(()=>service.convert(actor,rollbackQ.CotizacionId,rollbackOp),54998);}finally{await admin.query('DROP TRIGGER dbo.P3_COT_QA_FalloKardex;');}
 assert.deepEqual(await totals(),beforeRollback);assert.equal((await stock(rollbackP)).Stock,3);assert.equal((await service.detail(actor,rollbackQ.CotizacionId)).documento.Estado,'ACTIVA');assert.equal((await service.detail(actor,rollbackQ.CotizacionId)).historial.length,1);
 await service.convert(actor,rollbackQ.CotizacionId,rollbackOp);pass('error despues de Factura en Kardex revierte todo; misma referencia recuperable');
 // Waiting on inventory must not extend expiry.
 const waitingP=await product(1),waitingQ=await quote(waitingP,1,0,1800);await admin.query(`BEGIN TRANSACTION; SELECT Stock FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK) WHERE ProductoId=${waitingP};`);
 const blocked=service.convert(actor,waitingQ.CotizacionId,randomUUID()).then(()=>({ok:true}),e=>({error:e.number}));await new Promise(r=>setTimeout(r,2000));await admin.query('COMMIT;');assert.equal((await blocked).error,54910);assert.equal((await stock(waitingP)).Stock,1);pass('vigencia revalidada tras espera por producto bloqueado');
 // A non-admin with both permissions may not convert another creator's document.
 const outsider=(await query(`DECLARE @Name NVARCHAR(50)=CONCAT(N'QA_COT_',REPLACE(CONVERT(VARCHAR(36),NEWID()),'-','')); INSERT dbo.Usuario(NombreUsuario,NombreCompleto,Correo,PasswordHash) VALUES(@Name,N'QA UC09 no administrador',CONCAT(@Name,N'@example.invalid'),CRYPT_GEN_RANDOM(64)); DECLARE @Id INT=SCOPE_IDENTITY(); INSERT dbo.Rol(Nombre) VALUES(@Name);DECLARE @R INT=SCOPE_IDENTITY(); INSERT dbo.Usuario_Rol VALUES(@Id,@R,SYSUTCDATETIME()); INSERT dbo.Rol_Permiso SELECT @R,PermisoId FROM dbo.Permiso WHERE Codigo IN(N'COTIZACIONES_CONVERTIR',N'VENTAS_REGISTRAR'); SELECT @Id Id;`))[0];
 await reject(()=>wrapper(altered,randomUUID(),{actor:outsider.Id}),54101);pass('documento ajeno rechazado aunque el actor tenga permisos generales');
 const policyQuote=await quote(p,1,20,86400000,actors.Id);
 await admin.query(`DELETE FROM dbo.Usuario_Rol WHERE UsuarioId=${actors.Id}; INSERT dbo.Usuario_Rol(UsuarioId,RolId) SELECT ${actors.Id},RolId FROM dbo.Usuario_Rol WHERE UsuarioId=${outsider.Id};`);
 await reject(()=>service.convert(actors.Id,policyQuote.CotizacionId,randomUUID()),52012);pass('descuento pactado rechazado si la autorizacion vigente del creador disminuye');
 await reject(()=>wrapper(altered,legacy.operation),54803);
 await reject(()=>createVentaService().procesarVenta(client.ClienteId,actor,[{ProductoId:p,Cantidad:2,DescuentoPorcentaje:10}],'Ajuste comercial',operation),54803);pass('colision UUID entre venta normal y cotizacion rechazada en ambos sentidos');
 const normalP=await product(4),normalLines=[{ProductoId:normalP,Cantidad:1,DescuentoPorcentaje:0}],normalOp=randomUUID();const normal=await createVentaService().procesarVenta(client.ClienteId,actor,normalLines,null,normalOp);assert.equal(normal.Total,'112.00');assert.equal((await stock(normalP)).Stock,3);assert.equal((await createVentaService().procesarVenta(client.ClienteId,actor,normalLines,null,normalOp)).FacturaId,normal.FacturaId);pass('venta normal Parte II y reintento sin regresion');
 const raw=`DECLARE @D dbo.TipoDetalleVentaDescuento; INSERT @D VALUES(${normalP},1,0); EXEC dbo.sp_ERP_ProcesarVenta ${client.ClienteId},${actor},@D,${lit(randomUUID())},NULL,NULL;`;
 const positional=await admin.query(raw);assert.equal(positional[0][0].Total,'112.00');pass('firma posicional existente y NULL explicito conservan contado');
 const exhausted=await product(1),exq=await quote(exhausted,1,0,1600),exop=randomUUID(),ex=await service.convert(actor,exq.CotizacionId,exop);await new Promise(r=>setTimeout(r,1700));assert.equal((await service.convert(actor,exq.CotizacionId,exop)).documento.FacturaId,ex.documento.FacturaId);assert.equal((await stock(exhausted)).Stock,0);pass('reintento despues de vencer y agotar stock no repite validaciones de primera venta');
 const countBefore=await totals();await apply();assert.deepEqual(await totals(),countBefore);assert.equal((await service.convert(actor,q.CotizacionId,operation)).documento.FacturaId,f);pass('reaplicacion 43 conserva datos y conversiones idempotentes');
 for(const t of baseline.tables)assert.equal(await fingerprint(t.table,t.key,t.max),t.hash);pass('facturas, detalle, caja y Kardex anteriores intactos por SHA256');
 const audit=(await query("SELECT COUNT(*) N FROM dbo.P3_COT_HistorialEstado h WHERE EstadoNuevo='PROCESADA' AND NOT EXISTS(SELECT 1 FROM dbo.Bitacora_Transacciones b WHERE b.TablaAfectada=N'P3_COT_Cotizacion' AND b.OperacionId=h.OperacionId AND b.ActorUsuarioId=h.ActorUsuarioId)"))[0];assert.equal(audit.N,0);await admin.query('DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;');const constraints=await admin.query('DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS');assert(!constraints.some(rows=>rows.length));pass('auditoria completa, CHECKDB e integridad referencial');
 // Browser and manual-preview fixtures, only in this lab.
 const browserP=await product(12),browserQ=await quote(browserP,2,10);
 const result={lab:state.lab,actor,clientId:client.ClienteId,productId:browserP,browserQuote:browserQ.CotizacionId,frozenQuote:q.CotizacionId,frozenInvoice:f,priceQuote:'100.00',priceCatalog:'120.00',priceInvoice:'100.00',stockBefore:10,stockAfter:8,total:'201.60',passed,legacySeedBefore43:legacy.pre43,conversion:'PASS'};
 fs.writeFileSync('.data/uc09-sql.json',JSON.stringify(result,null,2));
 console.log('UC09 SQL COMPLETE: '+passed.length+' grupos PASS');
 }finally{admin.close();await closePool();}
}
run().catch(e=>{console.error('UC09 FAIL',e.number||e.code||e.name,e.message);process.exitCode=1;});
