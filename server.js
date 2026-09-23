'use strict';

require('dotenv').config({ quiet: true });
const express = require('express');
const session = require('express-session');
const path = require('node:path');
const { getPool, closePool } = require('./src/config/database');
const { createAuthService } = require('./src/services/authService');
const { createAuthRoutes } = require('./src/routes/authRoutes');

function createApp({ secret = process.env.SESSION_SECRET, authService = createAuthService(),
  production = process.env.NODE_ENV === 'production' } = {}) {
  if (!secret || secret.trim().length < 32) {
    throw new Error('Configura SESSION_SECRET con al menos 32 caracteres.');
  }
  const app = express();
  app.disable('x-powered-by');
  app.set('view engine', 'ejs');
  app.set('views', path.join(__dirname, 'src/views'));
  app.use(express.urlencoded({ extended: false, limit: '10kb' }));
  app.use(express.json({ limit: '10kb' }));
  app.use(express.static(path.join(__dirname, 'src/public')));
  app.use('/vendor/bootstrap', express.static(path.join(__dirname, 'node_modules/bootstrap/dist')));
  // MemoryStore exclusivamente para desarrollo académico local.
  app.use(session({
    name: 'securefinance.sid',
    secret,
    resave: false,
    saveUninitialized: false,
    cookie: {
      httpOnly: true,
      sameSite: 'lax',
      // En producción, auto activa Secure solo si Express detecta HTTPS.
      // No confiar en cabeceras de proxy sin configurar antes un proxy conocido.
      secure: production ? 'auto' : false,
      maxAge: 30 * 60 * 1000,
    },
  }));
  app.use(createAuthRoutes(authService));
  // Comprueba HTTP únicamente; la conexión SQL se valida durante el arranque.
  app.get('/health', (req, res) => res.json({ status: 'ok', phase: 3 }));
  app.use((error, req, res, next) => {
    if (res.headersSent) return next(error);
    const status = error.type === 'entity.too.large' ? 413 : error.status === 400 ? 400 : 500;
    return res.status(status).type('text').send(status === 500
      ? 'No fue posible procesar la solicitud.' : 'La solicitud no es válida.');
  });
  return app;
}

async function start() {
  const app = createApp();
  const port = Number(process.env.PORT || 3000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT debe ser un puerto válido.');
  }
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

module.exports = { start, createApp };
