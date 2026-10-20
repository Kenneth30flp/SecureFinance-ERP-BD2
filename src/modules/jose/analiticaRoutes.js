'use strict';

const express = require('express');
const { requireAuth } = require('../../middleware/authMiddleware');
const { createAnaliticaController } = require('./analiticaController');

function createAnaliticaRoutes(service) {
  const router = express.Router();
  router.get('/analitica', requireAuth, (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    if (!req.session.usuario.permisos?.includes('ANALITICA_CONSULTAR')) {
      return res.status(403).type('text').send('No tienes permiso para consultar analítica ejecutiva.');
    }
    return next();
  }, createAnaliticaController(service).mostrar);
  return router;
}

module.exports = { createAnaliticaRoutes };
