'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const express = require('express');
const { sql } = require('../src/config/database');
const { visibleAreas } = require('../src/config/moduleCatalog');
const { createAuditoriaDdlService } = require('../src/services/auditoriaDdlService');
const { filters, identifier, events } = require('../src/controllers/auditoriaDdlController');
const { createAuditoriaDdlRoutes } = require('../src/routes/auditoriaDdlRoutes');

const maxId = '9223372036854775807';
const row = Object.freeze({
  BitacoraDdlId: maxId,
  FechaHora: '2026-10-28T04:19:00.000Z',
  TipoEvento: 'ALTER_TABLE',
  NombreObjeto: 'Cuenta',
  TipoObjeto: 'TABLE',
  Esquema: 'dbo',
  UsuarioSQL: 'qa_ddl',
  LoginOriginal: 'qa_login',
  EquipoOrigen: 'qa_host',
  AplicacionOrigen: 'qa_app',
  BaseDatos: 'LaboratorioDDL',
  SesionId: 71,
  EstadoComando: 'PENDIENTE_RUBRICA',
});
const user = Object.freeze({
  usuarioId: 3, nombreUsuario: 'QA', permisos: ['AUDITORIA_DDL_CONSULTAR'],
  debeCambiarPassword: false,
});
const routes = ['/auditoria/ddl', '/auditoria/ddl/' + maxId];

function serviceFixture(result) {
  const calls = [];
  const provider = async () => ({
    request() {
      const params = [];
      return {
        input(...args) { params.push(args); return this; },
        async execute(proc) { calls.push({ proc, params }); return result; },
      };
    },
  });
  return { service: createAuditoriaDdlService(provider), calls };
}

async function fixture(t, usuario = user, event = row) {
  const calls = [];
  let error = null;
  const service = {
    async list(actor, f) {
      calls.push(['list', actor, f]);
      if (error) throw error;
      return { rows: event ? [event] : [], total: '41', corteId: maxId };
    },
    async detail(actor, id) {
      calls.push(['detail', actor, id]);
      if (error) throw error;
      return id === maxId ? event : null;
    },
  };
  const app = express();
  app.set('view engine', 'ejs');
  app.set('views', path.join(__dirname, '../src/views'));
  app.set('query parser', 'extended');
  app.locals.moduleAreas = visibleAreas;
  // Session injection exists only in this isolated test app, never in the real server.
  app.use((req, res, next) => { req.session = { usuario }; next(); });
  app.use(createAuditoriaDdlRoutes(service));
  const server = app.listen(0, '127.0.0.1');
  t.after(() => new Promise((resolve, reject) => {
    server.close(error => error ? reject(error) : resolve());
    server.closeAllConnections();
  }));
  await once(server, 'listening');
  const base = 'http://127.0.0.1:' + server.address().port;
  return {
    calls,
    setError(value) { error = value; },
    async request(route, options = {}) {
      const response = await fetch(base + route, { ...options, redirect: 'manual' });
      assert.equal(response.headers.get('cache-control'), 'no-store', route);
      return response;
    },
  };
}

test('DDL: filtros escalares, fechas reales, eventos y limites de pagina', () => {
  assert.deepEqual(filters({}), {
    desde: '', hasta: '', usuario: '', objeto: '', evento: '', pagina: 1, corteId: null,
  });
  assert.deepEqual(filters({
    desde: ' 2024-02-29 ', hasta: '2024-02-29', usuario: ' qa ', objeto: ' Cuenta ',
    evento: ' ALTER_TABLE ', pagina: '1000000', corte: maxId,
  }), {
    desde: '2024-02-29', hasta: '2024-02-29', usuario: 'qa', objeto: 'Cuenta',
    evento: 'ALTER_TABLE', pagina: 1000000, corteId: maxId,
  });
  assert.equal(filters({ desde: '0001-01-01', hasta: '9998-12-31' }).desde, '0001-01-01');
  assert.equal(filters({ usuario: 'u'.repeat(128), objeto: 'o'.repeat(128) }).objeto.length, 128);
  assert.deepEqual([...events].sort(), [
    'CREATE_TABLE', 'ALTER_TABLE', 'DROP_TABLE',
    'CREATE_PROCEDURE', 'ALTER_PROCEDURE', 'DROP_PROCEDURE',
  ].sort());
  for (const evento of events) assert.equal(filters({ evento }).evento, evento);
  for (const key of ['desde', 'hasta', 'usuario', 'objeto', 'evento', 'pagina', 'corte']) {
    for (const value of [[], ['a', 'b'], {}, { value: 'a' }, 1, true]) {
      assert.throws(() => filters({ [key]: value }), { status: 400 }, key);
    }
  }
  for (const query of [
    { desde: '2026-02-29' }, { hasta: '2026-02-30' }, { desde: '2026-13-01' },
    { desde: '2026-1-01' }, { desde: '2026-10-28T00:00:00Z' },
    { desde: '0000-01-01' }, { hasta: '9999-12-31' },
    { desde: '2026-10-29', hasta: '2026-10-28' },
    { usuario: 'x'.repeat(129) }, { objeto: 'x'.repeat(129) },
    { evento: 'x'.repeat(41) }, { evento: 'CREATE_LOGIN' }, { evento: 'alter_table' },
    ...['0', '-1', '01', '1.5', '1e2', ' 2', '1000001', ''].map(pagina => ({ pagina })),
  ]) assert.throws(() => filters(query), { status: 400 }, JSON.stringify(query));
});

test('DDL: IDs bigint exactos, overflow y cero solo como corte', () => {
  for (const id of ['1', '9007199254740993', maxId]) {
    assert.equal(identifier(id), id);
    assert.equal(filters({ corte: id }).corteId, id);
  }
  assert.equal(identifier('0', true), '0');
  assert.equal(filters({ corte: '0' }).corteId, '0');
  assert.throws(() => identifier('0'), { status: 400 });
  for (const id of [
    '9223372036854775808', '99999999999999999999', '-1', '+1', '01', '1.0', '1e3',
    ' 1', '1 ', '', '1 OR 1=1', 1, 0, 1n, null, undefined, [], {},
  ]) {
    assert.throws(() => identifier(id), { status: 400 });
    assert.throws(() => identifier(id, true), { status: 400 });
  }
});

test('DDL driver: codifica bigint exacto sin conexion a SQL Server', () => {
  const type = require('tedious').TYPES.BigInt;
  for (const id of ['0', '9007199254740993', maxId]) {
    const value = type.validate(id);
    assert.equal(value, BigInt(id));
    const bytes = Buffer.concat([...type.generateParameterData({ value })]);
    assert.equal(bytes.readBigInt64LE(), BigInt(id));
  }
});

test('DDL service: inputs SQL tipados, inyeccion ligada como valor y dias locales exclusivos', async () => {
  const f = filters({
    desde: '2026-10-27', hasta: '2026-10-28', pagina: '2', corte: maxId,
    usuario: "qa'; DROP TABLE dbo.Cuenta;--", objeto: "Cuenta%' OR 1=1;--", evento: 'ALTER_TABLE',
  });
  const { service, calls } = serviceFixture({
    recordsets: [[row], [{ TotalFilas: '41', CorteId: maxId }]], recordset: [row],
  });
  assert.deepEqual(await service.list(3, f), { rows: [row], total: '41', corteId: maxId });
  assert.equal(calls[0].proc, 'dbo.P3_DDL_ConsultarBitacora');
  assert.deepEqual(calls[0].params, [
    ['ActorUsuarioId', sql.Int, 3],
    ['Desde', sql.DateTime2(3), new Date('2026-10-27T06:00:00.000Z')],
    ['Hasta', sql.DateTime2(3), new Date('2026-10-29T06:00:00.000Z')],
    ['Usuario', sql.NVarChar(128), f.usuario], ['Objeto', sql.NVarChar(128), f.objeto],
    ['Evento', sql.NVarChar(40), 'ALTER_TABLE'], ['CorteId', sql.BigInt, maxId],
    ['Desplazamiento', sql.Int, 20], ['Limite', sql.Int, 20],
  ]);
  assert.deepEqual(await service.detail(3, maxId), row);
  assert.equal(calls[1].proc, 'dbo.P3_DDL_ConsultarDetalle');
  assert.deepEqual(calls[1].params, [
    ['ActorUsuarioId', sql.Int, 3], ['BitacoraDdlId', sql.BigInt, maxId],
  ]);
  await service.list(3, filters({ pagina: '1000000' }));
  const values = Object.fromEntries(calls[2].params.map(([name, type, value]) => [name, value]));
  for (const key of ['Desde', 'Hasta', 'Usuario', 'Objeto', 'Evento', 'CorteId']) assert.equal(values[key], null);
  assert.equal(values.Desplazamiento, 19999980);
});

test('DDL service: contrato listado estricto, faltantes no se convierten en vacio', async () => {
  const meta = { TotalFilas: '41', CorteId: maxId };
  for (const result of [
    {}, { recordset: [] }, { recordsets: null }, { recordsets: [] }, { recordsets: [[]] },
    { recordsets: [[], [meta], []] }, { recordsets: [null, [meta]] },
    { recordsets: [[], null] }, { recordsets: [[], []] }, { recordsets: [[], [meta, meta]] },
    { recordsets: [[], [{}]] }, { recordsets: [[], [{ TotalFilas: '0' }]] },
    { recordsets: [[], [{ CorteId: '0' }]] },
    { recordsets: [Array(21).fill(row), [meta]] },
  ]) await assert.rejects(serviceFixture(result).service.list(3, filters({})), /Contrato DDL/);
  const empty = serviceFixture({ recordsets: [[], [{ TotalFilas: '0', CorteId: '0' }]] });
  assert.deepEqual(await empty.service.list(3, filters({ corte: '0' })), { rows: [], total: '0', corteId: '0' });
  assert.equal(empty.calls[0].params.find(([name]) => name === 'CorteId')[2], '0');
  const bigTotal = serviceFixture({ recordsets: [[], [{ TotalFilas: maxId, CorteId: maxId }]] });
  assert.equal((await bigTotal.service.list(3, filters({}))).total, maxId);
});

test('DDL service: metadatos numericos son cadenas canonicas y corte no cambia ni permite filas superiores', async () => {
  for (const key of ['TotalFilas', 'CorteId']) {
    for (const value of [undefined, null, 0, 41, 1n, '', '-1', '01', '1.0', '1e2', '9223372036854775808']) {
      const meta = { TotalFilas: '41', CorteId: maxId, [key]: value };
      await assert.rejects(serviceFixture({ recordsets: [[], [meta]] }).service.list(3, filters({})), /Contrato DDL/);
    }
  }
  for (const [rows, total, corteId, requested] of [
    [[], '0', '2', '1'], [[row], '41', '9223372036854775806', null],
    [[row], '41', '0', '0'], [[row], '0', maxId, null], [[row, row], '41', maxId, null],
  ]) {
    const service = serviceFixture({ recordsets: [rows, [{ TotalFilas: total, CorteId: corteId }]] }).service;
    await assert.rejects(service.list(3, { ...filters({}), corteId: requested }), /Contrato DDL/);
  }
});

test('DDL service: solo metadata pendiente, SQL no NULL rechazado y columnas extra excluidas', async () => {
  const extended = { ...row, ComandoTSql: null, SecretoExtra: 'never-forward' };
  const { service } = serviceFixture({
    recordsets: [[extended], [{ TotalFilas: '1', CorteId: maxId }]], recordset: [extended],
  });
  assert.deepEqual((await service.list(3, filters({}))).rows, [row]);
  assert.deepEqual(await service.detail(3, maxId), row);
  for (const invalidRow of [
    null, {}, { ...row, EstadoComando: 'APROBADO' }, { ...row, EstadoComando: undefined },
    ...['', 'ALTER TABLE dbo.Cuenta ADD secreto int;', false, 0, {}].map(ComandoTSql => ({ ...row, ComandoTSql })),
    ...[0, 1, '0', '01', '9223372036854775808'].map(BitacoraDdlId => ({ ...row, BitacoraDdlId })),
  ]) {
    const invalid = serviceFixture({
      recordsets: [[invalidRow], [{ TotalFilas: '1', CorteId: maxId }]], recordset: [invalidRow],
    }).service;
    await assert.rejects(invalid.list(3, filters({})), /Contrato DDL/);
    await assert.rejects(invalid.detail(3, maxId), /Contrato DDL/);
  }
});

test('DDL service: detalle distingue ausente de contrato roto y rechaza identidad diferente', async () => {
  assert.equal(await serviceFixture({ recordset: [] }).service.detail(3, maxId), null);
  for (const result of [{}, { recordset: null }, { recordsets: [[]] }, { recordset: [row, row] },
    { recordset: [{ ...row, BitacoraDdlId: '9223372036854775806' }] },
    { recordset: [{ ...row, BitacoraDdlId: '9007199254740993' }] }]) {
    await assert.rejects(serviceFixture(result).service.detail(3, maxId), /Contrato DDL/);
  }
});

test('DDL HTTP: anonimo y cambio obligatorio redirigen; permiso DML no autoriza DDL', async t => {
  for (const [usuario, status, location] of [
    [null, 302, '/login'], [{ ...user, debeCambiarPassword: true }, 302, '/cambiar-password'],
    [{ ...user, permisos: ['AUDITORIA_CONSULTAR'] }, 403, null],
    [{ ...user, permisos: [] }, 403, null], [{ ...user, permisos: 'AUDITORIA_DDL_CONSULTAR' }, 403, null],
    ...[0, -1, '3', 2147483648].map(usuarioId => [{ ...user, usuarioId }, 403, null]),
  ]) {
    const f = await fixture(t, usuario);
    for (const route of routes) {
      const response = await f.request(route);
      assert.equal(response.status, status);
      assert.equal(response.headers.get('location'), location);
    }
    assert.equal(f.calls.length, 0);
  }
  const allowed = await fixture(t);
  for (const route of routes) assert.equal((await allowed.request(route)).status, 200);
  assert.deepEqual(allowed.calls.map(call => call[0]), ['list', 'detail']);
});

test('DDL HTTP: actor falso ignorado, IDs exactos, 404 y POST sin handler', async t => {
  const f = await fixture(t);
  const spoof = '?ActorUsuarioId=99&actor=99&usuarioId=99';
  for (const route of routes) assert.equal((await f.request(route + spoof)).status, 200);
  assert.equal(f.calls[0][1], 3);
  assert.equal(f.calls[1][1], 3);
  assert.equal(f.calls[1][2], maxId);
  assert.equal((await f.request('/auditoria/ddl/9007199254740993')).status, 404);
  assert.equal(f.calls[2][2], '9007199254740993');
  const before = f.calls.length;
  for (const route of routes) {
    assert.equal((await f.request(route, {
      method: 'POST', body: new URLSearchParams({ ActorUsuarioId: '99' }),
    })).status, 404);
  }
  assert.equal(f.calls.length, before);
});

test('DDL HTTP: filtros invalidos y IDs rechazados antes de llamar al servicio', async t => {
  const f = await fixture(t);
  for (const query of [
    'desde=2026-02-30', 'desde=0000-01-01', 'hasta=9999-12-31',
    'desde=2026-10-29&hasta=2026-10-28', 'evento=CREATE_LOGIN',
    'pagina=0', 'pagina=1000001', 'corte=9223372036854775808',
    ...['desde', 'hasta', 'usuario', 'objeto', 'evento', 'pagina', 'corte']
      .flatMap(key => [key + '=a&' + key + '=b', key + '[value]=x']),
  ]) assert.equal((await f.request('/auditoria/ddl?' + query)).status, 400, query);
  for (const id of ['0', '-1', '01', '9223372036854775808', '1%20OR%201=1']) {
    assert.equal((await f.request('/auditoria/ddl/' + id)).status, 400, id);
  }
  assert.equal(f.calls.length, 0);
});

test('DDL HTTP: revocacion SQL en ambas consultas, validacion 54990 y errores seguros 503', async t => {
  const f = await fixture(t);
  for (const [number, status] of [[54101, 403], [54990, 400], [2812, 503], [208, 503], [undefined, 503]]) {
    f.setError(Object.assign(new Error('DDL_SECRET_MARKER SQL Server internal failure'), {
      number, stack: 'DDL_STACK_MARKER', serverName: 'DDL_HOST_MARKER',
    }));
    for (const route of routes) {
      const response = await f.request(route);
      assert.equal(response.status, status, route + ': ' + number);
      const html = await response.text();
      assert.doesNotMatch(html, /DDL_SECRET_MARKER|DDL_STACK_MARKER|DDL_HOST_MARKER|SQL Server internal failure/);
      assert.doesNotMatch(html, /54101|54990|2812/);
    }
  }
  assert.equal(f.calls.length, 10);
});

test('DDL HTTP: metadata escapada y politica pendiente sin SQL crudo visible', async t => {
  const metadataFields = ['NombreObjeto', 'TipoObjeto', 'Esquema', 'UsuarioSQL',
    'LoginOriginal', 'EquipoOrigen', 'AplicacionOrigen', 'BaseDatos'];
  const unsafe = {
    ...row, ...Object.fromEntries(metadataFields.map(key => [key, '<script>ddl-' + key + '</script>'])),
    // Defense in depth: the UI must not display unexpected columns from a test double.
    ComandoTSql: 'ALTER TABLE dbo.DDL_RAW_MARKER ADD private int;', SecretoExtra: 'DDL_EXTRA_MARKER',
  };
  const f = await fixture(t, user, unsafe);
  for (const route of routes) {
    const response = await f.request(route);
    assert.equal(response.status, 200);
    const html = await response.text();
    assert.doesNotMatch(html, /<script>ddl-|DDL_RAW_MARKER|DDL_EXTRA_MARKER/);
    for (const key of route === routes[0] ? ['NombreObjeto', 'UsuarioSQL'] : metadataFields) {
      assert.ok(html.includes('&lt;script&gt;ddl-' + key + '&lt;/script&gt;'), key);
    }
    const prose = html.replace(/PENDIENTE_RUBRICA/g, '').replace(/<[^>]*>/g, ' ');
    assert.match(prose, /restringido/i, 'La UI debe advertir el acceso restringido al texto');
  }
});

test('DDL exacto: detalle conserva Unicode, espacios y mas de 4000 caracteres; listado excluye texto', async () => {
  const command = '  ALTER PROCEDURE dbo.P3_DDL_QA AS\r\n-- ' + '\u00f1'.repeat(6000) + '\r\nSELECT N\'<script>synthetic</script>\';  ';
  const exact = { ...row, EstadoComando: 'EXACTO_EVENTDATA', ComandoTSql: command };
  const detail = await serviceFixture({ recordset: [exact] }).service.detail(3, maxId);
  assert.equal(detail.ComandoTSql, command);
  const { ComandoTSql, ...summary } = exact;
  const listed = await serviceFixture({ recordsets: [[summary], [{ TotalFilas: '1', CorteId: maxId }]] }).service.list(3, filters({}));
  assert.deepEqual(listed.rows, [summary]);
  assert.ok(!Object.hasOwn(listed.rows[0], 'ComandoTSql'));
  await assert.rejects(serviceFixture({ recordsets: [[exact], [{ TotalFilas: '1', CorteId: maxId }]] }).service.list(3, filters({})), /Contrato DDL/);
  for (const value of [undefined, null, '', 42, {}]) {
    await assert.rejects(serviceFixture({ recordset: [{ ...exact, ComandoTSql: value }] }).service.detail(3, maxId), /Contrato DDL/);
  }
});

test('DDL exacto HTTP: comando solo en detalle autorizado, escapado sin truncado', async t => {
  const command = 'ALTER PROCEDURE dbo.P3_DDL_QA AS\nSELECT N\'<script>synthetic_only</script>\';\n-- ' + 'x'.repeat(6000);
  const exact = { ...row, EstadoComando: 'EXACTO_EVENTDATA', ComandoTSql: command };
  const allowed = await fixture(t, user, exact);
  const list = await (await allowed.request('/auditoria/ddl')).text();
  assert.doesNotMatch(list, /synthetic_only|ALTER PROCEDURE dbo.P3_DDL_QA/);
  const detail = await (await allowed.request(routes[1])).text();
  assert.ok(detail.includes('&lt;script&gt;synthetic_only&lt;/script&gt;'));
  assert.ok(detail.includes('x'.repeat(6000)));
  assert.doesNotMatch(detail, /<script>synthetic_only/);
  const denied = await fixture(t, { ...user, permisos: ['AUDITORIA_CONSULTAR'] }, exact);
  assert.equal((await denied.request(routes[1])).status, 403);
  assert.equal(denied.calls.length, 0);
});

test('DDL SQL93-94: SOLO texto, aceptacion de riesgo, captura unica y contexto limitado', () => {
  const read = name => readFileSync(path.join(__dirname, '../database', name), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/--[^\r\n]*/g, '');
  const policy = read('93_P3_DDL_TextoExacto.sql');
  const capture = read('94_P3_DDL_Captura.sql');
  for (const text of [policy, capture]) {
    assert.match(text, /SESSION_CONTEXT\(N'P3_DDL\.TextoExactoAutorizado'\)/);
    assert.match(text, /SESSION_CONTEXT\(N'P3_DDL\.LaboratorioConfirmado'\)/);
    assert.match(text, /DB_NAME\(\)\s+COLLATE\s+\w+\s*=\s*N'SecureFinanceERP'/);
    assert.match(text, /@@TRANCOUNT\s*=\s*0/);
    assert.doesNotMatch(text, /\bDROP\s+TABLE\b|\bDELETE\s+FROM\b|\bUPDATE\s+dbo\.Bitacora_DDL\b/i);
  }
  assert.match(policy, /WITH CHECK ADD CONSTRAINT P3_DDL_CK_ComandoEstado/);
  assert.match(policy, /ComandoTSql IS NOT NULL AND DATALENGTH\(ComandoTSql\) > 0/);
  assert.equal((capture.match(/EVENTDATA\(\)/g) || []).length, 1);
  assert.equal((capture.match(/INSERT dbo\.Bitacora_DDL/g) || []).length, 1);
  assert.match(capture, /CREATE OR ALTER TRIGGER P3_DDL_CapturarEstructura\s+ON DATABASE\s+WITH EXECUTE AS N'P3_DDL_Escritor'/);
  assert.match(capture, /CommandText\)\[1\]', 'nvarchar\(max\)'/);
  assert.match(capture, /CREATE USER P3_DDL_Escritor WITHOUT LOGIN/);
  assert.match(capture, /DENY IMPERSONATE ON USER::P3_DDL_Escritor TO securefinance_app/);
  assert.doesNotMatch(capture, /EXECUTE AS OWNER|TRUSTWORTHY|DISABLE TRIGGER|sp_executesql|LTRIM|RTRIM|LEFT\(@Command|SUBSTRING\(@Command/i);
  for (const event of events) assert.ok(capture.includes(event));
});

test('DDL HTTP: paginacion conserva corte bigint y todos los filtros, sin depender del texto UI', async t => {
  const f = await fixture(t);
  const query = { desde: '2026-10-27', hasta: '2026-10-28', usuario: 'qa & login',
    objeto: 'Cuenta + detalle', evento: 'ALTER_TABLE', pagina: '2' };
  // The first request has no corte: links must use the one returned by SQL.
  const response = await f.request('/auditoria/ddl?' + new URLSearchParams(query));
  assert.equal(response.status, 200);
  assert.deepEqual(f.calls[0], ['list', 3, { ...query, pagina: 2, corteId: null }]);
  const html = await response.text();
  const links = [...html.matchAll(/\bhref\s*=\s*["']([^"']+)["']/gi)]
    .map(match => new URL(match[1].replace(/&amp;|&#38;|&#x26;/gi, '&'), 'http://127.0.0.1'))
    .filter(url => url.pathname === '/auditoria/ddl' && url.searchParams.has('pagina'));
  assert.deepEqual(links.map(url => url.searchParams.get('pagina')).sort(), ['1', '3']);
  for (const link of links) {
    assert.equal(link.searchParams.get('corte'), maxId);
    for (const key of ['desde', 'hasta', 'usuario', 'objeto', 'evento']) {
      assert.equal(link.searchParams.get(key), query[key], key);
    }
    assert.equal((await f.request(link.pathname + link.search)).status, 200);
    assert.equal(f.calls.at(-1)[2].corteId, maxId);
  }
  const empty = await fixture(t, user, null);
  assert.equal((await empty.request('/auditoria/ddl')).status, 200);
  assert.equal((await empty.request(routes[1])).status, 404);
});

test('DDL SQL90-92: SOLO inspeccion textual, guardas de laboratorio y transaccion externa', () => {
  // Read SQL as text only. These tests must never connect to SQL Server or execute scripts.
  for (const filename of ['90_P3_DDL_Estructura.sql', '91_P3_DDL_Consultas.sql', '92_P3_DDL_Permisos.sql']) {
    const text = readFileSync(path.join(__dirname, '../database', filename), 'utf8');
    const code = text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/--[^\r\n]*/g, '');
    const guard = code.split(/^\s*GO\s*$/im)[0];
    assert.match(guard, /DB_ID\(\)\s+IS\s+NULL\s+OR\s+DB_ID\(\)\s*<=\s*4/i, filename);
    assert.match(guard, /DB_NAME\(\)\s+COLLATE\s+\w+\s*=\s*N'SecureFinanceERP'/i, filename);
    for (const name of ['master', 'tempdb', 'model', 'msdb', 'mssqlsystemresource']) {
      assert.ok(guard.includes("N'" + name + "'"), filename + ': ' + name);
    }
    assert.match(guard, /SESSION_CONTEXT\(N'P3_DDL\.LaboratorioConfirmado'\)[\s\S]*?<>\s*DB_NAME\(\)/i, filename);
    assert.match(guard, /IF\s+@@TRANCOUNT\s*=\s*0\s+OR\s+XACT_STATE\(\)\s*<>\s*1\s+THROW\s+54990/i, filename);
    assert.match(guard, /SET\s+XACT_ABORT\s+ON/i, filename);
    assert.doesNotMatch(code, /\b(?:CREATE|ALTER|ENABLE)\s+TRIGGER\b|\bsp_set_session_context\b/i, filename);
    assert.doesNotMatch(code, /\bBEGIN\s+TRAN(?:SACTION)?\b|\bCOMMIT\b/i, filename);
    assert.doesNotMatch(code, /\bsp_executesql\b|\bEXEC(?:UTE)?\s*\(|\bEXEC(?:UTE)?\s+@/i, filename);
  }
});

test('DDL SQL90-92: SOLO texto, comandos NULL, seis eventos, helper por consulta y grants minimos', () => {
  const read = name => readFileSync(path.join(__dirname, '../database', name), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/--[^\r\n]*/g, '');
  const structure = read('90_P3_DDL_Estructura.sql');
  const queries = read('91_P3_DDL_Consultas.sql');
  const permissions = read('92_P3_DDL_Permisos.sql');
  assert.match(structure, /CHECK\s*\(\s*ComandoTSql\s+IS\s+NULL\s*\)/i);
  assert.match(structure, /CHECK\s*\(\s*EstadoComando\s*=\s*'PENDIENTE_RUBRICA'\s*\)/i);
  const eventCheck = structure.match(/P3_DDL_CK_TipoEvento\s+CHECK\s*\(([^)]+)\)/i);
  assert.ok(eventCheck);
  assert.deepEqual([...eventCheck[1].matchAll(/N'([^']+)'/g)].map(match => match[1]).sort(), [...events].sort());
  const procedures = [...queries.matchAll(/CREATE\s+OR\s+ALTER\s+PROCEDURE\s+dbo\.(\w+)([\s\S]*?)(?=^\s*GO\s*$)/gim)];
  assert.deepEqual(procedures.map(match => match[1]), ['P3_DDL_ConsultarBitacora', 'P3_DDL_ConsultarDetalle']);
  for (const [, name, body] of procedures) {
    assert.match(body, /EXEC\s+dbo\.sp_ParteII_ValidarPermiso\s+@ActorUsuarioId,\s*N'AUDITORIA_DDL_CONSULTAR'/i, name);
    assert.ok(body.indexOf('sp_ParteII_ValidarPermiso') < body.search(/\bSELECT\b/i), name);
    assert.match(body, /CAST\(b\.BitacoraDdlId\s+AS\s+varchar\(20\)\)/i, name);
  }
  assert.match(queries, /CAST\(@TotalFilas\s+AS\s+varchar\(20\)\)\s+AS\s+TotalFilas/i);
  assert.match(queries, /CAST\(@CorteId\s+AS\s+varchar\(20\)\)\s+AS\s+CorteId/i);
  assert.match(queries, /@CorteId\s*>\s*0\s+AND\s+b\.BitacoraDdlId\s*<=\s*@CorteId/i);
  const grants = [...permissions.matchAll(/GRANT\s+EXECUTE\s+ON\s+OBJECT::dbo\.(\w+)\s+TO\s+(\w+)\s*;/gi)];
  assert.deepEqual(grants.map(match => [match[1], match[2]]), [
    ['P3_DDL_ConsultarBitacora', 'securefinance_app'], ['P3_DDL_ConsultarDetalle', 'securefinance_app'],
  ]);
  assert.equal((permissions.match(/\bGRANT\b/gi) || []).length, 2);
  assert.match(permissions, /DENY\s+SELECT,\s*INSERT,\s*UPDATE,\s*DELETE\s+ON\s+OBJECT::dbo\.Bitacora_DDL\s+TO\s+securefinance_app/i);
  for (const role of ['Administrador', 'Auditor']) {
    assert.match(permissions, new RegExp("WHERE Nombre = N'" + role + "' AND Activo = 1", 'i'));
  }
  assert.match(permissions, /FROM\s*\(VALUES\s*\(@AdministradorId\),\s*\(@AuditorId\)\)\s*r\(RolId\)/i);
  assert.match(permissions, /PermisoId\s*=\s*@PermisoId\s+AND\s+RolId\s+NOT\s+IN\s*\(@AdministradorId,\s*@AuditorId\)/i);
});
