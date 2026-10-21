'use strict';
class ValidationError extends Error { constructor(message) { super(message); this.status=400; } }
const fail=message=>{throw new ValidationError(message);};
function integer(value,minimum=1){if(!/^\d+$/.test(String(value))) fail('Número inválido.');const n=Number(value);if(!Number.isSafeInteger(n)||n<minimum||n>2147483647)fail('Número fuera de rango.');return n;}
function text(value,max,required=true){if(typeof value!=='string'||value.length>max||(required&&!value.trim()))fail('Revisa los campos de texto.');return value.trim();}
function uuid(value){if(typeof value!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value))fail('Referencia inválida.');return value;}
function version(value){if(typeof value!=='string'||!/^[0-9a-f]{16}$/i.test(value))fail('Recarga el ticket antes de guardar.');return Buffer.from(value,'hex');}
const states=['RECIBIDO','EN_REVISION','APROBADO','RECHAZADO','ENTREGADO'];
function state(value){if(!states.includes(value))fail('Estado inválido.');return value;}
function date(value){if(!value)return null;if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value)||!Number.isFinite(Date.parse(value))||new Date(value).toISOString().slice(0,10)!==value)fail('Fecha inválida.');return new Date(value);}
function filters(q){const desde=date(q.desde),hasta=date(q.hasta);if(hasta)hasta.setUTCDate(hasta.getUTCDate()+1);if(desde&&hasta&&desde>=hasta)fail('Período inválido.');return {id:q.id?integer(q.id):null,offset:integer(q.offset||0,0),buscar:text(q.buscar||'',150,false),estado:q.estado?state(q.estado):null,desde,hasta};}
function devolucion(b){
 const detalles=Array.isArray(b.Detalles)?b.Detalles:fail('Selecciona productos.');
 if(!detalles.length||detalles.length>100)fail('Selecciona entre 1 y 100 productos.');
 const rows=detalles.map(d=>({DetalleFacturaId:integer(d.DetalleFacturaId),Cantidad:integer(d.Cantidad),Reingresar:typeof d.Reingresar==='boolean'?d.Reingresar:fail('Selecciona la condición del producto.')}));
 if(new Set(rows.map(d=>d.DetalleFacturaId)).size!==rows.length)fail('Producto repetido.');
 return {FacturaId:integer(b.FacturaId),OperacionId:uuid(b.OperacionId),Motivo:text(b.Motivo,250),Detalles:rows};
}
module.exports={ValidationError,integer,text,uuid,version,state,states,filters,devolucion};
