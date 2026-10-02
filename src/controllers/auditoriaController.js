'use strict';

function createAuditoriaController(auditoriaService) {
  return {
    async index(req, res) {
      if (!req.session?.usuario) return res.redirect('/login');
      const permisos = Array.isArray(req.session.usuario.permisos) ? req.session.usuario.permisos : [];
      if (!permisos.includes('AUDITORIA_CONSULTAR')) {
        return res.status(403).type('text').send('No tienes permiso para consultar auditoría.');
      }

      const vista = ['acceso', 'dml', 'ventas'].includes(req.query.vista) ? req.query.vista : 'acceso';
      const campos = { acceso: ['usuario', 'resultado'], dml: ['tabla', 'operacion'], ventas: ['cliente'] };
      const filters = {};
      for (const campo of ['fechaInicial', 'fechaFinal', ...campos[vista]]) {
        const value = req.query[campo];
        if (value !== undefined && (typeof value !== 'string' || value.length > 150)) {
          return res.status(400).type('text').send('Los filtros no son válidos.');
        }
        filters[campo] = value || '';
      }
      for (const campo of ['fechaInicial', 'fechaFinal']) {
        const value = filters[campo];
        if (value && (!/^\d{4}-\d{2}-\d{2}$/.test(value)
          || Number.isNaN(new Date(value).getTime()) || new Date(value).toISOString().slice(0, 10) !== value)) {
          return res.status(400).type('text').send('Selecciona fechas válidas.');
        }
      }
      if (filters.fechaInicial && filters.fechaFinal && filters.fechaInicial > filters.fechaFinal) {
        return res.status(400).type('text').send('La fecha final debe ser posterior o igual a la inicial.');
      }

      try {
        const [bitacoraAcceso, auditoriaDml, historicoVentas] = await Promise.all([
          auditoriaService.getBitacoraAcceso(vista === 'acceso' ? filters : {}),
          auditoriaService.getAuditoriaDml(vista === 'dml' ? filters : {}),
          auditoriaService.getHistoricoVentas(vista === 'ventas' ? filters : {}),
        ]);

        return res.render('auditoria', {
          usuario: req.session.usuario,
          filtros: filters,
          vista,
          error: null,
          bitacoraAcceso,
          auditoriaDml,
          historicoVentas,
        });
      } catch {
        return res.status(500).render('auditoria', { usuario: req.session.usuario, filtros: filters, vista, error: 'No fue posible consultar la auditoría.', bitacoraAcceso: [], auditoriaDml: [], historicoVentas: [] });
      }
    },
  };
}

module.exports = { createAuditoriaController };
