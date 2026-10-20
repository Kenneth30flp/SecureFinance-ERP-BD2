'use strict';
const express = require('express');
const { randomUUID } = require('node:crypto');
const { requireAuth } = require('../middleware/authMiddleware');
const { createKennethController, csrf, failure } = require('../controllers/kennethController');
const { reference } = require('../services/fotografiaService');
function permit(permission) {
  return (req,res,next) => req.session.usuario.permisos?.includes(permission) ? next() : res.status(403).json({error:'No tienes permiso para esta operación.'});
}
function createKennethRoutes(services) {
  const root = express.Router(), controller = createKennethController(services);
  for (const [module,read,write] of [['inventario','INVENTARIO_CONSULTAR',null],['productos','PRODUCTOS_CONSULTAR','PRODUCTOS_ADMINISTRAR'],['proveedores','PROVEEDORES_CONSULTAR','PROVEEDORES_ADMINISTRAR'],['clientes','CLIENTES_CONSULTAR',null]]) {
    const router = express.Router();
    router.use(requireAuth,(req,res,next)=>{res.set('Cache-Control','no-store');next();},permit(read));
    router.get('/',controller.show);
    if (write) {
      router.post('/',permit(write),csrf,controller.save);
      router.post('/:id',permit(write),csrf,(req,res,next)=>req.params.id==='fotografias'?next('route'):controller.save(req,res));
    }
    if (module === 'inventario') router.post('/movimientos',csrf,controller.move);
    if (module === 'clientes') {
      router.post('/',permit('CLIENTES_REGISTRAR'),csrf,controller.save);
      router.post('/:id/datos',permit('CLIENTES_EDITAR'),csrf,controller.save);
      for (const [action,p] of [['nit','CLIENTES_ACTUALIZAR_NIT'],['inactivar','CLIENTES_INACTIVAR']]) router.post(`/:id/${action}`,permit(p),csrf,(req,res)=>{req.params.action=action;return controller.client(req,res);});
    }
    if (module === 'productos') {
      router.get('/proveedores',permit('PROVEEDORES_CONSULTAR'),controller.suppliers);
      router.post('/fotografias',permit(write),csrf,express.raw({type:['image/png','image/jpeg'],limit:'3mb'}),async(req,res)=>{
        try {
          await services.productos.list(req.session.usuario.usuarioId,{costo:true});
          req.session.pendingPhotos ||= {};
          for (const [key,pending] of Object.entries(req.session.pendingPhotos)) if(pending.expires<Date.now()){await services.photos.remove(pending.ref);delete req.session.pendingPhotos[key];}
          if(Object.keys(req.session.pendingPhotos).length>=3) return res.status(409).json({error:'Cancela las cargas anteriores antes de añadir otra fotografía.'});
          const ref=await services.photos.upload(req.body,req.get('X-File-Name'),req.get('Content-Type'));
          const token=randomUUID();
          req.session.pendingPhotos[token]={ref,expires:Date.now()+30*60*1000};
          return res.status(201).json({token,url:'/fotografias/'+ref});
        }catch(e){return failure(res,e);}
      });
      router.delete('/fotografias/:token',permit(write),csrf,async(req,res)=>{
        try{const p=req.session.pendingPhotos?.[req.params.token];if(p){await services.photos.remove(p.ref);delete req.session.pendingPhotos[req.params.token];}return res.sendStatus(204);}catch(e){return failure(res,e);}
      });
    }
    root.use('/'+module,router);
  }
  root.get('/fotografias/:reference',requireAuth,async(req,res)=>{
    res.set({'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'; sandbox"});
    const p=req.session.usuario.permisos || [];
    if(!p.includes('PRODUCTOS_CONSULTAR')&&!p.includes('INVENTARIO_CONSULTAR')) return res.sendStatus(403);
    if(!reference.test(req.params.reference)) return res.sendStatus(404);
    try{
      await services.productos.list(req.session.usuario.usuarioId,{inventario:!p.includes('PRODUCTOS_CONSULTAR')});
      const data=await services.photos.read(req.params.reference);
      return res.type(req.params.reference.endsWith('.png')?'image/png':'image/jpeg').send(data);
    }catch{return res.sendStatus(404);}
  });
  return root;
}
module.exports={createKennethRoutes};
