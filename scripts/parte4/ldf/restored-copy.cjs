'use strict';
// Operator-only rehearsal authorization. Never changes P3_INT_Destino or the DDL trigger.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { runSql, queryJson, lit, root } = require('./sqlcmd.cjs');

function validate(o) {
  assert.equal(o.authorized, true, 'Explicit restored-copy authorization required');
  assert.match(o.database, /^SecureFinanceERP_LDF_Rehearsal_\d{14}$/);
  assert.equal(o.sourceDatabase, 'SecureFinanceERP');
  assert(o.expectedServer && o.database !== o.sourceDatabase);
  assert.match(o.databaseGuid, /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i);
  assert.match(o.evidenceName, /^[a-zA-Z0-9_-]+$/);
  return o;
}
function guard(o) {
  validate(o);
  return `IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin'),0)<>1
 OR USER_NAME()<>N'dbo' OR DB_NAME()<>${lit(o.database)}
 OR CONVERT(nvarchar(128),SERVERPROPERTY('ServerName'))<>${lit(o.expectedServer)}
 OR NOT EXISTS(SELECT 1 FROM sys.database_recovery_status WHERE database_id=DB_ID() AND database_guid=CONVERT(uniqueidentifier,${lit(o.databaseGuid)}))
 THROW 59010,'Restored-copy DBA identity mismatch',1;
IF NOT EXISTS(SELECT 1 FROM sys.triggers WHERE name=N'P3_DDL_CapturarEstructura' AND parent_class=0 AND is_disabled=0)
 THROW 59010,'DDL capture must stay enabled',1;`;
}
async function withRestoredAuthorization(options, task) {
  const o=validate(options), old=o.expectedServer+'|'+o.sourceDatabase, bound=o.expectedServer+'|'+o.database;
  const evidence=path.join(root,'.data',o.evidenceName+'.json');
  assert(!fs.existsSync(evidence),'Existing authorization evidence: inspect before retry');
  const record={atUTC:new Date().toISOString(),database:o.database,databaseGuid:o.databaseGuid,sourceDatabase:o.sourceDatabase,expectedServer:o.expectedServer,oldBinding:old,temporaryBinding:bound,status:'PREPARED'};
  const restore=`${guard(o)}
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'P3.Despliegue.Autorizacion' AND CONVERT(nvarchar(256),value) IN(${lit(old)},${lit(bound)})) THROW 59010,'Unexpected binding during cleanup',1;
EXEC sys.sp_updateextendedproperty @name=N'P3.Despliegue.Autorizacion',@value=${lit(old)};
COMMIT;`;
  fs.mkdirSync(path.dirname(evidence),{recursive:true});
  fs.writeFileSync(evidence,JSON.stringify({...record,recoverySQL:restore},null,2),{flag:'wx'});
  try {
    // Windows MicrosoftAccount aliases may return NULL in IS_SRVROLEMEMBER(role, ORIGINAL_LOGIN()).
    // Check the authenticated effective token on each fresh -E connection instead.
    record.operator=(await queryJson(`SELECT ORIGINAL_LOGIN() LoginOriginal,SUSER_SNAME() EffectiveLogin,HOST_NAME() Host,APP_NAME() Application`,o))[0];
    record.authorization=await runSql(`${guard(o)}
BEGIN TRANSACTION;
IF NOT EXISTS(SELECT 1 FROM sys.extended_properties WHERE class=0 AND name=N'P3.Despliegue.Autorizacion' AND CONVERT(nvarchar(256),value)=${lit(old)}) THROW 59010,'Copy does not retain expected source binding',1;
EXEC sys.sp_updateextendedproperty @name=N'P3.Despliegue.Autorizacion',@value=${lit(bound)};
IF dbo.P3_INT_Destino()<>DB_NAME() THROW 59010,'Authorization not effective',1;
COMMIT; PRINT 'Explicit DBA restored-copy authorization applied';`,o);
    record.status='AUTHORIZED';fs.writeFileSync(evidence,JSON.stringify({...record,recoverySQL:restore},null,2));
    const result=await task(); record.task='PASS';return result;
  } catch(e) {record.task='FAIL';record.error=e.message;throw e;}
  finally {
    try {record.cleanup=await runSql(restore,o);record.status='REVOKED';}
    catch(e){record.status='CLEANUP_REQUIRED';record.cleanupError=e.message;throw e;}
    finally {record.finishedAtUTC=new Date().toISOString();fs.writeFileSync(evidence,JSON.stringify({...record,recoverySQL:restore},null,2));}
  }
}
module.exports={validate,guard,withRestoredAuthorization};
