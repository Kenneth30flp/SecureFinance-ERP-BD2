'use strict';
const { sql, getPool } = require('../config/database');
const { createProductoService } = require('./productoService');
const { createInventarioService } = require('./inventarioService');

function createDashboardService(poolProvider = getPool) {
  return {
    // Extension point: Jose's analytics can be composed here when installed.
    // Existing permission-checked procedures remain the source of operational data.
    async obtenerOperacion(usuarioId, permisos = []) {
      if (!permisos.includes('INVENTARIO_CONSULTAR')) return null;
      const productos=createProductoService(poolProvider), inventario=createInventarioService(poolProvider);
      const estado=(await inventario.state(usuarioId))[0];
      if(!estado)throw new Error('Estado de inventario no disponible.');
      const pendientes=[];let total=0,criticos=0;
      for(let offset=0;;offset+=50){
        const page=await productos.list(usuarioId,{inventario:true,offset});
        for(const p of page.slice(0,50))if(p.Activo&&p.Stock<=p.PuntoReorden){
          total++;if(p.Stock<=p.StockMinimo)criticos++;pendientes.push(p);
        }
        if(page.length<=50)break;
        if(offset>=1000000)throw new Error('Consulta operativa incompleta.');
      }
      pendientes.sort((a,b)=>(a.Stock-a.StockMinimo)-(b.Stock-b.StockMinimo)||a.ProductoId-b.ProductoId);
      return {habilitado:!!estado.Habilitado,total,criticos,productos:pendientes.slice(0,5)};
    },
    async obtenerResumen(usuarioId) {
      const pool = await poolProvider();
      const result = await pool.request().input('UsuarioId', sql.Int, usuarioId)
        .execute('dbo.sp_ObtenerResumenDashboard');
      const resumen = result.recordset?.[0];
      if (result.recordset?.length !== 1 || !resumen
        || (resumen.VentasDia !== null && !/^\d+\.\d{2}$/.test(resumen.VentasDia))
        || ['FacturasDia', 'ProductosStockBajo', 'EventosDMLDia'].some((campo) => resumen[campo] !== null && !/^\d+$/.test(resumen[campo]))
        || !/^\d{4}-\d{2}-\d{2}$/.test(resumen.FechaOperacion)
        || (resumen.RolesActuales !== null && typeof resumen.RolesActuales !== 'string')) {
        throw new Error('Resumen operativo no válido.');
      }
      return resumen;
    },
  };
}
module.exports = { createDashboardService };
