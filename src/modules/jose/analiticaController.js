'use strict';

const { filters, AnalyticsValidationError } = require('./analiticaValidation');

function createAnaliticaController(service) {
  return {
    async mostrar(req, res) {
      let filtros;
      try {
        filtros = filters(req.query);
      } catch (error) {
        const safe = error instanceof AnalyticsValidationError ? error : new AnalyticsValidationError('Filtros inválidos.');
        return res.status(safe.status).render('analitica', {
          usuario: req.session.usuario, filtros: { modo: 'MENSUAL', pagina: 1 }, dashboard: null,
          error: safe.message, actual: 'analitica', rolesCuenta: '',
        });
      }
      try {
        const dashboard = await service.obtenerDashboard(req.session.usuario.usuarioId, filtros);
        return res.render('analitica', {
          usuario: req.session.usuario, filtros, dashboard, error: null,
          actual: 'analitica', rolesCuenta: '',
        });
      } catch (error) {
        const status = [56011, 56012, 56013].includes(error.number) ? 400 : error.number === 54101 ? 403 : 503;
        return res.status(status).render('analitica', {
          usuario: req.session.usuario, filtros, dashboard: null,
          error: status === 403 ? 'No tienes permiso para consultar esta analítica.' : 'La analítica no está disponible en este momento.',
          actual: 'analitica', rolesCuenta: '',
        });
      }
    },
  };
}

module.exports = { createAnaliticaController };
