'use strict';
const { sql } = require('../../../config/database');
const pools = require('./pools');
const { diagnose } = require('./diagnostics');
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
function operation(body) {
  if (!body || Object.keys(body).some(k => !['OperacionId', 'csrf'].includes(k))
    || typeof body.OperacionId !== 'string' || !uuid.test(body.OperacionId)) {
    throw Object.assign(new Error('Referencia de operación inválida. Actualiza el panel.'), { status: 400 });
  }
  return body.OperacionId.toLowerCase();
}
function snapshot(result) {
  const sets = result.recordsets;
  if (!Array.isArray(sets) || sets.length !== 7 || sets[0].length !== 1 || sets[2].length !== 1 || !sets[1].length) throw Error('Contrato LDF incompleto.');
  const [summary] = sets[0], [vlf] = sets[2];
  const validNumber = value => value !== null && value !== undefined && Number.isFinite(Number(value)) && Number(value) >= 0;
  for (const key of ['LogicalMB','UsedMB','FreeMB','UsedPercent','PhysicalMB','WarningPercent','CriticalPercent']) {
    if (!validNumber(summary[key])) throw Error('Métrica LDF ausente o inválida.');
  }
  if (!summary.DatabaseName || !summary.ReuseWait || !summary.RecoveryModel || !summary.SampledAtUTC
    || ![true, false].includes(summary.ChainReady) || Number(summary.UsedPercent) > 100
    || !(Number(summary.WarningPercent) > 0 && Number(summary.WarningPercent) < Number(summary.CriticalPercent) && Number(summary.CriticalPercent) <= 100)
    || ![vlf.Total, vlf.Active, vlf.Inactive].every(validNumber) || Number(vlf.Total) !== Number(vlf.Active) + Number(vlf.Inactive)) throw Error('Contrato LDF incoherente.');
  return { summary, files: sets[1], vlf, segments: sets[3], distribution: sets[4], backups: sets[5], history: sets[6],
    diagnostic: diagnose(summary, sets[1], vlf) };
}
function createLdfService({ application = pools.application, administrative = pools.administrative } = {}) {
  return {
    async read(actor) {
      const result = await (await application()).request().input('ActorUsuarioId', sql.Int, actor).execute('dbo.P4_LDF_Consultar');
      return snapshot(result);
    },
    async backup(actor, id) {
      const result = await (await administrative()).request().input('ActorUsuarioId', sql.Int, actor)
        .input('OperacionId', sql.UniqueIdentifier, id).execute('dbo.P4_LDF_RespaldarLog');
      const row = result.recordset?.[0];
      if (!row || row.OperacionId?.toLowerCase() !== id.toLowerCase() || row.ActorUsuarioId !== actor
        || !['EN_CURSO','CONFIRMADO','FALLIDO','INCIERTO'].includes(row.Estado)
        || (row.Estado === 'CONFIRMADO' && (!row.BackupSetId || !row.Archivo || !row.FinUTC))) throw Error('Confirmación LDF incompatible.');
      return row;
    },
  };
}
module.exports = { createLdfService, operation, snapshot };
