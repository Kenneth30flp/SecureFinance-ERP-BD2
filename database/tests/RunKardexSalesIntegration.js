'use strict';

// SQL Server real, Windows integrated. No .env, no credentials, no real DB writes.
// node database/tests/RunKardexSalesIntegration.js --run --server localhost,1433 --trust-server-certificate
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const serverAt = process.argv.indexOf('--server');
const server = serverAt < 0 ? 'localhost,1433' : process.argv[serverAt + 1];
const trust = process.argv.includes('--trust-server-certificate');
const database = 'SecureFinanceERP_ParteII_Test_Kardex_' + randomUUID().replaceAll('-', '');
const quote = value => "N'" + String(value).replaceAll("'", "''") + "'";
const uuid = () => randomUUID();
let directory; let token; let sequence = 0; let fixture;
const results = [];
const reportPath = path.join(root, 'docs/ParteIIKardexVentaResultados.json');
const report = { database, server, results, retained: true, originalDatabaseWritten: false };

async function command(binary, args, label, timeout = 120000) {
  const child = spawn(binary, args, { cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
  let output = '';
  const timer = setTimeout(() => child.kill(), timeout);
  child.stdout.on('data', chunk => { output += chunk.toString('utf8'); });
  child.stderr.on('data', chunk => { output += chunk.toString('utf8'); });
  return new Promise((resolve, reject) => {
    child.once('error', error => { clearTimeout(timer); reject(error); });
    child.once('close', async code => {
      clearTimeout(timer);
      await fs.writeFile(path.join(directory, `${++sequence}-${label}.log`), output);
      if (code !== 0) reject(new Error(`${label}: exit ${code}\n${output.slice(-10000)}`));
      else resolve(output);
    });
  });
}

function safeSql(text) {
  const identifiers = text.replaceAll('[', '').replaceAll(']', '');
  assert(!/\bUSE\s+\[?\w+/i.test(text), 'SQL input must not change database');
  assert(!/\b(?:CREATE|ALTER|DROP)\s+(?:DATABASE|LOGIN|SERVER)\b/i.test(text), 'No server operations');
  assert(!/\b[A-Z_]\w*\s*\.\s*\w+\s*\.\s*\w+\b|\b[A-Z_]\w*\s*\.\s*\.\s*\w+\b/i.test(identifiers), 'No cross-database references');
  assert(!/^\s*(?::|!!)/m.test(text), 'No embedded SQLCMD commands');
}

async function sql(text, label = 'sql', initial = false) {
  safeSql(text);
  const guard = `USE [${database}];\nGO\nSET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;\nIF DB_NAME()<>${quote(database)} OR NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'ParteII.TestRun'${initial ? '' : ' AND CONVERT(NVARCHAR(32),value)=' + quote(token)}) THROW 54900,'Wrong isolated context',1;\nGO\n`;
  const batches = text.split(/^\s*GO\s*\r?$/mi).filter(batch => batch.trim());
  const file = path.join(directory, uuid() + '.sql');
  await fs.writeFile(file, batches.map(batch => guard + batch + '\nGO\n').join('\n'));
  const args = ['-S', server, '-E', '-l', '10', '-b', '-r', '0', '-f', '65001', '-w', '65535', '-y', '0', '-d', database, '-i', file];
  if (trust) args.push('-C');
  return command('sqlcmd', args, label);
}

function evidence(output) {
  const line = output.split(/\r?\n/).findLast(value => value.startsWith('EVIDENCE|'));
  assert(line, 'Missing SQL evidence');
  return JSON.parse(line.slice('EVIDENCE|'.length));
}

async function json(select, label) {
  const split = select.lastIndexOf('\nSELECT ');
  const prefix = split < 0 ? '' : select.slice(0, split);
  const finalSelect = split < 0 ? select : select.slice(split + 1);
  return evidence(await sql(`SET NOCOUNT ON; ${prefix}\nSELECT N'EVIDENCE|'+(${finalSelect} FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);`, label));
}

async function record(id, description, work) {
  try {
    const data = await work();
    results.push({ id, description, result: 'PASS', evidence: data ?? null });
    console.log(`PASS|${id}|${description}`);
  } catch (error) {
    results.push({ id, description, result: 'FAIL', error: error.message });
    throw error;
  } finally {
    await fs.writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
  }
}

function importRegression(output, prefix) {
  const lines = output.split(/\r?\n/);
  for (const line of lines) {
    const match = line.match(/^PASS\|(\d+|S\d+)\|(.+)$/);
    if (match) results.push({ id: prefix + match[1], description: match[2], result: 'PASS' });
  }
  assert.equal(results.filter(result => result.id.startsWith(prefix)).length, 32, 'All foundation cases must pass');
  assert(/OK: Funciones, auditor.*DML e hist.*validados\./.test(output), 'Legacy audit regression missing');
  results.push({ id: prefix + 'AUDIT', description: 'Auditoria e historico heredados', result: 'PASS' });
}

async function product(stock = 10, price = '35.90') {
  const code = 'K' + uuid().replaceAll('-', '');
  const operation = uuid();
  return json(`DECLARE @P INT;
EXEC dbo.sp_RegistrarProducto @ActorUsuarioId=${fixture.actor},@Codigo=${quote(code)},@Descripcion=N'Producto sintetico',@Precio=${price},@PrecioCosto=1,@ProveedorId=${fixture.provider},@ProductoId=@P OUTPUT;
${stock ? `EXEC dbo.sp_RegistrarMovimientoKardex @P,'COMPRA',${stock},${fixture.actor},N'COMPRA-TEST',${quote(operation)},1,N'Abastecimiento sintetico',NULL,NULL,0;` : ''}
SELECT @P AS id`, 'product');
}

function detail(lines) {
  return `DECLARE @D dbo.TipoDetalleVentaDescuento; INSERT @D VALUES ${lines.map(line => `(${line.id},${line.quantity ?? 1},${line.discount ?? 0})`).join(',')};`;
}

async function sale(lines, actor = fixture.actor, adapter = false) {
  const declaration = adapter ? `DECLARE @D dbo.TipoDetalleVenta; INSERT @D VALUES ${lines.map(line => `(${line.id},${line.quantity ?? 1})`).join(',')};` : detail(lines);
  const output = await sql(`SET NOCOUNT ON; ${declaration} DECLARE @F INT;
EXEC dbo.${adapter ? 'sp_ProcesarVentaSinDescuento' : 'sp_ProcesarVentaTransaccional'} @ClienteId=${fixture.client},@UsuarioId=${actor},@Detalle=@D,@FacturaId=@F OUTPUT;
SELECT N'EVIDENCE|'+(SELECT FacturaId,CONVERT(VARCHAR(30),Subtotal) Subtotal,CONVERT(VARCHAR(30),DescuentoTotal) Descuento,CONVERT(VARCHAR(30),Subtotal-DescuentoTotal) Neto,CONVERT(VARCHAR(30),IVA) IVA,CONVERT(VARCHAR(30),Total) Total,
(SELECT CONVERT(VARCHAR(30),Monto) FROM dbo.MovimientoCaja WHERE FacturaId=@F) Caja,
(SELECT COUNT(*) FROM dbo.Kardex_Inventario k JOIN dbo.DetalleFactura d ON d.DetalleFacturaId=k.DetalleFacturaId WHERE d.FacturaId=@F) Movimientos
FROM dbo.Factura WHERE FacturaId=@F FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);`, 'sale');
  return evidence(output);
}

async function snapshot() {
  const tables = [['Factura', 'FacturaId'], ['DetalleFactura', 'DetalleFacturaId'], ['Producto', 'ProductoId'], ['Kardex_Inventario', 'KardexId'], ['MovimientoCaja', 'MovimientoCajaId'], ['Bitacora_Transacciones', 'BitacoraTransaccionId']];
  const columns = tables.map(([table, key]) => `(SELECT COUNT_BIG(*) FROM dbo.${table}) AS ${table}Count,CONVERT(VARCHAR(64),HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),(SELECT * FROM dbo.${table} ORDER BY ${key} FOR JSON PATH,INCLUDE_NULL_VALUES))),2) AS ${table}Hash`);
  return json('SELECT ' + columns.join(','), 'snapshot');
}

async function rejectedSale(lines, expected, actor = fixture.actor) {
  const before = await snapshot();
  const actual = evidence(await sql(`SET NOCOUNT ON; ${detail(lines)} DECLARE @F INT,@Error INT;
BEGIN TRY EXEC dbo.sp_ProcesarVentaTransaccional ${fixture.client},${actor},@D,@F OUTPUT; END TRY
BEGIN CATCH SET @Error=ERROR_NUMBER(); END CATCH;
SELECT N'EVIDENCE|'+(SELECT @Error Error,@F FacturaId,@@TRANCOUNT Transacciones FOR JSON PATH,INCLUDE_NULL_VALUES,WITHOUT_ARRAY_WRAPPER);`, 'rejection'));
  assert.equal(actual.Error, expected);
  assert.equal(actual.FacturaId, null);
  assert.equal(actual.Transacciones, 0);
  assert.deepEqual(await snapshot(), before);
  return actual;
}

async function race(products, expectedSuccesses) {
  const run = uuid();
  const before = await json('SELECT (SELECT COUNT(*) FROM dbo.Factura) Facturas,(SELECT COUNT(*) FROM dbo.MovimientoCaja) Caja', 'race-before');
  const worker = name => sql(`SET NOCOUNT ON; SET XACT_ABORT ON;
INSERT dbo.PruebaKardexConcurrencia(RunId,Worker,SessionId) VALUES(${quote(run)},'${name}',@@SPID);
DECLARE @Limite DATETIME2=DATEADD(SECOND,20,SYSUTCDATETIME());
WHILE (SELECT COUNT(*) FROM dbo.PruebaKardexConcurrencia WHERE RunId=${quote(run)})<2
BEGIN IF SYSUTCDATETIME()>@Limite THROW 54900,'Concurrent barrier timeout',1; WAITFOR DELAY '00:00:00.050'; END;
${detail((name === 'A' ? products : [...products].reverse()).map(id => ({ id })))}
DECLARE @F INT,@Error INT;
BEGIN TRY
 BEGIN TRANSACTION;
 EXEC dbo.sp_ProcesarVentaTransaccional ${fixture.client},${fixture.actor},@D,@F OUTPUT;
 -- Retener la transaccion propia del test permite observar bloqueo SQL real.
 WAITFOR DELAY '00:00:02';
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH SET @Error=ERROR_NUMBER(); IF XACT_STATE()<>0 ROLLBACK TRANSACTION; END CATCH;
UPDATE dbo.PruebaKardexConcurrencia SET FacturaId=@F,ErrorNumero=@Error,Finalizado=SYSUTCDATETIME() WHERE RunId=${quote(run)} AND Worker='${name}';`, 'worker-' + name);
  const observer = sql(`SET NOCOUNT ON; DECLARE @Limite DATETIME2=DATEADD(SECOND,20,SYSUTCDATETIME()),@Espera INT,@Bloqueador INT,@Tipo NVARCHAR(60);
WHILE SYSUTCDATETIME()<@Limite
BEGIN
 SELECT TOP(1) @Espera=r.session_id,@Bloqueador=r.blocking_session_id,@Tipo=r.wait_type FROM sys.dm_exec_requests r
 WHERE r.session_id IN(SELECT SessionId FROM dbo.PruebaKardexConcurrencia WHERE RunId=${quote(run)}) AND r.blocking_session_id IN(SELECT SessionId FROM dbo.PruebaKardexConcurrencia WHERE RunId=${quote(run)});
 IF @Espera IS NOT NULL BREAK;
 WAITFOR DELAY '00:00:00.050';
END;
IF @Espera IS NULL THROW 54900,'No real simultaneous SQL lock observed',1;
SELECT N'EVIDENCE|'+(SELECT @Espera Waiter,@Bloqueador Blocker,@Tipo WaitType FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);`, 'race-observer');
  const [, , observation] = await Promise.all([worker('A'), worker('B'), observer]);
  const lock = evidence(observation);
  assert.notEqual(lock.Waiter, lock.Blocker);
  const state = await json(`SELECT (SELECT COUNT(*) FROM dbo.PruebaKardexConcurrencia WHERE RunId=${quote(run)} AND FacturaId IS NOT NULL AND ErrorNumero IS NULL) Exitos,
(SELECT COUNT(*) FROM dbo.PruebaKardexConcurrencia WHERE RunId=${quote(run)} AND FacturaId IS NULL AND ErrorNumero=52010) Rechazos,
(SELECT COUNT(DISTINCT SessionId) FROM dbo.PruebaKardexConcurrencia WHERE RunId=${quote(run)}) Sesiones,
(SELECT COUNT(*) FROM dbo.Factura)-${before.Facturas} Facturas,(SELECT COUNT(*) FROM dbo.MovimientoCaja)-${before.Caja} Caja,
(SELECT COUNT(*) FROM dbo.Producto WHERE ProductoId IN(${products.join(',')}) AND Stock=0) SaldosCero,
(SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE ProductoId IN(${products.join(',')}) AND TipoMovimiento='VENTA') Salidas`, 'race-after');
  assert.equal(state.Exitos, expectedSuccesses);
  assert.equal(state.Rechazos, 2 - expectedSuccesses);
  assert.equal(state.Sesiones, 2);
  assert.equal(state.Facturas, expectedSuccesses);
  assert.equal(state.Caja, expectedSuccesses);
  assert.equal(state.SaldosCero, products.length);
  assert.equal(state.Salidas, expectedSuccesses * products.length);
  return { ...state, ...lock };
}

async function main() {
  assert(process.argv.includes('--run'), 'Explicit --run required: creates only a new isolated test database');
  assert(/^SecureFinanceERP_ParteII_Test_Kardex_[a-f0-9]{32}$/.test(database));
  directory = await fs.mkdtemp(path.join(os.tmpdir(), 'securefinance-kardex-sales-'));
  report.logs = directory;
  try {
    const previous = JSON.parse(await fs.readFile(reportPath, 'utf8'));
    report.previousAttempts = [...(previous.previousAttempts ?? []), { database: previous.database, status: previous.error ? 'FAIL' : 'PASS', error: previous.error ?? null, logs: previous.logs, summary: previous.summary }];
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  console.log('ISOLATED DATABASE: ' + database);
  const foundationArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(__dirname, 'RunParteIIKennethTests.ps1'), '-Server', server, '-Database', database, '-Run'];
  if (trust) foundationArgs.push('-TrustServerCertificate');
  importRegression(await command('powershell.exe', foundationArgs, 'foundations'), 'F');
  token = evidence(await sql("SET NOCOUNT ON; SELECT N'EVIDENCE|'+(SELECT CONVERT(NVARCHAR(32),value) AS Token FROM sys.extended_properties WHERE class=0 AND name=N'ParteII.TestRun' FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);", 'token', true)).Token;
  assert(/^[a-f0-9]{32}$/.test(token));
  const migration = await fs.readFile(path.join(root, 'database/21_ParteII_IntegracionFacturacionKardex.sql'), 'utf8');
  await record('I01', 'Migracion 21 repetible sin apertura ni duplicados', async () => {
    await sql(migration, 'migration21-first');
    const shape = () => json("SELECT (SELECT type,name FROM sys.objects WHERE is_ms_shipped=0 ORDER BY type,name FOR JSON PATH) Objetos,(SELECT COUNT(*) FROM dbo.Kardex_Inventario) Movimientos,(SELECT Habilitado FROM dbo.ConfiguracionInventario) Habilitado", 'shape');
    const first = await shape();
    await sql(migration, 'migration21-second');
    assert.deepEqual(await shape(), first);
    assert.equal(first.Movimientos, 0); assert.equal(first.Habilitado, false);
    return { repeated: true, openingNotExecuted: true };
  });
  const core = await fs.readFile(path.join(__dirname, 'ParteIIKennethTests.sql'), 'utf8');
  const extra = await fs.readFile(path.join(__dirname, 'ParteIIKennethSupplementalTests.sql'), 'utf8');
  const legacy = (await fs.readFile(path.join(__dirname, 'AuditTests.sql'), 'utf8')).replace(/^USE \[SecureFinanceERP\];\r?\nGO\r?\n/, '');
  importRegression(await sql(core + '\n' + extra + '\n' + legacy, 'integrated-regression'), 'R');
  fixture = await json(`DECLARE @Prov INT,@Legacy INT,@C INT,@Cashier INT,@Historica INT,@DetalleHistorico INT;
INSERT dbo.Rol_Permiso(RolId,PermisoId) SELECT r.RolId,p.PermisoId FROM dbo.Rol r CROSS JOIN dbo.Permiso p WHERE r.Nombre=N'Administrador' AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=r.RolId AND rp.PermisoId=p.PermisoId);
DECLARE @A INT=(SELECT u.UsuarioId FROM dbo.Usuario u WHERE u.NombreUsuario=N'admin');
INSERT dbo.Usuario(NombreUsuario,NombreCompleto,Correo,PasswordHash,Salt) VALUES(N'cashier_kardex',N'Cajero sintetico',N'cashier_kardex@example.invalid',CRYPT_GEN_RANDOM(64),CRYPT_GEN_RANDOM(32)); SET @Cashier=SCOPE_IDENTITY();
INSERT dbo.Usuario_Rol(UsuarioId,RolId) SELECT @Cashier,RolId FROM dbo.Rol WHERE Nombre=N'Cajero';
EXEC dbo.sp_RegistrarProveedor @ActorUsuarioId=@A,@NIT=N'PROVEEDORKDX',@Nombre=N'Proveedor sintetico',@ProveedorId=@Prov OUTPUT;
INSERT dbo.Cliente(NIT,Nombre) VALUES(N'CLIENTEKDX',N'Cliente sintetico'); SET @C=SCOPE_IDENTITY();
INSERT dbo.Producto(Codigo,Descripcion,Precio,Stock) VALUES(N'LEGACY20',N'Saldo anterior sintetico',10,20); SET @Legacy=SCOPE_IDENTITY();
INSERT dbo.Factura(ClienteId,UsuarioId,Subtotal,IVA,Total) VALUES(@C,@A,10,1.20,11.20); SET @Historica=SCOPE_IDENTITY();
INSERT dbo.DetalleFactura(FacturaId,ProductoId,Cantidad,PrecioUnitario,Subtotal) VALUES(@Historica,@Legacy,1,10,10); SET @DetalleHistorico=SCOPE_IDENTITY();
SELECT @A actor,@Cashier cashier,@Prov provider,@C client,@Legacy legacy,@DetalleHistorico historicalDetail`, 'setup');
  const opening = uuid();
  report.opening = opening;
  await record('I02', 'Apertura conserva todas las existencias previas', async () => {
    const before = await json('SELECT (SELECT ProductoId,Stock FROM dbo.Producto ORDER BY ProductoId FOR JSON PATH) Stocks,(SELECT COUNT(*) FROM dbo.Producto) Productos', 'opening-before');
    await sql(`EXEC dbo.sp_AbrirKardexInventario ${quote(opening)},${fixture.actor},N'CORTE-TEST',N'Apertura sintetica';`, 'opening');
    const after = await json('SELECT (SELECT ProductoId,Stock FROM dbo.Producto ORDER BY ProductoId FOR JSON PATH) Stocks,(SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE TipoMovimiento=\'APERTURA\') Productos', 'opening-after');
    assert.deepEqual(after, before);
    return { products: after.Productos, stockNotAdded: true };
  });
  await record('I03', 'Apertura repetible y referencia inequivoca', async () => {
    const before = await snapshot();
    await sql(`EXEC dbo.sp_AbrirKardexInventario ${quote(opening)},${fixture.actor},N'CORTE-TEST',N'Apertura sintetica';`, 'opening-retry');
    assert.deepEqual(await snapshot(), before);
    return { duplicated: false };
  });
  await record('I04', 'Habilitacion explicita posterior a conciliacion', async () => {
    await sql(`EXEC dbo.sp_HabilitarKardexInventario ${quote(opening)},${fixture.actor};`, 'enable');
    const state = await json('SELECT Habilitado,IntegracionVersion FROM dbo.ConfiguracionInventario', 'enabled');
    assert.equal(state.Habilitado, true); assert.equal(state.IntegracionVersion, 2);
    return state;
  });
  await record('I05', 'Ejemplo apertura 20 y venta 3: saldo 17', async () => {
    const sold = await sale([{ id: fixture.legacy, quantity: 3 }]);
    const state = await json(`SELECT Stock,(SELECT Cantidad FROM dbo.Kardex_Inventario WHERE ProductoId=${fixture.legacy} AND TipoMovimiento='APERTURA') Apertura,(SELECT StockAnterior FROM dbo.Kardex_Inventario WHERE ProductoId=${fixture.legacy} AND TipoMovimiento='VENTA') Anterior FROM dbo.Producto WHERE ProductoId=${fixture.legacy}`, 'example');
    assert.equal(state.Stock, 17); assert.equal(state.Apertura, 20); assert.equal(state.Anterior, 20); assert.equal(sold.Movimientos, 1);
    return state;
  });
  const moneyCases = [
    ['M01', 'Adaptador sin descuento', fixture.actor, 0, ['71.80', '0.00', '71.80', '8.62', '80.42'], true],
    ['M02', 'Cajero descuento maximo 10%', fixture.cashier, 10, ['71.80', '7.18', '64.62', '7.75', '72.37']],
    ['M03', 'Administrador descuento 25%', fixture.actor, 25, ['71.80', '17.95', '53.85', '6.46', '60.31']],
    ['M04', 'Administrador descuento maximo 100%', fixture.actor, 100, ['71.80', '71.80', '0.00', '0.00', '0.00']],
  ];
  for (const [id, title, actor, discount, expected, adapter] of moneyCases) await record(id, title, async () => {
    const p = await product(); const sold = await sale([{ id: p.id, quantity: 2, discount }], actor, adapter);
    assert.deepEqual([sold.Subtotal, sold.Descuento, sold.Neto, sold.IVA, sold.Total], expected);
    assert.equal(sold.Caja, expected[4]); assert.equal(sold.Movimientos, 1);
    const state = await json(`SELECT Stock FROM dbo.Producto WHERE ProductoId=${p.id}`, 'money-stock'); assert.equal(state.Stock, 8);
    return sold;
  });
  await record('M05', 'Cajero no puede exceder 10%', async () => rejectedSale([{ id: (await product()).id, discount: 10.01 }], 52012, fixture.cashier));
  await record('M06', 'Descuento fuera de 0..100 rechazado', async () => rejectedSale([{ id: (await product()).id, discount: 100.01 }], 52011));
  await record('M07', 'IVA global y redondeo por linea con varios productos', async () => {
    const first = await product(); const second = await product(10, '10.25');
    const sold = await sale([{ id: first.id, quantity: 2, discount: 25 }, { id: second.id, quantity: 3, discount: 10 }]);
    assert.deepEqual([sold.Subtotal, sold.Descuento, sold.Neto, sold.IVA, sold.Total, sold.Caja], ['102.55', '21.03', '81.52', '9.78', '91.30', '91.30']);
    assert.equal(sold.Movimientos, 2); return sold;
  });
  await record('I06', 'Contrato Node: exactamente dos recordsets y moneda como string', async () => {
    const p = await product();
    const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(__dirname, 'ReadKardexSaleContract.ps1'), '-Server', server, '-Database', database, '-Actor', String(fixture.actor), '-Cliente', String(fixture.client), '-Producto', String(p.id)];
    if (trust) args.push('-TrustServerCertificate');
    const actual = JSON.parse((await command('powershell.exe', args, 'reader-contract')).trim());
    assert.equal(actual.sets.length, 2);
    assert.deepEqual(actual.sets[0].columns, ['FacturaId', 'FechaHora', 'Subtotal', 'Descuento', 'SubtotalNeto', 'IVA', 'Total', 'Cliente', 'NIT', 'Cajero', 'MotivoDescuento']);
    assert.deepEqual(actual.sets[1].columns, ['ProductoId', 'Descripcion', 'Cantidad', 'PrecioUnitario', 'Subtotal', 'DescuentoPorcentaje', 'DescuentoMonto', 'SubtotalNeto']);
    for (const field of ['Subtotal', 'Descuento', 'SubtotalNeto', 'IVA', 'Total']) assert.equal(actual.sets[0].types[actual.sets[0].columns.indexOf(field)], 'System.String');
    return { recordsets: actual.sets.length, moneyType: 'System.String' };
  });
  const faultCases = [
    ['B01', 'despues de factura', 'AFTER INSERT ON dbo.Factura', 54801],
    ['B02', 'despues de detalle', 'AFTER INSERT ON dbo.DetalleFactura', 54802],
    ['B03', 'despues de actualizar inventario', 'AFTER UPDATE ON dbo.Producto', 54803],
    ['B04', 'despues de insertar Kardex', 'AFTER INSERT ON dbo.Kardex_Inventario', 54804],
    ['B05', 'antes de insertar caja', 'INSTEAD OF INSERT ON dbo.MovimientoCaja', 54805],
    ['B06', 'error de auditoria', 'AFTER INSERT ON dbo.Bitacora_Transacciones', 54806],
  ];
  for (const [id, title, target, error] of faultCases) await record(id, 'Rollback completo ' + title, async () => {
    const p = await product(); const trigger = 'tr_TestKardex_' + id;
    const [timing, table] = target.split(' ON ');
    const condition = id === 'B04' ? "IF NOT EXISTS(SELECT 1 FROM inserted WHERE TipoMovimiento='VENTA') RETURN;" : id === 'B06' ? "IF NOT EXISTS(SELECT 1 FROM inserted WHERE TablaAfectada=N'Kardex_Inventario' AND JSON_VALUE(ValorNuevo,'$.TipoMovimiento')='VENTA') RETURN;" : '';
    await sql(`EXEC sys.sp_executesql ${quote(`CREATE TRIGGER dbo.${trigger} ON ${table} ${timing} AS BEGIN SET NOCOUNT ON; ${condition} THROW ${error},'Injected rollback ${id}',1; END;`)};`, 'inject-' + id);
    try { return await rejectedSale([{ id: p.id }], error); }
    finally { await sql(`DROP TRIGGER dbo.${trigger};`, 'remove-' + id); }
  });
  await record('I07', 'Movimiento idempotente no repite salida', async () => {
    const p = await product(); await sale([{ id: p.id }]);
    const k = await json(`SELECT TOP(1) OperacionId,LineaOperacion,DetalleFacturaId,DocumentoRespaldo,Motivo FROM dbo.Kardex_Inventario WHERE ProductoId=${p.id} AND TipoMovimiento='VENTA' ORDER BY KardexId DESC`, 'retry-source');
    const before = await snapshot();
    await sql(`EXEC dbo.sp_RegistrarMovimientoKardex ${p.id},'VENTA',1,${fixture.actor},${quote(k.DocumentoRespaldo)},${quote(k.OperacionId)},${k.LineaOperacion},${quote(k.Motivo)},${k.DetalleFacturaId},NULL,0;`, 'movement-retry');
    assert.deepEqual(await snapshot(), before); return { extraStockChange: 0 };
  });
  await record('I08', 'Venta completa sin clave de solicitud NO es idempotente', async () => {
    const p = await product(); const a = await sale([{ id: p.id }]); const b = await sale([{ id: p.id }]);
    assert.notEqual(a.FacturaId, b.FacturaId);
    const state = await json(`SELECT Stock FROM dbo.Producto WHERE ProductoId=${p.id}`, 'commercial-retry'); assert.equal(state.Stock, 8);
    return { first: a.FacturaId, second: b.FacturaId, limitationConfirmed: true };
  });
  await sql('CREATE TABLE dbo.PruebaKardexConcurrencia(RunId UNIQUEIDENTIFIER NOT NULL,Worker CHAR(1) NOT NULL,SessionId INT NOT NULL,FacturaId INT NULL,ErrorNumero INT NULL,Finalizado DATETIME2(3) NULL,PRIMARY KEY(RunId,Worker));', 'race-table');
  await record('C01', 'Dos conexiones simultaneas venden la ultima unidad', async () => race([(await product(1)).id], 1));
  await record('C02', 'Dos conexiones con productos en orden inverso sin deadlock', async () => race([(await product(2)).id, (await product(2)).id], 2));
  await record('I09', 'Conciliacion global de aperturas y movimientos', async () => {
    const state = await json("SELECT COUNT(*) Productos,SUM(CASE WHEN CONVERT(BIGINT,p.Stock)=COALESCE(s.Saldo,0) THEN 0 ELSE 1 END) Diferencias FROM dbo.Producto p OUTER APPLY(SELECT SUM(CASE WHEN TipoMovimiento IN('VENTA','AJUSTE_EGRESO') THEN -CONVERT(BIGINT,Cantidad) ELSE CONVERT(BIGINT,Cantidad) END) Saldo FROM dbo.Kardex_Inventario k WHERE k.ProductoId=p.ProductoId) s", 'reconciliation');
    assert.equal(state.Diferencias, 0); return state;
  });
  await record('I10', 'Reinstalar 21 con libro activo no altera saldos ni apertura', async () => {
    const before = await snapshot();
    const configuration = await json('SELECT * FROM dbo.ConfiguracionInventario', 'config-before');
    await sql(migration, 'migration21-active');
    assert.deepEqual(await snapshot(), before);
    assert.deepEqual(await json('SELECT * FROM dbo.ConfiguracionInventario', 'config-after'), configuration);
    return { stockAndLedgerUnchanged: true };
  });
  await record('I11', 'Segundo corte distinto rechazado sin cambiar el libro', async () => {
    const before = await snapshot();
    const result = evidence(await sql(`DECLARE @Error INT; BEGIN TRY EXEC dbo.sp_AbrirKardexInventario ${quote(uuid())},${fixture.actor},N'OTRO-CORTE',N'No permitido'; END TRY BEGIN CATCH SET @Error=ERROR_NUMBER(); END CATCH; SELECT N'EVIDENCE|'+(SELECT @Error Error FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);`, 'other-opening'));
    assert.equal(result.Error, 54403); assert.deepEqual(await snapshot(), before); return result;
  });
  await record('I12', 'Cuenta SQL de aplicacion no puede ejecutar apertura', async () => {
    const result = evidence(await sql(`DECLARE @Error INT; EXECUTE AS USER=N'securefinance_app'; BEGIN TRY EXEC dbo.sp_AbrirKardexInventario ${quote(opening)},${fixture.actor},N'CORTE-TEST',N'Apertura sintetica'; END TRY BEGIN CATCH SET @Error=ERROR_NUMBER(); IF XACT_STATE()<>0 ROLLBACK TRANSACTION; END CATCH; REVERT; SELECT N'EVIDENCE|'+(SELECT @Error Error FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);`, 'opening-denied'));
    assert.equal(result.Error, 229); return result;
  });
  await record('I13', 'Venta no confirma una transaccion exterior', async () => {
    const p = await product(); const before = await snapshot();
    const result = evidence(await sql(`SET NOCOUNT ON; ${detail([{ id: p.id }])} DECLARE @F INT,@Cuenta INT;
BEGIN TRANSACTION;
EXEC dbo.sp_ProcesarVentaTransaccional ${fixture.client},${fixture.actor},@D,@F OUTPUT;
SET @Cuenta=@@TRANCOUNT;
ROLLBACK TRANSACTION;
SELECT N'EVIDENCE|'+(SELECT @Cuenta TransaccionesAntesRollback,(SELECT COUNT(*) FROM dbo.Factura WHERE FacturaId=@F) FacturasPersistentes FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);`, 'outer-transaction'));
    assert.equal(result.TransaccionesAntesRollback, 1); assert.equal(result.FacturasPersistentes, 0);
    assert.deepEqual(await snapshot(), before); return result;
  });
  await record('I14', 'Factura anterior al corte no vuelve a descontar stock', async () => {
    const before = await snapshot();
    const result = evidence(await sql(`DECLARE @Error INT; BEGIN TRY EXEC dbo.sp_RegistrarMovimientoKardex ${fixture.legacy},'VENTA',1,${fixture.actor},N'FACTURA-ANTERIOR',${quote(uuid())},1,N'No duplicar historico',${fixture.historicalDetail},NULL,0; END TRY BEGIN CATCH SET @Error=ERROR_NUMBER(); END CATCH; SELECT N'EVIDENCE|'+(SELECT @Error Error FOR JSON PATH,WITHOUT_ARRAY_WRAPPER);`, 'historical-sale-denied'));
    assert.equal(result.Error, 54409); assert.deepEqual(await snapshot(), before); return result;
  });
  report.summary = { pass: results.filter(row => row.result === 'PASS').length, fail: results.filter(row => row.result === 'FAIL').length };
  await fs.writeFile(reportPath, JSON.stringify(report, null, 2) + '\n');
  console.log('PASS SQL INTEGRATION: ' + JSON.stringify({ database, ...report.summary, logs: directory }));
}

main().catch(async error => {
  report.error = error.message;
  if (!results.some(row => row.result === 'FAIL')) results.push({ id: 'RUNNER', description: 'Ejecucion interrumpida', result: 'FAIL', error: error.message });
  report.summary = { pass: results.filter(row => row.result === 'PASS').length, fail: results.filter(row => row.result === 'FAIL').length };
  await fs.writeFile(reportPath, JSON.stringify(report, null, 2) + '\n').catch(() => {});
  console.error(error.stack); process.exitCode = 1;
});
