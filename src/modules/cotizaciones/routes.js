'use strict';
const express=require('express');
const {randomBytes,randomUUID,timingSafeEqual}=require('node:crypto');
const {requireAuth}=require('../../middleware/authMiddleware');
const v=require('./validation');
function fail(res,e) {
  const messages={54902:'Revisa la vigencia (máximo 90 días), los productos y el descuento autorizado.',54903:'El documento o la referencia ya cambió. Consulta su estado antes de reenviar.',54904:'El cliente, producto o documento no existe o está inactivo.',54101:'No tienes autorización vigente para esta operación.'};
  const status=e instanceof v.ValidationError?400:e.number===54101?403:e.number===54903?409:e.number===54904?404:e.number===54902?400:503;
  return res.status(status).json({error:e instanceof v.ValidationError?e.message:messages[e.number]||'No fue posible confirmar el resultado. Conserva la referencia y consulta el historial antes de reenviar.'});
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
    try {const data=await service.detail(req.session.usuario.usuarioId,v.integer(req.params.id));if(!data.documento)return res.status(404).send('Cotización no encontrada.');return res.render('cotizaciones/detail',{usuario:req.session.usuario,csrf:req.session.cotizacionCsrf,operacionId:randomUUID(),...data});}catch(e){return fail(res,e);}
  });
  r.post('/cotizaciones/:id/cancelar',permit('COTIZACIONES_CANCELAR'),csrf,async(req,res)=>{
    try {const reason=v.text(req.body?.Motivo,250);if(!reason.trim())throw new v.ValidationError('Indica el motivo de cancelación.');const documento=await service.cancel(req.session.usuario.usuarioId,v.integer(req.params.id),v.uuid(req.body?.OperacionId),reason);return res.json({documento});}catch(e){return fail(res,e);}
  });
  // UC09 no se expone hasta aprobar e instalar la extension del motor real.
  return r;
}
module.exports={createCotizacionRoutes};
