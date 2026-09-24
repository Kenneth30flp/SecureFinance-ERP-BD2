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
        execute(procedure) {
          calls.push({ procedure, inputs });
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
  assert.equal(pool.calls[0].procedure, 'dbo.sp_ConsultarBitacoraAcceso');
  assert.equal(pool.calls[1].procedure, 'dbo.sp_ConsultarAuditoriaTransacciones');
  assert.equal(pool.calls[2].procedure, 'dbo.sp_ConsultarHistoricoVentas');
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
          permisos: ['AUDITORIA_CONSULTAR', 'VENTAS_REGISTRAR'],
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
  const dashboard = await request('/dashboard', { headers: { cookie } });
  const dashboardHtml = await dashboard.text();
  assert.ok(dashboardHtml.includes('href="/facturacion"'));
  assert.ok(dashboardHtml.includes('href="/auditoria"'));
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
  const deniedDashboard = await fetch(noPermissionBase + '/dashboard', { headers: { cookie: noPermissionCookie } });
  assert.ok(!(await deniedDashboard.text()).includes('href="/auditoria"'));
  assert.equal(pool.calls.length, 3);
  for (let failingIndex = 0; failingIndex < 3; failingIndex++) {
    const responses = [bitacoraAcceso(), auditoriaDml(), historicoVentas()];
    responses[failingIndex] = new Error('PasswordHash Salt TokenHash SESSION_SECRET DB_PASSWORD private-value');
    const failingPool = fakePool(responses);
    Object.assign(service, createAuditoriaService(async () => failingPool));
    const failed = await request('/auditoria', { headers: { cookie } });
    assert.equal(failed.status, 500);
    const body = await failed.text();
    assert.doesNotMatch(body, /Password|Salt|TokenHash|SESSION_SECRET|DB_PASSWORD|private-value/);
    assert.match(body, /No fue posible consultar/);
  }
  noPermissionServer.closeAllConnections();
  noPermissionServer.close();
  server.close();
});


test('Servicio: todos los filtros son tipados y los valores no son SQL', async () => {
  const { sql } = require('../src/config/database');
  const pool = fakePool([{recordset: []}, {recordset: []}, {recordset: []}]);
  const service = createAuditoriaService(async () => pool);
  const filters = {fechaInicial: '2026-01-01', fechaFinal: '2026-01-02', usuario: 'admin', resultado: 'EXITOSO', tabla: 'Producto', operacion: 'UPDATE', cliente: "Ana'; DROP TABLE Factura;--"};
  await service.getBitacoraAcceso(filters);
  await service.getAuditoriaDml(filters);
  await service.getHistoricoVentas(filters);
  const expected = [
    [['NombreUsuarioIntentado', sql.NVarChar(50), filters.usuario], ['Resultado', sql.VarChar(30), filters.resultado]],
    [['Tabla', sql.NVarChar(128), filters.tabla], ['Operacion', sql.VarChar(20), filters.operacion]],
    [['Cliente', sql.NVarChar(150), filters.cliente]],
  ];
  pool.calls.forEach((call, index) => {
    assert.deepEqual(call.inputs, [
      {name: 'FechaInicial', type: sql.DateTime2(3), value: new Date('2026-01-01T00:00:00.000Z')},
      {name: 'FechaFinal', type: sql.DateTime2(3), value: new Date('2026-01-02T23:59:59.999Z')},
      ...expected[index].map(([name,type,value]) => ({name,type,value})),
    ]);
  });
});

test('Servicio: sin filtros envia NULL y propaga errores de SQL', async () => {
  const pool = fakePool([{}, {}, {}]);
  const service = createAuditoriaService(async () => pool);
  for (const method of ['getBitacoraAcceso', 'getAuditoriaDml', 'getHistoricoVentas']) {
    assert.deepEqual(await service[method](), []);
  }
  assert.ok(pool.calls.every(call => call.inputs.every(input => input.value === null)));
  const error = Object.assign(new Error('fn_ObtenerHistoricoVentas no existe'), {number: 208});
  const failed = createAuditoriaService(async () => fakePool([error]));
  await assert.rejects(failed.getHistoricoVentas(), error);
});
