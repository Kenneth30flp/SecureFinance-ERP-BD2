'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createApp } = require('../server');
const { createVentaService } = require('../src/services/ventaService');
const { sql } = require('../src/config/database');

const clientes = [{ ClienteId: 1, NIT: 'DEMO-1', Nombre: '<script>cliente</script>' }];
const productos = [{ ProductoId: 3, Codigo: 'P1', Descripcion: '<img src=x onerror=alert(1)>', Precio: 10.25, Stock: 10 },
  { ProductoId: 4, Codigo: 'P2', Descripcion: 'Segundo', Precio: 3.10, Stock: 8 }];
const venta = { FacturaId: 7, FechaHora: '2026-09-23T12:00:00Z', Subtotal: '29.80', IVA: '3.58', Total: '33.38' };

function fakePool() {
  const calls = [];
  return {
    calls, error: null,
    request() {
      const inputs = [];
      const pool = this;
      return {
        input(...args) { inputs.push(args); return this; },
        async execute(procedure) {
          calls.push({ procedure, inputs });
          if (pool.error) throw pool.error;
          return { recordset: procedure.endsWith('ListarClientes') ? clientes
            : procedure.endsWith('ListarProductosDisponibles') ? productos : [venta] };
        },
      };
    },
  };
}

test('Servicio de ventas: listas y TVP tipado con una o varias líneas', async () => {
  const pool = fakePool();
  const service = createVentaService(async () => pool);
  assert.deepEqual(await service.listarClientes(), clientes);
  assert.deepEqual(await service.listarProductos(), productos);
  for (const lineas of [[{ ProductoId: 3, Cantidad: 2 }], [{ ProductoId: 4, Cantidad: 3 }, { ProductoId: 3, Cantidad: 2 }]]) {
    assert.deepEqual(await service.procesarVenta(1, 42, lineas), venta);
    const call = pool.calls.at(-1);
    assert.equal(call.procedure, 'dbo.sp_ProcesarVentaTransaccional');
    assert.deepEqual(call.inputs.slice(0, 2), [['ClienteId', sql.Int, 1], ['UsuarioId', sql.Int, 42]]);
    const [name, table] = call.inputs[2];
    assert.equal(name, 'Detalle');
    assert.ok(table instanceof sql.Table);
    assert.equal(table.schema, 'dbo');
    assert.equal(table.name, 'TipoDetalleVenta');
    assert.deepEqual(table.columns.map(({ name: column, type, nullable }) => [column, type, nullable]),
      [['ProductoId', sql.Int, false], ['Cantidad', sql.Int, false]]);
    assert.deepEqual([...table.rows], lineas.map(({ ProductoId, Cantidad }) => [ProductoId, Cantidad]));
    assert.equal(call.inputs.length, 3);
  }
  assert.deepEqual(pool.calls.slice(0, 2).map((call) => call.procedure),
    ['dbo.sp_ListarClientes', 'dbo.sp_ListarProductosDisponibles']);
  pool.error = Object.assign(new Error('detalle privado SQL'), { number: 52010 });
  await assert.rejects(service.procesarVenta(1, 42, [{ ProductoId: 3, Cantidad: 20 }]), { number: 52010 });
});

async function fixture(t, permisos = ['VENTAS_REGISTRAR']) {
  const pool = fakePool();
  const app = createApp({ secret: 'secreto-exclusivo-de-pruebas-ventas-123456', production: false,
    ventaService: createVentaService(async () => pool),
    authService: { async login() { return { codigo: 0, usuario: { usuarioId: 42, nombreUsuario: 'Cajero prueba', permisos } }; } },
  });
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise((resolve) => { server.close(resolve); server.closeAllConnections(); }));
  const base = `http://127.0.0.1:${server.address().port}`;
  let cookie;
  let token;
  const request = (path, options = {}) => fetch(base + path, {
    redirect: 'manual', ...options, headers: { ...(cookie ? { cookie } : {}), ...options.headers },
  });
  return {
    pool, request,
    async login() {
      const response = await request('/login', { method: 'POST', body: new URLSearchParams({ NombreUsuario: 'prueba', Password: 'prueba' }) });
      assert.equal(response.status, 303);
      cookie = response.headers.get('set-cookie').split(';')[0];
    },
    async pagina() {
      const response = await request('/facturacion');
      const html = await response.text();
      token = html.match(/name="csrf-token" content="([a-f0-9]+)"/)?.[1];
      return { response, html };
    },
    post(body, csrf = token) {
      return request('/facturacion/procesar', { method: 'POST', headers: {
        'Content-Type': 'application/json', ...(csrf ? { 'X-CSRF-Token': csrf } : {}),
      }, body: JSON.stringify(body) });
    },
  };
}
const entrada = () => ({ ClienteId: 1, Detalle: [{ ProductoId: 3, Cantidad: 2 }, { ProductoId: 4, Cantidad: 3 }] });

test('HTTP: ambas rutas requieren sesión y no ejecutan SQL anónimo', async (t) => {
  const f = await fixture(t);
  for (const response of [await f.request('/facturacion'), await f.post(entrada())]) {
    assert.equal(response.status, 302);
    assert.equal(response.headers.get('location'), '/login');
  }
  assert.equal(f.pool.calls.length, 0);
});

test('HTTP: ambas rutas deniegan usuario sin VENTAS_REGISTRAR', async (t) => {
  const f = await fixture(t, ['AUDITORIA_CONSULTAR']);
  await f.login();
  assert.equal((await f.request('/facturacion')).status, 403);
  assert.equal((await f.post(entrada())).status, 403);
  assert.doesNotMatch(await (await f.request('/dashboard')).text(), /href="\/facturacion"/);
  assert.equal(f.pool.calls.length, 0);
});

test('HTTP: formulario, listados, escape HTML, enlace y venta multiproducto', async (t) => {
  const f = await fixture(t);
  await f.login();
  const { response, html } = await f.pagina();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.match(html, /&lt;script&gt;cliente&lt;\/script&gt;/);
  assert.match(html, /data-descripcion="&lt;img/);
  assert.doesNotMatch(html, /<script>cliente|<img src=x/);
  assert.match(await (await f.request('/dashboard')).text(), /href="\/facturacion"/);
  const body = entrada();
  body.UsuarioId = 999;
  body.Total = 0.01;
  body.Detalle[0].PrecioUnitario = 0.01;
  const result = await f.post(body);
  assert.equal(result.status, 201);
  assert.deepEqual(await result.json(), { venta });
  const inputs = f.pool.calls.at(-1).inputs;
  assert.deepEqual(inputs[1], ['UsuarioId', sql.Int, 42]);
  assert.deepEqual([...inputs[2][1].rows], [[3, 2], [4, 3]]);
  assert.equal(inputs.length, 3);
  const single = await f.post({ ClienteId: '1', Detalle: [{ ProductoId: '3', Cantidad: '1' }] });
  assert.equal(single.status, 201);
  assert.deepEqual([...f.pool.calls.at(-1).inputs[2][1].rows], [[3, 1]]);
});

test('HTTP: rechaza CSRF ausente, inválido y de otra sesión antes de llamar SQL', async (t) => {
  const f = await fixture(t);
  await f.login();
  await f.pagina();
  const before = f.pool.calls.length;
  for (const token of ['', 'abc', '0'.repeat(64), 'é'.repeat(64)]) {
    assert.equal((await f.post(entrada(), token)).status, 403);
  }
  assert.equal(f.pool.calls.length, before);
});

test('HTTP: valida estructura, límites INT, cantidades y productos duplicados', async (t) => {
  const f = await fixture(t);
  await f.login();
  await f.pagina();
  const before = f.pool.calls.length;
  const invalidos = [null, {}, { ClienteId: 1, Detalle: [] }, { ClienteId: 1, Detalle: {} },
    { ClienteId: 1, Detalle: [null] }, { ClienteId: 1, Detalle: new Array(101).fill({ ProductoId: 3, Cantidad: 1 }) },
    { ClienteId: 1, Detalle: [{ ProductoId: 3, Cantidad: 1 }, { ProductoId: 3, Cantidad: 2 }] }];
  for (const value of [0, -1, 1.5, true, {}, [], '1e2', '1 OR 1=1', '2147483648', ' 1', null]) {
    invalidos.push({ ...entrada(), ClienteId: value });
    invalidos.push({ ClienteId: 1, Detalle: [{ ProductoId: 3, Cantidad: value }] });
    invalidos.push({ ClienteId: 1, Detalle: [{ ProductoId: value, Cantidad: 1 }] });
  }
  for (const body of invalidos) assert.equal((await f.post(body)).status, 400, JSON.stringify(body));
  assert.equal(f.pool.calls.length, before);
});

test('HTTP: mensajes seguros para stock y cada error de negocio; SQL interno nunca se expone', async (t) => {
  const f = await fixture(t);
  await f.login();
  await f.pagina();
  for (const number of [52001, 52002, 52003, 52004, 52005, 52006, 52007, 52008, 52009, 52010, 2627, 1205, undefined]) {
    f.pool.error = Object.assign(new Error('PASSWORD=secreto;Server=privado'), { number });
    const response = await f.post(entrada());
    assert.equal(response.status, number === 52010 ? 409 : number >= 52001 && number <= 52009 ? 400 : 503);
    const text = await response.text();
    assert.doesNotMatch(text, /PASSWORD|secreto|privado|Server/);
    if (number === 52010) assert.match(text, /Stock insuficiente/);
  }
  const response = await f.request('/facturacion');
  assert.equal(response.status, 503);
  assert.doesNotMatch(await response.text(), /PASSWORD|secreto|privado/);
});

test('HTTP: cuerpo excesivo se rechaza sin ejecutar una venta', async (t) => {
  const f = await fixture(t);
  await f.login();
  await f.pagina();
  const count = f.pool.calls.length;
  const response = await f.post({ ...entrada(), extra: 'x'.repeat(11000) });
  assert.equal(response.status, 413);
  assert.equal(f.pool.calls.length, count);
});
