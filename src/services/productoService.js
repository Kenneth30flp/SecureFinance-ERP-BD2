'use strict';
const { sql, executor, filters } = require('./kennethSql');
function createProductoService(provider) {
  const execute = executor(provider);
  return {
    relations(actor, f) { return execute('dbo.sp_ConsultarProductoProveedor',actor,[['ProductoId',sql.Int,f.productoId],['ProveedorId',sql.Int,f.proveedorId]]); },
    associate(actor,d) { return execute('dbo.sp_AsociarProductoProveedor',actor,[['ProductoId',sql.Int,d.id],['ProveedorId',sql.Int,d.ProveedorId],['Activo',sql.Bit,d.Activo]]); },
    list(actor, f = {}) { return execute('dbo.sp_ConsultarProductosWeb', actor, [...filters(f), ['Inventario', sql.Bit, !!f.inventario], ['IncluirCosto', sql.Bit, !!f.costo]]); },
    save(actor, d) {
      const p = [['Codigo', sql.NVarChar(40), d.Codigo], ['Descripcion', sql.NVarChar(200), d.Descripcion], ['Precio', sql.Decimal(12, 2), d.Precio], ['PrecioCosto', sql.Decimal(12, 2), d.PrecioCosto], ['ProveedorId', sql.Int, d.ProveedorId], ['StockMinimo', sql.Int, d.StockMinimo], ['PuntoReorden', sql.Int, d.PuntoReorden], ['GarantiaMeses', sql.SmallInt, d.GarantiaMeses], ['Fotografia', sql.VarChar(40), d.Fotografia]];
      if (d.id) p.push(['ProductoId', sql.Int, d.id], ['VersionEsperada', sql.Binary(8), Buffer.from(d.Version, 'hex')], ['Activo', sql.Bit, d.Activo]);
      return execute(d.id ? 'dbo.sp_ActualizarProducto' : 'dbo.sp_RegistrarProducto', actor, p);
    },
  };
}
module.exports = { createProductoService };
