'use strict';

const { sql, getPool } = require('../config/database');
const { randomUUID } = require('node:crypto');

function createVentaService(poolProvider = getPool) {
  return {
    async obtenerPolitica(usuarioId) {
      const pool = await poolProvider();
      return (await pool.request().input('UsuarioId', sql.Int, usuarioId)
        .execute('dbo.sp_ObtenerPoliticaVenta')).recordset[0];
    },
    async listarClientes() {
      const pool = await poolProvider();
      return (await pool.request().execute('dbo.sp_ListarClientes')).recordset;
    },
    async listarProductos() {
      const pool = await poolProvider();
      return (await pool.request().execute('dbo.sp_ListarProductosDisponibles')).recordset;
    },
    async procesarVenta(clienteId, usuarioId, lineas, motivoDescuento = null, operacionId = randomUUID()) {
      const detalle = new sql.Table('dbo.TipoDetalleVentaDescuento');
      detalle.columns.add('ProductoId', sql.Int, { nullable: false });
      detalle.columns.add('Cantidad', sql.Int, { nullable: false });
      detalle.columns.add('DescuentoPorcentaje', sql.Decimal(5, 2), { nullable: false });
      for (const linea of lineas) detalle.rows.add(linea.ProductoId, linea.Cantidad, linea.DescuentoPorcentaje ?? 0);
      const pool = await poolProvider();
      const result = await pool.request()
        .input('ClienteId', sql.Int, clienteId)
        .input('UsuarioId', sql.Int, usuarioId)
        .input('Detalle', detalle)
        .input('MotivoDescuento', sql.NVarChar(80), motivoDescuento)
        .input('OperacionId', sql.UniqueIdentifier, operacionId)
        .execute('dbo.sp_ERP_ProcesarVenta');
      return { ...result.recordset[0], Detalle: result.recordsets?.[1] ?? [] };
    },
  };
}

module.exports = { createVentaService };
