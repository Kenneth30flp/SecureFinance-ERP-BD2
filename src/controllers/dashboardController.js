'use strict';
function createDashboardController(service) {
  return {
    async mostrar(req, res) {
      let resumen = null;
      let advertencia = null;
      try {
        resumen = await service.obtenerResumen(req.session.usuario.usuarioId);
        if (!resumen) throw new Error('Resumen no disponible.');
      } catch {
        advertencia = 'No fue posible obtener el resumen operativo. Los módulos siguen disponibles.';
      }
      return res.render('dashboard', { usuario: req.session.usuario, resumen, advertencia });
    },
  };
}
module.exports = { createDashboardController };
