'use strict';

require('dotenv').config({ quiet: true });
const express = require('express');
const session = require('express-session');
const path = require('node:path');
const { getPool, closePool } = require('./src/config/database');
const { verifyIntegration } = require('./src/config/integration');

const { createAuthService } = require('./src/services/authService');
const { createAuthRoutes } = require('./src/routes/authRoutes');
const { createDashboardService } = require('./src/services/dashboardService');
const { createDashboardRoutes } = require('./src/routes/dashboardRoutes');

const { createVentaService } = require('./src/services/ventaService');
const { createFacturaService } = require('./src/services/facturaService');
const { createVentaRoutes } = require('./src/routes/ventaRoutes');

const { createAuditoriaService } = require('./src/services/auditoriaService');
const { createAuditoriaRoutes } = require('./src/routes/auditoriaRoutes');
const { createAuditoriaDdlService } = require('./src/services/auditoriaDdlService');
const { createAuditoriaDdlRoutes } = require('./src/routes/auditoriaDdlRoutes');

const { createUsuarioService } = require('./src/services/usuarioService');
const { createUsuarioRoutes } = require('./src/routes/usuarioRoutes');
const { createPasswordService } = require('./src/services/passwordService');
const { createPasswordRoutes } = require('./src/routes/passwordRoutes');
const { createProductoService } = require('./src/services/productoService');
const { createProveedorService } = require('./src/services/proveedorService');
const { createClienteService } = require('./src/services/clienteService');
const { createInventarioService } = require('./src/services/inventarioService');
const { createFotografiaService } = require('./src/services/fotografiaService');
const { createKennethRoutes } = require('./src/routes/kennethRoutes');
const { createEdwardService } = require('./src/modules/edward/services');
const { createEdwardRoutes } = require('./src/modules/edward/routes');
const { createAnaliticaService } = require('./src/modules/jose/analiticaService');
const { createAnaliticaRoutes } = require('./src/modules/jose/analiticaRoutes');
const { createCotizacionService } = require('./src/modules/cotizaciones/service');
const { createCotizacionRoutes } = require('./src/modules/cotizaciones/routes');
const { createPromocionService } = require('./src/modules/promociones/service');
const { createPromocionRoutes } = require('./src/modules/promociones/routes');
const { createCreditoService } = require('./src/modules/creditos/service');
const { createCreditoRoutes } = require('./src/modules/creditos/routes');
const { createMultibodegaService } = require('./src/modules/multibodega/service');
const { createMultibodegaRoutes } = require('./src/modules/multibodega/routes');

function createApp({
  secret = process.env.SESSION_SECRET,
  authService = createAuthService(),
  dashboardService = createDashboardService(),
  ventaService = createVentaService(),
  facturaService = createFacturaService(),
  auditoriaService = createAuditoriaService(),
  auditoriaDdlService = createAuditoriaDdlService(),
  usuarioService = createUsuarioService(),
  passwordService = createPasswordService(),
  edwardService = createEdwardService(),
  kennethServices = { productos:createProductoService(), proveedores:createProveedorService(), clientes:createClienteService(), inventario:createInventarioService(), photos:createFotografiaService() },
  analiticaService = createAnaliticaService(),
  cotizacionService = createCotizacionService(),
  promocionService = createPromocionService(),
  creditoService = createCreditoService(),
  multibodegaService = createMultibodegaService(),
  production = process.env.NODE_ENV === 'production',
} = {}) {
  if (!secret || secret.trim().length < 32) {
    throw new Error('Configura SESSION_SECRET con al menos 32 caracteres.');
  }

  const app = express();

  app.disable('x-powered-by');
  app.set('view engine', 'ejs');
  app.set('views', path.join(__dirname, 'src/views'));
  app.locals.moduleAreas = require('./src/config/moduleCatalog').visibleAreas;
  app.locals.displayMoney = require('./src/modules/cotizaciones/format').money;

  app.use(express.urlencoded({ extended: false, limit: '10kb' }));
  app.use(express.json({ limit: '10kb' }));
  app.use(express.static(path.join(__dirname, 'src/public')));
  app.use(
    '/vendor/bootstrap',
    express.static(path.join(path.dirname(require.resolve('bootstrap/package.json')), 'dist'))
  );

  // MemoryStore exclusivamente para desarrollo académico local.
  app.use(
    session({
      name: 'securefinance.sid',
      secret,
      resave: false,
      saveUninitialized: false,
      cookie: {
        httpOnly: true,
        sameSite: 'lax',
        secure: production ? 'auto' : false,
        maxAge: 30 * 60 * 1000,
      },
    })
  );

  // Autenticación de Kenneth
  app.get('/modulos', require('./src/middleware/authMiddleware').requireAuth, (req,res)=>{
    res.set('Cache-Control','no-store');
    res.render('modulos',{usuario:req.session.usuario});
  });
  app.use(createAuthRoutes(authService));
  app.use(createDashboardRoutes(dashboardService));
  app.use(createAnaliticaRoutes(analiticaService));
  app.use(createPasswordRoutes(passwordService, { production }));

  // Facturación de Edward
  app.use(createVentaRoutes(ventaService,facturaService,promocionService));
  app.use(createEdwardRoutes(edwardService));

  // Auditoría de José
  app.use(createAuditoriaRoutes(auditoriaService));
  app.use(createAuditoriaDdlRoutes(auditoriaDdlService));

  app.use(createUsuarioRoutes(usuarioService));
  app.use(createKennethRoutes(kennethServices));
  app.use(createCotizacionRoutes(cotizacionService));
  // Promociones de José (Parte III, migraciones 60-63)
  app.use(createPromocionRoutes(promocionService));
  app.use(createCreditoRoutes(creditoService));
  app.use(createMultibodegaRoutes(multibodegaService));

  app.get('/health', (req, res) =>
    res.json({ status: 'ok', phase: 3 })
  );

  app.use((error, req, res, next) => {
    if (res.headersSent) return next(error);

    const status =
      error.type === 'entity.too.large'
        ? 413
        : error.status === 400
          ? 400
          : 500;

    return res
      .status(status)
      .type('text')
      .send(
        status === 500
          ? 'No fue posible procesar la solicitud.'
          : 'La solicitud no es válida.'
      );
  });

  return app;
}

async function start() {
  const app = createApp();
  const port = Number(process.env.PORT || 3000);

  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT debe ser un puerto válido.');
  }

  const identity = await verifyIntegration(await getPool());

  const server = app.listen(port, '127.0.0.1', () => {
    console.log(`SecureFinance ERP: http://localhost:${port}`);
    console.log('Conexión inicial a SQL Server establecida.');
    console.log('ERP_RUNTIME', JSON.stringify({ pid: process.pid, directory: __dirname,
      database: identity.databaseName, login: identity.loginName }));
  });

  server.on('error', async (error) => {
    console.error(
      `No se pudo iniciar HTTP (${error.code || 'error'}).`
    );
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
    console.error(
      error.code
        ? `No se pudo conectar a SQL Server (${error.code}). Revisa tu configuración local.`
        : error.message
    );

    await closePool().catch(() => {});
    process.exitCode = 1;
  });
}

module.exports = { start, createApp };
