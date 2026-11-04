'use strict';
const causes = {
  NOTHING: ['Sin bloqueo de reutilización', 'SQL Server no informa una espera de truncado. El archivo físico puede conservar su tamaño.'],
  LOG_BACKUP: ['Respaldo LOG pendiente', 'Con cadena inicializada, ejecuta un respaldo LOG y vuelve a consultar. Coordina la frecuencia automática con el módulo Backups.'],
  ACTIVE_TRANSACTION: ['Transacción activa', 'El DBA debe identificar la transacción más antigua y permitir que termine o revisar su bloqueo. Un respaldo no libera el tramo que esa transacción necesita.'],
  ACTIVE_BACKUP_OR_RESTORE: ['Respaldo o restauración en curso', 'Espera a que termine la operación del motor y actualiza el panel. No inicies un respaldo incompatible.'],
  REPLICATION: ['Replicación pendiente', 'Revisar el lector del LOG, la distribución de replicación y, si corresponde, CDC. Un respaldo por sí solo no elimina esta espera.'],
  AVAILABILITY_REPLICA: ['Réplica de disponibilidad retrasada', 'Revisar sincronización, conectividad y colas de las réplicas antes de esperar reutilización.'],
  DATABASE_MIRRORING: ['Espejo pendiente', 'Revisar la conexión y sincronización del espejo de base de datos.'],
  CHECKPOINT: ['Checkpoint pendiente', 'El motor necesita completar un checkpoint. Actualiza tras la actividad normal; este panel no fuerza checkpoints.'],
  OLDEST_PAGE: ['Páginas antiguas pendientes', 'Revisar el progreso del checkpoint y latencia de escritura del almacenamiento.'],
  XTP_CHECKPOINT: ['Checkpoint de memoria optimizada', 'Revisar el progreso de checkpoint de tablas optimizadas para memoria.'],
  LOG_SCAN: ['Lectura del LOG en curso', 'Dejar terminar la lectura del registro y volver a consultar.'],
  OTHER_TRANSIENT: ['Espera transitoria del motor', 'Actualizar más tarde. Si persiste, el DBA debe revisar el registro de SQL Server.'],
  SLOG_SCAN: ['Escaneo de recuperación acelerada', 'Revisar el avance de recuperación acelerada (ADR) y volver a consultar.'],
};
function diagnose(summary, files, vlf) {
  const percent = Number(summary.UsedPercent), warning = Number(summary.WarningPercent), critical = Number(summary.CriticalPercent);
  const severity = percent >= critical ? 'critical' : percent >= warning ? 'warning' : 'healthy';
  const reuse = causes[summary.ReuseWait] || ['Espera reportada por SQL Server', 'Consultar la documentación de esta causa para la versión instalada. No se supone que un respaldo resuelva cualquier espera.'];
  const alerts = [];
  if (!summary.ChainReady) alerts.push({ title: 'Respaldo manual no habilitado', text: summary.RecoveryModel === 'SIMPLE'
    ? 'El modelo SIMPLE no admite BACKUP LOG. Un DBA debe planificar la política de recuperación; el panel no la cambia.'
    : 'Revisar estado ONLINE, escritura y respaldo FULL/diferencial que inicializa la cadena. No se cambia el modelo ni se crea un FULL desde este panel.' });
  if (summary.RecoveryModel === 'BULK_LOGGED') alerts.push({ title: 'Recuperación BULK_LOGGED', text: 'Admite BACKUP LOG; algunas operaciones masivas limitan la recuperación a un punto dentro del respaldo.' });
  if (severity !== 'healthy') alerts.push({ title: severity === 'critical' ? 'Uso crítico del LOG' : 'Uso en advertencia', text: `Uso ${percent.toFixed(2)} %. Revisar ${summary.ReuseWait}, capacidad del disco y crecimiento configurado. Un respaldo no garantiza reducción del tamaño físico.` });
  if (files.some(f => f.PercentGrowth)) alerts.push({ title: 'Crecimiento porcentual', text: 'El incremento cambia con el tamaño del archivo. Evaluar crecimiento fijo en MB según carga y almacenamiento; no se modifica automáticamente.' });
  if (files.some(f => Number(f.Growth) === 0)) alerts.push({ title: 'Crecimiento automático deshabilitado', text: 'Confirmar capacidad preasignada suficiente para la carga y las operaciones de recuperación.' });
  if (files.some(f => Number(f.MaxSizePages) > 0 && Number(f.SizeMB) >= Number(f.MaxSizePages) / 128)) alerts.push({ title: 'Límite físico alcanzado', text: 'Al menos un archivo alcanzó MAXSIZE. Revisar capacidad del volumen y la causa de retención con el DBA.' });
  if (Number(vlf.Total) > 0 && Number(vlf.MinMB) < 1) alerts.push({ title: 'VLF pequeños presentes', text: 'Hay segmentos menores de 1 MB. Evaluar tamaño, frecuencia de crecimiento y tiempos de recuperación; su cantidad por sí sola no prueba un problema.' });
  return { severity, label: { healthy: 'Saludable', warning: 'Advertencia', critical: 'Crítico' }[severity], reuseTitle: reuse[0], recommendation: reuse[1], alerts };
}
module.exports = { diagnose };
