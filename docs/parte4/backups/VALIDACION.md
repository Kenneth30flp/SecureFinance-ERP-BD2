# Validación UC13

Entorno de desarrollo: Windows, Node v24.16.0; repositorio `SecureFinance-ERP-COMPLETO`, rama `feature/p4-edward-backups`.

## Verificaciones ejecutadas

- `npm.cmd ci --ignore-scripts`: dependencias instaladas desde lockfile, sin modificarlo. npm informó 4 vulnerabilidades de dependencias (1 moderada, 3 altas); no se aplicaron actualizaciones ajenas a UC13.
- Primera pasada de `npm.cmd run check`: código de salida 0.
- Primera pasada de `npm.cmd test`: 268 aprobadas, 0 fallidas, 0 omitidas; 9 pruebas UC13 en esa pasada.
- Auditoría final: `npm.cmd run check` y `npm.cmd test` terminaron con código 0; **280 pruebas aprobadas, 0 fallidas, 0 omitidas**, incluidas **21 pruebas UC13**. Salida real en `check-final.txt` y `test-final.txt`.
- `npm.cmd run check:backups`: sintaxis JavaScript, parser PowerShell y contratos estáticos SQL correctos. No compila ni ejecuta T-SQL. `git diff --check` sin errores.
- Las plantillas se renderizan con EJS en pruebas; no se ha realizado validación visual en navegador real.

Las pruebas UC13 cubren tipos/rutas/fechas, precisión LSN, FULL/DIFF/LOG, brechas, ramas y familia, checksum y BULK_LOGGED, programación semanal/diaria/15 minutos, exclusión concurrente, cuentas SQL, identidad física del medio, metadatos LOG, parámetros tipados, sesión/RBAC/CSRF y renderizado sin datos ficticios. Los medios/servicios usados en esas pruebas son dobles explícitos, no backups reales.

## Pendiente: laboratorio SQL aislado

No se abrió conexión a ninguna base SQL, no se aplicaron scripts SQL, no se creó/modificó laboratorio ni se instalaron tareas Windows. Se requiere un laboratorio aislado autorizado y cuentas preparadas para ejecutar esta matriz:

| Caso | Procedimiento y resultado esperado |
|---|---|
| Instalación | Aplicar 01/02 sobre copia ERP aislada; compilar procedimientos; repetir instalación sin pérdida de historial |
| Privilegios web | Cuenta no sysadmin: consulta/cola permitidas; DML de tablas UC13, BACKUP y RESTORE directo denegados |
| Revocación | Revocar permiso ERP después de encolar; worker debe rechazar ejecución |
| FULL | Base FULL, solicitud manual: archivo UUID, checksum, VERIFYONLY y registro COMPLETADO/VERIFICADO |
| DIFF | Cambiar un dato solo en laboratorio; DIFF referencia FULL vigente; medio verificable |
| LOG | Generar transacciones y LOG; verificar continuidad LSN y msdb; rechazar SIMPLE y cadena no inicializada |
| Compresión Express | Config 0 funciona; config 1 falla sin declarar respaldo exitoso |
| Carpetas | Ruta fuera de allowlist o ACL insuficiente falla, sin secretos en UI |
| PITR real | FULL; transacción A con hora documentada; DIFF; transacción B; LOG posteriores al punto. Recuperar entre A y B: destino nuevo contiene A, no B |
| Fuente intacta | Comparar estado/conteos/hash de origen antes/después del PITR; archivos físicos originales sin alteración |
| Destino existente | Intentar nombre ya creado; rechazo sin cambios. Nombre origen, master y caracteres SQL rechazados |
| Medios defectuosos | Retirar/corromper una copia de medio en laboratorio; VERIFYONLY/HEADERONLY impide ejecutar plan |
| Cadena inválida | Omitir LOG, DIFF de otra base, otra familia/rama: rechazar sin recuperación aproximada |
| Topología | Agregar archivo después de FULL: rechazar plan; ningún archivo vuelve a su ruta original |
| Idempotencia | Repetir UUID idéntico: una solicitud. Reutilizar UUID con otro contenido: rechazar. Mismo plan: una RESTORE |
| Concurrencia | Lanzar dos runners: uno obtiene bloqueo; no duplicar operaciones ni turnos |
| Reinicio | Interrumpir runner durante operación: siguiente proceso marca INCIERTO; no reintenta ciegamente |
| Horarios | Validar domingo FULL+DIFF+LOG, resto de días DIFF+LOG, turnos de 15 minutos y clave única |
| Omisiones | Detener tarea más de 15 minutos; registrar OMITIDO, actualizar cursor; verificar intervalo >31 días |
| Fallo Windows | Credenciales/ACL inválidas: LastTaskResult no cero y heartbeat ausente; no estado ficticio de éxito |
| Recuperación parcial | Fallo de un RESTORE intermedio conserva destino parcial; nunca DROP ni REPLACE |

No usar bases existentes de trabajo para estos casos. Las transacciones de ejemplo son exclusivamente fixtures del laboratorio autorizado, nunca datos presentados como operaciones empresariales reales. VERIFYONLY no sustituye el ensayo de recuperación y comprobación de datos.

Estado de entrega: implementación en código disponible; validación operativa SQL/Windows y aceptación del cambio tecnológico C# → Node.js pendientes. No se certifica recuperación real hasta completar esta matriz.
