'use strict';
// NO se importa desde la aplicacion. No carga .env, no acepta destino existente.
// SQL Express: credencial dedicada y preflight obligatorio antes de CREATE DATABASE.
const fs=require('node:fs/promises');
const path=require('node:path');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const sql=require('mssql');
const safety=require('./comprasLabSafety');
const {createComprasService}=require('../../src/modules/compras/service');
async function run() {
  const p=safety.plan(process.env,process.argv.slice(2));
  let admin,lab;
  try {
    admin=await new sql.ConnectionPool(p.config).connect();
    // Read-only effective permissions. Refuse administrator credentials, linked
    // servers and even read access to any previous user database.
    const check=await admin.request().query(`
      SELECT DB_NAME() DatabaseName,CONVERT(nvarchar(128),SERVERPROPERTY('ServerName')) ServerName,
       CONVERT(int,SERVERPROPERTY('EngineEdition')) EngineEdition,IS_SRVROLEMEMBER('sysadmin') Sysadmin,
       (SELECT COUNT(*) FROM sys.login_token WHERE type='SERVER ROLE' AND name<>'public') ServerRoleCount,
       (SELECT COUNT(*) FROM sys.fn_my_permissions(NULL,'DATABASE') WHERE permission_name NOT IN('CONNECT','VIEW DATABASE STATE','VIEW DEFINITION','CREATE DATABASE')) MasterWrites,
       HAS_DBACCESS('model') ModelAccess;
      SELECT name,database_id,state,HAS_DBACCESS(name) Access FROM sys.databases;
      SELECT name FROM sys.servers WHERE server_id<>0;
      SELECT permission_name FROM sys.fn_my_permissions(NULL,'SERVER');
      USE [msdb]; SELECT COUNT(*) N FROM sys.fn_my_permissions(NULL,'DATABASE') WHERE permission_name NOT IN('CONNECT','VIEW DATABASE STATE','VIEW DEFINITION'); USE [master];
    `);
    const row={...check.recordsets[0][0],MsdbWrites:check.recordsets[4][0].N};
    safety.assertServer(row,p.instance,check.recordsets[1],check.recordsets[2],check.recordsets[3]);
    for(const name of ['master','msdb']) {
      const result=await admin.request().query(`USE [${name}];
       SELECT COUNT(*) N FROM sys.objects o CROSS APPLY sys.fn_my_permissions(QUOTENAME(SCHEMA_NAME(o.schema_id))+'.'+QUOTENAME(o.name),'OBJECT') p
       WHERE o.is_ms_shipped=0 AND p.permission_name NOT IN('SELECT','REFERENCES','VIEW DEFINITION'); USE [master];`);
      assert.equal(result.recordset[0].N,0,'Permiso en objeto personalizado de sistema');
    }
    assert.equal((await admin.request().input('Name',sql.NVarChar(128),p.database).query('SELECT DB_ID(@Name) Id')).recordset[0].Id,null);
    // Validate repository installers BEFORE the first write.
    const root=path.join(__dirname,'..'),files=await fs.readdir(root);
    const full=await fs.readFile(path.join(root,'SecureFinanceERP_Full.sql'),'utf8'),start=full.indexOf('USE [SecureFinanceERP];');
    assert.ok(start>0);
    const base=safety.installer(full.slice(start));
    const previous=[];
    for(const n of [...Array.from({length:12},(_,i)=>15+i),...Array.from({length:15},(_,i)=>30+i)]){
      const names=files.filter(f=>f.startsWith(n+'_')&&f.endsWith('.sql'));assert.equal(names.length,1);
      previous.push(safety.installer(await fs.readFile(path.join(root,names[0]),'utf8')));
    }
    const own=[];
    for(let n=50;n<=55;n++){const names=files.filter(f=>f.startsWith(n+'_')&&f.endsWith('.sql'));assert.equal(names.length,1);own.push(safety.batches(await fs.readFile(path.join(root,names[0]),'utf8')));}
    assert.match(p.database,safety.labPattern);
    await admin.request().query(`IF DB_ID(N'${p.database}') IS NOT NULL THROW 55000,'Existing target',1; CREATE DATABASE [${p.database}];`);
    console.log('Base nueva conservada: '+p.database);
    lab=await new sql.ConnectionPool({...p.config,database:p.database}).connect();
    assert.equal((await lab.request().query('SELECT DB_NAME() N')).recordset[0].N,p.database);
    await lab.request().input('Marker',sql.NVarChar(36),p.marker).query("EXEC sys.sp_addextendedproperty @name=N'P3_COM.TestRun',@value=@Marker;");
    const identity=async()=>{const r=(await lab.request().query("SELECT DB_NAME() N,CONVERT(nvarchar(36),value) Marker FROM sys.extended_properties WHERE class=0 AND name=N'P3_COM.TestRun' AND EXISTS(SELECT 1 FROM sys.databases WHERE database_id=DB_ID() AND is_trustworthy_on=0 AND is_db_chaining_on=0)")).recordset[0];safety.assertIdentity(r?.N,p.database,r?.Marker,p.marker);};
    await identity();
    await lab.request().batch('CREATE USER securefinance_app WITHOUT LOGIN;');
    async function install(groups){
      await identity();const tx=new sql.Transaction(lab);await tx.begin();
      try{for(const group of groups)for(const batch of group)await new sql.Request(tx).batch(batch);await tx.commit();}
      catch(e){await tx.rollback().catch(()=>{});throw e;}
    }
    await install([base,...previous]);
    const definitions=async()=>(await lab.request().query("SELECT o.name,m.definition FROM sys.objects o JOIN sys.sql_modules m ON m.object_id=o.object_id WHERE o.name NOT LIKE 'P3_COM[_]%' ORDER BY o.name")).recordset;
    const shared=await definitions();
    await install(own);await install(own);
    assert.deepEqual(await definitions(),shared,'Procedimientos compartidos inalterados');
    await identity();
    await lab.request().batch(`
      DECLARE @V INT; INSERT dbo.Proveedor(NIT,Nombre) VALUES('COM-LAB',N'Proveedor sintetico Compras'); SET @V=SCOPE_IDENTITY();
      INSERT dbo.Producto(Codigo,Descripcion,Precio,Stock,ProveedorId) VALUES('COM-LAB',N'Producto sintetico Compras',200,0,@V);
      INSERT dbo.ProductoProveedor(ProductoId,ProveedorId) VALUES(SCOPE_IDENTITY(),@V);
    `);
    const before=await snapshot(lab);await exercise(lab);assert.deepEqual(await snapshot(lab),before,'Operaciones sin recepcion no alteran inventario');
    await exerciseReceipts(lab);
    assert.deepEqual(await definitions(),shared,'Procedimientos compartidos inalterados');
    await identity();
    console.log('PASS SQL Compras: permisos, aprobacion, importes, recepciones, valoracion, reintentos, concurrencia y rollback.');
  } finally {if(lab)await lab.close();if(admin)await admin.close();}
}
async function snapshot(pool) {
  return (await pool.request().query(`
    SELECT * FROM dbo.Producto ORDER BY ProductoId;
    SELECT * FROM dbo.Proveedor ORDER BY ProveedorId;
    SELECT * FROM dbo.ProductoProveedor ORDER BY ProductoId,ProveedorId;
    SELECT * FROM dbo.Kardex_Inventario ORDER BY KardexId;
    SELECT * FROM dbo.RecepcionCompra ORDER BY RecepcionId;
    SELECT * FROM dbo.DetalleRecepcionCompra ORDER BY RecepcionId,ProductoId;
    SELECT o.name,m.definition FROM sys.objects o JOIN sys.sql_modules m ON m.object_id=o.object_id
    WHERE o.name IN('sp_RegistrarMovimientoKardex','sp_RegistrarRecepcionCompra','sp_ProcesarVentaTransaccional','sp_ERP_ProcesarVenta') ORDER BY o.name;
  `)).recordsets;
}
async function exercise(pool) {
  // Usuarios nuevos con hashes aleatorios sin password utilizable. Catalogos existentes SOLO se leen.
  const suffix=randomUUID().replaceAll('-','').slice(0,12);
  const f=(await pool.request().input('Suffix',sql.NVarChar(12),suffix).query(`
    DECLARE @Creator INT,@Approver INT,@Reader INT,@Role INT;
    INSERT dbo.Usuario(NombreUsuario,NombreCompleto,Correo,PasswordHash) VALUES(CONCAT('COM_C_',@Suffix),N'QA Compras creador',CONCAT(@Suffix,'c@example.invalid'),CRYPT_GEN_RANDOM(64));SET @Creator=SCOPE_IDENTITY();
    INSERT dbo.Usuario(NombreUsuario,NombreCompleto,Correo,PasswordHash) VALUES(CONCAT('COM_A_',@Suffix),N'QA Compras aprobador',CONCAT(@Suffix,'a@example.invalid'),CRYPT_GEN_RANDOM(64));SET @Approver=SCOPE_IDENTITY();
    INSERT dbo.Usuario(NombreUsuario,NombreCompleto,Correo,PasswordHash) VALUES(CONCAT('COM_R_',@Suffix),N'QA Compras lector',CONCAT(@Suffix,'r@example.invalid'),CRYPT_GEN_RANDOM(64));SET @Reader=SCOPE_IDENTITY();
    INSERT dbo.Rol(Nombre) VALUES(CONCAT('COM_C_',@Suffix));SET @Role=SCOPE_IDENTITY();INSERT dbo.Usuario_Rol(UsuarioId,RolId) VALUES(@Creator,@Role);
    INSERT dbo.Rol_Permiso SELECT @Role,PermisoId FROM dbo.Permiso WHERE Codigo IN('COMPRAS_CREAR','COMPRAS_CONSULTAR','COMPRAS_CANCELAR');
    INSERT dbo.Rol(Nombre) VALUES(CONCAT('COM_A_',@Suffix));SET @Role=SCOPE_IDENTITY();INSERT dbo.Usuario_Rol(UsuarioId,RolId) VALUES(@Approver,@Role);
    INSERT dbo.Rol_Permiso SELECT @Role,PermisoId FROM dbo.Permiso WHERE Codigo IN('COMPRAS_APROBAR','COMPRAS_CONSULTAR');
    INSERT dbo.Rol(Nombre) VALUES(CONCAT('COM_R_',@Suffix));SET @Role=SCOPE_IDENTITY();INSERT dbo.Usuario_Rol(UsuarioId,RolId) VALUES(@Reader,@Role);
    INSERT dbo.Rol_Permiso SELECT @Role,PermisoId FROM dbo.Permiso WHERE Codigo='COMPRAS_CONSULTAR';
    SELECT TOP(1) @Creator Creator,@Approver Approver,@Reader Reader,pp.ProveedorId,pp.ProductoId
    FROM dbo.ProductoProveedor pp JOIN dbo.Producto p ON p.ProductoId=pp.ProductoId JOIN dbo.Proveedor v ON v.ProveedorId=pp.ProveedorId
    WHERE pp.Activo=1 AND p.Activo=1 AND v.Activo=1 ORDER BY pp.ProveedorId,pp.ProductoId;
  `)).recordset[0];
  assert.ok(f,'El laboratorio requiere una relacion comercial activa');
  // Pruebas con permisos SQL efectivos del usuario de aplicacion y REVERT garantizado.
  const allowed=new Set(['dbo.P3_COM_Crear','dbo.P3_COM_Consultar','dbo.P3_COM_ConsultarHistorial','dbo.P3_COM_EnviarAprobacion','dbo.P3_COM_Aprobar','dbo.P3_COM_Cancelar']);
  const asApp=target=>async()=>({request(){const request=new sql.Request(target),names=[];return {
    input(name,type,value){assert.match(name,/^[A-Za-z]+$/);names.push(name);request.input(name,type,value);return this;},
    execute(procedure){assert.ok(allowed.has(procedure));return request.query(`EXECUTE AS USER='securefinance_app'; BEGIN TRY EXEC ${procedure} ${names.map(n=>'@'+n+'=@'+n).join(',')}; REVERT; END TRY BEGIN CATCH REVERT; THROW; END CATCH;`);}
  };}});
  const provider=asApp(pool);
  const service=createComprasService(provider);
  const d={ProveedorId:f.ProveedorId,OperacionId:randomUUID(),Observaciones:"QA literal '; DROP TABLE Producto;--",Detalle:[{ProductoId:f.ProductoId,Cantidad:3,CostoUnitario:'10.1250'}]};
  const [a,b]=await Promise.all([service.create(f.Creator,d),service.create(f.Creator,d)]);
  assert.equal(a.OrdenCompraId,b.OrdenCompraId);assert.equal(a.Total,'30.3750');
  await assert.rejects(service.create(f.Creator,{...d,Observaciones:'otro contenido'}),e=>e.number===55003);
  await assert.rejects(service.create(f.Reader,{...d,OperacionId:randomUUID()}),e=>e.number===54101);
  const change=(row)=>({OrdenCompraId:row.OrdenCompraId,Version:row.Version,OperacionId:randomUUID(),Motivo:'QA etapa 1'});
  await assert.rejects(service.approve(f.Approver,change(a)),e=>e.number===55005);
  const send=change(a),pending=await service.send(f.Creator,send);
  assert.deepEqual(await service.send(f.Creator,send),pending);
  await assert.rejects(service.cancel(f.Creator,change(a)),e=>e.number===55003);
  await assert.rejects(service.approve(f.Creator,change(pending)),e=>e.number===54101);
  // Incluso con el permiso independiente, no se permite autoaprobacion.
  await pool.request().input('Actor',sql.Int,f.Creator).query("INSERT dbo.Rol_Permiso SELECT ur.RolId,p.PermisoId FROM dbo.Usuario_Rol ur CROSS JOIN dbo.Permiso p WHERE ur.UsuarioId=@Actor AND p.Codigo='COMPRAS_APROBAR'");
  await assert.rejects(service.approve(f.Creator,change(pending)),e=>e.number===55001);
  const outcomes=await Promise.allSettled([service.approve(f.Approver,change(pending)),service.cancel(f.Creator,change(pending))]);
  assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);
  assert.equal(outcomes.find(x=>x.status==='rejected').reason.number,55003);
  const history=await service.history(f.Reader,a.OrdenCompraId);assert.equal(history.length,3);
  assert.equal(history[0].EstadoNuevo,'BORRADOR');assert.equal(history[1].EstadoNuevo,'PENDIENTE_APROBACION');
  const detail=await service.detail(f.Reader,a.OrdenCompraId);assert.equal(detail.detalle[0].Subtotal,'30.3750');
  assert.deepEqual(await service.create(f.Creator,d),a,'Reintento devuelve la creacion original');
  const audit=(await pool.request().input('Id',sql.Int,a.OrdenCompraId).query("SELECT COUNT(*) N FROM dbo.Bitacora_Transacciones WHERE TablaAfectada='P3_COM_OrdenCompra' AND IdentificadorRegistro=CONVERT(nvarchar(20),@Id)")).recordset[0];assert.equal(audit.N,3);
  const second=await service.create(f.Creator,{...d,OperacionId:randomUUID()});
  assert.notEqual(second.Numero,a.Numero);
  const secondPending=await service.send(f.Creator,change(second));
  const approve=change(secondPending),approved=await service.approve(f.Approver,approve);
  assert.equal(approved.Estado,'APROBADA');assert.deepEqual(await service.approve(f.Approver,approve),approved);
  const cancel=change(approved),cancelled=await service.cancel(f.Creator,cancel);
  assert.equal(cancelled.Estado,'CANCELADA');assert.deepEqual(await service.cancel(f.Creator,cancel),cancelled);
  await assert.rejects(service.send(f.Creator,change(cancelled)),e=>e.number===55005);
  // Ni siquiera DML administrativo puede habilitar recepcion o reescribir contenido.
  await assert.rejects(pool.request().input('Id',sql.Int,second.OrdenCompraId).query("UPDATE dbo.P3_COM_OrdenCompra SET Estado='RECIBIDA' WHERE OrdenCompraId=@Id"),e=>e.number===55005);
  await assert.rejects(pool.request().input('Id',sql.Int,second.OrdenCompraId).query('UPDATE dbo.P3_COM_DetalleOrdenCompra SET Cantidad=2 WHERE OrdenCompraId=@Id'),e=>e.number===55005);
  for(const statement of ['SELECT * FROM dbo.P3_COM_OrdenCompra',"UPDATE dbo.P3_COM_OrdenCompra SET Estado='RECIBIDA'",'EXEC dbo.P3_COM_Transicionar 1,1,NULL,NULL,NULL,NULL']) {
    await assert.rejects(pool.request().query(`EXECUTE AS USER='securefinance_app'; BEGIN TRY ${statement}; REVERT; END TRY BEGIN CATCH REVERT; THROW; END CATCH;`),e=>e.number===229);
  }
  // Validacion SQL independiente de Node: cantidades fraccionarias, costo redondeable y duplicados.
  for(const lines of [[{ProductoId:f.ProductoId,Cantidad:1.5,CostoUnitario:'1'}],[{ProductoId:f.ProductoId,Cantidad:1,CostoUnitario:'1.00001'}],[...d.Detalle,...d.Detalle]]) {
    const request=(await provider()).request().input('ActorUsuarioId',sql.Int,f.Creator).input('ProveedorId',sql.Int,f.ProveedorId)
      .input('Detalle',sql.NVarChar(sql.MAX),JSON.stringify(lines)).input('OperacionId',sql.UniqueIdentifier,randomUUID());
    await assert.rejects(request.execute('dbo.P3_COM_Crear'),e=>e.number===55002);
  }
  const failed=randomUUID();
  await assert.rejects(service.create(f.Creator,{...d,OperacionId:failed,Detalle:[...d.Detalle,{ProductoId:2147483647,Cantidad:1,CostoUnitario:'1'}]}),e=>e.number===55004);
  const noEvent=(await pool.request().input('Op',sql.UniqueIdentifier,failed).query('SELECT COUNT(*) N FROM dbo.P3_COM_HistorialEstado WHERE OperacionId=@Op')).recordset[0];assert.equal(noEvent.N,0);
  // Numeracion y operaciones distintas concurrentes. Igual contenido con UUID
  // distinto es una orden nueva legitima, no deduplicacion comercial por importe.
  const simultaneous=await Promise.all(Array.from({length:6},()=>service.create(f.Creator,{...d,OperacionId:randomUUID()})));
  assert.equal(new Set(simultaneous.map(r=>r.Numero)).size,6);
  assert.equal(new Set(simultaneous.map(r=>r.OrdenCompraId)).size,6);
  // Importes extremos: no permitir redondeo ni conversion JS a Number.
  const max=await service.create(f.Creator,{...d,OperacionId:randomUUID(),Detalle:[{ProductoId:f.ProductoId,Cantidad:2147483647,CostoUnitario:'999999999999999.9999'}]});
  const exact=2147483647n*9999999999999999999n;
  assert.equal(max.Total,(exact/10000n).toString()+'.'+(exact%10000n).toString().padStart(4,'0'));
  const zero=await service.create(f.Creator,{...d,OperacionId:randomUUID(),Detalle:[{ProductoId:f.ProductoId,Cantidad:1,CostoUnitario:'0'}]});assert.equal(zero.Total,'0.0000');
  // Mutaciones temporales SOLO en copia: mismo contexto transaccional, rollback.
  for(const mutate of [
    'UPDATE dbo.Proveedor SET Activo=0 WHERE ProveedorId=@Supplier',
    'UPDATE dbo.Producto SET Activo=0 WHERE ProductoId=@Product',
    'UPDATE dbo.ProductoProveedor SET Activo=0 WHERE ProveedorId=@Supplier AND ProductoId=@Product',
    'DELETE dbo.ProductoProveedor WHERE ProveedorId=@Supplier AND ProductoId=@Product',
  ]) {
    const tx=new sql.Transaction(pool);await tx.begin();
    try {
      await new sql.Request(tx).input('Supplier',sql.Int,f.ProveedorId).input('Product',sql.Int,f.ProductoId).query(mutate);
      await assert.rejects(createComprasService(asApp(tx)).create(f.Creator,{...d,OperacionId:randomUUID()}),e=>e.number===55004);
    } finally {await tx.rollback().catch(()=>{});}
  }
  // Revocacion vigente en SQL aunque el consumidor conserve permisos en sesion.
  const authTx=new sql.Transaction(pool);await authTx.begin();
  try {
    await new sql.Request(authTx).input('Actor',sql.Int,f.Creator).query('UPDATE dbo.Usuario SET Activo=0 WHERE UsuarioId=@Actor');
    await assert.rejects(createComprasService(asApp(authTx)).create(f.Creator,{...d,OperacionId:randomUUID()}),e=>e.number===54101);
  } finally {await authTx.rollback().catch(()=>{});}
  // Revalidacion al aprobar: el proveedor puede inactivarse tras el envio.
  const sent=await service.send(f.Creator,change(simultaneous[0]));
  const approvalTx=new sql.Transaction(pool);await approvalTx.begin();
  try {
    await new sql.Request(approvalTx).input('Supplier',sql.Int,f.ProveedorId).query('UPDATE dbo.Proveedor SET Activo=0 WHERE ProveedorId=@Supplier');
    await assert.rejects(createComprasService(asApp(approvalTx)).approve(f.Approver,change(sent)),e=>e.number===55004);
  } finally {await approvalTx.rollback().catch(()=>{});}
  // Error despues de insertar cabecera: comprobar rollback completo, no solo
  // rechazo de validacion anterior a cualquier escritura.
  const before=(await pool.request().query('SELECT COUNT(*) N FROM dbo.P3_COM_OrdenCompra')).recordset[0].N;
  await pool.request().batch("CREATE TRIGGER dbo.P3_COM_QA_Fallo ON dbo.P3_COM_DetalleOrdenCompra AFTER INSERT AS THROW 55009,'Fallo de ensayo',1;");
  try {await assert.rejects(service.create(f.Creator,{...d,OperacionId:randomUUID()}),e=>e.number===55009);}
  finally {await pool.request().batch('DROP TRIGGER dbo.P3_COM_QA_Fallo;');}
  assert.equal((await pool.request().query('SELECT COUNT(*) N FROM dbo.P3_COM_OrdenCompra')).recordset[0].N,before);
  // Denegaciones de columna: protegen incluso con GRANT heredado de un rol.
  await pool.request().batch('CREATE ROLE P3_COM_QA_Columna; GRANT UPDATE ON dbo.P3_COM_OrdenCompra(Estado) TO P3_COM_QA_Columna; ALTER ROLE P3_COM_QA_Columna ADD MEMBER securefinance_app;');
  await assert.rejects(pool.request().query("EXECUTE AS USER='securefinance_app'; BEGIN TRY UPDATE dbo.P3_COM_OrdenCompra SET Estado='APROBADA'; REVERT; END TRY BEGIN CATCH REVERT; THROW; END CATCH;"),e=>e.number===229);
}
async function exerciseReceipts(pool){
  const f=(await pool.request().query(`
   DECLARE @C INT=(SELECT MIN(UsuarioId) FROM dbo.Usuario WHERE NombreUsuario LIKE 'COM_C_%'),@A INT=(SELECT MIN(UsuarioId) FROM dbo.Usuario WHERE NombreUsuario LIKE 'COM_A_%');
   INSERT dbo.Rol_Permiso SELECT ur.RolId,p.PermisoId FROM dbo.Usuario_Rol ur CROSS JOIN dbo.Permiso p WHERE ur.UsuarioId=@C
    AND p.Codigo IN('COMPRAS_RECIBIR','INVENTARIO_REGISTRAR','INVENTARIO_APERTURAR','INVENTARIO_AJUSTAR','VENTAS_REGISTRAR','DEVOLUCIONES_REGISTRAR','DEVOLUCIONES_AUTORIZAR')
    AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=ur.RolId AND rp.PermisoId=p.PermisoId);
   DECLARE @Opening UNIQUEIDENTIFIER=NEWID();
   EXEC dbo.sp_AbrirKardexInventario @Opening,@C,N'QA nuevo laboratorio',N'Apertura cero sintetica';
   EXEC dbo.sp_HabilitarKardexInventario @Opening,@C;
   SELECT TOP(1) @C Creator,@A Approver,p.ProductoId,p.ProveedorId FROM dbo.Producto p WHERE p.Codigo='COM-LAB';
  `)).recordsets.at(-1)[0];
  const allowed=new Set(['Crear','EnviarAprobacion','Aprobar','Recibir','Consultar','ConsultarHistorial','ActualizarValoracion','ConsultarValoracion'].map(n=>'dbo.P3_COM_'+n));
  const provider=async()=>({request(){const request=pool.request(),names=[];return{input(n,t,v){assert.match(n,/^[A-Za-z]+$/);names.push(n);request.input(n,t,v);return this;},execute(proc){assert.ok(allowed.has(proc));return request.query(`EXECUTE AS USER='securefinance_app'; BEGIN TRY EXEC ${proc} ${names.map(n=>'@'+n+'=@'+n).join(',')}; REVERT; END TRY BEGIN CATCH REVERT; THROW; END CATCH;`);}};}});
  const service=createComprasService(provider),change=row=>({OrdenCompraId:row.OrdenCompraId,OperacionId:randomUUID(),Version:row.Version,Motivo:'Ensayo aislado'});
  async function order(q=20){const draft=await service.create(f.Creator,{ProveedorId:f.ProveedorId,OperacionId:randomUUID(),Detalle:[{ProductoId:f.ProductoId,Cantidad:q,CostoUnitario:'110'}]});return service.approve(f.Approver,change(await service.send(f.Creator,change(draft))));}
  const approved=await order(),body={...change(approved),DocumentoRespaldo:'QA-001',Detalle:[{ProductoId:f.ProductoId,Cantidad:10,CostoUnitario:'100'}]};
  const before=(await snapshot(pool));
  await assert.rejects(service.receive(f.Approver,body),e=>e.number===54101);
  await assert.rejects(service.receive(f.Creator,{...body,Detalle:[{ProductoId:f.ProductoId,Cantidad:21,CostoUnitario:'100'}]}),e=>e.number===55006);
  assert.deepEqual(await snapshot(pool),before,'Rechazos no alteran existencias');
  const [first,retry]=await Promise.all([service.receive(f.Creator,body),service.receive(f.Creator,body)]);assert.deepEqual(first,retry);assert.equal(first.Estado,'PARCIALMENTE_RECIBIDA');
  assert.equal((await service.detail(f.Creator,first.OrdenCompraId)).detalle[0].Pendiente,'10');
  let value=await service.refreshValuation(f.Creator,f.ProductoId);assert.equal(value.Promedio,'100.00000000');assert.equal(value.Stock,10);
  const finalBody={...change(first),DocumentoRespaldo:'QA-002',Detalle:[{ProductoId:f.ProductoId,Cantidad:10,CostoUnitario:'120'}]};
  const competing=await Promise.allSettled([service.receive(f.Creator,finalBody),service.receive(f.Creator,{...finalBody,OperacionId:randomUUID()})]);
  assert.equal(competing.filter(r=>r.status==='fulfilled').length,1);assert.equal(competing.find(r=>r.status==='rejected').reason.number,55003);
  const received=competing.find(r=>r.status==='fulfilled').value;assert.equal(received.Estado,'RECIBIDA');
  assert.equal((await service.detail(f.Creator,received.OrdenCompraId)).recepciones.length,2);
  value=await service.refreshValuation(f.Creator,f.ProductoId);assert.equal(value.Promedio,'110.00000000');assert.equal(value.Valor,'2200.00000000');assert.equal(value.Stock,20);
  const history=await service.valuation(f.Creator,f.ProductoId);await service.refreshValuation(f.Creator,f.ProductoId);assert.deepEqual(await service.valuation(f.Creator,f.ProductoId),history);
  const sale=(await pool.request().input('Actor',sql.Int,f.Creator).input('P',sql.Int,f.ProductoId).query(`
   INSERT dbo.Cliente(NIT,Nombre) VALUES('COM-LAB',N'Cliente sintetico');
   DECLARE @Client INT=SCOPE_IDENTITY(),@F INT,@Lines dbo.TipoDetalleVentaDescuento;
   INSERT @Lines VALUES(@P,4,0);
   EXEC dbo.sp_ProcesarVentaTransaccional @ClienteId=@Client,@UsuarioId=@Actor,@Detalle=@Lines,@FacturaId=@F OUTPUT;
   SELECT @F FacturaId,(SELECT DetalleFacturaId FROM dbo.DetalleFactura WHERE FacturaId=@F AND ProductoId=@P) DetalleFacturaId;
  `)).recordsets.at(-1)[0];
  value=await service.refreshValuation(f.Creator,f.ProductoId);assert.equal(value.Stock,16);assert.equal(value.Valor,'1760.00000000');assert.equal(value.Promedio,'110.00000000');
  await pool.request().input('Actor',sql.Int,f.Creator).input('F',sql.Int,sale.FacturaId).input('Op',sql.UniqueIdentifier,randomUUID()).input('Lines',sql.NVarChar(sql.MAX),JSON.stringify([{DetalleFacturaId:sale.DetalleFacturaId,Cantidad:2,Reingresar:true}])).query("EXEC dbo.sp_ProcesarDevolucionCliente @Actor,@F,@Op,N'QA devolucion',@Lines;");
  value=await service.refreshValuation(f.Creator,f.ProductoId);assert.equal(value.Stock,18);assert.equal(value.Valor,'1980.00000000');assert.equal(value.Promedio,'110.00000000');
  await pool.request().input('Actor',sql.Int,f.Creator).input('P',sql.Int,f.ProductoId).query("DECLARE @Op uniqueidentifier=NEWID(); EXEC dbo.sp_RegistrarMovimientoKardex @P,'AJUSTE_EGRESO',1,@Actor,N'QA ajuste salida',@Op,1,N'Ensayo';");
  value=await service.refreshValuation(f.Creator,f.ProductoId);assert.equal(value.Stock,17);assert.equal(value.Valor,'1870.00000000');
  await assert.rejects(service.receive(f.Creator,{...change(received),DocumentoRespaldo:'QA-extra',Detalle:body.Detalle}),e=>e.number===55005);
  // Fail AFTER the shared receipt changed stock: outer transaction must undo ALL.
  const rollbackOrder=await order(1),rollbackBody={...change(rollbackOrder),DocumentoRespaldo:'QA-rollback',Detalle:[{ProductoId:f.ProductoId,Cantidad:1,CostoUnitario:'0.1234'}]};
  const stockBefore=await snapshot(pool);
  await pool.request().batch("CREATE TRIGGER dbo.P3_COM_QA_Recepcion ON dbo.P3_COM_AplicacionRecepcion AFTER INSERT AS THROW 55009,'Failure after stock',1;");
  try{await assert.rejects(service.receive(f.Creator,rollbackBody),e=>e.number===55009);}finally{await pool.request().batch('DROP TRIGGER dbo.P3_COM_QA_Recepcion;');}
  assert.deepEqual(await snapshot(pool),stockBefore,'Rollback de stock, Kardex, recepcion y detalle');
  assert.equal((await service.detail(f.Creator,rollbackOrder.OrdenCompraId)).orden.Estado,'APROBADA');
  await service.receive(f.Creator,rollbackBody);
  const precise=(await pool.request().query("SELECT CONVERT(varchar(25),a.CostoDocumentado) C,d.CostoUnitario Legacy FROM dbo.P3_COM_AplicacionRecepcion a JOIN dbo.DetalleRecepcionCompra d ON d.KardexId=a.KardexId WHERE a.CostoDocumentado=0.1234")).recordset[0];assert.equal(precise.C,'0.1234');assert.equal(precise.Legacy,null);
  // Missing documented incoming adjustment must invalidate, never use PrecioCosto.
  await pool.request().input('Actor',sql.Int,f.Creator).input('P',sql.Int,f.ProductoId).query("DECLARE @Op uniqueidentifier=NEWID(); EXEC dbo.sp_RegistrarMovimientoKardex @P,'AJUSTE_INGRESO',1,@Actor,N'QA ajuste sin costo',@Op,1,N'Ensayo';");
  value=await service.refreshValuation(f.Creator,f.ProductoId);assert.equal(value.Completa,false);assert.equal(value.Promedio,null);assert.equal(value.Valor,null);
  // Full legacy DECIMAL(19,2) domain: do not overflow the auxiliary ledger.
  await pool.request().input('Actor',sql.Int,f.Creator).input('P',sql.Int,f.ProductoId).query(`
   DECLARE @Q INT=(SELECT Stock FROM dbo.Producto WHERE ProductoId=@P),@Op UNIQUEIDENTIFIER=NEWID();
   EXEC dbo.sp_RegistrarMovimientoKardex @P,'AJUSTE_EGRESO',@Q,@Actor,N'QA saldo cero',@Op,1,N'Ensayo';
  `);
  value=await service.refreshValuation(f.Creator,f.ProductoId);assert.equal(value.Stock,0);assert.equal(value.Completa,true);
  await pool.request().input('Actor',sql.Int,f.Creator).input('P',sql.Int,f.ProductoId).input('V',sql.Int,f.ProveedorId).query("DECLARE @Op UNIQUEIDENTIFIER=NEWID(); EXEC dbo.sp_RegistrarRecepcionCompra @Actor,@P,@V,1,N'QA costo legacy extremo',N'Ensayo',@Op,99999999999999999.99;");
  value=await service.refreshValuation(f.Creator,f.ProductoId);assert.equal(value.Promedio,'99999999999999999.99000000');assert.equal(value.Valor,value.Promedio);
  for(const statement of ['SELECT * FROM dbo.P3_COM_Valoracion','DELETE dbo.P3_COM_AplicacionRecepcion','UPDATE dbo.P3_COM_RecepcionOrden SET Motivo=N\'changed\''])await assert.rejects(pool.request().query(`EXECUTE AS USER='securefinance_app'; BEGIN TRY ${statement}; REVERT; END TRY BEGIN CATCH REVERT; THROW; END CATCH;`),e=>e.number===229);
}
if(require.main===module) run().catch(error=>{console.error('Compras SQL no completado:',error.number || error.code || error.message);process.exitCode=1;});
module.exports={run,exercise};
