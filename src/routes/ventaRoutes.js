'use strict';

const express = require('express');
const { requireAuth } = require('../middleware/authMiddleware');
const { createVentaController } = require('../controllers/ventaController');
const { createFacturaController } = require('../controllers/facturaController');

function createVentaRoutes(ventaService, facturaService, promocionService = null) {
  const router = express.Router();
  const controller = createVentaController(ventaService);
  router.use('/facturacion', requireAuth, (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    return next();
  });
  const invoices = createFacturaController(facturaService, promocionService);
  const consult = (req,res,next) => req.session.usuario.permisos?.includes('FACTURAS_CONSULTAR') ? next() : res.status(403).type('text').send('No tienes permiso para consultar facturas.');
  const sell = (req,res,next) => {
    if (!req.session.usuario.permisos?.includes('VENTAS_REGISTRAR')) {
      return res.status(403).type('text').send('No tienes permiso para registrar ventas.');
    }
    return next();
  };
  router.get('/facturacion/historial',consult,invoices.list);
  router.get('/facturacion/facturas/:id',consult,invoices.detail);
  router.get('/facturacion',(req,res,next)=>!req.session.usuario.permisos?.includes('VENTAS_REGISTRAR')&&req.session.usuario.permisos?.includes('FACTURAS_CONSULTAR')?res.redirect('/facturacion/historial'):next(),sell,controller.mostrar);
  router.post('/facturacion/procesar',sell,controller.procesar);
  return router;
}

module.exports = { createVentaRoutes };
