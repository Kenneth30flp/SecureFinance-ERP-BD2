'use strict';
const express=require('express');
const {randomBytes,timingSafeEqual}=require('node:crypto');
const {requireAuth}=require('../../../middleware/authMiddleware');
const v=require('./validation');
function createBackupsRoutes(service) {
  const r=express.Router(),base='/dba/backups';
  const permit=p=>(req,res,next)=>req.session.usuario.permisos?.includes('DBA_BACKUPS_'+p)?next():res.status(403).json({error:'Acceso denegado.'});
  r.use(base,requireAuth,(req,res,next)=>{res.set('Cache-Control','no-store');req.session.backupsCsrf ||= randomBytes(32).toString('hex');next();});
  const fail=(res,e)=>res.status(e instanceof v.ValidationError?400:e.number===54101?403:503).json({error:e instanceof v.ValidationError?e.message:'Operación no disponible. Consulte el historial antes de reintentar.'});
  r.get(base,permit('CONSULTAR'),async(req,res)=>{try {res.render('dba/backups/index',{usuario:req.session.usuario,csrf:req.session.backupsCsrf,...await service.dashboard(req.session.usuario.usuarioId)});}catch(e){fail(res,e);}});
  r.post(base,permit('CONSULTAR'),(req,res,next)=>{
    const t=req.get('X-CSRF-Token');if(!/^[a-f0-9]{64}$/.test(t||'')||!timingSafeEqual(Buffer.from(t),Buffer.from(req.session.backupsCsrf)))return res.status(403).json({error:'Actualice la página.'}); next();
  },async(req,res)=>{
    try {
      const d={id:v.uuid(req.body?.id),type:req.body?.type};
      const permission=['PLAN','RESTORE'].includes(d.type)?'RESTAURAR':'EJECUTAR';
      if(!req.session.usuario.permisos?.includes('DBA_BACKUPS_'+permission))return res.status(403).json({error:'Acceso denegado.'});
      if(permission==='EJECUTAR')v.type(d.type);else if(d.type==='PLAN'){d.point=v.point(req.body.point);d.target=v.target(req.body.target);}else d.planId=v.uuid(req.body.planId);
      res.status(202).json(await service.submit(req.session.usuario.usuarioId,d));
    }catch(e){fail(res,e);}
  }); return r;
}
module.exports={createBackupsRoutes};
