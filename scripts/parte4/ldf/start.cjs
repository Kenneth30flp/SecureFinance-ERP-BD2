'use strict';
require('./lab.cjs').useLab();
require('../../../server').start().catch(e => { console.error(e.code || 'No se pudo iniciar el laboratorio LDF.'); process.exitCode = 1; });
