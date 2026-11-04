'use strict';
const {getPool,sql}=require('../../../config/database');
function createBackupsService(pool=getPool) {
  async function call(proc,actor,params={}) { const r=(await pool()).request().input('ActorUsuarioId',sql.Int,actor); for(const [k,t,value] of Object.values(params)) r.input(k,t,value); return r.execute(proc); }
  return {
    async dashboard(actor) { const r=await call('dbo.sp_BackupsConsultar',actor); if(!r.recordsets||r.recordsets.length!==3||r.recordsets.some(s=>!Array.isArray(s))||r.recordsets[1].length!==1)throw new Error('Contrato UC13 incompatible.'); return {jobs:r.recordsets[0],schedule:r.recordsets[1],catalog:r.recordsets[2]}; },
    async submit(actor,d) { const r=await call('dbo.sp_BackupsSolicitar',actor,[['Id',sql.UniqueIdentifier,d.id],['Tipo',sql.VarChar(10),d.type],['Punto',sql.VarChar(19),d.point||null],['Destino',sql.NVarChar(128),d.target||null],['PlanId',sql.UniqueIdentifier,d.planId||null]]); const row=r.recordset?.[0];if(!row||String(row.Id).toLowerCase()!==d.id.toLowerCase()||!['PENDIENTE','EJECUTANDO','COMPLETADO','FALLIDO','INCIERTO','OMITIDO'].includes(row.Estado))throw new Error('Respuesta UC13 no confirmada.');return row; }
  };
}
module.exports={createBackupsService};
