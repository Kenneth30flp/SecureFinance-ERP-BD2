'use strict';
const fs=require('fs'),assert=require('assert/strict'),{randomBytes}=require('crypto');const lab=require('../../database/tests/promocionesLab');const state=lab.readState();
const evidence='docs/parte3/integracion-dylan/evidencias';fs.mkdirSync(evidence,{recursive:true});
const clean=s=>s.replace(/\uFEFF/g,'').replaceAll('SecureFinanceERP_Lab_Dylan',state.lab);
async function runFile(file,pre='',post=''){const out=await lab.labQuery(pre+'\n'+clean(fs.readFileSync(file,'utf8'))+'\n'+post);fs.writeFileSync(evidence+'/'+file.split('/').pop()+'.txt',out);console.log('PASS '+file);}
async function main(){
 assert.equal((await lab.labJson('SELECT DB_NAME() N,dbo.P3_INT_Destino() Authorized'))[0].Authorized,state.lab);
 const password='Qa#'+randomBytes(20).toString('base64url');
 await lab.labQuery(`DECLARE @U INT; IF NOT EXISTS(SELECT 1 FROM dbo.Usuario WHERE NombreUsuario=N'P3_DYLAN_QA_ADMIN') BEGIN
 EXEC dbo.sp_RegistrarUsuario N'P3_DYLAN_QA_ADMIN',N'qa.integration@example.invalid',N'${password}',N'QA sintetico integracion',@U OUTPUT;
 INSERT dbo.Usuario_Rol(UsuarioId,RolId) SELECT @U,RolId FROM dbo.Rol WHERE Nombre=N'Administrador';
 UPDATE dbo.Usuario SET DebeCambiarPassword=0 WHERE UsuarioId=@U; END;`);
 if(!fs.existsSync('.data/integration-ui.json'))fs.writeFileSync('.data/integration-ui.json',JSON.stringify({username:'P3_DYLAN_QA_ADMIN',password}));
 const actor=(await lab.labJson("SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'P3_DYLAN_QA_ADMIN'"))[0].UsuarioId;
 await lab.labQuery(`DECLARE @A INT=${actor},@Op UNIQUEIDENTIFIER=NEWID(),@P INT,@Pr INT,@V BINARY(8);
 EXEC sys.sp_set_session_context @key=N'ParteII.Actor',@value=@A;
 SELECT @Pr=ProveedorId FROM dbo.Proveedor WHERE NIT=N'P3BODQA100';
 IF @Pr IS NULL BEGIN INSERT dbo.Proveedor(NIT,Nombre) VALUES(N'P3BODQA100',N'Proveedor sintetico integracion');SET @Pr=SCOPE_IDENTITY(); END;
 IF NOT EXISTS(SELECT 1 FROM dbo.Producto WHERE Codigo=N'P3BOD-QA-100') INSERT dbo.Producto(Codigo,Descripcion,Precio,PrecioCosto,ProveedorId,Stock) VALUES(N'P3BOD-QA-100',N'QA 100 unidades',100,20,@Pr,0);
 SELECT @P=ProductoId,@V=Version FROM dbo.Producto WHERE Codigo=N'P3BOD-QA-100';
 EXEC dbo.sp_AsociarProductoProveedor @A,@P,@Pr,1;
 IF EXISTS(SELECT 1 FROM dbo.Producto WHERE ProductoId=@P AND Stock=0) EXEC dbo.sp_RegistrarMovimientoKardex @ProductoId=@P,@TipoMovimiento='AJUSTE_INGRESO',@Cantidad=100,@ActorUsuarioId=@A,@DocumentoRespaldo=N'QA-FIXTURE',@OperacionId=@Op,@LineaOperacion=1,@Motivo=N'Fixture sintetico',@VersionEsperada=@V;
 IF NOT EXISTS(SELECT 1 FROM dbo.Producto WHERE Codigo=N'P3BOD-QA-COST0') INSERT dbo.Producto(Codigo,Descripcion,Precio,PrecioCosto,ProveedorId,Stock) VALUES(N'P3BOD-QA-COST0',N'QA costo desconocido',100,NULL,@Pr,0);
 SELECT @P=ProductoId FROM dbo.Producto WHERE Codigo=N'P3BOD-QA-COST0'; EXEC dbo.sp_AsociarProductoProveedor @A,@P,@Pr,1;
 IF (SELECT COUNT(*) FROM dbo.P3_BOD_Bodega WHERE Activo=1)<2 BEGIN DECLARE @Bop UNIQUEIDENTIFIER=NEWID(); EXEC dbo.P3_BOD_GuardarBodega @ActorUsuarioId=@A,@OperacionId=@Bop,@BodegaId=NULL,@Nombre=N'QA Destino',@Activo=1,@IsCentral=0,@VersionEsperada=NULL,@Motivo=N'Fixture sintetico'; END;`);
 await runFile('database/79_P3_CRE_PruebasSinteticas.sql');
 const pre=`EXEC sys.sp_set_session_context @key=N'P3_BOD.TestActor',@value=${actor};\nGO\n`;
 await runFile('database/tests/P3_BOD_Transferencias.sql',pre);
 await runFile('database/tests/P3_BOD_Integraciones.sql',pre);
 await runFile('database/tests/AuditoriaDdlLabTests.sql',`EXEC sys.sp_set_session_context @key=N'P3_DDL.LaboratorioConfirmado',@value=N'${state.lab}';EXEC sys.sp_set_session_context @key=N'P3_DDL.TextoExactoAutorizado',@value=N'${state.lab}';BEGIN TRANSACTION;\nGO\n`,'\nROLLBACK;');
 const out=await lab.labQuery('DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;IF EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE Diferencia<>0) THROW 58100,\'Descuadre\',1;');fs.writeFileSync(evidence+'/integridad.txt',out||'CHECKDB/CHECKCONSTRAINTS sin errores; conciliacion global/local/transito sin diferencias.\n');
}
main().catch(e=>{console.error('FAIL',e.message);process.exitCode=1;});
