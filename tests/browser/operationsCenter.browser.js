'use strict';
// SQL-backed, read-only preview. Authentication injection exists only in this process.
require('dotenv').config({quiet:true});
const previewActor=Number(process.env.KENNETH_PREVIEW_USER_ID);if(!Number.isSafeInteger(previewActor)||previewActor<1)throw new Error('Configura KENNETH_PREVIEW_USER_ID con el usuario autorizado del laboratorio.');

const assert=require('node:assert/strict'),fs=require('node:fs/promises');
const {once}=require('node:events'),db=require('../../src/config/database');
(async()=>{let server;try{
 const pool=await db.getPool();const permissions=(await pool.request().input('UsuarioId',db.sql.Int,previewActor).execute('dbo.sp_ObtenerPermisosUsuario')).recordset.map(p=>p.Codigo);
 server=require('../../server').createApp({production:false,authService:{login:async()=>({codigo:0,usuario:{usuarioId:previewActor,nombreUsuario:'admin',permisos:permissions,debeCambiarPassword:false}})}}).listen(0,'127.0.0.1');await once(server,'listening');
 const base='http://127.0.0.1:'+server.address().port,before=process.argv.includes('--before');
 const directory='docs/capturas/corporate-refinement/'+(before?'antes':'despues');
 await require('./kennethCapture').withBrowser(directory,async b=>{
 await b.navigate(base+'/login');await b.evaluate("fetch('/login',{method:'POST',body:new URLSearchParams({NombreUsuario:'preview',Password:'readonly-session'})})");
 for(const [width,height]of [[1366,768],[1920,1080],[390,844]]){
 await b.viewport(width,height);await b.navigate(base+'/dashboard');assert.equal(await b.evaluate('document.documentElement.scrollWidth>innerWidth'),false);await b.capture('dashboard-'+width);
 if(before)continue;
 if(width>767)assert.equal(await b.evaluate('document.querySelector("#workspace").getBoundingClientRect().left>=document.querySelector(".sidebar").getBoundingClientRect().right'),true,'Workspace clear of navigation');
 await b.evaluate("document.querySelector('.account-menu').open=true;document.querySelector('a[href=\"/dashboard#mis-permisos\"]').click()");await b.wait('document.querySelector("#mis-permisos").open');await b.navigate(base+'/dashboard');
 assert.equal(await b.evaluate('document.querySelectorAll(".kpi-card").length'),0);
 assert.equal(await b.evaluate('!!document.querySelector(".operations-console")'),true);
 for(const route of ['/facturacion','/inventario','/productos','/proveedores','/clientes','/auditoria','/usuarios'])assert.equal(await b.evaluate(`!!document.querySelector('.operations-console a[href=${JSON.stringify(route)}]')`),true);
 for(const module of ['clientes','proveedores','productos','inventario']){await b.navigate(base+'/'+module);assert.equal(await b.evaluate('document.documentElement.scrollWidth>innerWidth'),false,module+' '+width);await b.evaluate('Promise.all([...document.images].map(img=>{img.loading="eager";return img.decode().catch(()=>null)}))');await b.capture(module+'-'+width);}
 }
 assert.deepEqual(b.errors,[]);
 });console.log('PASS: SQL read-only, screenshots '+directory);
 }finally{if(server){server.closeAllConnections();await new Promise(r=>server.close(r));}await db.closePool();}
})().catch(e=>{console.error(e);process.exitCode=1;});
