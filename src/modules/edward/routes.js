'use strict';
const express=require('express');
const {requireAuth}=require('../../middleware/authMiddleware');
const {createEdwardController,csrf}=require('./controllers');
const permit=p=>(req,res,next)=>req.session.usuario.permisos?.includes(p)?next():res.status(403).type('text').send('No tienes permiso para esta operación.');
function createEdwardRoutes(service){
 const root=express.Router(),c=createEdwardController(service);
 for(const module of ['devoluciones','notas-credito','garantias']){
  const router=express.Router();
  router.use(requireAuth,(req,res,next)=>{res.set('Cache-Control','no-store');next();},permit(module==='garantias'?'GARANTIAS_CONSULTAR':'DEVOLUCIONES_CONSULTAR'));
  router.get('/',c.show);
  if(module==='notas-credito')router.post('/:id/aplicaciones',permit('NOTAS_CREDITO_APLICAR'),csrf,c.aplicar);
  if(module==='devoluciones')router.post('/',permit('DEVOLUCIONES_REGISTRAR'),permit('DEVOLUCIONES_AUTORIZAR'),csrf,c.devolver);
  if(module==='garantias'){router.post('/',permit('GARANTIAS_GESTIONAR'),csrf,c.crear);router.post('/:id/estado',permit('GARANTIAS_GESTIONAR'),csrf,c.actualizar);}
  root.use('/'+module,router);
 }
 return root;
}
module.exports={createEdwardRoutes};
