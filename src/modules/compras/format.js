'use strict';
function money(value) {
  if(value===null || value===undefined)return 'Sin valorar';
  const m=/^(\d+)(?:\.(\d{1,8}))?$/.exec(String(value));
  if(!m)return 'No disponible';
  return 'Q '+BigInt(m[1]).toLocaleString('es-GT')+'.'+(m[2]||'').padEnd(4,'0');
}
const labels={BORRADOR:'Borrador',PENDIENTE_APROBACION:'Pendiente de aprobación',APROBADA:'Aprobada',PARCIALMENTE_RECIBIDA:'Recepción parcial',RECIBIDA:'Recibida',CANCELADA:'Cancelada'};
module.exports={money,labels};
