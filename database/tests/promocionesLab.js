'use strict';
// Laboratorio aislado de Promociones (José, migraciones 60-69).
// Crea SIEMPRE una base NUEVA marcada SecureFinanceERP_P3_PRO_<fecha>_<hex>; nunca escribe en
// SecureFinanceERP, no ejecuta DROP/RESTORE y solo reescribe en memoria el USE del instalador.
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const assert=require('node:assert/strict');
const {spawn}=require('node:child_process');
const {randomBytes,randomUUID}=require('node:crypto');
const root=path.resolve(__dirname,'..');
const stateFile=path.resolve(root,'..','.data','promociones-lab.json');
const server=process.env.PROMOCIONES_TEST_SERVER||'localhost';
const labPattern=/^SecureFinanceERP_P3_PRO_\d{14}_[a-f0-9]{8}$/;
const PROMOCIONES=[60,61,62,63];
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'promociones-sql-'));
let serial=0;
const prelude='SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;\n';
function sqlcmd(text,db){
 const file=path.join(temp,String(++serial)+'.sql');
 fs.writeFileSync(file,prelude+text);
 return new Promise((resolve,reject)=>{
  const p=spawn('sqlcmd',['-S',server,'-E','-C','-b','-r','0','-f','65001','-W','-s','|','-d',db,'-i',file],{windowsHide:true});
  let out='';p.stdout.on('data',d=>out+=d);p.stderr.on('data',d=>out+=d);
  p.on('error',reject);p.on('close',code=>code===0?resolve(out):reject(new Error(out.slice(0,4000))));
 });
}
function guard(db){assert.match(db,labPattern,'Destino fuera del laboratorio autorizado');return db;}
function migration(n){
 const files=fs.readdirSync(root).filter(f=>f.startsWith(n+'_')&&f.endsWith('.sql'));
 assert.equal(files.length,1,'Migracion ambigua o ausente: '+n);
 return path.join(root,files[0]);
}
function safe(text,db){
 text=text.replace(/USE \[SecureFinanceERP\];/g,'USE ['+db+'];');
 if(/\b(?:CREATE|ALTER|DROP)\s+(?:DATABASE|LOGIN|SERVER)\b/i.test(text.replace(/^\s*--.*$/gm,'')))throw Error('Instruccion de servidor prohibida en migracion');
 for(const use of text.matchAll(/\bUSE\s+\[?([\w]+)\]?\s*;/gi))assert.equal(use[1],db);
 return text;
}
// Promociones (60+) se instalan atomicamente: una transaccion externa por migracion; -b aborta y revierte.
async function applyMigration(db,n){
 const text=safe(fs.readFileSync(migration(n),'utf8'),db);
 await sqlcmd(n>=60?'BEGIN TRANSACTION;\nGO\n'+text+'\nGO\nIF @@TRANCOUNT>0 COMMIT;\n':text,guard(db));
}
function readState(){return JSON.parse(fs.readFileSync(stateFile,'utf8'));}
async function build(){
 const stamp=new Date().toISOString().replace(/\D/g,'').slice(0,14);
 const db=guard('SecureFinanceERP_P3_PRO_'+stamp+'_'+randomBytes(4).toString('hex'));
 const marker=randomUUID();
 await sqlcmd(`IF DB_ID(N'${db}') IS NOT NULL THROW 54900,'Base existente',1; CREATE DATABASE [${db}];`,'master');
 await sqlcmd(`EXEC sys.sp_addextendedproperty @name=N'Promociones.TestRun',@value=N'${marker}';`,db);
 // Login exclusivo del laboratorio para las pruebas HTTP con la cuenta de aplicacion (sin db_owner).
 // El usuario se crea ANTES del instalador para recibir sus GRANT/DENY condicionales.
 const login=db.replace('SecureFinanceERP_','sfapp_');const password='Lab#'+randomBytes(18).toString('base64url');
 await sqlcmd(`IF SUSER_ID(N'${login}') IS NULL CREATE LOGIN [${login}] WITH PASSWORD=N'${password}', CHECK_POLICY=OFF, DEFAULT_DATABASE=[${db}];`,'master');
 await sqlcmd(`IF DATABASE_PRINCIPAL_ID('securefinance_app') IS NULL CREATE USER securefinance_app FOR LOGIN [${login}];`,db);
 const full=fs.readFileSync(path.join(root,'SecureFinanceERP_Full.sql'),'utf8');
 const start=full.indexOf('USE [SecureFinanceERP];');assert.ok(start>=0);
 await sqlcmd("EXEC sys.sp_set_session_context @key=N'SecureFinance.AllowAcademicSeed',@value=1;\nGO\n"+safe(full.slice(start),db),db);
 // Full.sql (10_AppPermissions) guarda sus GRANT con SUSER_ID(N'securefinance_app') literal;
 // el login del laboratorio tiene otro nombre para evitar colisiones entre laboratorios, por lo
 // que ese bloque no se ejecuta. Se repiten aqui los mismos GRANT, ya con el USER securefinance_app creado.
 await sqlcmd(`GRANT EXECUTE ON OBJECT::dbo.sp_Login TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerResumenDashboard TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerPermisosUsuario TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_SolicitarRecuperacionPassword TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ValidarTokenRecuperacion TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_RestablecerPassword TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_CambiarPassword TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ListarClientes TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerPoliticaVenta TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ListarProductosDisponibles TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ProcesarVentaTransaccional TO [securefinance_app];
GRANT EXECUTE, REFERENCES ON TYPE::dbo.TipoDetalleVenta TO [securefinance_app];
GRANT EXECUTE, REFERENCES ON TYPE::dbo.TipoDetalleVentaDescuento TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ProcesarVentaSinDescuento TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ListarUsuariosAdministracion TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ListarRolesActivos TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ObtenerRolesUsuario TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ActualizarRolesUsuario TO [securefinance_app];
GRANT EXECUTE, REFERENCES ON TYPE::dbo.TipoRolUsuario TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarBitacoraAcceso TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarAuditoriaTransacciones TO [securefinance_app];
GRANT EXECUTE ON OBJECT::dbo.sp_ConsultarHistoricoVentas TO [securefinance_app];`,db);
 for(let n=15;n<=44;n++){if(n>=27&&n<=29)continue;await applyMigration(db,n);}
 console.log('PASS base Parte II + Cotizaciones 15-44 en '+db);
 // Fixtures: administrador academico con todos los permisos existentes y Kardex habilitado.
 await sqlcmd(`DECLARE @Actor INT=(SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'admin'),@Rol INT=(SELECT RolId FROM dbo.Rol WHERE Nombre=N'Administrador');
 IF @Actor IS NULL THROW 54900,'Falta admin academico',1;
 UPDATE dbo.Usuario SET DebeCambiarPassword=0 WHERE UsuarioId=@Actor;
 INSERT dbo.Rol_Permiso(RolId,PermisoId) SELECT @Rol,p.PermisoId FROM dbo.Permiso p WHERE NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=@Rol AND rp.PermisoId=p.PermisoId);
 DECLARE @Apertura UNIQUEIDENTIFIER=NEWID();
 EXEC dbo.sp_AbrirKardexInventario @Apertura,@Actor,N'LAB-P3-PRO',N'Apertura laboratorio aislado de promociones';
 EXEC dbo.sp_HabilitarKardexInventario @Apertura,@Actor;`,db);
 const actor=Number(/(\d+)\s*$/m.exec(await sqlcmd("SET NOCOUNT ON; SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'admin';",db))[1]);
 fs.mkdirSync(path.dirname(stateFile),{recursive:true});
 fs.writeFileSync(stateFile,JSON.stringify({lab:db,marker,server,login,password,actor,promociones:false},null,2));
 console.log('PASS laboratorio preparado: '+db+' (estado en .data/promociones-lab.json)');
 return db;
}
async function install(){
 const state=readState();guard(state.lab);
 for(const n of PROMOCIONES)await applyMigration(state.lab,n);
 state.promociones=true;fs.writeFileSync(stateFile,JSON.stringify(state,null,2));
 console.log('PASS migraciones '+PROMOCIONES.join(', ')+' instaladas en '+state.lab);
}
async function labQuery(text){const state=readState();return sqlcmd(text,guard(state.lab));}
// Lectura administrativa (Windows) devuelta como JSON; solo para verificar el laboratorio.
function labJson(query){
 const state=readState();guard(state.lab);
 const file=path.join(temp,String(++serial)+'.sql'),outFile=path.join(temp,String(++serial)+'.out');
 // Delimitadores unicos: evitan confundir el encabezado/guiones de sqlcmd con el JSON.
 fs.writeFileSync(file,prelude+"SET NOCOUNT ON; PRINT '~~~JSON-BEGIN~~~'; SELECT CONVERT(NVARCHAR(MAX),("+query+" FOR JSON PATH, INCLUDE_NULL_VALUES)); PRINT '~~~JSON-END~~~';");
 return new Promise((resolve,reject)=>{
  // sqlcmd solo preserva texto no ASCII de forma fiable en archivo Unicode (-u -o), no por stdout/pipe.
  const p=spawn('sqlcmd',['-S',server,'-E','-C','-b','-r','0','-y','0','-f','i:65001','-u','-o',outFile,'-d',state.lab,'-i',file],{windowsHide:true});
  let err='';p.stderr.on('data',d=>err+=d);
  p.on('error',reject);
  p.on('close',code=>{
   let out='';try{out=fs.readFileSync(outFile).toString('utf16le');}catch{}
   if(code!==0)return reject(new Error((err||out).slice(0,4000)));
   const begin=out.indexOf('~~~JSON-BEGIN~~~'),end=out.indexOf('~~~JSON-END~~~');
   if(begin<0||end<0)return reject(new Error('Delimitadores JSON ausentes: '+out.slice(0,500)));
   const body=out.slice(begin+'~~~JSON-BEGIN~~~'.length,end).replace(/\r?\n/g,'').trim();
   try{resolve(body&&body!=='NULL'?JSON.parse(body):[]);}catch(e){reject(new Error('JSON invalido: '+body.slice(0,800)));}
  });
 });
}
// Aplica la configuracion del laboratorio al proceso actual, antes de cargar src/config/database.
function useLab(){
 const state=readState();guard(state.lab);
 Object.assign(process.env,{DB_SERVER:state.server==='localhost'?'localhost':state.server,DB_NAME:state.lab,DB_USER:state.login,DB_PASSWORD:state.password,DB_ENCRYPT:'true',DB_TRUST_SERVER_CERTIFICATE:'true'});
 return state;
}
module.exports={build,install,labQuery,labJson,useLab,readState,applyMigration,PROMOCIONES};
if(require.main===module){
 const run=async()=>{
  if(process.argv.includes('--build'))await build();
  if(process.argv.includes('--install'))await install();
  if(!process.argv.some(a=>['--build','--install'].includes(a)))throw Error('Usa --build para crear una base NUEVA y/o --install para instalar 60-63.');
 };
 run().catch(e=>{console.error('LAB FAIL',e.message);process.exitCode=1;});
}
