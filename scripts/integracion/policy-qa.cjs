'use strict';
const fs=require('fs'),assert=require('assert/strict'),lab=require('../../database/tests/promocionesLab');
(async()=>{const s=lab.readState();assert.equal((await lab.labJson('SELECT dbo.P3_INT_Destino() A'))[0].A,s.lab);
const out=await lab.labQuery(`SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 EXEC sys.sp_updateextendedproperty @name=N'P3.Integracion.Autorizacion',@value=N'REVOKED-SYNTHETIC-QA';
 EXEC(N'CREATE TABLE dbo.P3_INT_ShouldNeverExist (Id INT)');
 THROW 54999,'Unauthorized DDL unexpectedly succeeded',1;
END TRY BEGIN CATCH
 DECLARE @Error INT=ERROR_NUMBER();IF XACT_STATE()<>0 ROLLBACK;
 IF @Error<>54993 THROW;
END CATCH;
IF OBJECT_ID('dbo.P3_INT_ShouldNeverExist') IS NOT NULL OR dbo.P3_INT_Destino()<>DB_NAME() THROW 54999,'Rollback/policy invalid',1;
SELECT N'PASS revoked authorization rejects DDL (54993), rolls back object and restores authorization' Result;`);
fs.writeFileSync('docs/parte3/integracion-dylan/evidencias/politica-ddl.txt',out);console.log('PASS DDL fail-closed authorization and rollback');})().catch(e=>{console.error(e.message);process.exitCode=1;});
