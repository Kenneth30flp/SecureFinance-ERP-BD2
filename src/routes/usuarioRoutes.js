'use strict';
const express = require('express');
const { requireAuth } = require('../middleware/authMiddleware');
const { createUsuarioController } = require('../controllers/usuarioController');
function createUsuarioRoutes(service) {
  const router = express.Router();
  const controller = createUsuarioController(service);
  router.use('/usuarios', requireAuth, async (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    if (!req.session.usuario.permisos?.includes('USUARIOS_ADMINISTRAR'))
      return res.status(403).type('text').send('No tienes permiso para administrar usuarios.');
    try {
      // Revalidar en cada solicitud evita administrar con permisos de una sesión anterior al cambio.
      const permisos = await service.permisosActuales(req.session.usuario.usuarioId);
      if (!permisos.some(p => p.Codigo === 'USUARIOS_ADMINISTRAR'))
        return res.status(403).type('text').send('No tienes permiso para administrar usuarios.');
      return next();
    } catch { return res.status(503).type('text').send('No fue posible verificar tus permisos.'); }
  });
  router.get('/usuarios', controller.mostrar);
  router.get('/usuarios/:id/roles', controller.obtener);
  router.post('/usuarios/:id/roles', controller.actualizar);
  return router;
}
module.exports = { createUsuarioRoutes };
