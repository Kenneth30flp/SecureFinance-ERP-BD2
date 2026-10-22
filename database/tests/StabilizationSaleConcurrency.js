'use strict';
const {run}=require('./StabilizationConcurrency');
const {randomUUID}=require('node:crypto');
const fs=require('node:fs');
async function main(){
 const op=randomUUID();
 const query=`DECLARE @a INT=(SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario='admin'),@p INT=(SELECT ProductoId FROM dbo.Producto WHERE Codigo='DEMO-CABLE'),@c INT=(SELECT MIN(ClienteId) FROM dbo.Cliente WHERE Activo=1);DECLARE @d dbo.TipoDetalleVentaDescuento;INSERT @d VALUES(@p,1,0);EXECUTE AS USER='securefinance_app';EXEC dbo.sp_ERP_ProcesarVenta @c,@a,@d,'${op}';REVERT;`;
 await Promise.all([run(query),run(query)]);
 await run(`DECLARE @f INT=(SELECT FacturaId FROM dbo.SolicitudVentaERP WHERE OperacionId='${op}');IF @f IS NULL OR (SELECT COUNT(*) FROM dbo.MovimientoCaja WHERE FacturaId=@f)<>1 OR (SELECT COUNT(*) FROM dbo.DetalleFactura d JOIN dbo.Kardex_Inventario k ON k.DetalleFacturaId=d.DetalleFacturaId WHERE d.FacturaId=@f)<>1 THROW 54900,'Concurrent sale duplicated',1;`);
 const message='PASS concurrent identical sale: one invoice, one cash movement, one Kardex';console.log(message);fs.writeFileSync('.data/stabilization-sale-concurrency.txt',message+'\n');
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
