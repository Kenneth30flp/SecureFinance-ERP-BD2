'use strict';

// Local cross-worktree QA only. No server.js, dotenv, SQL connection or Git merge.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { randomUUID } = require('node:crypto');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const express = require('express');
const root = path.resolve(__dirname, '..');
const credit = path.resolve(root, '..', 'SecureFinance-ERP-BD2-creditos');
const warehouse = path.resolve(root, '..', 'SecureFinance-ERP-BD2-multibodega');
const { createAuditoriaDdlRoutes } = require('../src/routes/auditoriaDdlRoutes');
const { createCreditoRoutes } = require(path.join(credit, 'src/modules/creditos/routes'));
const { createMultibodegaRoutes } = require(path.join(warehouse, 'src/modules/multibodega/routes'));
const catalogs = [root, credit, warehouse].map(p => require(path.join(p, 'src/config/moduleCatalog')));
const modules = new Map();
for (const catalog of catalogs) for (const module of catalog.modules) {
  if (module.available) modules.set(module.id, module);
}
const permissions = ['AUDITORIA_DDL_CONSULTAR', 'CREDITOS_CONSULTAR', 'CREDITOS_ADMINISTRAR',
  'CREDITOS_ABONAR', 'CREDITOS_FACTURAR', 'BODEGAS_CONSULTAR', 'BODEGAS_ADMINISTRAR',
  'TRANSFERENCIAS_CREAR', 'TRANSFERENCIAS_DESPACHAR', 'TRANSFERENCIAS_RECIBIR',
  'COTIZACIONES_CONVERTIR', 'VENTAS_REGISTRAR', 'INVENTARIO_REGISTRAR'];
const command = 'CREATE TABLE dbo.P3_DDL_QA_Integracion (Id int);';
const event = { BitacoraDdlId: '1', FechaHora: '2026-10-28T18:00:00Z', TipoEvento: 'CREATE_TABLE',
  NombreObjeto: 'P3_DDL_QA_Integracion', TipoObjeto: 'TABLE', Esquema: 'dbo', UsuarioSQL: 'QA',
  LoginOriginal: 'QA', EquipoOrigen: 'fixture', AplicacionOrigen: 'fixture', BaseDatos: 'fixture',
  SesionId: 1, EstadoComando: 'EXACTO_EVENTDATA', ComandoTSql: command };

async function fixture(t) {
  const calls = [];
  const session = { usuario: { usuarioId: 42, nombreUsuario: 'QA', permisos: [...permissions], debeCambiarPassword: false } };
  const app = express();
  app.use(express.json());
  app.use(express.urlencoded({ extended: false }));
  app.set('view engine', 'ejs');
  app.set('views', [root, credit, warehouse].map(p => path.join(p, 'src/views')));
  app.locals.moduleAreas = user => catalogs[0].areas.map(area => ({ ...area,
    modules: [...modules.values()].filter(m => m.area === area.id
      && (!m.permissions.length || m.permissions.some(p => user.permisos.includes(p)))) }));
  app.use((req, res, next) => { req.session = session; next(); });
  app.use(createAuditoriaDdlRoutes({
    list: async actor => { calls.push(['ddl-list', actor]); return { rows: [event], total: '1', corteId: '1' }; },
    detail: async (actor, id) => { calls.push(['ddl-detail', actor, id]); return id === '1' ? event : null; },
  }));
  app.use(createCreditoRoutes({
    list: async actor => { calls.push(['credit-list', actor]); return { cuentas: [], perfil: null, cuotas: [], abonos: [], historial: [], next: false }; },
    cash: async actor => { calls.push(['credit-cash', actor]); return { resumen: { EfectivoContado: '0.00', EfectivoAbonos: '0.00', EfectivoTotal: '0.00' }, movimientos: [], next: false }; },
    payment: async (actor, data) => { calls.push(['credit-payment', actor, data]); return { AbonoId: '1', ReciboId: '1' }; },
  }));
  app.use(createMultibodegaRoutes({
    authorize: async (actor, p) => { calls.push(['warehouse-permission', actor, p]); },
    list: async actor => { calls.push(['warehouse-list', actor]); return { rows: [], evidence: [], next: false }; },
    mutate: async (actor, action, data) => { calls.push(['warehouse-mutation', actor, action, data]); return { TransferenciaId: 1 }; },
  }));
  const server = app.listen(0, '127.0.0.1');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  await once(server, 'listening');
  return { session, calls, request: (route, options = {}) => fetch('http://127.0.0.1:' + server.address().port + route,
    { redirect: 'manual', ...options }), post(route, body, token) { return this.request(route,
    { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token }, body: JSON.stringify(body) }); } };
}

test('Dylan conjunto HTTP MOCK: tres routers y navegacion conviven sin merge', async t => {
  const f = await fixture(t);
  for (const route of ['/auditoria/ddl', '/auditoria/ddl/1', '/creditos', '/creditos/caja',
    '/multibodega', '/multibodega?seccion=bodegas', '/multibodega?seccion=integraciones']) {
    const response = await f.request(route);
    assert.equal(response.status, 200, route);
    const html = await response.text();
    for (const link of ['/auditoria/ddl', '/creditos', '/multibodega']) assert.ok(html.includes('href="' + link + '"'), route + ': ' + link);
    if (route !== '/auditoria/ddl/1') assert.ok(!html.includes(command));
    assert.equal(response.headers.get('cache-control'), 'no-store');
  }
  assert.ok(!f.calls.some(c => /mutation|payment/.test(c[0])));
});

test('Dylan conjunto HTTP MOCK: tokens CSRF de Creditos y Bodegas no se intercambian', async t => {
  const f = await fixture(t);
  await f.request('/creditos'); await f.request('/multibodega');
  const cre = f.session.creditosCsrf, bod = f.session.multibodegaCsrf;
  assert.notEqual(cre, bod);
  const payment = { ClienteId: '1', FacturaId: '1', Monto: '500.00', Referencia: 'QA sintetica', OperacionId: randomUUID() };
  const transfer = { ProductoId: 1, OrigenId: 1, DestinoId: 2, Cantidad: 5, Motivo: 'QA sintetica', OperacionId: randomUUID() };
  assert.equal((await f.post('/creditos/abonos', payment, bod)).status, 403);
  assert.equal((await f.post('/multibodega/transferencias', transfer, cre)).status, 403);
  assert.ok(!f.calls.some(c => /mutation|payment/.test(c[0])));
  assert.equal((await f.post('/creditos/abonos', { ...payment, ActorUsuarioId: 999 }, cre)).status, 200);
  assert.equal((await f.post('/multibodega/transferencias', { ...transfer, ActorUsuarioId: 999 }, bod)).status, 200);
  for (const call of f.calls.filter(c => /mutation|payment/.test(c[0]))) assert.equal(call[1], 42);
});

test('Dylan conjunto HTTP MOCK: permiso de un modulo no abre los otros', async t => {
  const f = await fixture(t);
  for (const [permission, allowed] of [['AUDITORIA_DDL_CONSULTAR', '/auditoria/ddl'],
    ['CREDITOS_CONSULTAR', '/creditos'], ['BODEGAS_CONSULTAR', '/multibodega']]) {
    f.session.usuario.permisos = [permission];
    for (const route of ['/auditoria/ddl', '/creditos', '/multibodega']) {
      assert.equal((await f.request(route)).status, route === allowed ? 200 : 403, permission + ': ' + route);
    }
  }
});

test('Dylan conjunto SOLO TEXTO: contrato de bodega y conversor coincide entre ramas', () => {
  const read = (p, file) => readFileSync(path.join(p, 'database', file), 'utf8');
  const helper = read(warehouse, '81_P3_BOD_Contratos.sql');
  const cre = read(credit, '77_P3_CRE_ConversionPublica.sql');
  const bod = read(warehouse, '85_P3_BOD_Integraciones.sql');
  assert.match(helper, /PROCEDURE dbo\.P3_BOD_ValidarBodegaVenta\s+@ActorUsuarioId INT\s*,\s*@BodegaId INT/i);
  assert.match(cre, /EXEC dbo\.P3_BOD_ValidarBodegaVenta @ActorUsuarioId=@ActorUsuarioId,@BodegaId=@BodegaId/);
  assert.match(cre, /PROCEDURE dbo\.P3_CRE_ConvertirCotizacionCredito\s+@ActorUsuarioId INT,@CotizacionId INT,@OperacionId UNIQUEIDENTIFIER,@PlazoDias INT,@NumeroCuotas INT=1,@BodegaId INT=NULL/);
  assert.match(bod, /EXEC dbo\.P3_CRE_ConvertirCotizacionCredito @ActorUsuarioId=@ActorUsuarioId,@CotizacionId=@CotizacionId,@OperacionId=@OperacionId,@PlazoDias=@PlazoDias,@NumeroCuotas=@NumeroCuotas,@BodegaId=@BodegaId/);
});
