'use strict';
// SQLCMD Windows authentication; only creates fresh, marked laboratory databases.
// Installation uses Windows authentication; integrated HTTP checks use the dedicated app login.
// No DROP/RESTORE operations.
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const {spawn}=require('node:child_process');
const {randomUUID}=require('node:crypto');
const assert=require('node:assert/strict');
const server=process.env.EDWARD_TEST_SERVER||'.\\SQLEXPRESS';
const integrated=process.argv.includes('--integrated');
const database='SecureFinanceERP_Edward_Test_'+randomUUID().replaceAll('-','');
const marker=randomUUID();
const root=path.resolve(__dirname,'..');
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'edward-sql-'));
let serial=0;
function run(text,db=database){
 const file=path.join(temp,String(++serial)+'.sql');
 fs.writeFileSync(file,'SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;\n'+text);
 return new Promise((resolve,reject)=>{
 const p=spawn('sqlcmd',['-S',server,'-E','-C','-b','-r','0','-f','65001','-d',db,'-i',file],{windowsHide:true});
 let out='';p.stdout.on('data',d=>out+=d);p.stderr.on('data',d=>out+=d);
 p.on('error',reject);p.on('close',code=>code===0?resolve(out):reject(new Error(out)));
 });
}
function safe(text){
 // Only installer context is rewritten, in memory, for a newly created empty database.
 text=text.replace(/USE \[SecureFinanceERP\];/g,'USE ['+database+'];');
 if(/\b(?:CREATE|ALTER|DROP)\s+(?:DATABASE|LOGIN|SERVER)\b/i.test(text.replace(/^\s*--.*$/gm,'')))throw Error('Forbidden server instruction');
 for(const use of text.matchAll(/\bUSE\s+\[?([\w]+)\]?\s*;/gi))assert.equal(use[1],database);
 return text;
}
async function setup(){
 await run("IF DB_ID(N'"+database+"') IS NOT NULL THROW 54900,'Existing database',1; CREATE DATABASE ["+database+"];",'master');
 await run("EXEC sys.sp_addextendedproperty @name=N'Edward.TestRun',@value=N'"+marker+"';");
 const full=fs.readFileSync(path.join(root,'SecureFinanceERP_Full.sql'),'utf8');
 const start=full.indexOf('USE [SecureFinanceERP];');assert.ok(start>=0);
 await run("EXEC sys.sp_set_session_context @key=N'SecureFinance.AllowAcademicSeed',@value=1;\nGO\n"+safe(full.slice(start)));
 await run("IF DATABASE_PRINCIPAL_ID('securefinance_app') IS NULL CREATE USER securefinance_app WITHOUT LOGIN;");
 for(let n=15;n<=26;n++){
 const file=fs.readdirSync(root).find(f=>f.startsWith(String(n)+'_'));assert.ok(file);
 await run(safe(fs.readFileSync(path.join(root,file),'utf8')));
 }
 // Reapply only new migrations to prove repeatability.
 for(let n=24;n<=26;n++)await run(safe(fs.readFileSync(path.join(root,fs.readdirSync(root).find(f=>f.startsWith(n+'_'))),'utf8')));
 if(integrated){
  for(let repeat=0;repeat<2;repeat++)for(const n of [30,31,32]){
   const file=fs.readdirSync(root).find(f=>f.startsWith(n+'_'));assert.ok(file);
   await run(safe(fs.readFileSync(path.join(root,file),'utf8')));
  }
 }
 console.log('PASS isolated installation and repeatability');
}
async function main(){
 if(!process.argv.includes('--run'))throw Error('Use --run to create a NEW isolated database.');
 console.log('Laboratory database: '+database);
 await setup();
 await run(fs.readFileSync(path.join(__dirname,'EdwardTests.sql'),'utf8'));
 console.log('PASS SQL business, security, rollback and historical amounts');
 if(integrated){await run(fs.readFileSync(path.join(__dirname,'JoseAnaliticaTests.sql'),'utf8'));console.log('PASS Jose SQL historical sales, discounts, customers and replenishment');}
 await concurrency();
 console.log('PASS SQL concurrency A/B/C');
 if(integrated)await require('./VerifyParteIIIntegration').verify({database,run});
 console.log('Database retained for inspection: '+database);
}
async function concurrency(){
 const operation=randomUUID();
 const request=op=>"DECLARE @a INT=(SELECT TOP(1) UsuarioId FROM dbo.Usuario ORDER BY UsuarioId),@f INT=(SELECT MAX(FacturaId) FROM dbo.Factura),@d INT=(SELECT TOP(1) DetalleFacturaId FROM dbo.DetalleFactura WHERE FacturaId=(SELECT MAX(FacturaId) FROM dbo.Factura)); DECLARE @json NVARCHAR(MAX)=CONCAT(N'[{\"DetalleFacturaId\":',@d,N',\"Cantidad\":1,\"Reingresar\":true}]'); EXEC dbo.sp_ProcesarDevolucionCliente @a,@f,'"+op+"',N'Concurrente',@json;";
 const fixture="DECLARE @a INT=(SELECT TOP(1) UsuarioId FROM dbo.Usuario ORDER BY UsuarioId),@c INT=(SELECT TOP(1) ClienteId FROM dbo.Cliente ORDER BY ClienteId),@p INT=(SELECT TOP(1) ProductoId FROM dbo.Producto WHERE Stock>2 ORDER BY ProductoId); DECLARE @d dbo.TipoDetalleVentaDescuento; INSERT @d VALUES(@p,1,0); EXEC dbo.sp_ProcesarVentaTransaccional @c,@a,@d;";
 await run(fixture);
 // A: hold the winning transaction open while the second SQL connection enters.
 const a=run('BEGIN TRANSACTION;'+request(operation)+" WAITFOR DELAY '00:00:02'; COMMIT;");
 await new Promise(r=>setTimeout(r,200));
 const outcomes=await Promise.allSettled([a,run(request(randomUUID()))]);
 assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);
 assert.match(outcomes.find(x=>x.status==='rejected').reason.message,/54605/);
 // C: concurrent same request produces a single credit and Kardex ingress.
 await run(fixture);
 const idem=randomUUID();await Promise.all([run(request(idem)),run(request(idem))]);
 await run("IF (SELECT COUNT(*) FROM dbo.DevolucionCliente WHERE OperacionId='"+idem+"')<>1 OR (SELECT COUNT(*) FROM dbo.Kardex_Inventario WHERE OperacionId='"+idem+"')<>1 THROW 54900,'Idempotence failed',1;");
 // B: both connections present exactly the same ROWVERSION.
 await run("DECLARE @a INT=(SELECT TOP(1) UsuarioId FROM dbo.Usuario ORDER BY UsuarioId),@d INT=(SELECT MAX(DetalleFacturaId) FROM dbo.DetalleFactura),@o UNIQUEIDENTIFIER=NEWID(); EXEC dbo.sp_CrearTicketGarantia @a,@d,@o,N'Concurrent ticket';");
 const output=await run("SET NOCOUNT ON; SELECT sys.fn_varbintohexstr(Version) FROM dbo.Ticket_Garantia WHERE TicketId=(SELECT MAX(TicketId) FROM dbo.Ticket_Garantia);");
 const version=output.match(/0x[0-9A-Fa-f]{16}/)[0];
 const update="DECLARE @a INT=(SELECT TOP(1) UsuarioId FROM dbo.Usuario ORDER BY UsuarioId),@t INT=(SELECT MAX(TicketId) FROM dbo.Ticket_Garantia); EXEC dbo.sp_ActualizarEstadoGarantia @a,@t,"+version+",'EN_REVISION',N'Diagnostico concurrente';";
 const b=await Promise.allSettled([run(update),run(update)]);
 assert.equal(b.filter(x=>x.status==='fulfilled').length,1);assert.match(b.find(x=>x.status==='rejected').reason.message,/54603/);
}
main().catch(error=>{console.error(error.message);process.exitCode=1;}).finally(()=>console.log('SQL evidence directory: '+temp));
