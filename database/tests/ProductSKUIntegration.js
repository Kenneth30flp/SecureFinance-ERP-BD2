'use strict';
// All writes are restricted to the dedicated restored SKU laboratory.
require('dotenv').config({ quiet: true });
const fs = require('node:fs');
const assert = require('node:assert/strict');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const { randomUUID } = require('node:crypto');
const runFile = promisify(execFile);
const state = JSON.parse(fs.readFileSync('.data/product-sku-lab.json', 'utf8').replace(/^\uFEFF/, ''));
assert.match(state.database, /^SecureFinanceERP_SKU_\d+$/);
process.env.DB_NAME = state.database;
const db = require('../../src/config/database');
const products = require('../../src/services/productoService').createProductoService();
const suppliers = require('../../src/services/proveedorService').createProveedorService();
const { verifyIntegration } = require('../../src/config/integration');
async function admin(query) {
  const { stdout } = await runFile('sqlcmd', ['-S','localhost','-E','-C','-b','-d',state.database,
    '-h','-1','-y','8000','-w','65535','-Q','SET NOCOUNT ON; ' + query], { windowsHide: true, maxBuffer: 1024 * 1024 });
  return stdout.trim();
}
const json = async query => JSON.parse(await admin(query + ' FOR JSON PATH'));
const checks = [];
const pass = text => { checks.push(text); console.log('PASS ' + text); };
async function main() {
  const actor = 3;
  const original = await json("SELECT p.ProductoId,CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT p.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES)),2) Digest FROM dbo.Producto p ORDER BY p.ProductoId");
  const historyQuery = "SELECT (SELECT COUNT_BIG(*) FROM dbo.Factura) Facturas,(SELECT COUNT_BIG(*) FROM dbo.DetalleFactura) Detalles,(SELECT COUNT_BIG(*) FROM dbo.Kardex_Inventario) Kardex,(SELECT COUNT_BIG(*) FROM dbo.Proveedor) Proveedores,(SELECT COUNT_BIG(*) FROM dbo.ProductoProveedor) Relaciones";
  const history = await json(historyQuery);
  const supplier = (await suppliers.list(actor, {})).find(s => s.Activo);
  assert.ok(supplier);
  const input = { Descripcion: 'QA SKU aislado', Precio: '12.00', PrecioCosto: '5.00', ProveedorId: supplier.ProveedorId,
    StockMinimo: 1, PuntoReorden: 2, GarantiaMeses: 6, Fotografia: null };
  const identity = await verifyIntegration(await db.getPool()); assert.equal(identity.databaseName, state.database);
  const [first] = await products.save(actor, input);
  assert.match(first.Codigo, /^PRD-\d{6,}$/); assert.equal(first.Stock, 0);
  pass('alta automatica desde SQL con codigo definitivo y stock inicial cero');
  const next = BigInt(await admin('SELECT CONVERT(varchar(20),current_value)+CHAR(10) FROM sys.sequences WHERE name=\'SeqProductoSKU\'')) + 1n;
  const reserved = 'PRD-' + String(next).padStart(6, '0');
  const [manual] = await products.save(actor, { ...input, CodigoAutomatico: false, Codigo: reserved });
  assert.equal(manual.Codigo, reserved);
  const [skipped] = await products.save(actor, input); assert.notEqual(skipped.Codigo, reserved);
  assert.equal(skipped.Codigo, 'PRD-' + String(next + 1n).padStart(6, '0'));
  pass('SKU manual preservado; automatico salta codigo PRD existente');
  await assert.rejects(products.save(actor, { ...input, CodigoAutomatico: false, Codigo: reserved }), e => [2601,2627].includes(e.number));
  pass('SKU manual duplicado rechazado por indice unico real');
  const simultaneous = await Promise.all([products.save(actor, input), products.save(actor, input)]);
  const codes = simultaneous.map(r => r[0].Codigo);
  assert.equal(new Set(codes).size, 2); assert.ok(codes.every(c => /^PRD-\d{6,}$/.test(c)));
  assert.notEqual(simultaneous[0][0].ProductoId, simultaneous[1][0].ProductoId);
  pass('dos solicitudes SQL simultaneas generan SKU e identidades diferentes');
  const sameCode = 'QA-' + randomUUID().slice(0, 20);
  const race = await Promise.allSettled([1,2].map(() => products.save(actor, { ...input, CodigoAutomatico: false, Codigo: sameCode })));
  assert.equal(race.filter(r => r.status === 'fulfilled').length, 1);
  assert.ok([2601,2627].includes(race.find(r => r.status === 'rejected').reason.number));
  pass('dos altas manuales simultaneas del mismo SKU: una sola persistida');
  const beforeDenied = await admin("SELECT CONVERT(varchar(20),current_value) FROM sys.sequences WHERE name='SeqProductoSKU'");
  await assert.rejects(products.save(-1, input), e => e.number === 54101);
  assert.equal(await admin("SELECT CONVERT(varchar(20),current_value) FROM sys.sequences WHERE name='SeqProductoSKU'"), beforeDenied);
  pass('permiso empresarial vigente requerido antes de consumir secuencia');
  const pool = await db.getPool();
  await assert.rejects(pool.request().query('SELECT NEXT VALUE FOR dbo.SeqProductoSKU'), e => e.number === 229);
  pass('cuenta de aplicacion sin acceso directo a la secuencia');
  const current = await json("SELECT p.ProductoId,CONVERT(varchar(64),HASHBYTES('SHA2_256',(SELECT p.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES)),2) Digest FROM dbo.Producto p ORDER BY p.ProductoId");
  assert.deepEqual(current.filter(p => original.some(o => o.ProductoId === p.ProductoId)), original);
  assert.deepEqual(await json(historyQuery), history);
  pass('productos historicos completos, existencias y relaciones de negocio intactos');
  const seqBefore = await admin("SELECT CONVERT(varchar(20),current_value) FROM sys.sequences WHERE name='SeqProductoSKU'");
  await runFile('sqlcmd', ['-S','localhost','-E','-C','-b','-d',state.database,'-i','database/38_ERP_ProductoSKUAutomatico.sql','-f','65001'], { windowsHide: true });
  assert.equal(await admin("SELECT CONVERT(varchar(20),current_value) FROM sys.sequences WHERE name='SeqProductoSKU'"), seqBefore);
  pass('reaplicar migracion 38 no reinicia la secuencia ni reescribe productos');
  await admin('ALTER SEQUENCE dbo.SeqProductoSKU RESTART WITH 1000000');
  const [large] = await products.save(actor, input); assert.equal(large.Codigo, 'PRD-1000000');
  pass('numeracion mayor de seis digitos sin truncamiento');
  await admin('DBCC CHECKDB WITH NO_INFOMSGS');
}
main().then(() => fs.writeFileSync('.data/product-sku-results.json', JSON.stringify({ database: state.database, checks }, null, 2)))
  .catch(e => { console.error(e.stderr || e.message); process.exitCode = 1; }).finally(db.closePool);
