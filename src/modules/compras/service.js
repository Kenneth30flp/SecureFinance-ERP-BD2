'use strict';
// Contrato sin rutas HTTP. El actor lo suministra el consumidor autenticado.
const {sql,getPool} = require('../../config/database');
const v = require('./validation');
function createComprasService(provider = getPool) {
  async function call(procedure, actor, parameters) {
    v.integer(actor);
    const request = (await provider()).request().input('ActorUsuarioId',sql.Int,actor);
    for (const [name,type,value] of parameters) request.input(name,type,value);
    const result = await request.execute(procedure);
    if (!Array.isArray(result.recordsets) || !result.recordsets.every(Array.isArray)) throw new Error('Respuesta SQL de Compras incompatible.');
    return result.recordsets.map(rows => rows.map(row => {
      const copy = {...row};
      for (const key of ['Version','VersionResultado']) if (Buffer.isBuffer(copy[key])) copy[key] = copy[key].toString('hex');
      for (const key of ['Total','Subtotal','CostoUnitario','CostoDocumentado']) if (Object.hasOwn(copy,key) &&
        (typeof copy[key]!=='string' || !/^\d+\.\d{4}$/.test(copy[key]))) throw new Error('Importe SQL de Compras incompatible.');
      for(const key of ['Valor','Promedio','CostoAplicado']) if(copy[key]!=null && (typeof copy[key]!=='string'||!/^\d+\.\d{8}$/.test(copy[key]))) throw new Error('Valoracion SQL de Compras incompatible.');
      return copy;
    }));
  }
  function confirmed(sets, operation, expectedState, id) {
    const row=sets[0]?.[0];
    if (sets[0]?.length!==1 || !row || !Number.isInteger(row.OrdenCompraId) || row.OrdenCompraId<1 ||
      (id!==undefined && row.OrdenCompraId!==id) || row.Estado!==expectedState ||
      typeof row.OperacionId!=='string' || row.OperacionId.toLowerCase()!==operation ||
      (expectedState==='BORRADOR' && (typeof row.Total!=='string' || row.Numero!=='OC-'+row.OrdenCompraId)) ||
      typeof row.Version!=='string' || !/^[0-9a-f]{16}$/i.test(row.Version)) throw new Error('Confirmacion SQL de Compras incompatible; consultar antes de reintentar.');
    return row;
  }
  const change = (procedure,state) => async (actor,data) => {
    const d = v.transition(data);
    return confirmed(await call(procedure,actor,[['OrdenCompraId',sql.Int,d.OrdenCompraId],['OperacionId',sql.UniqueIdentifier,d.OperacionId],['VersionEsperada',sql.Binary(8),d.Version],['Motivo',sql.NVarChar(sql.MAX),d.Motivo]]),d.OperacionId,state,d.OrdenCompraId);
  };
  return {
    async create(actor,data) {
      const d = v.create(data);
      return confirmed(await call('dbo.P3_COM_Crear',actor,[['ProveedorId',sql.Int,d.ProveedorId],['Detalle',sql.NVarChar(sql.MAX),JSON.stringify(d.Detalle)],['OperacionId',sql.UniqueIdentifier,d.OperacionId],['Observaciones',sql.NVarChar(sql.MAX),d.Observaciones]]),d.OperacionId,'BORRADOR');
    },
    async list(actor,{estado = null,offset = 0,buscar=''} = {}) {
      if ((estado !== null && !v.states.includes(estado)) || !Number.isInteger(offset) || offset < 0 || offset > 1000000) throw new TypeError('Filtros invalidos.');
      return (await call('dbo.P3_COM_Consultar',actor,[['Estado',sql.VarChar(25),estado],['Desplazamiento',sql.Int,offset],['Buscar',sql.NVarChar(150),v.text(buscar,150,true)]]))[0];
    },
    async detail(actor,id,receiptOffset=0) {
      if(!Number.isInteger(receiptOffset)||receiptOffset<0||receiptOffset>1000000)throw new TypeError('Pagina invalida.');
      const [header,lines,recepciones] = await call('dbo.P3_COM_Consultar',actor,[['OrdenCompraId',sql.Int,v.integer(id)],['RecepcionesDesplazamiento',sql.Int,receiptOffset]]);
      return {orden:header[0] || null,detalle:lines || [],recepciones:recepciones || []};
    },
    async history(actor,id,offset=0) {
      if(!Number.isInteger(offset)||offset<0||offset>1000000)throw new TypeError('Pagina invalida.');
      return (await call('dbo.P3_COM_ConsultarHistorial',actor,[['OrdenCompraId',sql.Int,v.integer(id)],['Desplazamiento',sql.Int,offset]]))[0];
    },
    send:change('dbo.P3_COM_EnviarAprobacion','PENDIENTE_APROBACION'),
    approve:change('dbo.P3_COM_Aprobar','APROBADA'),
    cancel:change('dbo.P3_COM_Cancelar','CANCELADA'),
    async receive(actor,data) {
      const d=v.receive(data);
      const sets=await call('dbo.P3_COM_Recibir',actor,[['OrdenCompraId',sql.Int,d.OrdenCompraId],['OperacionId',sql.UniqueIdentifier,d.OperacionId],['VersionEsperada',sql.Binary(8),d.Version],['DocumentoRespaldo',sql.NVarChar(sql.MAX),d.DocumentoRespaldo],['Motivo',sql.NVarChar(sql.MAX),d.Motivo],['Detalle',sql.NVarChar(sql.MAX),JSON.stringify(d.Detalle)]]);
      const final=sets.at(-1),state=final?.[0]?.Estado;
      if(!['PARCIALMENTE_RECIBIDA','RECIBIDA'].includes(state))throw Error('Confirmacion de recepcion incompatible.');
      return confirmed([final],d.OperacionId,state,d.OrdenCompraId);
    },
    async search(actor,clase,proveedor,buscar='',pagina=1) {
      if(!['proveedores','productos'].includes(clase))throw new TypeError('Catalogo invalido.');
      v.integer(pagina);if(pagina>100001)throw new TypeError('Pagina invalida.');
      const rows=(await call('dbo.P3_COM_BuscarCatalogo',actor,[['Clase',sql.VarChar(12),clase],['ProveedorId',sql.Int,proveedor===null?null:v.integer(proveedor)],['Buscar',sql.NVarChar(150),v.text(buscar,150,true)],['Pagina',sql.Int,pagina]]))[0];
      return {rows:rows.slice(0,10),next:rows.length>10,pagina};
    },
    async valuation(actor,id,offset=0) {
      if(!Number.isInteger(offset)||offset<0||offset>1000000)throw new TypeError('Pagina invalida.');
      const [header,history]=await call('dbo.P3_COM_ConsultarValoracion',actor,[['ProductoId',sql.Int,v.integer(id)],['Desplazamiento',sql.Int,offset]]);
      return {producto:header[0]||null,movimientos:history||[]};
    },
    async refreshValuation(actor,id) {
      return (await call('dbo.P3_COM_ActualizarValoracion',actor,[['ProductoId',sql.Int,v.integer(id)]]))[0][0];
    },
  };
}
module.exports = {createComprasService};
