'use strict';
const { sql, getPool } = require('../config/database');
const { localDayBoundary } = require('../public/js/operationalDates');
function createFacturaService(provider = getPool) {
  return {
    async list(actor, f) {
      const result = await (await provider()).request().input('ActorUsuarioId',sql.Int,actor)
        .input('FacturaId',sql.Int,f.numero).input('Cliente',sql.NVarChar(150),f.cliente || null)
        .input('Desde',sql.DateTime2(3),localDayBoundary(f.desde))
        .input('Hasta',sql.DateTime2(3),localDayBoundary(f.hasta,true))
        .input('Desplazamiento',sql.Int,(f.pagina-1)*20).input('Limite',sql.Int,20)
        .execute('dbo.sp_ERP_ConsultarFacturas');
      return result.recordset || [];
    },
    async detail(actor, id) {
      const result = await (await provider()).request().input('ActorUsuarioId',sql.Int,actor)
        .input('FacturaId',sql.Int,id).execute('dbo.sp_ERP_ConsultarComprobante');
      return { factura:result.recordsets?.[0]?.[0] || null, detalle:result.recordsets?.[1] || [] };
    },
  };
}
module.exports = { createFacturaService };
