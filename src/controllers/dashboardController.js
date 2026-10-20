'use strict';
function createDashboardController(service) {
  return {
    async mostrar(req, res) {
      let resumen = null;
      let advertencia = null;
      let operacion = null, avisoInventario = null;
      try {
        resumen = await service.obtenerResumen(req.session.usuario.usuarioId);
        if (!resumen) throw new Error('Resumen no disponible.');
      } catch {
        advertencia = 'No fue posible obtener el resumen operativo. Los módulos siguen disponibles.';
      }
      if(service.obtenerOperacion)try{operacion=await service.obtenerOperacion(req.session.usuario.usuarioId,req.session.usuario.permisos);}catch{avisoInventario='La consulta de inventario no está disponible. Puedes abrir el módulo para verificar sus existencias.';}
      return res.render('dashboard', { usuario: req.session.usuario, resumen, advertencia, operacion, avisoInventario });
    },
  };
}
module.exports = { createDashboardController };
