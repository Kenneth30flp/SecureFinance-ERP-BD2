'use strict';

const express = require('express');
const { guestOnly, requireSession } = require('../middleware/authMiddleware');
const { createPasswordController } = require('../controllers/passwordController');

function createPasswordRoutes(service, options) {
  const router = express.Router();
  const controller = createPasswordController(service, options);
  router.use(['/recuperar-password', '/restablecer-password', '/cambiar-password'], (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    res.set('Referrer-Policy', 'no-referrer');
    res.set('X-Robots-Tag', 'noindex, nofollow');
    next();
  });
  router.get('/recuperar-password', guestOnly, controller.mostrarRecuperacion);
  router.post('/recuperar-password', guestOnly, controller.solicitar);
  router.get('/restablecer-password', guestOnly, controller.mostrarRestablecimiento);
  router.post('/restablecer-password', guestOnly, controller.restablecer);
  // Disponible también durante el cambio obligatorio; requireAuth bloquearía esa misma pantalla.
  router.get('/cambiar-password', requireSession, controller.mostrarCambio);
  router.post('/cambiar-password', requireSession, controller.cambiar);
  return router;
}

module.exports = { createPasswordRoutes };
