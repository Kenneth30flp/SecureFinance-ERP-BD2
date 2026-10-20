'use strict';
// Isolated native mssql + Express integration. Never starts the ordinary server.
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const os=require('node:os');
const {spawn}=require('node:child_process');
const {once}=require('node:events');
const {randomUUID}=require('node:crypto');
const sharp=require('sharp');
const root=path.resolve(__dirname,'../..');
const database='SecureFinanceERP_ParteII_Test_Web_'+randomUUID().replaceAll('-','');
const report={database,results:[],retained:true};
const reportPath=path.join(root,'docs/ParteIIKennethWebResultados.json');
const literal=s=>"N'"+String(s).replaceAll("'","''")+"'";
let directory,server;
async function command(binary,args,label){
 const child=spawn(binary,args,{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});let out='';child.stdout.on('data',d=>out+=d);child.stderr.on('data',d=>out+=d);
 const code=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',resolve);});await fs.writeFile(path.join(directory,label+'.log'),out);
 if(code!==0)throw new Error(label+' falló; revisar log local (sin credenciales).');return out;
}
async function sql(source,label){
 assert(!/\bUSE\s+|\b(?:CREATE|DROP|ALTER)\s+(?:DATABASE|LOGIN|SERVER)\b|^\s*[:!]/im.test(source));
 const guard=`SET ANSI_NULLS ON;SET QUOTED_IDENTIFIER ON;SET ANSI_PADDING ON;SET ANSI_WARNINGS ON;SET ARITHABORT ON;SET CONCAT_NULL_YIELDS_NULL ON;SET NUMERIC_ROUNDABORT OFF;\nIF DB_NAME()<>${literal(database)} OR NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'ParteII.TestRun') THROW 54900,'Contexto aislado incorrecto',1;\nGO\n`;
 const text=source.split(/^\s*GO\s*\r?$/mi).filter(x=>x.trim()).map(x=>guard+x+'\nGO\n').join('');
 const file=path.join(directory,label+'.sql');await fs.writeFile(file,text);
 return command('sqlcmd',['-S','localhost,1433','-E','-C','-b','-l','10','-d',database,'-f','65001','-i',file],label);
}
async function record(id,description,fn){try{const evidence=await fn();report.results.push({id,description,result:'PASS',evidence});console.log('PASS|'+id+'|'+description);}catch(e){report.results.push({id,description,result:'FAIL',error:e.message});throw e;}}
async function main(){
 if(!process.argv.includes('--run'))throw new Error('Requiere --run para crear una base nueva autorizada.');
 try{const previous=JSON.parse(await fs.readFile(reportPath,'utf8'));report.previousAttempts=[...(previous.previousAttempts||[]),{database:previous.database,summary:previous.summary,logs:previous.logs,status:previous.results?.some(r=>r.result==='FAIL')?'FAIL':'PASS',failure:previous.results?.find(r=>r.result==='FAIL')||null}];}catch(e){if(e.code!=='ENOENT')throw e;}
 directory=await fs.mkdtemp(path.join(os.tmpdir(),'securefinance-web-'));report.logs=directory;
 console.log('ISOLATED DATABASE: '+database);
 const readOriginal=()=>command('sqlcmd',['-S','localhost,1433','-E','-C','-b','-l','5','-d','SecureFinanceERP','-i',path.join(__dirname,'ReadOriginalState.sql'),'-W','-s','|'],'original-'+randomUUID());
 const originalBefore=await readOriginal();
 await record('SQL01','Fundamentos 28 + 4 y regresión histórica en base nueva',async()=>{
  const output=await command('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'RunParteIIKennethTests.ps1'),'-Server','localhost,1433','-Database',database,'-Run','-TrustServerCertificate'],'foundations');
  assert.equal((output.match(/^PASS\|\d+\|/gm)||[]).length,28);assert.match(output,/PASS\|S4\|/);assert.match(output,/OK: Funciones/);return{main:28,supplemental:4,legacyAudit:'PASS'};
 });
 for(const number of[21,22]){
  const names=await fs.readdir(path.join(root,'database'));const name=names.find(n=>n.startsWith(number+'_'));
  const source=await fs.readFile(path.join(root,'database',name),'utf8');await sql(source,'migration-'+number);await sql(source,'migration-'+number+'-repeat');
 }
 await record('SQL02','Migraciones 21 y 22 repetibles, sin apertura automática',async()=>{
  const output=await sql("IF EXISTS(SELECT 1 FROM dbo.ConfiguracionInventario WHERE Habilitado=1) OR EXISTS(SELECT 1 FROM dbo.Kardex_Inventario) THROW 54901,'Activacion prematura',1; SELECT 'PASS';",'disabled');assert.match(output,/PASS/);
 });
 require('dotenv').config({quiet:true});
 const appLogin=process.env.DB_USER;
 assert(appLogin && appLogin.toLowerCase()!=='sa','Se requiere configuración local de cuenta SQL dedicada.');
 // Only map the existing application login inside THIS NEW database. No login/server changes.
 await sql(`ALTER USER securefinance_app WITH LOGIN=[${appLogin.replaceAll(']',']]')}];`,'map-app-user');
 process.env.DB_NAME=database;process.env.DB_SERVER='localhost';process.env.DB_PORT='1433';process.env.DB_TRUST_SERVER_CERTIFICATE='true';
 const password=randomUUID(),tag='WEB'+randomUUID().replaceAll('-','').slice(0,15);
 const permissions=['PRODUCTOS_CONSULTAR','PRODUCTOS_ADMINISTRAR','PROVEEDORES_CONSULTAR','PROVEEDORES_ADMINISTRAR','CLIENTES_CONSULTAR','CLIENTES_ACTUALIZAR_NIT','CLIENTES_INACTIVAR','INVENTARIO_CONSULTAR','INVENTARIO_REGISTRAR','INVENTARIO_AJUSTAR','INVENTARIO_APERTURAR','VENTAS_REGISTRAR'];
 await sql(`DECLARE @U INT,@R INT,@Salt VARBINARY(32)=CRYPT_GEN_RANDOM(32); INSERT dbo.Usuario(NombreUsuario,NombreCompleto,Correo,PasswordHash,Salt,DebeCambiarPassword) VALUES(${literal(tag)},N'Usuario de pruebas web',${literal(tag+'@example.invalid')},HASHBYTES('SHA2_512',CONVERT(VARBINARY(256),${literal(password)})+@Salt),@Salt,0); SET @U=SCOPE_IDENTITY(); INSERT dbo.Rol(Nombre) VALUES(${literal(tag)});SET @R=SCOPE_IDENTITY(); INSERT dbo.Usuario_Rol(UsuarioId,RolId) VALUES(@U,@R); INSERT dbo.Rol_Permiso SELECT @R,PermisoId FROM dbo.Permiso WHERE Codigo IN(${permissions.map(literal).join(',')}); INSERT dbo.Cliente(NIT,Nombre)VALUES(${literal(tag)},N'Cliente de pruebas aisladas');`,'synthetic-fixtures');
 const db=require('../../src/config/database');const pool=await db.getPool();
 assert.equal((await pool.request().query('SELECT DB_NAME() AS Name')).recordset[0].Name,database);
 const {createApp}=require('../../server');
 const photosDirectory=path.join(directory,'photos');const {createFotografiaService}=require('../../src/services/fotografiaService');
 const services={productos:require('../../src/services/productoService').createProductoService(),proveedores:require('../../src/services/proveedorService').createProveedorService(),clientes:require('../../src/services/clienteService').createClienteService(),inventario:require('../../src/services/inventarioService').createInventarioService(),photos:createFotografiaService(photosDirectory)};
 const app=createApp({secret:randomUUID()+randomUUID(),kennethServices:services});server=app.listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
 let cookie,csrf;const http=(url,options={})=>fetch(base+url,{redirect:'manual',...options,headers:{Cookie:cookie||'',...options.headers}});
 const post=(url,body)=>http(url,{method:'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':csrf},body:JSON.stringify(body)});
 await record('WEB01','Login real, permisos SQL y navegación protegida',async()=>{
  const response=await http('/login',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({NombreUsuario:tag,Password:password})});assert.equal(response.status,303);cookie=response.headers.get('set-cookie').split(';')[0];
  const r=await http('/productos');assert.equal(r.status,200);const html=await r.text();csrf=html.match(/name="csrf-token" content="([a-f0-9]+)"/)[1];for(const route of['inventario','productos','proveedores','clientes'])assert(html.includes('href="/'+route+'"'));
 });
 let supplier,product,customer,actor;
 // Identity comes from the actual login/session. Resolve test fixture IDs only through administrative SQL.
 const identities=await sql(`SET NOCOUNT ON; SELECT CONCAT('IDENTITY|',UsuarioId,'|',(SELECT ClienteId FROM dbo.Cliente WHERE NIT=${literal(tag)})) FROM dbo.Usuario WHERE NombreUsuario=${literal(tag)};`,'fixture-ids');
 const ids=identities.match(/IDENTITY\|(\d+)\|(\d+)/);assert(ids);actor=Number(ids[1]);customer=Number(ids[2]);
 await record('WEB02','Proveedor registrado y consultado mediante HTTP + SP',async()=>{
  const r=await post('/proveedores',{NIT:tag+'P',Nombre:'Abastecimiento de prueba',Correo:'proveedor@example.invalid',Telefono:'55550000',Direccion:'Base de pruebas'});assert.equal(r.status,201);supplier=(await r.json()).id;const found=await services.proveedores.list(actor,{buscar:'Abastecimiento'});assert(found.some(s=>s.ProveedorId===supplier));return{supplier};
 });
 const body={Codigo:tag,Descripcion:'Equipo de inventario de prueba',Precio:'35.90',PrecioCosto:'20.00',ProveedorId:String(supplier),StockMinimo:'2',PuntoReorden:'4',GarantiaMeses:'12'};
 await record('WEB03','Producto registrado sin stock editable; SKU duplicado rechazado',async()=>{
  const r=await post('/productos',{...body,Stock:999,UsuarioId:999});assert.equal(r.status,201);product=(await r.json()).id;assert.equal((await services.productos.list(actor,{id:product}))[0].Stock,0);assert.equal((await post('/productos',body)).status,400);return{product};
 });
 await record('WEB04','Proveedor editado con versión; concurrencia rechazada',async()=>{
  const row=(await services.proveedores.list(actor,{id:supplier}))[0];const d={NIT:row.NIT,Nombre:row.Nombre,Correo:'nuevo@example.invalid',Telefono:'55551111',Direccion:'Pruebas',Version:row.Version,Activo:'1'};
  assert.equal((await post('/proveedores/'+supplier,d)).status,200);assert.equal((await post('/proveedores/'+supplier,d)).status,409);
 });
 await record('WEB05','Fotografía real validada, asociada y servida con autorización',async()=>{
  const png=await sharp({create:{width:120,height:80,channels:3,background:'#283e58'}}).png().toBuffer();const r=await http('/productos/fotografias',{method:'POST',headers:{'Content-Type':'image/png','X-File-Name':'test.png','X-CSRF-Token':csrf},body:png});assert.equal(r.status,201);const photo=await r.json();const row=(await services.productos.list(actor,{id:product,costo:true}))[0];
  assert.equal((await post('/productos/'+product,{...body,Version:row.Version,Activo:'1',UploadToken:photo.token})).status,200);assert.equal((await http(photo.url)).status,200);assert.equal((await fetch(base+photo.url,{redirect:'manual'})).status,302);return{format:'PNG',reference:'UUID'};
 });
 async function operation(){const html=await(await http('/inventario?id='+product)).text();return html.match(/name="OperacionId" value="([a-f0-9-]+)"/)[1];}
 await record('WEB06','Kardex deshabilitado rechaza movimiento sin escrituras',async()=>{
  const row=(await services.productos.list(actor,{id:product}))[0];const r=await post('/inventario/movimientos',{ProductoId:String(product),Version:row.Version,TipoMovimiento:'COMPRA',Cantidad:'1',DocumentoRespaldo:'WEB-TEST',Motivo:'Ingreso de prueba',OperacionId:await operation()});assert.equal(r.status,400);assert.equal((await services.productos.list(actor,{id:product}))[0].Stock,0);
 });
 const opening=randomUUID();await sql(`EXEC dbo.sp_AbrirKardexInventario ${literal(opening)},${actor},N'WEB-TEST-CUT',N'Apertura exclusivamente temporal'; EXEC dbo.sp_HabilitarKardexInventario ${literal(opening)},${actor};`,'temporary-opening');
 await record('WEB07','Ingreso real, reintento y ajuste con stock insuficiente',async()=>{
  let row=(await services.productos.list(actor,{id:product}))[0];const d={ProductoId:String(product),Version:row.Version,TipoMovimiento:'COMPRA',Cantidad:'5',DocumentoRespaldo:'WEB-COMPRA',Motivo:'Ingreso prueba',OperacionId:await operation()};
  assert.equal((await post('/inventario/movimientos',d)).status,201);assert.equal((await post('/inventario/movimientos',d)).status,201);row=(await services.productos.list(actor,{id:product}))[0];assert.equal(row.Stock,5);
  const bad={...d,Version:row.Version,TipoMovimiento:'AJUSTE_EGRESO',Cantidad:'6',OperacionId:await operation()};assert.equal((await post('/inventario/movimientos',bad)).status,409);assert.equal((await services.productos.list(actor,{id:product}))[0].Stock,5);
  assert.equal((await services.inventario.history(actor,{id:product})).filter(k=>k.TipoMovimiento==='COMPRA').length,1);
 });
 await record('WEB08','Cambio de NIT, concurrencia y posterior inactivación lógica',async()=>{
  let row=(await services.clientes.list(actor,{id:customer}))[0];const d={Version:row.Version,NIT:tag+'N',Motivo:'Corrección prueba'};assert.equal((await post('/clientes/'+customer+'/nit',d)).status,200);assert.equal((await post('/clientes/'+customer+'/nit',d)).status,409);
  row=(await services.clientes.list(actor,{id:customer}))[0];assert.equal(row.NIT,(tag+'N').toUpperCase());assert.equal((await post('/clientes/'+customer+'/inactivar',{Version:row.Version,Motivo:'Solicitud de prueba'})).status,200);assert.equal((await services.clientes.list(actor,{id:customer}))[0].Activo,false);
 });
 await record('WEB09','CSRF real y permiso revocado en SQL impiden cambios',async()=>{
  const before=(await services.productos.list(actor,{id:product}))[0];assert.equal((await http('/productos',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)})).status,403);
  await sql(`DELETE rp FROM dbo.Rol_Permiso rp JOIN dbo.Permiso p ON p.PermisoId=rp.PermisoId JOIN dbo.Rol r ON r.RolId=rp.RolId WHERE r.Nombre=${literal(tag)} AND p.Codigo=N'PRODUCTOS_ADMINISTRAR';`,'revoke-test-permission');
  assert.equal((await post('/productos/'+product,{...body,Version:before.Version,Activo:'1'})).status,403);
  await sql(`INSERT dbo.Rol_Permiso SELECT r.RolId,p.PermisoId FROM dbo.Rol r CROSS JOIN dbo.Permiso p WHERE r.Nombre=${literal(tag)} AND p.Codigo=N'PRODUCTOS_ADMINISTRAR';`,'restore-test-permission');
 });
 await record('SQL03','Consulta operativa y mínimos privilegios de aplicación',async()=>{
  const result=await pool.request().input('ActorUsuarioId',db.sql.Int,actor).execute('dbo.sp_ConsultarConciliacionInventario');assert(result.recordset.every(r=>Number(r.Diferencia)===0));
  await assert.rejects(pool.request().query('UPDATE dbo.Producto SET Stock=Stock WHERE 1=0'));return{products:result.recordset.length,differences:0};
 });
 if(process.argv.includes('--browser')){
  await sql(`INSERT dbo.Cliente(NIT,Nombre)VALUES(${literal(tag+'B')},N'Cliente para confirmacion de pruebas');`,'browser-customer');
  const activeCustomer=(await services.clientes.list(actor,{buscar:'Cliente para confirmacion de pruebas'}))[0].ClienteId;
  const {runKennethBrowser}=require('../../tests/browser/kenneth.browser');
  await record('UI01','Navegador real sobre SQL aislado: módulos, formularios y responsive',async()=>runKennethBrowser({base,username:tag,password,product,supplier,customer,activeCustomer,directory}));
 }
 await record('ORIGINAL','Base original intacta: huellas anteriores y posteriores',async()=>{const after=await readOriginal();assert.equal(after,originalBefore);return{unchanged:true};});
 report.summary={pass:report.results.filter(r=>r.result==='PASS').length,fail:0};
 await fs.writeFile(reportPath,JSON.stringify(report,null,2)+'\n');console.log('PASS WEB SQL: '+JSON.stringify({database,...report.summary,logs:directory}));
}
main().catch(async e=>{if(!report.results.some(r=>r.result==='FAIL'))report.results.push({id:'RUNNER',description:'Ejecución interrumpida',result:'FAIL',error:e.message});report.summary={pass:report.results.filter(r=>r.result==='PASS').length,fail:report.results.filter(r=>r.result==='FAIL').length};await fs.writeFile(reportPath,JSON.stringify(report,null,2)+'\n').catch(()=>{});console.error(e.message);process.exitCode=1;}).finally(async()=>{if(server)await new Promise(resolve=>{server.close(resolve);server.closeAllConnections();});await require('../../src/config/database').closePool().catch(()=>{});});
