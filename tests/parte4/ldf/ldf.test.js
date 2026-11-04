'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { randomUUID } = require('node:crypto');
const { createApp } = require('../../../server');
const { createLdfService, snapshot, operation } = require('../../../src/modules/dba/ldf/service');
const { diagnose } = require('../../../src/modules/dba/ldf/diagnostics');
const { settings, verifyTarget } = require('../../../src/modules/dba/ldf/pools');
const { validateOptions } = require('../../../scripts/parte4/ldf/install.cjs');
const perms = ['DBA_LDF_CONSULTAR', 'DBA_LDF_RESPALDAR_LOG'];
function sets() {
  return [[{ DatabaseName: 'LDF_TEST', ServerVersion: '17', SampledAtUTC: new Date(), RecoveryModel: 'FULL', DatabaseState: 'ONLINE', ReuseWait: 'LOG_BACKUP', IsReadOnly: false,
    ChainReady: true, LogicalMB: 100, PhysicalMB: 101, UsedMB: 72, FreeMB: 28, UsedPercent: 72, WarningPercent: 70, CriticalPercent: 85, BackupDirectory: 'C:\\sql\\<script>bad</script>' }],
  [{ FileId: 2, LogicalName: 'log', PhysicalPath: 'C:\\sql\\test.ldf', SizeMB: 101, Growth: 8192, PercentGrowth: false, MaxSizePages: -1, FileState: 'ONLINE' }],
  [{ Total: 3, Active: 1, Inactive: 2, MinMB: 1, MaxMB: 64, AverageMB: 33.33, InactiveMB: 36 }],
  [{ FileId: 2, OffsetBytes: '8192', SizeMB: 64, Active: true, Status: 2, SequenceNumber: '9007199254740993' }],
  [{ SizeBand: '64-512 MB', Total: 1, Active: 1, TotalMB: 64 }], [], []];
}
async function fixture(t, permissions = perms, options = {}) {
  const calls = [], controls = { readError: null, backupError: null, result: null };
  const service = { async read(actor) { calls.push(['read', actor]); if (controls.readError) throw controls.readError; return snapshot({ recordsets: sets() }); },
    async backup(actor, id) { calls.push(['backup', actor, id]); if (controls.backupError) throw controls.backupError;
      return controls.result || { OperacionId: id, ActorUsuarioId: actor, Estado: 'CONFIRMADO', BackupSetId: 20, Archivo: 'LDF.trn', FinUTC: new Date() }; } };
  const app = createApp({ secret: 'isolated-ldf-http-tests-session-secret-32', production: false, ldfService: service,
    authService: { login: async () => ({ codigo: 0, usuario: { usuarioId: 7, nombreUsuario: 'Dylan', permisos: permissions, debeCambiarPassword: false } }) }, ...options });
  const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = 'http://127.0.0.1:' + server.address().port;
  const login = await fetch(base + '/login', { method: 'POST', redirect: 'manual', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: 'NombreUsuario=Dylan&Password=fixture' });
  const cookie = login.headers.get('set-cookie').split(';')[0];
  const request = (url, config = {}) => fetch(base + url, { redirect: 'manual', ...config, headers: { Cookie: cookie, ...config.headers } });
  const html = await (await request('/dba/ldf')).text(), csrf = html.match(/name="csrf-token" content="([a-f0-9]+)"/)?.[1];
  const post = (body, token = csrf) => request('/dba/ldf/backup', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token || '' }, body: JSON.stringify(body) });
  return { calls, controls, base, request, post, html, csrf };
}
test('LDF HTTP: sessions, RBAC on HTML/JSON/POST; no paths or queries for unauthorized users', async t => {
  const f = await fixture(t, []);
  assert.equal((await fetch(f.base + '/dba/ldf', { redirect: 'manual' })).status, 302);
  for (const path of ['/dba/ldf', '/dba/ldf/metrics']) assert.equal((await f.request(path)).status, 403);
  assert.equal((await f.post({ OperacionId: randomUUID() })).status, 403);
  assert.equal(f.calls.length, 0); assert.doesNotMatch(f.html, /sql|ldf-backup-form|C:\\/);
});
test('LDF HTTP: readonly user can see metrics, never trigger backup', async t => {
  const f = await fixture(t, [perms[0]]);
  assert.match(f.html, /Virtual Log Files/); assert.doesNotMatch(f.html, /id="ldf-backup-form"/);
  assert.equal((await f.post({ OperacionId: randomUUID() })).status, 403);
  assert.equal((await f.request('/dba/ldf/metrics')).headers.get('cache-control'), 'no-store');
});
test('LDF EJS escapes SQL metadata, preserves exact LSN and renders all required sections', async t => {
  const f = await fixture(t);
  assert.match(f.html, /&lt;script&gt;bad&lt;\/script&gt;/); assert.doesNotMatch(f.html, /<script>bad/);
  for (const text of ['9007199254740993','log-history','LOG_BACKUP','Espacio ocupado','Disponible lógico','Cadena LOG inicializada','Respaldar LOG ahora']) assert(f.html.includes(text), text);
  for (const file of ['/css/dba-ldf.css','/js/dba-ldf.js']) assert.equal((await f.request(file)).status, 200);
});
test('LDF CSRF and strict input contract prevent arbitrary SQL, destination, path, actor override', async t => {
  const f = await fixture(t), id = randomUUID();
  for (const token of ['', 'bad', 'a'.repeat(64)]) assert.equal((await f.post({ OperacionId: id }, token)).status, 403);
  for (const body of [{}, { OperacionId: ['x'] }, { OperacionId: "';BACKUP DATABASE master--" }, { OperacionId: id, Database: 'master' }, { OperacionId: id, Path: 'C:\\x' }, { OperacionId: id, ActorUsuarioId: 99 }]) assert.equal((await f.post(body)).status, 400);
  assert(!f.calls.some(c => c[0] === 'backup'));
  for (let i=0;i<2;i++) assert.equal((await f.post({ OperacionId: id })).status, 200);
  assert.deepEqual(f.calls.filter(c => c[0] === 'backup'), [['backup',7,id],['backup',7,id]]);
});
test('LDF errors do not fake metrics, leak engine details, or claim uncertain backups succeeded', async t => {
  const f = await fixture(t);
  f.controls.readError = Error('secret=123; C:\\private\\other-db.ldf');
  const response = await f.request('/dba/ldf'); assert.equal(response.status,503);
  const html = await response.text(); assert.match(html,/No se obtuvieron métricas/); assert.doesNotMatch(html,/private|secret=|ldf-percent/);
  for (const [number,status] of [[54101,403],[59013,409],[229,403],[59010,503]]) {
    f.controls.backupError = { number, message: 'private details' };
    const r = await f.post({ OperacionId: randomUUID() }); assert.equal(r.status,status); assert.doesNotMatch(await r.text(),/private details/);
  }
  f.controls.backupError = null; f.controls.result = { Estado:'INCIERTO', Mensaje:'Revisar historial' };
  assert.equal((await f.post({ OperacionId: randomUUID() })).status,202);
});
test('LDF diagnosis thresholds include exact boundaries and unknown waits are explicit', () => {
  const base=sets(), s=base[0][0];
  for (const [usage,state] of [[0,'healthy'],[69.999,'healthy'],[70,'warning'],[84.999,'warning'],[85,'critical'],[100,'critical']]) assert.equal(diagnose({...s,UsedPercent:usage},base[1],base[2][0]).severity,state);
  assert.match(diagnose({...s,ReuseWait:'ACTIVE_TRANSACTION'},base[1],base[2][0]).recommendation,/transacción más antigua/);
  assert.match(diagnose({...s,ReuseWait:'REPLICATION'},base[1],base[2][0]).recommendation,/replicación/);
  assert.match(diagnose({...s,ReuseWait:'UNRECOGNIZED'},base[1],base[2][0]).recommendation,/documentación/);
  assert.match(diagnose({...s,RecoveryModel:'SIMPLE',ChainReady:false},base[1],base[2][0]).alerts[0].text,/no admite/);
  // No universal VLF threshold: 2,000 segments alone must not produce a "critical VLF" alarm.
  assert.equal(diagnose({...s,UsedPercent:1},base[1],{...base[2][0],Total:2000}).severity,'healthy');
});
test('LDF missing values or truncated resultsets cannot masquerade as zero usage', () => {
  const ok=sets(); assert.equal(snapshot({recordsets:ok}).summary.PhysicalMB,101);
  for (const value of [null,undefined,NaN,-1]) { const bad=sets();bad[0][0].UsedMB=value;assert.throws(()=>snapshot({recordsets:bad})); }
  assert.throws(()=>snapshot({recordsets:ok.slice(0,6)}));
  const bad=sets();bad[2][0].Total=10;assert.throws(()=>snapshot({recordsets:bad}));
});
test('LDF SQL service has separate pools, typed RPC parameters and validates backup confirmation', async () => {
  const calls=[], id=randomUUID();
  const provider=kind=>async()=>({ request(){ const params=[];return {input(...args){params.push(args);return this;},async execute(proc){calls.push({kind,proc,params});return kind==='app'?{recordsets:sets()}:{recordset:[{OperacionId:id,ActorUsuarioId:8,Estado:'CONFIRMADO',Archivo:'x.trn',BackupSetId:1,FinUTC:new Date()}]};}}; } });
  const svc=createLdfService({application:provider('app'),administrative:provider('admin')});
  await svc.read(8);await svc.backup(8,id);
  assert.deepEqual(calls.map(c=>[c.kind,c.proc]),[['app','dbo.P4_LDF_Consultar'],['admin','dbo.P4_LDF_RespaldarLog']]);
  assert.equal(calls[1].params[1][1].name,'UniqueIdentifier');
  await assert.rejects(()=>svc.backup(8,randomUUID()),/incompatible/);
});
test('LDF target cannot be selected by browser; wrong SQL identity aborts before operations', async () => {
  assert.throws(()=>settings({DB_NAME:'real',LDF_DATABASE:'master',LDF_EXPECTED_SERVER:'local'}));
  const pool={request:()=>({query:async()=>({recordset:[{DatabaseName:'other',ServerName:'local'}]})})};
  await assert.rejects(()=>verifyTarget(pool,{database:'lab',server:'local'}),/no autorizada/);
  const valid={authorized:true,database:'lab',expectedServer:'local',adminLogin:'worker',backupDirectory:'C:\\sql',warning:70,critical:85};
  assert.equal(validateOptions(valid).backupDirectory,'C:\\sql\\');
  for (const diff of [{database:'master'},{authorized:false},{warning:85,critical:70},{backupDirectory:'C:\\sql\\..\\secret'},{backupDirectory:'\\\\remote\\share'}]) assert.throws(()=>validateOptions({...valid,...diff}));
  assert.equal(operation({OperacionId:randomUUID()}).length,36);
});
test('LDF isolated lab cookie is cleared on logout without clearing the original app cookie', async t => {
  const f=await fixture(t,perms,{sessionName:'securefinance.ldf.sid'});
  const response=await f.request('/logout');assert.match(response.headers.get('set-cookie'),/^securefinance\.ldf\.sid=;/);
  assert.equal((await f.request('/dba/ldf')).status,302);
});
