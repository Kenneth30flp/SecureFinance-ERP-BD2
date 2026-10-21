'use strict';
const {sql}=require('../../config/database');
const procedures=Object.freeze({factura:'dbo.sp_Edward_ConsultarFactura',devoluciones:'dbo.sp_Edward_ConsultarDevoluciones',garantias:'dbo.sp_Edward_ConsultarGarantias',devolver:'dbo.sp_ProcesarDevolucionCliente',crear:'dbo.sp_CrearTicketGarantia',actualizar:'dbo.sp_ActualizarEstadoGarantia'});
const queryParams=f=>[['Id',sql.Int,f.id],['Desde',sql.DateTime2(3),f.desde],['Hasta',sql.DateTime2(3),f.hasta],['Desplazamiento',sql.Int,f.offset||0]];
module.exports={sql,procedures,queryParams};
