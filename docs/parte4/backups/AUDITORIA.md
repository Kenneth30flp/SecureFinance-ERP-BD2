# Auditoría técnica UC13

Auditoría inicial conservada. La corrección del lock común, catálogo SQL real, rutas UC14 y recovery fork, junto con sus evidencias, está en [integración final](../integracion-final/README.md).

Se revisaron todos los archivos UC13 y sus cinco puntos compartidos de integración, no solo los 18 archivos principales mencionados inicialmente. El inventario completo está en ARCHIVOS.md. Esta auditoría no abrió conexiones SQL ni instaló tareas Windows.

## Correcciones

- PITR: se eliminó RECOVERY final incondicional. Los LOG usan STOPAT + RECOVERY y la ejecución termina al primer ONLINE confirmado por SQL; no se intenta reproducir un log posterior después de alcanzar el punto. Si el punto no se alcanza, el destino queda sin recuperar y el trabajo falla.
- Se conservan los milisegundos del historial SQL al comparar fechas con STOPAT, evitando seleccionar un FULL/DIFF posterior al segundo solicitado.
- El generador de comandos revalida la cadena guardada y protege otra vez el nombre origen. Cada lote destructivo exige el bloqueo de sesión. Antes del FULL se comprueba que el nombre destino no existe; los pasos posteriores exigen el mismo ID, fecha de creación y estado RESTORING.
- BACKUP se llama con parámetros tipados y una comprobación del bloqueo en el mismo lote. La cuenta de ejecución requiere BACKUP DATABASE/LOG y CREATE ANY DATABASE para la verificación/restauración; VIEW ANY DATABASE permite consultar el estado de recuperación y reconocer destinos existentes. Los accesos estáticos del procedimiento a sus tablas usan la cadena de propiedad dbo; el SQL dinámico utiliza los permisos explícitos del caller. No se introdujo EXECUTE AS OWNER, TRUSTWORTHY, sysadmin ni db_owner.
- Instalación: opciones SET necesarias para el índice filtrado; modo SQLCMD con detención al primer error; concesiones dentro de transacción; separación por SID, validación del mapeo ERP/msdb y rechazo de worker propietario del ERP.
- Configuración: validación estricta de puerto/TLS y archivo de secretos absoluto, existente, resuelto y externo al repositorio. El archivo externo prevalece sobre variables heredadas homónimas. El instalador Windows comprueba archivos y ejecutable.
- Programador: las solicitudes automáticas pendientes vencidas se marcan OMITIDO y las automáticas no se despachan con política deshabilitada. La web mantiene solicitudes manuales separadas. No hay dependencia del servidor HTTP para ejecutar la agenda.
- Web: contratos de respuesta SQL validados antes de confirmar solicitudes; cuerpo ausente rechazado; envíos dobles bloqueados y payload incierto conservado para reintento con el mismo UUID. Los planes vencidos o ya solicitados no ofrecen botón de ejecución. SQL mantiene la validación autoritativa aunque un plan previo no esté entre las últimas 100 filas.
- Interfaz: texto de navegación corregido, política visual alineada con FULL semanal/DIFF diaria/LOG cada 15 minutos, accesibilidad del destino de navegación y aviso sin JavaScript. Las vistas escapan resultados SQL y usan navegación/estilos corporativos existentes.

## Evidencia

Pruebas específicas añadidas: montaje real de createApp con login y servicio inyectado, entrega de CSS/JS, actor de sesión, renderizado de botones, metadatos escapados, plan vencido/usado, idempotencia del navegador, parada PITR al primer ONLINE, fallo sin RECOVERY forzada, rechazo de destino, configuración y respuestas SQL incompatibles. Son pruebas Node con dobles explícitos: no son restauraciones reales ni pruebas visuales de navegador.

`check:backups` incluye sintaxis JavaScript, parser PowerShell y aserciones estáticas de seguridad/contratos SQL. No equivale a compilar ni ejecutar T-SQL. Los resultados finales de la suite completa se conservan en check-final.txt y test-final.txt.

La implementación sigue las condiciones documentadas por Microsoft para [STOPAT y RECOVERY](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/restore-a-sql-server-database-to-a-point-in-time-full-recovery-model) y la [visibilidad de sys.database_recovery_status](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-database-recovery-status-transact-sql). La validación efectiva de permisos y comportamiento en Express sigue pendiente del laboratorio descrito en VALIDACION.md.
