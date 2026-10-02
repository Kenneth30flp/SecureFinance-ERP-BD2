'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const script = readFileSync(require.resolve('../src/public/js/facturacion.js'), 'utf8');

// DOM mínimo para probar el comportamiento del script real sin dependencias frontend.
function pantalla(fetchImpl, maxDescuento = 100) {
  class Element {
    constructor() { this.children = []; this.listeners = {}; this.value = ''; this.dataset = {}; this.className = ''; this.options = []; }
    append(element) { this.children.push(element); }
    replaceChildren() { this.children = []; }
    setAttribute() {}
    focus() {}
    checkValidity() { return true; }
    showModal() { this.open = true; }
    close() { this.open = false; }
    setCustomValidity(message) { this.validationMessage = message; }
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
  get('venta-form').dataset.maxDescuento = String(maxDescuento);
  get('cliente').options = [{ value: '', dataset: {}, textContent: 'Selecciona' }, { value: '1', dataset: { nombre: 'Comercial Aurora', nit: '123', search: '123 Aurora' }, textContent: 'Comercial Aurora', selected: true }];
  get('cliente').selectedOptions = [get('cliente').options[1]];
  get('producto').options = [{ value: '', dataset: {}, textContent: 'Selecciona' }, { value: '1', dataset: { search: 'HDMI Cable HDMI' }, textContent: 'Cable HDMI' }, { value: '2', dataset: { search: 'USB Cable USB' }, textContent: 'Cable USB' }];
  get('nueva-venta').className = 'd-none';
  let impresiones = 0;
  runInNewContext(readFileSync(require.resolve('../src/public/js/messages.js'), 'utf8') + '\n' + script, { document: { getElementById: get, createElement: () => new Element(),
    querySelector: () => ({ content: 'csrf-prueba' }) }, fetch: fetchImpl, window: { print: () => { impresiones += 1; } } });
  return {
    get,
    agregar(id, precio, cantidad, stock = 10, descripcion = 'Producto') {
      get('producto').selectedOptions = [{ value: String(id), dataset: { precio, stock: String(stock), descripcion } }];
      get('cantidad').value = String(cantidad);
      return get('agregar').trigger('click');
    },
    preparar: () => get('venta-form').trigger('submit'),
    enviar: () => { get('venta-form').trigger('submit'); return get('confirmar-venta').trigger('click'); },
    impresiones: () => impresiones,
  };
}

test('Frontend: agrega, acumula repetidos, quita y calcula IVA con centavos exactos', () => {
  const p = pantalla();
  p.agregar(3, '10.25', 1, 10, '<img onerror=alert(1)>');
  p.agregar(3, '10.25', 1);
  p.agregar(4, '3.10', 3);
  assert.equal(p.get('lineas').children.length, 2);
  assert.equal(p.get('lineas').children[0].children[1].children[0].value, '2');
  assert.equal(p.get('subtotal').textContent, 'Q 29.80');
  assert.equal(p.get('iva').textContent, 'Q 3.58');
  assert.equal(p.get('total').textContent, 'Q 33.38');
  p.get('lineas').children[1].children[6].children[0].trigger('click');
  assert.equal(p.get('total').textContent, 'Q 22.96');
  p.agregar(3, '10.25', 9);
  assert.match(p.get('mensaje').textContent, /supera las existencias/);
  assert.equal(p.get('total').textContent, 'Q 22.96');
  p.get('lineas').children[0].children[6].children[0].trigger('click');
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
  assert.deepEqual(JSON.parse(options.body), { ClienteId: 1, MotivoDescuento: null, Detalle: [{ ProductoId: 3, Cantidad: 2, DescuentoPorcentaje: '0.00' }] });
  assert.equal(options.headers['X-CSRF-Token'], 'csrf-prueba');
  assert.equal(p.get('venta-campos').disabled, true);
  assert.equal(p.get('confirmar-venta').disabled, true);
  assert.equal(p.get('cancelar-venta').disabled, true);
  resolve({ ok: true, json: async () => ({ venta: { FacturaId: 19, Subtotal: '30.00', IVA: '3.60', Total: '33.60' } }) });
  await pending;
  assert.match(p.get('mensaje').textContent, /Factura #19.*Total Q 33.60/);
  assert.equal(p.get('comprobante').hidden, false);
  assert.equal(p.get('recibo-total').textContent, 'Q 33.60');
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

test('Frontend: descuento editable, centavos exactos y caso Cable HDMI', () => {
  let peticiones = 0;
  const p = pantalla(() => { peticiones += 1; });
  p.agregar(1, '35.90', 1);
  const cambiar = (valor) => {
    const input = p.get('lineas').children[0].children[3].children[0].children[0];
    input.value = valor;
    input.trigger('input');
    return input;
  };
  for (const [porcentaje, descuento, neto, iva, total] of [
    ['0.00', '0.00', '35.90', '4.31', '40.21'],
    ['10.00', '3.59', '32.31', '3.88', '36.19'],
    ['7.50', '2.69', '33.21', '3.99', '37.20'],
    ['100.00', '35.90', '0.00', '0.00', '0.00'],
  ]) {
    cambiar(porcentaje);
    assert.equal(p.get('descuento-total').textContent, `− Q ${descuento}`);
    assert.equal(p.get('subtotal-neto').textContent, `Q ${neto}`);
    assert.equal(p.get('iva').textContent, `Q ${iva}`);
    assert.equal(p.get('total').textContent, `Q ${total}`);
  }
  for (const valor of ['-1', '100.01', '1.234', '', '1e2']) {
    assert.ok(cambiar(valor).validationMessage);
    assert.equal(p.get('total').textContent, 'Q 0.00');
  }
  cambiar('10');
  p.agregar(2, '10.25', 2);
  const segundo = p.get('lineas').children[1].children[3].children[0].children[0];
  segundo.value = '7.50'; segundo.trigger('input');
  assert.equal(p.get('subtotal').textContent, 'Q 56.40');
  assert.equal(p.get('subtotal-neto').textContent, 'Q 51.27');
  assert.equal(p.get('total').textContent, 'Q 57.42');
  assert.equal(peticiones, 0);
});

test('Frontend: cantidad editable, stock, ahorro y rechazo de valores inválidos', () => {
  const p = pantalla();
  p.agregar(1, '35.90', 1, 97, 'Cable HDMI');
  const row = p.get('lineas').children[0];
  const cantidad = row.children[1].children[0];
  const descuento = row.children[3].children[0].children[0];
  cantidad.value = '2'; cantidad.trigger('input');
  descuento.value = '25.00'; descuento.trigger('input');
  assert.equal(row.children[4].textContent, '− Q 17.95');
  assert.equal(row.children[5].textContent, 'Q 53.85');
  assert.match(row.children[0].children[1].textContent, /Stock actual: 97.*Después: 95/);
  assert.equal(p.get('iva').textContent, 'Q 6.46');
  assert.equal(p.get('total').textContent, 'Q 60.31');
  for (const valor of ['0', '-1', '1.5', '98', '1e2', '']) {
    cantidad.value = valor; cantidad.trigger('input'); p.preparar();
    assert.ok(cantidad.validationMessage);
    assert.ok(!p.get('confirmacion').open);
    assert.equal(p.get('total').textContent, 'Q 60.31');
  }
  cantidad.value = '94'; cantidad.trigger('input');
  assert.equal(row.children[0].children[2].hidden, false);
});

test('Frontend: política Cajero 10%, confirmación, cancelación y sin POST preliminar', async () => {
  let peticiones = 0;
  const p = pantalla(async () => { peticiones += 1; return { ok: false, status: 400, json: async () => ({ error: 'validación' }) }; }, 10);
  p.agregar(1, '35.90', 1);
  const descuento = p.get('lineas').children[0].children[3].children[0].children[0];
  descuento.value = '25'; descuento.trigger('input'); p.preparar();
  assert.match(descuento.validationMessage, /máximo.*10%/);
  assert.ok(!p.get('confirmacion').open);
  descuento.value = '10'; descuento.trigger('input'); p.preparar();
  assert.equal(p.get('confirmacion').open, true);
  assert.equal(p.get('confirmar-total').textContent, 'Q 36.19');
  assert.equal(peticiones, 0);
  p.get('cancelar-venta').trigger('click');
  assert.equal(p.get('confirmacion').open, false);
  assert.equal(p.get('venta-campos').disabled, false);
  await p.get('confirmar-venta').trigger('click');
  assert.equal(peticiones, 0);
  p.preparar(); p.get('confirmacion').trigger('cancel');
  assert.equal(p.get('confirmacion').open, false);
  await p.enviar();
  assert.equal(peticiones, 1);
});

test('Frontend: comprobante e impresión usan metadatos, detalle e importes devueltos por SQL', async () => {
  let cuerpo;
  const p = pantalla(async (url, options) => {
    cuerpo = JSON.parse(options.body);
    return { ok: true, json: async () => ({ venta: {
      FacturaId: 15, Cliente: 'Cliente SQL', NIT: 'SQL-123', Cajero: 'admin_sql', FechaHora: '2026-10-01T12:00:00Z',
      Subtotal: '71.80', Descuento: '17.95', SubtotalNeto: '53.85', IVA: '6.46', Total: '60.31', MotivoDescuento: 'Cliente frecuente',
      Detalle: [{ Descripcion: '<img src=x> Cable SQL', Cantidad: 2, PrecioUnitario: '35.90', DescuentoPorcentaje: '25.00', DescuentoMonto: '17.95', SubtotalNeto: '53.85' }],
    } }) };
  });
  p.get('imprimir-comprobante').trigger('click'); assert.equal(p.impresiones(), 0);
  p.agregar(1, '1.00', 1);
  const descuento = p.get('lineas').children[0].children[3].children[0].children[0];
  descuento.value = '10'; descuento.trigger('input');
  p.get('motivo-descuento').value = 'Cliente frecuente';
  await p.enviar();
  assert.equal(cuerpo.MotivoDescuento, 'Cliente frecuente');
  assert.equal(p.get('recibo-cliente').textContent, 'Cliente SQL');
  assert.equal(p.get('recibo-cajero').textContent, 'admin_sql');
  assert.equal(p.get('recibo-total').textContent, 'Q 60.31');
  assert.equal(p.get('recibo-detalle').children[0].children[0].textContent, '<img src=x> Cable SQL');
  assert.equal(p.get('venta-form').hidden, true);
  p.get('imprimir-comprobante').trigger('click'); assert.equal(p.impresiones(), 1);
});

test('Frontend: búsquedas por código/descripción y NIT/nombre conservan opciones reales', () => {
  const p = pantalla();
  p.get('buscar-producto').value = 'hdmi'; p.get('buscar-producto').trigger('input');
  assert.equal(p.get('producto').options[1].hidden, false);
  assert.equal(p.get('producto').options[2].hidden, true);
  p.get('buscar-producto').value = ''; p.get('buscar-producto').trigger('input');
  assert.equal(p.get('producto').options[2].hidden, false);
  p.get('buscar-cliente').value = '123'; p.get('buscar-cliente').trigger('input');
  assert.equal(p.get('cliente').options[1].hidden, false);
  p.get('buscar-cliente').value = 'inexistente'; p.get('buscar-cliente').trigger('input');
  assert.equal(p.get('cliente').value, '');
});
