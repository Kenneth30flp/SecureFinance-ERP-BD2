'use strict';
const { sql, executor, filters } = require('./kennethSql');
function createProveedorService(provider) {
  const execute = executor(provider);
  return {
    list(actor, f = {}) { return execute('dbo.sp_ConsultarProveedoresWeb', actor, filters(f)); },
    save(actor, d) {
      const p = ['NIT', 'Nombre', 'Correo', 'Telefono', 'Direccion'].map(name => [name, sql.NVarChar(sql.MAX), d[name] || null]);
      // La fotografia de proveedor se conserva; su carga no forma parte del catalogo de productos.
      p.push(['Fotografia', sql.VarChar(40), d.Fotografia]);
      if (d.id) p.push(['ProveedorId', sql.Int, d.id], ['VersionEsperada', sql.Binary(8), Buffer.from(d.Version, 'hex')], ['Activo', sql.Bit, d.Activo]);
      return execute(d.id ? 'dbo.sp_ActualizarProveedor' : 'dbo.sp_RegistrarProveedor', actor, p);
    },
  };
}
module.exports = { createProveedorService };
