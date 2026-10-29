'use strict';

const { sql, getPool } = require('../config/database');
const { localDayBoundary } = require('../public/js/operationalDates');

const fields = ['BitacoraDdlId', 'FechaHora', 'TipoEvento', 'NombreObjeto', 'TipoObjeto',
  'Esquema', 'UsuarioSQL', 'LoginOriginal', 'EquipoOrigen', 'AplicacionOrigen',
  'BaseDatos', 'SesionId', 'EstadoComando'];

function decimal(value, zero = false) {
  if (typeof value !== 'string' || !/^(0|[1-9]\d{0,18})$/.test(value)
    || BigInt(value) > 9223372036854775807n || (!zero && value === '0')) {
    throw new Error('Contrato DDL incompatible.');
  }
  return value;
}

function metadata(row, detail = false) {
  if (!row || !['PENDIENTE_RUBRICA', 'EXACTO_EVENTDATA'].includes(row.EstadoComando)
    || ((!detail || row.EstadoComando === 'PENDIENTE_RUBRICA')
      && row.ComandoTSql !== undefined && row.ComandoTSql !== null)
    || (detail && row.EstadoComando === 'EXACTO_EVENTDATA'
      && (typeof row.ComandoTSql !== 'string' || row.ComandoTSql.length === 0))) {
    throw new Error('Contrato DDL incompatible con la politica del evento.');
  }
  decimal(row.BitacoraDdlId);
  // Full text is forwarded only by the individually authorized detail query.
  const result = Object.fromEntries(fields.map(field => [field, row[field]]));
  if (detail && row.EstadoComando === 'EXACTO_EVENTDATA') result.ComandoTSql = row.ComandoTSql;
  return result;
}

function createAuditoriaDdlService(provider = getPool) {
  return {
    async list(actor, f) {
      const result = await (await provider()).request()
        .input('ActorUsuarioId', sql.Int, actor)
        .input('Desde', sql.DateTime2(3), localDayBoundary(f.desde))
        .input('Hasta', sql.DateTime2(3), localDayBoundary(f.hasta, true))
        .input('Usuario', sql.NVarChar(128), f.usuario || null)
        .input('Objeto', sql.NVarChar(128), f.objeto || null)
        .input('Evento', sql.NVarChar(40), f.evento || null)
        .input('CorteId', sql.BigInt, f.corteId)
        .input('Desplazamiento', sql.Int, (f.pagina - 1) * 20)
        .input('Limite', sql.Int, 20)
        .execute('dbo.P3_DDL_ConsultarBitacora');
      const sets = result.recordsets;
      if (!Array.isArray(sets) || sets.length !== 2 || !Array.isArray(sets[0])
        || sets[0].length > 20 || !Array.isArray(sets[1]) || sets[1].length !== 1) {
        throw new Error('Contrato DDL incompatible.');
      }
      const total = decimal(sets[1][0].TotalFilas, true);
      const corteId = decimal(sets[1][0].CorteId, true);
      const rows = sets[0].map(row => metadata(row));
      if ((f.corteId !== null && f.corteId !== corteId)
        || BigInt(total) < BigInt(rows.length)
        || rows.some(row => BigInt(row.BitacoraDdlId) > BigInt(corteId))
        || new Set(rows.map(row => row.BitacoraDdlId)).size !== rows.length) {
        throw new Error('Contrato DDL incompatible.');
      }
      return { rows, total, corteId };
    },
    async detail(actor, id) {
      const result = await (await provider()).request()
        .input('ActorUsuarioId', sql.Int, actor)
        .input('BitacoraDdlId', sql.BigInt, id)
        .execute('dbo.P3_DDL_ConsultarDetalle');
      if (!Array.isArray(result.recordset) || result.recordset.length > 1) {
        throw new Error('Contrato DDL incompatible.');
      }
      if (!result.recordset.length) return null;
      const row = metadata(result.recordset[0], true);
      if (row.BitacoraDdlId !== id) throw new Error('Contrato DDL incompatible.');
      return row;
    },
  };
}

module.exports = { createAuditoriaDdlService };
