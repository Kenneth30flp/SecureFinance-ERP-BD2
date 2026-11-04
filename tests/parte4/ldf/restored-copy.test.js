'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {validate,guard}=require('../../../scripts/parte4/ldf/restored-copy.cjs');
const base={authorized:true,sourceDatabase:'SecureFinanceERP',database:'SecureFinanceERP_LDF_Rehearsal_20261104054200',expectedServer:'SQL_TEST',databaseGuid:'12345678-1234-1234-1234-123456789012',evidenceName:'test-authorization'};
test('Restored-copy authorization rejects original, arbitrary databases and missing operator consent',()=>{
 for(const changes of [{authorized:false},{database:'SecureFinanceERP'},{database:'master'},{database:'SomeOtherERP'},{sourceDatabase:'OtherSource'},{databaseGuid:'invalid'},{evidenceName:'../escape'}]) assert.throws(()=>validate({...base,...changes}));
 assert.equal(validate(base),base);
});
test('Restored-copy SQL checks effective DBA token, actual database GUID and enabled capture',()=>{
 const sql=guard(base);
 for(const check of ["IS_SRVROLEMEMBER(N'sysadmin')","USER_NAME()<>","SERVERPROPERTY('ServerName')",'database_guid=CONVERT(uniqueidentifier',"is_disabled=0"]) assert(sql.includes(check));
 assert(!/DISABLE TRIGGER|ALTER FUNCTION|ALTER TRIGGER|CREATE OR ALTER|GRANT/i.test(sql));
});
