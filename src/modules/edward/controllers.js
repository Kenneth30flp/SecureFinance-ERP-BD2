'use strict';
const {randomBytes,randomUUID,timingSafeEqual}=require('node:crypto');
const v=require('./validations');
function csrf(req,res,next){
 const actual=req.get('X-CSRF-Token'),expected=req.session.edwardCsrf;
 if(typeof actual!=='string'||!/^[a-f0-9]{64}$/.test(actual)||typeof expected!=='string'||!timingSafeEqual(Buffer.from(actual),Buffer.from(expected)))return res.status(403).json({error:'La sesión del formulario expiró. Recarga la página.'});
 return next();
}
function failure(res,error){
 const known=new Map([[54101,'Tu permiso ya no está vigente.'],[54110,'El Kardex requiere apertura y habilitación autorizadas.'],[54104,'El producto no está disponible para reingreso.'],[54407,'El inventario requiere conciliación.'],[54602,'Revisa los datos de la solicitud.'],[54603,'El registro cambió o la referencia ya se utilizó con otros datos. Conserva tu borrador y recarga.'],[54604,'No existe la factura, el detalle o el ticket indicado.'],[54605,'La cantidad acumulada o el crédito supera la factura.'],[54606,'El estado o la cobertura no permiten esta operación.']]);
 return res.status(error.status|| (error.number===54101?403:error.number===54603?409:known.has(error.number)?400:503)).json({error:error.status?error.message:known.get(error.number)||'No fue posible confirmar el resultado. Reintenta con la misma referencia para evitar duplicados.'});
}
function createEdwardController(service){
 return {
 async show(req,res){
  const module=req.baseUrl.slice(1),actor=req.session.usuario.usuarioId;
  req.session.edwardCsrf ||=randomBytes(32).toString('hex');
  try{
   const f=v.filters(req.query);
   const [rows=[],details=[]]=module==='garantias'?await service.garantias(actor,f):await service.devoluciones(actor,f);
   const [invoices=[],lines=[]]=req.query.factura?await service.factura(actor,v.integer(req.query.factura),module==='garantias'):[[],[]];
   return res.render('edward/posventa',{usuario:req.session.usuario,module,csrf:req.session.edwardCsrf,f,query:req.query,rows:rows.slice(0,50),next:rows.length>50,details,invoice:invoices[0]||null,lines,operation:randomUUID(),states:v.states,error:req.query.factura&&!invoices.length?'Factura no encontrada.':null});
  }catch(error){
   if(error.status)return res.status(error.status).type('text').send(error.message);
   return res.status(error.number===54101?403:503).render('edward/unavailable',{usuario:req.session.usuario,module,csrf:req.session.edwardCsrf});
  }
 },
 async devolver(req,res){try{const result=await service.devolver(req.session.usuario.usuarioId,v.devolucion(req.body));return res.status(201).json({url:'/notas-credito?id='+result.DevolucionId});}catch(e){return failure(res,e);}},
 async crear(req,res){try{const b=req.body;const result=await service.crear(req.session.usuario.usuarioId,{DetalleFacturaId:v.integer(b.DetalleFacturaId),OperacionId:v.uuid(b.OperacionId),Motivo:v.text(b.Motivo,250)});return res.status(201).json({url:'/garantias?id='+result.TicketId});}catch(e){return failure(res,e);}},
 async actualizar(req,res){try{const b=req.body;const result=await service.actualizar(req.session.usuario.usuarioId,{TicketId:v.integer(req.params.id),Version:v.version(b.Version),Estado:v.state(b.Estado),Diagnostico:v.text(b.Diagnostico,2000),Evidencia:v.text(b.Evidencia||'',250,false)||null});return res.json({url:'/garantias?id='+result.TicketId});}catch(e){return failure(res,e);}},
 };
}
module.exports={createEdwardController,csrf};
