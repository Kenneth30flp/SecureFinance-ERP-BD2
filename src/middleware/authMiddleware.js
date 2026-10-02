'use strict';

function requireSession(req, res, next) {
  if (!req.session.usuario) return res.redirect('/login');
  return next();
}

function requireAuth(req, res, next) {
  return requireSession(req, res, () => {
    if (req.session.usuario.debeCambiarPassword) return res.redirect('/cambiar-password');
    return next();
  });
}

function guestOnly(req, res, next) {
  if (req.session.usuario) return res.redirect(req.session.usuario.debeCambiarPassword ? '/cambiar-password' : '/dashboard');
  return next();
}

module.exports = { requireAuth, requireSession, guestOnly };
