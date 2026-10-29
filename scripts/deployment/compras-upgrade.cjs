'use strict';
// Incremental deployment only: verified full backup -> restored rehearsal -> 50..55.
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {randomBytes,createHash}=require('crypto'),d=require('./original-upgrade.cjs');
const privateDir=path.join(d.ORIGINAL,'.data','compras-upgrade');fs.mkdirSync(privateDir,{recursive:true});
const stateFile=path.join(privateDir,'state.json');
const lit=s=>"N'"+String(s).replaceAll("'","''")+"'";
const files=()=>Array.from({length:6},(_,i)=>{const matches=fs.readdirSync(path.join(d.ROOT,'database')).filter(f=>f.startsWith((50+i)+'_')&&f.endsWith('.sql'));assert.equal(matches.length,1);return matches[0];});
function plan(){return files().map(f=>{const text=fs.readFileSync(path.join(d.ROOT,'database',f),'utf8').replace(/^\uFEFF/,'');assert(!/\bUSE\s|\b(?:CREATE|ALTER|DROP)\s+(?:DATABASE|LOGIN)\b/i.test(text.replace(/--[^\r\n]*/g,'')));return {file:f,text};});}
const hash=()=>createHash('sha256').update(plan().map(x=>x.file+'\n'+x.text.replace(/\r\n/g,'\n')).join('\n')).digest('hex');
const state=()=>JSON.parse(fs.readFileSync(stateFile,'utf8'));
const save=s=>fs.writeFileSync(stateFile,JSON.stringify(s,null,2));
async function integrity(db){const out=await d.exec("DBCC CHECKDB WITH NO_INFOMSGS,ALL_ERRORMSGS; DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS; IF EXISTS(SELECT 1 FROM dbo.P3_BOD_Conciliacion WHERE Diferencia<>0) THROW 59902,'Stock reconciliation failed',1;",db);const diagnostics=out.replaceAll('DBCC execution completed. If DBCC printed error messages, contact your system administrator.','').trim();assert.equal(diagnostics,'','DBCC returned constraint violations or unexpected diagnostics');}
async function prepare(){
 assert(!fs.existsSync(stateFile),'Existing state: inspect before retry');plan();
 const identity=await d.identity('SecureFinanceERP');assert.equal(identity.ServerName,d.state().server);
 const missing=await d.query("SELECT name,type FROM sys.objects WHERE name LIKE 'P3[_]COM[_]%'",'SecureFinanceERP');assert.equal(missing.length,0,'Partial Compras installation requires review');
 await integrity('SecureFinanceERP');
 const stamp=new Date().toISOString().replace(/\D/g,'').slice(0,14),suffix=randomBytes(3).toString('hex');
 const clone=`SecureFinanceERP_P3_Rehearsal_${stamp}_${suffix}`,backup=path.win32.join(identity.BackupPath,`SecureFinanceERP_PreCompras_${stamp}_${suffix}.bak`);
 await d.exec(`BACKUP DATABASE [SecureFinanceERP] TO DISK=${lit(backup)} WITH COPY_ONLY,CHECKSUM; RESTORE VERIFYONLY FROM DISK=${lit(backup)} WITH CHECKSUM;`,'SecureFinanceERP');
 const sourceFiles=await d.query('SELECT name,type,physical_name FROM sys.database_files ORDER BY file_id','SecureFinanceERP');assert.equal(sourceFiles.length,2);
 const moves=sourceFiles.map(f=>`MOVE ${lit(f.name)} TO ${lit(path.win32.join(f.type===0?identity.DataPath:identity.LogPath,clone+(f.type===0?'.mdf':'.ldf')))}`).join(',');
 await d.exec(`IF DB_ID(${lit(clone)}) IS NOT NULL THROW 59900,'Clone exists',1; RESTORE DATABASE [${clone}] FROM DISK=${lit(backup)} WITH ${moves},CHECKSUM,RECOVERY;`);
 // The restored Multibodega destination authorization must bind to its own copy.
 await d.exec(`EXEC sys.sp_updateextendedproperty @name=N'P3.Despliegue.Autorizacion',@value=${lit(identity.ServerName+'|'+clone)};`,clone);
 await integrity(clone);
 const s={source:'SecureFinanceERP',server:identity.ServerName,clone,backup,backupVerified:true,restoreVerified:true,preparedAt:new Date().toISOString(),missingObjectsBefore:missing,planHash:hash()};save(s);
 console.log('PASS new full COPY_ONLY/CHECKSUM backup, VERIFYONLY, actual restore, CHECKDB and Multibodega reconciliation: '+clone);
}
async function upgrade(db){
 const s=state();assert(s.backupVerified&&s.restoreVerified);assert(db===s.source||db===s.clone);assert.equal(hash(),s.planHash,'Plan changed: rehearse again');
 if(db===s.source)assert(s.rehearsalPassed&&s.operationsPassed&&s.fiveModulesPassed,'Rehearsal gates missing');
 assert.equal((await d.identity(db)).ServerName,s.server);
 assert.equal((await d.query("SELECT name FROM sys.objects WHERE name LIKE 'P3[_]COM[_]%'",db)).length,0,'No replay allowed');
 const script=`IF DB_NAME()<>${lit(db)} THROW 59900,'Wrong target',1;
 BEGIN TRANSACTION; DECLARE @Lock INT; EXEC @Lock=sys.sp_getapplock @Resource=N'P3.Compras.Deployment',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000;
 IF @Lock<0 THROW 59900,'Deployment busy',1;
 ${d.capture}\nGO\n`+plan().map(x=>x.text+'\nGO\n').join('')+d.preserve+'\nCOMMIT;';
 const out=await d.exec(script,db);fs.writeFileSync(path.join(privateDir,db===s.source?'production-migrations.txt':'rehearsal-migrations.txt'),out);
 await integrity(db);if(db===s.clone)s.rehearsalPassed=true;else s.productionUpdatedAt=new Date().toISOString();save(s);
 console.log('PASS atomic migrations 50–55, every existing row preserved, CHECKDB and stock reconciliation: '+db);
}
module.exports={...d,privateDir,stateFile,state,save,prepare,upgrade,integrity,hash};
if(require.main===module){const action=process.argv[2];(action==='prepare'?prepare():action==='rehearse'?upgrade(state().clone):action==='apply'?upgrade(state().source):Promise.reject(Error('Use prepare/rehearse/apply'))).catch(e=>{console.error('BLOCKED',e.message);process.exitCode=1;});}
