'use strict';
const fs = require('node:fs'), path = require('node:path');
const { execFileSync } = require('node:child_process');
const { root } = require('./sqlcmd.cjs');
const files = ['src/public/js/dba-ldf.js'];
for (const dir of ['src/modules/dba/ldf', 'scripts/parte4/ldf', 'tests/parte4/ldf']) {
  for (const entry of fs.readdirSync(path.join(root, dir))) if (/\.(c?js)$/.test(entry)) files.push(path.join(dir, entry));
}
for (const file of files) execFileSync(process.execPath, ['--check', path.join(root, file)], { stdio: 'inherit' });
console.log('LDF: sintaxis comprobada en', files.length, 'archivos.');
