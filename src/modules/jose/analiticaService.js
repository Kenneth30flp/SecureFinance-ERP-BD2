'use strict';

const { sql, getPool } = require('../../config/database');

function createAnaliticaService(poolProvider = getPool) {
  return {
    async obtenerDashboard(usuarioId, filtros) {
      const pool = await poolProvider();
      const result = await pool.request()
        .input('ActorUsuarioId', sql.Int, usuarioId)
        .input('Modo', sql.VarChar(15), filtros.modo)
        .input('FechaDesde', sql.Date, filtros.fechaDesde)
        .input('FechaHasta', sql.Date, filtros.fechaHasta)
        .input('Limite', sql.Int, filtros.limite)
        .input('Desplazamiento', sql.Int, filtros.desplazamiento)
        .execute('dbo.sp_ObtenerDashboardVentas');
      const [kpis = [], productos = [], clientes = [], abastecimiento = [], garantias = []] = result.recordsets || [];
      if (kpis.length !== 1) throw new Error('El dashboard devolvió un resumen inválido.');
      return { kpis: kpis[0], productos, clientes, abastecimiento, garantias };
    },
  };
}

module.exports = { createAnaliticaService };
