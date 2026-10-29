'use strict';
// Pruebas de aceptación SQL reales de Promociones (60-63) en el laboratorio aislado.
// Requiere: node database/tests/promocionesLab.js --build --install
// Escrituras solo en SecureFinanceERP_P3_PRO_*; la cuenta de aplicación es el login del laboratorio.
const fs=require('node:fs'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const lab=require('./promocionesLab');
const state=lab.useLab();
const {sql,getPool,closePool}=require('../../src/config/database');
const {createPromocionService}=require('../../src/modules/promociones/service');
const {createVentaService}=require('../../src/services/ventaService');
const {createFacturaService}=require('../../src/services/facturaService');
const {createProductoService}=require('../../src/services/productoService');
const {createProveedorService}=require('../../src/services/proveedorService');
const {createClienteService}=require('../../src/services/clienteService');
const {createInventarioService}=require('../../src/services/inventarioService');
const {createCotizacionService}=require('../../src/modules/cotizaciones/service');
const promos=createPromocionService(),ventas=createVentaService(),facturas=createFacturaService(),products=createProductoService();
const actor=state.actor,results=[];
const pass=(name,detail={})=>{results.push({prueba:name,resultado:'PASS',...detail});console.log('PASS PRO '+name);};
const reject=(fn,numbers)=>assert.rejects(fn,e=>{if(![].concat(numbers).includes(e.number))console.error('Numero inesperado',e.number,e.message);return [].concat(numbers).includes(e.number);});
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const now=()=>Date.now();
const day=86400000;
let supplier,client;
async function product(stock=20,price='100.00'){
 const p=(await products.save(actor,{CodigoAutomatico:true,Codigo:null,Descripcion:'QA PRO '+randomUUID().slice(0,8),Precio:price,PrecioCosto:'40.00',ProveedorId:supplier.ProveedorId,StockMinimo:1,PuntoReorden:2,GarantiaMeses:0,Fotografia:null}))[0];
 if(stock)await createInventarioService().receive(actor,{id:p.ProductoId,ProveedorId:supplier.ProveedorId,Cantidad:stock,DocumentoRespaldo:'QA PRO LAB',Motivo:'Ingreso de prueba aislada de promociones',OperacionId:randomUUID(),CostoUnitario:'40.00'});
 return p.ProductoId;
}
let codeSeq=0;
const code=prefix=>(prefix+'-'+Date.now().toString(36)+'-'+(++codeSeq)).toUpperCase().slice(0,30);
function rule(over){return {OperacionId:randomUUID(),Codigo:code('QA'),Nombre:'Promocion QA',Descripcion:null,TipoCodigo:'PORCENTAJE',Porcentaje:'10.00',CantidadMinima:null,TopeDescuento:null,
 VigenteDesde:new Date(now()-day),VigenteHasta:new Date(now()+30*day),Productos:[],Categorias:[],Motivo:'Alta QA laboratorio',...over};}
async function createActive(over,who=actor){const p=await promos.create(who,rule(over));const s=await promos.setState(who,p.PromocionId,{Activa:true,Version:p.Version,OperacionId:randomUUID(),Motivo:'Activacion QA'});return {...p,...s};}
const sell=(lines,{op=randomUUID(),motivo=null,who=actor,promo=true}={})=>ventas.procesarVenta(client.ClienteId,who,lines,motivo,op,promo?{aplicarPromociones:true}:undefined);
const counts=()=>lab.labJson('SELECT (SELECT COUNT(*) FROM dbo.Factura) F,(SELECT COUNT(*) FROM dbo.DetalleFactura) D,(SELECT COUNT(*) FROM dbo.MovimientoCaja) C,(SELECT COUNT(*) FROM dbo.Kardex_Inventario) K,(SELECT COUNT(*) FROM dbo.SolicitudVentaERP) S,(SELECT COUNT(*) FROM dbo.P3_PRO_AplicacionFactura) A').then(r=>r[0]);
const stock=async p=>(await lab.labJson(`SELECT Stock FROM dbo.Producto WHERE ProductoId=${Number(p)}`))[0].Stock;
const invoiceSnapshot=f=>lab.labJson(`SELECT f.FacturaId,f.Subtotal,f.DescuentoTotal,f.IVA,f.Total,f.MotivoDescuento,(SELECT d.ProductoId,d.Cantidad,d.PrecioUnitario,d.DescuentoPorcentaje,d.DescuentoMonto,d.SubtotalNeto FROM dbo.DetalleFactura d WHERE d.FacturaId=f.FacturaId ORDER BY d.ProductoId FOR JSON PATH) Lineas,(SELECT a.PromocionId,a.DescuentoMonto,a.Regla,a.ReglaVersion FROM dbo.P3_PRO_AplicacionFactura a WHERE a.FacturaId=f.FacturaId ORDER BY a.ProductoId FOR JSON PATH) Aplicaciones FROM dbo.Factura f WHERE f.FacturaId=${Number(f)}`).then(r=>r[0]);
async function run(){
 try{
 const pool=await getPool();assert.equal((await pool.request().query('SELECT DB_NAME() N')).recordset[0].N,state.lab);
 assert.ok(await ventas.promocionesInstaladas(),'Migracion 63 instalada');
 supplier=(await createProveedorService().list(actor,{})).find(p=>p.Activo)||(await createProveedorService().save(actor,{NIT:'QAPRO'+Date.now(),Nombre:'Proveedor QA Promociones',Correo:null,Telefono:null,Direccion:null,Fotografia:null}))[0];
 client=(await createClienteService().save(actor,{NIT:'QAPRO'+Date.now(),Nombre:'Cliente QA Promociones - Laboratorio',Correo:null,Telefono:null}))[0];

 // 0. Contrato historico: con promociones=0 la huella y los recordsets son los de 37/43.
 const legacyP=await product(5),legacyOp=randomUUID();
 const legacy=await sell([{ProductoId:legacyP,Cantidad:1,DescuentoPorcentaje:0}],{op:legacyOp,promo:false});
 assert.equal(legacy.Total,'112.00');assert.equal(legacy.Promociones,undefined);
 const hash=(await lab.labJson(`SELECT CASE WHEN SolicitudHash=HASHBYTES('SHA2_256',CONCAT(${client.ClienteId},N'|',${actor},N'|',N'',N'|',(SELECT ${legacyP} ProductoId,1 Cantidad,CONVERT(DECIMAL(5,2),0) DescuentoPorcentaje FOR JSON PATH))) THEN 1 ELSE 0 END Igual FROM dbo.SolicitudVentaERP WHERE OperacionId='${legacyOp}'`))[0];
 assert.equal(hash.Igual,1);
 const positional=await lab.labQuery(`SET NOCOUNT ON; DECLARE @D dbo.TipoDetalleVentaDescuento; INSERT @D VALUES(${legacyP},1,0); EXEC dbo.sp_ERP_ProcesarVenta ${client.ClienteId},${actor},@D,'${randomUUID()}',NULL,NULL;`);
 assert.match(positional,/112\.00/);
 pass('contrato de venta sin promociones intacto: huella historica, firma posicional y dos recordsets');

 // 1-4. Creacion de los cuatro tipos (inactivas al crear, activacion separada).
 const pPct=await product(30),p2x1=await product(30,'1000.00'),pVol=await product(30,'50.00'),pCat=await product(30,'80.00'),pNone=await product(10);
 const created=await promos.create(actor,rule({Nombre:'QA 10% porcentual',Productos:[pPct]}));
 assert.equal(created.Estado,'INACTIVA');
 const pct=await promos.setState(actor,created.PromocionId,{Activa:true,Version:created.Version,OperacionId:randomUUID(),Motivo:'Publicar QA'});
 assert.equal(pct.Estado,'VIGENTE');pass('crear promocion porcentual (inactiva) y activarla');
 const dos=await createActive({Nombre:'QA 2x1',TipoCodigo:'DOS_POR_UNO',Porcentaje:null,CantidadMinima:2,Productos:[p2x1]});pass('crear promocion 2x1');
 const vol=await createActive({Nombre:'QA volumen 15% desde 3',TipoCodigo:'VOLUMEN',Porcentaje:'15.00',CantidadMinima:3,Productos:[pVol]});pass('crear promocion por volumen');
 const cat=await promos.createCategory(actor,{Nombre:'QA Categoria '+Date.now(),OperacionId:randomUUID(),Motivo:'Categoria QA'});
 await promos.assignCategory(actor,{ProductoId:pCat,CategoriaId:cat.CategoriaId,OperacionId:randomUUID(),Motivo:'Asignacion QA'});
 const catPromo=await createActive({Nombre:'QA categoria 20%',TipoCodigo:'CATEGORIA',Porcentaje:'20.00',Categorias:[cat.CategoriaId]});pass('crear promocion por categoria con extension incremental de categorias');
 await reject(()=>promos.create(actor,rule({TipoCodigo:'DOS_POR_UNO',Porcentaje:'10.00',Productos:[pPct]})),57102);
 await reject(()=>promos.create(actor,rule({TipoCodigo:'VOLUMEN',CantidadMinima:1,Productos:[pPct]})),57102);
 await reject(()=>promos.create(actor,rule({Porcentaje:'95.00',Productos:[pPct]})),57102);
 await reject(()=>promos.create(actor,rule({TipoCodigo:'CATEGORIA',Productos:[pPct]})),57102);
 await reject(()=>promos.create(actor,rule({VigenteHasta:new Date(now()-1000),Productos:[pPct]})),57102);
 await reject(()=>promos.create(actor,rule({Codigo:created.Codigo,Productos:[pPct]})),57106);
 pass('reglas fuera de condiciones autorizadas rechazadas (tipo, minimo, porcentaje, elegibilidad, vigencia, codigo)');

 // 5-6, 10. Venta con promocion vigente, sin promocion, IVA y total.
 const s1=await sell([{ProductoId:pPct,Cantidad:2,DescuentoPorcentaje:0},{ProductoId:pNone,Cantidad:1,DescuentoPorcentaje:0}]);
 assert.deepEqual([s1.Subtotal,s1.Descuento,s1.SubtotalNeto,s1.IVA,s1.Total],['300.00','20.00','280.00','33.60','313.60']);
 assert.equal(s1.MotivoDescuento,'Promoción');assert.equal(s1.Promociones.length,1);assert.equal(s1.Promociones[0].PromocionId,pct.PromocionId);
 assert.deepEqual(s1.Detalle.map(d=>[d.ProductoId,d.DescuentoPorcentaje,d.DescuentoMonto]),[[pPct,'10.00','20.00'],[pNone,'0.00','0.00']].sort((a,b)=>a[0]-b[0]));
 pass('venta con promocion vigente y linea sin promocion; IVA 12% sobre neto y total',{factura:s1.FacturaId,total:s1.Total});
 const s0=await sell([{ProductoId:pNone,Cantidad:2,DescuentoPorcentaje:0}]);
 assert.equal(s0.Total,'224.00');assert.equal(s0.Promociones.length,0);assert.equal(s0.MotivoDescuento,null);pass('venta sin promocion elegible: sin descuento ni aplicacion');
 const sDos=await sell([{ProductoId:p2x1,Cantidad:3,DescuentoPorcentaje:0}]);
 assert.deepEqual([sDos.Subtotal,sDos.Descuento,sDos.IVA,sDos.Total],['3000.00','999.90','240.01','2240.11']);
 assert.equal(sDos.Promociones[0].UnidadesBonificadas,1);assert.equal(sDos.Promociones[0].BeneficioTeorico,'1000.00');assert.equal(sDos.Promociones[0].DescuentoPorcentaje,'33.33');
 const sDos2=await sell([{ProductoId:p2x1,Cantidad:2,DescuentoPorcentaje:0}]);assert.equal(sDos2.Descuento,'1000.00');assert.equal(sDos2.Total,'1120.00');
 pass('2x1: FLOOR(cantidad/2) bonificadas; importe registrable sin superar el teorico',{tres:sDos.Descuento,dos:sDos2.Descuento});
 const sVol=await sell([{ProductoId:pVol,Cantidad:2,DescuentoPorcentaje:0}]),sVol3=await sell([{ProductoId:pVol,Cantidad:3,DescuentoPorcentaje:0}]);
 assert.equal(sVol.Descuento,'0.00');assert.equal(sVol3.Descuento,'22.50');assert.equal(sVol3.Total,'142.80');pass('volumen: no aplica bajo el minimo y aplica desde 3 unidades');
 const sCat=await sell([{ProductoId:pCat,Cantidad:1,DescuentoPorcentaje:0}]);assert.equal(sCat.Descuento,'16.00');assert.equal(sCat.Promociones[0].PromocionId,catPromo.PromocionId);pass('categoria: producto asignado recibe la promocion');

 // 7-8. Futura y vencida.
 const pFut=await product(10),fut=await createActive({Nombre:'QA futura',Productos:[pFut],VigenteDesde:new Date(now()+5*day),VigenteHasta:new Date(now()+9*day)});
 assert.equal(fut.Estado,'PROGRAMADA');assert.equal((await sell([{ProductoId:pFut,Cantidad:1,DescuentoPorcentaje:0}])).Descuento,'0.00');pass('venta con promocion futura (PROGRAMADA) no aplica');
 const pExp=await product(10),exp=await createActive({Nombre:'QA por vencer',Productos:[pExp],VigenteDesde:new Date(now()-day),VigenteHasta:new Date(now()+2500)});
 assert.equal((await sell([{ProductoId:pExp,Cantidad:1,DescuentoPorcentaje:0}])).Descuento,'10.00');await delay(3000);
 assert.equal((await sell([{ProductoId:pExp,Cantidad:1,DescuentoPorcentaje:0}])).Descuento,'0.00');
 assert.equal((await promos.detail(actor,exp.PromocionId)).promocion.Estado,'VENCIDA');
 const expVersion=(await promos.detail(actor,exp.PromocionId)).promocion.Version;
 await reject(()=>promos.update(actor,exp.PromocionId,{...rule({Productos:[pExp]}),Version:expVersion}),57108);
 await reject(()=>promos.setState(actor,exp.PromocionId,{Activa:true,Version:expVersion,OperacionId:randomUUID(),Motivo:'Reactivar vencida'}),57108);
 pass('promocion vencida: deja de aplicar y no se edita');

 // 9, 11. Dos reglas elegibles: mejor descuento; sin doble descuento con manual.
 const pBoth=await product(40,'200.00');
 const a5=await createActive({Nombre:'QA 5%',Porcentaje:'5.00',Productos:[pBoth]});
 const v12=await createActive({Nombre:'QA volumen 12%',TipoCodigo:'VOLUMEN',Porcentaje:'12.00',CantidadMinima:2,Productos:[pBoth]});
 const two=await sell([{ProductoId:pBoth,Cantidad:2,DescuentoPorcentaje:0}]);
 assert.equal(two.Promociones.length,1);assert.equal(two.Promociones[0].PromocionId,v12.PromocionId);assert.equal(two.Descuento,'48.00');assert.equal(two.IVA,'42.24');assert.equal(two.Total,'394.24');
 const one=await sell([{ProductoId:pBoth,Cantidad:1,DescuentoPorcentaje:0}]);assert.equal(one.Promociones[0].PromocionId,a5.PromocionId);assert.equal(one.Descuento,'10.00');
 pass('dos reglas elegibles: se elige el mayor descuento monetario (volumen 12% > 5%)');
 const tieP=await product(10),t1=await createActive({Nombre:'QA empate A',Porcentaje:'10.00',Productos:[tieP]}),t2=await createActive({Nombre:'QA empate B',TipoCodigo:'VOLUMEN',Porcentaje:'10.00',CantidadMinima:2,Productos:[tieP]});
 assert.equal((await sell([{ProductoId:tieP,Cantidad:2,DescuentoPorcentaje:0}])).Promociones[0].PromocionId,Math.min(t1.PromocionId,t2.PromocionId));pass('empate determinista: gana la regla mas antigua');
 const manualWins=await sell([{ProductoId:pBoth,Cantidad:2,DescuentoPorcentaje:20}],{motivo:'Ajuste comercial'});
 assert.equal(manualWins.Descuento,'80.00');assert.equal(manualWins.Promociones.length,0);assert.equal(manualWins.MotivoDescuento,'Ajuste comercial');
 const promoWins=await sell([{ProductoId:pBoth,Cantidad:2,DescuentoPorcentaje:5}],{motivo:'Cliente frecuente'});
 assert.equal(promoWins.Descuento,'48.00');assert.equal(promoWins.Promociones[0].DescuentoManualDescartado,'5.00');assert.equal(promoWins.MotivoDescuento,'Promoción');
 const ledger=(await lab.labJson(`SELECT f.DescuentoTotal,(SELECT SUM(DescuentoMonto) FROM dbo.DetalleFactura WHERE FacturaId=f.FacturaId) Lineas,(SELECT COUNT(*) FROM dbo.P3_PRO_AplicacionFactura WHERE FacturaId=f.FacturaId) Apps FROM dbo.Factura f WHERE f.FacturaId=${promoWins.FacturaId}`))[0];
 assert.deepEqual(ledger,{DescuentoTotal:48,Lineas:48,Apps:1});
 pass('sin descuento doble: por linea gana el mayor entre manual y promocion, nunca la suma');

 // Superposicion del mismo tipo.
 const dup=await promos.create(actor,rule({Nombre:'QA duplicada',Porcentaje:'7.00',Productos:[pBoth]}));
 await reject(()=>promos.setState(actor,dup.PromocionId,{Activa:true,Version:dup.Version,OperacionId:randomUUID(),Motivo:'x'}),57109);pass('superposicion del mismo tipo y producto rechazada');

 // 12-14. Factura historica, cambios posteriores, reintentos.
 const histOp=randomUUID(),hist=await sell([{ProductoId:pPct,Cantidad:3,DescuentoPorcentaje:0}],{op:histOp});
 const before=await invoiceSnapshot(hist.FacturaId),receipt=await facturas.detail(actor,hist.FacturaId);
 assert.equal(receipt.factura.Total,hist.Total);assert.equal((await promos.invoiceApplications(actor,hist.FacturaId))[0].Codigo,pct.Codigo);
 pass('factura historica y comprobante conservan la promocion aplicada');
 let current=(await promos.detail(actor,pct.PromocionId)).promocion;
 await reject(()=>promos.update(actor,pct.PromocionId,{...rule({Productos:[pPct],Porcentaje:'30.00',VigenteDesde:current.VigenteDesde,VigenteHasta:current.VigenteHasta}),Version:current.Version}),57108);
 const renamed=await promos.update(actor,pct.PromocionId,{...rule({Nombre:'QA 10% renombrada',Productos:[pPct],VigenteDesde:current.VigenteDesde,VigenteHasta:current.VigenteHasta}),Version:current.Version});
 await reject(()=>promos.update(actor,pct.PromocionId,{...rule({Nombre:'otra',Productos:[pPct],VigenteDesde:current.VigenteDesde,VigenteHasta:current.VigenteHasta}),Version:current.Version}),57107);
 await promos.setState(actor,pct.PromocionId,{Activa:false,Version:renamed.Version,OperacionId:randomUUID(),Motivo:'Fin de campana QA'});
 await assert.rejects(()=>lab.labQuery(`UPDATE dbo.P3_PRO_Promocion SET Porcentaje=50 WHERE PromocionId=${pct.PromocionId};`),/57104/);
 await assert.rejects(()=>lab.labQuery(`DELETE dbo.P3_PRO_PromocionProducto WHERE PromocionId=${pct.PromocionId};`),/57104/);
 await assert.rejects(()=>lab.labQuery(`UPDATE dbo.P3_PRO_AplicacionFactura SET DescuentoMonto=DescuentoMonto WHERE FacturaId=${hist.FacturaId};`),/57103/);
 await assert.rejects(()=>lab.labQuery(`DELETE dbo.P3_PRO_Promocion WHERE PromocionId=${pct.PromocionId};`),/57103|547/);
 assert.deepEqual(await invoiceSnapshot(hist.FacturaId),before);
 assert.equal((await sell([{ProductoId:pPct,Cantidad:3,DescuentoPorcentaje:0}])).Descuento,'0.00');
 const hp=(await promos.detail(actor,pct.PromocionId)).historial;assert.deepEqual(hp.map(h=>h.Accion),['DESACTIVAR','EDITAR','ACTIVAR','CREAR']);
 assert.equal(hp[1].CamposModificados,'Nombre');assert.match(hp[1].ValorAnterior,/QA 10% porcentual/);assert.match(hp[1].ValorNuevo,/renombrada/);
 pass('cambiar y desactivar la regla tras la venta: factura pasada intacta (SHA/valores), historial anterior/nuevo y triggers de proteccion');
 const beforeRetry=await counts(),retry=await sell([{ProductoId:pPct,Cantidad:3,DescuentoPorcentaje:0}],{op:histOp});
 assert.equal(retry.FacturaId,hist.FacturaId);assert.equal(retry.Total,hist.Total);assert.deepEqual(retry.Promociones,hist.Promociones);assert.deepEqual(await counts(),beforeRetry);
 await reject(()=>sell([{ProductoId:pPct,Cantidad:3,DescuentoPorcentaje:0}],{op:histOp,promo:false}),54803);
 await reject(()=>sell([{ProductoId:pPct,Cantidad:2,DescuentoPorcentaje:0}],{op:histOp}),54803);
 pass('reintento con promocion ya desactivada devuelve el mismo comprobante; otra carga o modo con la misma referencia se rechaza');

 // 15. Concurrencia.
 const raceP=await product(5,'100.00');await createActive({Nombre:'QA concurrencia',Porcentaje:'10.00',Productos:[raceP]});
 const race=await Promise.allSettled(Array.from({length:8},()=>sell([{ProductoId:raceP,Cantidad:1,DescuentoPorcentaje:0}])));
 const ok=race.filter(r=>r.status==='fulfilled');assert.equal(ok.length,5);assert.ok(race.filter(r=>r.status==='rejected').every(r=>r.reason.number===52010));
 assert.ok(ok.every(r=>r.value.Total==='100.80'&&r.value.Promociones.length===1));assert.equal(await stock(raceP),0);
 const sameOp=randomUUID(),sameP=await product(5);await createActive({Nombre:'QA misma referencia',Porcentaje:'10.00',Productos:[sameP]});
 const same=await Promise.all([1,2,3].map(()=>sell([{ProductoId:sameP,Cantidad:1,DescuentoPorcentaje:0}],{op:sameOp})));
 assert.equal(new Set(same.map(s=>s.FacturaId)).size,1);assert.equal(await stock(sameP),4);
 pass('concurrencia: 8 ventas por 5 unidades => 5 facturas con promocion y stock 0; misma referencia simultanea => una factura');
 const lockP=await product(5);const lockPromo=await createActive({Nombre:'QA bloqueo reglas',Porcentaje:'10.00',Productos:[lockP]});
 const tx=new sql.Transaction(pool);await tx.begin();
 await new sql.Request(tx).query("DECLARE @r INT; EXEC @r=sys.sp_getapplock @Resource=N'P3.PRO.Reglas',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=5000; IF @r<0 THROW 57199,'lock',1;");
 let settled=false;const blocked=sell([{ProductoId:lockP,Cantidad:1,DescuentoPorcentaje:0}]).finally(()=>{settled=true;});
 await delay(1200);assert.equal(settled,false,'La venta espera el bloqueo de reglas');
 const lockVersion=(await promos.detail(actor,lockPromo.PromocionId)).promocion.Version;
 await new sql.Request(tx).input('ActorUsuarioId',sql.Int,actor).input('PromocionId',sql.Int,lockPromo.PromocionId).input('VersionEsperada',sql.Binary(8),Buffer.from(lockVersion,'hex')).input('Activa',sql.Bit,false).input('OperacionId',sql.UniqueIdentifier,randomUUID()).input('Motivo',sql.NVarChar(250),'Desactivacion concurrente QA').execute('dbo.P3_PRO_CambiarEstado');
 await tx.commit();const afterLock=await blocked;assert.equal(afterLock.Descuento,'0.00');assert.equal(afterLock.Promociones.length,0);
 pass('desactivacion concurrente: la venta espera la regla y factura con el estado confirmado, sin mezcla');

 // 16. Usuario sin autorizacion (cajero): vende con promociones, no administra reglas.
 await lab.labQuery(`DECLARE @N NVARCHAR(50)=CONCAT(N'QA_PRO_CAJ_',LEFT(REPLACE(CONVERT(VARCHAR(36),NEWID()),'-',''),12)); INSERT dbo.Usuario(NombreUsuario,NombreCompleto,Correo,PasswordHash) VALUES(@N,N'QA Cajero promociones',CONCAT(@N,N'@example.invalid'),CRYPT_GEN_RANDOM(64)); INSERT dbo.Usuario_Rol(UsuarioId,RolId) SELECT SCOPE_IDENTITY(),RolId FROM dbo.Rol WHERE Nombre=N'Cajero';`);
 const cajero=(await lab.labJson(`SELECT TOP(1) UsuarioId FROM dbo.Usuario WHERE NombreUsuario LIKE N'QA[_]PRO[_]CAJ%' ORDER BY UsuarioId DESC`))[0].UsuarioId;
 await reject(()=>promos.create(cajero,rule({Productos:[pPct]})),54101);
 await reject(()=>promos.update(cajero,a5.PromocionId,{...rule({Productos:[pBoth]}),Version:'0000000000000000'}),54101);
 await reject(()=>promos.setState(cajero,a5.PromocionId,{Activa:false,Version:'0000000000000000',OperacionId:randomUUID(),Motivo:'x'}),54101);
 await reject(()=>promos.list(cajero,{pagina:1}),54101);await reject(()=>promos.createCategory(cajero,{Nombre:'x',OperacionId:randomUUID(),Motivo:'x'}),54101);
 await reject(()=>pool.request().query('SELECT TOP(1) * FROM dbo.P3_PRO_Promocion'),229);
 await reject(()=>pool.request().query('SELECT dbo.fn_ObtenerDescuentoPromocional(1,NULL,1,1,SYSUTCDATETIME())'),229);
 await reject(()=>pool.request().query('EXEC dbo.sp_ProcesarVentaTransaccional'),229);
 const cajeroSale=await sell([{ProductoId:pBoth,Cantidad:2,DescuentoPorcentaje:0}],{who:cajero});assert.equal(cajeroSale.Descuento,'48.00');
 await reject(()=>sell([{ProductoId:pBoth,Cantidad:2,DescuentoPorcentaje:15}],{who:cajero,motivo:'Otro'}),52012);
 pass('usuario sin autorizacion: cajero no consulta ni cambia reglas; DML y funcion directa denegados; vende con la regla autorizada y su tope manual 10%');

 // 17. Cotizacion convertida: sin reevaluar promociones ni doble descuento.
 const cot=createCotizacionService(),quoteP=await product(10,'100.00');await createActive({Nombre:'QA promo y cotizacion',Porcentaje:'25.00',Productos:[quoteP]});
 const q=await cot.create(actor,{ClienteId:client.ClienteId,VenceEn:new Date(now()+day),OperacionId:randomUUID(),Observaciones:'QA PRO',Detalle:[{ProductoId:quoteP,Cantidad:2,DescuentoPorcentaje:10}]});
 const conv=await cot.convert(actor,q.CotizacionId,randomUUID());
 assert.equal(conv.factura.Total,'201.60');assert.equal((await lab.labJson(`SELECT COUNT(*) N FROM dbo.P3_PRO_AplicacionFactura WHERE FacturaId=${conv.documento.FacturaId}`))[0].N,0);
 const q2=await cot.create(actor,{ClienteId:client.ClienteId,VenceEn:new Date(now()+day),OperacionId:randomUUID(),Detalle:[{ProductoId:quoteP,Cantidad:1,DescuentoPorcentaje:0}]});
 const t=new sql.Table('dbo.TipoDetalleVentaDescuento');t.columns.add('ProductoId',sql.Int,{nullable:false});t.columns.add('Cantidad',sql.Int,{nullable:false});t.columns.add('DescuentoPorcentaje',sql.Decimal(5,2),{nullable:false});t.rows.add(quoteP,1,0);
 await reject(()=>pool.request().input('ClienteId',sql.Int,client.ClienteId).input('UsuarioId',sql.Int,actor).input('Detalle',t).input('OperacionId',sql.UniqueIdentifier,randomUUID()).input('MotivoDescuento',sql.NVarChar(80),null).input('P3CotizacionId',sql.Int,q2.CotizacionId).input('P3AplicarPromociones',sql.Bit,true).execute('dbo.sp_ERP_ProcesarVenta'),57111);
 pass('cotizacion convertida conserva el pacto (Q201.60) sin aplicar la promocion de 25%; combinacion cotizacion+promocion rechazada');

 // 18. ROLLBACK ante error posterior a Factura y aplicacion.
 const rbP=await product(3);await createActive({Nombre:'QA rollback',Porcentaje:'10.00',Productos:[rbP]});
 const rbOp=randomUUID(),rbBefore=await counts();
 await lab.labQuery(`GO\nCREATE OR ALTER TRIGGER dbo.P3_PRO_QA_FalloKardex ON dbo.Kardex_Inventario AFTER INSERT AS BEGIN IF EXISTS(SELECT 1 FROM inserted WHERE ProductoId=${rbP} AND TipoMovimiento='VENTA') THROW 57198,'QA falla despues de Factura y aplicacion',1; END;`);
 try{await reject(()=>sell([{ProductoId:rbP,Cantidad:1,DescuentoPorcentaje:0}],{op:rbOp}),57198);}finally{await lab.labQuery('DROP TRIGGER dbo.P3_PRO_QA_FalloKardex;');}
 assert.deepEqual(await counts(),rbBefore);assert.equal(await stock(rbP),3);
 const rbOk=await sell([{ProductoId:rbP,Cantidad:1,DescuentoPorcentaje:0}],{op:rbOp});assert.equal(rbOk.Promociones.length,1);
 pass('ROLLBACK: error en Kardex revierte factura, detalle, aplicacion, caja y stock; la misma referencia se recupera');

 // Vista previa coincide con la venta definitiva.
 const pv=await promos.preview(actor,[{ProductoId:pBoth,Cantidad:2,DescuentoPorcentaje:0},{ProductoId:p2x1,Cantidad:3,DescuentoPorcentaje:0}]);
 const real=await sell([{ProductoId:pBoth,Cantidad:2,DescuentoPorcentaje:0},{ProductoId:p2x1,Cantidad:3,DescuentoPorcentaje:0}]);
 assert.deepEqual([pv.totales.Subtotal,pv.totales.Descuento,pv.totales.IVA,pv.totales.Total],[real.Subtotal,real.Descuento,real.IVA,real.Total]);
 pass('vista previa SQL coincide con importes definitivos',{total:real.Total});

 // Funcion escalar obligatoria y repetibilidad.
 const fn=(await lab.labJson(`SELECT dbo.fn_ObtenerDescuentoPromocional(${p2x1},NULL,3,1000.00,SYSUTCDATETIME()) Tres,dbo.fn_ObtenerDescuentoPromocional(${p2x1},NULL,1,1000.00,SYSUTCDATETIME()) Uno,dbo.fn_ObtenerDescuentoPromocional(${pCat},${cat.CategoriaId},1,80.00,SYSUTCDATETIME()) Cat,dbo.fn_ObtenerDescuentoPromocional(${pCat},${cat.CategoriaId+1000},1,80.00,SYSUTCDATETIME()) CatAjena,dbo.fn_ObtenerDescuentoPromocional(${pFut},NULL,1,100.00,DATEADD(DAY,6,SYSUTCDATETIME())) Futura`))[0];
 assert.deepEqual(fn,{Tres:999.9,Uno:0,Cat:16,CatAjena:0,Futura:10});
 pass('dbo.fn_ObtenerDescuentoPromocional: parametros tipados, fecha de operacion, categoria y comparacion de beneficios',fn);
 const beforeReinstall=await counts();const keep=await invoiceSnapshot(hist.FacturaId);await lab.install();
 assert.deepEqual(await counts(),beforeReinstall);assert.deepEqual(await invoiceSnapshot(hist.FacturaId),keep);
 assert.equal((await sell([{ProductoId:pPct,Cantidad:3,DescuentoPorcentaje:0}],{op:histOp})).FacturaId,hist.FacturaId);
 pass('reinstalacion 60-63 repetible: datos, facturas e idempotencia conservados');
 await lab.labQuery('DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;');
 const constraints=await lab.labQuery('DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;');assert.doesNotMatch(constraints,/\|/);
 const consistency=(await lab.labJson('SELECT COUNT(*) N FROM dbo.P3_PRO_AplicacionFactura a JOIN dbo.DetalleFactura d ON d.DetalleFacturaId=a.DetalleFacturaId WHERE d.DescuentoMonto<>a.DescuentoMonto OR d.DescuentoPorcentaje<>a.DescuentoPorcentaje OR d.FacturaId<>a.FacturaId OR d.ProductoId<>a.ProductoId'))[0];
 assert.equal(consistency.N,0);pass('CHECKDB, CHECKCONSTRAINTS y aplicaciones consistentes con DetalleFactura');
 fs.mkdirSync('.data',{recursive:true});
 const output={lab:state.lab,fecha:new Date().toISOString(),cuentaAplicacion:state.login,pruebas:results.length,resultados:results};
 fs.writeFileSync('.data/promociones-sql.json',JSON.stringify(output,null,2));
 console.log('PROMOCIONES SQL COMPLETE: '+results.length+' PASS');
 }finally{await closePool();}
}
run().catch(e=>{console.error('PROMOCIONES SQL FAIL',e.number||e.code||e.name,e.message,e.stack);process.exitCode=1;});
