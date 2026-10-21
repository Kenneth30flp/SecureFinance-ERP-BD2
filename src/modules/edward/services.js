'use strict';
const {getPool}=require('../../config/database');
const {sql,procedures:p,queryParams}=require('./sqlContracts');
function createEdwardService(provider=getPool){
 async function execute(proc,actor,params=[]){
  const request=(await provider()).request().input('ActorUsuarioId',sql.Int,actor);
  for(const [name,type,value] of params)request.input(name,type,value??null);
  const result=await request.execute(proc);
  return (result.recordsets||[result.recordset||[]]).map(rows=>rows.map(row=>({...row,...(Buffer.isBuffer(row.Version)?{Version:row.Version.toString('hex')}:{})})));
 }
 return {
 factura:(actor,id,garantia=false)=>execute(p.factura,actor,[['FacturaId',sql.Int,id],['Garantia',sql.Bit,garantia]]),
 devoluciones:(actor,f)=>execute(p.devoluciones,actor,queryParams(f)),
 garantias:(actor,f)=>execute(p.garantias,actor,[...queryParams(f),['Buscar',sql.NVarChar(150),f.buscar||''],['Estado',sql.VarChar(15),f.estado]]),
 devolver:async(actor,b)=>(await execute(p.devolver,actor,[['FacturaId',sql.Int,b.FacturaId],['OperacionId',sql.UniqueIdentifier,b.OperacionId],['Motivo',sql.NVarChar(sql.MAX),b.Motivo],['Detalles',sql.NVarChar(sql.MAX),JSON.stringify(b.Detalles)]]))[0][0],
 crear:async(actor,b)=>(await execute(p.crear,actor,[['DetalleFacturaId',sql.Int,b.DetalleFacturaId],['OperacionId',sql.UniqueIdentifier,b.OperacionId],['Motivo',sql.NVarChar(sql.MAX),b.Motivo]]))[0][0],
 actualizar:async(actor,b)=>(await execute(p.actualizar,actor,[['TicketId',sql.Int,b.TicketId],['VersionEsperada',sql.Binary(8),b.Version],['Estado',sql.VarChar(15),b.Estado],['Diagnostico',sql.NVarChar(sql.MAX),b.Diagnostico],['Evidencia',sql.NVarChar(sql.MAX),b.Evidencia]]))[0][0],
 };
}
module.exports={createEdwardService};
