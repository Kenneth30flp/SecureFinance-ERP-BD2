# Instalación LDF en la original: SQL verificado; acceso web pendiente

Fecha local: 3 de noviembre de 2026 (Guatemala). Evidencias SQL generadas el 4 de noviembre UTC.

## Resultado

**LDF quedó instalado y configurado en `SecureFinanceERP` el 4 de noviembre de 2026, con autorización explícita del propietario.** Se completaron 16 comprobaciones del despliegue y una auditoría posterior de conservación. La aplicación original está activa en `http://localhost:3000`; falta concluir la comprobación web con una sesión real del admin habitual. No se declara aprobada esa comprobación mientras el propietario no haya iniciado sesión.

## Despliegue autorizado sobre la original — 4 de noviembre

Se ejecutó exclusivamente el plan de ocho pasos aprobado por el propietario, usando el instalador oficial sin modificarlo. La instalación SQL confirmó su transacción a `2026-11-04T06:16:55.166Z`. El procedimiento de instalación, configuración y reinicio terminó a `2026-11-04T06:17:15.617Z`. Las horas de esta sección son UTC salvo indicación expresa.

Identidad comprobada antes y después:

- Servidor: `9U8ICS2VLMRUE`, SQL Server `16.0.1000.6`.
- Base original: `SecureFinanceERP`, ONLINE, FULL.
- GUID original sin cambios: `3A93CC43-B4C7-4935-85D8-6D226BB0F56D`.
- `P3_INT_Destino()` devuelve `SecureFinanceERP`; su definición y propiedad de autorización permanecen intactas.

### Respaldo nuevo previo a cualquier cambio de instalación

```text
C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\Backup\SecureFinanceERP_PreLDF_Production_20261104061636.bak
```

Se creó FULL COPY_ONLY con CHECKSUM, se ejecutó VERIFYONLY con CHECKSUM y se restauró realmente con MOVE, CHECKSUM y RECOVERY en una base independiente nueva:

`SecureFinanceERP_PreLDF_Verify_20261104061636`

CHECKDB de la restauración no devolvió errores. Se conservaron el archivo y la copia. No se ejecutó REPLACE ni ninguna restauración sobre la original. El proceso web original se detuvo **después** de completar este respaldo y comprobar su restauración.

### Objetos y configuración instalados

- Tablas nuevas: `P4_LDF_Configuracion` y `P4_LDF_Ejecucion`, con sus restricciones e índices propios.
- Procedimientos nuevos: `P4_LDF_Validar`, `P4_LDF_Consultar` y `P4_LDF_RespaldarLog`.
- Certificados `P4_LDF_ReadCertificate` y `P4_LDF_BackupCertificate`, sus usuarios internos y las tres firmas esperadas. Se comprobó la eliminación de sus claves privadas.
- Certificado/login de lectura correspondiente en master y certificado/usuario en msdb, según el instalador oficial, para lectura DMV y de `backupset`/`backupmediafamily`.
- Login SQL nuevo `securefinance_ldf_service`, con política de contraseña, CONNECT SQL, sin roles de servidor y sin acceso a otras bases de usuario. Mapeado como `P4_LDF_BackupService` únicamente en la original, con EXECUTE del punto firmado de respaldo.
- `securefinance_app` conserva sus privilegios previos y recibe únicamente EXECUTE del punto LDF de consulta. No tiene EXECUTE del respaldo, BACKUP LOG directo, db_owner ni sysadmin.
- Permisos nuevos `DBA_LDF_CONSULTAR` y `DBA_LDF_RESPALDAR_LOG` asignados al rol `Administrador` existente. Se conservan admin UsuarioId 3, sus pertenencias y credenciales habituales.
- Configuración LDF ligada al servidor/base/GUID originales, umbrales 70/85 y directorio local de respaldo del motor comprobado mediante el FULL previo.
- Se añadieron localmente solo `LDF_DATABASE`, `LDF_EXPECTED_SERVER`, `LDF_ADMIN_USER` y `LDF_ADMIN_PASSWORD`. Todos los valores previos DB_*, SESSION_* y demás permanecen iguales. No se publican secretos.
- Se reinició únicamente el proceso web original del puerto 3000. El runtime nuevo confirmó directorio del proyecto, base `SecureFinanceERP` y login `securefinance_app`. No se cambió código de aplicación.

### Pruebas efectivas sobre la original

1. CHECKDB y CHECKCONSTRAINTS antes y después, sin diagnósticos de integridad; conciliación de stock sin diferencias.
2. Comparación SHA-256 con multiplicidades de las filas preexistentes de las **65 tablas originales**: ninguna modificada ni perdida. Incluye datos de negocio, usuarios, credenciales, roles, asignaciones y auditoría histórica. Solo se agregaron filas propias de LDF y de auditoría.
3. Las **190 definiciones SQL preexistentes** siguen exactamente iguales. El trigger `P3_DDL_CapturarEstructura` sigue habilitado; no fue modificado ni desactivado. Tampoco se modificaron la función de autorización, procedimientos previos o pertenencias a roles SQL/de servidor.
4. Tres firmas presentes y claves privadas retiradas. Identidad LDF y dos asociaciones de permisos al Administrador verificadas.
5. Conexiones SQL reales de aplicación y servicio: sin sysadmin, db_owner o BACKUP LOG directo; configuración y DMV directas rechazadas. Servicio con EXECUTE del respaldo y aplicación sin ese permiso. No se invocó el procedimiento de respaldo.
6. Lectura LDF real mediante su procedimiento firmado y el UsuarioId 3 del admin existente; tamaño físico y VLF coinciden con catálogo/DMV, historial consultado sin datos ficticios.
7. Consultas reales de los seis módulos anteriores usando `securefinance_app` y los permisos existentes de admin: cotizaciones, promociones, créditos, multibodega, compras y auditoría DDL. Se conservaron las reglas de negocio y no se crearon operaciones de negocio para probar producción. Los flujos de escritura con rollback ya habían pasado en la copia de ensayo.
8. `.env` comparado con su copia local previa: solo cuatro claves LDF nuevas; todos los valores anteriores conservados.
9. `/login` HTTP 200 después del reinicio y `/dba/ldf` anónimo redirige a `/login`, manteniendo la autenticación.
10. Auditoría posterior a `2026-11-04T06:22:01.559Z`: conservación de las 65 tablas y 190 módulos nuevamente aprobada; GUID y trigger sin cambios; conexión administrativa local y permisos de admin verificados.
11. Auditoría DDL original comprobada a `2026-11-04T06:24:39.333Z`: dos eventos CREATE_TABLE y tres CREATE_PROCEDURE del módulo, todos `EXACTO_EVENTDATA` con responsables registrados. Los comandos de consulta y respaldo conservan 8.338 y 12.410 bytes respectivamente, superiores al límite de 4.000 caracteres que se debía evitar.

Última muestra SQL de esa auditoría: LOG físico **136 MB**, uso lógico **55,127 %**, **6 VLF**, FULL/ONLINE, cadena inicializada y espera `LOG_BACKUP`. El archivo creció automáticamente conforme a su configuración previa de 64 MB; no se ejecutó ALTER DATABASE, shrink ni cambio de crecimiento. Se comprobaron aproximadamente 490.007 MB libres en el volumen. El uso cambia con la actividad normal.

Historial del módulo: cero solicitudes y cero respaldos LOG listados en la muestra. No se ejecutó **ningún BACKUP LOG de prueba**. La espera `LOG_BACKUP` se informa como dato operativo; no se intentó resolverla mediante una acción fuera del alcance autorizado.

La comprobación web autenticada continúa pendiente de que el propietario inicie sesión con su contraseña habitual en la ventana del ERP. No se leyó esa contraseña ni se sustituyó el login por una sesión artificial. Hasta completar ese paso, la confirmación de funcionamiento abarca la instalación, configuración, SQL y las consultas de los seis módulos, no su validación web autenticada final.

Evidencia local ignorada por Git: `.data/ldf-original-deployment.json`, `.data/ldf-original-postdeploy-audit.json`, hashes y definiciones previas, configuración previa y registros del runtime. Los archivos privados de credenciales no se publican. Durante este despliegue no se hicieron cambios de código ni publicaciones en GitHub; solo se actualiza este reporte como documentación necesaria.

Las secciones siguientes conservan la investigación, ensayo y plan anteriores al despliegue. Los estados pendientes de autorización de esas secciones son históricos y han sido superados por la autorización y ejecución descritas arriba.

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

Estado histórico previo al despliegue: el ensayo ya había sido aprobado. El PR #27 se fusionó en `36ff2a2a4cd2a88a0d840a98083f317d78167952`; el propietario autorizó después los ocho pasos. La sección de despliegue al principio de este reporte contiene el estado vigente y el pendiente web real.
