'use strict';
// Isolated browser-script VM fixtures, not a real-browser visual or SQL test.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../src/public/js/creditos.js'), 'utf8');
function browser(fetcher, storage = new Map()) {
  const button = { textContent: 'Confirmar abono', disabled: false };
  const fields = [ ['csrf', 'token'], ['OperacionId', 'stable-uuid'], ['Monto', '500.00'], ['FacturaId', '7'] ]
    .map(([name, value]) => ({ name, value, disabled: false }));
  let submit;
  const form = { action: '/creditos/abonos', dataset: { creForm: 'abono' }, elements: fields,
    querySelector: selector => selector.startsWith('button') ? button : null, addEventListener: (event, cb) => { if (event === 'submit') submit = cb; } };
  const notice = { hidden: true, text: '', replaceChildren(node) { this.text = node.text; }, append() {}, focus() {} };
  const document = { querySelector: selector => selector === 'meta[name="csrf-token"]' ? { content: 'token' } : null,
    querySelectorAll: () => [form], getElementById: () => notice, createTextNode: text => ({ text }), createElement: () => ({}) };
  const sessionStorage = { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key) };
  class FormData { constructor(f) { this.rows = f.elements.filter(e => !e.disabled).map(e => [e.name, e.value]); } [Symbol.iterator]() { return this.rows[Symbol.iterator](); } }
  vm.runInNewContext(source, { document, sessionStorage, FormData, fetch: fetcher, window: { print() {} } });
  return { fields, button, form, notice, storage, submit: () => submit({ preventDefault() {} }) };
}
test('CRE browser: network uncertainty keeps UUID, body and frozen fields across page reload', async () => {
  const requests = [], storage = new Map();
  const first = browser(async (url, options) => { requests.push(options.body); throw new Error('Network lost'); }, storage);
  await first.submit(); assert.match(first.notice.text, /Resultado incierto/); assert.equal(first.fields[2].disabled, true);
  assert.equal(first.button.disabled, false); assert.match(first.button.textContent, /Reintentar misma solicitud/);
  first.fields[2].value = '900.00'; await first.submit(); assert.equal(requests[0], requests[1]);
  const reloaded = browser(async (url, options) => { requests.push(options.body); return { ok: true, json: async () => ({ mensaje: 'Confirmado', url: '/creditos/recibos/1' }) }; }, storage);
  assert.equal(reloaded.fields[2].value, '500.00'); await reloaded.submit(); assert.equal(requests[0], requests[2]);
  assert.equal(storage.size, 0); assert.equal(reloaded.button.disabled, true);
});
test('CRE browser: duplicate clicks issue only one request until confirmation', async () => {
  let resolve, calls = 0;
  const b = browser(async () => { calls++; return new Promise(r => { resolve = r; }); });
  const pending = b.submit(); await b.submit(); assert.equal(calls, 1); assert.equal(b.button.disabled, true);
  resolve({ ok: true, json: async () => ({ mensaje: 'Confirmado' }) }); await pending; await b.submit(); assert.equal(calls, 1);
});
test('CRE browser: HTTP 503 followed by a known rejection still retains the original uncertain payload', async () => {
  let uncertain = true;
  const b = browser(async () => ({ ok: false, json: async () => ({ error: 'Rechazado', incierto: uncertain }) }));
  await b.submit(); assert.equal(b.storage.size, 1); assert.equal(b.fields[2].disabled, true);
  uncertain = false; await b.submit(); assert.equal(b.storage.size, 1); assert.equal(b.fields[2].disabled, true);
  assert.equal(b.fields[1].value, 'stable-uuid');
});
test('CRE browser: initial known rejection permits correction without generating UUID', async () => {
  const b = browser(async () => ({ ok: false, json: async () => ({ error: 'Rechazado', incierto: false }) }));
  await b.submit(); assert.equal(b.storage.size, 0); assert.equal(b.fields[2].disabled, false);
  assert.equal(b.fields[1].value, 'stable-uuid');
});
test('CRE browser: unavailable session storage blocks POST instead of losing uncertain reference', async () => {
  const storage = new Map(); storage.set = () => { throw new Error('Storage disabled'); };
  let calls = 0; const b = browser(async () => { calls++; }, storage); await b.submit(); assert.equal(calls, 0);
  assert.match(b.notice.text, /No se pudo conservar el UUID/);
});
