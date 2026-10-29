'use strict';
const {randomUUID}=require('node:crypto');
const v=require('./validation');
const {money,labels}=require('./format');
function failure(res,error) {
  const messages={54101:'Tu cuenta no tiene autorización vigente.',55001:'El creador no puede aprobar su propia orden.',55002:'Revisa los datos de la operación.',55003:'La orden o la referencia cambió. Consulta el detalle antes de reenviar.',55004:'La orden, el proveedor, el producto o su relación comercial no están disponibles.',55005:'El estado de la orden no permite esta operación.',55006:'La cantidad supera el pendiente o el producto no pertenece a esta orden.',55007:'El inventario no concilia. Solicita revisión antes de valorar.',54110:'Inventario deshabilitado: requiere apertura y habilitación autorizadas.',54113:'Cantidad de inventario fuera de rango.',54407:'Stock y Kardex no concilian.',54803:'La referencia de recepción ya fue utilizada.'};
  const validation=error instanceof TypeError;
  const status=validation?400:[54101,55001].includes(error.number)?403:[55003,55005,55006,54110,54113,54407,54803,1205].includes(error.number)?409:error.number===55004?404:messages[error.number]?400:503;
  return res.status(status).json({error:validation?error.message:messages[error.number]||'No se pudo confirmar el resultado. Conserva la referencia y consulta antes de reenviar.',incierto:status===503});
}
function createComprasController(service) {
  const common=req=>({usuario:req.session.usuario,csrf:req.session.comprasCsrf,comMoney:money,labels,states:v.states});
  const action=method=>async(req,res)=>{try{
    const d={...req.body,OrdenCompraId:v.id(req.params.id)};
    const clean=method==='receive'?v.receive(d):v.transition(d);
    const documento=await service[method](req.session.usuario.usuarioId,{...clean,Version:d.Version});
    return res.json({documento,url:'/compras/'+documento.OrdenCompraId});
  }catch(error){return failure(res,error);}};
  return {
    async list(req,res){try{const f=v.filters(req.query),rows=await service.list(req.session.usuario.usuarioId,f);return res.render('compras/list',{...common(req),f,rows:rows.slice(0,50),next:rows.length>50});}catch(e){return failure(res,e);}},
    async form(req,res){return res.render('compras/new',{...common(req),operacionId:randomUUID()});},
    async create(req,res){try{const documento=await service.create(req.session.usuario.usuarioId,v.create(req.body));return res.status(201).json({documento,url:'/compras/'+documento.OrdenCompraId});}catch(e){return failure(res,e);}},
    async detail(req,res){try{
      const id=v.id(req.params.id),actor=req.session.usuario.usuarioId;
      const rp=v.filters({pagina:req.query.entregas}),hp=v.filters({pagina:req.query.historial});
      const data=await service.detail(actor,id,rp.offset);if(!data.orden)return res.status(404).send('Orden no encontrada.');
      const events=await service.history(actor,id,hp.offset);
      return res.render('compras/detail',{...common(req),...data,recepciones:data.recepciones.slice(0,50),historial:events.slice(0,50),recPage:rp.pagina,histPage:hp.pagina,recNext:data.recepciones.length>50,histNext:events.length>50,operacionId:randomUUID()});
    }catch(e){return failure(res,e);}},
    async search(req,res){try{const proveedor=req.query.proveedor===undefined?null:v.id(req.query.proveedor);return res.json(await service.search(req.session.usuario.usuarioId,req.params.clase,proveedor,v.text(req.query.q??'',150,true),req.query.pagina===undefined?1:v.id(req.query.pagina)));}catch(e){return failure(res,e);}},
    send:action('send'),approve:action('approve'),cancel:action('cancel'),receive:action('receive'),
    async valuation(req,res){try{const f=v.filters({pagina:req.query.pagina}),data=await service.valuation(req.session.usuario.usuarioId,v.id(req.params.id),f.offset);if(!data.producto)return res.status(404).send('Producto no encontrado.');return res.render('compras/valuation',{...common(req),...data,f,next:data.movimientos.length>50,movimientos:data.movimientos.slice(0,50)});}catch(e){return failure(res,e);}},
    async refresh(req,res){try{const producto=await service.refreshValuation(req.session.usuario.usuarioId,v.id(req.params.id));return res.json({producto,url:'/compras/valoracion/'+producto.ProductoId});}catch(e){return failure(res,e);}},
  };
}
module.exports={createComprasController,failure};
