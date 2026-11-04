# Estado de integración Parte IV — 4 de noviembre de 2026

**Actualización técnica:** las correcciones de seguridad de tareas Windows y capacidad se documentan en [REVISION_TECNICA_TAREAS.md](REVISION_TECNICA_TAREAS.md). Pasaron **302 pruebas locales**, cero fallos/omisiones, incluida la batería UC13/UC14 ampliada de 43 pruebas. No se aplicaron estas correcciones a SQL Server, cuentas, derechos ni tareas Windows durante esa revisión. La validación operativa de las versiones endurecidas y el acceso web con el admin habitual siguen pendientes.

El informe siguiente conserva el estado y las evidencias del despliegue inicial; sus referencias al bloqueo original de Task Scheduler no sustituyen la revisión técnica posterior ni certifican el estado operativo actual.

**UC13 está instalado y probado con SQL Server real en la original; UC14 continúa funcionando. El cierre completo sigue pendiente del login habitual de admin en navegador. La automatización Windows no está operativa y la política SQL permanece deshabilitada.** No se presenta este estado como una Parte IV totalmente finalizada.

## Resultados comprobados

| Área | Resultado y evidencia |
|---|---|
| Repositorio | Base `82387e692e19fb4393fb225ecdd0c95e96ebf608`; rama `integration/p4-backups-ldf-final`. Se conservó fuera del commit la modificación local preexistente del reporte LDF. |
| Exclusión | UC13 y UC14 comparten `SecureFinanceERP:BACKUP`, base actual, `public`, `Exclusive`, `Session`; rechazo mutuo comprobado con conexiones SQL distintas. `UC13_WORKER` independiente comprobado en SQL. |
| Medios compartidos | El catálogo UC13 reconoce LOG UC14. Solo rutas autorizadas en SQL; HEADERONLY, identidad, fork, FILELISTONLY y VERIFYONLY antes de restaurar. |
| Preparación | FULL COPY_ONLY CHECKSUM, VERIFYONLY, restauración distinta y CHECKDB antes de migrar. Se conservaron las copias de los ensayos iniciales fallidos, sin borrar respaldos. |
| Laboratorio | Instalación repetida, FULL/DIFF/LOG verificados, permisos, idempotencia, cola manual y turno automático LOG real, concurrencia, PITR y regresiones SQL aprobados. Ver [sql-laboratorio.json](evidencias/sql-laboratorio.json). |
| PITR | Base separada con `BEFORE_STOPAT` presente y `AFTER_STOPAT` ausente. La secuencia contiene LOG de UC14. CHECKDB de destino aprobado; ningún RESTORE sobre la original. |
| Interfaz | Chromium real + SQL, ocho rutas en 1440/768/390, login QA solo en copia, sesión, CSRF inválido rechazado, solicitud válida encolada y métricas LDF. Ver [browser-lab.json](evidencias/browser-lab.json). |
| Despliegue original | Otro FULL COPY_ONLY CHECKSUM verificado y restaurado independientemente; UC13 incremental transaccional; 67 tablas históricas conservadas mediante multiconjuntos SHA-256; módulos previos y firmas LDF intactos. Ver [despliegue-original.json](evidencias/despliegue-original.json). |
| UC13 original | FULL, DIFF y LOG procesados por el worker externo, COMPLETADO/VERIFICADO. Contratos con cuenta web real y autorización SQL del actor admin. Ver [contratos-original.json](evidencias/contratos-original.json). |
| UC14 original | Métricas y VLF reales; BACKUP LOG posterior al despliegue UC13, CONFIRMADO mediante su servicio firmado. |
| Regresión Node | `npm.cmd run check`, `npm.cmd test` y `npm.cmd run check:backups`: salida 0; **294 pruebas**, cero fallos/omisiones. Evidencia en [npm-test.txt](evidencias/npm-test.txt) y [npm-check.txt](evidencias/npm-check.txt). |

## Instalación y cuentas

Se ejecutaron `database/parte4/backups/01_backups.sql` y `02_permissions.sql` dentro de una transacción de despliegue, más configuración UC13 y tres permisos nuevos del rol ERP `Administrador`. Objetos nuevos: `BackupsJob`, `BackupsSchedule`, `BackupsConfig`, `BackupsExecution`, `BackupsCatalog`, `BackupsAudit`, `sp_BackupsRutas`, `sp_BackupsConsultar`, `sp_BackupsSolicitar`, `sp_EjecutarBackupEstrategico` e índice único de turnos.

Cuenta web: `securefinance_app`, con consulta y encolado UC13, sin acceso directo a tablas ni ejecución BACKUP UC13. Worker SQL: `securefinance_uc13_worker`, separado de web y LDF, sin sysadmin ni db_owner en ERP. Puede consultar las dos tablas msdb necesarias, respaldar y crear destinos nuevos para PITR. Se concedieron permisos por objeto, no roles administrativos amplios. LDF conserva su cuenta, certificados y firmas existentes.

Runtime independiente: `C:\ProgramData\SecureFinanceERP\UC13`, con copia protegida del worker y sus dependencias. Secretos en `backups.env` externo a Git/OneDrive, ACL limitadas a SYSTEM, Administradores y `KENNETH\sf_backup_runner`. Propietario SYSTEM. La identidad Windows dedicada es estándar. El token no elevado de la identidad web no puede leer ese secreto. No se publican secretos ni hashes de usuarios.

No se reinstalaron Partes I, II o III, ni LDF. No se modificaron contraseñas, hashes, salts, usuarios existentes, datos comerciales ni auditoría histórica. Se agregaron únicamente registros legítimos del módulo, sus respaldos y auditoría DDL de instalación. El trigger y la función de autorización Parte III permanecieron intactos.

## Automatización: deshabilitada con bloqueo real

La política semanal FULL / diaria DIFF / LOG cada 15 minutos está implementada; se probó el turno LOG real en laboratorio y los límites del calendario con tests. `BackupsSchedule.Enabled=0` en la original.

El registro de `SecureFinance-UC13` fue rechazado por Windows Task Scheduler con **E_ACCESSDENIED (0x80070005)** en `RegisterTaskDefinition`, incluso con elevación Windows comprobada. La tarea no quedó instalada; no existe LastTaskResult aprobado ni ejecución bajo `sf_backup_runner`. No se cambiaron ACL del servicio, políticas del sistema ni controles de seguridad para forzarlo. Ver [programador-windows.json](evidencias/programador-windows.json).

El worker externo sí ejecutó las solicitudes originales mediante una invocación puntual del operador elevado, usando exclusivamente su login SQL limitado. Esa prueba **no acredita ejecución programada con la cuenta Windows dedicada**. Hasta resolver el rechazo, las solicitudes nuevas requieren ejecutar manualmente `Run-ProductionWorker.ps1` con elevación; sin esa acción permanecen PENDIENTE.

Había 510.350.319.616 bytes libres en C: al preparar el despliegue; es una medición puntual, no un presupuesto de retención. No se aprobó horizonte PITR ni capacidad/retención sostenida. Ambos puntos también impiden activar la política automática. No hay borrado automático de medios.

## Pendientes reales y publicación

1. Comprobar en la original `/dba/backups` y `/dba/ldf` con el login habitual de `admin`. Se abrió una ventana de prueba y se pidió al propietario ingresar directamente su contraseña. Sigue en login; no se leyó ni cambió la clave. La autorización SQL de admin y el navegador real de laboratorio están aprobados, pero no sustituyen esta comprobación.
2. Resolver el rechazo de registro de tarea por los mecanismos autorizados de Windows; verificar S4U/Limited, identidad efectiva, ACL, ejecución y LastTaskResult. Mantener la política SQL deshabilitada hasta completar recuperación/cadena/retención/capacidad y responsable operativo.
3. Obtener resolución académica sobre **Node.js frente al requisito C#**. La discrepancia permanece abierta; no hay confirmación del ingeniero.
4. El PR debe permanecer sin fusionar mientras falte la comprobación de acceso original. No declarar finalización por haber publicado código.

## Documentos y evidencias

- [Arquitectura y contrato de exclusión/cadena](ARQUITECTURA.md).
- [Operación, recuperación y programación](OPERACION.md).
- [Guion de demostración e informe académico](DEMOSTRACION.md).
- [SQL de laboratorio](evidencias/sql-laboratorio.json), [exclusión independiente](evidencias/locks-independientes.json), [despliegue](evidencias/despliegue-original.json), [contratos originales](evidencias/contratos-original.json), [auditoría final](evidencias/auditoria-original-final.json).
- Capturas: [Respaldos escritorio](evidencias/backups-1440.png), [Respaldos móvil](evidencias/backups-390.png), [LDF escritorio](evidencias/ldf-1440.png), [LDF móvil](evidencias/ldf-390.png).

Los JSON publicados contienen resultados y metadatos de medios; las credenciales temporales, snapshots de hashes y SQL privado de aprovisionamiento permanecen fuera de las evidencias públicas. Las bases y archivos de ensayo se conservaron y deben contemplarse al gestionar capacidad; no se eliminaron automáticamente.
