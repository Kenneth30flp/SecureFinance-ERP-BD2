'use strict';

const express = require('express');
const { requireAuth } = require('../middleware/authMiddleware');
const { createAuditoriaDdlController } = require('../controllers/auditoriaDdlController');

function createAuditoriaDdlRoutes(service) {
  const router = express.Router();
  const controller = createAuditoriaDdlController(service);
  router.use('/auditoria/ddl', (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    return next();
  }, requireAuth, (req, res, next) => {
    const usuario = req.session.usuario;
    if (!Number.isInteger(usuario.usuarioId) || usuario.usuarioId <= 0 || usuario.usuarioId > 2147483647
      || !Array.isArray(usuario.permisos) || !usuario.permisos.includes('AUDITORIA_DDL_CONSULTAR')) {
      return res.status(403).type('text').send('No tienes permiso para consultar Auditoria DDL.');
    }
    return next();
  });
  // Each procedure independently checks current SQL authorization before returning data.
  router.get('/auditoria/ddl', controller.list);
  router.get('/auditoria/ddl/:id', controller.detail);
  return router;
}

module.exports = { createAuditoriaDdlRoutes };
