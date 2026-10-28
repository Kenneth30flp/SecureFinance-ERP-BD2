'use strict';
const {sql,getPool}=require('../../config/database');
function createCotizacionService(provider=getPool) {
  async function call(name,actor,params=[]) {
    const r=(await provider()).request().input('ActorUsuarioId',sql.Int,actor);
    for(const [key,type,value] of params) {
      if(type instanceof sql.Table) r.input(key,type);
      else r.input(key,type,value??null);
    }
    return (await r.execute(name)).recordsets;
  }
  return {
    async catalogs(actor) {
      const [clientes,productos,politicas]=await call('dbo.P3_COT_Catalogos',actor);
      return {clientes,productos,politica:politicas[0]};
    },
    async create(actor,d) {
      const table=new sql.Table('dbo.TipoDetalleVentaDescuento');
      table.columns.add('ProductoId',sql.Int,{nullable:false});table.columns.add('Cantidad',sql.Int,{nullable:false});table.columns.add('DescuentoPorcentaje',sql.Decimal(5,2),{nullable:false});
      for(const l of d.Detalle) table.rows.add(l.ProductoId,l.Cantidad,l.DescuentoPorcentaje);
      return (await call('dbo.P3_COT_Crear',actor,[['ClienteId',sql.Int,d.ClienteId],['VenceEn',sql.DateTime2(3),d.VenceEn],['Detalle',table,undefined],['OperacionId',sql.UniqueIdentifier,d.OperacionId],['Observaciones',sql.NVarChar(sql.MAX),d.Observaciones]]))[0][0];
    },
    async list(actor,f) {
      return (await call('dbo.P3_COT_Consultar',actor,[['Numero',sql.NVarChar(14),f.numero||null],['Cliente',sql.NVarChar(150),f.cliente||null],['Estado',sql.VarChar(15),f.estado||null],['Desde',sql.DateTime2(3),f.Desde],['Hasta',sql.DateTime2(3),f.Hasta],['Desplazamiento',sql.Int,(f.pagina-1)*20]]))[0];
    },
    async detail(actor,id) {
      const [header,lines,history]=await call('dbo.P3_COT_Consultar',actor,[['Id',sql.Int,id]]);
      return {documento:header[0]||null,lineas:lines||[],historial:history||[]};
    },
    async cancel(actor,id,operation,reason) {
      return (await call('dbo.P3_COT_Cancelar',actor,[['CotizacionId',sql.Int,id],['OperacionId',sql.UniqueIdentifier,operation],['Motivo',sql.NVarChar(sql.MAX),reason]]))[0][0];
    },
  };
}
module.exports={createCotizacionService};
