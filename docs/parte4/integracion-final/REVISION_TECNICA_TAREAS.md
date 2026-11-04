# Correcciones locales de tareas Windows y capacidad UC13

## Alcance y estado

Esta revisión corrige cinco defectos detectados en las herramientas locales de mantenimiento. No es un despliegue ni certifica que se haya cambiado la instalación original. No se ejecutaron migraciones, conexiones SQL reales, tareas, logons de cuentas de servicio, asignación de derechos ni exportaciones de credenciales reales durante las pruebas. No se publicaron commits.

Se preservan las cuentas existentes, las credenciales DPAPI ya custodiadas y los módulos del ERP. El reporte del despliegue LDF anterior permanece sin cambios en esta revisión. Las evidencias históricas de operación no se sobrescriben con fixtures.

## Contratos corregidos

### 1. Estado y propiedad de tareas

`Task-Safety.ps1` concentra las validaciones de tarea, identidad, propietario, SDDL, acción, argumentos y directorio. `Verify-Production.ps1` y `Enable-QueueTask.ps1` guardan el estado anterior y marcan la intención de modificación inmediatamente antes de escribir. Un fallo previo no produce limpieza de tareas.

La verificación controlada restaura el estado habilitado/deshabilitado anterior. Si falla la activación, se restaura la definición anterior y su SDDL, siempre que la tarea siga correspondiendo a la identidad y definición modificadas por esa ejecución. Cambios concurrentes de propietario, DACL, SID o definición impiden sobrescribirla y quedan como fallo de restauración para revisión humana. No se borran ni recrean tareas como recuperación automática. No se detienen instancias en ejecución para forzar una prueba.

`Repair-Task.ps1` rechaza una tarea existente y no la deshabilita desde su bloque de error. Su registro nuevo comienza deshabilitado. `Register-IsolatedTask.ps1` solo crea; las actualizaciones de activación conservan explícitamente el SDDL existente, sin agregar ni quitar ACE de principal. Las tareas nuevas usan propietario Administradores, control SYSTEM/Administradores y lectura/ejecución del worker.

### 2. Cuentas y custodia

La preparación nueva conserva `sf_backup_runner` como predeterminado. La reparación histórica puede preparar `sf_backup_task` sin renombrar ni cambiar el runner anterior. Los verificadores resuelven la cuenta local desde el SID de la tarea; un parámetro de cuenta explícito debe coincidir con ese SID. No se exige un nombre fijo en los logs.

Ambos flujos de preparación usan el mismo mecanismo de custodia `task-registration.credential.clixml`, fuera del repositorio en el runtime protegido. Se mantiene el formato Windows DPAPI de PSCredential. El archivo se crea con DACL privada desde el inicio, no se sobrescribe y se fija su propietario SYSTEM. Las credenciales no se pasan por argumentos de proceso ni se registran en evidencia. La contraseña requerida por COM se limita al bloque de registro y no se escribe como texto plano.

DPAPI requiere el mismo equipo y usuario custodio que realizó la exportación. Otro administrador o SYSTEM no puede asumir que podrá descifrarla solo por tener permiso de lectura. Si falta la custodia o no se puede descifrar, detenerse y solicitar un procedimiento aprobado; no resetear contraseñas ni generar credenciales para una cuenta existente. [Contrato oficial de Export-Clixml](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/export-clixml?view=powershell-5.1).

La verificación no asigna derechos, ni siquiera al recibir el parámetro heredado `GrantBatchRight`. El logon batch real valida si los derechos existentes —directos o por grupos— permiten continuar. Si faltan, se requiere mantenimiento expresamente autorizado aparte. No se elimina ninguna política deny ni se importa una política global.

### 3. Permisos efectivos y ejecutable

`Windows-Inspection.cs` usa un token batch de la identidad existente, duplicado como token de impersonación, y `AccessCheck` con MAXIMUM_ALLOWED. Esto contempla el SID y los grupos del token, no una lista inventada de grupos. Los buffers de contraseña nativos se borran y los handles se liberan. Las pruebas compilan estos tipos pero no invocan sus funciones nativas. [AccessCheck](https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-accesscheck).

La comprobación exige lectura efectiva sin escritura, append, borrado, cambio de DACL o propietario sobre configuración y código. Rechaza grupos que puedan escribir, DACL nula, ACE no soportada, lectores inesperados del secreto, EFS, reparse points del runtime y ancestros que permitan reemplazarlo. El worker solo puede modificar logs; no controlar su ACL o propietario. Se conserva el permiso de lectura del runner histórico cuando existe, sin modificar su cuenta.

La ruta Node está fijada por defecto a Program Files/nodejs/node.exe; una ruta alternativa debe suministrarse explícitamente y superar las mismas comprobaciones. Se exige una acción exec, argumentos exactos hacia run.cjs, directorio del runtime, S4U, Limited, IgnoreNew y un solo disparador temporal de un minuto. No se confía en la resolución de Node por PATH para registrar la acción.

Si una instalación existente incumple estas restricciones, la herramienta se detiene; no cambia propietario, ACL, ejecutable o identidad para lograr un PASS. Esa adaptación requeriría una autorización operativa independiente.

### 4. Capacidad

`capacity-review.cjs` separa cálculo puro de consultas, medición y escritura de informe. Devuelve:

- `INSUFFICIENT_INFORMATION` / **INFORMACIÓN INSUFICIENTE** si falta identidad, historial operativo FULL/DIFF/LOG, destino autorizado o medición válida.
- `INSUFFICIENT_CAPACITY` si la evidencia es suficiente, pero no hay espacio para estimación y reserva.
- `SUFFICIENT` solo para una estimación positiva con evidencia válida. Esto no aprueba retención ni activa la política SQL.

Los COPY_ONLY se distinguen y no se utilizan como sustituto silencioso del historial operativo. Los tamaños se calculan con BigInt; no se convierten a Number. Cada destino autorizado se abre en modo de lectura de atributos y se identifica su volumen real por GUID, incluidos puntos montados/resolución de enlaces; no se deduce su espacio desde la ubicación del MDF/LDF. Las mediciones de destinos faltantes, duplicadas, inconsistentes, antiguas o futuras se rechazan. Un fallo de consulta o medición produce informe fallido, no conserva un resultado positivo de esa ejecución.

`Get-BackupVolumes.ps1` recibe rutas como JSON por stdin y solo llama APIs de consulta. La activación vuelve a comprobar que las rutas autorizadas, el volumen y el espacio disponible no hayan cambiado. La estimación sigue sin demostrar crecimiento sostenido, cuotas de la cuenta SQL, capacidad indefinida ni política de borrado/retención; no se activa automáticamente `BackupsSchedule.Enabled`.

### 5. Ejecución programada y evidencia

La activación exige informes schema 2 de la base/servidor/GUID actuales, seguridad aprobada para el mismo SID/definición en los últimos 30 minutos y capacidad aprobada en los últimos 5. Evidencias históricas de schema anterior se conservan, pero no autorizan una activación nueva. También se vuelve a validar la protección real de archivos antes de modificar la tarea.

Se requiere un evento 107 y un evento de finalización 102 del intervalo actual, con la misma instancia. La identidad se comprueba en el evento 102: el 107 no contiene UserContext en este Windows. Un evento de arranque manual 110, un 107 antiguo, otra tarea/instancia/usuario o un log viejo no acreditan ejecución programada. LastTaskResult 0 por sí solo no es suficiente.

## Pruebas reproducibles y seguras

```powershell
npm.cmd run check:backups
npm.cmd run check:ldf
node --test tests/parte4/backups/*.test.js tests/parte4/ldf/*.test.js
npm.cmd test
git diff --check
```

Las pruebas nuevas son `capacity-review.test.js`, `task-safety.test.js` y `task-safety.fixtures.ps1`. La batería PowerShell usa objetos falsos y datos sintéticos en memoria; no ejecuta los scripts de mantenimiento. Comprueba restauración/fallos/concurrencia, cuentas por SID, ACL y grupos, custodia, cinco defectos de capacidad, evidencia y correlación de eventos. Node también verifica que UC13 y UC14 conservan el mismo recurso SQL `SecureFinanceERP:BACKUP`, principal public, Exclusive/Session.

Los procesos desechables de pruebas y de consulta de volúmenes usan política de ejecución limitada a su propio proceso; no ejecutan Set-ExecutionPolicy ni cambian políticas persistentes. Se requiere Windows PowerShell 5.1 de 64 bits para las herramientas de mantenimiento. Las pruebas PowerShell se omiten explícitamente fuera de Windows; los tests puros de capacidad y los contratos de bloqueo se ejecutan en cualquier plataforma.

Resultados locales: `check:backups` y `check:ldf` aprobados; suite completa **302 pruebas aprobadas, cero fallos/omisiones**. La batería UC13/UC14 ampliada contiene **43 pruebas**; el caso PowerShell agrupa comprobaciones de los cinco defectos y compila el código nativo sin invocarlo. `git diff --check` sin errores. Estas verificaciones no sustituyen una ejecución operativa Windows/SQL aprobada.

## Pendiente de operación

Esta entrega permite revisión/commit del código después de aprobar los resultados locales. No sustituye la validación Windows real en ventana autorizada, la comprobación web con el admin habitual ni el cierre de retención/capacidad sostenida. No se ha cambiado la programación o el runtime protegido actual, ni se ha regenerado su credencial. Si una validación real exige cambiar identidad, propietario, derechos, custodia o ACL existentes, detenerse y pedir autorización antes de hacerlo.
