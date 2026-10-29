'use strict';
const fs=require('fs'),{spawnSync}=require('child_process'),assert=require('assert/strict'),os=require('os'),path=require('path');const lab=require('../../database/tests/promocionesLab');
(async()=>{const state=lab.readState();const identity=await lab.labJson('SELECT DB_NAME() N,dbo.P3_INT_Destino() A');assert.equal(identity[0].A,state.lab);fs.mkdirSync(path.join(os.tmpdir(),'opencode'),{recursive:true});
for(const name of ['P3_CRE_Concurrencias','P3_BOD_Integraciones','P3_BOD_Concurrencias']){
 const file='.data/'+name+'.ps1';const source=fs.readFileSync('database/tests/'+name+'.ps1','utf8').replaceAll('SecureFinanceERP_Lab_Dylan',state.lab);fs.writeFileSync(file,source);
 const p=spawnSync('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',file],{encoding:'utf8',windowsHide:true,timeout:180000});fs.writeFileSync('docs/parte3/integracion-dylan/evidencias/'+name+'.txt',(p.stdout||'')+(p.stderr||''));console.log(name+' exit='+p.status);if(p.status!==0){console.error((p.stdout||'').slice(-1800));process.exitCode=1;}
}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
