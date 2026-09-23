'use strict';

const { sql, getPool } = require('../config/database');

function normalizeDate(value) {
  if (value === undefined || value === null || value === '') return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date;
}

function addOptionalInput(request, name, type, value) {
  if (value === undefined || value === null || value === '') return request;
  return request.input(name, type, value);
}

function createAuditoriaService(poolProvider = getPool) {
  const runQuery = async (sqlText, params) => {
    const pool = await poolProvider();
    const request = pool.request();
    for (const param of params) {
      if (param.value !== undefined && param.value !== null && param.value !== '') {
        request.input(param.name, param.type, param.value);
      }
    }
    const result = await request.query(sqlText);
    return result.recordset ?? [];
  };

  return {
    async getBitacoraAcceso(filters = {}) {
      const clauses = [];
      const params = [];
      const fechaInicial = normalizeDate(filters.fechaInicial);
      const fechaFinal = normalizeDate(filters.fechaFinal);
      if (fechaInicial) {
        clauses.push('FechaHora >= @FechaInicial');
        params.push({ name: 'FechaInicial', type: sql.DateTime2, value: fechaInicial });
      }
      if (fechaFinal) {
        clauses.push('FechaHora <= @FechaFinal');
        params.push({ name: 'FechaFinal', type: sql.DateTime2, value: fechaFinal });
      }
      if (filters.resultado) {
        clauses.push('Resultado = @Resultado');
        params.push({ name: 'Resultado', type: sql.VarChar(30), value: String(filters.resultado) });
      }
      if (filters.usuario) {
        clauses.push('NombreUsuarioIntentado = @NombreUsuarioIntentado');
        params.push({ name: 'NombreUsuarioIntentado', type: sql.NVarChar(50), value: String(filters.usuario) });
      }

      const where = clauses.length ? ` WHERE ${clauses.join(' AND ')}` : '';
      const sqlText = `SELECT FechaHora, NombreUsuarioIntentado, Resultado, HostName, AppName, UsuarioSQL, IpConexionSQL FROM dbo.Bitacora_Acceso${where} ORDER BY FechaHora DESC;`;
      return runQuery(sqlText, params);
    },

    async getAuditoriaDml(filters = {}) {
      const params = [];
      const fechaInicial = normalizeDate(filters.fechaInicial);
      const fechaFinal = normalizeDate(filters.fechaFinal);
      const tabla = filters.tabla ? String(filters.tabla) : null;
      const operacion = filters.operacion ? String(filters.operacion) : null;

      if (fechaInicial) params.push({ name: 'FechaInicial', type: sql.DateTime2, value: fechaInicial });
      if (fechaFinal) params.push({ name: 'FechaFinal', type: sql.DateTime2, value: fechaFinal });
      if (tabla) params.push({ name: 'Tabla', type: sql.NVarChar(128), value: tabla });
      if (operacion) params.push({ name: 'Operacion', type: sql.VarChar(30), value: operacion });

      const sqlText = `SELECT FechaHora, TablaAfectada, Operacion, UsuarioSQL, HostName, ValorAnterior, ValorNuevo FROM dbo.fn_ConsultarAuditoria(${fechaInicial ? '@FechaInicial' : 'NULL'}, ${fechaFinal ? '@FechaFinal' : 'NULL'}, ${tabla ? '@Tabla' : 'NULL'}, ${operacion ? '@Operacion' : 'NULL'}) ORDER BY FechaHora DESC;`;
      return runQuery(sqlText, params);
    },

    async getHistoricoVentas(filters = {}) {
      const params = [];
      const fechaInicial = normalizeDate(filters.fechaInicial);
      const fechaFinal = normalizeDate(filters.fechaFinal);
      const cliente = filters.cliente ? String(filters.cliente) : null;

      if (fechaInicial) params.push({ name: 'FechaInicial', type: sql.DateTime2, value: fechaInicial });
      if (fechaFinal) params.push({ name: 'FechaFinal', type: sql.DateTime2, value: fechaFinal });
      if (cliente) params.push({ name: 'Cliente', type: sql.NVarChar(150), value: cliente });

      const sqlText = `SELECT Factura, Fecha, Cliente, Usuario, Subtotal, IVA, Total FROM dbo.fn_ObtenerHistoricoVentas(${fechaInicial ? '@FechaInicial' : 'NULL'}, ${fechaFinal ? '@FechaFinal' : 'NULL'}, ${cliente ? '@Cliente' : 'NULL'}) ORDER BY Fecha DESC;`;
      try {
        return await runQuery(sqlText, params);
      } catch (error) {
        const message = String(error?.message || '');
        const code = Number(error?.number) || Number(error?.code) || 0;
        if (message.includes('fn_ObtenerHistoricoVentas') || code === 208 || code === 3701) {
          return [];
        }
        throw error;
      }
    },
  };
}

module.exports = { createAuditoriaService };
