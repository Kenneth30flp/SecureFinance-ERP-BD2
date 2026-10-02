'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { readFileSync } = require('node:fs');
const { createApp } = require('../server');
const { createDashboardService } = require('../src/services/dashboardService');
const { sql } = require('../src/config/database');
const resumen = { VentasDia: '1245.50', FacturasDia: '12', ProductosStockBajo: '3', EventosDMLDia: '18', FechaOperacion: '2026-10-01', RolesActuales: 'Administrador' };

test('Dashboard: procedimiento tipado, importes exactos y contrato validado', async () => {
  const calls = [];
  let recordset = [resumen];
  const service = createDashboardService(async () => ({ request: () => ({
    input(name, type, value) { calls.push({ name, type, value }); return this; },
    async execute(name) { calls.push(name); return { recordset }; },
  }) }));
  assert.deepEqual(await service.obtenerResumen(17), resumen);
  assert.deepEqual(calls, [{ name: 'UsuarioId', type: sql.Int, value: 17 }, 'dbo.sp_ObtenerResumenDashboard']);
  for (const value of [[], [{ ...resumen, VentasDia: 'NaN' }], [{ ...resumen, FacturasDia: '-1' }]]) {
    recordset = value; await assert.rejects(service.obtenerResumen(17));
  }
});

test('Dashboard HTTP: autenticación, sesión real, KPIs escapados y fallo sin datos ficticios', async (t) => {
  let fail = false; const ids = [];
  const app = createApp({ secret: 'dashboard-tests-secret-12345678901234567890', production: false,
    authService: { login: async () => ({ codigo: 0, usuario: { usuarioId: 17, nombreUsuario: 'demo', permisos: ['VENTAS_REGISTRAR'] } }) },
    dashboardService: { obtenerResumen: async (id) => { ids.push(id); if (fail) throw new Error('SQL secret'); return { ...resumen, RolesActuales: '<script>role</script>' }; } },
  });
  const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = 'http://127.0.0.1:' + server.address().port;
  const anonymous = await fetch(base + '/dashboard', { redirect: 'manual' });
  assert.equal(anonymous.status, 302); assert.equal(ids.length, 0);
  const login = await fetch(base + '/login', { method: 'POST', redirect: 'manual', body: new URLSearchParams({ NombreUsuario: 'demo', Password: 'test' }) });
  const Cookie = login.headers.get('set-cookie').split(';')[0];
  let response = await fetch(base + '/dashboard?UsuarioId=999', { headers: { Cookie } });
  assert.equal(response.status, 200); assert.match(response.headers.get('cache-control'), /no-store/);
  let html = await response.text(); assert.match(html, /Q 1,245\.50/); assert.match(html, /&lt;script&gt;role/);
  assert.equal((html.match(/class="kpi-card"/g) || []).length, 4); assert.deepEqual(ids, [17]);
  fail = true; response = await fetch(base + '/dashboard', { headers: { Cookie } }); html = await response.text();
  assert.equal(response.status, 200); assert.match(html, /No fue posible obtener el resumen operativo/);
  assert.doesNotMatch(html, /SQL secret|Q 0\.00/); assert.match(html, /href="\/facturacion"/);
});

test('Dashboard SQL: instalador sincronizado y permiso EXECUTE exclusivo', () => {
  const module = readFileSync('database/14_DashboardSummary.sql', 'utf8').replace(/\r\n/g, '\n').trim();
  const full = readFileSync('database/SecureFinanceERP_Full.sql', 'utf8').replace(/\r\n/g, '\n');
  assert.ok(full.includes(module));
  assert.match(readFileSync('database/10_AppPermissions.sql', 'utf8'), /GRANT EXECUTE ON OBJECT::dbo\.sp_ObtenerResumenDashboard/);
  assert.doesNotMatch(module, /GRANT SELECT|FLOAT/);
});
