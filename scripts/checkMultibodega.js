'use strict';
// Offline syntax checks only. Does not load .env, database providers or start an application.
const { spawnSync } = require('node:child_process');
const path = require('node:path');
for (const name of ['src/modules/multibodega/validation.js', 'src/modules/multibodega/service.js', 'src/modules/multibodega/routes.js', 'src/public/js/multibodega.js', 'tests/multibodega.test.js']) {
  const result = spawnSync(process.execPath, ['--check', path.join(__dirname, '..', name)], { stdio: 'inherit' });
  if (result.status !== 0) process.exit(result.status || 1);
}
console.log('Mod5: 5 archivos JavaScript con sintaxis valida; no se ejecuto SQL.');
