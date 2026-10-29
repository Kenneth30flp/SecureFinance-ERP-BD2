'use strict';
const states = Object.freeze(['BORRADOR','PENDIENTE_APROBACION','APROBADA','PARCIALMENTE_RECIBIDA','RECIBIDA','CANCELADA']);
function integer(value) {
  if (!Number.isInteger(value) || value < 1 || value > 2147483647) throw new TypeError('Identificador o cantidad invalida.');
  return value;
}
function uuid(value) {
  if (typeof value !== 'string' || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(value)) throw new TypeError('Referencia invalida.');
  return value.toLowerCase();
}
function text(value, max, optional = false) {
  if (optional && value == null) return null;
  if (typeof value !== 'string' || value.length > max || (!optional && !value.trim())) throw new TypeError('Texto invalido.');
  return value;
}
function create(d) {
  if (d && ['BodegaId','ModalidadPago'].some(key=>Object.hasOwn(d,key))) throw new TypeError('Compras opera con inventario global; no admite bodega ni modalidad de pago.');
  if (!d || !Array.isArray(d.Detalle) || d.Detalle.length < 1 || d.Detalle.length > 100) throw new TypeError('Detalle invalido.');
  const seen = new Set();
  const Detalle = Array.from(d.Detalle,line => {
    if (!line || Object.keys(line).sort().join(',') !== 'Cantidad,CostoUnitario,ProductoId') throw new TypeError('Columnas de detalle invalidas.');
    const ProductoId = integer(line.ProductoId), Cantidad = integer(line.Cantidad);
    if (seen.has(ProductoId)) throw new TypeError('Producto repetido.');
    seen.add(ProductoId);
    if (typeof line.CostoUnitario !== 'string' || !/^(0|[1-9]\d{0,14})(?:\.\d{1,4})?$/.test(line.CostoUnitario)) throw new TypeError('Costo decimal invalido.');
    const [whole, fraction = ''] = line.CostoUnitario.split('.');
    return {ProductoId,Cantidad,CostoUnitario:whole + '.' + fraction.padEnd(4,'0')};
  }).sort((a,b) => a.ProductoId-b.ProductoId);
  return {ProveedorId:integer(d.ProveedorId),OperacionId:uuid(d.OperacionId),Observaciones:text(d.Observaciones,1000,true),Detalle};
}
function transition(d) {
  if (!d || typeof d.Version !== 'string' || !/^[0-9a-f]{16}$/i.test(d.Version)) throw new TypeError('Version invalida.');
  return {OrdenCompraId:integer(d.OrdenCompraId),OperacionId:uuid(d.OperacionId),Version:Buffer.from(d.Version,'hex'),Motivo:text(d.Motivo,250)};
}
function id(value) { if(typeof value==='string' && /^[1-9]\d{0,9}$/.test(value)) return integer(Number(value)); return integer(value); }
function filters(query={}) {
  const pagina=query.pagina===undefined?1:id(query.pagina);
  if(pagina>20001) throw new TypeError('Pagina invalida.');
  const estado=query.estado || null;
  if(estado!==null && !states.includes(estado))throw new TypeError('Estado invalido.');
  return {pagina,offset:(pagina-1)*50,estado,buscar:text(query.buscar??'',150,true)};
}
function receive(d) {
  const lines=create({...d,ProveedorId:1});
  return {...transition(d),DocumentoRespaldo:text(d.DocumentoRespaldo,100),Detalle:lines.Detalle};
}
module.exports = {states,integer,id,uuid,text,create,transition,filters,receive};
