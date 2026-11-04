'use strict';
const v=require('./validation');
const literal=s=>"N'"+String(s).replaceAll("'","''")+"'";
const identifier=s=>'['+String(s).replaceAll(']',']]')+']';
function plan(rows, when, name, source) {
  v.point(when); v.target(name);
  if(name.toLowerCase()===source.toLowerCase()) throw new v.ValidationError('La base original está protegida.');
  const cutoff=when+'.000',time=s=>s.length===19?s+'.000':s;
  const valid=rows.filter(r=>r.DatabaseName===source && r.Checksum && !r.Damaged && r.RecoveryModel==='FULL' && !r.Bulk && r.Path && Number.isInteger(r.Position));
  const full=valid.filter(r=>r.Type==='D'&&!r.CopyOnly&&time(r.Finish)<=cutoff).sort((a,b)=>b.Finish.localeCompare(a.Finish))[0];
  if(!full) throw new v.ValidationError('No existe FULL compatible anterior al punto solicitado.');
  const same=r=>r.Fork===full.Fork && r.Family===full.Family && r.FirstFork===r.Fork;
  const diff=valid.filter(r=>r.Type==='I'&&same(r)&&r.BaseLSN===full.CheckpointLSN&&time(r.Finish)<=cutoff).sort((a,b)=>b.Finish.localeCompare(a.Finish))[0];
  const chain=diff?[full,diff]:[full]; let end=BigInt((diff||full).LastLSN);
  // The first LOG after a restored database can span the recovery fork. It is
  // usable from a FULL on the ending fork only when that FULL is past the fork point.
  const logs=valid.filter(r=>r.Type==='L'&&r.Fork===full.Fork&&r.Family===full.Family).sort((a,b)=>BigInt(a.LastLSN)<BigInt(b.LastLSN)?-1:1);
  for(const row of logs) {
    if(BigInt(row.LastLSN)<=end) continue;
    if(row.FirstFork!==row.Fork && (!/^\d+$/.test(row.ForkPointLSN||'') || BigInt(row.ForkPointLSN)>end || BigInt(row.ForkPointLSN)<BigInt(row.FirstLSN)))continue;
    if(BigInt(row.FirstLSN)>end) break;
    chain.push(row); end=BigInt(row.LastLSN);
    // Start strictly after STOPAT is conservative on pre-2022 servers without last_valid_restore_time.
    if(time(row.Start)>cutoff) return {target:name,when,source,chain};
  }
  throw new v.ValidationError('Cadena LOG incompleta: falta un log posterior al punto o hay una brecha LSN.');
}
function commands(p, files, root) {
  v.directory(root); v.target(p.target); v.point(p.when);
  if(typeof p.source!=='string'||p.source.toLowerCase()===p.target.toLowerCase())throw new v.ValidationError('La base original está protegida.');
  const checked=plan(p.chain,p.when,p.target,p.source);
  if(JSON.stringify(checked.chain)!==JSON.stringify(p.chain))throw new v.ValidationError('El plan no contiene una cadena canónica válida.');
  if(!files.length || files.some(f=>!['D','L'].includes(f.Type)||!f.IsPresent)) throw new v.ValidationError('Solo archivos de datos y log presentes son compatibles.');
  v.uuid(p.fileToken);
  const moves=files.map((f,i)=>'MOVE '+literal(f.LogicalName)+' TO '+literal(root+p.target+'_'+p.fileToken+'_'+i+(f.Type==='L'?'.ldf':i===0?'.mdf':'.ndf'))).join(', ');
  // STOPAT + RECOVERY leaves the database restoring until SQL reaches the point.
  // The executor MUST stop on ONLINE; never issue an unconditional final RECOVERY.
  return p.chain.map((r,i)=>`RESTORE ${r.Type==='L'?'LOG':'DATABASE'} ${identifier(p.target)} FROM DISK = ${literal(r.Path)} WITH FILE = ${r.Position}, CHECKSUM, ${r.Type==='L'?'RECOVERY':'NORECOVERY'}, STOPAT = ${literal(p.when)}${i===0?', '+moves:''};`);
}
module.exports={plan,commands,literal,identifier};
