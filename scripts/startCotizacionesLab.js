'use strict';
// Explicit opt-in lab launcher. Never rewrites .env or enables a fixture login.
const fs=require('node:fs');
const path=require('node:path');
const {execFileSync}=require('node:child_process');
const {once}=require('node:events');
const root=path.resolve(__dirname,'..');
process.chdir(root);
require('dotenv').config({quiet:true});
const demo=process.argv.includes('--demo');
const state=JSON.parse(fs.readFileSync(demo?'.data/cotizaciones-demo.json':'.data/cotizaciones-lab.json','utf8').replace(/^\uFEFF/,''));
const allowed=demo?/^SecureFinanceERP_P3_COT_DEMO_\d{14}_[a-f0-9]{8}$/:/^SecureFinanceERP_P3_COT_\d{14}_[a-f0-9]{8}$/;
if(!allowed.test(state.lab))throw Error('El destino no coincide con el entorno aislado seleccionado.');
const branch=execFileSync('git',['branch','--show-current'],{encoding:'utf8',windowsHide:true}).trim();
if(branch!=='feature/p3-kenneth-cotizaciones')throw Error('Selecciona feature/p3-kenneth-cotizaciones antes de iniciar el laboratorio.');
const commit=execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8',windowsHide:true}).trim();
const portIndex=process.argv.indexOf('--port');
const port=portIndex===-1?(demo?3104:3103):Number(process.argv[portIndex+1]);
if(!Number.isInteger(port)||port<1024||port>65535||port===3000)throw Error('Usa un puerto de laboratorio distinto de 3000 (predeterminado 3103).');
process.env.DB_NAME=state.lab;
process.env.PORT=String(port);
const {getPool,closePool,sql}=require('../src/config/database');
const {verifyIntegration}=require('../src/config/integration');
const {createCotizacionService}=require('../src/modules/cotizaciones/service');
const {requireAuth}=require('../src/middleware/authMiddleware');
const {createApp}=require('../server');
async function main(){
 const pool=await getPool(),identity=await verifyIntegration(pool);
 if(identity.databaseName!==state.lab)throw Error('DB_NAME no coincide con el laboratorio seleccionado.');
 const permissions=(await pool.request().input('UsuarioId',sql.Int,state.actor).execute('dbo.sp_ObtenerPermisosUsuario')).recordset.map(p=>p.Codigo);
 const required=['COTIZACIONES_CONSULTAR','COTIZACIONES_CREAR','COTIZACIONES_CONVERTIR','VENTAS_REGISTRAR','FACTURAS_CONSULTAR'];
 if(required.some(p=>!permissions.includes(p)))throw Error('El Administrador de la copia no tiene todos los permisos de Cotizaciones/Facturacion.');
 const status=await createCotizacionService().readiness(state.actor,1);
 if(!status.installed||!status.executable||status.database!==state.lab)throw Error('Falta instalar/verificar el contrato SQL 43 en laboratorio.');
 if(demo){await createCotizacionService().form(state.actor);await createCotizacionService().search(state.actor,'productos','',1);}
 const runtime={pid:process.pid,port,branch,commit,database:identity.databaseName,sqlLogin:identity.loginName,conversionInstalled:true,authentication:'REAL_LOGIN_REQUIRED',demo};
 const app=createApp({production:false});
 app.locals.laboratorio=runtime;
 app.get('/laboratorio/estado',requireAuth,async(req,res)=>{
  res.set('Cache-Control','no-store');
  if(!req.session.usuario.permisos?.includes('COTIZACIONES_CONSULTAR'))return res.status(403).json({error:'Permiso requerido.'});
  try{const actual=(await pool.request().query('SELECT DB_NAME() Nombre')).recordset[0].Nombre;
   if(actual!==state.lab)throw Error();return res.json({...runtime,database:actual});
  }catch{return res.status(503).json({error:'No se pudo verificar la base de laboratorio.'});}
 });
 const server=app.listen(port,'127.0.0.1');
 await once(server,'listening');
 fs.writeFileSync(demo?'.data/cotizaciones-demo-preview.json':'.data/cotizaciones-preview.json',JSON.stringify(runtime,null,2));
 console.log((demo?'COTIZACIONES_DEMO_RUNTIME ':'COTIZACIONES_LAB_RUNTIME ')+JSON.stringify(runtime));
 console.log('Abrir http://localhost:'+port+'/cotizaciones (iniciar sesion con credenciales existentes de la copia).');
 const stop=()=>server.close(async()=>{await closePool();process.exitCode=0;});
 process.once('SIGINT',stop);process.once('SIGTERM',stop);
}
main().catch(async e=>{console.error('No se pudo iniciar laboratorio:',e.code||e.message);await closePool().catch(()=>{});process.exitCode=1;});
