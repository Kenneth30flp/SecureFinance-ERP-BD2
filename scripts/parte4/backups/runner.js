'use strict';
const path=require('node:path');
const fs=require('node:fs');
const sql=require('mssql');
const {config,run}=require('../../../src/modules/dba/backups/worker');
function loadEnvironment() {
  if(!process.env.BACKUPS_ENV_FILE||!path.isAbsolute(process.env.BACKUPS_ENV_FILE))throw new Error('Configure BACKUPS_ENV_FILE absoluto fuera del repositorio.');
  const file=fs.realpathSync(process.env.BACKUPS_ENV_FILE),repo=fs.realpathSync(path.resolve(__dirname,'../../..'));
  const relative=path.relative(repo,file);
  if(!relative||(!relative.startsWith('..'+path.sep)&&!path.isAbsolute(relative)))throw new Error('Los secretos deben estar fuera del repositorio.');
  const result=require('dotenv').config({path:file,quiet:true,override:true});if(result.error)throw result.error;
}
if(require.main===module)(async()=>{let pool;try {loadEnvironment();pool=await new sql.ConnectionPool(config()).connect();console.log(JSON.stringify(await run(pool)));}catch(e){console.error('UC13_WORKER_FAILURE',e.number||e.code||e.name);process.exitCode=1;}finally{if(pool)await pool.close();}})();
module.exports={loadEnvironment};
