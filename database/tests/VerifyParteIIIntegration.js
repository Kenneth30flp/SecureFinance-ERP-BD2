'use strict';
// Only invoked by RunEdwardTests after a fresh marked database has been installed.
const assert=require('node:assert/strict');
const {once}=require('node:events');
async function verify({database,run}){
 assert.match(database,/^SecureFinanceERP_Edward_Test_[a-f0-9]{32}$/);
 require('dotenv').config({quiet:true});
 const login=process.env.DB_USER;
 assert(login && login.toLowerCase()!=='sa');
 await run(`ALTER USER securefinance_app WITH LOGIN=[${login.replaceAll(']',']]')}];`);
 process.env.DB_NAME=database;
 const db=require('../../src/config/database');
 let server;
 try{
  const actorOutput=await run("SET NOCOUNT ON; SELECT 'ACTOR:'+CONVERT(varchar(12),MIN(UsuarioId)) FROM dbo.Usuario;");
  const actor=Number(actorOutput.match(/ACTOR:(\d+)/)[1]);
  const permissionsOutput=await run("SET NOCOUNT ON; SELECT Codigo FROM dbo.Permiso WHERE Activo=1;");
  const permissions=permissionsOutput.match(/\b[A-Z]+(?:_[A-Z]+)+\b/g);
  await assert.rejects((await db.getPool()).request().query('SELECT TOP(1) TicketId FROM dbo.Ticket_Garantia'),error=>error.number===229);
  const service=require('../../src/modules/jose/analiticaService').createAnaliticaService();
  const filters={modo:'RANGO',fechaDesde:'2000-01-01',fechaHasta:'2099-12-31',limite:100,desplazamiento:0};
  let result=await service.obtenerDashboard(actor,filters);
  assert.equal(result.garantias.length,5);
  const countsOutput=await run("SET NOCOUNT ON; SELECT 'COUNT:'+Estado+':'+CONVERT(varchar(30),COUNT_BIG(*)) FROM dbo.Ticket_Garantia GROUP BY Estado;");
  const counts=Object.fromEntries([...countsOutput.matchAll(/COUNT:([A-Z_]+):(\d+)/g)].map(m=>[m[1],m[2]]));
  assert(Object.keys(counts).length>0,'Expected real Edward ticket fixtures');
  for(const row of result.garantias){assert.equal(row.Integrado,true);assert.equal(row.Cantidad,counts[row.Estado]||'0');}
  console.log('PASS warranty metrics equal actual Edward fixtures for all five states');
  result=await service.obtenerDashboard(actor,{...filters,fechaDesde:'2000-01-01',fechaHasta:'2000-01-02'});
  assert(result.garantias.every(g=>g.Cantidad==='0'));
  const app=require('../../server').createApp({secret:'integration-isolated-session-secret-123456789',production:false,
   authService:{login:async()=>({codigo:0,usuario:{usuarioId:actor,nombreUsuario:'integration-lab',permisos:permissions}})}});
  server=app.listen(0,'127.0.0.1');await once(server,'listening');
  const base='http://127.0.0.1:'+server.address().port;
  const routes=['/dashboard','/facturacion','/inventario','/productos','/proveedores','/clientes','/devoluciones','/garantias','/analitica'];
  for(const route of routes)assert.equal((await fetch(base+route,{redirect:'manual'})).status,302,route+' requires login');
  const response=await fetch(base+'/login',{method:'POST',body:new URLSearchParams({NombreUsuario:'integration-lab',Password:'fixture'}),redirect:'manual'});
  assert.equal(response.status,303);const cookie=response.headers.get('set-cookie').split(';')[0];
  for(const route of routes){const response=await fetch(base+route,{headers:{cookie},redirect:'manual'});assert.equal(response.status,200,route);await response.text();console.log('PASS HTTP + isolated SQL '+route);}
  // Remove only the lab administrator assignment, then restore it even on failure.
  const grant="INSERT dbo.Rol_Permiso(RolId,PermisoId) SELECT r.RolId,p.PermisoId FROM dbo.Rol r CROSS JOIN dbo.Permiso p WHERE r.Nombre=N'Administrador' AND p.Codigo=N'GARANTIAS_CONSULTAR';";
  await run("DELETE rp FROM dbo.Rol_Permiso rp JOIN dbo.Rol r ON r.RolId=rp.RolId JOIN dbo.Permiso p ON p.PermisoId=rp.PermisoId WHERE r.Nombre=N'Administrador' AND p.Codigo=N'GARANTIAS_CONSULTAR';");
  try{result=await service.obtenerDashboard(actor,filters);assert.equal(result.garantias[0].Integrado,false);assert.equal(result.garantias[0].Cantidad,undefined);}finally{await run(grant);}
  await assert.rejects(service.obtenerDashboard(2147483647,filters),error=>error.number===54101);
  console.log('PASS analytics and warranty SQL RBAC; unauthorized metrics withheld');
 }finally{if(server){server.closeAllConnections();await new Promise(r=>server.close(r));}await db.closePool();}
}
module.exports={verify};
