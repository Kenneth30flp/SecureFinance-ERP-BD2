'use strict';
// No connection, CLI or credential loading. Integrator supplies an existing lab transaction.
const fs = require('node:fs');
const path = require('node:path');
const names = ['70_P3_CRE_Estructura.sql', '71_P3_CRE_Perfiles.sql', '72_P3_CRE_Financiacion.sql',
  '73_P3_CRE_Abonos.sql', '74_P3_CRE_Consultas.sql', '75_P3_CRE_Seguridad.sql',
  '76_P3_CRE_Ventas_PROPUESTA.sql', '77_P3_CRE_ConversionPublica.sql',
  '78_P3_CRE_AjustesConsultas.sql', '78_P3_CRE_Verificacion.sql'];
function migrationPlan() {
  return names.flatMap(file => fs.readFileSync(path.join(__dirname, '../database', file), 'utf8')
    .split(/^GO\s*$/im).filter(batch => batch.trim()).map((sql, i) => ({ file, batch: i + 1, sql })));
}
async function applyReviewedPlan(transaction, { kennethReviewApproved = false } = {}) {
  if (kennethReviewApproved !== true) throw new Error('76 PROPOSED: Kenneth review required.');
  if (!transaction || typeof transaction.request !== 'function') throw new Error('External transaction required.');
  try {
    for (const batch of migrationPlan()) {
      // Verify EVERY GO boundary, including after any failure or unexpected transaction loss.
      const result = await transaction.request().query('SELECT DB_NAME() AS DatabaseName, @@TRANCOUNT AS TranCount, XACT_STATE() AS XactState;');
      const state = result.recordset?.[0];
      if (state?.DatabaseName !== 'SecureFinanceERP_Lab_Dylan' || state.TranCount !== 1 || state.XactState !== 1) {
        throw new Error('Exact Dylan laboratory and one committable external transaction required.');
      }
      await transaction.request().batch(batch.sql);
    }
    // Caller inspects verification and commits explicitly; never silently commits here.
  } catch (error) {
    await transaction.rollback().catch(() => {});
    throw error;
  }
}
module.exports = { migrationPlan, applyReviewedPlan };
