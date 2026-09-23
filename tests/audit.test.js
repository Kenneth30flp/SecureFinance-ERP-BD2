'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createApp } = require('../server');
const { createAuditoriaService } = require('../src/services/auditoriaService');

function fakePool(responses) {
  const calls = [];
  return {
    calls,
    request() {
      const inputs = [];
      return {
        input(name, type, value) {
          inputs.push({ name, type, value });
          return this;
        },
        query(sqlText) {
          calls.push({ sqlText, inputs });
          const response = responses.shift();
          if (response instanceof Error) throw response;
          return response;
        },
      };
    },
  };
}

const bitacoraAcceso = () => ({
  recordset: [{
    FechaHora: '2026-01-01T10:00:00Z',
    NombreUsuarioIntentado: 'admin',
    Resultado: 'EXITOSO',
    HostName: 'APPHOST',
    AppName: 'SecureFinanceERP-Node',
    UsuarioSQL: 'sa',
    IpConexionSQL: '127.0.0.1',
  }],
});

const auditoriaDml = () => ({
  recordset: [{
    FechaHora: '2026-01-01T10:30:00Z',
    TablaAfectada: 'Producto',
    Operacion: 'UPDATE',
    UsuarioSQL: 'app_user',
    HostName: 'APPHOST',
    ValorAnterior: '{"Precio":10}',
    ValorNuevo: '{"Precio":12}',
  }],
});

const historicoVentas = () => ({
  recordset: [{
    Factura: 101,
    Fecha: '2026-01-02T00:00:00Z',
    Cliente: 'Ana',
    Usuario: 'admin',
    Subtotal: 100,
    IVA: 12,
    Total: 112,
  }],
});

test('Servicio auditoría: consulta de tablas reales y filtros', async () => {
  const pool = fakePool([bitacoraAcceso(), auditoriaDml(), historicoVentas()]);
  const service = createAuditoriaService(async () => pool);

  const acceso = await service.getBitacoraAcceso({ fechaInicial: '2026-01-01', fechaFinal: '2026-01-02', resultado: 'EXITOSO' });
  const dml = await service.getAuditoriaDml({ fechaInicial: '2026-01-01', tabla: 'Producto', operacion: 'UPDATE' });
  const ventas = await service.getHistoricoVentas({ fechaInicial: '2026-01-01', fechaFinal: '2026-01-02', cliente: 'Ana' });

  assert.equal(acceso.length, 1);
  assert.equal(dml.length, 1);
  assert.equal(ventas.length, 1);
  assert.match(pool.calls[0].sqlText, /Bitacora_Acceso/);
  assert.match(pool.calls[1].sqlText, /fn_ConsultarAuditoria/);
  assert.match(pool.calls[2].sqlText, /fn_ObtenerHistoricoVentas/);
});

test('HTTP auditoría: redirige sin sesión, 403 sin permiso y 200 con permiso', async (t) => {
  const pool = fakePool([bitacoraAcceso(), auditoriaDml(), historicoVentas()]);
  const service = createAuditoriaService(async () => pool);

  const app = createApp({
    secret: 'secreto-exclusivo-de-pruebas-locales-1234',
    production: false,
    authService: {
      login: async (nombreUsuario, password) => ({
        codigo: 0,
        usuario: {
          usuarioId: 7,
          nombreUsuario,
          correo: 'admin@example.invalid',
          debeCambiarPassword: false,
          permisos: ['AUDITORIA_CONSULTAR'],
        },
      }),
    },
    auditoriaService: service,
  });

  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise((resolve) => { server.close(resolve); server.closeAllConnections(); }));

  const base = `http://127.0.0.1:${server.address().port}`;
  const request = (path, options = {}) => fetch(base + path, { redirect: 'manual', ...options });

  let response = await request('/auditoria');
  assert.equal(response.status, 302);
  assert.equal(response.headers.get('location'), '/login');

  const loginResponse = await fetch(base + '/login', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ NombreUsuario: 'admin', Password: 'secreto' }),
    redirect: 'manual',
  });
  assert.equal(loginResponse.status, 303);
  const cookie = loginResponse.headers.get('set-cookie').split(';')[0];

  response = await request('/auditoria', { headers: { cookie } });
  assert.equal(response.status, 200);
  const html = await response.text();
  assert.match(html, /BITÁCORA DE ACCESO/);
  assert.match(html, /AUDITORÍA DML/);
  assert.match(html, /HISTÓRICO DE VENTAS/);
  assert.doesNotMatch(html, /PasswordHash|TokenHash|db_owner/);

  const noPermissionApp = createApp({
    secret: 'secreto-exclusivo-de-pruebas-locales-1234',
    production: false,
    authService: {
      login: async () => ({
        codigo: 0,
        usuario: {
          usuarioId: 8,
          nombreUsuario: 'analista',
          correo: 'analista@example.invalid',
          debeCambiarPassword: false,
          permisos: ['OTRO_PERMISO'],
        },
      }),
    },
    auditoriaService: service,
  });
  const noPermissionServer = noPermissionApp.listen(0, '127.0.0.1');
  await once(noPermissionServer, 'listening');
  const noPermissionBase = `http://127.0.0.1:${noPermissionServer.address().port}`;
  const noPermissionLogin = await fetch(noPermissionBase + '/login', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ NombreUsuario: 'analista', Password: 'secreto' }),
    redirect: 'manual',
  });
  const noPermissionCookie = noPermissionLogin.headers.get('set-cookie').split(';')[0];
  const noPermissionResponse = await fetch(noPermissionBase + '/auditoria', {
    headers: { cookie: noPermissionCookie },
    redirect: 'manual',
  });
  assert.equal(noPermissionResponse.status, 403);
  assert.doesNotMatch(await noPermissionResponse.text(), /PasswordHash|TokenHash/);
  noPermissionServer.close();
  server.close();
});
