'use strict';
const { sql, getPool } = require('../../../config/database');
let administrativePool;
function settings(env = process.env) {
  if (!env.LDF_DATABASE || env.LDF_DATABASE !== env.DB_NAME || !env.LDF_EXPECTED_SERVER) {
    throw Object.assign(new Error('Destino LDF no configurado.'), { number: 59010 });
  }
  return { database: env.LDF_DATABASE, server: env.LDF_EXPECTED_SERVER };
}
async function verifyTarget(pool, target = settings()) {
  const result = await pool.request().query("SELECT DB_NAME() DatabaseName, CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) ServerName;");
  const identity = result.recordset?.[0];
  if (identity?.DatabaseName !== target.database || identity?.ServerName !== target.server) {
    throw Object.assign(new Error('Identidad SQL no autorizada.'), { number: 59010 });
  }
  return pool;
}
async function application() { const target = settings(); return verifyTarget(await getPool(), target); }
async function administrative() {
  settings();
  const e = process.env;
  if (!e.LDF_ADMIN_USER || !e.LDF_ADMIN_PASSWORD || e.LDF_ADMIN_USER.toLowerCase() === 'sa'
      || e.LDF_ADMIN_USER.toLowerCase() === e.DB_USER?.toLowerCase()) {
    throw Object.assign(new Error('Servicio de respaldo no configurado.'), { number: 59019 });
  }
  if (!administrativePool) {
    const port = Number(e.DB_PORT || 1433);
    if (!Number.isInteger(port) || port < 1 || port > 65535) throw Error('Puerto SQL invalido.');
    const pool = new sql.ConnectionPool({ server: e.DB_SERVER, port, database: e.LDF_DATABASE,
      user: e.LDF_ADMIN_USER, password: e.LDF_ADMIN_PASSWORD, connectionTimeout: 15000, requestTimeout: 120000,
      pool: { max: 2, min: 0, idleTimeoutMillis: 30000 },
      options: { encrypt: true, trustServerCertificate: e.DB_TRUST_SERVER_CERTIFICATE === 'true', appName: 'SecureFinanceERP-P4-LDF-Manual' } });
    pool.on('error', () => console.error('Conexion del servicio LDF interrumpida.'));
    administrativePool = pool.connect().catch(async error => { administrativePool = undefined; await pool.close().catch(() => {}); throw error; });
  }
  return verifyTarget(await administrativePool);
}
async function close() {
  const pending = administrativePool; administrativePool = undefined;
  if (pending) await (await pending).close();
}
module.exports = { application, administrative, settings, verifyTarget, close };
