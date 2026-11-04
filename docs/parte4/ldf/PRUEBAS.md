# Matriz y resultados de pruebas · UC14 LDF

Fecha de ejecución: **3 de noviembre de 2026, hora local de Guatemala** (las marcas internas UTC corresponden al 4 de noviembre). Todas las pruebas se ejecutaron en la rama `feature/p4-dylan-ldf`, worktree `SecureFinance-ERP-BD2-ldf`.

## Entorno real utilizado

| Componente | Valor comprobado |
|---|---|
| Node.js | v25.8.1 |
| SQL Server | 17.0.1145.4, Enterprise Developer Edition (64-bit) |
| Instancia / servidor lógico | `localhost` / `DESKTOP-HBNSH7J` |
| Navegador | Chrome 156.0.8078.80, modo headless con perfil temporal aislado |
| Base principal de pruebas | `SecureFinanceERP_P4_LDF_20261104033413_019717ca` (creada para el laboratorio) |
| Base SIMPLE de pruebas | `SecureFinanceERP_P4_LDF_20261104034459_12237c24` (creada para el laboratorio) |
| Base restaurada | `SecureFinanceERP_P4_LDF_Restore_20261104035849_9742214d` (creada por la prueba) |

No se ejecutaron escrituras, respaldos, restauraciones ni cambios de modelo sobre `SecureFinanceERP`, `SecureFinanceERP_Completo` ni otras bases del usuario. Las bases de laboratorio cumplen el patrón `SecureFinanceERP_P4_LDF_*` y llevan una propiedad extendida `P4.Laboratorio` con su propio nombre. La restauración usa `*_Restore_*` y no lleva `REPLACE`.

## Resumen

| Nivel | Comando | Resultado |
|---|---|---|
| Sintaxis | `npm.cmd run check` | **PASS** (15 archivos LDF + chequeo histórico del ERP) |
| Unitarias/HTTP LDF | `npm.cmd run test:ldf` | **PASS 10/10** |
| Suite completa del ERP | `npm.cmd test` | **PASS 269/269** |
| SQL real en laboratorio | `npm.cmd run test:sql:ldf` | **PASS 15/15** |
| Chromium + SQL real | `npm.cmd run test:ui:ldf` | **PASS** |
| Restauración FULL+LOG | `npm.cmd run test:restore:ldf` | **PASS** |

## 1. Unitarias y HTTP (`test:ldf`)

| Caso | Qué demuestra | Resultado |
|---|---|---|
| Sesión, RBAC en HTML/JSON/POST | Sin sesión redirige; sin `DBA_LDF_CONSULTAR` devuelve 403; no se consulta SQL ni se filtran rutas | PASS |
| Usuario solo lectura | Ve métricas y VLF; no recibe formulario de respaldo; POST devuelve 403; `Cache-Control: no-store` | PASS |
| Escape EJS y contrato visual | Metadatos hostiles se escapan; LSN grande se conserva como texto; secciones requeridas presentes | PASS |
| CSRF e input estricto | Token ausente/incorrecto rechazado; UUID obligatorio; propiedades extra (`Database`, `Path`, `ActorUsuarioId`) rechazadas antes de SQL | PASS |
| Errores honestos | Un fallo de lectura no pinta métricas ficticias ni rutas privadas; `INCIERTO` no se presenta como éxito | PASS |
| Umbrales y diagnóstico | Límites exactos 70/85; causas conocidas y desconocidas tienen texto específico; 2 000 VLF por sí solos no generan alarma crítica | PASS |
| Contrato de métricas | Valores ausentes, negativos o recordsets truncados no se convierten en cero | PASS |
| Servicio SQL | Consulta y respaldo usan conexiones separadas, RPC tipado y validan la confirmación devuelta | PASS |
| Destino no elegible desde el navegador | `LDF_DATABASE` debe coincidir con `DB_NAME`; identidad SQL distinta aborta; instalador rechaza base de sistema, ruta con `..`, UNC y umbrales incoherentes | PASS |
| Cookie del laboratorio | Logout limpia `securefinance.ldf.sid` sin borrar la cookie de la instalación principal | PASS |

## 2. Suite completa del ERP

`npm.cmd test` ejecutó **269 pruebas, 269 PASS, 0 FAIL**. Incluye autenticación, ventas, facturación, auditoría, DDL, compras, cotizaciones, créditos, multibodega, promociones, usuarios, dashboard y el módulo LDF. Esto comprueba que los cambios compartidos (registro de rutas, navegación, cookie opcional, scripts npm) no rompieron los módulos existentes.

## 3. SQL real (`test:sql:ldf`) — 15/15 PASS

| # | Prueba | Evidencia real |
|---|---|---|
| 1 | Métricas contra catálogo/DMV | Físico **192 MB**, uso **20.617 %**, **7 VLF**; suma usado+libre = lógico con tolerancia de redondeo |
| 2 | `DBCC SQLPERF(LOGSPACE)` y `DBCC LOGINFO` | Coinciden con `sys.dm_db_log_space_usage` y `sys.dm_db_log_info`; DBCC se ejecutó solo como DBA de laboratorio, sin dar permisos a la web |
| 3 | Cadena no inicializada | Antes del primer FULL, `ChainReady=false` y el respaldo devolvió `FALLIDO`, código **59016**, sin archivo; la evidencia persiste en `P4_LDF_Ejecucion` |
| 4 | FULL inicial de laboratorio | `BACKUP DATABASE ... WITH CHECKSUM` + `RESTORE VERIFYONLY WITH CHECKSUM`; creó la cadena solo dentro del laboratorio |
| 5 | Mínimos privilegios | Usuario web y worker: `sysadmin=0`, `db_owner=0`, `BACKUP LOG` directo=0; lectura directa de configuración/DMV denegada; EXECUTE del respaldo denegado a la web; actor inválido rechazado con 54101 |
| 6 | Respaldo manual real | `CONFIRMADO`, `backup_set_id=41`, checksum real, aparece en `msdb`, `VERIFYONLY` correcto y métricas reconsultadas |
| 7 | Idempotencia y conciliación | Repetir la misma UUID no crea otra copia; una ejecución marcada `EN_CURSO` se reconcilia con `msdb`; una UUID sin evidencia queda `INCIERTO` y no se reenvía |
| 8 | Bloqueo compartido | Con `SecureFinanceERP:BACKUP` tomado por otra sesión, el respaldo se rechaza de inmediato con **59013** |
| 9 | Firma sin `BACKUP LOG` | Al revocar el permiso al usuario de certificado, el procedimiento devuelve `FALLIDO` con **59017**; luego se restablece |
| 10 | Destino/ruta no autorizados | `Habilitado=0` produce 59010; un directorio inexistente produce fallo controlado sin exponer el error crudo del sistema operativo; la configuración se restaura |
| 11 | Umbrales configurables | Se graban 17/33, se leen desde SQL y se restablecen los valores originales; no se ejecutó ninguna acción sobre el LOG |
| 12 | Transacción activa y reutilización | Con una transacción abierta: `ACTIVE_TRANSACTION`, usado **148.205 MB**. Tras confirmar y respaldar: usado **60.355 MB**, físico **192 MB** sin cambios |
| 13 | Modelo SIMPLE | Base nueva en SIMPLE: `ChainReady=false`; respaldo rechazado con **59015**, sin crear archivo |
| 14 | HTTP con SQL real | Login real y respuestas **200** en `/dba/ldf`, `/dba/ldf/metrics`, `/cotizaciones`, `/promociones`, `/creditos`, `/multibodega`, `/auditoria/ddl` y `/compras`, sin depender del módulo Backups de Parte IV |
| 15 | Integridad e invariancia | `DBCC CHECKDB` y `CHECKCONSTRAINTS` sin errores; conciliación de stock en cero; trigger DDL activo; `Bitacora_DDL.ComandoTSql` sigue siendo `nvarchar(max)` |

Resultado persistido: `.data/ldf-sql-results.json` (ignorado por Git). Extracto verificable en la sección 6.

## 4. Chromium + SQL real (`test:ui:ldf`)

| Verificación | Resultado |
|---|---|
| Anchos 1440, 1024, 768 y 390 px | Sin desbordamiento horizontal; panel, VLF e historial legibles |
| Respaldo real desde el botón | UUID `b5153edd-5fbb-440d-b6e4-4d27eb14f65d` confirmado por SQL y visible en el historial |
| Doble clic | Un solo POST; una sola copia en `msdb` |
| Respuesta perdida | La operación real termina; la interfaz conserva la referencia, muestra advertencia y al recargar la concilia; no se repite el respaldo |
| `sessionStorage` bloqueado | No se envía el POST; se explica que no se puede conservar la referencia |
| Errores JavaScript | **0** |
| Respuestas HTTP del módulo | Ninguna ≥ 400 durante el recorrido |

Evidencias: `docs/parte4/ldf/evidencias/panel-{1440,1024,768,390}.png`, `vlf-{1440,1024,768,390}.png`, `respaldo-confirmado.png`, `respuesta-incierta.png`, `browser-results.json`.

## 5. Restauración independiente (`test:restore:ldf`)

- Origen: `SecureFinanceERP_P4_LDF_20261104033413_019717ca`.
- FULL de laboratorio: `backup_set_id=40`.
- LOG restaurados en orden: `41, 42, 43, 44, 45, 46`.
- Destino nuevo: `SecureFinanceERP_P4_LDF_Restore_20261104035849_9742214d`.
- Sin `REPLACE`; archivos MDF/LDF movidos a nombres nuevos.
- `DBCC CHECKDB` del destino: **sin errores**.
- La base restaurada no queda autorizada para el panel (su `database_guid` no coincide con la configuración instalada).

Resultado: `.data/ldf-restore-results.json` (ignorado por Git).

## 6. Evidencia reproducible

Comandos, desde el worktree:

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run test:ldf
npm.cmd run test:sql:ldf
npm.cmd run test:ui:ldf
npm.cmd run test:restore:ldf
```

Los reportes `.data/ldf-sql-results.json`, `.data/ldf-restore-results.json` y `docs/parte4/ldf/evidencias/browser-results.json` se regeneran al ejecutar las pruebas. Los dos primeros no se versionan porque `.data/` está ignorado; las capturas y `browser-results.json` sí forman parte de la entrega.

## 7. Límites y pruebas no ejecutadas

- No se probaron Availability Groups, réplicas reales, espejo, replicación ni CDC. El panel muestra sus causas de espera con recomendaciones, pero no se simula infraestructura no disponible.
- No se probaron SQL Server 2017, 2019 ni Linux. El código contempla la diferencia de permisos (`VIEW SERVER STATE` vs. `VIEW SERVER PERFORMANCE STATE`), pero la validación real fue en SQL Server 17 (2025) sobre Windows.
- No se ejecutó `DBCC SHRINKFILE`, borrado de `.ldf`, cambio automático a SIMPLE ni manipulación de archivos: están prohibidos por diseño.
- No se recibió el PDF de Parte IV ni las observaciones de Parte III; no se atribuyen los umbrales 70/85 ni la arquitectura Node a esos documentos. La diferencia con la especificación C# queda pendiente de confirmación del ingeniero.
- El laboratorio conserva su LOG y sus respaldos después de las pruebas; no se limpian automáticamente para no ocultar evidencia. Las bases de prueba pueden eliminarse manualmente por el DBA cuando ya no se necesiten.

## 8. Conclusión

Con las validaciones ejecutadas, el módulo `/dba/ldf` funciona de forma autónoma, muestra métricas reales, distingue correctamente las causas de no reutilización, rechaza operaciones incompatibles, ejecuta un respaldo LOG verificable con permisos separados y conserva trazabilidad ante respuestas inciertas. La integración con los módulos existentes no presentó regresiones en las 269 pruebas de la suite.
