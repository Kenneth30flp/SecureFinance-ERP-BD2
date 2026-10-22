'use strict';
// Real SQL and real Express session; substitutes only authentication, never a real login.
// Sends GET requests only after the in-memory fixture session has been established.
require('dotenv').config({ quiet: true });
const fs = require('node:fs');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const statePath = '.data/erp-deployment.json';
const state = JSON.parse(fs.readFileSync(statePath, 'utf8').replace(/^\uFEFF/, ''));
process.env.DB_NAME = process.argv.includes('--main') ? 'SecureFinanceERP' : state.lab;
const { getPool, closePool, sql } = require('../../src/config/database');
const { verifyIntegration } = require('../../src/config/integration');
const { createApp } = require('../../server');
const { createProductoService } = require('../../src/services/productoService');
const { createProveedorService } = require('../../src/services/proveedorService');
const { createClienteService } = require('../../src/services/clienteService');
const { createInventarioService } = require('../../src/services/inventarioService');
const escape = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&#34;', "'": '&#39;' })[c]);
async function main() {
  let server;
  try {
    const pool = await getPool();
    const identity = await verifyIntegration(pool);
    const actor = 3;
    const permisos = (await pool.request().input('UsuarioId', sql.Int, actor).execute('dbo.sp_ObtenerPermisosUsuario')).recordset.map(p => p.Codigo);
    const app = createApp({ production: false, authService: { login: async () => ({ codigo: 0,
      usuario: { usuarioId: actor, nombreUsuario: 'QA_READ_ONLY_SESSION', permisos, debeCambiarPassword: false } }) } });
    server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
    const base = `http://127.0.0.1:${server.address().port}`;
    const session = await fetch(base + '/login', { method: 'POST', redirect: 'manual',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: 'NombreUsuario=QA_READ_ONLY_SESSION&Password=IN_MEMORY_FIXTURE' });
    assert.equal(session.status, 303);
    const cookie = session.headers.get('set-cookie').split(';')[0];
    const products = await createProductoService().list(actor, { inventario: true });
    const suppliers = await createProveedorService().list(actor, {});
    const clients = await createClienteService().list(actor, {});
    const routes = ['/dashboard', '/facturacion', '/inventario', '/productos', '/proveedores', '/clientes',
      '/devoluciones', '/notas-credito', '/garantias', '/analitica', '/auditoria', '/usuarios'];
    const results = [];
    async function check(route, expected = []) {
      const response = await fetch(base + route, { headers: { cookie }, redirect: 'manual' });
      const html = await response.text();
      assert.equal(response.status, 200, `${route}: HTTP ${response.status}`);
      assert.match(html, /<main\b/, route);
      assert.doesNotMatch(html, /No fue posible|módulo no está disponible|no está disponible\. Puedes abrir|no se pudo cargar|no se pudieron cargar/i, route);
      for (const text of expected) assert.ok(html.includes(escape(text)), `${route}: missing actual database value`);
      results.push({ route, status: response.status, realValuesChecked: expected.length });
      console.log('PASS SQL + EJS + RBAC ' + route);
      return html;
    }
    for (const route of routes) {
      const expected = route === '/inventario' || route === '/productos' ? products.map(p => p.Codigo)
        : route === '/proveedores' ? suppliers.map(p => p.Nombre)
        : route === '/clientes' ? clients.map(p => p.NIT) : [];
      await check(route, expected);
    }
    for (const product of products) {
      await check('/inventario?id=' + product.ProductoId, [product.Codigo, product.Stock]);
      await createInventarioService().history(actor, { id: product.ProductoId });
      await check('/productos?id=' + product.ProductoId + '&editar=1', [product.Codigo]);
    }
    for (const supplier of suppliers) await check('/proveedores?id=' + supplier.ProveedorId + '&editar=1', [supplier.Nombre]);
    for (const product of products.filter(p => p.Fotografia)) {
      const response = await fetch(base + '/fotografias/' + product.Fotografia, { headers: { cookie } });
      assert.equal(response.status, 200, 'Photograph for product ' + product.ProductoId);
      assert.match(response.headers.get('content-type'), /^image\/(png|jpeg)/);
      assert.ok((await response.arrayBuffer()).byteLength > 0);
      console.log('PASS fotografia real producto ' + product.ProductoId);
    }
    const edward = require('../../src/modules/edward/services').createEdwardService();
    const [returns] = await edward.devoluciones(actor, {});
    for (const entry of returns.slice(0, 3)) {
      await check('/devoluciones?id=' + entry.DevolucionId);
      if (entry.NotaCreditoId) {
        const [balances] = await edward.aplicaciones(actor, entry.NotaCreditoId);
        assert.equal(balances.length, 1, 'Actual credit balance must exist');
        await check('/notas-credito?id=' + entry.DevolucionId);
      }
      await check('/devoluciones?factura=' + entry.FacturaId);
    }
    const [warranties] = await edward.garantias(actor, {});
    for (const entry of warranties.slice(0, 3)) await check('/garantias?id=' + entry.TicketId);
    const result = { identity, authentication: 'SESSION_FIXTURE_NOT_REAL_LOGIN', writes: 'NONE_SQL', routes: results };
    fs.writeFileSync('.data/erp-readonly-' + (process.argv.includes('--main') ? 'main' : 'lab') + '.json', JSON.stringify(result, null, 2));
    if (!process.argv.includes('--main')) { state.readOnlyRoutesPassed = true; fs.writeFileSync(statePath, JSON.stringify(state, null, 2)); }
  } finally {
    if (server) await new Promise(resolve => server.close(resolve));
    await closePool();
  }
}
main().catch(e => { console.error(e); process.exitCode = 1; });
