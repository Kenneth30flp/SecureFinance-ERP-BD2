# SecureFinance ERP — BD2

Fase 3: login web con EJS y Bootstrap 5, autenticación mediante procedimientos SQL, sesiones y dashboard mínimo de permisos. No incluye recuperación de contraseña, RBAC completo ni módulos de negocio.

## Equipo

- Kenneth: arquitectura BD, estructura común, usuarios, roles, permisos, autenticación, contraseñas y bitácora de accesos (incluido `sp_RegistrarAcceso`).
- Edward: tablas de negocio, inventario, ventas transaccionales y facturación.
- José: triggers DML, bitácora de transacciones, funciones, auditoría y reportes.
- Rubén: documento técnico, ERD final, matriz de pruebas, guía y evidencias.

La aplicación usa Node.js por decisión del equipo, sustituyendo la presentación C# descrita en el PDF. La seguridad y lógica de datos se mantendrán en SQL Server.

## Preparación

Requisitos: Node.js 24 o posterior, npm, SQL Server 2016 SP1 o posterior y SSMS. Habilitar TCP/IP en la instancia y conocer su puerto. Para una instancia con nombre, configurar su host y puerto TCP real en las variables, sin concatenar el nombre de instancia al host.

1. Ejecutar `npm ci` para instalar las versiones del lockfile.
2. En SSMS, ejecutar `database/01_CreateDatabase.sql` con una cuenta autorizada. No cambia una base existente.
3. Ejecutar `database/02_SecurityTables.sql` **una sola vez** sobre la base preparada. Es una instalación inicial transaccional; no elimina ni reemplaza tablas existentes. Una segunda ejecución fallará por objetos existentes.
4. Ejecutar `database/tests/SecurityTests.sql` con la cuenta de desarrollo. Debe imprimir `OK`; los datos se revierten. Los contadores IDENTITY pueden avanzar aunque se reviertan las filas.
5. Crear manualmente un `.env` local tomando `.env.example` como referencia. Completar las credenciales de una cuenta SQL dedicada y `SESSION_SECRET` con un secreto aleatorio de al menos 32 caracteres. El repositorio no incluye `.env` ni credenciales reales.
6. Ejecutar `npm run check`, `npm run check:db` y `npm start`.
7. Con Fase 2 instalada y permisos EXECUTE concedidos como se indica abajo, abrir `http://localhost:3000/login`. `/health` debe devolver `{"status":"ok","phase":3}`. El servidor valida la conexión SQL antes de escuchar; `/health` comprueba HTTP, no la disponibilidad continua de SQL.

Si el certificado local es autofirmado, se puede configurar `DB_TRUST_SERVER_CERTIFICATE=true` exclusivamente para desarrollo. Se conserva `DB_ENCRYPT=true`. La aplicación escucha inicialmente solo en `127.0.0.1`.

## Modelo inicial

| Tabla | Propósito |
|---|---|
| `dbo.Usuario` | Identidad, correo único, estado, hash de 64 bytes y sal única de 32 bytes. |
| `dbo.Rol` | Catálogo de roles con nombre único. |
| `dbo.Permiso` | Catálogo de códigos de permiso únicos. |
| `dbo.Usuario_Rol` | Relación muchos a muchos de usuarios y roles, sin duplicados. |
| `dbo.Rol_Permiso` | Relación muchos a muchos de roles y permisos, sin duplicados. |
| `dbo.Token_Recuperacion` | Hash del token, vigencia, consumo e invalidación; solo el esquema en esta fase. |
| `dbo.Bitacora_Acceso` | Resultado, usuario opcional, nombre intentado, fecha UTC, host, aplicación, principal SQL e IP disponibles. |

Los cuatro resultados permitidos son `EXITOSO`, `PASSWORD_INCORRECTA`, `USUARIO_INEXISTENTE` y `USUARIO_INACTIVO`. El usuario es nulo únicamente para el resultado inexistente. No se almacenan contraseñas ni tokens originales en la bitácora. No hay borrado en cascada. Las columnas de texto usan la collation de la base; esta determina sensibilidad a mayúsculas y acentos.

Los procedimientos generan sal con `CRYPT_GEN_RANDOM(32)` y hash con `HASHBYTES('SHA2_512', CONVERT(VARBINARY(256), @Password) + @Salt)`. Reciben `@Password NVARCHAR(MAX)` y validan entre 1 y 256 bytes antes de convertir, evitando truncamiento silencioso: máximo 128 unidades UTF-16. No recortan espacios ni normalizan contraseñas. Se concatenan los bytes UTF-16LE de la contraseña y los 32 bytes de sal. La misma sal se usa para calcular e insertar el hash; `UNIQUE` impide repetirla. El resultado SHA2_512 tiene [64 bytes según Microsoft](https://learn.microsoft.com/en-us/sql/t-sql/functions/hashbytes-transact-sql). Cualquier futuro cambio/restablecimiento deberá repetir exactamente esta fórmula con una sal nueva; todavía no se implementa. No hay hashing de contraseñas en Node.

`HOST_NAME()`, `APP_NAME()` y `SUSER_SNAME()` describen la conexión del backend. `CONNECTIONPROPERTY('client_net_address')` captura su IP cuando está disponible y puede devolver NULL. `IpClienteAplicacion` queda separada para el navegador. Estos metadatos no constituyen por sí solos prueba de identidad del usuario final.

## Cuenta SQL de aplicación

La aplicación usa el login SQL dedicado `securefinance_app`, mapeado a un usuario en `SecureFinanceERP` con permiso de conexión (`CONNECT`). No utilizar `sa` ni permisos directos sobre tablas.

Conceder manualmente `EXECUTE` únicamente sobre `dbo.sp_Login` y `dbo.sp_ObtenerPermisosUsuario`, preferiblemente mediante un rol de base de datos. No otorgar `sysadmin`, `db_owner`, `db_datareader`, `db_datawriter`, permisos DDL ni DML directo. La bitácora se escribe mediante la llamada interna del login a `sp_RegistrarAcceso`. No se crean cuentas ni contraseñas desde estos scripts.

## Estructura y siguientes fases

`server.js` configura Express, EJS, Bootstrap local y express-session. `authRoutes` define rutas, `authController` maneja HTTP y sesiones, `authService` ejecuta los SP con parámetros tipados y `authMiddleware` protege el dashboard. `src/config/database.js` comparte el pool existente con parámetros de entorno.

Las sesiones usan MemoryStore únicamente para desarrollo académico local y se pierden al reiniciar. No es una solución definitiva de producción. La cookie dura 30 minutos, usa `httpOnly` y `sameSite: 'lax'`. En desarrollo local HTTP no usa Secure; en producción `secure: 'auto'` lo activa cuando Express detecta HTTPS. El servidor actual escucha HTTP local y no confía en cabeceras de proxy. Un despliegue real requiere HTTPS, configurar explícitamente el proxy de confianza si corresponde y sustituir MemoryStore; [express-session documenta esta limitación](https://expressjs.com/en/resources/middleware/session/). `SESSION_SECRET` proviene de `.env`, con al menos 32 caracteres.

Las semillas de Fase 2 son exclusivamente académicas. No es necesario repetir su instalación para integrar Fase 3 sobre una base ya validada.

## Fase 3: rutas y verificación web

| Ruta | Comportamiento |
|---|---|
| `GET /` | Redirige a login o dashboard según la sesión. |
| `GET /login` | Muestra el formulario; con sesión redirige al dashboard. |
| `POST /login` | Recibe NombreUsuario y Password; ejecuta `dbo.sp_Login`. |
| `GET /dashboard` | Requiere sesión; muestra usuario y permisos. |
| `GET /logout` | Destruye la sesión, elimina la cookie y redirige a login. |
| `GET /health` | Devuelve estado HTTP y `phase: 3`. |

Después de EXITOSO, Node consulta `dbo.sp_ObtenerPermisosUsuario`, regenera el identificador de sesión y guarda únicamente `usuarioId`, `nombreUsuario`, `correo`, `debeCambiarPassword` y los códigos de `permisos` en `req.session.usuario`. Guarda la sesión antes de redirigir. Si falla la consulta de permisos, no se crea una sesión autenticada. El hashing y la comparación ocurren exclusivamente en SQL Server; Node no consulta hash ni sal, no transforma la contraseña y no construye SQL concatenado. Los permisos son una instantánea del login; los cambios posteriores se reflejan al iniciar sesión nuevamente.

Con Fase 2 ya instalada, probar en este orden:

1. Confirmar las dos concesiones EXECUTE con el administrador SQL. Conservar el `.env` local existente y la cuenta `securefinance_app`.
2. Ejecutar `npm run check`, `npm test` y `npm start` (en PowerShell puede usarse `npm.cmd`). `npm test` usa SQL simulado; no verifica la instancia real.
3. Abrir `/health`: esperar `{"status":"ok","phase":3}`. En ventana privada abrir `/` y `/dashboard`: ambos deben redirigir a `/login`.
4. Abrir `/login`: formulario con usuario, contraseña y botón Ingresar.
5. Probar `admin_demo` con una contraseña incorrecta y luego `no_existe_demo`: ambos deben mostrar **Usuario o contraseña incorrectos.**, permanecer en login y no crear sesión.
6. Ingresar con **admin_demo / Demo_Academica_2026!**: esperar `/dashboard`, nombre del usuario y los permisos `USUARIOS_ADMINISTRAR`, `VENTAS_REGISTRAR`, `AUDITORIA_CONSULTAR`.
7. Con sesión, visitar `/` o `/login`: esperar redirección al dashboard.
8. Pulsar **Cerrar sesión**: esperar `/login`; visitar nuevamente `/dashboard`: debe redirigir a `/login`.

Para un usuario inactivo se muestra **El usuario se encuentra inactivo.** Los errores técnicos muestran un mensaje genérico, sin detalles SQL. El indicador `DebeCambiarPassword` se conserva en sesión; el cambio de contraseña queda fuera de esta fase. Las pruebas HTTP locales verifican también escape de datos, cookies y rechazo de la sesión anterior al cerrar sesión. La validación real del login y de su bitácora debe realizarse en la instancia del equipo.

## Fase 2: instalación sobre la Fase 1 existente

En SSMS, con la cuenta de desarrollo autorizada, ejecutar en este orden:

1. `database/03_SecurityStoredProcedures.sql`: crea o actualiza los cuatro SP, sin modificar tablas.
2. `database/04_SecuritySeedData.sql`: imprime `OK: semillas DEMO disponibles; datos existentes conservados.` En la primera ejecución también devuelve `Codigo = 0`, `Resultado = REGISTRADO` y el ID creado.
3. `database/tests/SecurityTests.sql`: pruebas originales de Fase 1; imprime `OK`.
4. `database/tests/AuthenticationTests.sql`: pruebas de Fase 2; imprime `OK: Fase 2, ... Datos revertidos.`

No volver a ejecutar `02` ni el unificado sobre las tablas ya instaladas. Para una **instalación nueva**, ejecutar `01`, `02`, `03`, `04`, o alternativamente solo `database/SecureFinanceERP_Full.sql`, que contiene esos cuatro archivos completos y en orden. El unificado requiere detenerse ante errores de instalación; no es una migración idempotente. Después ejecutar ambos archivos de pruebas.

Los scripts `03` y `04` pueden repetirse. El seed crea los roles Administrador, Cajero y Auditor y asigna estos permisos:

| Rol | Permisos |
|---|---|
| Administrador | USUARIOS_ADMINISTRAR, VENTAS_REGISTRAR, AUDITORIA_CONSULTAR |
| Cajero | VENTAS_REGISTRAR |
| Auditor | AUDITORIA_CONSULTAR |

Usuario **DEMO**: `admin_demo`, correo `admin.demo@example.invalid`, contraseña temporal pública **`Demo_Academica_2026!`**. Se crea mediante `sp_RegistrarUsuario` con `DebeCambiarPassword = 1`. Ese indicador aún no ejecuta ni obliga el cambio mediante una interfaz: el flujo se implementará posteriormente. Reejecutar el seed no cambia la contraseña, estado ni indicador de un usuario existente; tampoco reactiva roles o permisos. Si los datos ya fueron modificados, las expectativas DEMO pueden variar.

## Contrato de los procedimientos

`sp_RegistrarUsuario` recibe NombreUsuario, Correo, Password y NombreCompleto (obligatorio en el modelo), y permite obtener `@UsuarioId OUTPUT`. Devuelve una fila con `Codigo`, `Resultado`, `UsuarioId`: 0/REGISTRADO, 10/DATOS_INVALIDOS, 11/USUARIO_O_CORREO_EXISTENTE o 12/CONFLICTO_UNICIDAD (incluye carreras concurrentes). El valor RETURN repite Codigo. Los errores técnicos se propagan con THROW. Las validaciones de correo y nombres respetan el modelo actual: no vacíos, longitudes máximas y unicidad según collation; no se agrega un validador de formato de correo.

`sp_Login` devuelve exactamente una fila y siete columnas: `Codigo`, `Resultado`, `UsuarioId`, `NombreUsuario`, `Correo`, `Activo`, `DebeCambiarPassword`. RETURN repite Codigo. En fallos, todos los datos de usuario son NULL.

| Codigo | Resultado |
|---|---|
| 0 | EXITOSO |
| 1 | USUARIO_INEXISTENTE |
| 2 | USUARIO_INACTIVO |
| 3 | PASSWORD_INCORRECTA |

Nunca devuelve PasswordHash, Salt, contraseña ni token. La capa web usa el mismo mensaje para usuario inexistente y contraseña incorrecta; informa por separado si el usuario está inactivo. Password NULL, vacío o demasiado largo se considera incorrecto para un usuario activo. Nombre NULL o demasiado largo se considera inexistente.

`sp_RegistrarAcceso` es un procedimiento interno sin result set; registra fecha UTC y metadatos de conexión sin exigir VIEW SERVER STATE. Un nombre intentado que exceda la columna existente se limita a NVARCHAR(50); NULL se registra como cadena vacía. La IP SQL puede ser NULL en conexiones locales y no es la IP del navegador. El login registra exactamente un intento antes de devolver su resultado; un error al escribir la bitácora impide devolver éxito. **Llamar login en autocommit**: una transacción externa que luego haga rollback también revierte la bitácora. Las pruebas aprovechan este comportamiento para limpiar sus datos.

`sp_ObtenerPermisosUsuario @UsuarioId` devuelve `PermisoId` y `Codigo` únicos, solo para usuario, roles y permisos activos. Sin asignaciones activas devuelve cero filas; un mismo permiso concedido por dos roles aparece una vez.

Para pruebas de SP con la cuenta SQL de aplicación, un administrador puede conceder únicamente EXECUTE sobre `dbo.sp_Login` y `dbo.sp_ObtenerPermisosUsuario` mediante un rol de base de datos. No conceder acceso directo a tablas ni EXECUTE sobre `sp_RegistrarAcceso`: la cadena de propiedad dbo permite su llamada interna desde login. El registro administrativo se prueba con la cuenta de desarrollo; su exposición a Node se decidirá posteriormente. Estos scripts no alteran cuentas SQL ni concesiones existentes.

## Pruebas manuales en SSMS

Ejecutar con la cuenta de desarrollo después de instalar las semillas:

```sql
USE SecureFinanceERP;
GO
-- Esperado: 0 / EXITOSO, datos seguros, DebeCambiarPassword = 1.
EXEC dbo.sp_Login @NombreUsuario = N'admin_demo', @Password = N'Demo_Academica_2026!';
-- Esperado: 3 / PASSWORD_INCORRECTA, datos de usuario NULL.
EXEC dbo.sp_Login @NombreUsuario = N'admin_demo', @Password = N'Incorrecta';
-- Esperado: 1 / USUARIO_INEXISTENTE, datos de usuario NULL.
EXEC dbo.sp_Login @NombreUsuario = N'no_existe_demo', @Password = N'Incorrecta';

-- Esperado: los tres intentos anteriores y sus metadatos; no contiene secretos.
SELECT TOP (20) BitacoraAccesoId, UsuarioId, NombreUsuarioIntentado,
       Resultado, FechaHora, HostName, AppName, UsuarioSQL, IpConexionSQL
FROM dbo.Bitacora_Acceso ORDER BY BitacoraAccesoId DESC;

-- Esperado: los tres permisos del Administrador, sin duplicados.
DECLARE @Id INT = (SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario = N'admin_demo');
EXEC dbo.sp_ObtenerPermisosUsuario @UsuarioId = @Id;
GO
-- Prueba reversible de usuario inactivo: 2 / USUARIO_INACTIVO.
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE dbo.Usuario SET Activo = 0 WHERE NombreUsuario = N'admin_demo';
    EXEC dbo.sp_Login @NombreUsuario = N'admin_demo', @Password = N'Demo_Academica_2026!';
    -- El intento se puede consultar aquí, antes del rollback.
    SELECT TOP (1) Resultado, FechaHora FROM dbo.Bitacora_Acceso
    WHERE NombreUsuarioIntentado = N'admin_demo' ORDER BY BitacoraAccesoId DESC;
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
```

Para comprobar idempotencia, ejecutar `04` nuevamente: no deben duplicarse usuarios, roles, permisos ni asignaciones. `AuthenticationTests.sql` verifica además registro, fórmula binaria con Unicode y espacios, longitud de hash, sal presente y distinta para la misma contraseña, rechazo de duplicados y contraseñas largas, los cuatro accesos, contrato de columnas y permisos sin duplicados ni entidades inactivas. Ambas suites hacen rollback; los contadores IDENTITY pueden avanzar.

## Validación

- `npm run check`: sintaxis de los archivos JavaScript de aplicación y pruebas.
- `npm test`: pruebas de servicio y HTTP con SQL simulado, sin conexión a SQL Server.
- `npm ls --depth=0`: dependencias instaladas.
- `npm audit`: estado de vulnerabilidades reportadas por npm.
- `npm run check:db`: conexión real usando exclusivamente la configuración local.
- `database/tests/SecurityTests.sql`: integración SQL manual, con rollback de datos temporales.
- `database/tests/AuthenticationTests.sql`: integración SQL de Fase 2, con rollback.

Las revisiones estáticas no sustituyen ejecutar los scripts contra la instancia del equipo. La conexión y las pruebas SQL requieren que un integrante configure su entorno real.
