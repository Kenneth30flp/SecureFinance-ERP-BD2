'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { randomUUID } = require('node:crypto');
const v = require('../src/modules/creditos/validation');
const { createCreditoService } = require('../src/modules/creditos/service');
const { createApp } = require('../server');
const permissions = ['CREDITOS_CONSULTAR', 'CREDITOS_ADMINISTRAR', 'CREDITOS_ABONAR', 'CREDITOS_FACTURAR', 'COTIZACIONES_CONVERTIR', 'VENTAS_REGISTRAR'];
const payment = () => ({ ClienteId: '3', FacturaId: '7', Monto: '500.00', Referencia: 'Transferencia <script>unsafe</script>', OperacionId: randomUUID() });
const profile = () => ({ ClienteId: '3', Activo: '1', Limite: '5000.00', PlazoDias: '30', VersionEsperada: '000000000000001A', Motivo: 'Autorizado', OperacionId: randomUUID() });
const conversion = () => ({ CotizacionId: '5', PlazoDias: '30', NumeroCuotas: '3', BodegaId: '', OperacionId: randomUUID() });
const receipt = op => ({ AbonoId: '9007199254740993', ReciboId: '9007199254740994', ClienteId: 3, FacturaId: 7, ActorUsuarioId: 42,
  OperacionId: op, FechaHora: new Date('2026-10-28T18:00:00Z'), Monto: '500.00', SaldoPosterior: '1500.00', Referencia: 'Transferencia <script>unsafe</script>' });
function readSets() {
  return [[{ FacturaId: 7, ClienteId: 3, Cliente: '<script>unsafe</script>', NIT: 'QA', Estado: 'PARCIAL',
    Total: '2000.00', Saldo: '1500.00', FechaHora: new Date(), VenceEn: new Date() }],
  [{ ClienteId: 3, Nombre: '<script>unsafe</script>', NIT: 'QA', ClienteActivo: true, Activo: true,
    Limite: '5000.00', Deuda: '1500.00', Disponible: '3500.00', PlazoDias: 30, Version: '000000000000001A' }],
  [{ FacturaId: 7, Numero: 1, Importe: '666.66', Abonado: '500.00', Saldo: '166.66', Estado: 'PARCIAL', VenceEn: new Date() }],
  [receipt(randomUUID())], [{ Evento: 'ABONO', ActorUsuarioId: 42, Motivo: '<script>unsafe</script>', OperacionId: randomUUID(), FechaHora: new Date() }]];
}
function cashSets() {
  return [[{ EfectivoContado: '224.00', EfectivoAbonos: '500.00', EfectivoTotal: '724.00' }], [
    { Origen: 'ABONO', DocumentoId: '9007199254740994', FacturaId: 7, AbonoId: '9007199254740993', FechaHora: new Date(), Monto: '500.00' },
    { Origen: 'CONTADO', DocumentoId: '8', FacturaId: 8, AbonoId: null, FechaHora: new Date(), Monto: '224.00' },
  ]];
}
function poolFixture() {
  const calls = [], state = { error: null, sets: null };
  const provider = async () => ({ request() {
    const params = [];
    return { input(...args) { params.push(args); return this; }, async execute(name) {
      calls.push({ name, params });
      if (state.error) throw state.error;
      if (state.sets) return { recordsets: state.sets };
      const value = key => params.find(p => p[0] === key)?.[2];
      const op = value('OperacionId');
      const sets = name === 'dbo.P3_CRE_ConsultarCaja' ? cashSets() : name === 'dbo.P3_CRE_Consultar' ? readSets()
        : name === 'dbo.sp_RegistrarAbonoCliente' ? [[receipt(op)]]
          : name === 'dbo.P3_CRE_ConsultarRecibo' ? [[receipt(op)], [{ Numero: 1, Monto: '500.00' }]]
            : name === 'dbo.P3_CRE_AdministrarCredito' ? [[{ ClienteId: 3, Activo: value('Activo'), Limite: value('Limite'), PlazoDias: value('PlazoDias'), Version: '000000000000001B', OperacionId: op }]]
              : [[{ FacturaId: 7, Total: '2000.00' }], [{ PrecioUnitario: '1785.71' }], [{ FacturaId: 7, CotizacionId: 5, Estado: 'PROCESADA', OperacionId: op }]];
      return { recordsets: sets };
    } };
  } });
  return { calls, state, service: createCreditoService(provider) };
}
async function fixture(t, perms = permissions) {
  const pool = poolFixture();
  const app = createApp({ secret: 'creditos-isolated-http-fixture-secret-32', production: false, creditoService: pool.service,
    authService: { login: async () => ({ codigo: 0, usuario: { usuarioId: 42, nombreUsuario: 'Fixture', permisos: perms, debeCambiarPassword: false } }) } });
  const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = 'http://127.0.0.1:' + server.address().port;
  const login = await fetch(base + '/login', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'NombreUsuario=Fixture&Password=fixture', redirect: 'manual' });
  const cookie = login.headers.get('set-cookie').split(';')[0];
  const request = (url, options = {}) => fetch(base + url, { redirect: 'manual', ...options, headers: { Cookie: cookie, ...options.headers } });
  const post = (url, body, csrf) => request(url, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf || '' }, body: JSON.stringify(body) });
  const html = perms.includes('CREDITOS_CONSULTAR') ? await (await request('/creditos?clienteId=3&facturaId=7')).text() : '';
  const csrf = html.match(/name="csrf-token" content="([a-f0-9]+)"/)?.[1];
  return { ...pool, base, request, post, html, csrf };
}
test('CRE amounts: normalized strings preserve DECIMAL19,2 maximum exactly', () => {
  for (const [input, output] of [['1', '1.00'], ['0.01', '0.01'], ['10.5', '10.50'], ['99999999999999999.99', '99999999999999999.99']]) assert.equal(v.amount(input), output);
});
for (const input of [0, 1.5, null, undefined, {}, [], '0', '0.00', '-1', '1e2', '+1', '01', '.01', '1.', ' 1.00', '1,00', 'NaN', '0.001', '100000000000000000.00']) {
  test('CRE amounts reject ' + JSON.stringify(input), () => assert.throws(() => v.amount(input), v.ValidationError));
}
test('CRE identifiers: bigint canonical strings, UUID v4, rowversion, no coercion arrays', () => {
  assert.equal(v.bigint('9223372036854775807'), '9223372036854775807'); assert.equal(v.bigint('9007199254740993'), '9007199254740993');
  for (const x of ['0', '01', '9223372036854775808', 42, ['3'], '3.0']) assert.throws(() => v.bigint(x));
  for (const x of ['bad', [], 42]) assert.throws(() => v.uuid(x));
  assert.equal(v.version('abcdefabcdefabcd'), 'ABCDEFABCDEFABCD'); assert.equal(v.version(''), null);
  assert.throws(() => v.version('0xabcdefabcdefabcd')); assert.throws(() => v.integer(['1']));
});
test('CRE forms validate state, reason, ownership IDs and plan bounds', () => {
  assert.equal(v.profile(profile()).Activo, true); assert.equal(v.profile({ ...profile(), VersionEsperada: '', Activo: '0' }).VersionEsperada, null);
  for (const change of [{ Activo: 'true' }, { Motivo: '' }, { Motivo: 'a'.repeat(251) }, { PlazoDias: '3651' }, { ClienteId: 0 }, { VersionEsperada: 'bad' }]) assert.throws(() => v.profile({ ...profile(), ...change }));
  for (const change of [{ Referencia: ' ' }, { Referencia: 'a'.repeat(101) }, { FacturaId: '0' }, { OperacionId: 'bad' }]) assert.throws(() => v.payment({ ...payment(), ...change }));
  for (const change of [{ NumeroCuotas: '31' }, { NumeroCuotas: '121', PlazoDias: '200' }, { BodegaId: 0 }, { PlazoDias: '3651' }]) assert.throws(() => v.conversion({ ...conversion(), ...change }));
  assert.equal(v.conversion(conversion()).BodegaId, null); assert.equal(v.conversion({ ...conversion(), BodegaId: '2' }).BodegaId, 2);
});
test('CRE filters: Guatemala exclusive UTC, pagination and invalid repeated values', () => {
  const f = v.filters({ clienteId: '3', facturaId: '7', estado: 'VENCIDA', desde: '2026-10-01', hasta: '2026-10-02', pagina: '2' });
  assert.equal(f.Desde.toISOString(), '2026-10-01T06:00:00.000Z'); assert.equal(f.Hasta.toISOString(), '2026-10-03T06:00:00.000Z'); assert.equal(f.pagina, 2);
  for (const q of [{ estado: ['PARCIAL'] }, { clienteId: 0 }, { facturaId: 0 }, { desde: '2026-02-30' }, { hasta: [] }, { pagina: '100002' }, { pagina: 0 }, { desde: '2026-11-02', hasta: '2026-11-01' }, { facturaId: '7;DROP' }]) assert.throws(() => v.filters(q));
});
test('CRE service: amounts sent as typed RPC strings, rowversion binary and session actor', async () => {
  const f = poolFixture(), d = profile(); d.Limite = '99999999999999999.99'; await f.service.profile(42, d);
  const call = f.calls[0], param = name => call.params.find(p => p[0] === name);
  assert.equal(call.name, 'dbo.P3_CRE_AdministrarCredito'); assert.equal(param('ActorUsuarioId')[2], 42);
  assert.equal(param('Limite')[2], d.Limite); assert.equal(param('Limite')[1].length, 21);
  assert.equal(param('Limite')[1].type.name, 'NVarChar'); assert.equal(param('VersionEsperada')[2].toString('hex'), '000000000000001a');
  await f.service.payment(42, payment()); assert.equal(f.calls[1].params.find(p => p[0] === 'Monto')[2], '500.00');
});
test('CRE service: parameterized read filters, pagination, bigint and no arbitrary SQL API', async () => {
  const f = poolFixture(); f.state.sets = [Array.from({ length: 21 }, () => readSets()[0][0]), [], [], [], []];
  const result = await f.service.list(42, v.filters({ pagina: '2' })); assert.equal(result.cuentas.length, 20); assert.equal(result.next, true);
  assert.equal(f.calls[0].params.find(p => p[0] === 'Desplazamiento')[2], 20);
  f.state.sets = null; await f.service.receipt(42, '9007199254740993');
  assert.equal(f.calls[1].params.find(p => p[0] === 'AbonoId')[2], '9007199254740993');
});
test('CRE service: conversion fixed signature excludes browser prices and terms are typed', async () => {
  const f = poolFixture(), d = conversion(); const result = await f.service.convert(42, { ...d, ActorUsuarioId: 999, PrecioUnitario: '0.01' });
  assert.equal(result.factura.Total, '2000.00'); assert.equal(f.calls[0].name, 'dbo.P3_CRE_ConvertirCotizacionCredito');
  assert.deepEqual(f.calls[0].params.map(p => p[0]), ['ActorUsuarioId', 'CotizacionId', 'OperacionId', 'PlazoDias', 'NumeroCuotas', 'BodegaId']);
  assert.equal(f.calls[0].params.find(p => p[0] === 'OperacionId')[2], d.OperacionId);
});
test('CRE service: incompatible responses are not confirmations', async () => {
  const f = poolFixture(); f.state.sets = [[{ ...receipt(randomUUID()), AbonoId: 1 }]];
  await assert.rejects(() => f.service.payment(42, payment()));
  f.state.sets = [[{ FacturaId: 7 }], [], [{ CotizacionId: 5, FacturaId: 8, Estado: 'PROCESADA', OperacionId: randomUUID() }]];
  await assert.rejects(() => f.service.convert(42, conversion()));
  f.state.sets = []; await assert.rejects(() => f.service.list(42, v.filters({})), /incompatible/);
  await assert.rejects(() => f.service.receipt(42, '1'), /incompatible/);
});
test('CRE HTTP: actual createApp routes render escaped EJS, profile, cuotas and receipt', async t => {
  const f = await fixture(t); assert.match(f.html, /Disponible derivado/); assert.match(f.html, /Q 3,500.00/);
  assert.match(f.html, /&lt;script&gt;unsafe&lt;\/script&gt;/); assert.doesNotMatch(f.html, /<script>unsafe<\/script>/);
  assert.match(f.html, /data-cre-form="perfil"/); assert.match(f.html, /data-cre-form="conversion"/); assert.match(f.html, /data-cre-form="abono"/);
  const r = await f.request('/creditos/recibos/9007199254740993'); assert.equal(r.status, 200);
  const html = await r.text(); assert.match(html, /REC-9007199254740994/); assert.match(html, /Q 500.00/); assert.doesNotMatch(html, /<script>unsafe/);
  assert(f.calls.every(c => c.name.startsWith('dbo.P3_CRE_Consultar')));
  for (const asset of ['/css/styles.css', '/css/navigation.css', '/css/creditos.css', '/js/creditos.js', '/vendor/bootstrap/css/bootstrap.min.css']) {
    assert.equal((await f.request(asset)).status, 200, asset);
  }
});
test('CRE HTTP: unauthenticated redirect, readonly cache, invalid filters and receipt ID', async t => {
  const f = await fixture(t);
  assert.equal((await fetch(f.base + '/creditos', { redirect: 'manual' })).status, 302);
  assert.equal((await f.request('/creditos')).headers.get('cache-control'), 'no-store');
  for (const path of ['/creditos?pagina=0', '/creditos?desde=bad', '/creditos?estado=X', '/creditos/recibos/01']) assert.equal((await f.request(path)).status, 400);
  f.state.sets = [[], []]; assert.equal((await f.request('/creditos/recibos/1')).status, 404);
});
test('CRE HTTP: CSRF fails before writes, no global token replacement', async t => {
  const f = await fixture(t), count = f.calls.length;
  for (const token of ['', 'bad', 'a'.repeat(64)]) assert.equal((await f.post('/creditos/abonos', payment(), token)).status, 403);
  assert.equal(f.calls.length, count);
  const response = await f.request('/creditos/perfil', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ ...profile(), csrf: f.csrf }) });
  assert.equal(response.status, 200);
});
test('CRE HTTP: Auditor consultation only and Cajero cannot administer or credit-invoice', async t => {
  const auditor = await fixture(t, ['CREDITOS_CONSULTAR']); assert.doesNotMatch(auditor.html, /data-cre-form=/);
  for (const route of ['/creditos/perfil', '/creditos/abonos', '/creditos/conversiones']) assert.equal((await auditor.post(route, {}, auditor.csrf)).status, 403);
  const cashier = await fixture(t, ['CREDITOS_CONSULTAR', 'CREDITOS_ABONAR']); assert.match(cashier.html, /data-cre-form="abono"/);
  assert.doesNotMatch(cashier.html, /data-cre-form="perfil"|data-cre-form="conversion"/);
  assert.equal((await cashier.post('/creditos/perfil', profile(), cashier.csrf)).status, 403);
  assert.equal((await cashier.post('/creditos/conversiones', conversion(), cashier.csrf)).status, 403);
  assert.equal((await cashier.post('/creditos/abonos', payment(), cashier.csrf)).status, 200);
});
test('CRE HTTP: permission-free session denied for all module endpoints', async t => {
  const f = await fixture(t, []);
  for (const path of ['/creditos', '/creditos/caja', '/creditos/recibos/1']) assert.equal((await f.request(path)).status, 403);
  for (const path of ['/creditos/perfil', '/creditos/abonos', '/creditos/conversiones']) assert.equal((await f.post(path, {})).status, 403);
  assert.equal(f.calls.length, 0);
});
test('CRE HTTP: all three conversion permissions required', async t => {
  for (const missing of ['CREDITOS_FACTURAR', 'COTIZACIONES_CONVERTIR', 'VENTAS_REGISTRAR']) {
    const f = await fixture(t, permissions.filter(p => p !== missing));
    assert.equal((await f.post('/creditos/conversiones', conversion(), f.csrf)).status, 403);
  }
});
test('CRE HTTP: session actor and same UUID reach SQL on repeat; money remains string', async t => {
  const f = await fixture(t), d = payment();
  for (let i = 0; i < 2; i++) {
    const r = await f.post('/creditos/abonos', { ...d, ActorUsuarioId: 999, UsuarioId: 999 }, f.csrf);
    assert.equal(r.status, 200); const body = await r.json(); assert.equal(body.recibo.Monto, '500.00'); assert.equal(body.url, '/creditos/recibos/9007199254740993');
  }
  const calls = f.calls.filter(c => c.name === 'dbo.sp_RegistrarAbonoCliente'); assert.equal(calls.length, 2);
  for (const c of calls) { assert.equal(c.params[0][2], 42); assert.equal(c.params.find(p => p[0] === 'OperacionId')[2], d.OperacionId); }
});
test('CRE HTTP: profile and conversion endpoints end-to-end with pool mocks', async t => {
  const f = await fixture(t); const p = await f.post('/creditos/perfil', profile(), f.csrf); assert.equal(p.status, 200);
  const d = conversion(), r = await f.post('/creditos/conversiones', { ...d, BodegaId: '2', Detalle: [{ PrecioUnitario: 0 }] }, f.csrf);
  assert.equal(r.status, 200); assert.equal((await r.json()).url, '/creditos?facturaId=7');
  const c = f.calls.find(c => c.name === 'dbo.P3_CRE_ConvertirCotizacionCredito');
  assert.equal(c.params.find(p => p[0] === 'BodegaId')[2], 2); assert(!c.params.some(p => p[0] === 'Detalle'));
});
test('CRE HTTP: invalid input never reaches SQL write procedures', async t => {
  const f = await fixture(t); const count = f.calls.length;
  for (const d of [{ ...payment(), Monto: 500 }, { ...payment(), Monto: '0.001' }, { ...payment(), FacturaId: '0' }]) assert.equal((await f.post('/creditos/abonos', d, f.csrf)).status, 400);
  assert.equal((await f.post('/creditos/perfil', { ...profile(), VersionEsperada: 'bad' }, f.csrf)).status, 400);
  assert.equal((await f.post('/creditos/conversiones', { ...conversion(), NumeroCuotas: '40' }, f.csrf)).status, 400);
  assert.equal(f.calls.length, count);
});
test('CRE HTTP: uncertain result retains form UUID across GET, no secret leakage or fake success', async t => {
  const f = await fixture(t), op = f.html.match(/name="OperacionId" value="([^"]+)"/)[1];
  f.state.error = Error('TLS SQL password SECRET');
  const r = await f.post('/creditos/abonos', { ...payment(), OperacionId: op }, f.csrf); assert.equal(r.status, 503);
  const result = await r.json(); assert.equal(result.incierto, true); assert.doesNotMatch(result.error, /SECRET|password/);
  assert.equal((await f.request('/creditos')).status, 503); f.state.error = null;
  const html = await (await f.request('/creditos?clienteId=3')).text(); assert.match(html, new RegExp('value="' + op + '"'));
});
test('CRE HTTP: fixed SQL error mapping, SQL RBAC still applies after login', async t => {
  const f = await fixture(t);
  for (const [number, status] of [[54101, 403], [57002, 400], [57003, 409], [57004, 404], [57005, 409], [57006, 409],
    [57008, 409], [57009, 409], [54910, 409], [54903, 409], [54803, 409], [52010, 409], [52012, 403], [2812, 503]]) {
    f.state.error = Object.assign(Error('SECRET SQL'), { number });
    const r = await f.post('/creditos/abonos', payment(), f.csrf); assert.equal(r.status, status);
    const body = await r.json(); assert.equal(body.incierto, status === 503); assert.doesNotMatch(body.error, /SECRET/);
  }
});
test('CRE caja service: typed date filters, session actor, pagination and canonical strings', async () => {
  const f = poolFixture(), filters = v.filters({ desde: '2026-10-01', hasta: '2026-10-02', pagina: '2' });
  const result = await f.service.cash(42, filters), c = f.calls[0];
  assert.equal(c.name, 'dbo.P3_CRE_ConsultarCaja');
  assert.deepEqual(c.params.map(p => p[0]), ['ActorUsuarioId', 'Desde', 'Hasta', 'Desplazamiento']);
  assert.equal(c.params[0][2], 42); assert.equal(c.params[1][2].toISOString(), '2026-10-01T06:00:00.000Z');
  assert.equal(c.params[2][2].toISOString(), '2026-10-03T06:00:00.000Z'); assert.equal(c.params[3][2], 20);
  assert.equal(result.resumen.EfectivoAbonos, '500.00'); assert.equal(result.movimientos[0].DocumentoId, '9007199254740994');
  f.state.sets = [cashSets()[0], Array.from({ length: 21 }, () => cashSets()[1][0])];
  const page = await f.service.cash(42, filters); assert.equal(page.next, true); assert.equal(page.movimientos.length, 20);
});
test('CRE caja HTTP: own dashboard indicator and unified cash page, not full invoice debt', async t => {
  const f = await fixture(t); assert.match(f.html, /Efectivo recibido por abonos/); assert.match(f.html, /Todos los clientes; solo aplica el rango/);
  const response = await f.request('/creditos/caja?desde=2026-10-01&hasta=2026-10-02&pagina=2&ActorUsuarioId=999');
  assert.equal(response.status, 200); assert.equal(response.headers.get('cache-control'), 'no-store');
  const html = await response.text(); assert.match(html, /Caja unificada/); assert.match(html, /Q 724.00/);
  assert.match(html, /CONTADO/); assert.match(html, /ABONO/); assert.match(html, /\/creditos\/recibos\/9007199254740993/);
  assert.doesNotMatch(html, /Q 2,000.00/); assert.equal(f.calls.at(-1).params[0][2], 42);
  assert.equal((await fetch(f.base + '/creditos/caja', { redirect: 'manual' })).status, 302);
  for (const path of ['/creditos/caja?desde=invalid', '/creditos/caja?pagina=0', '/creditos/caja?desde=2026-11-02&hasta=2026-11-01']) assert.equal((await f.request(path)).status, 400);
});
test('CRE caja HTTP: Auditor consultation, real zero and DECIMAL38 summary preserved without Number', async t => {
  const f = await fixture(t, ['CREDITOS_CONSULTAR']);
  f.state.sets = [[{ EfectivoContado: '0.00', EfectivoAbonos: '0.00', EfectivoTotal: '0.00' }], []];
  let r = await f.request('/creditos/caja'); assert.equal(r.status, 200); assert.match(await r.text(), /Sin movimientos/);
  const total = '100000000000000000.01';
  f.state.sets = [[{ EfectivoContado: '0.00', EfectivoAbonos: total, EfectivoTotal: total }], []];
  r = await f.request('/creditos/caja'); assert.equal(r.status, 200); assert.match(await r.text(), /Q 100,000,000,000,000,000.01/);
});
test('CRE caja HTTP: missing SQL contract, denied SQL permission or malformed money never become a fake zero', async t => {
  const f = await fixture(t);
  for (const number of [2812, 54101]) {
    f.state.error = Object.assign(Error('SECRET'), { number }); const r = await f.request('/creditos/caja');
    assert.equal(r.status, number === 54101 ? 403 : 503); assert.doesNotMatch(await r.text(), /SECRET/);
  }
  f.state.error = null;
  for (const sets of [[], [[], []], [[{ EfectivoContado: '0.00', EfectivoAbonos: 500, EfectivoTotal: '500.00' }], []],
    [cashSets()[0], [{ ...cashSets()[1][0], Origen: 'DEUDA' }]], [cashSets()[0], [{ ...cashSets()[1][0], DocumentoId: 1 }]]]) {
    f.state.sets = sets; assert.equal((await f.request('/creditos/caja')).status, 503);
  }
});
