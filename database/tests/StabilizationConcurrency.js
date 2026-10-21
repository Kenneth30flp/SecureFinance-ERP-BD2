'use strict';
// Connections use Windows authentication. Only the explicitly restored laboratory is accepted.
const {spawn}=require('node:child_process');
const {randomUUID}=require('node:crypto');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const db='SecureFinanceERP_Estabilizacion_20261021';
function run(query){return new Promise((resolve,reject)=>{
 const file=path.resolve('.data','qa-concurrency-'+randomUUID()+'.sql');
 fs.writeFileSync(file,`SET NOCOUNT ON; SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF; IF DB_NAME()<>'${db}' THROW 54900,'Wrong target',1; ${query}`);
 const p=spawn('sqlcmd',['-S','localhost','-E','-C','-b','-d',db,'-f','65001','-i',file],{windowsHide:true});
 let out='';p.stdout.on('data',d=>out+=d);p.stderr.on('data',d=>out+=d);p.on('error',reject);p.on('close',code=>code?reject(Error(out)):resolve(out));
});}
const fixture="DECLARE @a INT=(SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario='admin'),@p INT=(SELECT ProductoId FROM dbo.Producto WHERE Codigo='DEMO-CABLE'),@v INT=(SELECT MIN(ProveedorId) FROM dbo.Proveedor WHERE Activo=1); ";
async function main(){
 const lines=[];const pass=s=>{lines.push('PASS '+s);console.log(lines.at(-1));};
 const op=randomUUID();
 const buy=fixture+`EXEC dbo.sp_RegistrarRecepcionCompra @a,@p,@v,1,N'LAB-CONCURRENT-IDEM',N'QA concurrente','${op}';`;
 await Promise.all([run(buy),run(buy)]);
 await run(`IF (SELECT COUNT(*) FROM dbo.RecepcionCompra WHERE OperacionId='${op}')<>1 OR (SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE OperacionId='${op}')<>1 THROW 54900,'Duplicate purchase',1;`);
 pass('concurrent same purchase: one receipt and one Kardex');
 const a=randomUUID(),b=randomUUID();
 await Promise.all([a,b].map(o=>run(fixture+`EXEC dbo.sp_RegistrarRecepcionCompra @a,@p,@v,1,N'LAB-CONCURRENT-DISTINCT',N'QA concurrente','${o}';`)));
 await run(`IF (SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE OperacionId IN('${a}','${b}'))<>2 THROW 54900,'Lost purchase',1;`);
 pass('concurrent distinct purchases: no lost movement');
 // Remaining unit of the laboratory sale: a new verifiable return, no fabricated credit row.
 const ret=randomUUID();
 await run(fixture+`DECLARE @f INT=(SELECT MAX(FacturaId) FROM dbo.Factura),@d INT=(SELECT MAX(DetalleFacturaId) FROM dbo.DetalleFactura),@j NVARCHAR(MAX); SET @j=CONCAT(N'[{"DetalleFacturaId":',@d,N',"Cantidad":1,"Reingresar":false}]'); EXEC dbo.sp_ProcesarDevolucionCliente @a,@f,'${ret}',N'QA defecto sin reingreso',@j;`);
 const credit=`DECLARE @a INT=(SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario='admin'),@n INT=(SELECT MAX(NotaCreditoId) FROM dbo.NotaCredito),@m DECIMAL(19,2); SELECT @m=ROUND(Total*0.75,2) FROM dbo.NotaCredito WHERE NotaCreditoId=@n; `;
 const outcomes=await Promise.allSettled([randomUUID(),randomUUID()].map(o=>run(credit+`EXEC dbo.sp_RegistrarAplicacionNotaCredito @a,@n,@m,N'LAB-EXTERNAL-CONCURRENT','${o}';`)));
 assert.equal(outcomes.filter(r=>r.status==='fulfilled').length,1);
 assert.match(outcomes.find(r=>r.status==='rejected').reason.message,/54804/);
 await run('IF EXISTS(SELECT 1 FROM dbo.NotaCredito n CROSS APPLY(SELECT SUM(Monto) M FROM dbo.AplicacionNotaCredito WHERE NotaCreditoId=n.NotaCreditoId) a WHERE a.M>n.Total) THROW 54900,\'Negative balance\',1;');
 pass('concurrent credit applications: one succeeds, excess rejected, no negative balance');
 const last=randomUUID();
 const liquidate=`DECLARE @a INT=(SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario='admin'),@n INT=(SELECT MAX(NotaCreditoId) FROM dbo.NotaCredito),@m DECIMAL(19,2); SELECT @m=Total-(SELECT SUM(Monto) FROM dbo.AplicacionNotaCredito WHERE NotaCreditoId=@n) FROM dbo.NotaCredito WHERE NotaCreditoId=@n; `;
 // Capture remaining amount before both sessions, so retry compares exactly the original payload.
 const output=await run(liquidate+' SELECT CONVERT(VARCHAR(30),@m) Remaining;');
 const amount=output.match(/\b\d+\.\d{2}\b/)[0];
 const final=`DECLARE @a INT=(SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario='admin'),@n INT=(SELECT MAX(NotaCreditoId) FROM dbo.NotaCredito); EXEC dbo.sp_RegistrarAplicacionNotaCredito @a,@n,${amount},N'LAB-EXTERNAL-FINAL','${last}';`;
 await Promise.all([run(final),run(final)]);
 await run(`IF (SELECT COUNT(*) FROM dbo.AplicacionNotaCredito WHERE OperacionId='${last}')<>1 THROW 54900,'Duplicate credit application',1;`);
 pass('concurrent identical final application: one ledger entry');
 await run(`DECLARE @a INT=(SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario='admin'),@t INT=(SELECT MAX(TicketId) FROM dbo.Ticket_Garantia),@v BINARY(8);SELECT @v=Version FROM dbo.Ticket_Garantia WHERE TicketId=@t; BEGIN TRY EXEC dbo.sp_ActualizarEstadoGarantia @a,@t,0x0000000000000000,'RECHAZADO',N'QA version obsoleta';THROW 54900,'Stale version accepted',1; END TRY BEGIN CATCH IF ERROR_NUMBER()<>54603 THROW; END CATCH;`);
 pass('warranty stale version rejected');
 fs.writeFileSync('.data/stabilization-concurrency.txt',lines.join('\n')+'\n');
}
if(require.main===module)main().catch(e=>{console.error(e.message);process.exitCode=1;});
module.exports={run};
