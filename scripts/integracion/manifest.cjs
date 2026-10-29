'use strict';
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../..');
const pick=n=>{const f=fs.readdirSync(path.join(root,'database')).filter(f=>f.startsWith(n+'_')&&!/Verificacion|Pruebas/.test(f));if(f.length!==1)throw Error('Ambiguous migration '+n);return f[0];};
const files=[...Array.from({length:9},(_,i)=>70+i),...Array.from({length:10},(_,i)=>80+i),90,91,92,93,94,95].map(pick);files.unshift('integration/00_AutorizacionLaboratorio.sql');
const manifest={base:'02d85b519cc00a57599308bbbe24844b061bf0a7',prerequisites:'SecureFinanceERP_Full.sql body; 15-26,30-44;60-63 (unchanged)',atomicGroup:files,verificationOnly:['78_P3_CRE_Verificacion.sql','79_P3_CRE_PruebasSinteticas.sql','89_P3_BOD_Verificacion.sql'],policy:'new synthetic laboratory only; 76 integrated proposal; 95 fails closed outside explicitly bound database; production deployment pending',files:files.map(file=>({file,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'database',file),'utf8').replace(/^\uFEFF/,'').replace(/\r\n/g,'\n')).digest('hex')}))};
if(require.main===module)fs.writeFileSync(path.join(root,'database/integracion-manifest.json'),JSON.stringify(manifest,null,2)+'\n');
module.exports=manifest;
