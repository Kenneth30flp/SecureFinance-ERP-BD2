'use strict';

const express = require('express');
const { requireAuth } = require('../middleware/authMiddleware');
const { createAuditoriaController } = require('../controllers/auditoriaController');

function createAuditoriaRoutes(auditoriaService) {
  const router = express.Router();
  const controller = createAuditoriaController(auditoriaService);

  router.get('/auditoria', requireAuth, (req, res, next) => {
    const permisos = Array.isArray(req.session?.usuario?.permisos) ? req.session.usuario.permisos : [];
    if (!permisos.includes('AUDITORIA_CONSULTAR')) {
      return res.status(403).type('text').send('No tienes permiso para consultar auditoría.');
    }
    return next();
  }, controller.index);

  return router;
}

module.exports = { createAuditoriaRoutes };
