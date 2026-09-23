'use strict';

function createAuditoriaController(auditoriaService) {
  return {
    async index(req, res) {
      if (!req.session?.usuario) return res.redirect('/login');
      const permisos = Array.isArray(req.session.usuario.permisos) ? req.session.usuario.permisos : [];
      if (!permisos.includes('AUDITORIA_CONSULTAR')) {
        return res.status(403).type('text').send('No tienes permiso para consultar auditoría.');
      }

      const filters = {
        fechaInicial: req.query.fechaInicial,
        fechaFinal: req.query.fechaFinal,
        fechaHora: req.query.fechaHora,
        usuario: req.query.usuario,
        resultado: req.query.resultado,
        tabla: req.query.tabla,
        operacion: req.query.operacion,
        cliente: req.query.cliente,
      };

      try {
        const [bitacoraAcceso, auditoriaDml, historicoVentas] = await Promise.all([
          auditoriaService.getBitacoraAcceso(filters),
          auditoriaService.getAuditoriaDml(filters),
          auditoriaService.getHistoricoVentas(filters),
        ]);

        return res.render('auditoria', {
          usuario: req.session.usuario,
          filtros: filters,
          bitacoraAcceso,
          auditoriaDml,
          historicoVentas,
        });
      } catch {
        return res.status(500).type('text').send('No fue posible consultar la auditoría.');
      }
    },
  };
}

module.exports = { createAuditoriaController };
