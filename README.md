# SecureFinance ERP — BD2

Fases 1 y 2: estructura Node.js, modelo SQL de seguridad y autenticación mediante procedimientos almacenados. La integración del login con Node.js corresponde a la Fase 3; no incluye recuperación funcional, páginas completas ni RBAC en Node.

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
7. Abrir `http://localhost:3000` y `/health`. Este último debe devolver `{"status":"ok","phase":1}`. El servidor valida la conexión SQL antes de escuchar; `/health` comprueba HTTP, no la disponibilidad continua de SQL.

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

El administrador deberá crear un login SQL dedicado (por ejemplo `securefinance_app`), mapear un usuario en `SecureFinanceERP` y permitir conexión a la base (`CONNECT`). En Fase 1 solo se abre la conexión: no necesita permisos sobre tablas.

Cuando existan los procedimientos, conceder `EXECUTE` únicamente sobre los SP necesarios, mediante un rol de base de datos. No otorgar `sysadmin`, `db_owner`, `db_datareader`, `db_datawriter`, permisos DDL ni DML directo. La bitácora se escribirá mediante el SP de Kenneth y la cuenta no tendrá UPDATE/DELETE sobre ella; la restricción no vuelve inmutables los datos frente al administrador de SQL Server. No se crean cuentas ni contraseñas desde estos scripts.

## Estructura y siguientes fases

`server.js` configura Express, EJS, Bootstrap local y express-session. `src/config/database.js` comparte un pool reutilizable con parámetros de entorno. Las carpetas de controladores, rutas, middleware, servicios, vistas y recursos quedan reservadas con `.gitkeep`; no contienen funcionalidades simuladas.

Las sesiones usan MemoryStore únicamente para desarrollo académico local y se pierden al reiniciar. No se crea `SesionUsuario`. Antes de un despliegue real se deberá elegir un almacén apropiado y configurar HTTPS; [express-session documenta esta limitación](https://expressjs.com/en/resources/middleware/session/).

Las semillas de Fase 2 son exclusivamente académicas. Las pruebas automatizadas SQL usan datos temporales y no dependen de esas semillas. Node.js permanece como en Fase 1, incluido `/health` con `phase: 1`, porque la integración corresponde a Fase 3.

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

Nunca devuelve PasswordHash, Salt, contraseña ni token. La futura capa web debe presentar un mensaje genérico ante rechazo, sin exponer la distinción de usuario inexistente/inactivo al público. Password NULL, vacío o demasiado largo se considera incorrecto para un usuario activo. Nombre NULL o demasiado largo se considera inexistente.

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

- `npm run check`: sintaxis de los dos archivos JavaScript.
- `npm ls --depth=0`: dependencias instaladas.
- `npm audit`: estado de vulnerabilidades reportadas por npm.
- `npm run check:db`: conexión real usando exclusivamente la configuración local.
- `database/tests/SecurityTests.sql`: integración SQL manual, con rollback de datos temporales.
- `database/tests/AuthenticationTests.sql`: integración SQL de Fase 2, con rollback.

Las revisiones estáticas no sustituyen ejecutar los scripts contra la instancia del equipo. La conexión y las pruebas SQL requieren que un integrante configure su entorno real.
