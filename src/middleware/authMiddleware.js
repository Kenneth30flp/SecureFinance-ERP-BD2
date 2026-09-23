'use strict';

function requireAuth(req, res, next) {
  if (!req.session.usuario) return res.redirect('/login');
  return next();
}

function guestOnly(req, res, next) {
  if (req.session.usuario) return res.redirect('/dashboard');
  return next();
}

module.exports = { requireAuth, guestOnly };
