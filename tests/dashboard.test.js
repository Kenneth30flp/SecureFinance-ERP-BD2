'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { readFileSync } = require('node:fs');
const { createApp } = require('../server');
const { createDashboardService } = require('../src/services/dashboardService');
const { sql } = require('../src/config/database');
const resumen = { VentasDia: '1245.50', FacturasDia: '12', ProductosStockBajo: '3', EventosDMLDia: '18', FechaOperacion: '2026-10-01', RolesActuales: 'Administrador' };

test('Dashboard: procedimiento tipado, importes exactos y contrato validado', async () => {
  const calls = [];
  let recordset = [resumen];
  const service = createDashboardService(async () => ({ request: () => ({
    input(name, type, value) { calls.push({ name, type, value }); return this; },
    async execute(name) { calls.push(name); return { recordset }; },
  }) }));
  assert.deepEqual(await service.obtenerResumen(17), resumen);
  assert.deepEqual(calls, [{ name: 'UsuarioId', type: sql.Int, value: 17 }, 'dbo.sp_ObtenerResumenDashboard']);
  for (const value of [[], [{ ...resumen, VentasDia: 'NaN' }], [{ ...resumen, FacturasDia: '-1' }]]) {
    recordset = value; await assert.rejects(service.obtenerResumen(17));
  }
});

test('Dashboard HTTP: autenticación, sesión real, KPIs escapados y fallo sin datos ficticios', async (t) => {
  let fail = false; const ids = [];
  const app = createApp({ secret: 'dashboard-tests-secret-12345678901234567890', production: false,
    authService: { login: async () => ({ codigo: 0, usuario: { usuarioId: 17, nombreUsuario: 'demo', permisos: ['VENTAS_REGISTRAR'] } }) },
    dashboardService: { obtenerResumen: async (id) => { ids.push(id); if (fail) throw new Error('SQL secret'); return { ...resumen, RolesActuales: '<script>role</script>' }; } },
  });
  const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = 'http://127.0.0.1:' + server.address().port;
  const anonymous = await fetch(base + '/dashboard', { redirect: 'manual' });
  assert.equal(anonymous.status, 302); assert.equal(ids.length, 0);
  const login = await fetch(base + '/login', { method: 'POST', redirect: 'manual', body: new URLSearchParams({ NombreUsuario: 'demo', Password: 'test' }) });
  const Cookie = login.headers.get('set-cookie').split(';')[0];
  let response = await fetch(base + '/dashboard?UsuarioId=999', { headers: { Cookie } });
  assert.equal(response.status, 200); assert.match(response.headers.get('cache-control'), /no-store/);
  let html = await response.text(); assert.match(html, /Q 1,245\.50/); assert.match(html, /&lt;script&gt;role/);
  assert.equal((html.match(/class="kpi-card"/g) || []).length, 0); assert.match(html,/operations-console/); assert.match(html,/id="mis-permisos"/); assert.deepEqual(ids, [17]);
  fail = true; response = await fetch(base + '/dashboard', { headers: { Cookie } }); html = await response.text();
  assert.equal(response.status, 200); assert.match(html, /No fue posible obtener el resumen operativo/);
  assert.doesNotMatch(html, /SQL secret|Q 0\.00/); assert.match(html, /href="\/facturacion"/);
});

test('Dashboard SQL: instalador sincronizado y permiso EXECUTE exclusivo', () => {
  const module = readFileSync('database/14_DashboardSummary.sql', 'utf8').replace(/\r\n/g, '\n').trim();
  const full = readFileSync('database/SecureFinanceERP_Full.sql', 'utf8').replace(/\r\n/g, '\n');
  assert.ok(full.includes(module));
  assert.match(readFileSync('database/10_AppPermissions.sql', 'utf8'), /GRANT EXECUTE ON OBJECT::dbo\.sp_ObtenerResumenDashboard/);
  assert.doesNotMatch(module, /GRANT SELECT|FLOAT/);
});

test('Dashboard: reorden real, paginacion sin duplicar el registro de adelanto y permiso SQL',async()=>{
 const requests=[];const products=Array.from({length:52},(_,i)=>({ProductoId:i+1,Descripcion:'Producto '+i,Activo:i!==2,Stock:8,StockMinimo:3,PuntoReorden:i===0?10:4}));
 products[51]={...products[51],Stock:1};
 const service=createDashboardService(async()=>({request:()=>{const values={};return{input(k,t,v){values[k]=v;return this;},async execute(proc){requests.push({proc,values});return{recordset:proc.includes('Estado')?[{Habilitado:true}]:products.slice(values.Desplazamiento,values.Desplazamiento+51)};}};}}));
 assert.equal(await service.obtenerOperacion(17,[]),null);assert.equal(requests.length,0);
 const result=await service.obtenerOperacion(17,['INVENTARIO_CONSULTAR']);
 assert.equal(result.total,2);assert.equal(result.criticos,1);assert.deepEqual(result.productos.map(p=>p.ProductoId),[52,1]);
 assert(requests.every(r=>r.values.ActorUsuarioId===17));assert.equal(requests[1].values.Inventario,true);assert.equal(requests[2].values.Desplazamiento,50);
});

test('Dashboard: cero real, accesos RBAC y permisos plegados sin tarjetas repetidas',async t=>{
 const app=createApp({secret:'operations-center-unit-secret-1234567890',production:false,authService:{login:async()=>({codigo:0,usuario:{usuarioId:17,nombreUsuario:'Operador',permisos:['CLIENTES_CONSULTAR']}})},dashboardService:{obtenerResumen:async()=>({...resumen,VentasDia:'0.00',FacturasDia:'0'}),obtenerOperacion:async()=>null}});
 const server=app.listen(0,'127.0.0.1');await once(server,'listening');t.after(()=>new Promise(r=>{server.close(r);server.closeAllConnections();}));
 const base='http://127.0.0.1:'+server.address().port;const login=await fetch(base+'/login',{method:'POST',redirect:'manual',body:new URLSearchParams({NombreUsuario:'test',Password:'test'})});
 const html=await(await fetch(base+'/dashboard',{headers:{Cookie:login.headers.get('set-cookie').split(';')[0]}})).text();
 assert.match(html,/Q 0\.00/);assert.match(html,/href="\/clientes"/);assert.doesNotMatch(html,/href="\/inventario"|href="\/usuarios"|href="\/facturacion"|kpi-card|Stock ≤ 5/);assert.match(html,/<details id="mis-permisos">/);
});

test('Seeds: academicos requieren opt-in, bloquean historicos y Full conserva fuentes',()=>{
 const full=readFileSync('database/SecureFinanceERP_Full.sql','utf8').replace(/\r\n/g,'\n');
 for(const name of ['04_SecuritySeedData.sql','05_BusinessSeedData.sql']){const source=readFileSync('database/'+name,'utf8').replace(/\r\n/g,'\n');assert.match(source,/SecureFinance.AllowAcademicSeed/);assert(full.includes(source));}
 const business=readFileSync('database/05_BusinessSeedData.sql','utf8');assert(business.indexOf('RETURN;')<business.indexOf('INSERT dbo.Cliente'));assert.match(business,/THROW 54950/);assert.match(business,/Kardex_Inventario/);
});

test('Dashboard: ceros discretos y alertas solo con evidencia de existencias o estado',async()=>{
 const render=operacion=>require('ejs').renderFile('src/views/dashboard.ejs',{moduleAreas:require('../src/config/moduleCatalog').visibleAreas,usuario:{nombreUsuario:'Operador',permisos:['INVENTARIO_CONSULTAR']},resumen:{...resumen,VentasDia:'0.00',FacturasDia:'0'},advertencia:null,avisoInventario:null,operacion});
 const empty=await render({total:0,criticos:0,habilitado:true,productos:[]});
 assert.match(empty,/oc-sales is-zero/);assert.match(empty,/Q 0\.00/);assert.doesNotMatch(empty,/class="oc-attention"|role="status"|Financial Operations Center|Enterprise finance/);
 const critical=await render({total:1,criticos:1,habilitado:true,productos:[{ProductoId:81,Descripcion:'Equipo <script>',Codigo:'SKU81',Stock:0,StockMinimo:3,PuntoReorden:8}]});
 assert.match(critical,/Revisar abastecimiento/);assert.match(critical,/Sin existencias/);assert.match(critical,/href="\/inventario\?id=81"/);assert.match(critical,/Equipo &lt;script&gt;/);
 const disabled=await render({total:0,criticos:0,habilitado:false,productos:[]});assert.match(disabled,/oc-inventory-state is-disabled/);assert.match(disabled,/El Kardex está deshabilitado/);
});
