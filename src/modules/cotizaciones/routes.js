'use strict';
const express=require('express');
const {randomBytes,randomUUID,timingSafeEqual}=require('node:crypto');
const {requireAuth}=require('../../middleware/authMiddleware');
const v=require('./validation');
function fail(res,e) {
  const conversionErrors={54910:'La cotización está vencida. Emite una nueva propuesta.',54912:'Las condiciones no coinciden con la cotización. Consulta el documento antes de continuar.',52010:'Stock insuficiente. No se ha convertido la cotización.',54113:'Stock insuficiente para completar la conversión.',52006:'El cliente está inactivo.',52009:'Uno de los productos está inactivo.',52012:'El descuento pactado supera tu autorización vigente.',52013:'No tienes permiso vigente para registrar ventas.',54803:'La referencia corresponde a otra operación. Consulta el documento antes de reenviar.'};
  const messages={54902:'Revisa la vigencia (máximo 90 días), los productos y el descuento autorizado.',54903:'El documento o la referencia ya cambió. Consulta su estado antes de reenviar.',54904:'El cliente, producto o documento no existe o está inactivo.',54101:'No tienes autorización vigente para esta operación.'};
  const status=e instanceof v.ValidationError?400:[54101,52013].includes(e.number)?403:[54903,54910,54803,52010,54113,52006,52009].includes(e.number)?409:e.number===54904?404:[54902,54912,52012].includes(e.number)?400:503;
  return res.status(status).json({error:e instanceof v.ValidationError?e.message:conversionErrors[e.number]||messages[e.number]||'No fue posible confirmar el resultado. Conserva la referencia y consulta el historial antes de reenviar.',incierto:status===503});
}
function createCotizacionRoutes(service) {
  const r=express.Router();
  const permit=p=>(req,res,next)=>req.session.usuario.permisos?.includes(p)?next():res.status(403).json({error:'No tienes permiso para esta operación.'});
  const csrf=(req,res,next)=>{
    const token=req.get('X-CSRF-Token'),expected=req.session.cotizacionCsrf;
    if(typeof token!=='string'||!/^[a-f0-9]{64}$/.test(token)||typeof expected!=='string'||!timingSafeEqual(Buffer.from(token),Buffer.from(expected))) return res.status(403).json({error:'Actualiza la página e inténtalo nuevamente.'});
    return next();
  };
  r.use('/cotizaciones',requireAuth,(req,res,next)=>{res.set('Cache-Control','no-store');req.session.cotizacionCsrf ||=randomBytes(32).toString('hex');next();});
  r.get('/cotizaciones',permit('COTIZACIONES_CONSULTAR'),async(req,res)=>{
    try {const f=v.filters(req.query),all=await service.list(req.session.usuario.usuarioId,f);return res.render('cotizaciones/list',{usuario:req.session.usuario,csrf:req.session.cotizacionCsrf,f,rows:all.slice(0,20),next:all.length>20});}catch(e){return fail(res,e);}
  });
  r.get('/cotizaciones/nueva',permit('COTIZACIONES_CREAR'),async(req,res)=>{
    try {const data=await service.catalogs(req.session.usuario.usuarioId);return res.render('cotizaciones/new',{usuario:req.session.usuario,csrf:req.session.cotizacionCsrf,operacionId:randomUUID(),...data});}catch(e){return fail(res,e);}
  });
  r.post('/cotizaciones',permit('COTIZACIONES_CREAR'),csrf,async(req,res)=>{
    try {const d=v.creation(req.body),documento=await service.create(req.session.usuario.usuarioId,d);return res.status(201).json({documento,url:'/cotizaciones/'+documento.CotizacionId});}catch(e){return fail(res,e);}
  });
  r.get('/cotizaciones/:id',permit('COTIZACIONES_CONSULTAR'),async(req,res)=>{
    try {
      const id=v.integer(req.params.id),actor=req.session.usuario.usuarioId;
      const data=await service.detail(actor,id);if(!data.documento)return res.status(404).send('Cotización no encontrada.');
      const conversion=await service.readiness(actor,id);
      req.session.cotizacionConversionOps ||= {};
      if(!req.session.cotizacionConversionOps[id]){
        const keys=Object.keys(req.session.cotizacionConversionOps);if(keys.length>=100)delete req.session.cotizacionConversionOps[keys[0]];
        req.session.cotizacionConversionOps[id]=randomUUID();
      }
      return res.render('cotizaciones/detail',{usuario:req.session.usuario,csrf:req.session.cotizacionCsrf,operacionId:randomUUID(),conversionOperacion:req.session.cotizacionConversionOps[id],conversion,...data});
    }catch(e){return fail(res,e);}
  });
  r.post('/cotizaciones/:id/cancelar',permit('COTIZACIONES_CANCELAR'),csrf,async(req,res)=>{
    try {const reason=v.text(req.body?.Motivo,250);if(!reason.trim())throw new v.ValidationError('Indica el motivo de cancelación.');const documento=await service.cancel(req.session.usuario.usuarioId,v.integer(req.params.id),v.uuid(req.body?.OperacionId),reason);return res.json({documento});}catch(e){return fail(res,e);}
  });
  r.post('/cotizaciones/:id/convertir',permit('COTIZACIONES_CONVERTIR'),permit('VENTAS_REGISTRAR'),csrf,async(req,res)=>{
    try {
      if(['ModalidadPago','MedioPago','TipoPago','Credito','BodegaId'].some(k=>Object.hasOwn(req.body||{},k)))throw new v.ValidationError('Esta conversión admite únicamente contado e inventario global; no recibe modalidad ni bodega.');
      const id=v.integer(req.params.id),operation=v.uuid(req.body?.OperacionId);
      const result=await service.convert(req.session.usuario.usuarioId,id,operation);
      return res.json({...result,url:'/facturacion/facturas/'+result.documento.FacturaId,mensaje:'Cotización convertida a factura de contado correctamente.'});
    }catch(e){return fail(res,e);}
  });
  return r;
}
module.exports={createCotizacionRoutes};
