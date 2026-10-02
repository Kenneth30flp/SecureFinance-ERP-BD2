'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { createApp } = require('../server');
const { createPasswordService } = require('../src/services/passwordService');

async function fixture(t, production = false) {
  const token = 'a'.repeat(64);
  const calls = [];
  let failure;
  let valid = true;
  const service = {
    solicitar: async id => { calls.push(['solicitar', id]); if (failure) throw failure; return id === 'demo' || id === 'demo@example.invalid' ? token : null; },
    validar: async value => { if (failure) throw failure; return value === token && valid; },
    restablecer: async (...args) => { if (failure) throw failure; if (!valid) throw Object.assign(new Error('private'), { number: 54001 }); calls.push(['restablecer', ...args]); valid = false; },
    cambiar: async (...args) => { if (failure) throw failure; calls.push(['cambiar', ...args]); },
  };
  const app = createApp({ dashboardService: { obtenerResumen: async () => null }, secret: 'secreto-exclusivo-password-pruebas-123456789', production,
    passwordService: service, authService: { login: async nombreUsuario => ({ codigo: 0, usuario: {
      usuarioId: 17, nombreUsuario, correo: 'demo@example.invalid', debeCambiarPassword: nombreUsuario === 'obligatorio',
      permisos: ['USUARIOS_ADMINISTRAR', 'VENTAS_REGISTRAR', 'AUDITORIA_CONSULTAR'],
    } }) } });
  const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = 'http://127.0.0.1:' + server.address().port;
  const request = (path, options = {}) => fetch(base + path, { redirect: 'manual', ...options });
  const cookie = response => response.headers.get('set-cookie')?.split(';')[0];
  const csrf = html => html.match(/name="_csrf" value="([a-f0-9]{64})"/)[1];
  const post = (path, session, body) => request(path, { method: 'POST', headers: { cookie: session }, body: new URLSearchParams(body) });
  const login = async user => request('/login', { method: 'POST', body: new URLSearchParams({ NombreUsuario: user, Password: 'Anterior_2026!' }) });
  return { token, calls, request, cookie, csrf, post, login,
    fail: error => { failure = error; }, invalidate: () => { valid = false; } };
}

test('Recuperación: formulario oscuro, CSRF y mensaje genérico sin token en producción', async t => {
  const f = await fixture(t, true);
  const page = await f.request('/recuperar-password');
  assert.equal(page.status, 200); assert.equal(page.headers.get('referrer-policy'), 'no-referrer');
  assert.equal(page.headers.get('cache-control'), 'no-store');
  const html = await page.text(); assert.match(html, /RECUPERAR ACCESO/); assert.match(html, /class="login-page"/);
  const session = f.cookie(page); const csrf = f.csrf(html);
  const responses = [];
  for (const UsuarioOCorreo of ['demo','inexistente','demo@example.invalid','']) {
    const response = await f.post('/recuperar-password',session,{ _csrf: csrf, UsuarioOCorreo });
    assert.equal(response.status, 200); responses.push(await response.text());
  }
  assert.ok(responses.every(body => body === responses[0]));
  assert.match(responses[0], /Si la cuenta existe, se generó una solicitud de recuperación\./);
  assert.doesNotMatch(responses[0], /token=|DEMOSTRACIÓN|a{64}/);
  f.fail(new Error('PasswordHash Salt secret SQL'));
  assert.equal(await (await f.post('/recuperar-password',session,{ _csrf: csrf, UsuarioOCorreo: 'demo' })).text(),responses[0]);
  const count=f.calls.length;
  assert.equal((await f.post('/recuperar-password',session,{ _csrf:'bad', UsuarioOCorreo:'demo' })).status,403);
  assert.equal(f.calls.length,count);
  assert.match(await (await f.request('/login')).text(), /href="\/recuperar-password"/);
});

test('Desarrollo: enlace académico relativo, sin confiar en Host', async t => {
  const f=await fixture(t);
  const page=await f.request('/recuperar-password'); const csrf=f.csrf(await page.text());
  const response=await f.post('/recuperar-password',f.cookie(page),{_csrf:csrf,UsuarioOCorreo:'demo'});
  const html=await response.text(); assert.match(html,/DEMOSTRACIÓN ACADÉMICA/);
  assert.ok(html.includes('/restablecer-password?token='+f.token));
  assert.doesNotMatch(html,/https?:\/\//);
});

test('NODE_ENV=production oculta el enlace incluso si se desactiva la opción de producción de createApp', async t => {
  const previous = process.env.NODE_ENV;
  process.env.NODE_ENV = 'production';
  t.after(() => {
    if (previous === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = previous;
  });
  const f=await fixture(t,false);
  const page=await f.request('/recuperar-password'); const csrf=f.csrf(await page.text());
  const response=await f.post('/recuperar-password',f.cookie(page),{_csrf:csrf,UsuarioOCorreo:'demo'});
  assert.doesNotMatch(await response.text(),/token=|DEMOSTRACIÓN|a{64}/);
});

test('CSRF está aislado entre formularios y entre sesiones', async t => {
  const f=await fixture(t);
  const recovery=await f.request('/recuperar-password'); const session=f.cookie(recovery); const otherCsrf=f.csrf(await recovery.text());
  const reset=await f.request('/restablecer-password?token='+f.token,{headers:{cookie:session}});
  const resetCsrf=f.csrf(await reset.text()); assert.notEqual(resetCsrf,otherCsrf);
  const payload={token:f.token,Password:'Nueva_2026!',ConfirmarPassword:'Nueva_2026!'};
  assert.equal((await f.post('/restablecer-password',session,{...payload,_csrf:otherCsrf})).status,403);
  const other=await f.request('/restablecer-password?token='+f.token);
  assert.equal((await f.post('/restablecer-password',f.cookie(other),{...payload,_csrf:resetCsrf})).status,403);
  assert.equal(f.calls.length,0);
});

test('Restablecimiento: token válido, confirmación, longitudes UTF-16, CSRF y consumo único', async t => {
  const f=await fixture(t);
  let response=await f.request('/restablecer-password?token='+f.token);
  assert.equal(response.status,200); const html=await response.text(); const session=f.cookie(response); const csrf=f.csrf(html);
  assert.match(html,/NUEVA CONTRASEÑA/); assert.match(html,/name="token"/);
  for(const body of [
    {Password:'Nueva_2026!',ConfirmarPassword:'diferente'},
    {Password:'',ConfirmarPassword:''},
    {Password:'1234567',ConfirmarPassword:'1234567'},
    {Password:' '.repeat(8),ConfirmarPassword:' '.repeat(8)},
    {Password:'😀'.repeat(65),ConfirmarPassword:'😀'.repeat(65)},
  ]) {
    response=await f.post('/restablecer-password',session,{_csrf:csrf,token:f.token,...body});
    assert.equal(response.status,400); assert.doesNotMatch(await response.text(),/value="Nueva_2026!/);
  }
  assert.equal(f.calls.length,0);
  const payload={_csrf:csrf,token:f.token,Password:' Nueva_2026! ',ConfirmarPassword:' Nueva_2026! '};
  assert.equal((await f.post('/restablecer-password',session,{...payload,_csrf:'bad'})).status,403);
  response=await f.post('/restablecer-password',session,payload); assert.equal(response.status,200);
  const done=await response.text(); assert.match(done,/Contraseña actualizada/); assert.doesNotMatch(done,/name="token"|a{64}|Nueva_2026!/);
  assert.deepEqual(f.calls,[['restablecer',f.token,' Nueva_2026! ']]);
  response=await f.request('/restablecer-password?token='+f.token); assert.equal(response.status,400);
  assert.match(await response.text(),/no es válido o ha expirado/);
  for(const token of ['bad','b'.repeat(64)]) assert.equal((await f.request('/restablecer-password?token='+token)).status,400);
});

test('Restablecimiento: token expirado/utilizado/invalidado y errores internos no se revelan', async t => {
  const f=await fixture(t); const page=await f.request('/restablecer-password?token='+f.token);
  const session=f.cookie(page); const csrf=f.csrf(await page.text());
  const payload={_csrf:csrf,token:f.token,Password:'Nueva_2026!',ConfirmarPassword:'Nueva_2026!'};
  f.invalidate(); let response=await f.post('/restablecer-password',session,payload); assert.equal(response.status,400);
  assert.match(await response.text(),/no es válido o ha expirado/);
  f.fail(new Error('PasswordHash Salt TokenHash private-secret'));
  response=await f.post('/restablecer-password',session,payload); assert.equal(response.status,503);
  assert.doesNotMatch(await response.text(),/PasswordHash|Salt|TokenHash|private-secret|Nueva_2026!/);
});

test('Cambio obligatorio: login y acceso directo a todos los módulos redirigen; cambio renueva sesión', async t => {
  const f=await fixture(t);
  assert.equal((await f.request('/cambiar-password')).headers.get('location'),'/login');
  const login=await f.login('obligatorio'); assert.equal(login.status,303); assert.equal(login.headers.get('location'),'/cambiar-password');
  const session=f.cookie(login);
  for(const path of ['/','/login','/dashboard','/facturacion','/auditoria','/usuarios','/usuarios/2/roles']) {
    const response=await f.request(path,{headers:{cookie:session}});
    assert.equal(response.headers.get('location'),'/cambiar-password',path);
  }
  for(const path of ['/facturacion/procesar','/usuarios/2/roles'])
    assert.equal((await f.post(path,session,{})).headers.get('location'),'/cambiar-password');
  const page=await f.request('/cambiar-password',{headers:{cookie:session}}); assert.equal(page.status,200);
  const html=await page.text(); const csrf=f.csrf(html); assert.match(html,/antes de continuar/);
  const body={_csrf:csrf,PasswordActual:'Anterior_2026!',Password:'Nueva_2026!',ConfirmarPassword:'Nueva_2026!',UsuarioId:999,DebeCambiarPassword:0};
  assert.equal((await f.post('/cambiar-password',session,{...body,_csrf:'bad'})).status,403);
  f.fail(Object.assign(new Error('private SQL'),{number:54003}));
  let response=await f.post('/cambiar-password',session,body); assert.equal(response.status,400);
  assert.match(await response.text(),/contraseña actual no es correcta/);
  assert.equal((await f.request('/dashboard',{headers:{cookie:session}})).headers.get('location'),'/cambiar-password');
  f.fail(undefined);
  response=await f.post('/cambiar-password',session,body); assert.equal(response.status,303); assert.equal(response.headers.get('location'),'/dashboard');
  const updated=f.cookie(response); assert.notEqual(updated,session);
  assert.deepEqual(f.calls,[['cambiar',17,'Anterior_2026!','Nueva_2026!']]);
  assert.equal((await f.request('/dashboard',{headers:{cookie:updated}})).status,200);
  assert.equal((await f.request('/dashboard',{headers:{cookie:session}})).headers.get('location'),'/login');
});

test('Cambio voluntario disponible para usuarios autenticados sin obligación', async t => {
  const f=await fixture(t); const login=await f.login('normal');
  assert.equal(login.headers.get('location'),'/dashboard');
  const response=await f.request('/cambiar-password',{headers:{cookie:f.cookie(login)}});
  assert.equal(response.status,200); assert.match(await response.text(),/Volver al dashboard/);
});

test('PasswordService: randomBytes, solo SHA-512 del token a SQL y fórmula de password delegada', async () => {
  const calls=[]; const responses=[{Generado:true},{Valido:true},{Actualizado:true},{Actualizado:true}];
  const service=createPasswordService(async () => ({request(){ const inputs=[];return {
    input(name,type,value){inputs.push({name,type,value});return this;},
    async execute(procedure){calls.push({procedure,inputs});return {recordset:[responses.shift()]};},
  };}}));
  const token=await service.solicitar('demo'); assert.match(token,/^[a-f0-9]{64}$/);
  const hash=createHash('sha512').update(token,'utf8').digest();
  assert.deepEqual(calls[0].inputs[1].value,hash); assert.equal(hash.length,64);
  assert.equal(await service.validar(token),true); await service.restablecer(token,' Unicode á 2026! '); await service.cambiar(17,'Anterior_2026!','Nueva_2026!');
  assert.deepEqual(calls.map(c=>c.procedure),['dbo.sp_SolicitarRecuperacionPassword','dbo.sp_ValidarTokenRecuperacion','dbo.sp_RestablecerPassword','dbo.sp_CambiarPassword']);
  assert.equal(calls[2].inputs[1].value,' Unicode á 2026! ');
  assert.ok(calls.every(c=>c.inputs.every(i=>i.value!==token)));
  const count=calls.length; assert.equal(await service.validar('bad'),false);
  await assert.rejects(service.restablecer('bad','Nueva_2026!'),{number:54001}); assert.equal(calls.length,count);
});

test('SQL de recuperación sincronizado, permisos EXECUTE y sin tabla nueva ni auditoría de secretos', () => {
  const sql=readFileSync('database/12_PasswordRecovery.sql','utf8');
  const full=readFileSync('database/SecureFinanceERP_Full.sql','utf8').replace(/\r\n/g,'\n');
  assert.ok(full.includes(sql.replace(/\r\n/g,'\n')));
  assert.doesNotMatch(sql,/CREATE TABLE|INSERT\s+(?:INTO\s+)?dbo\.Bitacora_Transacciones/i);
  const permissions=readFileSync('database/10_AppPermissions.sql','utf8');
  assert.doesNotMatch(permissions,/GRANT\s+(SELECT|UPDATE|INSERT|DELETE)|db_owner|db_datareader|db_datawriter/i);
  for(const procedure of ['sp_SolicitarRecuperacionPassword','sp_ValidarTokenRecuperacion','sp_RestablecerPassword','sp_CambiarPassword'])
    assert.ok(permissions.includes('GRANT EXECUTE ON OBJECT::dbo.'+procedure));
});
