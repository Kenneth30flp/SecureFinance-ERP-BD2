'use strict';
const {spawn}=require('node:child_process');
const readline=require('node:readline');
function labAdmin(){
 const process=spawn('powershell',['-NoProfile','-ExecutionPolicy','Bypass','-File','database/tests/CotizacionesLabAdmin.ps1'],{windowsHide:true,stdio:['pipe','pipe','pipe']});
 let sequence=0;const pending=new Map();let stderr='';
 process.stderr.on('data',d=>{stderr+=d;});
 readline.createInterface({input:process.stdout}).on('line',line=>{
  let result;try{result=JSON.parse(line);}catch{return;}
  const task=pending.get(result.id);if(!task)return;pending.delete(result.id);clearTimeout(task.timer);
  result.error?task.reject(Object.assign(Error(result.error),{number:result.number})):task.resolve(result.sets);
 });
 process.on('exit',code=>{for(const task of pending.values()){clearTimeout(task.timer);task.reject(Error('Lab admin exit '+code+' '+stderr.slice(0,600)));}pending.clear();});
 return {
  query(sql){return new Promise((resolve,reject)=>{const id=++sequence,timer=setTimeout(()=>{pending.delete(id);reject(Error('Lab admin timeout'));},50000);pending.set(id,{resolve,reject,timer});process.stdin.write(JSON.stringify({id,sql})+'\n');});},
  close(){process.stdin.end();},
 };
}
module.exports={labAdmin};
