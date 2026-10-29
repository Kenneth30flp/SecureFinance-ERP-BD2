'use strict';
// Test-only fixture. No server.js, dotenv, credentials or production authentication.
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
if (!process.argv.includes('--worker')) {
  const child = spawnSync(process.execPath, [__filename, '--worker'], { stdio: 'inherit',
    env: { ...process.env, NODE_PATH: path.join(root, 'node_modules') } });
  process.exit(child.status ?? 1);
}
const fs = require('node:fs');
const { once } = require('node:events');
const readline = require('node:readline');
const assert = require('node:assert/strict');
const sql = require('mssql');
const express = require('express');
const credit = path.resolve(root, '..', 'SecureFinance-ERP-BD2-creditos');
const warehouse = path.resolve(root, '..', 'SecureFinance-ERP-BD2-multibodega');
const { createAuditoriaDdlService } = require('../src/services/auditoriaDdlService');
const { createAuditoriaDdlRoutes } = require('../src/routes/auditoriaDdlRoutes');
const { createCreditoService } = require(path.join(credit, 'src/modules/creditos/service'));
const { createCreditoRoutes } = require(path.join(credit, 'src/modules/creditos/routes'));
const { createMultibodegaService } = require(path.join(warehouse, 'src/modules/multibodega/service'));
const { createMultibodegaRoutes } = require(path.join(warehouse, 'src/modules/multibodega/routes'));
const evidence = path.join(root, 'docs', 'dylan-readonly-qa-20261028');
const results = { authentication: 'SESSION_FIXTURE_NOT_REAL_LOGIN', realSqlServices: true,
  database: 'SecureFinanceERP_Lab_Dylan', checks: [], screenshots: [], rpc: [] };
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
function check(name, condition, details = {}) {
  results.checks.push({ name, pass: !!condition, ...details });
  console.log(`${condition ? 'PASS' : 'FAIL'} ${name}`);
}
async function main() {
  assert.ok(fs.statSync(path.dirname(evidence)).isDirectory());
  fs.mkdirSync(evidence, { recursive: true });
  const bridge = spawn('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-File', path.join(__dirname, 'dylanReadonlyRpc.ps1')], { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
  const pending = new Map(); let seq = 0, server, browser, socket, profile;
  bridge.stderr.on('data', () => {}); // Never relay driver payloads or SQL messages.
  readline.createInterface({ input: bridge.stdout }).on('line', line => {
    try { const reply = JSON.parse(line), p = pending.get(reply.id); if (!p) return;
      pending.delete(reply.id); clearTimeout(p.timer);
      reply.ok ? p.resolve(reply.result) : p.reject(Object.assign(new Error('Readonly RPC rejected'), { number: reply.error.number }));
    } catch { /* Non-protocol output cannot enter an HTTP response. */ }
  });
  const rpc = payload => new Promise((resolve, reject) => {
    const id = ++seq, timer = setTimeout(() => { pending.delete(id); reject(new Error('RPC timeout')); }, 35000);
    pending.set(id, { resolve, reject, timer }); bridge.stdin.write(JSON.stringify({ id, ...payload }) + '\n');
  });
  const provider = async () => ({ request() {
    const params = [];
    return { input(name, type, value) {
      const fn = type.type || type;
      const typeName = ['Int','BigInt','NVarChar','VarChar','DateTime2','DateTime','Date','Binary','VarBinary','Bit','UniqueIdentifier','Decimal'].find(k => sql[k] === fn);
      assert.ok(typeName, 'Supported scalar type');
      params.push({ name, type: typeName, length: type.length, value: Buffer.isBuffer(value) ? value.toString('base64') : value ?? null }); return this;
    }, async execute(proc) {
      const r = await rpc({ op: 'execute', proc, params });
      assert.ok(r.guard && r.applicationToken);
      results.rpc.push({ procedure: proc, guard: r.guard, applicationToken: r.applicationToken, rowCounts: r.recordsets.map(s => s.length) });
      return { ...r, recordset: r.recordsets[0] || [] };
    } };
  } });
  try {
    const boot = await rpc({ op: 'bootstrap' });
    assert.ok(boot.guard && boot.recordsets[0].length === 1);
    const actor = boot.recordsets[0][0].UsuarioId;
    const permissions = boot.recordsets[1].map(p => p.Codigo);
    check('Guarded synthetic actor and actual role permissions', permissions.includes('AUDITORIA_DDL_CONSULTAR') && permissions.includes('CREDITOS_CONSULTAR') && permissions.includes('BODEGAS_CONSULTAR'));
    const ddl = createAuditoriaDdlService(provider), cre = createCreditoService(provider), bod = createMultibodegaService(provider);
    const session = { usuario: { usuarioId: actor, nombreUsuario: 'P3_DYLAN_QA_ADMIN', permisos: permissions, debeCambiarPassword: false } };
    const app = express(); app.disable('x-powered-by'); app.use(express.json());
    app.set('view engine', 'ejs'); app.set('views', [root, credit, warehouse].map(p => path.join(p, 'src/views')));
    const catalogs = [root, credit, warehouse].map(p => require(path.join(p, 'src/config/moduleCatalog')));
    const modules = new Map(); for (const c of catalogs) for (const m of c.modules) if (m.available) modules.set(m.id, m);
    app.locals.moduleAreas = user => catalogs[0].areas.map(area => ({ ...area, modules: [...modules.values()].filter(m => m.area === area.id && (!m.permissions.length || m.permissions.some(p => user.permisos.includes(p)))) }));
    for (const p of [root, credit, warehouse]) app.use(express.static(path.join(p, 'src/public')));
    app.use('/vendor/bootstrap', express.static(path.join(root, 'node_modules/bootstrap/dist')));
    app.use((req, res, next) => { req.session = session; next(); });
    app.use(createAuditoriaDdlRoutes(ddl)); app.use(createCreditoRoutes(cre)); app.use(createMultibodegaRoutes(bod));
    app.use((err, req, res, next) => res.status(500).json({ error: 'QA fixture rendering failed' }));
    server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
    const base = 'http://127.0.0.1:' + server.address().port;
    const request = (route, options) => fetch(base + route, { redirect: 'manual', ...options });
    const routes = ['/auditoria/ddl?objeto=__none_qa__','/creditos','/creditos/caja', ...['inventario','bodegas','transferencias','kardex','integraciones'].map(s => '/multibodega?seccion=' + s)];
    for (const route of routes) {
      const response = await request(route), html = await response.text();
      check('HTTP GET ' + route, response.status === 200 && response.headers.get('cache-control') === 'no-store' && html.includes('href="/creditos"') && html.includes('href="/multibodega"'), { status: response.status });
    }
    const filters = { pagina: 1, ClienteId: null, FacturaId: null, estado: '', Desde: null, Hasta: null };
    const credits = await cre.list(actor, filters), inventory = await bod.list(actor, 'inventario');
    const settled = credits.cuentas.filter(c => c.Estado === 'PAGADA' && Number(c.Saldo) === 0);
    check('Actual SQL settled credit invoices', settled.length > 0, { rows: credits.cuentas.length, settled: settled.length });
    const creditHtml = await (await request('/creditos')).text();
    check('HTTP renders actual SQL invoice identities', credits.cuentas.length > 0 && credits.cuentas.every(c => creditHtml.includes('FAC-' + c.FacturaId)), { rows: credits.cuentas.length });
    const transit = inventory.rows.filter(r => Number(r.Transito) > 0);
    check('Actual SQL warehouse transit reconciles', transit.length > 0 && inventory.rows.every(r => Number(r.Diferencia) === 0), { rows: inventory.rows.length, transitProducts: transit.length });
    const missing = await ddl.detail(actor, '9223372036854775807'); check('DDL missing detail real SQL', missing === null);
    // 2026-10-28 tarde: instalar 89 (complemento BOD) y el ajuste CRE en el laboratorio
    // genero eventos DDL reales capturados por la propia bitacora. El listado con datos
    // reales es mejor evidencia que exigir una tabla vacia; solo se persiste el tipo de
    // evento, nunca comandos ni identificadores DDL sensibles.
    const ddlList = await ddl.list(actor, { pagina: 1, desde: '', hasta: '', corteId: null });
    const firstDdl = ddlList.rows[0];
    const firstDetail = firstDdl ? await ddl.detail(actor, firstDdl.BitacoraDdlId) : null;
    check('DDL bitacora real data responds and detail resolves',
      ddlList.rows.length > 0
      && ddlList.rows.every(r => BigInt(r.BitacoraDdlId) > 0n)
      && BigInt(ddlList.total) >= BigInt(ddlList.rows.length)
      && !!firstDetail && firstDetail.BitacoraDdlId === firstDdl.BitacoraDdlId,
      { rows: ddlList.rows.length, total: ddlList.total, firstEvent: firstDdl.TipoEvento, detailResolved: !!firstDetail });
    try { await (await provider()).request().input('ActorUsuarioId', sql.Int, 0).execute('dbo.P3_CRE_Consultar'); check('SQL credit actor zero rejected directly', false); }
    catch (e) { check('SQL credit actor zero rejected directly', e.number === 54101, { number: e.number ?? 0 }); }
    check('Unknown warehouse operation real SQL', await bod.operation(actor, '00000000-0000-4000-8000-000000000001') === null);
    try { await rpc({ op: 'execute', proc: 'dbo.sp_RegistrarAbonoCliente', params: [] }); check('Bridge blocks mutating procedure', false); }
    catch (e) { check('Bridge blocks mutating procedure', e.number === 0); }
    const receipt = credits.abonos[0];
    if (receipt) { const response = await request('/creditos/recibos/' + receipt.AbonoId); check('Actual receipt HTTP GET', response.status === 200, { status: response.status }); }
    else check('Existing receipt available for HTTP QA', false);
    const transfers = await bod.list(actor, 'transferencias');
    if (transfers.rows.length) { const response = await request('/multibodega/transferencias/' + transfers.rows[0].TransferenciaId); check('Actual transfer detail HTTP GET', response.status === 200, { status: response.status }); }
    for (const route of ['/auditoria/ddl','/creditos','/multibodega']) {
      session.usuario.permisos = []; const response = await request(route); check('Permission denied ' + route, response.status === 403, { status: response.status });
    }
    session.usuario.permisos = permissions;
    session.usuario.usuarioId = 0;
    for (const route of ['/auditoria/ddl','/creditos','/multibodega']) {
      const response = await request(route), validatesBeforeSql = route === '/creditos';
      check((validatesBeforeSql ? 'Service validates actor zero ' : 'SQL rejects actor zero ') + route, response.status === (validatesBeforeSql ? 400 : 403), { status: response.status, reachesSql: !validatesBeforeSql });
    }
    session.usuario.usuarioId = actor;
    for (const route of ['/creditos/abonos','/multibodega/transferencias']) {
      const before = results.rpc.length, response = await request(route, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
      check('Missing CSRF denied ' + route, response.status === 403 && results.rpc.slice(before).every(r => r.procedure === 'dbo.P3_BOD_Autorizar'), { status: response.status });
    }
    // Screenshots are restricted to synthetic lab records. Never persist DDL identities/commands.
    // A label heuristic is not proof of synthetic identity. Credit screenshots use
    // verified empty filters instead of persisting uncertain client identities.
    const emptyFilters = { ...filters, ClienteId: 2147483647, FacturaId: 2147483647, Desde: new Date('2099-01-01T06:00:00Z'), Hasta: new Date('2099-01-02T06:00:00Z') };
    const emptyCredits = await cre.list(actor, emptyFilters), emptyCash = await cre.cash(actor, emptyFilters);
    const safeCredits = !emptyCredits.cuentas.length && !emptyCredits.perfil && !emptyCredits.abonos.length && !emptyCredits.cuotas.length && !emptyCredits.historial.length && !emptyCash.movimientos.length && emptyCash.resumen.EfectivoTotal === '0.00';
    const syntheticProduct = inventory.rows.find(r => r.Codigo === 'P3BOD-QA-100');
    const syntheticInventory = !!syntheticProduct;
    check('Empty credit and cash screenshot privacy gate', safeCredits);
    check('Synthetic-only warehouse screenshot gate', syntheticInventory);
    results.screenshotScope = { ddl: 'empty object filter', credit: 'verified empty future filters; populated SQL checked via HTTP only', warehouse: 'P3BOD-QA-100 synthetic product only' };
    const browserPath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
    assert.ok(fs.existsSync(browserPath), 'Installed Chrome required');
    const temp = 'C:\\Users\\ALBRYGTH\\AppData\\Local\\Temp\\opencode'; assert.ok(fs.statSync(temp).isDirectory());
    profile = fs.mkdtempSync(path.join(temp, 'dylan-readonly-qa-'));
    browser = spawn(browserPath, ['--headless=new','--no-first-run','--disable-background-networking','--disable-component-update','--remote-debugging-address=127.0.0.1','--remote-debugging-port=0','--user-data-dir=' + profile,'about:blank'], { stdio: 'ignore', windowsHide: true });
    const portFile = path.join(profile, 'DevToolsActivePort');
    for (let i = 0; i < 100 && !fs.existsSync(portFile); i++) await delay(100);
    assert.ok(fs.existsSync(portFile), 'Chrome DevToolsActivePort unavailable');
    const port = Number(fs.readFileSync(portFile, 'utf8').split(/\r?\n/)[0]);
    const pages = await (await fetch('http://127.0.0.1:' + port + '/json/list')).json();
    socket = new WebSocket(pages.find(p => p.type === 'page').webSocketDebuggerUrl); await once(socket, 'open');
    let sequence = 0; const commands = new Map(), exceptions = [], failedAssets = [];
    socket.addEventListener('message', e => { const m = JSON.parse(e.data), p = commands.get(m.id);
      if (m.method === 'Runtime.exceptionThrown') exceptions.push(true);
      if (m.method === 'Network.responseReceived' && m.params.response.status >= 400 && m.params.type !== 'Other') failedAssets.push(m.params.response.status);
      if (p) { commands.delete(m.id); clearTimeout(p.timer); m.error ? p.reject(new Error('CDP rejected')) : p.resolve(m.result); }
    });
    const cdp = (method, params = {}) => new Promise((resolve, reject) => { const id = ++sequence, timer = setTimeout(() => reject(new Error('CDP timeout')), 15000); commands.set(id, { resolve, reject, timer }); socket.send(JSON.stringify({ id, method, params })); });
    const evaluate = async expression => { const r = await cdp('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }); assert.ok(!r.exceptionDetails, 'Browser evaluation'); return r.result.value; };
    await cdp('Page.enable'); await cdp('Runtime.enable'); await cdp('Network.enable');
    // Block all non-loopback requests without weakening browser security.
    await cdp('Network.setBlockedURLs', { urls: ['https://*','http://*.com/*'] });
    const dateQuery = 'desde=2099-01-01&hasta=2099-01-01';
    const browserRoutes = [routes[0], ...(safeCredits ? ['/creditos?clienteId=2147483647&facturaId=2147483647&' + dateQuery,'/creditos/caja?' + dateQuery] : []), ...(syntheticInventory ? ['/multibodega?seccion=inventario&ProductoId=' + syntheticProduct.ProductoId] : [])];
    const contrastSamples = [];
    for (const width of [1366,1024,768,390,320]) {
      await cdp('Emulation.setDeviceMetricsOverride', { width, height: 900, deviceScaleFactor: 1, mobile: false });
      for (let i = 0; i < browserRoutes.length; i++) {
        const route = browserRoutes[i]; await cdp('Page.navigate', { url: base + route });
        let ready = false; for (let retry = 0; retry < 150; retry++) { ready = await evaluate('location.href===' + JSON.stringify(base + route) + '&&document.readyState==="complete"'); if (ready) break; await delay(100); }
        assert.ok(ready, 'Browser navigation timeout'); await delay(150);
        const dimensions = await evaluate('({width:innerWidth,scroll:document.documentElement.scrollWidth,main:!!document.querySelector("main"),styles:[...document.querySelectorAll("link[rel=stylesheet]")].every(l=>!!l.sheet)})');
        check(`Browser responsive ${width} ${route}`, dimensions.main && dimensions.styles && dimensions.scroll <= dimensions.width, dimensions);
        if (route.startsWith('/creditos')) {
          const samples = await evaluate(`(() => {
            const luminance = color => {
              const channels = color.match(/[\\d.]+/g).slice(0,3).map(Number).map(v => { v /= 255; return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; });
              return channels[0] * .2126 + channels[1] * .7152 + channels[2] * .0722;
            };
            return [...document.querySelectorAll('.cre-panel h2')].map(h => {
              const style = getComputedStyle(h), foreground = luminance(style.color), background = luminance(getComputedStyle(h.closest('.cre-panel')).backgroundColor);
              const ratio = (Math.max(foreground,background) + .05) / (Math.min(foreground,background) + .05);
              const size = parseFloat(style.fontSize), weight = parseFloat(style.fontWeight);
              return { ratio: Math.round(ratio * 100) / 100, threshold: size >= 24 || (size >= 18.66 && weight >= 700) ? 3 : 4.5 };
            });
          })()`);
          contrastSamples.push(...samples.map(s => ({ width, ...s })));
        }
        const shot = await cdp('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
        const filename = `view-${i + 1}-${width}.png`; fs.writeFileSync(path.join(evidence, filename), Buffer.from(shot.data, 'base64')); results.screenshots.push(path.relative(root, path.join(evidence, filename)));
      }
    }
    results.browser = true; check('Browser JavaScript exceptions absent', exceptions.length === 0, { count: exceptions.length });
    check('Browser assets return success', failedAssets.length === 0, { failed: failedAssets.length });
    results.creditHeadingContrast = contrastSamples;
    check('Credit panel headings meet WCAG AA contrast', contrastSamples.length > 0 && contrastSamples.every(s => s.ratio >= s.threshold), { samples: contrastSamples.length, minimumRatio: Math.min(...contrastSamples.map(s => s.ratio)) });
  } catch (e) {
    results.failure = { message: ['Readonly RPC rejected','RPC timeout'].includes(e.message) ? e.message : 'QA execution failed', number: e.number ?? null, code: e.code || null };
    check('Complete execution', false, results.failure);
  } finally {
    socket?.close();
    if (browser) { const exited = once(browser, 'exit').catch(() => {}); browser.kill(); await Promise.race([exited, delay(5000)]); }
    if (server) await new Promise(resolve => { server.close(resolve); server.closeAllConnections(); });
    bridge.stdin.end(); bridge.kill();
    for (const p of pending.values()) { clearTimeout(p.timer); p.reject(new Error('Bridge closed')); }
    if (profile) { try { fs.rmSync(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }); results.profileCleaned = true; } catch { results.profileCleaned = false; } }
    results.total = results.checks.length; results.passed = results.checks.filter(c => c.pass).length; results.failed = results.total - results.passed;
    fs.writeFileSync(path.join(evidence, 'results.json'), JSON.stringify(results, null, 2));
    console.log(JSON.stringify({ total: results.total, passed: results.passed, failed: results.failed, browser: !!results.browser, evidence: path.relative(root, evidence) }));
    if (results.failed) process.exitCode = 1;
  }
}
main().catch(() => { console.error('QA startup failed'); process.exitCode = 1; });
