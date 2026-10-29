'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { randomUUID } = require('node:crypto');
const { readFileSync, readdirSync } = require('node:fs');
const path = require('node:path');
const { runInNewContext } = require('node:vm');
const { createApp } = require('../server');
const v = require('../src/modules/multibodega/validation');
const { createMultibodegaService } = require('../src/modules/multibodega/service');
const { sql } = require('../src/config/database');
const permissions = ['BODEGAS_CONSULTAR', 'BODEGAS_ADMINISTRAR', 'TRANSFERENCIAS_CREAR', 'TRANSFERENCIAS_DESPACHAR', 'TRANSFERENCIAS_RECIBIR', 'INVENTARIO_REGISTRAR', 'COTIZACIONES_CONVERTIR', 'VENTAS_REGISTRAR'];
const version = '00000000000000AB';
const proposal = () => ({ OperacionId: randomUUID(), ProductoId: 1, OrigenId: 1, DestinoId: 2, Cantidad: 5, Motivo: 'Traslado documentado' });
test('BOD validacion: cantidades enteras positivas, limites, origen distinto, UUID y version', () => {
  const p = proposal(); assert.deepEqual(v.mutation(p, 'preparar'), p);
  for (const value of [0, -1, 1.2, '1e2', ' 1 ', '2147483648', [], {}, null, true]) assert.throws(() => v.mutation({ ...p, Cantidad: value }, 'preparar'), v.ValidationError);
  for (const change of [{ DestinoId: 1 }, { Motivo: '' }, { Motivo: 'a'.repeat(251) }, { OperacionId: 'bad' }, { ProductoId: 0 }]) assert.throws(() => v.mutation({ ...p, ...change }, 'preparar'));
  assert.throws(() => v.mutation({ ...p, VersionEsperada: '123' }, 'recibir', 3));
  assert.equal(v.mutation({ ...p, VersionEsperada: version.toLowerCase() }, 'recibir', '3').VersionEsperada, version);
});
test('BOD validacion: actor no aceptado, costo decimal string exacto y sin precios web', () => {
  const b = { ...proposal(), BodegaId: 2, ProveedorId: 7, DocumentoRespaldo: 'DOC', CostoUnitario: '12345678901234567.89', ActorUsuarioId: 999, PrecioUnitario: 1 };
  const d = v.mutation(b, 'compra'); assert.equal(d.CostoUnitario, b.CostoUnitario); assert(!Object.hasOwn(d, 'ActorUsuarioId')); assert(!Object.hasOwn(d, 'PrecioUnitario'));
  assert.equal(v.money('100.5'), '100.50'); assert.equal(v.money(''), null); assert.equal(v.money('0'), '0.00');
  for (const x of [1, '1e4', '-1', '1.234', '1,50', '100000000000000000.00', {}, []]) assert.throws(() => v.money(x));
});
test('BOD validacion: bodegas, baja logica, modalidades y parametros de credito', () => {
  const b = { OperacionId: randomUUID(), Nombre: 'Sucursal', Activo: '1', IsCentral: '0', Motivo: 'Alta' };
  assert.equal(v.mutation(b, 'bodega').Activo, true); assert.throws(() => v.mutation(b, 'bodega', 2));
  assert.equal(v.mutation({ ...b, VersionEsperada: version, Activo: '0' }, 'bodega', 2).Activo, false);
  const q = { OperacionId: randomUUID(), CotizacionId: 1, BodegaId: 2, Credito: '0' };
  assert.equal(v.mutation(q, 'cotizacion').PlazoDias, null);
  assert.throws(() => v.mutation({ ...q, PlazoDias: 30 }, 'cotizacion'));
  for (const change of [{ PlazoDias: 0, NumeroCuotas: 1 }, { PlazoDias: 30, NumeroCuotas: 121 }, { PlazoDias: 3651, NumeroCuotas: 1 }]) assert.throws(() => v.mutation({ ...q, Credito: true, ...change }, 'cotizacion'));
  assert.equal(v.mutation({ ...q, Credito: true, PlazoDias: 30, NumeroCuotas: 2 }, 'cotizacion').NumeroCuotas, 2);
});
test('BOD filtros: paginacion limitada, UTC Guatemala, hasta exclusivo y parametros repetidos', () => {
  const f = v.filters({ pagina: '2', BodegaId: '3', desde: '2026-10-01', hasta: '2026-10-02' });
  assert.equal(f.Desde.toISOString(), '2026-10-01T06:00:00.000Z'); assert.equal(f.Hasta.toISOString(), '2026-10-03T06:00:00.000Z');
  for (const q of [{ pagina: 0 }, { pagina: 100002 }, { BodegaId: ['1', '2'] }, { desde: '2026-02-30' }, { desde: '2026-11-02', hasta: '2026-11-01' }]) assert.throws(() => v.filters(q));
});
async function fixture(t, allowed = permissions, options = {}) {
  const calls = [];
  const row = { TransferenciaId: 3, ProductoId: 1, Codigo: 'SKU-1', Descripcion: '<script>bad()</script>', OrigenId: 1, DestinoId: 2, Origen: 'Central', Destino: 'Z1', Cantidad: 5, Estado: 'PREPARADA', Motivo: 'Documento', ActorUsuarioId: 42, FechaHora: new Date('2026-10-28T18:00:00Z'), Version: version };
  const service = {
    authorize: async (...args) => { calls.push(['authorize', ...args]); },
    list: async (actor, section, f, id) => {
      calls.push(['list', actor, section, f, id]);
      return { rows: section === 'bodegas' ? [{ BodegaId: 1, Nombre: '<img src=x onerror=bad()>', Activo: true, IsCentral: true, Stock: '100', Version: version }] : section === 'inventario' ? [{ ...row, Stock: 100, StockLocal: '95', Transito: '5', Diferencia: '0' }] : [row], next: true, evidence: section === 'inventario' ? [{ StockGlobal: '100', StockLocal: '95', Transito: '5', Descuadres: '0' }] : [] };
    },
    mutate: async (actor, action, data) => { calls.push(['mutate', actor, action, data]); return { TransferenciaId: 3, OperacionId: data.OperacionId, Estado: 'PREPARADA' }; },
    operation: async (...args) => { calls.push(['operation', ...args]); return { FechaHora: new Date(), Respuesta: '{"Nombre":"<script>bad()</script>"}' }; },
  };
  const app = createApp({ secret: 'multibodega-http-mock-secret-at-least-32', production: false, multibodegaService: service, authService: { login: async () => ({ codigo: 0, usuario: { usuarioId: 42, nombreUsuario: 'Mod5', permisos: allowed, debeCambiarPassword: options.changePassword || false } }) } });
  const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = 'http://127.0.0.1:' + server.address().port;
  const login = await fetch(base + '/login', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: 'NombreUsuario=Mod5&Password=fixture', redirect: 'manual' });
  const cookie = login.headers.get('set-cookie').split(';')[0];
  const request = (url, opts = {}) => fetch(base + url, { redirect: 'manual', ...opts, headers: { Cookie: cookie, ...opts.headers } });
  const post = (url, data, csrf = '') => request(url, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf }, body: JSON.stringify(data) });
  const token = async () => (await (await request('/multibodega')).text()).match(/name="csrf-token" content="([a-f0-9]{64})"/)[1];
  return { service, row, calls, request, post, token, base };
}
test('BOD HTTP: autenticacion, cambio obligatorio y RBAC sin consultas de negocio', async t => {
  const f = await fixture(t, []);
  assert.equal((await fetch(f.base + '/multibodega', { redirect: 'manual' })).status, 302);
  assert.equal((await f.request('/multibodega')).status, 403); assert.equal(f.calls.length, 0);
  const g = await fixture(t, permissions, { changePassword: true }); const r = await g.request('/multibodega'); assert.equal(r.status, 302); assert.equal(r.headers.get('location'), '/cambiar-password');
});
test('BOD HTTP: todas las vistas, navegacion real, escape EJS y ningun cambio por GET', async t => {
  const f = await fixture(t);
  for (const url of ['/multibodega', '/multibodega?seccion=bodegas', '/multibodega?seccion=transferencias', '/multibodega?seccion=kardex', '/multibodega?seccion=integraciones', '/multibodega/transferencias/3', '/multibodega/operaciones/' + randomUUID()]) {
    const r = await f.request(url); assert.equal(r.status, 200, url); const html = await r.text();
    assert.doesNotMatch(html, /<script>bad\(\)<\/script>|<img src=x/); assert.match(html, /multibodega/);
  }
  assert(!f.calls.some(c => c[0] === 'mutate'));
  const modules = await (await f.request('/modulos')).text(); assert.match(modules, /href="\/multibodega"/);
  for (const asset of ['/css/multibodega.css', '/js/multibodega.js', '/vendor/bootstrap/css/bootstrap.min.css']) assert.equal((await f.request(asset)).status, 200, asset);
});
test('BOD HTTP: CSRF independiente y todos los permisos de escritura', async t => {
  const f = await fixture(t, ['BODEGAS_CONSULTAR']), csrf = await f.token();
  for (const url of ['/multibodega/bodegas', '/multibodega/bodegas/1', '/multibodega/transferencias', '/multibodega/transferencias/3/despachar', '/multibodega/transferencias/3/recibir', '/multibodega/compras', '/multibodega/cotizaciones/convertir']) assert.equal((await f.post(url, proposal(), csrf)).status, 403, url);
  const g = await fixture(t); await g.token();
  for (const token of ['', 'bad', 'a'.repeat(64), 'a'.repeat(65)]) assert.equal((await g.post('/multibodega/transferencias', proposal(), token)).status, 403);
  assert(!g.calls.some(c => c[0] === 'mutate'));
});
test('BOD HTTP: autorizacion vigente SQL bloquea sesiones con permisos revocados', async t => {
  const f = await fixture(t), csrf = await f.token();
  f.service.authorize = async () => { throw Object.assign(new Error('SQL INTERNAL'), { number: 54101 }); };
  const r = await f.post('/multibodega/transferencias', proposal(), csrf); assert.equal(r.status, 403); assert.doesNotMatch(await r.text(), /INTERNAL/); assert(!f.calls.some(c => c[0] === 'mutate'));
});
test('BOD HTTP: preparar conserva UUID/carga y toma actor solamente de sesion', async t => {
  const f = await fixture(t), csrf = await f.token(), body = { ...proposal(), ActorUsuarioId: 999, UsuarioId: 999, PrecioUnitario: 1 };
  for (let i = 0; i < 2; i++) assert.equal((await f.post('/multibodega/transferencias', body, csrf)).status, 200);
  const mutations = f.calls.filter(c => c[0] === 'mutate'); assert.equal(mutations.length, 2); assert.equal(mutations[0][1], 42); assert.equal(mutations[0][3].OperacionId, body.OperacionId); assert.deepEqual(mutations[0][3], mutations[1][3]); assert.equal(mutations[0][3].ActorUsuarioId, undefined);
  for (const change of [{ Cantidad: 0 }, { Cantidad: 1.5 }, { OrigenId: 2 }, { OperacionId: 'bad' }]) assert.equal((await f.post('/multibodega/transferencias', { ...body, ...change }, csrf)).status, 400);
});
test('BOD HTTP: fases exigen version y UUID, accion no proviene del navegador', async t => {
  const f = await fixture(t), csrf = await f.token(), b = { OperacionId: randomUUID(), VersionEsperada: version, Motivo: 'Despacho', Accion: 'SQL', ActorUsuarioId: 2 };
  for (const phase of ['despachar', 'recibir']) {
    assert.equal((await f.post('/multibodega/transferencias/3/' + phase, { ...b, VersionEsperada: '' }, csrf)).status, 400);
    assert.equal((await f.post('/multibodega/transferencias/3/' + phase, b, csrf)).status, 200);
    const call = f.calls.filter(c => c[0] === 'mutate').at(-1); assert.equal(call[3].TransferenciaId, 3); assert.equal(call[3].Accion, phase.toUpperCase());
  }
  assert.equal((await f.request('/multibodega/transferencias/3/despachar')).status, 404);
});
test('BOD HTTP: compras y cotizaciones usan wrappers propios y cadenas monetarias', async t => {
  const f = await fixture(t), csrf = await f.token();
  const b = { ...proposal(), BodegaId: 2, ProveedorId: 1, CostoUnitario: '900719925474099.51', DocumentoRespaldo: 'COMPRA-1' };
  assert.equal((await f.post('/multibodega/compras', b, csrf)).status, 200); assert.equal(f.calls.filter(c => c[0] === 'mutate').at(-1)[3].CostoUnitario, b.CostoUnitario);
  const q = { OperacionId: randomUUID(), CotizacionId: 1, BodegaId: 2, Credito: true, PlazoDias: 30, NumeroCuotas: 2, PrecioUnitario: 1 };
  assert.equal((await f.post('/multibodega/cotizaciones/convertir', q, csrf)).status, 200); assert.equal(f.calls.filter(c => c[0] === 'mutate').at(-1)[3].PrecioUnitario, undefined);
});
test('BOD HTTP: CRUD de bodega conserva version, nombre escapado y baja logica', async t => {
  const f = await fixture(t), csrf = await f.token(), b = { OperacionId: randomUUID(), Nombre: '<script>bad()</script>', Activo: true, IsCentral: false, Motivo: 'Alta' };
  assert.equal((await f.post('/multibodega/bodegas', b, csrf)).status, 200);
  assert.equal((await f.post('/multibodega/bodegas/1', b, csrf)).status, 400);
  assert.equal((await f.post('/multibodega/bodegas/1', { ...b, VersionEsperada: version, Activo: false }, csrf)).status, 200);
  assert.equal(f.calls.filter(c => c[0] === 'mutate').at(-1)[3].Activo, false);
});
test('BOD HTTP: evidencia por fase imprimible, auditor no recibe formularios', async t => {
  const f = await fixture(t, ['BODEGAS_CONSULTAR']);
  for (const Estado of ['PREPARADA', 'DESPACHADA', 'RECIBIDA']) {
    f.row.Estado = Estado; const html = await (await f.request('/multibodega/transferencias/3')).text();
    assert.match(html, /data-bod-print/); assert.match(html, new RegExp(Estado)); assert.doesNotMatch(html, /data-bod-flow=/);
  }
  const g = await fixture(t); g.row.Estado = 'DESPACHADA'; assert.match(await (await g.request('/multibodega/transferencias/3')).text(), /\/recibir/);
});
test('BOD HTTP: errores SQL no filtran internos, resultado incierto y consulta 404 honesta', async t => {
  const f = await fixture(t), csrf = await f.token();
  for (const [number, status] of [[58002, 400], [58003, 409], [58004, 404], [58005, 409], [58008, 400], [54101, 403], [58007, 503], [12345, 503]]) {
    f.service.mutate = async () => { throw Object.assign(new Error('SQL password INTERNAL'), { number }); };
    const r = await f.post('/multibodega/transferencias', proposal(), csrf); assert.equal(r.status, status); const data = await r.json(); assert.doesNotMatch(data.error, /password|INTERNAL/); assert.equal(data.incierto, status === 503);
  }
  f.service.operation = async () => null; const r = await f.request('/multibodega/operaciones/' + randomUUID()); assert.equal(r.status, 404); assert.match(await r.text(), /puede seguir en curso/);
});
test('BOD HTTP: filtros no validos se rechazan antes de consultas y paginacion se conserva', async t => {
  const f = await fixture(t);
  for (const query of ['pagina=0', 'seccion=sql', 'BodegaId=1&BodegaId=2', 'hasta=2026-02-30', 'ProductoId=1.2']) assert.equal((await f.request('/multibodega?' + query)).status, 400);
  assert.equal((await f.request('/multibodega?seccion=inventario&pagina=2&BodegaId=2')).status, 200); const c = f.calls.filter(c => c[0] === 'list').at(-1); assert.equal(c[3].pagina, 2); assert.equal(c[3].BodegaId, 2);
});
test('BOD servicio: RPC tipado, binario de version, decimal string y ultimo recibo', async () => {
  const calls = [], requests = []; let result;
  const s = createMultibodegaService(async () => ({ request() { const params = []; requests.push(params); return { input(...args) { params.push(args); return this; }, async execute(name) { calls.push(name); return { recordsets: result || [[]] }; } }; } }));
  await s.authorize(42, 'BODEGAS_CONSULTAR'); assert.equal(calls[0], 'dbo.P3_BOD_Autorizar');
  const op = randomUUID(); result = [[{ FacturaId: 1 }], [{ Respuesta: JSON.stringify({ OperacionId: op, Estado: 'DESPACHADA' }) }]];
  const d = v.mutation({ OperacionId: op, VersionEsperada: version, Motivo: 'Salida' }, 'despachar', 3);
  assert.equal((await s.mutate(42, 'despachar', d)).Estado, 'DESPACHADA');
  const params = requests.at(-1); assert.equal(params[0][0], 'ActorUsuarioId'); assert.equal(params[0][1], sql.Int); assert.equal(params[0][2], 42); assert.deepEqual(params.find(p => p[0] === 'VersionEsperada')[2], Buffer.from(version, 'hex'));
  const compra = v.mutation({ ...proposal(), OperacionId: op, BodegaId: 2, ProveedorId: 1, DocumentoRespaldo: 'DOC', CostoUnitario: '900719925474099.51' }, 'compra');
  await s.mutate(42, 'compra', compra); const cost = requests.at(-1).find(p => p[0] === 'CostoUnitario'); assert.equal(cost[2], compra.CostoUnitario); assert.equal(cost[1].type, sql.VarChar);
  result = [[{ Respuesta: '{}' }]]; await assert.rejects(() => s.mutate(42, 'despachar', d));
  await assert.rejects(() => s.mutate(42, 'SQL', d)); await assert.rejects(() => s.mutate(42, 'compra', { SQL: 'DROP' }));
});
test('BOD servicio: consultas y desplazamiento tipados, parametros no interpolados', async () => {
  const params = [], calls = []; const s = createMultibodegaService(async () => ({ request: () => ({ input(...p) { params.push(p); return this; }, async execute(n) { calls.push(n); return { recordsets: [Array.from({ length: 21 }, (_, i) => ({ ProductoId: i + 1 })), []] }; } }) }));
  const data = await s.list(42, 'inventario', { pagina: 2, ProductoId: 1, BodegaId: 2 }); assert.equal(data.rows.length, 20); assert.equal(data.next, true); assert.equal(params.find(p => p[0] === 'Desplazamiento')[2], 20); assert.equal(calls[0], 'dbo.P3_BOD_Consultar');
  await s.operation(42, randomUUID()); assert.equal(calls[1], 'dbo.P3_BOD_ConsultarOperacion');
});
test('BOD SQL estatico: rango propio, guards exactos, transaccion externa y sin reemplazos compartidos', () => {
  const dir = path.join(__dirname, '../database'); const names = readdirSync(dir).filter(n => /^8\d_P3_BOD_.*\.sql$/.test(n)); assert.equal(names.length, 11);
  for (const name of names) {
    const source = readFileSync(path.join(dir, name), 'utf8').replace(/\r\n/g,'\n'); assert.match(source, /DB_NAME\(\) COLLATE Latin1_General_100_BIN2\s*<>\s*(?:dbo\.P3_INT_Destino\(\)|N?'SecureFinanceERP_Lab_Dylan')/); assert.match(source, /@@TRANCOUNT=0/); assert.match(source, /XACT_STATE\(\)<>1/);
    assert.match(source, /DATALENGTH\(DB_NAME\(\)\)/);
    for (const declaration of source.matchAll(/CREATE(?: OR ALTER)? (?:PROCEDURE|TABLE|TRIGGER|VIEW) dbo\.(\w+)/g)) assert(declaration[1].startsWith('P3_BOD_') || declaration[1] === 'sp_TransferirStockBodegas');
    assert.doesNotMatch(source, /CREATE OR ALTER PROCEDURE dbo\.(?:sp_RegistrarMovimientoKardex|sp_ERP_ProcesarVenta|sp_ProcesarVentaTransaccional|sp_ConvertirCotizacionAFactura)\b/i);
    assert.doesNotMatch(source, /UPDATE\s+dbo\.ConfiguracionInventario|TRUSTSERVERCERTIFICATE/i);
    const productWrites = [...source.matchAll(/UPDATE\s+dbo\.Producto\s+SET\s+([^;]+);/gi)];
    if (name === '85_P3_BOD_Integraciones.sql') {
      assert.equal(productWrites.length, 1);
      assert.equal(productWrites[0][1].split(/\s+WHERE\s+/i)[0], 'PrecioCosto=@CostoPromedio');
    } else assert.equal(productWrites.length, 0, name);
  }
  const mirror = readFileSync(path.join(dir, '84_P3_BOD_EspejoKardex.sql'), 'utf8'); assert.match(mirror, /AFTER INSERT/); assert.match(mirror, /ORDER BY ProductoId,KardexId/); assert.match(mirror, /APERTURA/); assert.match(mirror, /TipoMovimiento NOT IN/);
  const phases = readFileSync(path.join(dir, '82_P3_BOD_Transferencias.sql'), 'utf8'); assert(phases.indexOf('dbo.Producto WITH(UPDLOCK,HOLDLOCK)', phases.indexOf('CREATE OR ALTER PROCEDURE dbo.P3_BOD_Avanzar')) < phases.indexOf('dbo.P3_BOD_Transferencia WITH(UPDLOCK,HOLDLOCK)'));
  const installer = readFileSync(path.join(dir, 'tests/P3_BOD_InstallLab.sql'), 'utf8'); assert.match(installer, /:ON ERROR EXIT/); assert.equal((installer.match(/BEGIN TRANSACTION;/g) || []).length, 1); assert.equal((installer.match(/^:r 8\d_P3_BOD_/gm) || []).length, 11);
});

function sqlProcedure(file, name) {
  const source = readFileSync(path.join(__dirname, '../database', file), 'utf8').replace(/\r\n/g,'\n');
  const definitions = [...source.matchAll(/EXEC\(N'((?:''|[^'])*)'\);/g)].map(m => m[1].replace(/''/g, "'"));
  const body = definitions.find(d => d.startsWith('CREATE OR ALTER PROCEDURE dbo.' + name + '\n'));
  assert(body, name + ' debe existir como procedimiento real');
  return body.replace(/--[^\n]*/g, '');
}
test('BOD contrato SQL: helper acordado con Creditos, firma exacta, RBAC y sin recordsets/prelocks', () => {
  const body = sqlProcedure('81_P3_BOD_Contratos.sql', 'P3_BOD_ValidarBodegaVenta');
  assert.match(body, /^CREATE OR ALTER PROCEDURE dbo\.P3_BOD_ValidarBodegaVenta\s+@ActorUsuarioId INT,@BodegaId INT\s+AS/);
  assert.match(body, /EXEC dbo\.P3_BOD_Autorizar @ActorUsuarioId,N'BODEGAS_CONSULTAR'/);
  assert.match(body, /@BodegaId IS NULL OR @BodegaId<=0/); assert.match(body, /WHERE BodegaId=@BodegaId AND Activo=1/);
  assert.doesNotMatch(body, /^\s*SELECT\b|\b(?:INSERT|UPDATE|DELETE|UPDLOCK|HOLDLOCK)\b|dbo\.Producto|dbo\.P3_BOD_Stock/gim);
  const permissionsSql = readFileSync(path.join(__dirname, '../database/87_P3_BOD_Permisos.sql'), 'utf8');
  assert.doesNotMatch(permissionsSql, /GRANT EXECUTE ON (?:OBJECT::)?dbo\.P3_BOD_ValidarBodegaVenta/i);
  assert.match(permissionsSql, /DENY EXECUTE ON dbo\.P3_BOD_ValidarBodegaVenta TO securefinance_app/);
});
test('BOD contrato SQL: conversion delega orden quote/credito/producto y no consulta stock antes del replay', () => {
  const body = sqlProcedure('85_P3_BOD_Integraciones.sql', 'P3_BOD_ConvertirCotizacion');
  assert.doesNotMatch(body, /dbo\.Producto\b|dbo\.P3_BOD_Stock\b|dbo\.P3_COT_Detalle\b|P3_BOD_BloquearUbicaciones|UPDLOCK|HOLDLOCK/);
  const replay = body.indexOf('EXEC dbo.P3_BOD_Reintento'), first = body.indexOf('IF @Respuesta IS NULL'), validate = body.indexOf('EXEC dbo.P3_BOD_ValidarBodegaVenta');
  assert(replay < first && first < validate);
  assert(validate < body.indexOf('EXEC dbo.P3_CRE_ConvertirCotizacionCredito'));
  assert(validate < body.indexOf('EXEC dbo.sp_ConvertirCotizacionAFactura'));
  assert.match(body, /EXEC dbo\.P3_CRE_ConvertirCotizacionCredito @ActorUsuarioId=@ActorUsuarioId,@CotizacionId=@CotizacionId,@OperacionId=@OperacionId,@PlazoDias=@PlazoDias,@NumeroCuotas=@NumeroCuotas,@BodegaId=@BodegaId/);
});
test('BOD contrato SQL: ponderado bajo lock, una recepcion original y solo UPDATE PrecioCosto fuera de replay', () => {
  const body = sqlProcedure('85_P3_BOD_Integraciones.sql', 'P3_BOD_RegistrarCompra');
  const first = body.indexOf('IF @Respuesta IS NULL'), lock = body.indexOf('SELECT @StockAnterior=Stock,@CostoAnterior=PrecioCosto FROM dbo.Producto WITH(UPDLOCK,HOLDLOCK)'), delegate = body.indexOf('EXEC dbo.sp_RegistrarRecepcionCompra'), update = body.indexOf('UPDATE dbo.Producto SET PrecioCosto=@CostoPromedio'), book = body.indexOf('INSERT dbo.P3_BOD_Operacion');
  assert(first < lock && lock < delegate && delegate < update && update < book);
  assert.equal((body.match(/EXEC dbo\.sp_RegistrarRecepcionCompra\b/g) || []).length, 1);
  const newEntry = body.indexOf('IF NOT EXISTS(SELECT 1 FROM dbo.Producto WHERE ProductoId=@ProductoId AND Stock=@StockNuevo)');
  assert(delegate < newEntry && newEntry < update, 'no valorar un replay nativo concurrente como si fuera otro ingreso');
  assert.match(body, /@CostoUnitario=@CostoUnitario;/); assert.doesNotMatch(body, /EXEC dbo\.sp_RegistrarMovimientoKardex|\bFLOAT\b|\bREAL\b|SET Stock\s*=/i);
  assert.match(body, /IF @CostoUnitario IS NOT NULL/); assert.match(body, /IF @StockAnterior=0/);
  assert.match(body, /@CostoAnterior IS NULL OR @CostoAnterior<0 THROW 58008/);
  assert.match(body, /@StockNuevo>2147483647/); assert.match(body, /@CentavosRedondeados>999999999999/);
  assert.match(body, /@Centavos%CONVERT\(DECIMAL\(10,0\),@StockNuevo\)/); assert.match(body, /@Residuo\*2>=@StockNuevo/);
  for (const key of ['CostoUnitario', 'CostoPromedio', 'PrecioCostoResultante']) assert.match(body, new RegExp('CONVERT\\(VARCHAR\\(21\\),[^)]+\\) ' + key));
  for (const key of ['@ActorPrevio', '@OperacionPrevia', '@MotivoPrevio']) assert.equal((body.match(new RegExp('@value=' + key + ';', 'g')) || []).length, 2);
  assert.match(body, /@CostoPromedio DECIMAL\(12,2\)=NULL,@PoliticaCosto VARCHAR\(25\)='SIN_COSTO_RECEPCION'/);
});
test('BOD oraculo matematico exacto de centavos para fixtures ponderados (no ejecuta SQL)', () => {
  const average = (stock, oldCents, quantity, unitCents) => {
    const total = stock + quantity, value = stock * oldCents + quantity * unitCents;
    return value / total + (2n * (value % total) >= total ? 1n : 0n);
  };
  assert.equal(average(100n, 2000n, 25n, 3000n), 2200n);
  assert.equal(average(0n, 0n, 25n, 3000n), 3000n);
  assert.equal(average(100n, 2000n, 1n, 2050n), 2000n);
  assert.equal(average(100n, 2000n, 1n, 2051n), 2001n);
  assert.equal(average(100n, 2000n, 100n, 2001n), 2001n);
  assert.equal(average(2147483646n, 2000n, 1n, 1073743823n), 2000n);
  assert.equal(average(2147483646n, 2000n, 1n, 1073743824n), 2001n);
  assert(average(100n, 2000n, 1n, 9999999999999999999n) > 999999999999n);
});
test('BOD servicio: recibo ponderado o sin costo conserva cadenas/null del SQL, sin recalcular en JS', async () => {
  const op = randomUUID(); let result = { OperacionId: op, RecepcionId: '7', CostoUnitario: '30.00', CostoPromedio: '22.00', PrecioCostoResultante: '22.00', CostoPromedioAplicado: true, PoliticaCosto: 'PONDERADO' };
  const s = createMultibodegaService(async () => ({ request: () => ({ input() { return this; }, execute: async () => ({ recordsets: [[{ Respuesta: JSON.stringify(result) }]] }) }) }));
  const data = v.mutation({ ...proposal(), OperacionId: op, BodegaId: 2, ProveedorId: 1, DocumentoRespaldo: 'DOC', CostoUnitario: '30.00' }, 'compra');
  assert.deepEqual(await s.mutate(42, 'compra', data), result);
  result = { ...result, CostoUnitario: null, CostoPromedio: null, PrecioCostoResultante: '20.00', CostoPromedioAplicado: false, PoliticaCosto: 'SIN_COSTO_RECEPCION' };
  assert.deepEqual(await s.mutate(42, 'compra', { ...data, CostoUnitario: null }), result);
});
test('BOD HTTP/EJS: muestra costo documental y promedio separados; desconocido no se presenta como cero', async t => {
  const f = await fixture(t), op = randomUUID(), csrf = await f.token();
  let receipt = { OperacionId: op, RecepcionId: '7', CostoUnitario: '30.00', CostoPromedio: '22.00', PrecioCostoResultante: '22.00', CostoPromedioAplicado: true, PoliticaCosto: 'PONDERADO' };
  f.service.mutate = async (actor, action, data) => { assert.equal(actor, 42); assert.equal(action, 'compra'); assert.equal(data.CostoPromedio, undefined); return receipt; };
  const r = await f.post('/multibodega/compras', { ...proposal(), OperacionId: op, BodegaId: 2, ProveedorId: 1, DocumentoRespaldo: 'DOC', CostoUnitario: '30.00', CostoPromedio: '0.01' }, csrf);
  assert.equal(r.status, 200); assert.deepEqual((await r.json()).documento, receipt);
  f.service.operation = async () => ({ FechaHora: new Date(), Respuesta: JSON.stringify(receipt) });
  let html = await (await f.request('/multibodega/operaciones/' + op)).text();
  assert.match(html, /Costo unitario del documento/); assert.match(html, /Costo promedio aplicado/); assert.match(html, />30\.00</); assert.match(html, />22\.00</);
  receipt = { ...receipt, CostoUnitario: null, CostoPromedio: null, PrecioCostoResultante: null, CostoPromedioAplicado: false, PoliticaCosto: 'SIN_COSTO_RECEPCION' };
  html = await (await f.request('/multibodega/operaciones/' + op)).text(); assert.match(html, /No calculado/); assert.match(html, /sin valorar las unidades nuevas/);
  receipt = { ...receipt, PoliticaCosto: '<script>bad()</script>' };
  html = await (await f.request('/multibodega/operaciones/' + op)).text(); assert.doesNotMatch(html, /<script>bad\(\)<\/script>/);
});

function browser(fetchImpl, storage = new Map(), unavailable = false) {
  class Element {
    constructor(value = '') { this.value = value; this.listeners = {}; this.children = []; this.dataset = {}; this.hidden = false; this.disabled = false; }
    addEventListener(event, fn) { this.listeners[event] = fn; }
    trigger(event) { return this.listeners[event]?.({ preventDefault() {} }); }
    replaceChildren(...children) { this.children = children; }
    append(child) { this.children.push(child); }
    focus() {}
  }
  const fields = Object.fromEntries(Object.entries({ OperacionId: randomUUID(), ProductoId: '1', OrigenId: '1', DestinoId: '2', Cantidad: '5', Motivo: 'Envio', VersionEsperada: version }).map(([k, x]) => [k, new Element(x)]));
  const controls = Object.fromEntries(['[type=submit]', '[data-bod-retry]', '[data-bod-new]', '[data-bod-reference]', '[data-bod-status]'].map(k => [k, new Element()]));
  const message = new Element(), print = new Element(), form = new Element();
  form.dataset.bodFlow = 'preparar'; form.getAttribute = () => '/multibodega/transferencias'; form.querySelector = k => controls[k]; form.querySelectorAll = () => Object.values(fields); form.reportValidity = () => true; form.elements = { namedItem: k => fields[k] };
  const calls = []; let reloads = 0, prints = 0;
  const sessionStorage = { getItem: k => { if (unavailable) throw new Error('disabled'); return storage.get(k) || null; }, setItem: (k, val) => { if (unavailable) throw new Error('disabled'); storage.set(k, val); }, removeItem: k => storage.delete(k) };
  const document = { body: { dataset: { bodActor: '42' } }, querySelector: k => k === '#bod-message' ? message : k === '[data-bod-print]' ? print : { content: 'csrf' }, querySelectorAll: () => [form], createElement: () => new Element(), createTextNode: text => ({ textContent: text }) };
  runInNewContext(readFileSync(require.resolve('../src/public/js/multibodega.js'), 'utf8'), { document, sessionStorage, location: { pathname: '/multibodega', reload: () => { reloads++; } }, window: { confirm: () => true, print: () => { prints++; } }, fetch: async (...args) => { calls.push(args); return fetchImpl(...args); }, FormData: class { *[Symbol.iterator]() { for (const [k, e] of Object.entries(fields)) if (!e.disabled) yield [k, e.value]; } } });
  return { form, fields, controls, calls, storage, message, print, reloads: () => reloads, prints: () => prints };
}
const settle = () => new Promise(resolve => setImmediate(resolve));
test('BOD JS real en DOM simulado: doble clic, persistencia previa y resultado incierto sin reenvio', async () => {
  let reject;
  const b = browser(() => new Promise((resolve, no) => { reject = no; }));
  b.form.trigger('submit'); b.form.trigger('submit');
  assert.equal(b.calls.length, 1); assert.equal(b.fields.Cantidad.disabled, true); assert.equal(b.controls['[type=submit]'].disabled, true);
  const sent = JSON.parse(b.calls[0][1].body); assert.equal(sent.Cantidad, '5');
  assert.equal(b.calls[0][1].headers['X-CSRF-Token'], 'csrf'); assert(b.storage.size > 0);
  reject(new Error('network')); await settle(); assert.equal(b.calls.length, 1); assert.equal(b.controls['[data-bod-new]'].hidden, true);
  const restored = browser(async () => ({ ok: true, json: async () => ({ url: '/multibodega/operaciones/' + sent.OperacionId }) }), b.storage);
  assert.equal(restored.fields.OperacionId.value, sent.OperacionId); assert.equal(restored.fields.VersionEsperada.value, sent.VersionEsperada); assert.equal(restored.calls.length, 0);
  restored.fields.Cantidad.value = '99'; restored.controls['[data-bod-retry]'].trigger('click'); await settle();
  assert.deepEqual(JSON.parse(restored.calls[0][1].body), sent); assert.equal(restored.controls['[data-bod-retry]'].hidden, true);
  restored.controls['[data-bod-retry]'].trigger('click'); await settle(); assert.equal(restored.calls.length, 1);
  restored.controls['[data-bod-new]'].trigger('click'); assert.equal(restored.reloads(), 1);
});
test('BOD JS real en DOM simulado: almacenamiento fallido bloquea escritura e impresion no hace POST', async () => {
  const b = browser(async () => { throw new Error('No debe enviar'); }, new Map(), true);
  assert.equal(b.controls['[type=submit]'].disabled, true); b.form.trigger('submit'); await settle(); assert.equal(b.calls.length, 0);
  b.print.trigger('click'); assert.equal(b.prints(), 1); assert.equal(b.calls.length, 0);
});
