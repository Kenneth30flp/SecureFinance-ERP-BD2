'use strict';
// Source contract checks, NOT SQL compilation, execution or proof of business invariants.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { migrationPlan, applyReviewedPlan } = require('../scripts/creditosMigrationPlan');
const file = name => fs.readFileSync(path.join(__dirname, '../database', name), 'utf8').replace(/\r\n/g,'\n');
const compact = source => source.replace(/\s+/g, '');
test('CRE source contract: all 70-78 files are lab guarded and external transaction required', () => {
  const plan = migrationPlan(); assert.equal(new Set(plan.map(b => b.file)).size, 9);
  for (const name of new Set(plan.map(b => b.file))) {
    const source = file(name);
    assert.match(source, /DB_NAME\(\)[^;]*<> (?:dbo\.P3_INT_Destino\(\)|N'SecureFinanceERP_Lab_Dylan')/);
    assert.doesNotMatch(source, /^\s*USE\s/mi);
  }
  for (const name of ['70_P3_CRE_Estructura.sql','71_P3_CRE_Perfiles.sql','72_P3_CRE_Financiacion.sql','73_P3_CRE_Abonos.sql','74_P3_CRE_Consultas.sql','75_P3_CRE_Seguridad.sql','76_P3_CRE_Ventas_PROPUESTA.sql','77_P3_CRE_ConversionPublica.sql','78_P3_CRE_Verificacion.sql'])
    assert.match(file(name), /@@TRANCOUNT=0/, name + ' exige transaccion externa.');
  assert.match(file('78_P3_CRE_AjustesConsultas.sql'), /@@TRANCOUNT<>1 OR XACT_STATE\(\)<>1/);
  assert.match(file('79_P3_CRE_PruebasSinteticas.sql'), /DB_NAME\(\) <> N'SecureFinanceERP_Lab_Dylan' OR @@TRANCOUNT<>0/);
});
test('CRE source contract: exact academic tables, immutable abono/receipt, no old cash repair', () => {
  const structure = file('70_P3_CRE_Estructura.sql'), payment = file('73_P3_CRE_Abonos.sql'), security = file('75_P3_CRE_Seguridad.sql');
  assert.match(structure, /CREATE TABLE dbo\.Credito_Cliente\(/); assert.match(structure, /CREATE TABLE dbo\.Abono_Factura\(/);
  assert.match(structure, /P3_CRE_UQ_ReciboAbono UNIQUE/); assert.match(structure, /P3_CRE_UQ_AbonoOperacion UNIQUE/);
  assert.match(payment, /CREATE OR ALTER PROCEDURE dbo\.sp_RegistrarAbonoCliente/);
  assert.match(payment, /sp_getapplock/); assert.match(payment, /@Prev<>@Hash/); assert.match(security, /INSTEAD OF UPDATE,DELETE/);
  for (const b of migrationPlan()) assert.doesNotMatch(b.sql, /(?:DELETE\s+(?:FROM\s+)?|UPDATE\s+)dbo\.MovimientoCaja/i);
});
test('CRE source contract: credit locked before invoice, FIFO and date-derived states', () => {
  const payment = file('73_P3_CRE_Abonos.sql'), helper = file('72_P3_CRE_Financiacion.sql'), views = file('74_P3_CRE_Consultas.sql');
  assert(payment.indexOf('dbo.Credito_Cliente WITH(UPDLOCK,HOLDLOCK)') < payment.indexOf('dbo.Factura WITH(UPDLOCK,HOLDLOCK)'));
  assert.match(payment, /ORDER BY VenceEn,Numero/); assert.match(payment, /@Monto>@Saldo/);
  assert.match(helper, /@Deuda DECIMAL\(38,2\)/); assert.match(helper, /@Total>@Limite-CONVERT\(DECIMAL\(19,2\),@Deuda\)/);
  assert(helper.indexOf('IF @Deuda>@Limite') < helper.indexOf('@Total>@Limite-CONVERT'));
  assert.match(views, /VenceEn<=SYSUTCDATETIME\(\)/); assert.doesNotMatch(file('70_P3_CRE_Estructura.sql'), /Estado VARCHAR/);
});
test('CRE source contract: original cash hashes are unchanged, credit hash adds financing and warehouse', () => {
  const old = file('43_P3_COT_ConversionFactura.sql'), proposed = file('76_P3_CRE_Ventas_PROPUESTA.sql');
  const hashes = old.match(/SET @Hash=HASHBYTES\('SHA2_256',CONCAT\([^;]+;/g);
  assert.equal(hashes.length, 2);
  for (const expression of hashes) assert(compact(proposed).includes(compact(expression)));
  assert.match(proposed, /IF @P3Credito=1/); assert.match(proposed, /P3CRE:v1/); assert.match(proposed, /@P3PlazoDias,N'\|',@P3NumeroCuotas/);
  assert.match(proposed, /SESSION_CONTEXT\(N'P3_BOD.BodegaId'\)/); assert.match(proposed, /INTEGRATED:/);
});
test('CRE source contract: one engine, frozen SQL quote prices, no TVP or global stock mutation', () => {
  const proposed = file('76_P3_CRE_Ventas_PROPUESTA.sql');
  assert.equal((proposed.match(/CREATE OR ALTER PROCEDURE dbo\.sp_/g) || []).length, 3);
  assert.match(proposed, /SELECT @Precio=PrecioUnitario FROM dbo\.P3_COT_Detalle/);
  assert.match(proposed, /EXEC dbo\.sp_RegistrarMovimientoKardex/);
  assert.match(proposed, /IF @P3Credito=0 INSERT dbo\.MovimientoCaja/);
  assert(compact(proposed).indexOf('@P3NumeroCuotas,@Total;') < compact(proposed).indexOf('INSERTdbo.Factura('));
  assert.doesNotMatch(proposed, /(?:ALTER|CREATE) TYPE|UPDATE dbo\.Producto/i);
  const originalExpressions = ['SET @Bruto = @Precio * CONVERT(DECIMAL(10,0), @Cantidad);',
    'SET @MontoDescuento = ROUND(@Bruto * @Porcentaje / CONVERT(DECIMAL(5,2), 100), 2);',
    'SET @IVA = ROUND(@SubtotalNeto * CONVERT(DECIMAL(3,2), 0.12), 2);'];
  for (const e of originalExpressions) assert(compact(proposed).includes(compact(e)));
});
test('CRE source contract: reject foreign BOD context outside TRY/transaction; clean only owned context', () => {
  const source = file('77_P3_CRE_ConversionPublica.sql');
  assert.match(source, /@ActorUsuarioId INT,@CotizacionId INT,@OperacionId UNIQUEIDENTIFIER,@PlazoDias INT,@NumeroCuotas INT=1,@BodegaId INT=NULL/);
  assert.match(source, /IF ERROR_NUMBER\(\)=2812 THROW 57008/);
  assert.doesNotMatch(source, /OBJECT_ID\('dbo.P3_BOD_ValidarBodegaVenta'/);
  assert.match(source, /EXEC dbo.P3_BOD_ValidarBodegaVenta @ActorUsuarioId=@ActorUsuarioId,@BodegaId=@BodegaId/);
  assert.equal((source.match(/IF @ContextoPropio=1 EXEC sys.sp_set_session_context @key=N'P3_BOD.BodegaId',@value=NULL/g) || []).length, 2);
  assert(source.indexOf("IF SESSION_CONTEXT(N'P3_BOD.BodegaId') IS NOT NULL") < source.indexOf('BEGIN TRY'));
  assert(source.indexOf('THROW 57009') < source.indexOf('BEGIN TRANSACTION'));
  assert.doesNotMatch(source.slice(0, source.indexOf('BEGIN TRY')), /sp_set_session_context/);
  assert(source.indexOf('SET @ContextoPropio=1') > source.indexOf('@value=@BodegaId'));
  assert(source.indexOf('BEGIN TRANSACTION') < source.indexOf("@value=@BodegaId"));
});
function procedure(source, name) {
  const block = source.split(/^GO\s*$/im).find(b => new RegExp('CREATE OR ALTER PROCEDURE dbo\\.' + name + '\\s').test(b));
  assert(block, name); return block.slice(block.indexOf('CREATE OR ALTER PROCEDURE'));
}
function tokens(source) {
  return (source.match(/--[^\r\n]*|\/\*[\s\S]*?\*\/|N?'(?:''|[^'])*'|@?[a-z_]\w*|\d+(?:\.\d+)?|<>|<=|>=|[^\s]/gi) || [])
    .filter(t => !t.startsWith('--') && !t.startsWith('/*') && t !== ';' && t.toUpperCase() !== 'AS')
    .map(t => /^(?:N)?'/.test(t) ? t : t.toUpperCase());
}
for (const name of ['sp_ConvertirCotizacionAFactura']) {
  test('CRE 76 default source projection equals all 43 tokens: ' + name, () => {
    const old = procedure(file('43_P3_COT_ConversionFactura.sql'), name);
    let cash = procedure(file('76_P3_CRE_Ventas_PROPUESTA.sql'), name);
    // Project ONLY the declared default @P3Credito=0, stripping its explicit extension sites.
    cash = cash.replace(/,\s*@P3Credito BIT=0,@P3PlazoDias INT=NULL,@P3NumeroCuotas INT=1/g, '')
      .replace(/,\s*@P3Credito=@P3Credito,@P3PlazoDias=@P3PlazoDias,@P3NumeroCuotas=@P3NumeroCuotas/g, '')
      .replace(/IF @P3Credito IS NULL THROW 57002,'Modalidad invalida\.',1;/g, '')
      .replace(/IF @P3Credito=1\s+EXEC dbo\.P3_CRE_ValidarFinanciacion[^;]+;/g, '')
      .replace(/IF @P3Credito=0 (INSERT dbo\.MovimientoCaja[^;]+;)\s*ELSE EXEC dbo\.P3_CRE_CrearCuenta[^;]+;/g, '$1');
    const start = cash.indexOf('  IF @P3Credito=1\n  BEGIN');
    if (start !== -1) {
      const end = cash.indexOf('  EXEC @Lock=sys.sp_getapplock', start); assert(end > start);
      cash = cash.slice(0, start) + cash.slice(end);
    }
    cash = cash.replace(/DECLARE @ConversionMotivo NVARCHAR\(250\)=CASE[^;]+;/g, '')
      .replace(/@ConversionMotivo/g, "N'Conversion a factura de contado'");
    assert.deepEqual(tokens(cash), tokens(old));
  });
}
test('CRE caja source: union of actual receipts and cash only; wide SUM, scoped permission and typed strings', () => {
  const source = procedure(file('74_P3_CRE_Consultas.sql'), 'P3_CRE_ConsultarCaja');
  assert.match(source, /N'CREDITOS_CONSULTAR'/); assert.match(source, /UNION ALL/);
  assert.match(source, /FROM dbo.MovimientoCaja m/); assert.match(source, /FROM dbo.P3_CRE_ReciboCaja r JOIN dbo.Abono_Factura/);
  assert.doesNotMatch(source, /FROM dbo.Factura\b|SUM\(Total\)|FLOAT|MONEY\b/);
  assert.match(source, /CONVERT\(VARCHAR\(40\),COALESCE\(SUM\(Monto\),0\)\) EfectivoTotal/);
  assert.match(source, /r.FechaHora<@Hasta/); assert.match(source, /m.FechaHora<@Hasta/);
  assert.match(file('75_P3_CRE_Seguridad.sql'), /GRANT EXECUTE ON dbo.P3_CRE_ConsultarCaja TO securefinance_app/);
});
test('CRE 79 source: synthetic client/product but actual quote creation and converter, no invoice injection', () => {
  const source = file('79_P3_CRE_PruebasSinteticas.sql');
  assert.match(source, /EXEC dbo.P3_COT_Crear/); assert.match(source, /EXEC dbo.P3_CRE_ConvertirCotizacionCredito/);
  assert.doesNotMatch(source, /INSERT\s+(?:INTO\s+)?dbo\.(?:Factura|DetalleFactura|P3_CRE_Cuenta)\b/i);
  assert.match(source, /Subtotal=1785.71 AND IVA=214.29 AND Total=2000/);
  assert.match(source, /@Scenario<=24/); assert.match(source, /@Scenario=15/); assert.match(source, /@Scenario=16/);
  assert.match(source, /@Scenario=17/); assert.match(source, /@Scenario=21/); assert.match(source, /@ContextoPrueba=1/);
  assert.match(source, /@Scenario=22/); assert.match(source, /@Scenario=23/); assert.match(source, /@Scenario=24/);
  assert.match(source, /Credito de esta venta|Efectivo de esta venta/);
});
test('CRE migration runner: no approval means no SQL or connections', async () => {
  let requests = 0;
  await assert.rejects(() => applyReviewedPlan({ request() { requests++; } }), /Kenneth review/);
  assert.equal(requests, 0);
});
test('CRE migration runner: principal DB rejected before first DDL and external transaction rolled back', async () => {
  let batches = 0, rolledBack = 0;
  await assert.rejects(() => applyReviewedPlan({ request: () => ({
    query: async () => ({ recordset: [{ DatabaseName: 'SecureFinanceERP', TranCount: 1, XactState: 1 }] }),
    batch: async () => { batches++; },
  }), rollback: async () => { rolledBack++; } }, { kennethReviewApproved: true }), /Explicitly authorized/);
  assert.equal(batches, 0); assert.equal(rolledBack, 1);
});
test('CRE migration runner: every GO checked, first error aborts remaining batches', async () => {
  let guards = 0, batches = 0, rolledBack = 0;
  await assert.rejects(() => applyReviewedPlan({ request: () => ({
    query: async () => { guards++; return { recordset: [{ DatabaseName: 'SecureFinanceERP_P3_PRO_20261029000000_abcdef12', AuthorizedName: 'SecureFinanceERP_P3_PRO_20261029000000_abcdef12', TranCount: 1, XactState: 1 }] }; },
    batch: async () => { if (++batches === 3) throw new Error('synthetic DDL failure'); },
  }), rollback: async () => { rolledBack++; } }, { kennethReviewApproved: true }), /synthetic DDL failure/);
  assert.equal(guards, 3); assert.equal(batches, 3); assert.equal(rolledBack, 1);
});
test('CRE migration runner: complete mocked plan leaves commit decision to caller', async () => {
  let batches = 0, guards = 0;
  await applyReviewedPlan({ request: () => ({
    query: async () => { guards++; return { recordset: [{ DatabaseName: 'SecureFinanceERP_P3_PRO_20261029000000_abcdef12', AuthorizedName: 'SecureFinanceERP_P3_PRO_20261029000000_abcdef12', TranCount: 1, XactState: 1 }] }; },
    batch: async () => { batches++; },
  }), rollback: async () => assert.fail('Unexpected rollback'), commit: async () => assert.fail('Must not auto commit') }, { kennethReviewApproved: true });
  assert.equal(batches, migrationPlan().length); assert.equal(guards, batches);
});
test('CRE migration runner: lost or uncommittable transaction aborts at GO boundary', async () => {
  for (const [TranCount, XactState] of [[0, 0], [1, -1], [2, 1]]) {
    let batches = 0;
    await assert.rejects(() => applyReviewedPlan({ request: () => ({ query: async () => ({ recordset: [{ DatabaseName: 'SecureFinanceERP_P3_PRO_20261029000000_abcdef12', AuthorizedName: 'SecureFinanceERP_P3_PRO_20261029000000_abcdef12', TranCount, XactState }] }),
      batch: async () => { batches++; } }), rollback: async () => {} }, { kennethReviewApproved: true }));
    assert.equal(batches, 0);
  }
});

test('Integrated 76 preserves promotion parameter positions and cash/credit/warehouse fingerprints',()=>{
 const s=file('76_P3_CRE_Ventas_PROPUESTA.sql');
 for(const n of ['sp_ProcesarVentaTransaccional','sp_ERP_ProcesarVenta']) {
 const p=procedure(s,n);assert(p.indexOf('@P3AplicarPromociones BIT')<p.indexOf('@P3Credito BIT'));
 assert.match(p,/IF @P3CotizacionId IS NOT NULL AND @P3AplicarPromociones\s*=\s*1/);
 assert.match(p,/P3_PRO_AplicacionesDeFactura/);
 }
 assert.match(s,/P3PRO:v1/);assert.match(s,/P3CRE:v1/);assert.match(s,/P3BOD:v1/);
 assert.match(s,/ELSE EXEC dbo.P3_CRE_CrearCuenta/);
});
