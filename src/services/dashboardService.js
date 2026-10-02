'use strict';
const { sql, getPool } = require('../config/database');

function createDashboardService(poolProvider = getPool) {
  return {
    async obtenerResumen(usuarioId) {
      const pool = await poolProvider();
      const result = await pool.request().input('UsuarioId', sql.Int, usuarioId)
        .execute('dbo.sp_ObtenerResumenDashboard');
      const resumen = result.recordset?.[0];
      if (result.recordset?.length !== 1 || !resumen
        || (resumen.VentasDia !== null && !/^\d+\.\d{2}$/.test(resumen.VentasDia))
        || ['FacturasDia', 'ProductosStockBajo', 'EventosDMLDia'].some((campo) => resumen[campo] !== null && !/^\d+$/.test(resumen[campo]))
        || !/^\d{4}-\d{2}-\d{2}$/.test(resumen.FechaOperacion)
        || (resumen.RolesActuales !== null && typeof resumen.RolesActuales !== 'string')) {
        throw new Error('Resumen operativo no válido.');
      }
      return resumen;
    },
  };
}
module.exports = { createDashboardService };
