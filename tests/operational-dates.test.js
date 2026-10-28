'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const dates = require('../src/public/js/operationalDates');
const { createInventarioService } = require('../src/services/inventarioService');
const { createAuditoriaService } = require('../src/services/auditoriaService');
const { createEdwardService } = require('../src/modules/edward/services');
const validation = require('../src/modules/edward/validations');
const { createApp } = require('../server');
const stamp = '2026-10-22T04:19:00.000Z';

test('UTC instants display in Spanish Guatemala time, including previous-day rollover', () => {
  assert.equal(dates.formatDateTime(stamp), '21/10/2026, 22:19:00');
  assert.equal(dates.formatDateTime(new Date(stamp)), '21/10/2026, 22:19:00');
  assert.equal(dates.formatDateTime('2026-10-22T04:19:00'), '21/10/2026, 22:19:00');
  assert.equal(dates.formatDateTime('2026-10-21T22:19:00-06:00'), '21/10/2026, 22:19:00');
  assert.equal(dates.formatDate('2026-01-01T05:59:59Z'), '31/12/2025');
  assert.equal(dates.formatDateTime('2026-01-01T06:00:00Z'), '01/01/2026, 00:00:00');
  for (const value of [null, undefined, '', 'invalid']) assert.equal(dates.formatDateTime(value), 'No registrada');
});

test('Guatemala day filters include the late local evening and exclude both adjacent days', () => {
  const from = dates.localDayBoundary('2026-10-21');
  const until = dates.localDayBoundary('2026-10-21', true);
  const inclusive = dates.localDayBoundary('2026-10-21', true, true);
  assert.equal(from.toISOString(), '2026-10-21T06:00:00.000Z');
  assert.equal(until.toISOString(), '2026-10-22T06:00:00.000Z');
  assert.equal(inclusive.toISOString(), '2026-10-22T05:59:59.999Z');
  for (const [value, included] of [['2026-10-21T05:59:59.999Z', false],
    ['2026-10-21T06:00:00Z', true], [stamp, true],
    ['2026-10-22T05:59:59.999Z', true], ['2026-10-22T06:00:00Z', false]]) {
    const date = new Date(value);
    assert.equal(date >= from && date < until, included, value);
    assert.equal(date >= from && date <= inclusive, included, value + ' inclusive audit');
  }
  assert.equal(dates.localDayBoundary('2026-12-31', true).toISOString(), '2027-01-01T06:00:00.000Z');
  assert.equal(dates.localDayBoundary('2028-02-29', true).toISOString(), '2028-03-01T06:00:00.000Z');
  assert.throws(() => dates.localDayBoundary('2026-02-29'), RangeError);
  assert.equal(dates.localDayBoundary(''), null);
});

test('Kardex, returns, warranties and all audit services send local-day limits as typed UTC parameters', async () => {
  const calls = [];
  const provider = async () => ({ request: () => {
    const params = {};
    return { input(name, type, value) { params[name] = value; return this; },
      async execute(proc) { calls.push({ proc, params }); return { recordset: [], recordsets: [[]] }; } };
  } });
  await createInventarioService(provider).history(3, { id: 4, desde: '2026-10-21', hasta: '2026-10-21' });
  const filters = validation.filters({ desde: '2026-10-21', hasta: '2026-10-21' });
  await createEdwardService(provider).devoluciones(3, filters);
  await createEdwardService(provider).garantias(3, filters);
  for (const call of calls) {
    assert.equal(call.params.Desde.toISOString(), '2026-10-21T06:00:00.000Z');
    assert.equal(call.params.Hasta.toISOString(), '2026-10-22T06:00:00.000Z');
  }
  const audit = createAuditoriaService(provider);
  for (const method of ['getBitacoraAcceso', 'getAuditoriaDml', 'getHistoricoVentas']) {
    await audit[method]({ fechaInicial: '2026-10-21', fechaFinal: '2026-10-21' });
    const { params } = calls.at(-1);
    assert.equal(params.FechaInicial.toISOString(), '2026-10-21T06:00:00.000Z');
    assert.equal(params.FechaFinal.toISOString(), '2026-10-22T05:59:59.999Z');
  }
});

test('Rendered operational modules show Guatemala dates and labels, preserving UTC machine timestamps', async t => {
  const product = { ProductoId: 4, Codigo: 'SKU', Descripcion: 'Producto', Stock: 10, Precio: 10,
    Activo: true, StockMinimo: 1, PuntoReorden: 2, Version: '0000000000000001' };
  const entry = { DevolucionId: 1, NotaCreditoId: 1, FacturaId: 1, Cliente: 'Cliente', FechaHora: stamp,
    Estado: 'EMITIDA', EstadoCredito: 'PENDIENTE', Total: '10.00' };
  const warranty = { TicketId: 1, FacturaId: 1, FechaApertura: stamp, Estado: 'RECIBIDO', Version: product.Version };
  const app = createApp({ secret: 'timezone-render-tests-only-secret-12345', production: false,
    authService: { login: async () => ({ codigo: 0, usuario: { usuarioId: 3, nombreUsuario: 'QA',
      permisos: ['INVENTARIO_CONSULTAR', 'DEVOLUCIONES_CONSULTAR', 'GARANTIAS_CONSULTAR', 'AUDITORIA_CONSULTAR'] } }) },
    kennethServices: { productos: { list: async () => [product] }, inventario: {
      state: async () => [{ Habilitado: true }], history: async () => [{ FechaHora: stamp, TipoMovimiento: 'COMPRA', Motivo: 'Compra' }] } },
    edwardService: { devoluciones: async () => [[entry], []], aplicaciones: async () => [[{ SaldoDisponible: '10.00' }],
      [{ FechaHora: stamp, Monto: '1.00' }]], garantias: async () => [[warranty], [{ FechaHora: stamp, EstadoNuevo: 'RECIBIDO' }]] },
    auditoriaService: { getBitacoraAcceso: async () => [{ FechaHora: stamp }], getAuditoriaDml: async () => [], getHistoricoVentas: async () => [] },
  });
  const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = 'http://127.0.0.1:' + server.address().port;
  const session = await fetch(base + '/login', { method: 'POST', redirect: 'manual',
    body: new URLSearchParams({ NombreUsuario: 'QA', Password: 'fixture' }) });
  const cookie = session.headers.get('set-cookie').split(';')[0];
  for (const route of ['/inventario', '/devoluciones?id=1', '/notas-credito?id=1', '/garantias?id=1', '/auditoria']) {
    const response = await fetch(base + route, { headers: { cookie } });
    assert.equal(response.status, 200, route);
    const html = await response.text();
    assert.match(html, /21\/10\/2026, 22:19:00/, route);
    assert.match(html, /Guatemala.*UTC−6/, route);
    assert.doesNotMatch(html, /Fecha(?:s)? (?:· )?UTC|Fechas de filtro en UTC/, route);
    if (route === '/inventario') assert.ok(html.includes('datetime="' + stamp + '"'));
  }
});
