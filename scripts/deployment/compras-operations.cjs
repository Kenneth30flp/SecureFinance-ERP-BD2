'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert/strict'),d=require('./compras-upgrade.cjs');
// All fixtures, temporary grants and documents are inside rollback transactions.
// No accounts, passwords or hashes are created/read/changed.
const fixture=`
DECLARE @C INT=(SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario=N'admin'),
 @A INT=(SELECT TOP(1) UsuarioId FROM dbo.Usuario WHERE Activo=1 AND NombreUsuario<>N'admin' ORDER BY UsuarioId),@Role INT;
IF @C IS NULL OR @A IS NULL THROW 59910,'Two existing independent actors required',1;
SELECT TOP(1) @Role=RolId FROM dbo.Usuario_Rol WHERE UsuarioId=@A;
IF @Role IS NULL THROW 59910,'Independent actor has no existing role',1;
INSERT dbo.Rol_Permiso(RolId,PermisoId) SELECT @Role,PermisoId FROM dbo.Permiso p WHERE Codigo='COMPRAS_APROBAR'
 AND NOT EXISTS(SELECT 1 FROM dbo.Rol_Permiso rp WHERE rp.RolId=@Role AND rp.PermisoId=p.PermisoId);
DECLARE @Supplier INT=(SELECT TOP(1) ProveedorId FROM dbo.Proveedor WHERE Activo=1 ORDER BY ProveedorId),@P INT,@N INT,@V BINARY(8),@Op UNIQUEIDENTIFIER=NEWID(),@Lines NVARCHAR(MAX);
INSERT dbo.Producto(Codigo,Descripcion,Precio,PrecioCosto,ProveedorId,Stock) VALUES(CONCAT('REV-',LEFT(CONVERT(VARCHAR(36),NEWID()),20)),N'Ensayo reversible Compras',200,NULL,@Supplier,0);
SET @P=SCOPE_IDENTITY();INSERT dbo.ProductoProveedor(ProductoId,ProveedorId) VALUES(@P,@Supplier);
SET @Lines=(SELECT @P ProductoId,20 Cantidad,'110.0000' CostoUnitario FOR JSON PATH);
EXECUTE AS USER='securefinance_app';
EXEC dbo.P3_COM_Crear @ActorUsuarioId=@C,@ProveedorId=@Supplier,@Detalle=@Lines,@OperacionId=@Op;
REVERT;
SELECT @N=OrdenCompraId,@V=Version FROM dbo.P3_COM_OrdenCompra WHERE CreadorUsuarioId=@C AND ProveedorId=@Supplier AND OrdenCompraId=(SELECT MAX(OrdenCompraId) FROM dbo.P3_COM_OrdenCompra);
SET @Op=NEWID();EXECUTE AS USER='securefinance_app';
EXEC dbo.P3_COM_EnviarAprobacion @C,@N,@Op,@V,N'Ensayo con rollback'; REVERT;
SELECT @V=Version FROM dbo.P3_COM_OrdenCompra WHERE OrdenCompraId=@N;
`;
const success=fixture+`
SET @Op=NEWID(); EXECUTE AS USER='securefinance_app'; EXEC dbo.P3_COM_Aprobar @A,@N,@Op,@V,N'Aprobador independiente'; REVERT;
SELECT @V=Version FROM dbo.P3_COM_OrdenCompra WHERE OrdenCompraId=@N;
SET @Lines=(SELECT @P ProductoId,10 Cantidad,'100.0000' CostoUnitario FOR JSON PATH); SET @Op=NEWID();
EXECUTE AS USER='securefinance_app';EXEC dbo.P3_COM_Recibir @C,@N,@Op,@V,N'REV-PARCIAL',N'Rollback',@Lines;
EXEC dbo.P3_COM_Recibir @C,@N,@Op,@V,N'REV-PARCIAL',N'Rollback',@Lines; REVERT;
IF NOT EXISTS(SELECT 1 FROM dbo.P3_COM_OrdenCompra WHERE OrdenCompraId=@N AND Estado='PARCIALMENTE_RECIBIDA') THROW 59910,'Partial receipt failed',1;
IF (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>10 THROW 59910,'Replay duplicated stock',1;
EXECUTE AS USER='securefinance_app';EXEC dbo.P3_COM_ActualizarValoracion @C,@P;REVERT;
IF NOT EXISTS(SELECT 1 FROM dbo.P3_COM_Valoracion WHERE ProductoId=@P AND StockResultante=10 AND ValorResultante=1000 AND PromedioResultante=100 AND Completa=1) THROW 59910,'Partial valuation failed',1;
SELECT @V=Version FROM dbo.P3_COM_OrdenCompra WHERE OrdenCompraId=@N;
SET @Lines=(SELECT @P ProductoId,10 Cantidad,'120.0000' CostoUnitario FOR JSON PATH); SET @Op=NEWID();
EXECUTE AS USER='securefinance_app';EXEC dbo.P3_COM_Recibir @C,@N,@Op,@V,N'REV-COMPLETA',N'Rollback',@Lines;
EXEC dbo.P3_COM_ActualizarValoracion @C,@P;EXEC dbo.P3_COM_ConsultarValoracion @C,@P;EXEC dbo.P3_COM_Consultar @C,@N;EXEC dbo.P3_COM_ConsultarHistorial @C,@N;REVERT;
IF NOT EXISTS(SELECT 1 FROM dbo.P3_COM_OrdenCompra WHERE OrdenCompraId=@N AND Estado='RECIBIDA') THROW 59910,'Full receipt failed',1;
IF NOT EXISTS(SELECT 1 FROM dbo.P3_COM_Valoracion WHERE ProductoId=@P AND StockResultante=20 AND ValorResultante=2200 AND PromedioResultante=110 AND Completa=1) THROW 59910,'Full valuation failed',1;
IF (SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE ProductoId=@P AND TipoMovimiento='COMPRA')<>2 THROW 59910,'Kardex failed',1;
IF (SELECT COUNT(*) FROM dbo.P3_BOD_Ledger WHERE ProductoId=@P AND Tipo='COMPRA')<>2 THROW 59910,'Warehouse ledger failed',1;
IF (SELECT Cantidad FROM dbo.P3_BOD_Stock WHERE ProductoId=@P AND BodegaId=(SELECT CentralId FROM dbo.P3_BOD_Configuracion WHERE ConfiguracionId=1))<>20 THROW 59910,'Central stock failed',1;
IF EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE Diferencia<>0) THROW 59910,'Warehouse mismatch',1;
SET @Lines=(SELECT @P ProductoId,1 Cantidad,'0.1234' CostoUnitario FOR JSON PATH);SET @Op=NEWID();
EXECUTE AS USER='securefinance_app';EXEC dbo.P3_COM_Crear @C,@Supplier,@Lines,@Op; REVERT;
SELECT TOP(1) @N=OrdenCompraId,@V=Version FROM dbo.P3_COM_OrdenCompra ORDER BY OrdenCompraId DESC;
SET @Op=NEWID();EXECUTE AS USER='securefinance_app';EXEC dbo.P3_COM_Cancelar @C,@N,@Op,@V,N'Cancelacion reversible'; REVERT;
IF NOT EXISTS(SELECT 1 FROM dbo.P3_COM_OrdenCompra WHERE OrdenCompraId=@N AND Estado='CANCELADA') THROW 59910,'Cancellation failed',1;
IF (SELECT Stock FROM dbo.Producto WHERE ProductoId=@P)<>20 THROW 59910,'Cancellation changed stock',1;
`;
async function run(db){
 const s=d.state();assert(db===s.clone||db===s.source);
 if(db===s.clone){s.operationsPassed=false;s.fiveModulesPassed=false;}else s.productionOperationsPassed=false;d.save(s);
 const perms=await d.query("SELECT p.Codigo FROM dbo.Rol r JOIN dbo.Rol_Permiso rp ON rp.RolId=r.RolId JOIN dbo.Permiso p ON p.PermisoId=rp.PermisoId WHERE r.Nombre=N'Administrador' AND p.Codigo LIKE 'COMPRAS[_]%'",db);assert.equal(perms.length,5);
 const run=async(name,sql)=>{const out=await d.exec(d.capture+'\nGO\nBEGIN TRANSACTION;\n'+sql+'\nGO\nROLLBACK;\nGO\n'+d.preserve,db);fs.writeFileSync(path.join(d.privateDir,name+'-'+(db===s.source?'original':'copy')+'.txt'),out);};
 await run('operations',success);
 // Expected procedure errors deliberately roll back the whole transaction.
 for(const [name,action,number] of [
 ['self-approval',"EXEC dbo.P3_COM_Aprobar @C,@N,@Op,@V,N'Autoaprobacion prohibida'",55001],
 ['over-receipt',"EXEC dbo.P3_COM_Aprobar @A,@N,@Op,@V,N'Independiente'; REVERT; SELECT @V=Version FROM dbo.P3_COM_OrdenCompra WHERE OrdenCompraId=@N;SET @Lines=(SELECT @P ProductoId,21 Cantidad,'100' CostoUnitario FOR JSON PATH);SET @Op=NEWID();EXECUTE AS USER='securefinance_app';EXEC dbo.P3_COM_Recibir @C,@N,@Op,@V,N'Exceso',N'Rechazo',@Lines",55006],
 ['stale-version',"SET @V=0x0000000000000000;EXEC dbo.P3_COM_Cancelar @C,@N,@Op,@V,N'Version obsoleta'",55003],
 ['cancel-permission',"EXEC dbo.P3_COM_Cancelar @A,@N,@Op,@V,N'Sin permiso de cancelar'",54101],
 ['receive-permission',"EXEC dbo.P3_COM_Recibir @A,@N,@Op,@V,N'Sin permiso',N'Rechazo',@Lines",54101],
 ['table-protection',"EXEC(N'SELECT * FROM dbo.P3_COM_OrdenCompra')",229]
 ]){
 const script=d.capture+'\nGO\nBEGIN TRY BEGIN TRANSACTION;\n'+fixture+`SET @Op=NEWID();EXECUTE AS USER='securefinance_app';${action};REVERT;IF @@TRANCOUNT>0 ROLLBACK;THROW 59910,'Expected rejection absent',1;
 END TRY BEGIN CATCH IF XACT_STATE()<>0 ROLLBACK;IF USER_NAME()='securefinance_app' REVERT;IF ERROR_NUMBER()<>${number} THROW;END CATCH;\nGO\n`+d.preserve;
 fs.writeFileSync(path.join(d.privateDir,name+'-'+(db===s.source?'original':'copy')+'.txt'),await d.exec(script,db));
 }
 await d.integrity(db);
 if(db===s.clone){await require('./validate-original.cjs').validate(db,{state:s,persist:false});s.operationsPassed=true;s.fiveModulesPassed=true;}else s.productionOperationsPassed=true;
 s[db===s.clone?'rehearsalChecksAt':'productionChecksAt']=new Date().toISOString();d.save(s);
 console.log('PASS creation, independent approval, self-approval denial, cancellation, partial/full receipt, replay, excess/stale denial, Kardex, valuation, Multibodega; all fixtures/grants/documents rolled back: '+db);
}
module.exports={run};if(require.main===module)run(process.argv[2]==='original'?d.state().source:d.state().clone).catch(e=>{console.error('BLOCKED',e.message);process.exitCode=1;});
