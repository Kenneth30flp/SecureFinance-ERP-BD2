'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),path=require('node:path');
const {assessCapacity,review}=require('../../../scripts/parte4/backups/capacity-review.cjs');
const now=new Date('2026-11-04T18:00:00Z'),GiB=1024n**3n;
const guid='12345678-1234-1234-1234-123456789012';
function input(){return {policy:{DdlTarget:'SecureFinanceERP',DatabaseGuid:guid,LdfGuid:guid,Enabled:false,DdlDisabled:false,LdfSignatures:3},roots:[{Ruta:'C:\\Backups\\'}],volumes:[{Root:'C:\\Backups\\',VolumeId:'\\\\?\\Volume{12345678-1234-1234-1234-123456789012}\\',FreeBytes:String(1000n*GiB),TotalBytes:String(2000n*GiB),SampledAtUTC:now.toISOString()}],backups:[{Type:'D',CopyOnly:false,MaxBytes:String(GiB)},{Type:'I',CopyOnly:false,MaxBytes:String(GiB/4n)},{Type:'L',CopyOnly:false,MaxBytes:String(8n*1024n**2n)}]};}
test('Capacity: operational D/I/L projection uses exact BigInt, retains reserve and never approves retention',()=>{
 const r=assessCapacity(input(),{now});assert.equal(r.Result,'PASS');assert.equal(r.status,'SUFFICIENT');assert.equal(r.estimatedAdditionalBytes,String((3n*GiB+14n*(GiB/4n)+1344n*8n*1024n**2n)*4n));assert.equal(r.retention.activationApproved,false);assert.equal(r.automaticScheduleEnabled,false);
});
test('Capacity: empty, missing series and COPY_ONLY-only history are insufficient information',()=>{
 for(const mutate of [d=>d.backups=[],d=>d.backups=d.backups.slice(0,2),d=>d.backups=d.backups.map(b=>({...b,CopyOnly:true})),d=>d.backups[2].MaxBytes='0',d=>d.backups[2].MaxBytes='NaN']){
  const d=input();mutate(d);const r=assessCapacity(d,{now});assert.equal(r.status,'INSUFFICIENT_INFORMATION');assert.equal(r.statusLabel,'INFORMACIÓN INSUFICIENTE');assert.equal(r.observedCapacityFitsEstimate,false);assert.equal(r.estimatedAdditionalBytes,null);
 }
 const d=input();d.backups.push({Type:'L',CopyOnly:true,MaxBytes:String(1000n*GiB)});assert.equal(assessCapacity(d,{now}).estimatedAdditionalBytes,assessCapacity(input(),{now}).estimatedAdditionalBytes);
});
test('Capacity: every authorized destination must have one fresh valid actual volume measurement',()=>{
 for(const mutate of [d=>d.volumes=[],d=>d.roots.push({Ruta:'D:\\Backups\\'}),d=>d.volumes.push({...d.volumes[0]}),d=>d.volumes[0].SampledAtUTC='2026-11-04T17:54:59Z',d=>d.volumes[0].SampledAtUTC='2026-11-04T18:02:00Z',d=>d.volumes[0].FreeBytes='-1',d=>d.volumes[0].VolumeId='',d=>d.roots[0].Ruta='C:\\Backups\\..\\Other',d=>d.roots=[]]){
  const d=input();mutate(d);const r=assessCapacity(d,{now});assert.equal(r.status,'INSUFFICIENT_INFORMATION');assert.equal(r.observedCapacityFitsEstimate,false);
 }
});
test('Capacity: insufficient destination space is distinct from missing evidence',()=>{
 const d=input();d.volumes[0].FreeBytes='1';const r=assessCapacity(d,{now});assert.equal(r.status,'INSUFFICIENT_CAPACITY');assert.equal(r.Result,'FAIL');assert(BigInt(r.estimatedAdditionalBytes)>0n);
});
test('Capacity: shared volumes, conflicting samples and identity/DDL/schedule guards',()=>{
 const d=input();d.roots.push({Ruta:'C:\\LDF\\'});d.volumes.push({...d.volumes[0],Root:'C:\\LDF\\'});assert.equal(assessCapacity(d,{now}).Result,'PASS');d.volumes[1].FreeBytes='1';assert.equal(assessCapacity(d,{now}).status,'INSUFFICIENT_INFORMATION');
 for(const changes of [{Enabled:true},{DdlDisabled:true},{LdfSignatures:2},{LdfGuid:'different'},{DatabaseGuid:null},{DatabaseGuid:'bad',LdfGuid:'bad'},{DdlTarget:'other'}]){const x=input();Object.assign(x.policy,changes);assert.equal(assessCapacity(x,{now}).observedCapacityFitsEstimate,false);}
});
test('Capacity review orchestration uses only injected SQL, destination probe and writer',async()=>{
 const d=input(),calls=[],writes=[];
 const query=async sql=>{calls.push(sql);if(sql.includes('DdlTarget'))return [d.policy];if(sql.includes('SELECT Ruta FROM'))return d.roots;if(sql.includes('backupset b'))return d.backups;return [];};
 const r=await review({now,query,probe:roots=>{assert.deepEqual(roots,d.roots);return d.volumes;},write:(p,text)=>writes.push({p,data:JSON.parse(text)})});
 assert.equal(r.Result,'PASS');assert.equal(writes.length,1);assert(path.isAbsolute(writes[0].p));assert(calls.every(q=>q.startsWith('SELECT ')));assert(!calls.some(q=>/\b(BACKUP|RESTORE|UPDATE|INSERT|ALTER|DELETE|EXEC)\b/i.test(q)));
 const failed=await review({now,query,probe:()=>{throw Error('No volume evidence');},write:()=>{}});assert.equal(failed.status,'INSUFFICIENT_INFORMATION');assert.equal(failed.Result,'FAIL');
 let saved;await review({now,query:()=>{throw Error('SQL unavailable');},probe:()=>{throw Error('Must not probe');},write:(p,text)=>{saved=JSON.parse(text);}});assert.equal(saved.Result,'FAIL');assert.equal(saved.status,'INSUFFICIENT_INFORMATION');
});
