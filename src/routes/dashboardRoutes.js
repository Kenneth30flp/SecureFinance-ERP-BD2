'use strict';
const express = require('express');
const { requireAuth } = require('../middleware/authMiddleware');
const { createDashboardController } = require('../controllers/dashboardController');
function createDashboardRoutes(service) {
  const router = express.Router();
  router.get('/dashboard', requireAuth, (req, res, next) => { res.set('Cache-Control', 'no-store'); next(); },
    createDashboardController(service).mostrar);
  return router;
}
module.exports = { createDashboardRoutes };
