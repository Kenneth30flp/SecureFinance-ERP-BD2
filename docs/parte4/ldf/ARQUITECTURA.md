# Arquitectura, seguridad e integración

## Componentes propios

```text
src/modules/dba/ldf/          pools, service, routes, diagnostics
src/views/dba/ldf/            index.ejs
src/public/js/dba-ldf.js      interacción manual e idempotencia
src/public/css/dba-ldf.css    estilos limitados al módulo
database/parte4/ldf/          esquema, monitor, respaldo
scripts/parte4/ldf/           instalación, firmas, laboratorio, umbrales
tests/parte4/ldf/             unitarias/HTTP, SQL, Chromium y restauración
docs/parte4/ldf/              documentación y evidencia
```

Los cambios compartidos se limitan al registro de rutas/servicio, navegación, scripts npm y nombre opcional de cookie para un laboratorio concurrente. Logout limpia la cookie de la instancia, en vez de eliminar la sesión de otra instalación local. No se reemplazan procedimientos de negocio ni el trigger DDL.

## Flujo de privilegios

```text
Sesión web existente + RBAC + CSRF
 ├─ GET → conexión web → EXEC P4_LDF_Consultar
 │                        firma de lectura → DMV y msdb acotados a DB_ID()
 └─ POST → conexión administrativa separada → EXEC P4_LDF_RespaldarLog
                                            firmas de lectura + BACKUP LOG
                                            bloqueo + verificación + auditoría
```

- La web solo recibe `EXECUTE P4_LDF_Consultar`.
- El login de servicio solo recibe `EXECUTE P4_LDF_RespaldarLog` a través de `P4_LDF_BackupService`.
- Ninguna cuenta tiene `db_owner`, `sysadmin`, lectura directa de métricas privilegiadas, escritura directa a configuración/historial ni `BACKUP LOG` directo.
- `P4_LDF_ReadCertificate` firma las dos entradas. Certificado público en `master` con login **de certificado, no autenticable**, y usuario de certificado en `msdb`.
- SQL 2022+: `VIEW SERVER PERFORMANCE STATE` para uso del LOG y `VIEW DATABASE PERFORMANCE STATE` para VLF. SQL 2017–2019: `VIEW SERVER STATE` y `VIEW DATABASE STATE`.
- `VIEW ANY DATABASE` en el login de certificado permite metadatos de identidad en `sys.database_recovery_status`. Los procedimientos solo devuelven la base autorizada.
- `msdb`: SELECT solamente en `backupset` y `backupmediafamily`, mediante certificado; sin `db_datareader`.
- `P4_LDF_BackupCertificateUser` tiene únicamente `BACKUP LOG` en la base del módulo; aporta ese permiso solo al procedimiento firmado.
- Claves privadas eliminadas después de firmar; certificados sin credenciales utilizables por una conexión.
- `TRUSTWORTHY` y encadenamiento entre bases no se habilitan.
- Cada operación valida al usuario web activo y sus permisos vigentes en SQL, además de la sesión HTTP.
- Valores del navegador: solo UUID. Actor desde sesión. Sin parámetros para rutas, SQL, destino, permisos ni modelo de recuperación.

Las tablas nuevas `P4_LDF_Configuracion` y `P4_LDF_Ejecucion` se acceden por propiedad del módulo. El historial no es editable desde las cuentas de ejecución.

## Métricas: significado y límites

| Métrica | Fuente | Interpretación |
|---|---|---|
| Físico MB | `sys.database_files.size / 128` | Tamaño asignado, suma de todos los LOG |
| Lógico total/uso/libre | `sys.dm_db_log_space_usage` | Conjunto del LOG; no se atribuye un porcentaje individual a cada archivo |
| Uso % | `used_log_space_in_percent` | Porcentaje real del motor |
| VLF | `sys.dm_db_log_info(DB_ID())` | Conteo/actividad exactos y tamaños; detalle visible limitado a 200 |
| VLF inactivos MB | Suma de tamaños de VLF inactivos | No es idéntico a bytes libres del LOG |
| Espera | `sys.databases.log_reuse_wait_desc` | Última evaluación de truncado del motor; se muestra sin inventar causa |
| Cadena inicializada | `sys.database_recovery_status.last_log_backup_lsn` | NULL: no admite próximo LOG por modelo SIMPLE o ausencia de FULL/diferencial vigente |
| Último LOG | `msdb.backupset` + `backupmediafamily` | Filtrado por identidad y recovery fork actuales, no solo por nombre |

Los timestamps de la muestra y auditoría propia son UTC explícito. Las fechas de `msdb` se muestran como **hora local del servidor SQL**, sin fingir que sean UTC. Los LSN se transportan como texto decimal para no perder precisión en JavaScript.

La muestra incluye consultas sucesivas: SQL puede cambiar durante la lectura. No se bloquea la actividad del negocio para una foto perfectamente simultánea. Sin caché HTTP, intervalos ni cargas automáticas permanentes.

`DBCC LOGINFO` reemplazado por la DMV para SQL 2017+; se usa en las comprobaciones DBA del laboratorio junto con `DBCC SQLPERF(LOGSPACE)`. No se conceden privilegios adicionales a la web para ejecutarlos. Versiones anteriores al mínimo del ERP no están soportadas; no se simula un fallback para ellas.

## Respaldo e idempotencia

1. Validar destino (`ServerName`, `DB_NAME`, `database_guid`) y permisos del actor.
2. Adquirir `sp_getapplock` exclusivo con espera cero.
3. Si UUID existe, devolver su resultado. Si quedó `EN_CURSO`/`INCIERTO`, conciliar nombre, ruta, database GUID y fork en `msdb`; no ejecutar otro BACKUP.
4. Registrar nueva solicitud antes de empezar. Verificar FULL/BULK_LOGGED, ONLINE, escritura, `last_log_backup_lsn`, permiso firmado y directorio existente.
5. `BACKUP LOG @Db TO DISK=@File WITH CHECKSUM, NOINIT, NOFORMAT, NAME=@Name`.
6. Nombre de archivo único: `P4_LDF_<DBID>_<UUID>.trn`. Sin sobreescritura de archivos preexistentes, sin COPY_ONLY.
7. Confirmar `backup_set_id` del motor; registrar éxito, fallo controlado o incertidumbre. Liberar lock en ambas salidas.

La comprobación previa asegura elegibilidad del motor, **no la integridad física de toda la cadena almacenada**. La evidencia de restauración FULL+LOG se obtiene en una base nueva separada. El módulo manual no ejecuta RESTORE, VERIFYONLY, FULL ni CHECKPOINT por sí mismo.

Si el respaldo se pierde a mitad de conexión, SQL puede haber terminado. La interfaz conserva la UUID, evita doble clic y bloquea envío si no puede persistirla. No realiza reintentos automáticos. La auditoría queda acotada a intentos que superaron autenticación/permisos de entrada; rechazos de sesión/CSRF no llegan al servicio SQL.

## Contrato de exclusión para Edward

Para todas las operaciones FULL/DIFF/LOG que deban excluirse, ejecutar en la **misma base monitoreada** y conexión:

```sql
DECLARE @r int;
EXEC @r=sys.sp_getapplock
 @Resource=N'SecureFinanceERP:BACKUP',
 @LockMode='Exclusive', @LockOwner='Session', @LockTimeout=0,
 @DbPrincipal='public';
-- @r < 0: no ejecutar. No mantener una transacción durante BACKUP.
-- Tras finalizar, también en CATCH:
EXEC sys.sp_releaseapplock
 @Resource=N'SecureFinanceERP:BACKUP', @LockOwner='Session', @DbPrincipal='public';
```

El lock es por base y principal; adquirirlo en `master` no coordina con este módulo. Las operaciones externas que no participen del contrato siguen sujetas a los bloqueos/errores del motor, pero no se presume coordinación con ellas.

**Solo el programador de Edward debe programar LOG automáticamente.** Este módulo mantiene exclusivamente la acción manual. Edward debe considerar los `.trn` manuales al restaurar: un LOG normal participa de la misma cadena. La consulta de `msdb` ya incluye respaldos de cualquier origen de esa identidad/fork.

## Referencias oficiales

- [dm_db_log_space_usage](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-db-log-space-usage-transact-sql)
- [dm_db_log_info](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-db-log-info-transact-sql)
- [database_recovery_status y last_log_backup_lsn](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-database-recovery-status-transact-sql)
- [Guía de arquitectura del LOG](https://learn.microsoft.com/sql/relational-databases/sql-server-transaction-log-architecture-and-management-guide)

No se probaron failover AG, replicación real ni sistemas anteriores a SQL 17. Sus causas de espera tienen mensajes específicos, pero no se declaran pruebas de infraestructura que no se ejecutaron.
