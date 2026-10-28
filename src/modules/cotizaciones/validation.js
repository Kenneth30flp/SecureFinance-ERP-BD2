'use strict';
const { localDayBoundary } = require('../../public/js/operationalDates');
class ValidationError extends Error {}
function integer(value) {
  if (!['string','number'].includes(typeof value)||!/^[1-9]\d{0,9}$/.test(String(value)) || Number(value)>2147483647) throw new ValidationError('Usa identificadores y cantidades enteras positivas.');
  return Number(value);
}
function uuid(value) {
  if (typeof value!=='string'||!/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i.test(value)) throw new ValidationError('Referencia de operación inválida.');
  return value;
}
function text(value, max) {
  if (typeof value!=='string'||value.length>max) throw new ValidationError('Texto inválido o demasiado extenso.');
  return value;
}
function day(value, end=false) {
  if (typeof value!=='string') throw new ValidationError('Fecha inválida.');
  try { return localDayBoundary(value,end); } catch { throw new ValidationError('Fecha inválida.'); }
}
function creation(b={}) {
  const ClienteId=integer(b.ClienteId),OperacionId=uuid(b.OperacionId);
  if (!b.Vencimiento) throw new ValidationError('Indica la fecha de vencimiento.');
  // Fecha de vigencia inclusiva: final del día operativo Guatemala, límite exclusivo UTC.
  const VenceEn=day(b.Vencimiento,true);
  if (!Array.isArray(b.Detalle)||b.Detalle.length<1||b.Detalle.length>100) throw new ValidationError('Agrega entre 1 y 100 productos.');
  const ids=new Set();
  const Detalle=b.Detalle.map(l=>{
    const ProductoId=integer(l?.ProductoId),Cantidad=integer(l?.Cantidad);
    const d=l.DescuentoPorcentaje??'0';
    if (!['string','number'].includes(typeof d)||!/^\d{1,3}(\.\d{1,2})?$/.test(String(d))||Number(d)>100||ids.has(ProductoId)) throw new ValidationError('Revisa productos repetidos y descuentos entre 0 y 100.');
    ids.add(ProductoId);
    return {ProductoId,Cantidad,DescuentoPorcentaje:Number(d)};
  });
  return {ClienteId,OperacionId,VenceEn,Detalle,Observaciones:text(b.Observaciones??'',1000)};
}
function filters(q={}) {
  const numero=text(q.numero??'',14),cliente=text(q.cliente??'',150),estado=text(q.estado??'',15);
  if (numero&&!/^COT-[1-9]\d{0,9}$/.test(numero)) throw new ValidationError('Usa un número como COT-1.');
  if (estado&&!['ACTIVA','VENCIDA','PROCESADA','CANCELADA'].includes(estado)) throw new ValidationError('Estado inválido.');
  const desde=q.desde?day(q.desde):null,hasta=q.hasta?day(q.hasta,true):null,pagina=q.pagina===undefined?1:integer(q.pagina);
  if(pagina>100001||(desde&&hasta&&desde>=hasta)) throw new ValidationError('Rango o página inválidos.');
  return {numero,cliente,estado,desde:q.desde||'',hasta:q.hasta||'',Desde:desde,Hasta:hasta,pagina};
}
module.exports={ValidationError,integer,uuid,text,creation,filters};
