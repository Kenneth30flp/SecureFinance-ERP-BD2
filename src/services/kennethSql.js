'use strict';
const { sql, getPool } = require('../config/database');
function executor(provider = getPool) {
  return async (procedure, actor, parameters = []) => {
    const request = (await provider()).request().input('ActorUsuarioId', sql.Int, actor);
    for (const [name, type, value] of parameters) request.input(name, type, value ?? null);
    let result;
    try {
      result = await request.execute(procedure);
    } catch (error) {
      // No registrar parametros, mensajes SQL (pueden contener datos) ni credenciales.
      console.error('ERP_SQL_FAILURE', JSON.stringify({ procedure, code: error.code,
        number: error.number, state: error.state, class: error.class,
        lineNumber: error.lineNumber, serverProcedure: error.procName }));
      throw error;
    }
    return (result.recordset || []).map(row => ({ ...row, ...(Buffer.isBuffer(row.Version) ? { Version: row.Version.toString('hex') } : {}) }));
  };
}
const filters = f => [['Buscar', sql.NVarChar(150), f.buscar || ''], ['Id', sql.Int, f.id], ['Desplazamiento', sql.Int, f.offset || 0]];
module.exports = { sql, executor, filters };
