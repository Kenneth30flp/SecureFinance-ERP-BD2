'use strict';
// Read-only SQL/filesystem assessment. No schedule activation or media deletion.
const fs=require('node:fs'),path=require('node:path'),{execFileSync}=require('node:child_process');
const {queryJson,root}=require('../ldf/sqlcmd.cjs');
const target={server:'localhost',expectedServer:'9U8ICS2VLMRUE',database:'SecureFinanceERP'};
const normalized=p=>path.win32.resolve(p).toLowerCase().replace(/\\+$/,'')+'\\';
const local=p=>typeof p==='string'&&/^[a-z]:\\/i.test(p)&&!/[\r\n\0]/.test(p)&&!/(^|[\\/])\.\.([\\/]|$)/.test(p);
const uuid=v=>typeof v==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(v)&&!/^0{8}-0{4}-0{4}-0{4}-0{12}$/.test(v);
const decimal=v=>typeof v==='string'&&/^\d+$/.test(v);
function assessCapacity({policy,roots,volumes,backups,sourceFiles=[]},{now=new Date(),maxAgeMinutes=5}={}){
 const reasons=[],assumptions={days:14,fullCount:3,diffCount:14,logCount:14*24*4,growthFactor:4,freeReserveBytes:String(20n*1024n**3n)};
 const result={SchemaVersion:2,AtUTC:now.toISOString(),Server:target.expectedServer,Database:target.database,DatabaseGuid:policy?.DatabaseGuid||null,policy,roots,volumes,backups,sourceFiles,assumptions,Result:'FAIL',status:'INSUFFICIENT_INFORMATION',statusLabel:'INFORMACIÓN INSUFICIENTE',observedCapacityFitsEstimate:false,estimatedAdditionalBytes:null,reasons,automaticScheduleEnabled:false,retention:{activationApproved:false,automaticDeletionImplemented:false,deleteExistingMedia:false,sustainedGrowthMeasured:false,capacityStopGuardImplemented:false,proposedPitrHorizonDays:14}};
 if(!policy||policy.Enabled!==false||policy.DdlTarget!==target.database||policy.DdlDisabled!==false||policy.LdfSignatures!==3||!uuid(policy.DatabaseGuid)||!uuid(policy.LdfGuid)||policy.DatabaseGuid.toLowerCase()!==policy.LdfGuid.toLowerCase())reasons.push('Database identity, DDL, LDF or disabled schedule evidence missing/inconsistent.');
 const paths=Array.isArray(roots)?roots.map(r=>r?.Ruta):[];
 if(!paths.length||paths.some(p=>!local(p)))reasons.push('Authorized local destination list missing/invalid.');
 const usable=Array.isArray(volumes)?volumes:[],groups=new Map();
 for(const p of paths.filter(local)){
  const facts=usable.filter(v=>local(v?.Root)&&normalized(v.Root)===normalized(p));
  if(facts.length!==1){reasons.push('Destination volume evidence missing/ambiguous: '+p);continue;}
  const v=facts[0],sample=Date.parse(v.SampledAtUTC);
  const volumeUuid=typeof v.VolumeId==='string'?v.VolumeId.match(/^\\\\\?\\Volume\{([^}]+)\}\\$/i)?.[1]:null;
  if(!uuid(volumeUuid)||!decimal(v.FreeBytes)||!decimal(v.TotalBytes)||BigInt(v.TotalBytes)===0n||BigInt(v.FreeBytes)>BigInt(v.TotalBytes)||!Number.isFinite(sample)||sample>now.getTime()+60000||sample<now.getTime()-maxAgeMinutes*60000){reasons.push('Invalid or stale destination volume measurement: '+p);continue;}
  const key=v.VolumeId.toLowerCase(),old=groups.get(key);
  if(old&&(old.FreeBytes!==v.FreeBytes||old.TotalBytes!==v.TotalBytes)){reasons.push('Conflicting measurements for shared destination volume.');continue;}
  groups.set(key,v);
 }
 const history=Array.isArray(backups)?backups:[],maximum={};
 for(const type of ['D','I','L']){
  const samples=history.filter(b=>b?.Type===type&&b.CopyOnly===false);
  if(!samples.length||samples.some(b=>!decimal(b.MaxBytes)||BigInt(b.MaxBytes)<=0n)){reasons.push('Operational non-COPY_ONLY history insufficient: '+type);continue;}
  maximum[type]=samples.reduce((n,b)=>BigInt(b.MaxBytes)>n?BigInt(b.MaxBytes):n,0n);
 }
 if(reasons.length)return result;
 const estimated=(BigInt(assumptions.fullCount)*maximum.D+BigInt(assumptions.diffCount)*maximum.I+BigInt(assumptions.logCount)*maximum.L)*BigInt(assumptions.growthFactor);
 result.estimatedAdditionalBytes=String(estimated);
 result.observedCapacityFitsEstimate=groups.size>0&&[...groups.values()].every(v=>BigInt(v.FreeBytes)>estimated+BigInt(assumptions.freeReserveBytes));
 result.status=result.observedCapacityFitsEstimate?'SUFFICIENT':'INSUFFICIENT_CAPACITY';result.statusLabel=result.observedCapacityFitsEstimate?'CAPACIDAD ESTIMADA SUFICIENTE':'CAPACIDAD INSUFICIENTE';result.Result=result.observedCapacityFitsEstimate?'PASS':'FAIL';
 return result;
}
function probeVolumes(roots){
 // Process-only policy for this fixed read-only probe; no persistent policy changes.
 const output=execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'Get-BackupVolumes.ps1')],{input:JSON.stringify(roots.map(r=>r.Ruta)),encoding:'utf8',windowsHide:true});
 const data=JSON.parse(output.replace(/^\uFEFF/,''));return Array.isArray(data)?data:[data];
}
async function review({query=queryJson,probe=probeVolumes,write=(p,text)=>fs.writeFileSync(p,text),now}={}){
 let result;
 try {
 const policy=(await query("SELECT dbo.P3_INT_Destino() DdlTarget,(SELECT CONVERT(varchar(36),database_guid) FROM sys.database_recovery_status WHERE database_id=DB_ID()) DatabaseGuid,(SELECT CONVERT(varchar(36),DatabaseGuid) FROM dbo.P4_LDF_Configuracion WHERE Id=1) LdfGuid,(SELECT Enabled FROM dbo.BackupsSchedule WHERE Id=1) Enabled,(SELECT is_disabled FROM sys.triggers WHERE name='P3_DDL_CapturarEstructura') DdlDisabled,(SELECT COUNT(*) FROM sys.crypt_properties WHERE major_id IN(OBJECT_ID('dbo.P4_LDF_Consultar'),OBJECT_ID('dbo.P4_LDF_RespaldarLog'))) LdfSignatures",target))[0];
 const roots=await query('SELECT Ruta FROM (SELECT Ruta FROM dbo.BackupsConfig WHERE Id=1 UNION SELECT RutaBackup FROM dbo.P4_LDF_Configuracion WHERE Id=1) roots',target);
 const backups=await query("SELECT b.type Type,b.is_copy_only CopyOnly,CONVERT(varchar(30),MAX(b.backup_size)) MaxBytes FROM msdb.dbo.backupset b WHERE b.database_name=DB_NAME() AND b.family_guid=(SELECT family_guid FROM sys.database_recovery_status WHERE database_id=DB_ID()) AND b.backup_finish_date IS NOT NULL GROUP BY b.type,b.is_copy_only",target);
 const sourceFiles=await query('SELECT type_desc Type,CONVERT(varchar(30),SUM(CONVERT(bigint,size))*8192) Bytes FROM sys.database_files GROUP BY type_desc',target);
 let volumes=[],probeError;try{volumes=await probe(roots);}catch(e){probeError=e.message;}
 result=assessCapacity({policy,roots,volumes,backups,sourceFiles},{now:now||new Date()});if(probeError)result.reasons.push('Destination probing failed: '+probeError);
 } catch(e) {result=assessCapacity({},{now:now||new Date()});result.reasons.push('Assessment failed: '+e.message);}
 write(path.join(root,'.data/p4-capacity-review.json'),JSON.stringify(result,null,2));return result;
}
if(require.main===module)review().then(r=>{console.log(JSON.stringify(r,null,2));if(r.Result!=='PASS')process.exitCode=1;}).catch(e=>{console.error(e.message);process.exitCode=1;});
module.exports={review,assessCapacity,probeVolumes};
