'use strict';
// Existing-database deployment. No seed, no login/password/role reset, no DROP DATABASE/RESTORE REPLACE.
const fs=require('fs'),path=require('path'),assert=require('assert/strict'),{spawn,execFileSync}=require('child_process'),{randomBytes,createHash}=require('crypto');
const ROOT=path.resolve(__dirname,'../..');
const ORIGINAL=path.dirname(execFileSync('git',['rev-parse','--path-format=absolute','--git-common-dir'],{cwd:ROOT,encoding:'utf8',windowsHide:true}).trim());
const PRIVATE=path.join(ORIGINAL,'.data','original-p3-upgrade');fs.mkdirSync(PRIVATE,{recursive:true});
const STATE=path.join(PRIVATE,'state.json');let serial=0;
const lit=s=>"N'"+String(s).replaceAll("'","''")+"'";const id=s=>'['+s.replaceAll(']',']]')+']';
const prelude='SET NOCOUNT ON;SET XACT_ABORT ON;SET ANSI_NULLS ON;SET QUOTED_IDENTIFIER ON;SET ANSI_PADDING ON;SET ANSI_WARNINGS ON;SET ARITHABORT ON;SET CONCAT_NULL_YIELDS_NULL ON;SET NUMERIC_ROUNDABORT OFF;\n';
async function exec(sql,db='master',json=false){assert(db==='master'||db==='SecureFinanceERP'||/^SecureFinanceERP_P3_Rehearsal_\d{14}_[a-f0-9]{6}$/.test(db));const p=path.join(PRIVATE,`command-${Date.now()}-${randomBytes(3).toString('hex')}-${++serial}.sql`),out=p+'.out';fs.writeFileSync(p,prelude+sql,'utf8');return new Promise((resolve,reject)=>{const child=spawn('sqlcmd',['-S','localhost','-E','-C','-b','-r','0','-f','i:65001','-u','-y','0','-d',db,'-i',p,'-o',out],{windowsHide:true});let err='';child.stderr.on('data',d=>err+=d);child.on('error',reject);child.on('close',code=>{const text=fs.existsSync(out)?fs.readFileSync(out).toString('utf16le').replace(/^\uFEFF/,''):'';if(code)return reject(Error((err||text).slice(0,3500)));if(!json)return resolve(text);const a=text.indexOf('~JSON~'),b=text.indexOf('~END~');assert(a>=0&&b>a,'JSON framing absent');const body=text.slice(a+6,b).replace(/\r?\n/g,'').trim();try{resolve(body==='NULL'||!body?[]:JSON.parse(body));}catch(e){reject(e);}});});}
const query=(s,db)=>exec("PRINT '~JSON~'; SELECT CONVERT(NVARCHAR(MAX),("+s+" FOR JSON PATH,INCLUDE_NULL_VALUES)); PRINT '~END~';",db,true);
const state=()=>JSON.parse(fs.readFileSync(STATE));
async function identity(db){const row=(await query("SELECT CONVERT(NVARCHAR(128),SERVERPROPERTY('ServerName')) ServerName,DB_NAME() DatabaseName,CONVERT(NVARCHAR(260),SERVERPROPERTY('InstanceDefaultBackupPath')) BackupPath,CONVERT(NVARCHAR(260),SERVERPROPERTY('InstanceDefaultDataPath')) DataPath,CONVERT(NVARCHAR(260),SERVERPROPERTY('InstanceDefaultLogPath')) LogPath",db))[0];assert.equal(row.DatabaseName,db);return row;}
async function inventory(db){return query("SELECT o.name,o.type FROM sys.objects o WHERE schema_id=SCHEMA_ID('dbo') AND (o.name LIKE 'P3[_]%' OR o.name IN('Credito_Cliente','Abono_Factura','Bitacora_DDL')) ORDER BY o.name",db);}
async function prepare(){assert(!fs.existsSync(STATE),'Existing deployment state: do not repeat backup/restore implicitly');const i=await identity('SecureFinanceERP');assert.equal(i.ServerName,'9U8ICS2VLMRUE','Unexpected server; review before writing');const objects=await inventory('SecureFinanceERP');assert.equal(objects.length,0,'Part III partially present: review required');await exec('DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;','SecureFinanceERP');
 const stamp=new Date().toISOString().replace(/\D/g,'').slice(0,14),suffix=randomBytes(3).toString('hex'),clone=`SecureFinanceERP_P3_Rehearsal_${stamp}_${suffix}`,backup=path.win32.join(i.BackupPath,`SecureFinanceERP_PreP3_${stamp}_${suffix}.bak`);
 await exec(`IF DB_NAME()<>N'SecureFinanceERP' THROW 59900,'Wrong source',1; BACKUP DATABASE SecureFinanceERP TO DISK=${lit(backup)} WITH COPY_ONLY,CHECKSUM; RESTORE VERIFYONLY FROM DISK=${lit(backup)} WITH CHECKSUM;`,'SecureFinanceERP');
 const files=await query('SELECT name,type FROM sys.database_files ORDER BY file_id','SecureFinanceERP');assert.equal(files.length,2,'Review restore layout');const moves=files.map(f=>`MOVE ${lit(f.name)} TO ${lit(path.win32.join(f.type===0?i.DataPath:i.LogPath,clone+(f.type===0?'.mdf':'.ldf')))}`).join(',');
 await exec(`IF DB_ID(${lit(clone)}) IS NOT NULL THROW 59900,'Clone already exists',1;RESTORE DATABASE ${id(clone)} FROM DISK=${lit(backup)} WITH ${moves},CHECKSUM,RECOVERY;`);
 await exec('DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;',clone);
 const s={server:i.ServerName,source:'SecureFinanceERP',clone,backup,backupVerified:true,restoreVerified:true,preparedAt:new Date().toISOString(),objectsBefore:objects};fs.writeFileSync(STATE,JSON.stringify(s,null,2));console.log('PASS full COPY_ONLY/CHECKSUM backup, VERIFYONLY, actual restore and clone CHECKDB.');console.log('Rehearsal copy: '+clone);
}
function migrations(){const files=fs.readdirSync(path.join(ROOT,'database'));const one=n=>{const a=files.filter(f=>f.startsWith(n+'_')&&!/Verificacion|Pruebas/.test(f));assert.equal(a.length,1,'Ambiguous '+n);return a[0];};return [41,42,43,44,60,61,62,63,70,71,72,73,74,75,76,77,78,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95].map(one);}
function render(file){let s=fs.readFileSync(path.join(ROOT,'database',file),'utf8').replace(/^\uFEFF/,'');assert(!/\bUSE\s+\[?/i.test(s.replace(/--[^\r\n]*/g,'')),'No context switching allowed');if(/^9[0-4]_/.test(file)){
 s=s.replace(/OR DB_NAME\(\) COLLATE Latin1_General_100_CI_AS = N'SecureFinanceERP'/g,'OR DB_NAME() COLLATE Latin1_General_100_BIN2 <> dbo.P3_INT_Destino()');
 s=s.replaceAll('P3_DDL.LaboratorioConfirmado','P3_DDL.DespliegueConfirmado').replaceAll('P3_DDL.TextoExactoAutorizado','P3_DDL.TextoExactoDespliegue');
 }
 return s;
}
const policy=`CREATE OR ALTER FUNCTION dbo.P3_INT_Destino() RETURNS NVARCHAR(128) AS BEGIN
 DECLARE @Bound NVARCHAR(256)=(SELECT CONVERT(NVARCHAR(256),value) FROM sys.extended_properties WHERE class=0 AND name=N'P3.Despliegue.Autorizacion');
 RETURN CASE WHEN DB_ID()>4 AND @Bound=CONCAT(CONVERT(NVARCHAR(128),SERVERPROPERTY('ServerName')),N'|',DB_NAME())
 THEN DB_NAME() ELSE N'!DESPLIEGUE_NO_AUTORIZADO!' END; END;`;
// Preserve every preexisting row, including salts/password hashes, role memberships, and audit history.
// Hash only; no credential material is exported. Added permissions/audit rows are allowed.
const capture=`CREATE TABLE #OldTables(Name SYSNAME,Columns NVARCHAR(MAX));CREATE TABLE #BeforeRows(T SYSNAME,H VARBINARY(32));CREATE TABLE #AfterRows(T SYSNAME,H VARBINARY(32));
 INSERT #OldTables SELECT t.name,STRING_AGG(CONVERT(NVARCHAR(MAX),N't.'+QUOTENAME(c.name)),N',') WITHIN GROUP(ORDER BY c.column_id) FROM sys.tables t JOIN sys.columns c ON c.object_id=t.object_id WHERE t.schema_id=SCHEMA_ID('dbo') GROUP BY t.name;
 DECLARE @Table SYSNAME,@Cols NVARCHAR(MAX),@SQL NVARCHAR(MAX);DECLARE OldTables CURSOR LOCAL FAST_FORWARD FOR SELECT Name,Columns FROM #OldTables;
 OPEN OldTables;FETCH NEXT FROM OldTables INTO @Table,@Cols;WHILE @@FETCH_STATUS=0 BEGIN
 SET @SQL=N'INSERT #BeforeRows SELECT '+QUOTENAME(@Table,'''')+N',HASHBYTES(''SHA2_256'',CONVERT(VARBINARY(MAX),(SELECT '+@Cols+N' FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES))) FROM dbo.'+QUOTENAME(@Table)+N' t;';EXEC sys.sp_executesql @SQL;
 FETCH NEXT FROM OldTables INTO @Table,@Cols;END;CLOSE OldTables;DEALLOCATE OldTables;`;
const preserve=`DECLARE @Table SYSNAME,@Cols NVARCHAR(MAX),@SQL NVARCHAR(MAX);DECLARE OldTables CURSOR LOCAL FAST_FORWARD FOR SELECT Name,Columns FROM #OldTables;
 OPEN OldTables;FETCH NEXT FROM OldTables INTO @Table,@Cols;WHILE @@FETCH_STATUS=0 BEGIN
 SET @SQL=N'INSERT #AfterRows SELECT '+QUOTENAME(@Table,'''')+N',HASHBYTES(''SHA2_256'',CONVERT(VARBINARY(MAX),(SELECT '+@Cols+N' FOR JSON PATH,WITHOUT_ARRAY_WRAPPER,INCLUDE_NULL_VALUES))) FROM dbo.'+QUOTENAME(@Table)+N' t;';EXEC sys.sp_executesql @SQL;
 FETCH NEXT FROM OldTables INTO @Table,@Cols;END;CLOSE OldTables;DEALLOCATE OldTables;
 IF EXISTS(SELECT T,H,COUNT_BIG(*) N FROM #BeforeRows GROUP BY T,H EXCEPT SELECT b.T,b.H,COUNT_BIG(*) FROM #AfterRows b WHERE EXISTS(SELECT 1 FROM #BeforeRows a WHERE a.T=b.T AND a.H=b.H) GROUP BY b.T,b.H) THROW 59901,'Existing row modified or lost: rolling back all migrations',1;
 IF EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE Diferencia<>0) THROW 59902,'Stock reconciliation failed',1;
 IF NOT EXISTS(SELECT 1 FROM dbo.Usuario u JOIN dbo.Usuario_Rol ur ON u.UsuarioId=ur.UsuarioId JOIN dbo.Rol r ON r.RolId=ur.RolId WHERE u.NombreUsuario=N'admin' AND u.Activo=1 AND r.Nombre=N'Administrador') THROW 59903,'Existing admin authorization missing',1;
 SELECT N'PRESERVED' Result,T,COUNT_BIG(*) OriginalRows FROM #BeforeRows GROUP BY T ORDER BY T;`;
async function upgrade(db){const s=state();assert(s.backupVerified&&s.restoreVerified);assert(db===s.clone||db===s.source);if(db===s.source){assert(s.rehearsalPassed&&s.rehearsalOperationsPassed,'Verified rehearsal required');assert.equal(s.planHash,planHash(),'Code changed since rehearsal');}const i=await identity(db);assert.equal(i.ServerName,s.server);assert.equal((await inventory(db)).length,0,'No implicit replay/partial upgrade allowed');
 let script=`IF DB_NAME()<>${lit(db)} OR CONVERT(NVARCHAR(128),SERVERPROPERTY('ServerName'))<>${lit(s.server)} THROW 59900,'Deployment identity mismatch',1;
 BEGIN TRANSACTION; DECLARE @L INT;EXEC @L=sys.sp_getapplock @Resource=N'P3.Original.Deployment',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;IF @L<0 THROW 59900,'Deployment busy',1;
 IF EXISTS(SELECT 1 FROM sys.dm_exec_sessions WHERE database_id=DB_ID() AND session_id<>@@SPID AND is_user_process=1) THROW 59900,'Close active application sessions before deployment',1;
 EXEC sys.sp_addextendedproperty @name=N'P3.Despliegue.Autorizacion',@value=${lit(s.server+'|'+db)};
 EXEC sys.sp_set_session_context @key=N'P3_DDL.DespliegueConfirmado',@value=${lit(db)};
 EXEC sys.sp_set_session_context @key=N'P3_DDL.TextoExactoDespliegue',@value=${lit(db)};\n${capture}\nGO\n${policy}\nGO\n`;
 for(const f of migrations()){script+=render(f)+'\nGO\n';if(f.startsWith('95_'))script+='GRANT EXECUTE ON dbo.P3_INT_Destino TO P3_DDL_Escritor;\nGO\n';}
 script+=preserve+`\nEXEC sys.sp_addextendedproperty @name=N'P3.Despliegue.Plan',@value=${lit(planHash())};COMMIT;`;
 const out=await exec(script,db);await exec('DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS;DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;',db);fs.writeFileSync(path.join(PRIVATE,db===s.source?'production-upgrade.txt':'rehearsal-upgrade.txt'),out);
 if(db===s.clone){s.rehearsalPassed=true;s.planHash=planHash();}else{s.productionUpdated=true;s.productionAt=new Date().toISOString();}fs.writeFileSync(STATE,JSON.stringify(s,null,2));console.log('PASS atomic Part III upgrade, existing rows preserved, CHECKDB: '+db);
}
function planHash(){return createHash('sha256').update(policy+migrations().map(f=>f+'\n'+render(f)).join('\n')).digest('hex');}
function manifest(){return {base:'b5cca8d',planHash:planHash(),atomic:true,requires:['verified COPY_ONLY CHECKSUM full backup','actual restore and CHECKDB','rehearsal with all existing rows preserved','successful essential operation tests'],files:migrations().map(file=>({file,sourceSHA256:createHash('sha256').update(fs.readFileSync(path.join(ROOT,'database',file),'utf8').replace(/^\uFEFF/,'').replace(/\r\n/g,'\n')).digest('hex'),renderedSHA256:createHash('sha256').update(render(file).replace(/\r\n/g,'\n')).digest('hex')}))};}
module.exports={exec,query,identity,state,upgrade,prepare,ROOT,ORIGINAL,PRIVATE,STATE,planHash,manifest};
if(require.main===module){const action=process.argv[2];(action==='prepare'?prepare():action==='rehearse'?upgrade(state().clone):action==='apply'?upgrade(state().source):Promise.reject(Error('Use prepare/rehearse/apply'))).catch(e=>{console.error(e.message);process.exitCode=1;});}
