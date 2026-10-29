'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {readFileSync} = require('node:fs');
const path = require('node:path');
const {createComprasService} = require('../src/modules/compras/service');
const v = require('../src/modules/compras/validation');
const safety = require('../database/tests/comprasLabSafety');
const data = () => ({ProveedorId:2,OperacionId:randomUUID(),Observaciones:null,Detalle:[{ProductoId:3,Cantidad:2,CostoUnitario:'10.1250'}]});
function fixture() {
  const calls = [];
  const provider = async () => ({request() {
    const inputs = [];
    return {input(...p) {inputs.push(p);return this;},async execute(procedure) {
      calls.push({procedure,inputs});
      return {recordsets:[[{OrdenCompraId:7,Numero:'OC-7',Total:'20.2500',OperacionId:inputs.find(p=>p[0]==='OperacionId')?.[2],
        Estado:({'dbo.P3_COM_EnviarAprobacion':'PENDIENTE_APROBACION','dbo.P3_COM_Aprobar':'APROBADA','dbo.P3_COM_Cancelar':'CANCELADA'})[procedure] || 'BORRADOR',Version:Buffer.from('0000000000000001','hex')}],[]]};
    }};
  }});
  return {calls,service:createComprasService(provider)};
}
test('Compras: actor externo, parametros tipados y texto hostil sin SQL concatenado',async () => {
  const {calls,service} = fixture(), d = {...data(),ActorUsuarioId:999,Observaciones:"'; DROP TABLE Producto;--"};
  const result = await service.create(42,d);
  assert.equal(result.Total,'20.2500');assert.equal(result.Version,'0000000000000001');
  assert.equal(calls[0].procedure,'dbo.P3_COM_Crear');
  const inputs = Object.fromEntries(calls[0].inputs.map(([k,,val]) => [k,val]));
  assert.equal(inputs.ActorUsuarioId,42);assert.equal(inputs.Observaciones,d.Observaciones);
  assert.equal(inputs.OperacionId,d.OperacionId);assert.deepEqual(JSON.parse(inputs.Detalle),d.Detalle);
});
test('Compras: costos exactos, cero explicito y orden canonico sin Number monetario',() => {
  const d = data();d.Detalle = [{ProductoId:4,Cantidad:2147483647,CostoUnitario:'999999999999999.9999'},{ProductoId:3,Cantidad:1,CostoUnitario:'0'}];
  const result = v.create(d);
  assert.equal(result.Detalle[0].CostoUnitario,'0.0000');assert.equal(result.Detalle[1].CostoUnitario,'999999999999999.9999');
});
test('Compras: rechaza cantidades y costos invalidos antes de obtener conexion',async () => {
  const service = createComprasService(() => {throw Error('No debe conectarse');});
  for (const Cantidad of [0,-1,1.5,'1',2147483648,NaN]) await assert.rejects(service.create(1,{...data(),Detalle:[{ProductoId:3,Cantidad,CostoUnitario:'1'}]}),TypeError);
  for (const CostoUnitario of [null,0,1.2,'-1','1e2','1.00001','1000000000000000','NaN',' 1','1.','01']) await assert.rejects(service.create(1,{...data(),Detalle:[{ProductoId:3,Cantidad:1,CostoUnitario}]}),TypeError);
  const d = data();d.Detalle.push({...d.Detalle[0]});await assert.rejects(service.create(1,d),TypeError);
  for (const Detalle of [[],Array(1),Array(101).fill(data().Detalle[0]),[{...data().Detalle[0],Stock:100}]]) await assert.rejects(service.create(1,{...data(),Detalle}),TypeError);
});
test('Compras: transiciones separadas conservan UUID, version y motivo',async () => {
  const {calls,service} = fixture();
  const d = {OrdenCompraId:7,OperacionId:randomUUID(),Version:'0000000000000001',Motivo:'Revision documentada'};
  for (const method of ['send','approve','cancel']) await service[method](42,d);
  assert.deepEqual(calls.map(c => c.procedure),['dbo.P3_COM_EnviarAprobacion','dbo.P3_COM_Aprobar','dbo.P3_COM_Cancelar']);
  for (const c of calls) {
    assert.equal(c.inputs.find(p => p[0]==='OperacionId')[2],d.OperacionId);
    assert.equal(c.inputs.find(p => p[0]==='VersionEsperada')[2].toString('hex'),d.Version);
  }
  for (const patch of [{Version:'1'},{Motivo:''},{Motivo:'x'.repeat(251)},{OperacionId:'invalid'},{OrdenCompraId:0}]) await assert.rejects(service.approve(42,{...d,...patch}),TypeError);
  assert.equal(calls.length,3);
});
test('Compras: consultas paginadas e historial usan procedimientos fijos',async () => {
  const {calls,service} = fixture();
  await service.list(42,{estado:'APROBADA',offset:50});await service.detail(42,7);await service.history(42,7);
  assert.deepEqual(calls.map(c=>c.procedure),['dbo.P3_COM_Consultar','dbo.P3_COM_Consultar','dbo.P3_COM_ConsultarHistorial']);
  await assert.rejects(service.list(42,{estado:"'; DROP TABLE x;--"}),TypeError);
  await assert.rejects(service.list(42,{offset:-1}),TypeError);
  await assert.rejects(service.detail(0,7),TypeError);
});
test('Compras: errores SQL no se reintentan automaticamente',async () => {
  let count=0;const error=Object.assign(Error('conflicto'),{number:55003});
  const service=createComprasService(async()=>({request(){return {input(){return this;},execute(){count++;throw error;}};}}));
  await assert.rejects(service.create(42,data()),e=>e===error);assert.equal(count,1);
});
test('Compras: guardas estaticas de alcance SQL (no sustituyen pruebas reales)',() => {
  const read = name => readFileSync(path.join(__dirname,'../database',name),'utf8');
  const schema=read('50_P3_COM_EstructuraOrdenesCompra.sql'),operations=read('51_P3_COM_OperacionesOrdenesCompra.sql');
  for (const source of [schema,operations]) {
    assert.doesNotMatch(source,/^\s*USE\s/im);
    assert.doesNotMatch(source,/\b(?:UPDATE|ALTER\s+TABLE|INSERT(?:\s+INTO)?|DELETE\s+FROM)\s+dbo\.(?:Producto|Proveedor|Kardex_Inventario|RecepcionCompra|DetalleRecepcionCompra)\b/i);
    assert.doesNotMatch(source,/EXEC\s+dbo\.sp_(?:RegistrarMovimientoKardex|RegistrarRecepcionCompra|ProcesarVenta)/i);
  }
  for (const permission of ['CONSULTAR','CREAR','APROBAR','CANCELAR']) assert.match(schema,new RegExp('COMPRAS_'+permission));
  assert.match(schema,/OperacionId UNIQUEIDENTIFIER NOT NULL UNIQUE/);
  assert.match(operations,/@Creador=@ActorUsuarioId/);
  assert.match(operations,/DENY EXECUTE ON dbo.P3_COM_Transicionar/);
  assert.doesNotMatch(operations,/SET\s+Estado\s*=\s*'(?:RECIBIDA|PARCIALMENTE_RECIBIDA)'/i);
});
test('Compras: laboratorio Express falla cerrado y genera solo destinos nuevos',()=>{
 const env={COMPRAS_LAB_SERVER:'localhost',COMPRAS_LAB_INSTANCE:'SQLEXPRESS',COMPRAS_LAB_EXPECTED_SERVER:'TEST\\SQLEXPRESS',COMPRAS_LAB_USER:'lab_dedicated',COMPRAS_LAB_PASSWORD:'not-a-real-password',COMPRAS_SQL_WRITE_AUTHORIZATION:'LAB_NUEVO_AISLADO'};
 assert.throws(()=>safety.plan(env,[]));assert.throws(()=>safety.plan({...env,COMPRAS_SQL_WRITE_AUTHORIZATION:''},['--execute-new-lab']));
 const a=safety.plan(env,['--execute-new-lab']),b=safety.plan(env,['--execute-new-lab']);assert.notEqual(a.database,b.database);assert.match(a.database,safety.labPattern);
 safety.assertIdentity(a.database,a.database,a.marker,a.marker);
 for(const actual of ['SecureFinanceERP','SecureFinanceERP_Edward_Test_1',b.database])assert.throws(()=>safety.assertIdentity(actual,a.database,a.marker,a.marker));
 assert.throws(()=>safety.assertIdentity(a.database,a.database,b.marker,a.marker));
 for(const patch of [{COMPRAS_LAB_SERVER:'production'},{COMPRAS_LAB_INSTANCE:'other'},{COMPRAS_LAB_USER:'sa'},{COMPRAS_LAB_USER:'securefinance_app'},{COMPRAS_LAB_DATABASE:a.database},{DB_DATABASE:'SecureFinanceERP'}])assert.throws(()=>safety.plan({...env,...patch},['--execute-new-lab']));
 for(const source of ['USE [SecureFinanceERP];','DROP DATABASE x;','RESTORE DATABASE x;','CREATE LOGIN x;'])assert.throws(()=>safety.batches(source));
 assert.equal(safety.batches('SELECT 1;\nGO\nSELECT 2;').length,2);
});
test('Compras: rechaza administrador y cualquier acceso a bases anteriores',()=>{
 const name='TEST\\SQLEXPRESS',row={DatabaseName:'master',ServerName:name,Sysadmin:0,ServerRoleCount:0,EngineEdition:4,MasterWrites:0,ModelAccess:0,MsdbWrites:0},db=[{database_id:5,state:0,Access:0}],perms=['CONNECT SQL','VIEW ANY DATABASE','CREATE ANY DATABASE'].map(permission_name=>({permission_name}));
 safety.assertServer(row,name,db,[],perms);
 for(const patch of [{Sysadmin:1},{ServerRoleCount:1},{MasterWrites:1},{ModelAccess:1},{MsdbWrites:1},{EngineEdition:3},{ServerName:'production'},{DatabaseName:'SecureFinanceERP'}])assert.throws(()=>safety.assertServer({...row,...patch},name,db,[],perms));
 for(const Access of [1,null,undefined])assert.throws(()=>safety.assertServer(row,name,[{...db[0],Access}],[],perms));
 assert.throws(()=>safety.assertServer(row,name,[{...db[0],state:6}],[],perms));
 assert.throws(()=>safety.assertServer(row,name,db,[{name:'remote'}],perms));
 assert.throws(()=>safety.assertServer(row,name,db,[],[...perms,{permission_name:'CONTROL SERVER'}]));
 assert.throws(()=>safety.assertServer(row,name,db,[],perms.filter(p=>p.permission_name!=='VIEW ANY DATABASE')));
});

test('Compras: no confirma respuestas incompletas, ajenas o con dinero convertido a Number',async()=>{
  const d=data(),base={OrdenCompraId:1,Numero:'OC-1',OperacionId:d.OperacionId,Estado:'BORRADOR',Version:Buffer.alloc(8),Total:'30.3750'};
  for(const patch of [{OperacionId:randomUUID()},{Estado:'RECIBIDA'},{Version:Buffer.alloc(4)},{Total:30.375},{Total:undefined},{Numero:'OC-2'},{OrdenCompraId:null}]) {
    const service=createComprasService(async()=>({request(){return {input(){return this;},async execute(){return {recordsets:[[{...base,...patch}]]};}};}}));
    await assert.rejects(service.create(1,d),/incompatible/);
  }
  const service=createComprasService(async()=>({request(){return {input(){return this;},async execute(){return {};}};}}));
  await assert.rejects(service.create(1,d),/incompatible/);
});
test('Compras: lote maximo y permutaciones conservan precision y carga canonica',()=>{
  const d=data();d.Detalle=Array.from({length:100},(_,i)=>({ProductoId:i+1,Cantidad:2147483647,CostoUnitario:'999999999999999.9999'}));
  assert.deepEqual(v.create(d),v.create({...d,Detalle:[...d.Detalle].reverse()}));
  assert.equal(v.create(d).Detalle.length,100);
  assert.deepEqual(v.create({...data(),OperacionId:d.OperacionId,Detalle:[{ProductoId:3,Cantidad:2,CostoUnitario:'10.1'}]}).Detalle,[{ProductoId:3,Cantidad:2,CostoUnitario:'10.1000'}]);
});
test('Compras: script de laboratorio es sintactico y no se ejecuta para validarlo', {skip:process.platform!=='win32'},()=>{
  const {execFileSync}=require('node:child_process');
  // Parser solamente: no dot-source, Invoke-Expression, Docker ni conexion SQL.
  const script=path.join(__dirname,'../scripts/prepareComprasLab.ps1');
  const command="$tokens=$null; $parseErrors=$null; [void][System.Management.Automation.Language.Parser]::ParseFile('"+script.replaceAll("'","''")+"',[ref]$tokens,[ref]$parseErrors); if($parseErrors.Count){throw 'Script de laboratorio invalido'}";
  execFileSync('powershell',['-NoProfile','-NonInteractive','-Command',command],{windowsHide:true,stdio:'pipe'});
  const source=readFileSync(script,'utf8');
  assert.doesNotMatch(source,/docker network|RESTORE DATABASE|DROP DATABASE/i);
  assert.match(source,/Get-Credential/);
  assert.ok(source.indexOf('if(-not $AuthorizeSqlWrites)')<source.indexOf('Get-Credential'));
});
test('Compras: instalador prepara todas las fuentes locales sin conectar SQL',()=>{
  const fs=require('node:fs'),root=path.join(__dirname,'../database'),names=fs.readdirSync(root);
  const full=fs.readFileSync(path.join(root,'SecureFinanceERP_Full.sql'),'utf8'),start=full.indexOf('USE [SecureFinanceERP];');assert.ok(start>0);
  assert.ok(safety.installer(full.slice(start)).length>0);
  for(const n of [...Array.from({length:12},(_,i)=>15+i),...Array.from({length:15},(_,i)=>30+i),50,51,52,53,54,55]){
    const files=names.filter(f=>f.startsWith(n+'_')&&f.endsWith('.sql'));assert.equal(files.length,1,'Migracion unica '+n);
    assert.ok(safety.installer(fs.readFileSync(path.join(root,files[0]),'utf8')).length>0);
  }
});
