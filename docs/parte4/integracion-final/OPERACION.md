# Operación y recuperación

## Operación habitual

1. Iniciar sesión con la contraseña habitual de `admin`. Si los permisos se concedieron durante una sesión abierta, cerrar sesión y entrar de nuevo para refrescarlos.
2. Abrir Administración → Respaldos. Comprobar heartbeat, estado de política y catálogo.
3. Solicitar FULL, DIFF o LOG. PENDIENTE confirma la cola; solo COMPLETADO con ejecución VERIFICADO confirma el respaldo.
4. Ante INCIERTO, revisar msdb, archivo e historial. No repetir ciegamente ni reutilizar un plan de restauración ejecutado.
5. Abrir Administración → LDF. Las métricas, VLF, historial LOG y respaldo firmado siguen operando con el servicio UC14 separado.

FULL normal cambia la base diferencial; COPY_ONLY de protección no la cambia. No mover, sobrescribir ni borrar medios históricos. CHECKSUM y VERIFYONLY no sustituyen una restauración ensayada.

## Recuperación

Solicitar PLAN con fecha/hora SQL local y destino `SF_Recovery_nombre`. Revisar los comandos y medios. El plan expira a los 30 minutos y solo su autor puede ejecutarlo una vez. Todos los medios deben seguir existiendo en las carpetas SQL autorizadas. El worker exige un LOG iniciado después del instante elegido como cobertura conservadora.

La ejecución crea archivos nuevos con UUID, mantiene NORECOVERY hasta alcanzar STOPAT y se detiene al primer estado ONLINE confirmado. Un fallo conserva la base parcial para inspección; elegir otro nombre tras revisar la causa. Nunca dirigir la aplicación a una recuperación ni reemplazar la original como parte de este flujo.

## Programación

La estrategia implementada es FULL domingo 00:00 UTC, DIFF diario 00:00 UTC y LOG cada 15 minutos, incluida medianoche. Coincidencias se procesan FULL, DIFF, LOG. Medianoche UTC corresponde a las 18:00 del día anterior en Guatemala. El worker consulta cada minuto y conserva turnos vencidos como OMITIDO, sin inventar ejecución retrospectiva.

La tarea Windows y `BackupsSchedule.Enabled` son controles distintos. Una tarea habilitada puede atender solicitudes manuales con política SQL automática deshabilitada. No inferir automatización completa de un heartbeat reciente.

Antes de habilitar `BackupsSchedule.Enabled`, verificar espacio con crecimiento previsto, identidad Windows efectiva, ACL, salida de la tarea, cadena y recuperación comprobadas, horizonte PITR/retención y responsable operativo. No existe borrado automático de respaldos. No activar una política indefinida sin presupuesto de almacenamiento y retención aprobados.

```powershell
Get-ScheduledTask -TaskName SecureFinance-UC13
Get-ScheduledTaskInfo -TaskName SecureFinance-UC13
```

Consultar como DBA la configuración y la cola; la cuenta web no tiene SELECT directo. Los secretos de producción deben permanecer fuera del repositorio y OneDrive. No copiarlos al `.env` web ni incluirlos en evidencias.

## Herramientas de ensayo y despliegue

`scripts/parte4/backups/integration.cjs` está fijado a esta instalación y no se ejecuta al arrancar HTTP. `prepare` crea un FULL COPY_ONLY verificado y una copia nueva. `lab` instala dos veces y ejecuta la batería real. `browser` usa Chromium/SQL en esa copia. `--new-trial` archiva el estado anterior, conserva bases y respaldos y prepara una copia adicional. No ejecutar en bucle: las copias consumen espacio y no se eliminan automáticamente.

`Prepare-Production.ps1` requiere elevación Windows para crear una cuenta estándar nueva, proteger un runtime independiente y ejecutar el despliegue incremental con otro FULL verificado. Rechaza sobrescribir identidades, secretos, tarea o estado de despliegue existentes. No repetirlo sobre una instalación realizada; inspeccionar sus evidencias. No reinstala Partes I–III ni LDF.

Ante fallo transaccional del instalador SQL, la conexión revierte los cambios pendientes. Tras una instalación confirmada, detener/deshabilitar el worker si procede, conservar auditoría y aplicar una corrección incremental revisada. No restaurar la original ni eliminar objetos/historial como rollback automático.
