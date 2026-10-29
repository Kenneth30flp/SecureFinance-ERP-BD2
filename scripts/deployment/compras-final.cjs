'use strict';
const assert=require('assert/strict'),fs=require('fs'),path=require('path'),d=require('./compras-upgrade.cjs');
async function final(){
 const s=d.state();assert(s.productionOperationsPassed&&s.browserPassed&&s.backupVerified&&s.restoreVerified);
 await d.integrity(s.source);
 // Compare credential bytes inside SQL Server. Never export their values.
 const output=await d.exec(`
 IF EXISTS(SELECT UsuarioId,NombreUsuario,PasswordHash,Salt,FechaCambioPassword FROM dbo.Usuario EXCEPT SELECT UsuarioId,NombreUsuario,PasswordHash,Salt,FechaCambioPassword FROM [${s.clone}].dbo.Usuario)
 OR EXISTS(SELECT UsuarioId,NombreUsuario,PasswordHash,Salt,FechaCambioPassword FROM [${s.clone}].dbo.Usuario EXCEPT SELECT UsuarioId,NombreUsuario,PasswordHash,Salt,FechaCambioPassword FROM dbo.Usuario) THROW 59911,'Credential or account mismatch',1;
 IF EXISTS(SELECT * FROM dbo.Rol EXCEPT SELECT * FROM [${s.clone}].dbo.Rol) OR EXISTS(SELECT * FROM [${s.clone}].dbo.Rol EXCEPT SELECT * FROM dbo.Rol) THROW 59911,'Role mismatch',1;
 IF EXISTS(SELECT * FROM dbo.Usuario_Rol EXCEPT SELECT * FROM [${s.clone}].dbo.Usuario_Rol) OR EXISTS(SELECT * FROM [${s.clone}].dbo.Usuario_Rol EXCEPT SELECT * FROM dbo.Usuario_Rol) THROW 59911,'Membership mismatch',1;
 IF EXISTS(SELECT name,definition FROM sys.objects o JOIN sys.sql_modules m ON m.object_id=o.object_id WHERE o.name NOT LIKE 'P3[_]COM[_]%'
 EXCEPT SELECT name,definition FROM [${s.clone}].sys.objects o JOIN [${s.clone}].sys.sql_modules m ON m.object_id=o.object_id WHERE o.name NOT LIKE 'P3[_]COM[_]%') THROW 59911,'Shared SQL module changed',1;
 SELECT N'PASS credential bytes, existing accounts, roles, memberships and shared SQL definitions unchanged' Result;
 `,s.source);
 fs.writeFileSync(path.join(d.privateDir,'final-integrity.txt'),output);
 s.finalIntegrityPassed=true;s.finalVerifiedAt=new Date().toISOString();d.save(s);
 console.log(output.trim());console.log('PASS final CHECKDB, constraints and warehouse reconciliation');
}
if(require.main===module)final().catch(e=>{console.error('FINAL BLOCKED',e.message);process.exitCode=1;});module.exports={final};
