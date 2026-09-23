'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const script = readFileSync(require.resolve('../src/public/js/facturacion.js'), 'utf8');

// DOM mínimo para probar el comportamiento del script real sin dependencias frontend.
function pantalla(fetchImpl) {
  class Element {
    constructor() { this.children = []; this.listeners = {}; this.value = ''; this.dataset = {}; this.className = ''; }
    append(element) { this.children.push(element); }
    replaceChildren() { this.children = []; }
    setAttribute() {}
    focus() {}
    addEventListener(event, callback) { this.listeners[event] = callback; }
    get classList() { return { remove: (name) => { this.className = this.className.replace(name, ''); } }; }
    trigger(event) { return this.listeners[event]({ preventDefault() {} }); }
  }
  const elements = new Map();
  const get = (id) => {
    if (!elements.has(id)) elements.set(id, new Element());
    return elements.get(id);
  };
  get('cliente').value = '1';
  get('nueva-venta').className = 'd-none';
  runInNewContext(script, { document: { getElementById: get, createElement: () => new Element(),
    querySelector: () => ({ content: 'csrf-prueba' }) }, fetch: fetchImpl });
  return {
    get,
    agregar(id, precio, cantidad, stock = 10, descripcion = 'Producto') {
      get('producto').selectedOptions = [{ value: String(id), dataset: { precio, stock: String(stock), descripcion } }];
      get('cantidad').value = String(cantidad);
      return get('agregar').trigger('click');
    },
    enviar: () => get('venta-form').trigger('submit'),
  };
}

test('Frontend: agrega, acumula repetidos, quita y calcula IVA con centavos exactos', () => {
  const p = pantalla();
  p.agregar(3, '10.25', 1, 10, '<img onerror=alert(1)>');
  p.agregar(3, '10.25', 1);
  p.agregar(4, '3.10', 3);
  assert.equal(p.get('lineas').children.length, 2);
  assert.equal(p.get('lineas').children[0].children[1].textContent, 2);
  assert.equal(p.get('subtotal').textContent, 'Q 29.80');
  assert.equal(p.get('iva').textContent, 'Q 3.58');
  assert.equal(p.get('total').textContent, 'Q 33.38');
  p.get('lineas').children[1].children[4].children[0].trigger('click');
  assert.equal(p.get('total').textContent, 'Q 22.96');
  p.agregar(3, '10.25', 9);
  assert.match(p.get('mensaje').textContent, /supera las existencias/);
  assert.equal(p.get('total').textContent, 'Q 22.96');
  p.get('lineas').children[0].children[4].children[0].trigger('click');
  assert.equal(p.get('total').textContent, 'Q 0.00');
  assert.equal(p.get('procesar').disabled, true);
});

test('Frontend: envío mínimo, bloqueo de doble clic y confirmación con totales SQL', async () => {
  const calls = [];
  let resolve;
  const p = pantalla((...args) => { calls.push(args); return new Promise((done) => { resolve = done; }); });
  p.agregar(3, '10.25', 2);
  const pending = p.enviar();
  await p.enviar();
  assert.equal(calls.length, 1);
  const [url, options] = calls[0];
  assert.equal(url, '/facturacion/procesar');
  assert.deepEqual(JSON.parse(options.body), { ClienteId: 1, Detalle: [{ ProductoId: 3, Cantidad: 2 }] });
  assert.equal(options.headers['X-CSRF-Token'], 'csrf-prueba');
  assert.equal(p.get('venta-campos').disabled, true);
  resolve({ ok: true, json: async () => ({ venta: { FacturaId: 19, Subtotal: '30.00', IVA: '3.60', Total: '33.60' } }) });
  await pending;
  assert.match(p.get('mensaje').textContent, /Factura #19.*Total Q 33.60/);
  assert.doesNotMatch(p.get('nueva-venta').className, /d-none/);
  await p.enviar();
  assert.equal(calls.length, 1);
});

test('Frontend: permite corregir stock, conserva líneas y no reintenta resultados inciertos', async () => {
  let calls = 0;
  const p = pantalla(async () => {
    calls += 1;
    if (calls === 1) return { ok: false, status: 409, json: async () => ({ error: 'Stock insuficiente.' }) };
    throw new Error('Fallo de conexión');
  });
  p.agregar(3, '10.25', 2);
  await p.enviar();
  assert.equal(p.get('venta-campos').disabled, false);
  assert.equal(p.get('lineas').children.length, 1);
  assert.match(p.get('mensaje').textContent, /Stock insuficiente/);
  await p.enviar();
  assert.equal(p.get('venta-campos').disabled, true);
  assert.match(p.get('mensaje').textContent, /antes de volver a enviar/);
  await p.enviar();
  assert.equal(calls, 2);
});
