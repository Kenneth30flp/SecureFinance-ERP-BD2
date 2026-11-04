# Parte IV · Módulo 1 · UC13

Implementación para la aplicación Express/EJS vigente, rama `feature/p4-edward-backups`. No se ejecutan migraciones al arrancar HTTP. El servidor web **no importa el ejecutor ni carga sus credenciales**. Las operaciones son reales una vez instaladas: no hay modo demo ni resultados SQL simulados en producción.

## Arquitectura y acceso

`/dba/backups` pertenece a Administración. Usa sesiones, cambio obligatorio de contraseña, navegación corporativa y estilos oscuros existentes. Requiere `DBA_BACKUPS_CONSULTAR`; solicitar FULL/DIFF/LOG exige además `DBA_BACKUPS_EJECUTAR`, y planificar/ejecutar PITR exige además `DBA_BACKUPS_RESTAURAR`. El usuario procede exclusivamente de la sesión. SQL vuelve a comprobar permisos vigentes al encolar y el ejecutor los comprueba antes de operar. Asigne los permisos explícitamente a los roles ERP autorizados; la instalación no los concede automáticamente. Reinicie la sesión después de asignarlos.

POST usa CSRF independiente y UUID de idempotencia. La web solamente puede ejecutar dos procedimientos de consulta/cola. `BackupsJob` conserva solicitudes, actor, fechas, estados, resultados y plan. `BackupsExecution` conserva ejecución de BACKUP y verificación. `BackupsAudit` conserva eventos con actor ERP, login SQL y UTC; la cuenta web no puede editar ninguna de estas tablas. El worker solo recibe INSERT/SELECT sobre auditoría, sin UPDATE/DELETE. El historial web muestra las últimas 100 solicitudes; los registros anteriores permanecen en SQL.

El proceso independiente toma un `sp_getapplock` exclusivo de sesión y utiliza un pool de una conexión. Otro proceso sale sin operar. Antes de cada trabajo comprueba que conserva el bloqueo. Tras un cierre inesperado, un trabajo en ejecución pasa a INCIERTO: nunca se vuelve a lanzar automáticamente. Un backup además toma su propio bloqueo SQL. Las solicitudes manuales y automáticas se serializan en la misma cola.

## Instalación explícita por DBA

Requisitos: Windows, Node >=24, SQL Server 2016 SP1 o posterior (Express incluido), ERP con Parte II y autenticación instalados, TCP SQL habilitado. No se necesita SQL Server Agent. Ejecutar primero en un laboratorio aislado autorizado. Estos pasos son instrucciones de despliegue; **no se ejecutaron en esta entrega**.

1. Instalar dependencias con `npm.cmd ci`. Crear, fuera del repositorio, carpetas de backup y recuperación, por ejemplo `D:\SFBackups\` y `D:\SFRecovery\`. No usar unidades mapeadas ni rutas UNC; no usar junctions/symlinks. La cuenta del servicio SQL necesita lectura/escritura en ambas carpetas. Los nombres de carpeta admiten letras ASCII, números, `_` y `-`. No conceder escritura a la cuenta Windows del servidor web.
2. Crear por los mecanismos seguros del entorno un login SQL dedicado al worker y un usuario correspondiente en ERP. No usar `sa`, `sysadmin`, `db_owner` ni la cuenta de la aplicación. El worker requiere capacidad de crear bases nuevas, por lo que sus credenciales **no deben ser accesibles al proceso web**. Ejecutar ambos procesos con identidades Windows distintas y ACL separadas. No poner secretos en argumentos de consola, Git o `package.json`.
3. Ejecutar `database/parte4/backups/01_backups.sql` seleccionando explícitamente la base ERP correcta en SSMS, con **modo SQLCMD** habilitado. Ambos scripts incluyen `:ON ERROR EXIT` para detenerse al primer error entre lotes GO. No crea bases ni cambia su modelo de recuperación. Revisar también los triggers DDL corporativos vigentes antes de instalar.
4. Ejecutar `02_permissions.sql` en modo SQLCMD con `ErpDatabase`, `WebUser`, `WorkerLogin`, `WorkerUser`, todos identificadores controlados por el DBA. Verifica la separación por SID de los logins, la asociación del usuario ERP/msdb al login worker y que este no sea propietario del ERP. Las concesiones se realizan en una transacción. El script concede permisos sobre objetos concretos, lectura de las dos tablas de historial msdb, BACKUP, CREATE ANY DATABASE y VIEW ANY DATABASE (visibilidad de destinos y sys.database_recovery_status). No concede sysadmin ni privilegios DBA a la web. Verificar además permisos heredados del login web: debe seguir sin CREATE ANY DATABASE, BACKUP o membresías amplias. El script no elimina concesiones ajenas preexistentes.
5. Configurar la ruta autorizada en SQL, manualmente, como DBA:

```sql
-- En la base ERP seleccionada. Sustituir por la ruta local real del servicio SQL.
INSERT dbo.BackupsConfig(Id,Ruta,Compresion) VALUES(1,N'D:\SFBackups\',0);
```

Para una reinstalación revisar la fila existente y usar UPDATE explícito. Express usa `Compresion=0` y el comando emite NO_COMPRESSION aunque el servidor tenga otro valor predeterminado. En ediciones Standard/Enterprise compatibles puede habilitarse `Compresion=1`; el procedimiento rechaza ediciones no compatibles. CHECKSUM y RESTORE VERIFYONLY son obligatorios. Los medios usan UUID, extensión `.bak`/`.trn` y nunca INIT/FORMAT.

6. El DBA debe comprobar recovery FULL y una cadena inicializada. Si la base está en SIMPLE, el módulo falla de forma explícita; **no la cambia automáticamente**. La conversión a FULL y el FULL inicial son operaciones de despliegue que requieren autorización específica del entorno. Un FULL manual del módulo puede inicializar la cadena después del cambio autorizado. No habilitar DIFF/LOG hasta disponer del FULL.
7. Preparar el archivo de secretos externo descrito abajo y probar el ejecutor solamente en el laboratorio autorizado. Abrir `/dba/backups` con el usuario ERP autorizado. Un POST devuelve PENDIENTE; solo el resultado posterior del worker puede confirmar éxito.

## Variables del ejecutor

La conexión habitual del ERP conserva `DB_*`. No añadir variables `BACKUPS_DB_PASSWORD` al `.env` del servidor web.

| Variable | Uso |
|---|---|
| `BACKUPS_ENV_FILE` | Ruta absoluta del archivo externo de configuración, definida por Run-Task.ps1 |
| `BACKUPS_DB_SERVER` | Host TCP SQL Server |
| `BACKUPS_DB_PORT` | Puerto TCP, predeterminado 1433 |
| `BACKUPS_DB_NAME` | Base ERP origen, también contiene la cola |
| `BACKUPS_DB_USER` | Login dedicado del ejecutor |
| `BACKUPS_DB_PASSWORD` | Secreto suministrado fuera de Git |
| `BACKUPS_DB_ENCRYPT` | `true` por defecto |
| `BACKUPS_DB_TRUST_SERVER_CERTIFICATE` | `false` por defecto; preferir certificado confiable |
| `BACKUPS_ROOT` | Carpeta exacta autorizada en BackupsConfig, terminada en `\` |
| `BACKUPS_RESTORE_ROOT` | Carpeta independiente para archivos recuperados, terminada en `\` |

En archivos dotenv usar comillas simples en rutas Windows, por ejemplo `BACKUPS_ROOT='D:\SFBackups\'`. Mantener archivo secreto en un directorio fuera de OneDrive y del repositorio; restringir ACL a la identidad del worker y administradores. El ejecutor rechaza `sa`, sysadmin y una cuenta igual a DB_USER cuando esa variable está presente. La separación real depende además de usuarios y ACL de despliegue; no es una barrera contra un administrador SQL.

## Programador de tareas de Windows

En PowerShell elevado, desde el repositorio, después de preparar la cuenta Windows dedicada y sus permisos de inicio de sesión por lotes:

```powershell
.\scripts\parte4\backups\Install-Task.ps1 -SecretsFile 'C:\SecureFinanceSecrets\backups.env' -RunAsUser 'EQUIPO\sf_backup_runner'
```

El instalador crea `SecureFinance-UC13`, ejecuta cada minuto, usa S4U y privilegios Windows limitados, impide instancias superpuestas y recupera inicios omitidos. Rechaza reemplazar una tarea existente. S4U se limita a recursos locales; no usar EFS ni recursos de red autenticados. `Run-Task.ps1` conserva el código de salida Node para LastTaskResult. No se instala ni inicia ninguna tarea durante desarrollo o `npm test`.

La política SQL inicia deshabilitada. Tras verificar el FULL inicial, habilitarla explícitamente:

```sql
UPDATE dbo.BackupsSchedule SET Enabled=1,CursorUtc=SYSUTCDATETIME() WHERE Id=1;
```

FULL los domingos a 00:00 UTC, DIFF **todos los días** a 00:00 UTC y LOG cada 15 minutos, incluyendo medianoche. Coincidiendo en un turno, el orden es FULL, DIFF y LOG. UTC evita ambigüedades de horario de verano; en Guatemala medianoche UTC equivale a 18:00 del día anterior. El worker corre cada minuto para atender solicitudes manuales y comprobar turnos. Los horarios son fijos en esta versión.

La clave única de turno evita duplicaciones; cada turno vencido aparece OMITIDO, sin fingir que se ejecutó. Solo el turno vigente se encola automáticamente. Interrupciones mayores de 31 días generan un registro del intervalo anterior y detalle por turno para los últimos 31 días. Los trabajos fallidos se conservan sin reintento automático. Después de un FULL omitido, solicitar FULL manual y revisar la cadena antes de continuar. No hay política de borrado de medios ni del historial: el DBA debe vigilar espacio y preservar todas las piezas necesarias para el horizonte PITR.

La vista muestra habilitación SQL, heartbeat y solicitudes. Una señal de más de cinco minutos se informa como no reciente, incluso si una operación larga sigue activa; comprobar entonces Inicio/Estado y el Programador. La vista no afirma que Windows tenga una tarea instalada solo porque Enabled sea 1. Consultar `Get-ScheduledTaskInfo -TaskName SecureFinance-UC13` y el registro operacional de TaskScheduler para fallos de lanzamiento.

## Recuperación PITR

1. Ingresar fecha/hora con segundos **en la hora local del servidor SQL**, que es la usada por backupset y STOPAT. No convierte silenciosamente entre UTC y hora local. Configurar SQL en UTC cuando sea posible; en zonas con DST no seleccionar horas ambiguas.
2. Dar un nombre `SF_Recovery_...`, nunca el nombre origen. Generar plan; el worker elige FULL no copy-only anterior al punto, DIFF opcional con base LSN correcta y LOG continuos de la misma familia/rama. Usa BigInt/string para LSN, sin pérdida de precisión. Excluye medios dañados, sin checksum, BULK_LOGGED, bandas múltiples y dispositivos no DISK.
3. Exige un LOG que **comience después** del punto, condición conservadora compatible con servidores anteriores a SQL 2022. Puede requerir esperar el siguiente LOG incluso si un backup recién terminado ya contiene el punto. Si hay una brecha o los medios no son suficientes, falla; no aproxima la hora.
4. Verifica HEADERONLY/UUID, FILELISTONLY y VERIFYONLY sobre **todos** los medios antes de ofrecer el plan. Acepta archivos convencionales D/L presentes en FULL; rechaza FILESTREAM y archivos nuevos/cambios de identidad posteriores. Los LOG/DIFF pueden omitir contenidos ya presentes en FULL. Solo admite medios dentro de BACKUPS_ROOT. Los medios externos válidos se incorporan vía msdb si cumplen esas restricciones; no se aceptan rutas del navegador.
5. Revisar comandos en el historial y ejecutar el plan. Solo su autor puede ejecutarlo, una vez, dentro de 30 minutos. El worker verifica otra vez autorización, medios y archivos; rechaza un destino existente y una configuración modificada. MOVE usa nuevos nombres físicos con UUID por plan, independientes para todos los MDF/NDF/LDF.
6. FULL/DIFF usan NORECOVERY y STOPAT. Cada LOG usa STOPAT + RECOVERY: SQL mantiene RESTORING cuando todavía no se alcanzó el punto. El ejecutor se detiene al primer ONLINE confirmado y no aplica logs posteriores. No existe RECOVERY final incondicional: si ninguno alcanza el punto, falla conservando la base sin recuperar. Antes del primer RESTORE vuelve a rechazar destinos existentes en el mismo lote SQL; los siguientes pasos verifican el ID, fecha de creación y estado RESTORING del destino creado por esta ejecución. Cada lote comprueba también el bloqueo de sesión. **No hay WITH REPLACE, DROP DATABASE, ALTER del origen ni restauración en el origen**. Un fallo conserva la base parcial para inspección DBA y exige otro nombre/plan para reintentar. No se cambia la conexión del ERP ni se realiza una conmutación automática a la base recuperada.

Los permisos CREATE ANY DATABASE permiten al worker crear destinos y ser dueño de ellos, sin ser dueño del ERP. Por eso este proceso es una frontera administrativa y sus secretos/archivos ejecutables deben estar protegidos. El DBA debe gestionar el acceso a los datos de las bases recuperadas y su eliminación posterior fuera de UC13.

## Verificación y alcance académico

Ver [VALIDACION.md](VALIDACION.md) y [ARCHIVOS.md](ARCHIVOS.md). Las pruebas Node usan dobles explícitos y fixtures solo en tests; no acreditan que un BACKUP o RESTORE haya ocurrido. La compilación/ejecución T-SQL, permisos efectivos, tarea Windows y recuperación de transacciones reales necesitan laboratorio aislado y siguen pendientes.

El documento académico pide C#. El repositorio vigente usa Node.js/Express/EJS; UC13 se integra en esa arquitectura y el ejecutor independiente también es Node.js. Se cumplen los flujos funcionales mediante SQL Server, pero **no se entrega implementación C# ni se afirma cumplimiento del requisito tecnológico C#**. Esa discrepancia debe ser aceptada académicamente o resolverse en una entrega C# separada.

Referencias oficiales utilizadas: [BACKUP y permisos](https://learn.microsoft.com/en-us/sql/t-sql/statements/backup-transact-sql), [recuperación Point-In-Time y STOPAT](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/restore-a-sql-server-database-to-a-point-in-time-full-recovery-model), [metadatos backupset](https://learn.microsoft.com/en-us/sql/relational-databases/system-tables/backupset-transact-sql).
