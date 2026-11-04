# Parte IV · UC14 · Administración del registro transaccional LDF

Responsable: Dylan. Rama: `feature/p4-dylan-ldf`. Punto de partida: `main@3b30519`.

Panel: **`/dba/ldf`**, en **Administración → Registro transaccional LDF**.

## Qué entrega

- Tamaño físico de todos los archivos LOG, rutas, crecimiento y límites.
- Uso lógico real, porcentaje y espacio libre con `sys.dm_db_log_space_usage`.
- Conteo, actividad, tamaños, distribución y mapa de VLF mediante `sys.dm_db_log_info(DB_ID())`.
- Modelo de recuperación, estado de la base y causa `log_reuse_wait_desc`, con recomendaciones específicas.
- Últimos 20 respaldos LOG reales de `msdb`, separados de las últimas 30 solicitudes del módulo.
- Respaldo manual `BACKUP LOG ... WITH CHECKSUM`, con directorio autorizado, cadena inicializada, permisos y exclusión concurrente.
- Umbrales configurables (inicialmente 70/85), sin acciones automáticas.
- Actualización manual y nueva lectura del motor al terminar un respaldo. Sin polling ni programador.

Es autónomo: **no importa ni necesita código de Backups de Parte IV de Edward**. Los módulos de Partes I–III ya presentes en el ERP son la base de autenticación y navegación.

## Documentos

- [Instalación y ejecución](INSTALACION.md)
- [Seguridad, SQL y contrato con Backups](ARQUITECTURA.md)
- [Matriz y resultados reales](PRUEBAS.md)
- [Explicación sencilla y guion para Dylan](EXPLICACION_DYLAN.txt)
- [Capturas para Rubén](evidencias/)
- [Texto preparado del PR](PR.md)

## Aclaraciones académicas

Se utiliza **Node.js 24, Express, EJS y SQL Server**, integrado al ERP existente. No se implementa una aplicación separada en C#. Esta diferencia con la especificación académica debe ser confirmada con el ingeniero; no se presume aprobada.

Se inició por la instrucción expresa de Dylan de comenzar. No se recibieron el PDF de Parte IV ni la calificación/observaciones de Parte III; queda pendiente contrastar esos materiales. Los porcentajes 70/85 son una política configurable de interfaz, no una exigencia atribuida al PDF.

## Distinciones importantes

1. El LDF es el registro interno de recuperación de SQL Server, no la tabla de auditoría de negocio ni la bitácora DDL.
2. Respaldar el LOG puede habilitar reutilización, pero **no reduce necesariamente el archivo físico**.
3. Espacio físico, espacio lógico libre y tamaño de VLF inactivos son métricas diferentes.
4. `last_log_backup_lsn` permite saber si el motor admite continuar la cadena. No prueba que todos los archivos antiguos sigan existiendo ni que una restauración completa sea posible; esto se verifica restaurando la cadena.
5. El estado de espera puede cambiar entre lecturas. Una transacción abierta no implica siempre `ACTIVE_TRANSACTION`: SQL informa su última evaluación de truncado.

No hay `SHRINKFILE`, eliminación del `.ldf`, tareas programadas ni cambios de modelo de recuperación en el módulo operativo.
