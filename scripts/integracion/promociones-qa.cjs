'use strict';
const fs=require('fs');const lab=require('../../database/tests/promocionesLab');
// Reapply shared definitions atomically; 63 must never be committed without integrated 76.
lab.install=async()=>{const files=fs.readdirSync('database');let text='BEGIN TRANSACTION;\nGO\n';for(const n of [60,61,62,63,76]){const f=files.find(f=>f.startsWith(n+'_'));text+=fs.readFileSync('database/'+f,'utf8').replace(/\uFEFF/g,'')+'\nGO\n';}await lab.labQuery(text+'COMMIT;');};
require('../../database/tests/PromocionesIntegration');
