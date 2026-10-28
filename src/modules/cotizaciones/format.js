'use strict';
function money(value){
 const match=/^(\d+)(?:\.(\d{1,2}))?$/.exec(String(value??'0'));
 if(!match)return 'No disponible';
 return 'Q '+BigInt(match[1]).toLocaleString('es-GT')+'.'+(match[2]||'').padEnd(2,'0');
}
module.exports={money};
