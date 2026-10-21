'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { filters, validDate, AnalyticsValidationError } = require('../src/modules/jose/analiticaValidation');
const { createAnaliticaService } = require('../src/modules/jose/analiticaService');

test('acepta fechas calendario válidas y rechaza fechas imposibles', () => {
  assert.equal(validDate('2026-02-28'), true);
  assert.equal(validDate('2026-02-29'), false);
  assert.equal(validDate('2026-13-01'), false);
});

test('usa mensual como período predeterminado', () => {
  assert.deepEqual(filters({}), { modo: 'MENSUAL', fechaDesde: null, fechaHasta: null, pagina: 1, desplazamiento: 0, limite: 10 });
});

test('normaliza los modos y pagina con límites razonables', () => {
  assert.deepEqual(filters({ modo: 'diario', pagina: '2' }), { modo: 'DIARIO', fechaDesde: null, fechaHasta: null, pagina: 2, desplazamiento: 10, limite: 10 });
  assert.equal(filters({ pagina: '1000' }).pagina, 100);
});

test('exige rango completo y ordenado', () => {
  assert.throws(() => filters({ modo: 'RANGO', fechaDesde: '2026-04-02' }), AnalyticsValidationError);
  assert.throws(() => filters({ modo: 'RANGO', fechaDesde: '2026-04-03', fechaHasta: '2026-04-02' }), /invertido/);
  assert.deepEqual(filters({ modo: 'RANGO', fechaDesde: '2026-04-01', fechaHasta: '2026-04-03' }).modo, 'RANGO');
});

test('rechaza modos y fechas no soportados', () => {
  assert.throws(() => filters({ modo: 'ANUAL' }), /período válido/);
  assert.throws(() => filters({ modo: 'DIARIO', fechaDesde: '2026-02-30' }), /YYYY-MM-DD/);
});

test('servicio usa procedimiento y parámetros tipados sin concatenar filtros', async () => {
  const calls = [];
  const request = {
    input(name, type, value) { calls.push({ name, type, value }); return this; },
    async execute(name) {
      assert.equal(name, 'dbo.sp_ObtenerDashboardVentas');
      return { recordsets: [[{ VentasRango: '0.00' }], [], [], [], []] };
    },
  };
  const dashboard = await createAnaliticaService(async () => ({ request: () => request })).obtenerDashboard(7, {
    modo: 'RANGO', fechaDesde: '2026-04-01', fechaHasta: '2026-04-03', limite: 10, desplazamiento: 0,
  });
  assert.equal(dashboard.kpis.VentasRango, '0.00');
  assert.deepEqual(calls.map(item => item.name), ['ActorUsuarioId', 'Modo', 'FechaDesde', 'FechaHasta', 'Limite', 'Desplazamiento']);
  assert.equal(calls[1].value, 'RANGO');
  assert.equal(calls[2].value, '2026-04-01');
});
