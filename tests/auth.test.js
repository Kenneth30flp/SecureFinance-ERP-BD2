'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createApp } = require('../server');
const { createAuthService } = require('../src/services/authService');
const { sql } = require('../src/config/database');

// Doble del pool: nunca abre una conexión SQL ni consulta .env.
function fakePool(responses) {
  const calls = [];
  return {
    calls,
    request() {
      const inputs = [];
      return {
        input(name, type, value) { inputs.push({ name, type, value }); return this; },
        async execute(procedure) {
          calls.push({ procedure, inputs });
          const response = responses.shift();
          if (response instanceof Error) throw response;
          return response;
        },
      };
    },
  };
}
const success = () => ({ recordset: [{ Codigo: 0, Resultado: 'EXITOSO', UsuarioId: 1,
  NombreUsuario: '<script>demo</script>', Correo: 'demo@example.invalid', Activo: true, DebeCambiarPassword: true }] });
const permissions = () => ({ recordset: [{ Codigo: 'AUDITORIA_CONSULTAR' }, { Codigo: 'VENTAS_REGISTRAR' }] });

test('Servicio: parámetros tipados, procedimientos y datos permitidos', async () => {
  const pool = fakePool([success(), permissions()]);
  const result = await createAuthService(async () => pool).login('demo', ' prueba Unicode á ');
  assert.deepEqual(Object.keys(result.usuario).sort(), ['correo', 'debeCambiarPassword', 'nombreUsuario', 'permisos', 'usuarioId']);
  assert.deepEqual(pool.calls.map((call) => call.procedure), ['dbo.sp_Login', 'dbo.sp_ObtenerPermisosUsuario']);
  assert.equal(pool.calls[0].inputs[0].type.type, sql.NVarChar);
  assert.equal(pool.calls[0].inputs[0].type.length, sql.MAX);
  assert.equal(pool.calls[0].inputs[1].value, ' prueba Unicode á ');
  assert.equal(pool.calls[0].inputs[1].type.type, sql.NVarChar);
  assert.equal(pool.calls[1].inputs[0].type, sql.Int);
  assert.equal(pool.calls[1].inputs[0].value, 1);
});

test('Servicio: contrato inesperado se rechaza', async () => {
  const pool = fakePool([{ recordset: [{ Codigo: 0, Resultado: 'DESCONOCIDO' }] }]);
  await assert.rejects(createAuthService(async () => pool).login('demo', 'prueba'));
  assert.equal(pool.calls.length, 1);
});

test('HTTP: login, sesión, permisos escapados, errores y logout con SQL simulado', async (t) => {
  const responses = [];
  const pool = fakePool(responses);
  const app = createApp({ secret: 'secreto-exclusivo-de-pruebas-locales-1234', production: false,
    authService: createAuthService(async () => pool) });
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise((resolve) => { server.close(resolve); server.closeAllConnections(); }));
  const base = `http://127.0.0.1:${server.address().port}`;
  const request = (path, options = {}) => fetch(base + path, { redirect: 'manual', ...options });
  const post = (body) => request('/login', { method: 'POST', body: new URLSearchParams(body) });
  // Inyectar respuestas por solicitud mantiene el flujo HTTP y sesiones reales.
  for (const path of ['/', '/dashboard']) {
    const response = await request(path);
    assert.equal(response.status, 302);
    assert.equal(response.headers.get('location'), '/login');
  }
  let response = await request('/login');
  assert.equal(response.status, 200);
  assert.match(await response.text(), /name="Password"/);
  assert.equal(response.headers.get('set-cookie'), null);
  for (const [code, outcome] of [[3, 'PASSWORD_INCORRECTA'], [1, 'USUARIO_INEXISTENTE'], [2, 'USUARIO_INACTIVO']]) {
    responses.push({ recordset: [{ Codigo: code, Resultado: outcome }] });
    response = await post({ NombreUsuario: 'demo', Password: 'secreto-no-renderizable' });
    assert.equal(response.status, 401);
    const html = await response.text();
    assert.match(html, code === 2 ? /El usuario se encuentra inactivo\./ : /Usuario o contraseña incorrectos\./);
    assert.doesNotMatch(html, /secreto-no-renderizable|USUARIO_INEXISTENTE|PASSWORD_INCORRECTA/);
    assert.equal(response.headers.get('set-cookie'), null);
    assert.equal(responses.length, 0);
  }
  responses.push(success(), new Error('detalle SQL privado'));
  response = await post({ NombreUsuario: 'demo', Password: 'prueba' });
  assert.equal(response.status, 503);
  assert.doesNotMatch(await response.text(), /detalle SQL privado/);
  assert.equal((await request('/dashboard')).headers.get('location'), '/login');

  responses.push(success(), permissions());
  response = await post({ NombreUsuario: 'demo', Password: 'prueba' });
  assert.equal(response.status, 303);
  assert.equal(response.headers.get('location'), '/dashboard');
  const setCookie = response.headers.get('set-cookie');
  assert.match(setCookie, /HttpOnly/);
  assert.match(setCookie, /SameSite=Lax/);
  assert.doesNotMatch(setCookie, /; Secure/);
  const cookie = setCookie.split(';')[0];
  const authenticated = (path) => request(path, { headers: { cookie } });
  response = await authenticated('/dashboard');
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  const html = await response.text();
  assert.match(html, /AUDITORIA_CONSULTAR/);
  assert.match(html, /VENTAS_REGISTRAR/);
  assert.match(html, /&lt;script&gt;demo&lt;\/script&gt;/);
  assert.doesNotMatch(html, /<script>demo/);
  for (const path of ['/', '/login']) {
    assert.equal((await authenticated(path)).headers.get('location'), '/dashboard');
  }
  response = await authenticated('/logout');
  assert.equal(response.headers.get('location'), '/login');
  // Incluso reenviando el ID anterior, la sesión ya no autoriza acceso.
  assert.equal((await authenticated('/dashboard')).headers.get('location'), '/login');
  assert.deepEqual(await (await request('/health')).json(), { status: 'ok', phase: 3 });
  response = await post({ NombreUsuario: 'demo' });
  assert.equal(response.status, 400);
});
