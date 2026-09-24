'use strict';

const express = require('express');
const { requireAuth } = require('../middleware/authMiddleware');
const { createVentaController } = require('../controllers/ventaController');

function createVentaRoutes(ventaService) {
  const router = express.Router();
  const controller = createVentaController(ventaService);
  router.use('/facturacion', requireAuth, (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    if (!req.session.usuario.permisos?.includes('VENTAS_REGISTRAR')) {
      return res.status(403).type('text').send('No tienes permiso para registrar ventas.');
    }
    return next();
  });
  router.get('/facturacion', controller.mostrar);
  router.post('/facturacion/procesar', controller.procesar);
  return router;
}

module.exports = { createVentaRoutes };
