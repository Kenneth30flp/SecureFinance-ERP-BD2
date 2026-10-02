'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { readFileSync } = require('node:fs');
const { createApp } = require('../server');
const { createUsuarioService } = require('../src/services/usuarioService');

test('Usuarios HTTP: acceso, renderizado, CSRF, validaciones y errores seguros', async t => {
  const calls = [];
  let failure;
  let revoked = false;
  const service = {
    permisosActuales: async () => revoked ? [] : [{ Codigo: 'USUARIOS_ADMINISTRAR' }],
    listarUsuarios: async () => [{ UsuarioId: 2, NombreUsuario: 'cajero', NombreCompleto: 'Cajero DEMO', Correo: 'cajero.demo@example.invalid', Activo: true, Roles: 'Cajero' }],
    listarRolesActivos: async () => [{ RolId: 2, Nombre: 'Cajero', Descripcion: 'Ventas' }, { RolId: 3, Nombre: 'Auditor', Descripcion: 'Control' }],
    obtenerRolesUsuario: async id => { if (failure) throw failure; return [{ RolId: 2, Nombre: 'Cajero' }]; },
    actualizarRoles: async (...args) => { if (failure) throw failure; calls.push(args); },
  };
  const app = createApp({ dashboardService: { obtenerResumen: async () => null }, secret: 'secreto-exclusivo-pruebas-usuarios-123456789', production: false, usuarioService: service,
    authService: { login: async nombreUsuario => ({ codigo: 0, usuario: { usuarioId: 1, nombreUsuario, correo: 'test@example.invalid',
      permisos: nombreUsuario === 'admin' ? ['USUARIOS_ADMINISTRAR'] : nombreUsuario === 'cajero' ? ['VENTAS_REGISTRAR'] : ['AUDITORIA_CONSULTAR'] } }) } });
  const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = 'http://127.0.0.1:' + server.address().port;
  const request = (path, options = {}) => fetch(base + path, { redirect: 'manual', ...options });
  for (const path of ['/usuarios', '/usuarios/2/roles']) {
    const res = await request(path); assert.equal(res.status, 302); assert.equal(res.headers.get('location'), '/login');
  }
  const login = async user => (await request('/login', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ NombreUsuario: user, Password: 'test' }) })).headers.get('set-cookie').split(';')[0];
  for (const user of ['cajero', 'auditor']) {
    const cookie = await login(user);
    for (const [path, method] of [['/usuarios', 'GET'], ['/usuarios/2/roles', 'GET'], ['/usuarios/2/roles', 'POST']]) {
      const res = await request(path, { method, headers: { cookie } });
      assert.equal(res.status, 403); assert.match(await res.text(), /No tienes permiso para administrar usuarios/);
    }
    const dashboard = await request('/dashboard', { headers: { cookie } }); assert.doesNotMatch(await dashboard.text(), /href="\/usuarios"/);
  }
  const cookie = await login('admin');
  const page = await request('/usuarios', { headers: { cookie } }); assert.equal(page.status, 200);
  assert.equal(page.headers.get('cache-control'), 'no-store');
  const html = await page.text(); assert.match(html, /Cajero DEMO/); assert.match(html, /cajero.demo@example.invalid/);
  assert.match(html, /value="2"/); assert.match(html, /value="3"/); assert.doesNotMatch(html, /PasswordHash|Salt/);
  const csrf = html.match(/data-csrf="([a-f0-9]{64})"/)[1];
  const post = (Roles, id = '2', token = csrf) => request('/usuarios/' + id + '/roles', {
    method: 'POST', headers: { cookie, 'Content-Type': 'application/json', 'X-CSRF-Token': token }, body: JSON.stringify({ Roles, UsuarioId: 999, ActorUsuarioId: 999 }),
  });
  const assigned = await request('/usuarios/2/roles', { headers: { cookie } }); assert.deepEqual((await assigned.json()).roles, [{ RolId: 2, Nombre: 'Cajero' }]);
  assert.equal((await post([2], '2', 'bad')).status, 403);
  for (const roles of [[2], [3], [2,3], []]) {
    const res = await post(roles); assert.equal(res.status, 200); assert.match((await res.json()).mensaje, /actualizados/);
    assert.deepEqual(calls.at(-1), [2, roles, 1]);
  }
  const count = calls.length;
  for (const roles of [[2,2], [2,'2'], [0], [-1], [1.2], ['2e0'], [null], {}, '2']) assert.equal((await post(roles)).status, 400);
  for (const id of ['0','-1','abc','2147483648']) assert.equal((await post([2], id)).status, 400);
  assert.equal(calls.length, count);
  for (const [number, status, text] of [[53001,400,/usuario no existe/], [53002,400,/existir y estar activos/], [53003,409,/último administrador activo/], [53004,403,/No tienes permiso/], [999,503,/No fue posible/]]) {
    failure = Object.assign(new Error('PasswordHash Salt SQL private-secret'), { number });
    const res = await post([2]); assert.equal(res.status, status); const body = await res.text(); assert.match(body,text); assert.doesNotMatch(body,/PasswordHash|Salt|private-secret/);
  }
  failure = undefined; revoked = true;
  assert.equal((await request('/usuarios', { headers: { cookie } })).status, 403);
  assert.equal((await post([2])).status, 403);
});

test('UsuarioService: procedimientos exclusivos, parámetros tipados y TVP', async () => {
  const { sql } = require('../src/config/database');
  const calls = [];
  const service = createUsuarioService(async () => ({ request() {
    const inputs=[]; return { input(...args) { inputs.push(args); return this; }, async execute(procedure) { calls.push({ procedure, inputs }); return { recordset: [{ UsuarioId: 2 }] }; } };
  } }));
  await service.permisosActuales(1); await service.listarUsuarios(); await service.listarRolesActivos(); await service.obtenerRolesUsuario(2); await service.actualizarRoles(2,[2,3],1);
  assert.deepEqual(calls.map(c=>c.procedure), ['dbo.sp_ObtenerPermisosUsuario','dbo.sp_ListarUsuariosAdministracion','dbo.sp_ListarRolesActivos','dbo.sp_ObtenerRolesUsuario','dbo.sp_ActualizarRolesUsuario']);
  const inputs=calls.at(-1).inputs; assert.deepEqual(inputs[0],['UsuarioId',sql.Int,2]); assert.deepEqual(inputs[2],['ActorUsuarioId',sql.Int,1]);
  assert.equal(inputs[1].length,2); assert.equal(inputs[1][1].name,'TipoRolUsuario'); assert.deepEqual([...inputs[1][1].rows],[[2],[3]]);
});

test('Instalador completo sincronizado con nuevos procedimientos y permisos mínimos', () => {
  const full=readFileSync('database/SecureFinanceERP_Full.sql','utf8').replace(/\r\n/g,'\n');
  for (const file of ['database/08_AuditTriggers.sql','database/11_UserAdministration.sql','database/10_AppPermissions.sql']) assert.ok(full.includes(readFileSync(file,'utf8').replace(/\r\n/g,'\n')));
  const permissions=readFileSync('database/10_AppPermissions.sql','utf8');
  assert.doesNotMatch(permissions,/GRANT\s+(SELECT|INSERT|UPDATE|DELETE)/i);
});
