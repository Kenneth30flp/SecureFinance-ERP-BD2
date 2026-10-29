'use strict';
const fs=require('fs'),assert=require('assert/strict');
const lab=require('../../database/tests/promocionesLab');
const manifest=JSON.parse(fs.readFileSync('database/integracion-manifest.json','utf8'));
const crypto=require('crypto');
const digest=crypto.createHash('sha256').update(JSON.stringify(manifest.files)).digest('hex');
for(const f of manifest.files)assert.equal(crypto.createHash('sha256').update(fs.readFileSync('database/'+f.file,'utf8').replace(/^\uFEFF/,'').replace(/\r\n/g,'\n')).digest('hex'),f.sha256,'Manifest mismatch '+f.file);
async function install(){
 const s=lab.readState();assert.match(s.lab,/^SecureFinanceERP_P3_PRO_\d{14}_[a-f0-9]{8}$/);
 const seen=await lab.labJson("SELECT CONVERT(NVARCHAR(128),SERVERPROPERTY('ServerName')) ServerName,DB_NAME() DatabaseName");
 assert.equal(seen[0].DatabaseName,s.lab);assert.ok(seen[0].ServerName);
 const done=await lab.labJson("SELECT CONVERT(NVARCHAR(100),value) Installed FROM sys.extended_properties WHERE class=0 AND name=N'P3.Integracion.Version'");
 if(done.length){assert.equal(done[0].Installed,'1');const stamp=await lab.labJson("SELECT CONVERT(NVARCHAR(64),value) Hash FROM sys.extended_properties WHERE class=0 AND name=N'P3.Integracion.Manifest'");assert.equal(stamp[0]?.Hash,digest,'Manifest differs: review upgrade instead of replaying tables/snapshot');assert.equal((await lab.labJson('SELECT dbo.P3_INT_Destino() A'))[0].A,s.lab);console.log('SKIP matching integration already installed; schema/data preserved');return;}
 let text=`SET XACT_ABORT ON; BEGIN TRANSACTION;\nIF DB_NAME()<>N'${s.lab}' OR CONVERT(NVARCHAR(128),SERVERPROPERTY('ServerName'))<>N'${seen[0].ServerName}' THROW 54990,'Identidad incorrecta',1;
 EXEC sys.sp_addextendedproperty @name=N'P3.Integracion.Autorizacion',@value=N'${seen[0].ServerName}|${s.lab}';
 EXEC sys.sp_set_session_context @key=N'P3_DDL.LaboratorioConfirmado',@value=N'${s.lab}';
 EXEC sys.sp_set_session_context @key=N'P3_DDL.TextoExactoAutorizado',@value=N'${s.lab}';\nGO\n`;
 for(const f of manifest.atomicGroup) {
 text+=fs.readFileSync('database/'+f,'utf8').replace(/\uFEFF/g,'')+'\nGO\n';
 if(f.startsWith('95_'))text+='GRANT EXECUTE ON dbo.P3_INT_Destino TO P3_DDL_Escritor;\nGO\n';
 }
 text+=`EXEC sys.sp_addextendedproperty @name=N'P3.Integracion.Version',@value=N'1';EXEC sys.sp_addextendedproperty @name=N'P3.Integracion.Manifest',@value=N'${digest}'; COMMIT;\n`;
 await lab.labQuery(text);console.log('PASS atomic integration install '+s.lab);
}
if(require.main===module)install().catch(e=>{console.error(e.message);process.exitCode=1;});module.exports={install};
