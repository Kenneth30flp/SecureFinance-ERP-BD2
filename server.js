'use strict';

require('dotenv').config({ quiet: true });
const express = require('express');
const session = require('express-session');
const path = require('node:path');
const { getPool, closePool } = require('./src/config/database');

async function start() {
  const secret = process.env.SESSION_SECRET;
  if (!secret || secret.trim().length < 32) {
    throw new Error('Configura SESSION_SECRET con al menos 32 caracteres.');
  }
  const port = Number(process.env.PORT || 3000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT debe ser un puerto válido.');
  }

  const app = express();
  app.disable('x-powered-by');
  app.set('view engine', 'ejs');
  app.set('views', path.join(__dirname, 'src/views'));
  app.use(express.urlencoded({ extended: false, limit: '10kb' }));
  app.use(express.json({ limit: '10kb' }));
  app.use(express.static(path.join(__dirname, 'src/public')));
  app.use('/vendor/bootstrap', express.static(path.join(__dirname, 'node_modules/bootstrap/dist')));
  // MemoryStore solo para esta fase académica local. No implementa login.
  app.use(session({
    name: 'securefinance.sid',
    secret,
    resave: false,
    saveUninitialized: false,
    cookie: {
      httpOnly: true,
      sameSite: 'lax',
      secure: process.env.NODE_ENV === 'production',
      maxAge: 30 * 60 * 1000,
    },
  }));
  app.get('/', (req, res) => res.type('text').send('SecureFinance ERP — Base de la Fase 1.'));
  // Comprueba HTTP únicamente; la conexión SQL se valida durante el arranque.
  app.get('/health', (req, res) => res.json({ status: 'ok', phase: 1 }));

  await getPool();
  const server = app.listen(port, '127.0.0.1', () => {
    console.log(`SecureFinance ERP: http://localhost:${port}`);
    console.log('Conexión inicial a SQL Server establecida.');
  });
  server.on('error', async (error) => {
    console.error(`No se pudo iniciar HTTP (${error.code || 'error'}).`);
    await closePool().catch(() => {});
    process.exitCode = 1;
  });
  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.once(signal, () => {
      server.close(async () => {
        await closePool().catch(() => {});
        process.exitCode = 0;
      });
    });
  }
}

if (require.main === module) {
  start().catch(async (error) => {
    // Los errores del driver pueden incluir información de conexión.
    console.error(error.code ? `No se pudo conectar a SQL Server (${error.code}). Revisa tu configuración local.` : error.message);
    await closePool().catch(() => {});
    process.exitCode = 1;
  });
}

module.exports = { start };
