# Ensayar LDF en una copia restaurada con auditoría Parte III

## Causa del error 54993

`95_P3_DDL_CapturaAplicable.sql` instala un trigger con seis eventos de tablas y procedimientos. Antes de insertar el EVENTDATA íntegro, exige que `dbo.P3_INT_Destino()` coincida con `DB_NAME()`. El texto del error dice «laboratorio», pero la definición desplegada en esta instalación usa la política de mantenimiento `P3.Despliegue.Autorizacion`, creada por `scripts/deployment/original-upgrade.cjs`.

La función real devuelve el nombre de la base únicamente cuando la propiedad coincide con `SERVERPROPERTY('ServerName') + '|' + DB_NAME()` y la base no es de sistema. No autoriza por sí misma al operador: SQL Server sigue exigiendo los permisos DDL correspondientes.

Restaurar el FULL conserva esa propiedad con el nombre **original**, aunque la copia tenga otro nombre. Es un rechazo correcto de la copia, no evidencia de que el trigger original sea incompatible con LDF. En la investigación se comprobó que la original devuelve `SecureFinanceERP`, tanto como DBA como bajo `EXECUTE AS USER = 'P3_DDL_Escritor'`. La copia devuelve `!DESPLIEGUE_NO_AUTORIZADO!`.

El instalador oficial LDF comprueba su propio destino mediante `P4_LDF.InstallTarget`; no reemplaza ni debe eludir la autorización de Parte III.

## Procedimiento DBA limitado a la copia

`scripts/parte4/ldf/restored-copy.cjs` proporciona un alcance de mantenimiento para el ensayo. No crea un procedimiento privilegiado permanente ni un permiso de omisión en la base. Requiere:

- Autorización explícita del operador.
- Nombre `SecureFinanceERP_LDF_Rehearsal_` seguido de 14 dígitos; rechaza la original y cualquier otro nombre.
- Servidor y GUID reales de la copia verificados en SQL.
- Token efectivo de la conexión Windows del operador miembro de `sysadmin`, ejecutando como `dbo`; se registran identidad original y efectiva. La variante de `IS_SRVROLEMEMBER` con el nombre MicrosoftAccount de `ORIGINAL_LOGIN()` puede devolver NULL aunque el token Windows sea administrador, por lo que se verifica el token de cada conexión nueva `sqlcmd -E`.
- Trigger de captura habilitado y propiedad todavía ligada al origen esperado.

El alcance conserva evidencia local con operador, equipo, aplicación, GUID, valores anterior/temporal, resultado y SQL de recuperación. Actualiza **solo el metadato de autorización de la copia**. Ejecuta el instalador oficial sin modificar su SQL y después las verificaciones. En `finally` devuelve la propiedad a su valor original. La copia vuelve a quedar rechazada por la política Parte III. El login de ensayo se deshabilita al finalizar.

No se cambian la función, el trigger, sus seis eventos, el escritor restringido ni las reglas de negocio. No se conceden permisos DDL a la aplicación. La autorización de destino y los permisos del operador son controles distintos.

Este alcance es para una copia aislada bajo control DBA. No se debe compartir el servidor/proceso de ensayo con escritores concurrentes. Un DBA con control total sigue pudiendo alterar metadatos: este procedimiento no pretende proteger frente a un `sysadmin` malicioso. El registro local tampoco sustituye SQL Server Audit para auditar todas las acciones administrativas.

## Ejecución del ensayo existente

Requiere los archivos locales ignorados por Git de la preparación anterior: `.data/ldf-original-backup-result.json` y `.data/ldf-original-trial-private.json`. El segundo contiene el secreto SQL de ensayo y no debe publicarse.

```powershell
node tests/parte4/ldf/restored-sql.cjs --authorize-restored-copy
npm.cmd run test:ldf
npm.cmd run check
npm.cmd test
```

El ensayo SQL es de una sola instalación. No reinstalar a ciegas sobre la misma copia si ya existe LDF: revisar el resultado y crear otra copia o preparar un paso de continuación revisado. No utilizar `lab:ldf` ni las migraciones antiguas para reconstruir la instalación original.

Para otra copia preparada con archivos locales independientes, se admiten `--backup-state=.data/otra-copia-backup.json` y `--trial-state=.data/otra-copia-private.json`. El ensayo aprobado de esta instalación utilizó `.data/ldf-second-copy-backup.json` y `.data/ldf-second-copy-private.json`. Nunca publicar esos archivos privados.

El ensayo verifica el FULL con CHECKSUM, compara hashes de todas las filas preexistentes con multiplicidades, conserva las definiciones SQL previas, prueba texto Unicode mayor de 4.000 caracteres y los seis eventos, revoca temporalmente la autorización dentro de un rollback para probar el error 54993, comprueba firmas y privilegios efectivos y ejecuta operaciones de los seis módulos de Parte III con rollback. No ejecuta BACKUP LOG.

## Recuperación de una interrupción

Una excepción normal ejecuta la revocación. Una terminación forzada, pérdida de conexión o caída del equipo puede impedir `finally`. Antes de otra operación, revisar `.data/ldf-restored-authorization-*.json`. Cada archivo conserva `recoverySQL`, comprobando servidor, nombre y GUID, para restituir únicamente el metadato de la copia. Si figura `CLEANUP_REQUIRED`, corregirlo antes de continuar. Comprobar también que el login temporal esté deshabilitado. No ejecutar ese SQL sobre la original.

La instalación LDF es transaccional; el cambio temporal de autorización de la copia y las pruebas son pasos separados. Si LDF ya confirmó su instalación y una prueba posterior falla, el módulo puede permanecer instalado **en la copia**. No declarar aprobado el ensayo completo ni avanzar a la original por ese motivo.

Las filas DDL de pruebas confirmadas se conservan en la copia; los comandos rechazados y las pruebas con rollback no dejan filas persistentes en un trigger transaccional. El rechazo se demuestra por el código de error y la ausencia del objeto. No se promete auditoría persistente de intentos revertidos.

## Instalación original y reversibilidad

Si la política original sigue devolviendo `SecureFinanceERP`, **no hace falta migración de compatibilidad DDL**. Modificar el trigger o crear un procedimiento de omisión ampliaría innecesariamente el alcance de seguridad. Conservar `95` y `P3_INT_Destino()` íntegros es el plan de compatibilidad, con cero cambios en esos objetos.

Antes de aplicar LDF, presentar al usuario la lista exacta de objetos, permisos, identidad administrativa, respaldo vigente y cambios locales. Obtener su autorización explícita para la original. Volver a verificar identidad, política, integridad y respaldo. Ejecutar solo el instalador oficial autorizado, agregar localmente las variables LDF y probar el acceso con la cuenta web habitual sin leer ni cambiar su contraseña.

El rollback de una instalación fallida es el rollback de su transacción. Después de una instalación confirmada, detener el proceso web y retirar/revertir la configuración local si fuera necesario; no restaurar la original ni borrar auditoría. Una desinstalación SQL requiere un plan independiente que compruebe dependencias y conserve los registros nuevos. No se incluye una eliminación automática de objetos.
