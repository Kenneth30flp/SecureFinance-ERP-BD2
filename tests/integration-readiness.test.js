'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { verifyIntegration } = require('../src/config/integration');
const pool = allowed => ({ request: () => ({ query: async () => ({ recordsets: [
  [{ databaseName: 'isolated', loginName: 'app' }], [{ name: 'sp_ERP_ConsultarKardex', allowed }],
] }) }) });
test('startup rejects missing procedures and denied effective EXECUTE before serving HTTP', async () => {
  for (const value of [null, 0]) await assert.rejects(verifyIntegration(pool(value)), /migraciones 33-38 y EXECUTE.*sp_ERP_ConsultarKardex/);
});
test('startup returns actual SQL identity after checking effective permissions', async () => {
  assert.deepEqual(await verifyIntegration(pool(1)), { databaseName: 'isolated', loginName: 'app' });
});
