'use strict';
// Only synthetic UI/service data. No SQL connection is created.
const permissions=['COMPRAS_CONSULTAR','COMPRAS_CREAR','COMPRAS_APROBAR','COMPRAS_CANCELAR','COMPRAS_RECIBIR','INVENTARIO_REGISTRAR','PROVEEDORES_CONSULTAR','PRODUCTOS_CONSULTAR'];
function mockCompras(){
 const calls=[];
 const orden={OrdenCompraId:7,Numero:'OC-7',ProveedorId:2,ProveedorNombre:'Suministros del Altiplano · DEMO',ProveedorNIT:'DEMO-001',CreadorUsuarioId:1,Creador:'Comprador DEMO',FechaCreacion:'2026-10-28T15:00:00Z',Observaciones:'Entregar en horario de atención. Documento de demostración.',Total:'2200.0000',Estado:'APROBADA',Version:'0000000000000001'};
 const detalle=[{ProductoId:3,SKU:'DEMO-03',Descripcion:'Kit de conexiones y accesorios de oficina',Cantidad:20,Recibido:'0',Pendiente:'20',CostoUnitario:'110.0000',Subtotal:'2200.0000'}],recepciones=[];
 const historial=[{EstadoNuevo:'BORRADOR',Motivo:'Solicitud documentada',ActorUsuarioId:1,FechaHora:orden.FechaCreacion},{EstadoNuevo:'PENDIENTE_APROBACION',Motivo:'Revisión de condiciones comerciales',ActorUsuarioId:1,FechaHora:orden.FechaCreacion},{EstadoNuevo:'APROBADA',Motivo:'Presupuesto autorizado',ActorUsuarioId:42,FechaHora:orden.FechaCreacion}];
 const action=(name,state)=>async(actor,data)=>{calls.push([name,actor,data]);orden.Estado=state;return{OrdenCompraId:7,Numero:'OC-7',Estado:state,OperacionId:data.OperacionId,Version:orden.Version};};
 const service={list:async(actor,f)=>{calls.push(['list',actor,f]);return[{...orden}];},detail:async()=>({orden:{...orden},detalle,recepciones}),history:async()=>historial,
 create:action('create','BORRADOR'),send:action('send','PENDIENTE_APROBACION'),approve:action('approve','APROBADA'),cancel:action('cancel','CANCELADA'),
 receive:async(actor,data)=>{calls.push(['receive',actor,data]);const q=data.Detalle[0].Cantidad;detalle[0].Recibido=String(Number(detalle[0].Recibido)+q);detalle[0].Pendiente=String(20-Number(detalle[0].Recibido));orden.Estado=Number(detalle[0].Pendiente)?'PARCIALMENTE_RECIBIDA':'RECIBIDA';recepciones.push({DocumentoRespaldo:data.DocumentoRespaldo,FechaHora:orden.FechaCreacion,Descripcion:detalle[0].Descripcion,Cantidad:q,CostoDocumentado:data.Detalle[0].CostoUnitario,Motivo:data.Motivo,Actor:'Operador DEMO',RecepcionId:'1',KardexId:'1'});return{OrdenCompraId:7,Estado:orden.Estado,Version:orden.Version,OperacionId:data.OperacionId};},
 search:async(actor,clase,provider,q,page)=>{calls.push(['search',actor,clase,provider,q,page]);return{rows:clase==='proveedores'?[{Id:2,Nombre:orden.ProveedorNombre,Referencia:'DEMO-001'}]:[{Id:3,Nombre:detalle[0].Descripcion,Referencia:'DEMO-03'}],pagina:page,next:false};},
 valuation:async()=>({producto:{ProductoId:3,Codigo:'DEMO-03',Descripcion:detalle[0].Descripcion,Stock:20,Promedio:'110.00000000',Valor:'2200.00000000',Completa:true,Actualizada:true},movimientos:[{KardexId:'1',TipoMovimiento:'COMPRA',Cantidad:20,StockResultante:20,CostoAplicado:'110.00000000',Promedio:'110.00000000',Valor:'2200.00000000',Completa:true,Razon:'Costos documentados · datos sintéticos',FechaHora:orden.FechaCreacion}]}),
 refreshValuation:async(actor,id)=>{calls.push(['refresh',actor,id]);return{ProductoId:id,Stock:20,Promedio:'110.00000000'};}};
 return{service,calls,orden,detalle};
}
module.exports={mockCompras,permissions};
