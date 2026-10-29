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
    // Promociones (migración 63): el parámetro opcional final solo se envía si está instalado.
    async promocionesInstaladas() {
      const pool = await poolProvider();
      const result = await pool.request().query(`SELECT COUNT(*) AS N FROM sys.parameters
        WHERE object_id = OBJECT_ID('dbo.sp_ERP_ProcesarVenta') AND name = '@P3AplicarPromociones'`);
      return result.recordset[0].N === 1;
    },
    async procesarVenta(clienteId, usuarioId, lineas, motivoDescuento = null, operacionId = randomUUID(), opciones = {}) {
      const detalle = new sql.Table('dbo.TipoDetalleVentaDescuento');
      detalle.columns.add('ProductoId', sql.Int, { nullable: false });
      detalle.columns.add('Cantidad', sql.Int, { nullable: false });
      detalle.columns.add('DescuentoPorcentaje', sql.Decimal(5, 2), { nullable: false });
      for (const linea of lineas) detalle.rows.add(linea.ProductoId, linea.Cantidad, linea.DescuentoPorcentaje ?? 0);
      const pool = await poolProvider();
      const request = pool.request()
        .input('ClienteId', sql.Int, clienteId)
        .input('UsuarioId', sql.Int, usuarioId)
        .input('Detalle', detalle)
        .input('MotivoDescuento', sql.NVarChar(80), motivoDescuento)
        .input('OperacionId', sql.UniqueIdentifier, operacionId);
      if (opciones.aplicarPromociones === true) request.input('P3AplicarPromociones', sql.Bit, true);
      const result = await request.execute('dbo.sp_ERP_ProcesarVenta');
      const venta = { ...result.recordset[0], Detalle: result.recordsets?.[1] ?? [] };
      if (opciones.aplicarPromociones === true) venta.Promociones = result.recordsets?.[2] ?? [];
      return venta;
    },
  };
}

module.exports = { createVentaService };
