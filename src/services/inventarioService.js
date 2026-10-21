'use strict';
const { sql, executor } = require('./kennethSql');
function createInventarioService(provider) {
  const execute = executor(provider);
  return {
    state(actor) { return execute('dbo.sp_ConsultarEstadoInventario', actor); },
    history(actor, f) { return execute('dbo.sp_ERP_ConsultarKardex', actor, [['ProductoId', sql.Int, f.id], ['Desde', sql.DateTime2(3), f.desde ? new Date(f.desde) : null], ['Hasta', sql.DateTime2(3), f.hasta ? new Date(new Date(f.hasta).getTime() + 86400000) : null], ['Desplazamiento', sql.Int, f.histOffset || 0]]); },
    receive(actor, d) { return execute('dbo.sp_RegistrarRecepcionCompra', actor, [['ProductoId',sql.Int,d.id],['ProveedorId',sql.Int,d.ProveedorId],['Cantidad',sql.Int,d.Cantidad],['DocumentoRespaldo',sql.NVarChar(100),d.DocumentoRespaldo],['Motivo',sql.NVarChar(250),d.Motivo],['OperacionId',sql.UniqueIdentifier,d.OperacionId],['CostoUnitario',sql.Decimal(19,2),d.CostoUnitario]]); },
    move(actor, d) { return execute('dbo.sp_ERP_RegistrarAjuste', actor, [['ProductoId', sql.Int, d.id], ['TipoMovimiento', sql.VarChar(25), d.TipoMovimiento], ['Cantidad', sql.Int, d.Cantidad], ['DocumentoRespaldo', sql.NVarChar(100), d.DocumentoRespaldo], ['OperacionId', sql.UniqueIdentifier, d.OperacionId], ['LineaOperacion', sql.Int, 1], ['Motivo', sql.NVarChar(250), d.Motivo], ['VersionEsperada', sql.Binary(8), d.TipoMovimiento === 'COMPRA' ? null : Buffer.from(d.Version, 'hex')]]); },
  };
}
module.exports = { createInventarioService };
