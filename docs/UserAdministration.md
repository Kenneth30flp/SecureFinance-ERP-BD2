# Usuarios y roles

Rama: feature/admin-user-roles. No requiere cambios en tablas de seguridad ni en login.

## Instalacion

En una base existente con todos los modulos previos instalados, ejecutar con una cuenta administradora:

1. database/11_UserAdministration.sql
2. database/12_PasswordRecovery.sql (nuevo modulo de acceso, requerido por las concesiones actualizadas)
3. database/10_AppPermissions.sql

El procedimiento usa dbo.Bitacora_Transacciones, creada por database/07_AuditCore.sql.
Para instalaciones nuevas usar database/SecureFinanceERP_Full.sql, que incluye el modulo antes de conceder permisos. No ejecutar el instalador completo sobre una base existente.
La aplicacion mantiene securefinance_app con EXECUTE en cuatro procedimientos y EXECUTE/REFERENCES en dbo.TipoRolUsuario; no se conceden permisos directos a tablas.

## Comportamiento

GET /usuarios muestra todos los usuarios y los roles activos. GET /usuarios/:id/roles obtiene las asignaciones activas. POST /usuarios/:id/roles recibe JSON { "Roles": [1, 2] } y X-CSRF-Token de la pantalla. Un arreglo vacio quita todos los roles activos editables, salvo la proteccion del ultimo administrador.

El sidebar depende de USUARIOS_ADMINISTRAR en la sesion. Todos los endpoints requieren sesion, ese permiso y su revalidacion actual en SQL Server mediante sp_ObtenerPermisosUsuario. El POST comprueba tambien el actor activo y su permiso dentro de la transaccion SQL. El actor se obtiene exclusivamente de la sesion.

La lista de opciones proviene de dbo.Rol; Node y EJS no contienen nombres ni IDs de roles fijos. Las asignaciones de roles inactivos se conservan y no se editan, porque no aparecen como opciones. El nombre Administrador se usa solamente en SQL para proteger la regla requerida.

Las sesiones de los otros modulos mantienen el comportamiento existente: sus permisos se cargan al iniciar sesion. Los cambios se reflejan alli en el siguiente inicio de sesion. Este modulo revalida cada solicitud incluso con una sesion previa al cambio.

sp_ActualizarRolesUsuario valida usuario, actor, roles activos y duplicados; usa XACT_ABORT, TRY/CATCH, transaccion y sp_getapplock exclusivo para serializar cambios concurrentes. Los locks UPDLOCK/HOLDLOCK protegen las filas relevantes. Una segunda revocacion concurrente no puede dejar sin administrador activo al sistema.

La auditoria se inserta en la misma transaccion en dbo.Bitacora_Transacciones, con TablaAfectada Usuario_Rol y Operacion UPDATE. IdentificadorRegistro incluye UsuarioId y ActorUsuarioId; ValorAnterior/ValorNuevo contienen solo RolId en JSON. No se modifican triggers ni consultas de auditoria existentes. Guardar sin cambios no genera un evento adicional. No se incluyen hashes, salts, contrasenas ni secretos.

## Pruebas

- npm run check
- npm test: HTTP con servicios simulados, validaciones, CSRF, permisos, contrato TVP y sincronizacion de scripts; conserva pruebas anteriores.
- npm run test:sql:usuarios -- localhost: SQL real con autenticacion Windows y sqlcmd. Crea y elimina exclusivamente una base temporal SecureFinanceERP_UserRolesTest_*. Instala el script completo y ejecuta SecurityTests, AuthenticationTests, TransactionTests, AuditTests y UserAdministrationTests, ademas de revocaciones concurrentes. No usa .env ni modifica SecureFinanceERP.

En PowerShell con npm.ps1 bloqueado, usar npm.cmd en los mismos comandos.
