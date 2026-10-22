'use strict';

const procedures = [
  'sp_ConsultarProductoProveedor', 'sp_ERP_ConsultarKardex',
  'sp_RegistrarRecepcionCompra', 'sp_ERP_RegistrarAjuste',
  'sp_ERP_ProcesarVenta', 'sp_RegistrarAplicacionNotaCredito',
  'sp_ConsultarAplicacionesNotaCredito', 'sp_AsociarProductoProveedor',
  'sp_ERP_RegistrarProducto',
];

async function verifyIntegration(pool) {
  const result = await pool.request().query(`
    SELECT DB_NAME() AS databaseName, ORIGINAL_LOGIN() AS loginName;
    SELECT p.name, HAS_PERMS_BY_NAME('dbo.' + p.name, 'OBJECT', 'EXECUTE') AS allowed
    FROM (VALUES ${procedures.map(name => `('${name}')`).join(',')}) p(name);`);
  const missing = result.recordsets[1].filter(row => row.allowed !== 1).map(row => row.name);
  if (missing.length) {
    const error = new Error(`Integracion SQL incompleta en ${result.recordsets[0][0].databaseName}: verificar migraciones 33-38 y EXECUTE (${missing.join(', ')}).`);
    error.integration = true;
    throw error;
  }
  return result.recordsets[0][0];
}

module.exports = { verifyIntegration };
