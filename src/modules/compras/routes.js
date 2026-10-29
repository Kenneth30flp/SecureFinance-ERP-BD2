'use strict';
const express=require('express');
const {randomBytes,timingSafeEqual}=require('node:crypto');
const {requireAuth}=require('../../middleware/authMiddleware');
const {createComprasController}=require('./controller');
function createComprasRoutes(service) {
  const r=express.Router(),c=createComprasController(service);
  const permit=p=>(req,res,next)=>req.session.usuario.permisos?.includes(p)?next():res.status(403).json({error:'No tienes permiso para esta operación.'});
  const csrf=(req,res,next)=>{const value=req.get('X-CSRF-Token'),expected=req.session.comprasCsrf;if(typeof value!=='string'||!/^[a-f0-9]{64}$/.test(value)||typeof expected!=='string'||!/^[a-f0-9]{64}$/.test(expected)||!timingSafeEqual(Buffer.from(value),Buffer.from(expected)))return res.status(403).json({error:'Actualiza la página para renovar la protección de la operación.'});return next();};
  r.use('/compras',requireAuth,(req,res,next)=>{res.set('Cache-Control','no-store');req.session.comprasCsrf ||=randomBytes(32).toString('hex');next();});
  r.get('/compras',permit('COMPRAS_CONSULTAR'),c.list);
  r.get('/compras/nueva',permit('COMPRAS_CREAR'),c.form);
  r.get('/compras/buscar/:clase',permit('COMPRAS_CREAR'),c.search);
  r.get('/compras/valoracion/:id',permit('COMPRAS_CONSULTAR'),c.valuation);
  r.post('/compras/valoracion/:id/actualizar',permit('COMPRAS_CONSULTAR'),csrf,c.refresh);
  r.get('/compras/:id',permit('COMPRAS_CONSULTAR'),c.detail);
  r.post('/compras',permit('COMPRAS_CREAR'),csrf,c.create);
  r.post('/compras/:id/enviar',permit('COMPRAS_CREAR'),csrf,c.send);
  r.post('/compras/:id/aprobar',permit('COMPRAS_APROBAR'),csrf,c.approve);
  r.post('/compras/:id/cancelar',permit('COMPRAS_CANCELAR'),csrf,c.cancel);
  r.post('/compras/:id/recibir',permit('COMPRAS_RECIBIR'),permit('INVENTARIO_REGISTRAR'),csrf,c.receive);
  return r;
}
module.exports={createComprasRoutes};
