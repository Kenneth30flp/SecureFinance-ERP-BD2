# SecureFinance ERP — BD2

Proyecto académico con Node.js, Express, EJS, Bootstrap y SQL Server. Incluye autenticación segura mediante SHA2_512 + Salt, RBAC, bitácora de accesos, clientes, productos, facturación multiproducto, transacciones ACID, control de stock, movimiento de caja, auditoría DML mediante triggers, histórico de ventas, interfaz web corporativa y permisos mínimos SQL.

La recuperación y el cambio de contraseña completos **no están implementados**. Existen el esquema `Token_Recuperacion` y el indicador `DebeCambiarPassword`, pero este indicador no obliga a cambiar la contraseña mediante una interfaz.

## Equipo

- Kenneth: arquitectura BD, estructura común, usuarios, roles, permisos, autenticación, contraseñas y bitácora de accesos.
- Edward: tablas de negocio, inventario, ventas transaccionales y facturación.
- José: triggers DML, bitácora de transacciones, funciones, auditoría y reportes.
- Rubén: documento técnico, ERD final, matriz de pruebas, guía y evidencias.

La aplicación usa Node.js por decisión del equipo, sustituyendo la presentación C# descrita en el PDF. La seguridad y la lógica de datos residen en SQL Server.

## Requisitos y configuración

Node.js 24 o posterior, npm, SQL Server 2016 SP1 o posterior y SSMS. Para Node, habilitar TCP/IP y configurar el host y el puerto TCP real de la instancia; no concatenar el nombre de instancia al host.

Crear el archivo local `.env` tomando `.env.example` como referencia. Las credenciales SQL y `SESSION_SECRET` van exclusivamente en `.env`; generar un secreto de sesión aleatorio de al menos 32 caracteres. Configurar servidor, puerto, base `SecureFinanceERP` y cuenta SQL dedicada. No usar `sa` desde Node ni publicar `.env`, contraseñas personales o tokens.

Mantener `DB_ENCRYPT=true`. Para un certificado autofirmado, `DB_TRUST_SERVER_CERTIFICATE=true` es una opción exclusivamente de desarrollo local. La aplicación escucha inicialmente en `127.0.0.1:3000`.

## Instalación final

Ambas opciones son para una **instalación nueva**. El Full no es una migración ni debe ejecutarse sobre una instalación con las tablas ya creadas. Ejecutar los scripts con una cuenta administradora autorizada y detenerse ante cualquier error SQL; no continuar los lotes después de un error. En `sqlcmd`, usar `-b` para detenerse ante errores. Las fechas se almacenan en UTC donde aplica.

### Opción A — instalación completa nueva

1. Ejecutar `npm ci`.
2. Crear/configurar manualmente el login SQL externo `securefinance_app`, o preparar una cuenta equivalente según el entorno. Ningún instalador crea logins ni passwords. Los scripts de permisos suministrados usan específicamente `securefinance_app`; una cuenta equivalente requiere que el administrador configure su usuario y los mismos permisos mínimos y ajuste `DB_USER` localmente.
3. Ejecutar `database/SecureFinanceERP_Full.sql` en SSMS o sqlcmd. Incluye los diez bloques de la opción B, con el contenido de sus fuentes modulares y sin pruebas.
4. Si el login fue creado después del Full, ejecutar `database/10_AppPermissions.sql`.
5. Configurar `.env` según la sección anterior.
6. Ejecutar `npm run check`.
7. Ejecutar `npm test`.
8. Ejecutar `npm run check:db` para verificar la conexión real.
9. Ejecutar `npm start` y abrir `http://localhost:3000/login`.

Si falta el login, el Full muestra una advertencia: la base fue instalada, el administrador debe configurar el login y ejecutar después `10_AppPermissions.sql`. Esa ausencia no aborta la instalación.

### Opción B — instalación modular

Instalar dependencias y preparar el login como en la opción A. Ejecutar estos archivos en este orden:

1. `database/01_CreateDatabase.sql`
2. `database/02_SecurityTables.sql`
3. `database/03_SecurityStoredProcedures.sql`
4. `database/04_SecuritySeedData.sql`
5. `database/05_BusinessTables.sql`
6. `database/05_BusinessSeedData.sql`
7. `database/06_TransactionProcedures.sql`
8. `database/07_AuditCore.sql`
9. `database/08_AuditTriggers.sql`
10. `database/10_AppPermissions.sql`

Continuar con `.env`, las verificaciones y el arranque de los pasos 5–9 de la opción A. No ejecutar además el Full.

`07_AuditCore.sql` requiere `Factura`, `Cliente` y `Usuario`. Los triggers requieren `Producto`, `Factura` y `Bitacora_Transacciones`; por eso auditoría va después de negocio y los triggers después del núcleo de auditoría.

`07_TransactionPermissions.sql` y `09_AuditPermissions.sql` se conservan como scripts parciales/históricos. Para la instalación final se recomienda `10_AppPermissions.sql`, que reúne todas las concesiones necesarias.

## Cuenta SQL y permisos mínimos

`10_AppPermissions.sql` usa `SecureFinanceERP`, comprueba `SUSER_ID(N'securefinance_app')` y crea el usuario de base con `CREATE USER [securefinance_app] FOR LOGIN [securefinance_app]` solo si el login existe y el usuario falta. Si el usuario ya existe, aplica las concesiones. El administrador debe ejecutarlo con visibilidad del login y verificar que un usuario preexistente esté correctamente mapeado.

| Área | Permisos concedidos |
|---|---|
| Autenticación | `EXECUTE` sobre `dbo.sp_Login` y `dbo.sp_ObtenerPermisosUsuario` |
| Ventas | `EXECUTE` sobre `dbo.sp_ListarClientes`, `dbo.sp_ListarProductosDisponibles` y `dbo.sp_ProcesarVentaTransaccional` |
| TVP | `EXECUTE` y `REFERENCES` sobre `TYPE::dbo.TipoDetalleVenta` |
| Auditoría | `EXECUTE` sobre `dbo.sp_ConsultarBitacoraAcceso`, `dbo.sp_ConsultarAuditoriaTransacciones` y `dbo.sp_ConsultarHistoricoVentas` |

El script imprime `OK` al aplicar los permisos y puede repetirse. No concede `sysadmin`, `db_owner`, `db_datareader`, `db_datawriter`, `CONTROL`, permisos globales SELECT/INSERT/UPDATE/DELETE ni acceso directo a tablas. No concede ejecución a los procedimientos administrativos o internos: las llamadas internas usan la cadena de propiedad `dbo`. No revoca privilegios previos; el administrador debe comprobar que la cuenta dedicada no herede permisos adicionales y que pueda conectarse a la base.

## Modelo y seguridad

Seguridad: `Usuario`, `Rol`, `Permiso`, `Usuario_Rol`, `Rol_Permiso`, `Token_Recuperacion` y `Bitacora_Acceso`. Negocio: `Cliente`, `Producto`, `Factura`, `DetalleFactura`, `MovimientoCaja` y el tipo de tabla `TipoDetalleVenta`. Auditoría DML: `Bitacora_Transacciones`.

SQL genera una sal única de 32 bytes con `CRYPT_GEN_RANDOM(32)` y calcula `HASHBYTES('SHA2_512', CONVERT(VARBINARY(256), @Password) + @Salt)`, con resultado de 64 bytes. Los procedimientos validan entre 1 y 256 bytes de contraseña antes de convertir; no recortan espacios ni normalizan. Node no calcula hashes ni consulta hash o sal. Usa procedimientos con parámetros tipados.

`sp_Login` registra cada intento mediante `sp_RegistrarAcceso`. Los resultados son `EXITOSO`, `PASSWORD_INCORRECTA`, `USUARIO_INEXISTENTE` y `USUARIO_INACTIVO`. No devuelve hash, sal ni contraseña. La bitácora contiene fecha UTC y metadatos de conexión; la IP SQL describe la conexión del backend, no necesariamente el navegador. Ejecutar login en autocommit: un rollback externo también revertiría su bitácora.

Tras autenticar, Node consulta `sp_ObtenerPermisosUsuario`, regenera la sesión y guarda la identidad y los códigos de permisos. Los cambios RBAC se reflejan al volver a iniciar sesión. Las sesiones usan **MemoryStore solo para desarrollo académico**, se pierden al reiniciar y requieren reemplazo para producción. La cookie dura 30 minutos y usa `httpOnly` y `sameSite: 'lax'`; un despliegue real requiere HTTPS y configuración explícita del proxy de confianza si corresponde.

## Semillas DEMO

Las credenciales DEMO son exclusivamente académicas: **`admin_demo` / `Demo_Academica_2026!`**, correo `admin.demo@example.invalid`. Se crea con `DebeCambiarPassword = 1`, sin flujo completo de cambio de contraseña.

| Rol | Permisos RBAC |
|---|---|
| Administrador | `USUARIOS_ADMINISTRAR`, `VENTAS_REGISTRAR`, `AUDITORIA_CONSULTAR` |
| Cajero | `VENTAS_REGISTRAR` |
| Auditor | `AUDITORIA_CONSULTAR` |

Las semillas de seguridad conservan los usuarios existentes; no restablecen su contraseña ni reactivan roles o permisos. Las de negocio incluyen tres clientes y cuatro productos ficticios. Reejecutarlas no repone stock ni cambia precios o estados existentes. Esto no hace repetible el instalador completo: los scripts de creación de tablas son de instalación inicial.

## Ventas, auditoría e interfaz

`/dashboard` muestra la sesión y sus permisos. `/facturacion` requiere `VENTAS_REGISTRAR` y permite ventas con varios productos. `POST /facturacion/procesar` recibe cliente y detalle con token CSRF; obtiene el usuario exclusivamente de la sesión. SQL calcula importes y registra factura, detalles, ingreso de caja y descuentos de stock en una transacción ACID. Un error revierte toda la venta. Los precios son sin IVA; se calcula el 12% sobre el subtotal global, redondeado a centavos. Node invoca el procedimiento en autocommit, sin reintentar automáticamente resultados inciertos.

`/auditoria` requiere `AUDITORIA_CONSULTAR` y ofrece bitácora de accesos, auditoría de transacciones e histórico de ventas con filtros. Los triggers registran cambios de precio o stock y eliminaciones de productos, e inserciones de facturas, con valores anteriores/nuevos según la operación. La autenticación se registra exclusivamente en `Bitacora_Acceso`. El núcleo incluye las funciones de IVA, subtotal, consulta de auditoría e histórico de ventas y sus procedimientos de consulta.

Sin sesión, las páginas protegidas redirigen al login; sin el permiso requerido, ventas y auditoría responden 403. `/health` comprueba HTTP, no la disponibilidad continua de SQL; el servidor valida la conexión SQL antes de escuchar.

## Pruebas y validación

- `npm run check`: comprobación de sintaxis JavaScript de aplicación y pruebas.
- `npm test`: pruebas Node de autenticación, ventas, interfaz y auditoría con mocks; no conecta a SQL Server.
- `npm run check:db`: conexión SQL real usando la configuración local de `.env`.
- `database/tests/SecurityTests.sql`: esquema y restricciones de seguridad.
- `database/tests/AuthenticationTests.sql`: autenticación, hashing, semillas y RBAC.
- `database/tests/TransactionTests.sql`: ventas transaccionales, importes, stock y rollback.
- `database/tests/AuditTests.sql`: funciones, triggers y consultas de auditoría e histórico.

Las cuatro suites SQL se ejecutan contra SQL Server después de instalar el esquema completo, con una cuenta de desarrollo autorizada y una base de pruebas sin escritores concurrentes. Revisar sus mensajes `OK` y cualquier error. Sus transacciones revierten datos temporales, pero los contadores IDENTITY pueden avanzar. No están incluidas en el Full.

También existe `npm run test:sql -- ".\SQLEXPRESS"`: requiere `sqlcmd`, autenticación Windows y permisos para crear/eliminar una base temporal aislada. Su alcance actual es seguridad, autenticación y ventas, incluyendo concurrencia y permisos transaccionales; no instala auditoría ni valida el Full o `10_AppPermissions.sql`. No usa `.env` y no sustituye las cuatro suites SQL ni la prueba del driver `mssql` con la cuenta real de aplicación.

### Verificación manual final de Kenneth

1. En una instancia de pruebas, instalar el Full sobre una base nueva con el login disponible: verificar creación/mapeo del usuario y mensaje `OK` de permisos.
2. En un entorno aislado sin ese login, instalar el Full: verificar que no falle por su ausencia y que muestre la advertencia. Configurar manualmente el login y ejecutar `10_AppPermissions.sql`; repetir este último para confirmar que no falla por usuario existente. No eliminar el login ni la base de trabajo para simular estos casos.
3. Ejecutar las cuatro suites SQL y comprobar funciones, procedimientos, triggers y semillas. Comparar también una instalación modular nueva con la instalación Full en entornos separados.
4. Conectarse como `securefinance_app`: probar login, permisos RBAC, catálogos, venta con TVP y las tres consultas de auditoría. Confirmar que no puede leer/escribir tablas directamente ni tiene roles amplios.
5. Ejecutar `npm run check:db`, iniciar la web y probar login correcto/incorrecto, cierre de sesión, restricciones de acceso y filtros de auditoría.
6. Con precios DEMO originales, vender dos teclados y tres mouse: subtotal **Q 476.75**, IVA **Q 57.21**, total **Q 533.96**. Con la cuenta de desarrollo verificar una factura, dos detalles, un ingreso de caja, stock reducido en 2 y 3, auditoría de factura/productos e histórico. Una venta con stock insuficiente debe revertirse íntegramente.

Las comprobaciones estáticas y los mocks no sustituyen estas verificaciones en SQL Server.
