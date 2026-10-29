'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { randomUUID } = require('node:crypto');
const v = require('../src/modules/promociones/validation');
const { createPromocionService } = require('../src/modules/promociones/service');
const { createApp } = require('../server');

const permissions = ['PROMOCIONES_CONSULTAR', 'PROMOCIONES_CREAR', 'PROMOCIONES_MODIFICAR', 'PROMOCIONES_ACTIVAR', 'VENTAS_REGISTRAR'];
const validRule = () => ({ OperacionId: randomUUID(), Codigo: 'VERANO-10', Nombre: '10% en verano', Descripcion: 'Campaña', TipoCodigo: 'PORCENTAJE',
  Porcentaje: '10.00', CantidadMinima: '', TopeDescuento: '', Desde: '2026-11-01', Hasta: '2026-11-30', Productos: [2], Categorias: [], Motivo: 'Alta QA' });

test('Promociones: validacion de reglas exige condiciones coherentes por tipo y elegibilidad', () => {
  const d = v.rule(validRule());
  assert.equal(d.Codigo, 'VERANO-10'); assert.equal(d.Porcentaje, '10.00'); assert.deepEqual(d.Productos, [2]);
  assert.equal(d.VigenteHasta.toISOString(), '2026-12-01T06:00:00.000Z');
  for (const change of [
    { Codigo: 'tiene espacio' }, { Codigo: 'a'.repeat(31) }, { Nombre: '' }, { Motivo: '' }, { OperacionId: 'bad' },
    { TipoCodigo: 'OTRO' }, { Porcentaje: '0' }, { Porcentaje: '95' }, { Porcentaje: undefined },
    { TipoCodigo: 'DOS_POR_UNO', Porcentaje: '10.00' }, { TipoCodigo: 'VOLUMEN', CantidadMinima: '1' },
    { Productos: [] }, { TipoCodigo: 'CATEGORIA', Categorias: [1] }, { Categorias: [1] },
    { Desde: '2026-12-01', Hasta: '2026-11-01' }, { Productos: [1, 1] },
  ]) assert.throws(() => v.rule({ ...validRule(), ...change }), v.ValidationError, JSON.stringify(change));
  const twoForOne = v.rule({ ...validRule(), TipoCodigo: 'DOS_POR_UNO', Porcentaje: null, CantidadMinima: null });
  assert.equal(twoForOne.CantidadMinima, 2); assert.equal(twoForOne.Porcentaje, null);
  const edit = v.rule({ ...validRule(), Version: 'ABCDEF0123456789' }, { edit: true });
  assert.equal(edit.Version, 'ABCDEF0123456789'); assert.equal(edit.Codigo, undefined);
  assert.throws(() => v.rule({ ...validRule(), Version: 'bad' }, { edit: true }), v.ValidationError);
});

test('Promociones: validacion de estado y filtros rechaza entradas fuera de catalogo', () => {
  const s = v.state({ Activa: true, Motivo: 'Publicar', Version: 'abcdef0123456789', OperacionId: randomUUID() });
  assert.equal(s.Version, 'ABCDEF0123456789');
  for (const change of [{ Activa: 'true' }, { Motivo: '' }, { Version: 'xyz' }]) assert.throws(() => v.state({ Activa: true, Motivo: 'x', Version: 'abcdef0123456789', OperacionId: randomUUID(), ...change }), v.ValidationError);
  const f = v.filters({ buscar: "a' OR 1=1 --", tipo: 'VOLUMEN', estado: 'VIGENTE', pagina: '2' });
  assert.equal(f.pagina, 2); assert.equal(f.tipo, 'VOLUMEN');
  for (const q of [{ tipo: 'OTRO' }, { estado: 'RARO' }, { pagina: '0' }, { pagina: '100002' }]) assert.throws(() => v.filters(q), v.ValidationError);
});

test('Promociones: vista previa valida el detalle igual que facturacion', () => {
  const lines = v.previewLines(JSON.stringify([{ ProductoId: 2, Cantidad: 3, DescuentoPorcentaje: '10' }]));
  assert.deepEqual(lines, [{ ProductoId: 2, Cantidad: 3, DescuentoPorcentaje: 10 }]);
  for (const bad of ['[]', '{}', JSON.stringify([{ ProductoId: 1, Cantidad: 1 }, { ProductoId: 1, Cantidad: 2 }]), 'no-json'])
    assert.throws(() => v.previewLines(bad), v.ValidationError);
});

test('Promociones: servicio tipado usa procedimientos y TVP propios, sin texto dinamico', async () => {
  const calls = [], requests = [];
  const provider = async () => ({ request: () => { const p = []; requests.push(p); return { input(...a) { p.push(a); return this; }, async execute(name) { calls.push(name); return { recordsets: [[{ PromocionId: 1 }], [], [], [], []] }; } }; } });
  const s = createPromocionService(provider), d = v.rule(validRule());
  await s.create(42, d);
  const productos = requests[0].find((p) => p[0] === 'Productos'), categorias = requests[0].find((p) => p[0] === 'Categorias');
  assert.equal(productos[1].rows.length, 1); assert.equal(categorias[1].rows.length, 0);
  assert.equal(requests[0][0][2], 42);
  await s.update(42, 1, { ...d, Version: 'ABCDEF0123456789' });
  await s.setState(42, 1, { Activa: true, Version: 'ABCDEF0123456789', OperacionId: randomUUID(), Motivo: 'x' });
  await s.list(42, { pagina: 1 }); await s.detail(42, 1); await s.createCategory(42, { Nombre: 'x', Motivo: 'y', OperacionId: randomUUID() });
  await s.assignCategory(42, { ProductoId: 1, CategoriaId: null, Motivo: 'y', OperacionId: randomUUID() });
  await s.preview(42, [{ ProductoId: 1, Cantidad: 1, DescuentoPorcentaje: 0 }]);
  await s.invoiceApplications(42, 7);
  assert.deepEqual(calls, ['dbo.P3_PRO_Crear', 'dbo.P3_PRO_Actualizar', 'dbo.P3_PRO_CambiarEstado', 'dbo.P3_PRO_Consultar', 'dbo.P3_PRO_Consultar',
    'dbo.P3_PRO_CrearCategoria', 'dbo.P3_PRO_AsignarCategoria', 'dbo.P3_PRO_SimularVenta', 'dbo.P3_PRO_ConsultarAplicacionesFactura']);
});

test('Promociones: invoiceApplications no falla si la extension no esta instalada (2812)', async () => {
  const provider = async () => ({ request: () => ({ input() { return this; }, async execute() { throw Object.assign(Error('missing'), { number: 2812 }); } }) });
  const s = createPromocionService(provider);
  assert.deepEqual(await s.invoiceApplications(42, 1), []);
  await assert.rejects(() => s.list(42, {}));
});

const doc = { PromocionId: 1, Codigo: 'VERANO-10', Nombre: '10% en verano', Descripcion: null, TipoCodigo: 'PORCENTAJE', Tipo: 'Descuento porcentual', Elegibilidad: 'PRODUCTO',
  Porcentaje: '10.00', CantidadMinima: null, TopeDescuento: null, VigenteDesde: new Date(), VigenteHasta: new Date(Date.now() + 86400000), Activa: true, Estado: 'VIGENTE',
  Version: 'ABCDEF0123456789', CreadaPor: 'admin', FechaCreacion: new Date(), ModificadaPor: 'admin', FechaModificacion: new Date(), Productos: 1, Categorias: 0, Aplicaciones: 0, DescuentoOtorgado: '0.00' };
async function fixture(t, permisos = permissions) {
  const calls = [];
  const service = {
    form: async () => ({ tipos: [{ TipoCodigo: 'PORCENTAJE', Nombre: 'Descuento porcentual', Descripcion: 'd', Elegibilidad: 'PRODUCTO' }], categorias: [{ CategoriaId: 1, Nombre: 'Cat', Activa: true, Productos: 0 }], ahora: new Date() }),
    searchProducts: async (actor, buscar, categoria) => { calls.push(['search', actor, buscar, categoria]); return { rows: [], next: false }; },
    list: async (a, f) => { calls.push(['list', a, f]); return [doc]; },
    detail: async (a, id) => { calls.push(['detail', a, id]); return { promocion: doc, productos: [{ ProductoId: 2, Codigo: 'SKU', Descripcion: 'P', Precio: '10.00', Activo: true }], categorias: [], historial: [{ HistorialId: 1, Accion: 'CREAR', FechaHora: new Date(), Responsable: 'admin', Motivo: 'Alta', CamposModificados: null, ValorAnterior: null, ValorNuevo: '{"a":1}' }], aplicaciones: [] }; },
    create: async (a, d) => { calls.push(['create', a, d]); return { PromocionId: 1, Codigo: d.Codigo, Estado: 'INACTIVA', Version: 'ABCDEF0123456789' }; },
    update: async (a, id, d) => { calls.push(['update', a, id, d]); return { PromocionId: id, Codigo: doc.Codigo, Estado: 'VIGENTE', Version: 'ABCDEF0123456789' }; },
    setState: async (a, id, d) => { calls.push(['setState', a, id, d]); return { PromocionId: id, Codigo: doc.Codigo, Estado: d.Activa ? 'VIGENTE' : 'INACTIVA', Version: 'ABCDEF0123456789' }; },
    createCategory: async (a, d) => { calls.push(['createCategory', a, d]); return { CategoriaId: 2, Nombre: d.Nombre }; },
    assignCategory: async (a, d) => { calls.push(['assignCategory', a, d]); return { ProductoId: d.ProductoId, CategoriaId: d.CategoriaId }; },
    preview: async (a, lines) => { calls.push(['preview', a, lines]); return { totales: { Subtotal: '100.00', Descuento: '0.00', SubtotalNeto: '100.00', IVA: '12.00', Total: '112.00' }, lineas: [] }; },
    invoiceApplications: async () => [],
  };
  const app = createApp({ secret: 'promociones-unit-test-secret-32-characters', production: false, promocionService: service,
    authService: { login: async () => ({ codigo: 0, usuario: { usuarioId: 42, nombreUsuario: 'QA', permisos, debeCambiarPassword: false } }) } });
  const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise((r) => { server.close(r); server.closeAllConnections(); }));
  const base = 'http://127.0.0.1:' + server.address().port;
  const login = await fetch(base + '/login', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: 'NombreUsuario=QA&Password=fixture', redirect: 'manual' });
  const cookie = login.headers.get('set-cookie').split(';')[0];
  const request = (url, options = {}) => fetch(base + url, { redirect: 'manual', ...options, headers: { Cookie: cookie, ...options.headers } });
  const post = (url, body, csrf) => request(url, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf || '' }, body: JSON.stringify(body) });
  return { base, request, post, calls, service };
}

test('Promociones HTTP: navegacion, filtros y detalle sin exponer scripts', async (t) => {
  const f = await fixture(t);
  for (const route of ['/promociones', '/promociones/nueva', '/promociones/1', '/promociones/1/editar', '/promociones/categorias']) {
    const r = await f.request(route); assert.equal(r.status, 200, route);
    const html = await r.text(); assert.doesNotMatch(html, /<script>bad<\/script>/);
  }
  assert.equal((await fetch(f.base + '/promociones', { redirect: 'manual' })).status, 302);
});

test('Promociones HTTP: RBAC separa consultar, crear, modificar y activar', async (t) => {
  const onlyConsult = await fixture(t, ['PROMOCIONES_CONSULTAR']);
  assert.equal((await onlyConsult.request('/promociones')).status, 200);
  assert.equal((await onlyConsult.request('/promociones/nueva')).status, 403);
  assert.equal((await onlyConsult.post('/promociones', validRule())).status, 403);
  assert.equal((await onlyConsult.post('/promociones/1/estado', {})).status, 403);
  assert.equal((await onlyConsult.post('/promociones/categorias', {})).status, 403);
  const none = await fixture(t, []);
  for (const route of ['/promociones', '/promociones/nueva', '/promociones/1', '/promociones/categorias']) assert.equal((await none.request(route)).status, 403);
  assert(!none.calls.some((c) => c[0] === 'create'));
});

test('Promociones HTTP: CSRF obligatorio para toda escritura', async (t) => {
  const f = await fixture(t);
  assert.equal((await f.post('/promociones', validRule())).status, 403);
  assert.equal((await f.post('/promociones', validRule(), 'bad')).status, 403);
  assert.equal((await f.post('/promociones', validRule(), 'a'.repeat(64))).status, 403);
  assert.equal((await f.post('/promociones/1/estado', { Activa: true, Motivo: 'x', Version: 'ABCDEF0123456789', OperacionId: randomUUID() })).status, 403);
});

test('Promociones HTTP: creacion, edicion y cambio de estado con CSRF valido', async (t) => {
  const f = await fixture(t), html = await (await f.request('/promociones/nueva')).text();
  const csrf = html.match(/name="csrf-token" content="([a-f0-9]+)"/)[1];
  const created = await f.post('/promociones', validRule(), csrf);
  assert.equal(created.status, 201); assert.equal((await created.json()).url, '/promociones/1');
  const updated = await f.post('/promociones/1', { ...validRule(), Version: 'ABCDEF0123456789' }, csrf);
  assert.equal(updated.status, 200);
  const state = await f.post('/promociones/1/estado', { Activa: true, Motivo: 'Publicar', Version: 'ABCDEF0123456789', OperacionId: randomUUID() }, csrf);
  assert.equal(state.status, 200);
  assert.equal((await f.post('/promociones', { ...validRule(), Codigo: '' }, csrf)).status, 400);
});

test('Promociones HTTP: categorias se crean y se asignan con motivo obligatorio', async (t) => {
  const f = await fixture(t), html = await (await f.request('/promociones/categorias')).text();
  const csrf = html.match(/name="csrf-token" content="([a-f0-9]+)"/)[1];
  const created = await f.post('/promociones/categorias', { Nombre: 'Oficina', Motivo: 'Alta', OperacionId: randomUUID() }, csrf);
  assert.equal(created.status, 201);
  assert.equal((await f.post('/promociones/categorias', { Nombre: '', Motivo: '', OperacionId: randomUUID() }, csrf)).status, 400);
  const assigned = await f.post('/promociones/categorias/asignar', { ProductoId: 2, CategoriaId: 1, Motivo: 'Asignar', OperacionId: randomUUID() }, csrf);
  assert.equal(assigned.status, 200);
});

test('Promociones HTTP: mensajes seguros por cada error de negocio sin exponer SQL interno', async (t) => {
  const f = await fixture(t), html = await (await f.request('/promociones/nueva')).text();
  const csrf = html.match(/name="csrf-token" content="([a-f0-9]+)"/)[1];
  for (const [number, status] of [[54101, 403], [57104, 409], [57105, 409], [57106, 409], [57107, 409], [57108, 409], [57109, 409], [57110, 404], [57102, 400], [1234, 503]]) {
    f.service.create = async () => { throw Object.assign(Error('SECRET SQL DETAIL'), { number }); };
    const r = await f.post('/promociones', validRule(), csrf);
    assert.equal(r.status, status, String(number));
    const data = await r.json(); assert.doesNotMatch(data.error, /SECRET/); assert.equal(data.incierto, status === 503);
  }
});

test('Promociones HTTP: vista previa de facturacion es de solo lectura y exige permiso de venta', async (t) => {
  const f = await fixture(t);
  const r = await f.request('/promociones/vista-previa?detalle=' + encodeURIComponent(JSON.stringify([{ ProductoId: 2, Cantidad: 1, DescuentoPorcentaje: 0 }])));
  assert.equal(r.status, 200); assert.equal((await r.json()).totales.Total, '112.00');
  const denied = await fixture(t, ['PROMOCIONES_CONSULTAR']);
  assert.equal((await denied.request('/promociones/vista-previa?detalle=' + encodeURIComponent(JSON.stringify([{ ProductoId: 1, Cantidad: 1 }])))).status, 403);
});

test('Promociones: integracion de venta omite el parametro opcional cuando la extension no esta instalada', async () => {
  const { createVentaService } = require('../src/services/ventaService');
  let lastCall = null;
  const provider = async () => ({ request: () => ({
    input(name, type, value) { lastCall = lastCall || {}; lastCall[name] = value === undefined ? true : value; return this; },
    async query() { return { recordset: [{ N: 0 }] }; },
    async execute(name) { lastCall.proc = name; return { recordset: [{ FacturaId: 1, Total: '100.00' }], recordsets: [[{ FacturaId: 1 }], []] }; },
  }) });
  const s = createVentaService(provider);
  assert.equal(await s.promocionesInstaladas(), false);
  await s.procesarVenta(1, 1, [{ ProductoId: 1, Cantidad: 1, DescuentoPorcentaje: 0 }]);
  assert.equal(lastCall.P3AplicarPromociones, undefined);
});
