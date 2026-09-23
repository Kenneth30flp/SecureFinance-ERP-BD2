# SecureFinance ERP — BD2

Fase 1: estructura Node.js y modelo SQL de seguridad de Kenneth. Todavía no incluye procedimientos almacenados, login, recuperación funcional, páginas completas ni RBAC en Node.

## Equipo

- Kenneth: arquitectura BD, estructura común, usuarios, roles, permisos, autenticación, contraseñas y bitácora de accesos (incluido `sp_RegistrarAcceso`).
- Edward: tablas de negocio, inventario, ventas transaccionales y facturación.
- José: triggers DML, bitácora de transacciones, funciones, auditoría y reportes.
- Rubén: documento técnico, ERD final, matriz de pruebas, guía y evidencias.

La aplicación usa Node.js por decisión del equipo, sustituyendo la presentación C# descrita en el PDF. La seguridad y lógica de datos se mantendrán en SQL Server.

## Preparación

Requisitos: Node.js 24 o posterior, npm, SQL Server y SSMS. Habilitar TCP/IP en la instancia y conocer su puerto. Para una instancia con nombre, configurar su host y puerto TCP real en las variables, sin concatenar el nombre de instancia al host.

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

Los futuros procedimientos generarán sal con `CRYPT_GEN_RANDOM(32)` y hash con `HASHBYTES('SHA2_512', CONVERT(VARBINARY(256), @Password) + @Salt)`, usando `@Password NVARCHAR(128)` validada antes de convertir. La misma sal debe usarse para calcular e insertar el hash: el DEFAULT no calcula el hash. Cada cambio/restablecimiento generará una nueva sal en SQL. No hay hashing de contraseñas en Node.

`HOST_NAME()`, `APP_NAME()` y `SUSER_SNAME()` describen la conexión del backend. `CONNECTIONPROPERTY('client_net_address')` captura su IP cuando está disponible y puede devolver NULL. `IpClienteAplicacion` queda separada para el navegador. Estos metadatos no constituyen por sí solos prueba de identidad del usuario final.

## Cuenta SQL de aplicación

El administrador deberá crear un login SQL dedicado (por ejemplo `securefinance_app`), mapear un usuario en `SecureFinanceERP` y permitir conexión a la base (`CONNECT`). En Fase 1 solo se abre la conexión: no necesita permisos sobre tablas.

Cuando existan los procedimientos, conceder `EXECUTE` únicamente sobre los SP necesarios, mediante un rol de base de datos. No otorgar `sysadmin`, `db_owner`, `db_datareader`, `db_datawriter`, permisos DDL ni DML directo. La bitácora se escribirá mediante el SP de Kenneth y la cuenta no tendrá UPDATE/DELETE sobre ella; la restricción no vuelve inmutables los datos frente al administrador de SQL Server. No se crean cuentas ni contraseñas desde estos scripts.

## Estructura y siguientes fases

`server.js` configura Express, EJS, Bootstrap local y express-session. `src/config/database.js` comparte un pool reutilizable con parámetros de entorno. Las carpetas de controladores, rutas, middleware, servicios, vistas y recursos quedan reservadas con `.gitkeep`; no contienen funcionalidades simuladas.

Las sesiones usan MemoryStore únicamente para desarrollo académico local y se pierden al reiniciar. No se crea `SesionUsuario`. Antes de un despliegue real se deberá elegir un almacén apropiado y configurar HTTPS; [express-session documenta esta limitación](https://expressjs.com/en/resources/middleware/session/).

No se necesitan semillas permanentes para validar el modelo: las pruebas SQL usan datos temporales. `03_SecurityStoredProcedures.sql`, `04_SecuritySeedData.sql` y `SecureFinanceERP_Full.sql` se incorporarán en fases posteriores. No se presentan archivos vacíos como entregables completos.

## Validación

- `npm run check`: sintaxis de los dos archivos JavaScript.
- `npm ls --depth=0`: dependencias instaladas.
- `npm audit`: estado de vulnerabilidades reportadas por npm.
- `npm run check:db`: conexión real usando exclusivamente la configuración local.
- `database/tests/SecurityTests.sql`: integración SQL manual, con rollback de datos temporales.

Las revisiones estáticas no sustituyen ejecutar los scripts contra la instancia del equipo. La conexión y las pruebas SQL requieren que un integrante configure su entorno real.
