'use strict';

const express = require('express');
const { createAuthController } = require('../controllers/authController');
const { guestOnly } = require('../middleware/authMiddleware');

function createAuthRoutes(authService) {
  const router = express.Router();
  const controller = createAuthController(authService);
  router.use((req, res, next) => {
    res.set('Cache-Control', 'no-store');
    next();
  });
  router.get('/', (req, res) => res.redirect(req.session.usuario
    ? (req.session.usuario.debeCambiarPassword ? '/cambiar-password' : '/dashboard') : '/login'));
  router.get('/login', guestOnly, controller.showLogin);
  router.post('/login', guestOnly, controller.login);
  router.get('/logout', controller.logout);
  return router;
}

module.exports = { createAuthRoutes };
