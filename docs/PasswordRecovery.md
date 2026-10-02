# Recuperación y cambio de contraseña

## Arquitectura y compatibilidad

Las pantallas EJS usan el portal corporativo oscuro existente. `passwordRoutes` aplica sesión, CSRF y cabeceras; `passwordController` valida los formularios y controla la demostración; `passwordService` genera tokens con `crypto.randomBytes(32)`, calcula SHA-512 sobre su representación hexadecimal UTF-8 y llama exclusivamente a procedimientos almacenados mediante parámetros tipados.

No se crean tablas ni TYPEs. Se reutilizan `dbo.Usuario` y `dbo.Token_Recuperacion`. Los nuevos procedimientos conservan exactamente la fórmula existente:

```sql
DECLARE @Salt VARBINARY(32) = CRYPT_GEN_RANDOM(32);
HASHBYTES('SHA2_512', CONVERT(VARBINARY(256), @Password) + @Salt)
```

Las nuevas contraseñas admiten 8 a 128 unidades UTF-16; SQL verifica entre 16 y 256 bytes, sin truncar. No se normalizan ni recortan: espacios y Unicode forman parte de la contraseña. Se rechazan cadenas compuestas únicamente por espacios. La contraseña actual mantiene el límite del login existente, de 1 a 128 unidades UTF-16.

## Aplicar a SecureFinanceERP existente

Ejecutar en SSMS o sqlcmd con una cuenta administradora, sobre la instancia que contiene SecureFinanceERP, deteniendo la ejecución ante errores:

1. Si todavía no se aplicó el módulo anterior, ejecutar `database/11_UserAdministration.sql`.
2. Ejecutar `database/12_PasswordRecovery.sql`.
3. Ejecutar `database/10_AppPermissions.sql` actualizado.
4. Reiniciar la aplicación con `npm.cmd start`.

Ejemplo con autenticación Windows para la instancia local predeterminada:

```powershell
sqlcmd -S localhost -E -C -b -f 65001 -i database/12_PasswordRecovery.sql
sqlcmd -S localhost -E -C -b -f 65001 -i database/10_AppPermissions.sql
```

El login de servidor `securefinance_app` debe existir previamente. El script concede solamente EXECUTE en `sp_SolicitarRecuperacionPassword`, `sp_ValidarTokenRecuperacion`, `sp_RestablecerPassword` y `sp_CambiarPassword`, conservando las concesiones previas. No concede acceso directo a tablas.

El instalador `database/SecureFinanceERP_Full.sql` ya incluye ambos módulos antes del bloque de permisos. Usarlo exclusivamente para una instalación nueva.

## Flujos

- GET/POST `/recuperar-password`: recibe usuario o correo. La respuesta es siempre «Si la cuenta existe, se generó una solicitud de recuperación.», incluso ante cuenta inexistente, inactiva, identificador ambiguo o error técnico.
- GET/POST `/restablecer-password`: el GET verifica un token sin consumirlo. El POST valida confirmación y consume el token dentro de la misma transacción que cambia la contraseña. Token inexistente, expirado, usado o invalidado produce el mismo mensaje.
- GET/POST `/cambiar-password`: exige sesión y contraseña actual, comprobada por SQL. Disponible tanto para el cambio obligatorio como para cambios voluntarios desde el enlace del sidebar.

Cada formulario tiene CSRF específico almacenado en la sesión y comparación con `timingSafeEqual`. Las páginas usan `Cache-Control: no-store`, `Referrer-Policy: no-referrer` y `X-Robots-Tag: noindex, nofollow`. Los passwords nunca vuelven a poblar los formularios.

Los tokens expiran a los 15 minutos. Una nueva solicitud invalida las anteriores de esa cuenta. Un cambio por recuperación marca `FechaUso`, invalida el token utilizado e invalida los restantes. Un cambio autenticado invalida todos los tokens pendientes. Todas las operaciones que escriben bloquean primero la cuenta y después sus tokens para impedir el consumo simultáneo.

## Demostración académica

Con `NODE_ENV` diferente de `production`, la pantalla puede mostrar un enlace relativo `/restablecer-password?token=...` para la cuenta existente. El navegador lo resuelve contra el origen actual, por ejemplo `http://localhost:3000`. Esta es una excepción explícita de demostración que revela la disponibilidad del enlace únicamente en desarrollo. El texto de confirmación sigue siendo genérico.

Con `NODE_ENV=production`, no se devuelve ni imprime el token ni se muestra un enlace. No existe integración SMTP; para entregar recuperación en producción deberá incorporarse un proveedor de correo que envíe el enlace al destinatario verificado. El token plano existe únicamente de manera transitoria en memoria y en el navegador durante la demostración/restablecimiento; SQL recibe y guarda exclusivamente su hash. No se guarda el token plano en la sesión.

## Cambio obligatorio y sesiones

Cuando el login devuelve `DebeCambiarPassword=1`, la aplicación redirige a `/cambiar-password`. El middleware compartido impide entrar a los módulos protegidos por GET o POST, incluso escribiendo sus URLs directamente. Solo la pantalla de cambio y el cierre de sesión permanecen disponibles para completar o abandonar ese acceso.

Después del cambio autenticado, SQL deja `DebeCambiarPassword=0`, el backend renueva el identificador de sesión y elimina los CSRF anteriores; la sesión nueva conserva el usuario y permite el dashboard. Después de recuperación, se requiere iniciar sesión con la nueva contraseña. Como en la arquitectura previa, no se implementa revocación global de otras sesiones ya abiertas: el MemoryStore existente no tiene un registro por usuario para ese fin.

No se alteran la facturación ni los procedimientos de auditoría. No se insertan cambios de credenciales en la auditoría DML para evitar registrar PasswordHash o Salt; los intentos de login continúan pasando por la bitácora existente.

## Pruebas

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run test:sql:password -- localhost
git diff --check
```

Las pruebas Node cubren los formularios, mensajes genéricos de producción, demostración, token inválido, errores seguros, longitudes y confirmación, CSRF, hash de token, cambio obligatorio, renovación de sesión y compatibilidad con los módulos anteriores.

El runner SQL compartido crea y elimina exclusivamente una base temporal `SecureFinanceERP_UserRolesTest_*`; no usa `.env` ni modifica la base SecureFinanceERP. Instala el script completo y ejecuta las suites existentes, Usuarios y Roles y `PasswordRecoveryTests.sql`. Verifica Salt/hash nuevos, fórmula exacta, flags, login anterior/nuevo, expiración, uso único, rollback, mínimo privilegio y concurrencia de recuperación y administradores.
