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
    async form(actor){
      return {politica:(await call('dbo.P3_COT_PrepararFormulario',actor))[0][0]};
    },
    async search(actor,clase,buscar,pagina=1){
      const rows=(await call('dbo.P3_COT_BuscarCatalogo',actor,[['Clase',sql.VarChar(10),clase],['Buscar',sql.NVarChar(150),buscar],['Pagina',sql.Int,pagina],['Limite',sql.Int,8]]))[0];
      return {rows:rows.slice(0,8),next:rows.length>8,pagina};
    },
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
    async readiness(actor,id) {
      try {
        const sets=await call('dbo.P3_COT_EstadoConversion',actor,[['CotizacionId',sql.Int,id]]);
        const row=sets[0]?.[0];
        return {installed:row?.Instalado===true,executable:row?.Ejecutar===true,allowed:row?.Permitido===true,database:row?.BaseDatos};
      } catch(error) {
        if(error.number===2812) return {installed:false,executable:false,allowed:false};
        throw error;
      }
    },
    async convert(actor,id,operation) {
      const [header,lines,metadata]=await call('dbo.sp_ConvertirCotizacionAFactura',actor,[['CotizacionId',sql.Int,id],['OperacionId',sql.UniqueIdentifier,operation]]);
      const factura=header?.[0],documento=metadata?.[0];
      if(!documento||documento.CotizacionId!==id||documento.Estado!=='PROCESADA'
        ||!Number.isInteger(documento.FacturaId)||documento.FacturaId<1||factura?.FacturaId!==documento.FacturaId
        ||String(documento.OperacionId).toLowerCase()!==operation.toLowerCase()) throw Error('Respuesta de conversion incompatible.');
      return {documento,factura:{...factura,Detalle:lines||[]}};
    },
  };
}
module.exports={createCotizacionService};
