'use strict';
const sql=require('mssql');
const {randomUUID}=require('node:crypto');
const v=require('./validation');
const {plan,commands,literal}=require('./planner');
function config(env=process.env) {
  const get=k=>{if(!env[k])throw new Error('Falta '+k);return env[k];};
  const user=get('BACKUPS_DB_USER');
  if(user.toLowerCase()==='sa'||user.toLowerCase()===(env.DB_USER||'').toLowerCase())throw new Error('Use un login DBA dedicado distinto de la cuenta web y sa.');
  const port=Number(env.BACKUPS_DB_PORT||1433);
  if(!Number.isInteger(port)||port<1||port>65535)throw new Error('Puerto SQL inválido.');
  for(const key of ['BACKUPS_DB_ENCRYPT','BACKUPS_DB_TRUST_SERVER_CERTIFICATE'])if(env[key]!==undefined&&!['true','false'].includes(env[key]))throw new Error('Valor booleano inválido: '+key);
  return {server:get('BACKUPS_DB_SERVER'),port,database:get('BACKUPS_DB_NAME'),user,password:get('BACKUPS_DB_PASSWORD'),requestTimeout:0,pool:{max:1,min:1},options:{encrypt:env.BACKUPS_DB_ENCRYPT!=='false',trustServerCertificate:env.BACKUPS_DB_TRUST_SERVER_CERTIFICATE==='true',appName:'SecureFinance-UC13-Worker',useUTC:true}};
}
function slots(from,to) {
  const out=[]; const end=Math.floor(to.getTime()/900000)*900000;
  for(let t=Math.floor(from.getTime()/900000)*900000+900000;t<=end;t+=900000){
    const d=new Date(t), midnight=d.getUTCHours()===0&&d.getUTCMinutes()===0;
    if(midnight&&d.getUTCDay()===0)out.push({slot:d.toISOString()+'_FULL',type:'FULL',missed:end-t>=900000});
    if(midnight)out.push({slot:d.toISOString()+'_DIFF',type:'DIFF',missed:end-t>=900000});
    out.push({slot:d.toISOString()+'_LOG',type:'LOG',missed:end-t>=900000});
  } return out;
}
async function catalog(pool) {
  return (await pool.request().query(`SELECT b.backup_set_id AS Id,b.database_name AS DatabaseName,b.type AS Type,
    CONVERT(varchar(23),b.backup_start_date,126) AS Start,CONVERT(varchar(23),b.backup_finish_date,126) AS Finish,
    CONVERT(varchar(30),b.first_lsn) AS FirstLSN,CONVERT(varchar(30),b.last_lsn) AS LastLSN,
    CONVERT(varchar(30),b.checkpoint_lsn) AS CheckpointLSN,CONVERT(varchar(30),b.differential_base_lsn) AS BaseLSN,
    CONVERT(varchar(36),b.backup_set_uuid) AS UUID,CONVERT(varchar(36),b.family_guid) AS Family,
    CONVERT(varchar(36),b.first_recovery_fork_guid) AS FirstFork,CONVERT(varchar(36),b.last_recovery_fork_guid) AS Fork,
    b.has_backup_checksums AS Checksum,b.is_damaged AS Damaged,b.is_copy_only AS CopyOnly,b.has_bulk_logged_data AS Bulk,
    b.recovery_model AS RecoveryModel,b.position AS Position,m.physical_device_name AS Path
    FROM msdb.dbo.backupset b JOIN msdb.dbo.backupmediafamily m ON m.media_set_id=b.media_set_id
    WHERE b.database_name=DB_NAME() AND b.backup_finish_date IS NOT NULL AND m.device_type=2
    AND (SELECT COUNT(*) FROM msdb.dbo.backupmediafamily x WHERE x.media_set_id=b.media_set_id)=1
    ORDER BY b.backup_set_id`)).recordset;
}
async function inspect(pool,p,root) {
  let files;
  for(const row of p.chain) {
    if(!row.Path.toLowerCase().startsWith(root.toLowerCase()) || row.Path.slice(root.length).includes('\\') || !/^[a-zA-Z0-9_.-]+$/.test(row.Path.slice(root.length)))throw new Error('Medio fuera de la ruta autorizada.');
    const device=' FROM DISK = '+literal(row.Path)+' WITH FILE = '+row.Position;
    const headers=(await pool.request().query('RESTORE HEADERONLY'+device+';')).recordset;
    const h=headers.find(x=>x.Position===row.Position);
    if(!h||String(h.BackupSetGUID).toLowerCase()!==row.UUID.toLowerCase()||h.DatabaseName!==p.source||!h.HasBackupChecksums||h.IsDamaged)throw new Error('El medio no coincide con el catálogo.');
    await pool.request().query('RESTORE VERIFYONLY'+device+', CHECKSUM;');
    const current=(await pool.request().query('RESTORE FILELISTONLY'+device+';')).recordset;
    if(!current.length||current.some(f=>!['D','L'].includes(f.Type)))throw new Error('Topología de archivos no compatible.');
    if(!files) {
      if(current.some(f=>!f.IsPresent))throw new Error('FULL incompleto.');
      files=current;
    } else {
      // LOG/DIFF may list files whose contents are not present in that backup.
      // Every listed file must map to a file moved by the initial FULL.
      const signature=f=>JSON.stringify([f.LogicalName,f.Type,String(f.UniqueID)]);
      const initial=new Set(files.map(signature));
      if(current.some(f=>!initial.has(signature(f))))throw new Error('Archivos nuevos dentro de la cadena. Requiere intervención DBA.');
    }
  }
  return files;
}
async function executeRestore(pool,p,statements) {
  let created;
  for(let i=0;i<statements.length;i++) {
    const request=pool.request().input('target',sql.NVarChar(128),p.target);
    let guard="IF ISNULL(APPLOCK_MODE('public','UC13_WORKER','Session'),'NoLock')<>'Exclusive' THROW 58004,'Sesion exclusiva perdida.',1; ";
    if(i===0)guard+="IF DB_ID(@target) IS NOT NULL THROW 58004,'El destino ya existe.',1; ";
    else {
      request.input('createdId',sql.Int,created.Id).input('createdAt',sql.DateTime,created.Created);
      guard+="IF NOT EXISTS(SELECT 1 FROM sys.databases WHERE name=@target AND database_id=@createdId AND create_date=@createdAt AND state_desc='RESTORING') THROW 58004,'El destino cambio.',1; ";
    }
    const state=(await request.query(guard+statements[i]+" SELECT database_id AS Id,create_date AS Created,state_desc AS State FROM sys.databases WHERE name=@target;")).recordset?.[0];
    if(!state)throw new Error('Destino no confirmado.');
    created ||= state;
    if(state.State==='ONLINE') {
      if(p.chain[i].Type!=='L')throw new Error('Recuperación prematura.');
      return {destino:p.target,punto:p.when,estado:state.State};
    }
    if(state.State!=='RESTORING')throw new Error('Estado de recuperación inesperado.');
  }
  throw new Error('SQL no confirmó alcanzar STOPAT; se conserva la base sin recuperar.');
}
async function run(pool,env=process.env) {
  const root=v.directory(env.BACKUPS_ROOT),restoreRoot=v.directory(env.BACKUPS_RESTORE_ROOT);
  const identity=(await pool.request().query("SELECT DB_NAME() AS Db,IS_SRVROLEMEMBER('sysadmin') AS IsAdmin;")).recordset[0];
  if(identity.IsAdmin!==0)throw new Error('El ejecutor no debe ser sysadmin.');
  const locked=(await pool.request().query("DECLARE @r int; EXEC @r=sys.sp_getapplock @Resource='UC13_WORKER',@LockMode='Exclusive',@LockOwner='Session',@LockTimeout=0; SELECT @r AS Code;")).recordset[0].Code;
  if(locked<0)return {busy:true};
  try {
    // A lost session releases the lock. Unfinished jobs are uncertain and never retried automatically.
    await pool.request().query("UPDATE dbo.BackupsJob SET Estado='INCIERTO',Fin=SYSUTCDATETIME() WHERE Estado='EJECUTANDO'; UPDATE dbo.BackupsSchedule SET HeartbeatUtc=SYSUTCDATETIME() WHERE Id=1;");
    const s=(await pool.request().query('SELECT *,SYSUTCDATETIME() AS NowUtc FROM dbo.BackupsSchedule WHERE Id=1;')).recordset[0];
    if(s.Enabled) {
      // Bound recovery to 31 days; preserve the older gap explicitly in a job.
      let from=s.CursorUtc;
      if(s.NowUtc-from>31*86400000) {
        await pool.request().input('id',sql.UniqueIdentifier,randomUUID()).input('gap',sql.NVarChar(sql.MAX),JSON.stringify({desde:from,hasta:new Date(s.NowUtc-31*86400000)})).query("INSERT dbo.BackupsJob(Id,Tipo,Estado,Resultado) VALUES(@id,'LOG','OMITIDO',@gap);");
        from=new Date(s.NowUtc-31*86400000);
      }
      for(const slot of slots(from,s.NowUtc)) {
        await pool.request().input('id',sql.UniqueIdentifier,randomUUID()).input('slot',sql.VarChar(40),slot.slot).input('type',sql.VarChar(10),slot.type).input('status',sql.VarChar(20),slot.missed?'OMITIDO':'PENDIENTE').query("IF NOT EXISTS(SELECT 1 FROM dbo.BackupsJob WHERE Slot=@slot) INSERT dbo.BackupsJob(Id,Tipo,Slot,Estado) VALUES(@id,@type,@slot,@status);");
      }
      await pool.request().input('now',sql.DateTime2,s.NowUtc).query('UPDATE dbo.BackupsSchedule SET CursorUtc=@now WHERE Id=1;');
    }
    let rows=await catalog(pool);
    await pool.request().query("UPDATE dbo.BackupsJob SET Estado='OMITIDO',Fin=SYSUTCDATETIME() WHERE Estado='PENDIENTE' AND Slot IS NOT NULL AND TRY_CONVERT(datetime2,LEFT(Slot,23),126)<DATEADD(minute,-15,SYSUTCDATETIME());");
    const jobs=(await pool.request().query("SELECT TOP(20) * FROM dbo.BackupsJob WHERE Estado='PENDIENTE' AND (Slot IS NULL OR EXISTS(SELECT 1 FROM dbo.BackupsSchedule WHERE Id=1 AND Enabled=1)) ORDER BY Creado,CASE Tipo WHEN 'FULL' THEN 0 WHEN 'DIFF' THEN 1 ELSE 2 END;")).recordset;
    for(const job of jobs) {
      const held=(await pool.request().query("SELECT APPLOCK_MODE('public','UC13_WORKER','Session') AS Mode;")).recordset[0].Mode;
      if(held!=='Exclusive')throw new Error('Se perdió la sesión exclusiva del ejecutor.');
      await pool.request().input('id',sql.UniqueIdentifier,job.Id).query("UPDATE dbo.BackupsJob SET Estado='EJECUTANDO',Inicio=SYSUTCDATETIME() WHERE Id=@id; INSERT dbo.BackupsAudit(JobId,Evento,ActorUsuarioId) SELECT Id,'EJECUTANDO',ActorUsuarioId FROM dbo.BackupsJob WHERE Id=@id;");
      try {
        if(job.ActorUsuarioId!==null)await pool.request().input('ActorUsuarioId',sql.Int,job.ActorUsuarioId).input('Permiso',sql.NVarChar(100),'DBA_BACKUPS_'+(['PLAN','RESTORE'].includes(job.Tipo)?'RESTAURAR':'EJECUTAR')).execute('dbo.sp_ParteII_ValidarPermiso');
        let result,stored=null;
        if(['FULL','DIFF','LOG'].includes(job.Tipo)) {
          result=(await pool.request().input('TipoBackup',sql.VarChar(4),job.Tipo).input('RutaDestino',sql.NVarChar(240),root).query("IF ISNULL(APPLOCK_MODE('public','UC13_WORKER','Session'),'NoLock')<>'Exclusive' THROW 58004,'Sesion exclusiva perdida.',1; EXEC dbo.sp_EjecutarBackupEstrategico @TipoBackup,@RutaDestino;")).recordset;
          rows=await catalog(pool);
        } else if(job.Tipo==='PLAN') {
          const p=plan(rows,job.Punto,job.Destino,identity.Db);
          const files=await inspect(pool,p,root);p.fileToken=randomUUID();p.commands=commands(p,files,restoreRoot);p.root=restoreRoot;
          stored=JSON.stringify(p);result={plan:p.commands,medios:p.chain.map(r=>r.Id),destino:p.target,punto:p.when};
        } else {
          const previous=(await pool.request().input('id',sql.UniqueIdentifier,job.PlanId).query("SELECT * FROM dbo.BackupsJob WHERE Id=@id AND Tipo='PLAN' AND Estado='COMPLETADO' AND Fin>DATEADD(minute,-30,SYSUTCDATETIME());")).recordset[0];
          if(!previous||previous.ActorUsuarioId!==job.ActorUsuarioId)throw new Error('Plan vencido o ajeno.');
          const p=JSON.parse(previous.PlanJson);v.target(p.target);
          if(p.source!==identity.Db||p.target.toLowerCase()===identity.Db.toLowerCase()||p.root!==restoreRoot)throw new Error('Destino protegido o configuración modificada.');
          const exists=(await pool.request().input('name',sql.NVarChar(128),p.target).query('SELECT DB_ID(@name) AS Id;')).recordset[0].Id;
          if(exists!==null)throw new Error('La base destino ya existe.');
          const files=await inspect(pool,p,root), statements=commands(p,files,restoreRoot);
          if(JSON.stringify(statements)!==JSON.stringify(p.commands))throw new Error('El plan cambió.');
          result=await executeRestore(pool,p,statements);
        }
        await pool.request().input('id',sql.UniqueIdentifier,job.Id).input('result',sql.NVarChar(sql.MAX),JSON.stringify(result)).input('plan',sql.NVarChar(sql.MAX),stored).query("UPDATE dbo.BackupsJob SET Estado='COMPLETADO',Fin=SYSUTCDATETIME(),Resultado=@result,PlanJson=@plan WHERE Id=@id; INSERT dbo.BackupsAudit(JobId,Evento,ActorUsuarioId) SELECT Id,'COMPLETADO',ActorUsuarioId FROM dbo.BackupsJob WHERE Id=@id;");
      } catch(e) {
        await pool.request().input('id',sql.UniqueIdentifier,job.Id).input('number',sql.Int,Number.isInteger(e.number)?e.number:null).input('result',sql.NVarChar(sql.MAX),JSON.stringify({error:e instanceof v.ValidationError?e.message:'Falló la operación. Revisar SQL y medios; una recuperación parcial se conserva para inspección.',codigo:e.code||null})).query("UPDATE dbo.BackupsJob SET Estado='FALLIDO',Fin=SYSUTCDATETIME(),ErrorNumero=@number,Resultado=@result WHERE Id=@id; INSERT dbo.BackupsAudit(JobId,Evento,ActorUsuarioId) SELECT Id,'FALLIDO',ActorUsuarioId FROM dbo.BackupsJob WHERE Id=@id;");
        console.error('UC13_JOB_FAILED',job.Id,e.number||e.code||e.name);process.exitCode=1;
      }
    }
    await pool.request().input('json',sql.NVarChar(sql.MAX),JSON.stringify(rows)).query("UPDATE dbo.BackupsCatalog SET JsonData=@json,Actualizado=SYSUTCDATETIME() WHERE Id=1; IF @@ROWCOUNT=0 INSERT dbo.BackupsCatalog(Id,JsonData) VALUES(1,@json); UPDATE dbo.BackupsSchedule SET HeartbeatUtc=SYSUTCDATETIME() WHERE Id=1;");
    return {processed:jobs.length};
  } finally {await pool.request().query("EXEC sys.sp_releaseapplock @Resource='UC13_WORKER',@LockOwner='Session';");}
}
module.exports={config,slots,catalog,inspect,executeRestore,run};
