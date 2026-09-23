'use strict';

const sql = require('mssql');
let poolPromise;

function required(name) {
  const value = process.env[name];
  if (!value || !value.trim()) throw new Error(`Falta configurar ${name}.`);
  return value;
}

function booleanSetting(name, fallback) {
  const value = process.env[name];
  if (value === undefined || value === '') return fallback;
  if (value !== 'true' && value !== 'false') {
    throw new Error(`${name} debe ser true o false.`);
  }
  return value === 'true';
}

function getConfig() {
  const port = Number(process.env.DB_PORT || 1433);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('DB_PORT debe ser un puerto válido.');
  }
  const user = required('DB_USER');
  if (user.trim().toLowerCase() === 'sa') {
    throw new Error('Configura una cuenta SQL de aplicación dedicada, distinta de sa.');
  }
  return {
    server: required('DB_SERVER'),
    port,
    database: required('DB_NAME'),
    user,
    password: required('DB_PASSWORD'),
    connectionTimeout: 15000,
    requestTimeout: 15000,
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 },
    options: {
      encrypt: booleanSetting('DB_ENCRYPT', true),
      trustServerCertificate: booleanSetting('DB_TRUST_SERVER_CERTIFICATE', false),
      appName: 'SecureFinanceERP-Node',
    },
  };
}

// Una sola promesa comparte el pool incluso entre solicitudes concurrentes.
// Los servicios futuros usarán request().input(...).execute(...), nunca SQL concatenado.
function getPool() {
  if (!poolPromise) {
    const pool = new sql.ConnectionPool(getConfig());
    pool.on('error', () => console.error('Error en el pool de SQL Server.'));
    poolPromise = pool.connect().catch(async (error) => {
      poolPromise = undefined;
      await pool.close().catch(() => {});
      throw error;
    });
  }
  return poolPromise;
}

async function closePool() {
  const pending = poolPromise;
  poolPromise = undefined;
  if (pending) {
    const pool = await pending;
    await pool.close();
  }
}

module.exports = { sql, getPool, closePool };
