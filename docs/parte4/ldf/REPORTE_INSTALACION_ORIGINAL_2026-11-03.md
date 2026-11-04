# Instalación LDF: ensayo aprobado; original pendiente de autorización

Fecha local: 3 de noviembre de 2026 (Guatemala). Evidencias SQL generadas el 4 de noviembre UTC.

## Resultado

**LDF todavía no quedó instalado ni habilitado en la instalación original.** Investigación y segundo ensayo completados el 4 de noviembre de 2026. La base original continúa pendiente de autorización explícita. El error inicial se debió a que la copia restaurada conservaba el vínculo de autorización de la original. No fue necesario modificar el trigger ni la función de autorización.

## Actualización del 4 de noviembre: investigación y ensayo completo

Se leyeron las definiciones reales de `P3_DDL_CapturarEstructura` y `P3_INT_Destino()` en SQL Server y se comprobaron con el operador DBA y bajo `P3_DDL_Escritor`:

- Original: la propiedad `P3.Despliegue.Autorizacion` coincide con `9U8ICS2VLMRUE|SecureFinanceERP`; la función devuelve `SecureFinanceERP`.
- Copia: conserva esa misma propiedad, pero su nombre es distinto; la función devuelve `!DESPLIEGUE_NO_AUTORIZADO!`. El rechazo 54993 es correcto.
- La función desplegada es la política de despliegue original, no la política de laboratorio sintético de `database/integration/00_AutorizacionLaboratorio.sql`. El mensaje «laboratorio» del trigger no distingue ambas políticas.

Se desarrolló un alcance DBA limitado a copias restauradas, con servidor, nombre, GUID y token Windows sysadmin comprobados; evidencia local y revocación en `finally`. No modifica funciones ni triggers ni crea un procedimiento permanente de omisión. Se documenta en [COMPATIBILIDAD_DDL.md](COMPATIBILIDAD_DDL.md).

El primer ensayo autorizado instaló LDF correctamente, pero la regresión chocó con una promoción real vigente. El rechazo funcional fue correcto; se retiró la autorización y se deshabilitó el login. Se corrigió únicamente la selección de fixtures de la prueba para evitar promociones y perfiles de crédito existentes. No se cambiaron reglas SQL ni datos históricos.

El ensayo completo se repitió desde el mismo FULL, restaurándolo con CHECKSUM y MOVE en **otra base nueva**, sin REPLACE:

`SecureFinanceERP_LDF_Rehearsal_20261104060210`

Resultado: **PASS**, terminado `2026-11-04T06:03:01.106Z`.

Pruebas SQL reales aprobadas:

1. FULL original nuevamente verificable con CHECKSUM.
2. Instalador LDF oficial ejecutado con captura DDL activa, sin error 54993.
3. Métricas reales y VLF comparados con archivos y DMV; 72 MB físicos y 5 VLF en la copia. Historial y respaldos consultados realmente: ambos vacíos para la identidad nueva de la copia; no se inventaron registros.
4. Aplicación y servicio separados, sin sysadmin, db_owner, BACKUP LOG directo ni lectura directa de configuración/DMV. Servicio sin acceso a la original, sin roles de servidor y con CONNECT SQL como único permiso explícito de servidor. Aplicación sin permiso de ejecutar el respaldo ni CREATE TABLE.
5. Actor inválido rechazado por SQL; ambos permisos LDF asignados al Administrador de la copia.
6. Tres firmas LDF verificadas; claves privadas de certificados retiradas.
7. Seis eventos DDL capturados con atribución al operador. `ComandoTSql` comparado como bytes, incluido un comando Unicode de más de 4.000 caracteres.
8. Autorización revocada dentro de una prueba transaccional: error 54993, objeto ausente y rollback correcto.
9. Cotizaciones, promociones, crédito/abonos/caja, multibodega y auditoría DDL: operaciones reales con rollback.
10. Compras: aprobación independiente, recepción parcial/completa, reintento idempotente, cancelación, Kardex, stock y valoración, con rollback.
11. Hashes SHA-256 con multiplicidades de todas las filas preexistentes en 65 tablas: ninguna modificada ni perdida. Incluye usuarios, credenciales, roles, asignaciones y auditoría histórica. Solo se permiten filas nuevas del módulo y de auditoría DDL de ensayo.
12. Todas las definiciones SQL previas permanecen exactamente iguales, incluidos trigger y función.
13. CHECKDB, comprobación de restricciones, conciliación de stock y trigger habilitado.
14. Vínculo de autorización de la copia devuelto al valor original; la copia vuelve a ser rechazada por la política de Parte III. Login temporal deshabilitado.

Evidencias locales ignoradas por Git: `.data/ldf-restored-sql-results.json`, `.data/ldf-six-modules-validation.json`, `.data/ldf-restored-authorization-*.json`. Los archivos privados de conexión no se publican.

No se ejecutó BACKUP LOG. No se comprobó todavía un login web con la contraseña habitual de admin; las verificaciones SQL usan su identidad y permisos existentes sin leer ni cambiar la contraseña.

## Plan exacto para la original, sujeto a autorización

No se necesita migración de compatibilidad DDL: **cero cambios** en trigger, función o propiedad de autorización de la original. La compatibilidad se logra autorizando correctamente el ensayo, no relajando la política original.

Tras autorización explícita, el plan es:

1. Reconfirmar servidor `9U8ICS2VLMRUE`, base `SecureFinanceERP`, GUID, política DDL, integridad y recuperabilidad del FULL. Tomar un nuevo FULL COPY_ONLY/CHECKSUM previo al cambio para cubrir actividad posterior y verificarlo/restaurarlo en otra base nueva.
2. Crear un login SQL dedicado nuevo `securefinance_ldf_service`, con secreto aleatorio guardado localmente, política de contraseña, CONNECT SQL y sin roles de servidor ni acceso a otras bases. Si ya existe, detenerse y revisar su identidad/privilegios; no reemplazar contraseña.
3. Ejecutar el instalador oficial, transaccional, exclusivamente sobre la original: agregar tablas `P4_LDF_Configuracion` y `P4_LDF_Ejecucion`; procedimientos `P4_LDF_Validar`, `P4_LDF_Consultar` y `P4_LDF_RespaldarLog`; índices y restricciones propios. Agregar dos permisos `DBA_LDF_*` y sus asociaciones al rol `Administrador` existente. No reejecutar migraciones antiguas.
4. Crear los dos certificados y sus usuarios internos en la original, más el usuario `P4_LDF_BackupService`. Crear el certificado y login de certificado de lectura en master y certificado/usuario correspondiente en msdb, con nombres derivados del servidor/base. Firmar los procedimientos y retirar las claves privadas.
5. Conceder al usuario web solo EXECUTE del punto de consulta; al servicio dedicado solo EXECUTE del punto de respaldo. El certificado de lectura recibe los permisos DMV de SQL 2022 y SELECT limitado a backupset/backupmediafamily en msdb; el certificado de respaldo recibe BACKUP LOG. Ninguna cuenta de aplicación recibe privilegios administrativos.
6. Registrar como destino LDF el directorio local de respaldos del motor, comprobar su existencia y escritura efectiva mediante el FULL previo; umbrales 70/85. No ejecutar LOG de prueba sin una autorización de destino/cadena específica.
7. Agregar localmente `LDF_DATABASE`, `LDF_EXPECTED_SERVER`, `LDF_ADMIN_USER`, `LDF_ADMIN_PASSWORD`, conservando DB_*, SESSION_* y demás configuración. Mantener secretos fuera de Git. Reiniciar únicamente el proceso web identificado de la instalación original; la sesión en memoria requerirá nuevo login.
8. Comprobar firmas, permisos, conservación de datos, SQL real, VLF y regresiones. Pedir al usuario iniciar sesión con admin habitual en el navegador; verificar `/dba/ldf` y los seis módulos sin leer la contraseña ni sustituir la autenticación.

La reversión de un fallo SQL es la transacción del instalador. Después de una instalación confirmada, cualquier desinstalación requiere otro plan que conserve auditoría. No se restaurará destructivamente la original ni se borrarán registros para «revertir».

Las secciones siguientes conservan la evidencia del primer intento del 3 de noviembre.

## Inspección

- HEAD: `2e72db9`, integración oficial de Parte IV. Árbol de trabajo inicialmente limpio.
- Se revisó `INSTALACION.md`, el instalador oficial y sus requisitos.
- Servidor verificado: `9U8ICS2VLMRUE`; SQL Server `16.0.1000.6` (2022).
- Base original: `SecureFinanceERP`, ONLINE, recuperación FULL.
- Usuario web original `admin`: activo, UsuarioId 3. Rol `Administrador`: activo, RolId 2.
- `securefinance_app` no pertenece a `db_owner`.
- No existían objetos LDF ni una cuenta SQL dedicada a LDF.
- Se observó `last_log_backup_lsn` no nulo. No se ejecutó ningún BACKUP LOG de prueba.

## Respaldo y restauración

Se creó un FULL **COPY_ONLY, CHECKSUM**, sin sobrescribir medios existentes. COPY_ONLY conserva la base diferencial de la política previa.

Archivo local al motor:

```text
C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Backup\SecureFinanceERP_PreLDF_20261104054200.bak
```

Pruebas superadas:

1. BACKUP DATABASE completo con CHECKSUM.
2. RESTORE VERIFYONLY con CHECKSUM.
3. Restauración con CHECKSUM y MOVE a archivos nuevos, en `SecureFinanceERP_LDF_Rehearsal_20261104054200`, sin REPLACE.
4. DBCC CHECKDB de la base restaurada, sin errores.

La base original no recibió ninguna restauración. La copia y el respaldo se conservaron. Evidencia local adicional: `.data/ldf-original-backup-result.json`.

## Ensayo y bloqueo

Se creó exclusivamente para el ensayo el login SQL `securefinance_ldf_trial_20261104054200`, con secreto aleatorio local, política de contraseña activada y GRANT CONNECT SQL. No se reutilizó `sa` ni `securefinance_app` para el servicio administrativo.

Se invocó la función `install` del instalador oficial `scripts/parte4/ldf/install.cjs`, autorizando únicamente la copia restaurada y solicitando los permisos del rol `Administrador`.

El motor rechazó la instalación:

```text
Msg 54993, Procedure P3_DDL_CapturarEstructura, Line 11
Captura DDL fuera del laboratorio autorizado.
```

El ensayo no pasó. No se interpretó este error como permiso para modificar la auditoría DDL ni su identidad autorizada.

Comprobaciones posteriores:

- Original: cero objetos LDF y cero permisos `DBA_LDF_*`.
- Copia de ensayo: cero objetos LDF, cero permisos `DBA_LDF_*` y cero certificados LDF; se confirmó la reversión del instalador.
- Comparación SQL bidireccional entre original y copia: coinciden los usuarios, sus hashes, salts, estado, cambio obligatorio y fecha de cambio de contraseña. No se mostraron estos secretos.
- Login temporal de ensayo deshabilitado (`is_disabled = 1`), conservado como evidencia.
- `.env` sin cambios; no se publicaron contraseñas ni se configuraron variables para un módulo no instalado.
- No se reinstalaron Partes I–III, no se cambiaron contraseñas y no se hicieron respaldos LOG de prueba.

## Pruebas de código

`npm.cmd run test:ldf`: **10 pruebas aprobadas**, cero fallos. Cubren HTTP, sesiones/RBAC, CSRF, contratos, escape de datos, identidad SQL y separación de conexiones. Estas pruebas no sustituyen la verificación de SQL real ni el acceso con la cuenta habitual.

`npm.cmd test`: **269 pruebas aprobadas**, cero fallos y cero omitidas. La suite general incluye los módulos anteriores; no equivale a comprobarlos funcionalmente sobre la instalación original con una sesión real.

Actualización del 4 de noviembre: suite ampliada a **271 pruebas aprobadas**, incluidas **12 pruebas LDF**; `npm.cmd run check` aprobado. Las nuevas regresiones rechazan nombres de bases arbitrarios/original, falta de autorización, GUID inválido y ausencia de comprobaciones de identidad/captura.

## Pendientes del primer intento (resueltos parcialmente por la actualización anterior)

1. Revisar el contrato de autorización de `P3_DDL_CapturarEstructura` y preparar una forma soportada de ensayar LDF en la copia, conservando la auditoría y sus protecciones. No se modificó ese componente.
2. Completar un ensayo exitoso y comprobar los privilegios efectivos de la cuenta dedicada mediante conexiones SQL reales.
3. Solo después, crear y verificar una cuenta dedicada de producción y ejecutar el instalador oficial sobre `SecureFinanceERP`.
4. Configurar localmente `LDF_*`, asignar los dos permisos al rol existente y reiniciar el proceso web correspondiente.
5. Verificar `/dba/ldf` con el login web `admin` habitual, métricas contra DMV, VLF e historial. No se solicitó ni cambió su contraseña.
6. Probar BACKUP LOG únicamente con cadena válida y destino expresamente autorizado.
7. Verificar funcionalmente los seis módulos anteriores en SQL y web. No se declara esa regresión aprobada.

El ensayo ya fue aprobado. La instalación original permanece pendiente de autorización explícita, publicación/revisión del PR y comprobación web con la cuenta habitual.
