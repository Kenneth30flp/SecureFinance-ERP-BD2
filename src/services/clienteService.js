'use strict';
const { sql, executor, filters } = require('./kennethSql');
function createClienteService(provider) {
  const execute = executor(provider);
  return {
    list(actor, f = {}) { return execute('dbo.sp_ConsultarClientesWeb', actor, filters(f)); },
    stateHistory(actor,id) { return execute('dbo.sp_ConsultarHistorialEstadoCliente',actor,[['ClienteId',sql.Int,id]]); },
    reactivate(actor,d) { return execute('dbo.sp_ReactivarCliente',actor,[['ClienteId',sql.Int,d.id],['VersionEsperada',sql.Binary(8),Buffer.from(d.Version,'hex')],['Motivo',sql.NVarChar(250),d.Motivo],['OperacionId',sql.UniqueIdentifier,d.OperacionId]]); },
    save(actor, d) {
      const p = [['Nombre', sql.NVarChar(sql.MAX), d.Nombre], ['Correo', sql.NVarChar(sql.MAX), d.Correo], ['Telefono', sql.NVarChar(sql.MAX), d.Telefono]];
      if (d.id) p.push(['ClienteId', sql.Int, d.id], ['VersionEsperada', sql.Binary(8), Buffer.from(d.Version, 'hex')]);
      else p.push(['NIT', sql.NVarChar(sql.MAX), d.NIT]);
      return execute(d.id ? 'dbo.sp_ActualizarDatosCliente' : 'dbo.sp_RegistrarCliente', actor, p);
    },
    update(actor, d, inactivar = false) {
      const p = [['ClienteId', sql.Int, d.id], ['VersionEsperada', sql.Binary(8), Buffer.from(d.Version, 'hex')], ['Motivo', sql.NVarChar(250), d.Motivo]];
      if (!inactivar) p.push(['NIT', sql.NVarChar(25), d.NIT]);
      return execute(inactivar ? 'dbo.sp_InactivarCliente' : 'dbo.sp_ActualizarNitCliente', actor, p);
    },
  };
}
module.exports = { createClienteService };
