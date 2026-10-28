'use strict';

const { sql, getPool } = require('../config/database');
const { localDayBoundary } = require('../public/js/operationalDates');

function normalizeDate(value, endOfDay = false) {
  if (value === undefined || value === null || value === '') return null;
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return localDayBoundary(value, endOfDay, true);
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date;
}

function createAuditoriaService(poolProvider = getPool) {
  async function execute(procedure, filters, parameters) {
    const pool = await poolProvider();
    const request = pool.request()
      .input('FechaInicial', sql.DateTime2(3), normalizeDate(filters.fechaInicial))
      .input('FechaFinal', sql.DateTime2(3), normalizeDate(filters.fechaFinal, true));
    for (const [name, type, value] of parameters) {
      request.input(name, type, value == null || value === '' ? null : String(value));
    }
    const result = await request.execute(procedure);
    return result.recordset ?? [];
  }

  return {
    getBitacoraAcceso(filters = {}) {
      return execute('dbo.sp_ConsultarBitacoraAcceso', filters, [
        ['NombreUsuarioIntentado', sql.NVarChar(50), filters.usuario],
        ['Resultado', sql.VarChar(30), filters.resultado],
      ]);
    },
    getAuditoriaDml(filters = {}) {
      return execute('dbo.sp_ConsultarAuditoriaTransacciones', filters, [
        ['Tabla', sql.NVarChar(128), filters.tabla],
        ['Operacion', sql.VarChar(20), filters.operacion],
      ]);
    },
    getHistoricoVentas(filters = {}) {
      return execute('dbo.sp_ConsultarHistoricoVentas', filters, [
        ['Cliente', sql.NVarChar(150), filters.cliente],
      ]);
    },
  };
}

module.exports = { createAuditoriaService };
