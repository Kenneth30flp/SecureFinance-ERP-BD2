'use strict';

const { sql, getPool } = require('../config/database');

function createVentaService(poolProvider = getPool) {
  return {
    async listarClientes() {
      const pool = await poolProvider();
      return (await pool.request().execute('dbo.sp_ListarClientes')).recordset;
    },
    async listarProductos() {
      const pool = await poolProvider();
      return (await pool.request().execute('dbo.sp_ListarProductosDisponibles')).recordset;
    },
    async procesarVenta(clienteId, usuarioId, lineas) {
      const detalle = new sql.Table('dbo.TipoDetalleVenta');
      detalle.columns.add('ProductoId', sql.Int, { nullable: false });
      detalle.columns.add('Cantidad', sql.Int, { nullable: false });
      for (const linea of lineas) detalle.rows.add(linea.ProductoId, linea.Cantidad);
      const pool = await poolProvider();
      const result = await pool.request()
        .input('ClienteId', sql.Int, clienteId)
        .input('UsuarioId', sql.Int, usuarioId)
        .input('Detalle', detalle)
        .execute('dbo.sp_ProcesarVentaTransaccional');
      return result.recordset[0];
    },
  };
}

module.exports = { createVentaService };
