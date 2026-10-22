'use strict';
require('dotenv').config({ quiet: true });
const fs = require('node:fs');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const sharp = require('sharp');
const state = JSON.parse(fs.readFileSync('.data/erp-deployment.json', 'utf8').replace(/^\uFEFF/, ''));
assert.match(state.lab, /^SecureFinanceERP_Estabilizacion_\d+$/);
process.env.DB_NAME = state.lab;
const { closePool } = require('../../src/config/database');
const suppliers = require('../../src/services/proveedorService').createProveedorService();
const products = require('../../src/services/productoService').createProductoService();
const photos = require('../../src/services/fotografiaService').createFotografiaService();
async function main() {
  const actor = 3;
  const created = (await suppliers.save(actor, { NIT: 'CF', Nombre: 'QA AISLADO ' + randomUUID(),
    Correo: null, Telefono: null, Direccion: null, Fotografia: null }))[0];
  let supplier = (await suppliers.list(actor, { id: created.ProveedorId }))[0];
  assert.ok(supplier);
  for (const active of [false, true]) {
    await suppliers.save(actor, { ...supplier, id: supplier.ProveedorId, Activo: active, Nombre: supplier.Nombre + ' editado' });
    supplier = (await suppliers.list(actor, { id: supplier.ProveedorId }))[0];
    assert.equal(!!supplier.Activo, active);
  }
  console.log('PASS SQL real: alta, seleccion, edicion e inactivacion/reactivacion de proveedor aislado');
  const product = (await products.list(actor, { id: 4, costo: true }))[0];
  await products.associate(actor, { id: product.ProductoId, ProveedorId: supplier.ProveedorId, Activo: true });
  const relations = await products.relations(actor, { productoId: product.ProductoId });
  assert.ok(relations.length >= 2);
  assert.ok(relations.some(r => r.ProveedorId === supplier.ProveedorId));
  const image = await sharp({ create: { width: 32, height: 32, channels: 3, background: '#123456' } }).png().toBuffer();
  const ref = await photos.upload(image, 'qa-laboratorio.png', 'image/png'); await photos.retain(ref);
  await products.save(actor, { ...product, id: product.ProductoId, Descripcion: product.Descripcion + ' QA aislado', Fotografia: ref });
  const saved = (await products.list(actor, { id: product.ProductoId, costo: true }))[0];
  assert.equal(saved.Fotografia, ref); assert.equal(saved.Descripcion, product.Descripcion + ' QA aislado');
  assert.equal(saved.Stock, product.Stock); assert.ok((await photos.read(ref)).length);
  console.log('PASS SQL real: varios proveedores por SKU, edicion y fotografia persistida sin alterar stock');
}
main().catch(e => { console.error(e.code || e.message); process.exitCode = 1; }).finally(closePool);
