# Entrega de Kenneth — integración del equipo

Stack: Node.js 24+, Express, EJS, CSS, JavaScript y SQL Server 2017+. Rama de entrega: `feature/parte-ii-kenneth`; PR hacia `main`, sin merge automático. Esta guía es la referencia actual de instalación. Los informes anteriores reflejan etapas de validación, no el estado final de una base ajena.

## 1. Instalación y migraciones

Usar una base propia del compañero, respaldada y con recuperación comprobada. No copiar bases, identidades, credenciales ni registros de la instalación principal al repositorio. SQL Server necesita `nested triggers` habilitado y una cuenta SQL de aplicación dedicada con permisos mínimos, nunca `sa`, `db_owner` ni `db_datawriter`.

Una instalación **nueva** requiere primero Parte I hasta 14. `database/SecureFinanceERP_Full.sql` prepara esa base inicial; no es una migración y no incluye automáticamente Parte II. Después aplicar, en la base destino explícitamente seleccionada:

| Orden | Archivo | Alcance |
|---|---|---|
| 15 | `15_ParteII_Preflight.sql` | Dependencias, versión, integridad y NIT equivalentes |
| 16 | `16_ParteII_Catalogos.sql` | Proveedores, ampliaciones de productos/clientes y snapshots fiscales |
| 17 | `17_ParteII_Kardex.sql` | Kardex y configuración inicialmente deshabilitada |
| 18 | `18_ParteII_Procedimientos.sql` | Operaciones parametrizadas y RBAC en SQL |
| 19 | `19_ParteII_Auditoria.sql` | Auditoría DML e identidad del actor |
| 20 | `20_ParteII_Permisos.sql` | Permisos EXECUTE y restricciones de acceso directo |
| 21 | `21_ParteII_IntegracionFacturacionKardex.sql` | Venta/Kardex, apertura y conciliación |
| 22 | `22_ParteII_ConsultasWeb.sql` | Búsqueda, paginación, fichas y consultas web |
| 23 | `23_ParteII_MantenimientoClientes.sql` | Alta/edición general de clientes y permisos específicos |

Si el compañero ya tiene parte de esas migraciones, verificar objetos y estado antes de aplicar **solo lo pendiente**. No ejecutar el Full ni paquetes anteriores sobre una instalación existente. La principal que ya tiene 15–23 no requiere reinstalación. Ejecutar con un DBA autorizado y detenerse ante el primer error (`sqlcmd -b` o `:ON ERROR EXIT` en SSMS).

Ejemplo de invocación, sustituyendo instancia y nombre por el entorno propio:

```powershell
sqlcmd -S <instancia> -E -C -b -d <base_del_companero> -i database/15_ParteII_Preflight.sql
```

Repetir para los archivos pendientes en el orden indicado; no usar un bucle que continúe después de un fallo. `-E` utiliza la identidad Windows del DBA, no credenciales de aplicación.

Las migraciones **no abren ni habilitan el Kardex automáticamente**. La apertura documentada, conciliación y habilitación requieren un corte coordinado y el procedimiento autorizado, según [la guía de activación](ParteIIKardexVentaActivacion.md). No probar movimientos sobre una base operativa. La integración 21 conserva las firmas de venta existentes y exige el estado de inventario correcto antes de operar.

## 2. Procedimientos disponibles

| Área | Procedimientos relevantes |
|---|---|
| Productos | `sp_RegistrarProducto`, `sp_ActualizarProducto`, `sp_ConsultarProductos`, `sp_ConsultarProductosWeb` |
| Proveedores | `sp_RegistrarProveedor`, `sp_ActualizarProveedor`, `sp_ConsultarProveedores`, `sp_ConsultarProveedoresWeb` |
| Clientes | `sp_RegistrarCliente`, `sp_ActualizarDatosCliente`, `sp_ActualizarNitCliente`, `sp_InactivarCliente`, `sp_ConsultarClientesAdministracion`, `sp_ConsultarClientesWeb` |
| Inventario | `sp_RegistrarMovimientoKardex`, `sp_ConsultarKardex`, `sp_ConsultarKardexWeb`, `sp_ConsultarEstadoInventario`, `sp_ConsultarConciliacionInventario`, `sp_AbrirKardexInventario`, `sp_HabilitarKardexInventario` |
| Dashboard | `sp_ObtenerResumenDashboard`; abastecimiento reutiliza consultas existentes de productos/inventario |
| Venta integrada | `sp_ProcesarVentaTransaccional`, `sp_ProcesarVentaSinDescuento`; las firmas y el TVP de descuentos permanecen compatibles |
| Accesos | `sp_ObtenerPermisosUsuario`, `sp_RegistrarUsuario`, `sp_ActualizarRolesUsuario` y procedimientos de recuperación existentes |

Consultar las firmas exactas en los scripts, sin crear duplicados para los módulos de los compañeros. El actor se obtiene de la sesión; SQL vuelve a validar permisos y recurso. Cambios de maestros usan ROWVERSION; errores 409 conservan el borrador. El cliente no puede elegir otro actor enviando un UsuarioId en el cuerpo.

El NIT se modifica por su procedimiento específico, con motivo y auditoría. Inactivar es lógico y conserva facturas. El stock no se edita desde Productos: los cambios pasan por movimientos documentados, con validación de saldo, transacción e idempotencia. El Kardex es de solo lectura.

## 3. Rutas y RBAC

Todas las rutas exigen sesión válida y respetan el cambio obligatorio de contraseña. Cada POST de los módulos Kenneth exige también el token CSRF propio. Los permisos se vuelven a comprobar en SQL; seleccionar una fila no autoriza su modificación.

| Ruta / acción | Permisos |
|---|---|
| `/dashboard` | Sesión; accesos y datos sujetos a sus permisos |
| `/clientes` consultar | `CLIENTES_CONSULTAR` |
| Alta / editar datos | Lectura + `CLIENTES_REGISTRAR` / `CLIENTES_EDITAR` |
| Cambiar NIT / inactivar | Lectura + `CLIENTES_ACTUALIZAR_NIT` / `CLIENTES_INACTIVAR` |
| `/proveedores` consultar / administrar | `PROVEEDORES_CONSULTAR` / lectura + `PROVEEDORES_ADMINISTRAR` |
| `/productos` consultar / administrar | `PRODUCTOS_CONSULTAR` / lectura + `PRODUCTOS_ADMINISTRAR` |
| Buscar proveedor desde Productos | `PRODUCTOS_CONSULTAR` + `PROVEEDORES_CONSULTAR` |
| `/inventario` consultar | `INVENTARIO_CONSULTAR` |
| Registrar compra / ajuste | Lectura + `INVENTARIO_REGISTRAR` / `INVENTARIO_AJUSTAR` |
| Apertura administrativa | `INVENTARIO_APERTURAR`, procedimiento y operador autorizados; sin botón web de apertura |
| `/facturacion` | `VENTAS_REGISTRAR` |
| `/auditoria` | `AUDITORIA_CONSULTAR` |
| `/usuarios` | `USUARIOS_ADMINISTRAR` |

La cuenta SQL recibe EXECUTE sobre procedimientos concretos. No conceder SELECT/DML general para hacer funcionar las pantallas. Los permisos de rol se gestionan por las vías existentes; no replicar asignaciones de una base ajena. Costo de producto y acciones administrativas no se exponen a quien solo puede consultar.

## 4. Arranque y configuración

```powershell
npm.cmd ci
Copy-Item .env.example .env
# Completar .env localmente, sin compartir secretos.
npm.cmd run check
npm.cmd test
npm.cmd run check:db
npm.cmd start
```

Abrir `http://localhost:3000/login` o el puerto propio. `.env.example` contiene valores vacíos para `SESSION_SECRET` y `DB_PASSWORD`: generar un secreto local de al menos 32 caracteres y obtener la contraseña de la cuenta SQL dedicada por un canal privado. Configurar `DB_SERVER`, `DB_PORT`, `DB_NAME`, `DB_USER`, cifrado y certificado para el entorno. No añadir `.env`, credenciales reales, tokens ni archivos de configuración locales a Git.

Bootstrap se sirve desde la dependencia local. `sharp` valida/recodifica fotografías; Node 24 y el lockfile son parte de la entrega. El almacén de sesiones actual es el existente para desarrollo; no se presenta este cierre como un despliegue de infraestructura productiva.

## 5. Fotografías

`src/services/fotografiaService.js` guarda uploads en `.data/product-photos/`, fuera de Git. SQL almacena una referencia UUID, no una ruta libre. Solo PNG/JPEG con formato y contenido coincidentes, hasta 3 MB; se decodifican, orientan y recodifican con `sharp`, con límites de píxeles y dimensiones. No se publican originales, metadatos privados ni uploads de la base principal.

Una carga temporal se vincula al guardar; cancelar no elimina la foto definitiva. `/fotografias/:reference` exige sesión y permiso de Productos o Inventario, revalidado en SQL. Mantener persistente ese directorio al desplegar; respaldarlo junto con la base por una vía privada autorizada. Una copia de la base sin sus archivos no reproduce sus fotografías.

El repositorio reproduce las vistas y el estado sin foto. Cada compañero debe cargar imágenes propias autorizadas en su laboratorio. Las pruebas generan imágenes sintéticas en directorios aislados: no necesitan los archivos de producción. Galería/tabla, fotografías actuales y editor con stock de solo lectura se conservan.

## 6. Pruebas

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run test:ui
git diff --check
```

La validación de cierre registró **66 pruebas Node PASS**, check PASS, Chromium PASS y diff limpio de errores. `test:ui` usa servicios controlados y no escribe en SQL principal; requiere Chrome o Edge instalado. Revisa responsive, foco, roles, formularios, contraste, reduced-motion y navegación. Si Chromium no puede abrir el canal de depuración en un sandbox, ejecutar con los permisos del entorno.

Los ensayos SQL son **optativos** y requieren una instancia de laboratorio, permisos DBA y `sqlcmd`. Los ejecutores crean/restauran bases aisladas; no apuntarlos a una base operativa. No son un paso de arranque ni de despliegue:

- `database/tests/RunParteIIKennethTests.ps1`: fundamentos SQL en una base nueva con prefijo validado; `-Run` es explícito.
- `npm.cmd run test:sql:kenneth:web`: ensayos web/SQL aislados; requiere el entorno de laboratorio descrito por el ejecutor, autenticación Windows para el DBA y cuenta SQL local de aplicación.
- `npm.cmd run test:sql:kenneth:refinement`: restauración privada y pruebas de mantenimiento. Configurar localmente `KENNETH_TEST_DATABASE` con prefijo `SecureFinanceERP_ParteII_Test_`, `KENNETH_TEST_SERVER`, `KENNETH_TEST_BACKUP`, `KENNETH_TEST_DATA_DIRECTORY` y `KENNETH_TEST_LOG_DIRECTORY`. Las rutas pertenecen al servidor SQL de laboratorio; requiere espacio y permisos de backup/restore. No publicar el respaldo. `--resume` solo debe usarse sobre el ensayo aislado existente, nunca sobre la principal.
- Los previews `operationsCenter.browser.js`, `kennethReadOnlyPreview.js` y `kennethSelection.browser.js` requieren `KENNETH_PREVIEW_USER_ID` de una cuenta autorizada del laboratorio. Usan autenticación inyectada solo en ese proceso; no verifican la contraseña real. La selección `--write` exige además el nombre aislado en `KENNETH_TEST_DATABASE`; usa fixtures de los tres clientes de laboratorio, no datos operativos.

Los informes, capturas, exportaciones SQL y perfiles de navegador generados permanecen locales e ignorados. Las pruebas de sintaxis y Node no sustituyen un ensayo de instalación/recuperación en el entorno del compañero. No se volvieron a ejecutar migraciones en la principal para este cierre.

## 7. DEMO e históricos

Las instalaciones nuevas omiten datos académicos por defecto. Los fixtures requieren el opt-in de conexión `SecureFinance.AllowAcademicSeed`; el seed comercial rechaza bases con facturas o Kardex. Nunca habilitarlo sobre una base empresarial existente.

Pueden permanecer NIT/SKU/nombres DEMO de instalaciones anteriores, con facturas y movimientos históricos. Se muestran sin reemplazos visuales engañosos. No se incluyen en Git exportaciones de esos registros. La transición recomendada es conservar el historial y crear identidades auténticas separadas cuando el responsable entregue datos legítimos, utilizando procedimientos autorizados. No renombrar entidades ficticias para presentarlas como reales, ni reescribir snapshots fiscales, auditoría o saldos.

## 8. Fronteras de integración

Kenneth entrega inventario/Kardex, maestros, clientes y Dashboard corporativo. Se conserva la integración transaccional existente con Facturación; los formatos, CSRF, sesiones, descuentos, RBAC y auditoría no deben duplicarse.

- **Edward:** continúa sus módulos pendientes de devoluciones y garantías. Tener campos de garantía en el catálogo no significa que el flujo de garantías esté implementado.
- **José:** continúa la analítica avanzada y los contratos futuros de Dashboard/TVF. No hay métricas simuladas ni implementaciones provisionales; `dashboardService.obtenerOperacion` ofrece una composición de consultas existentes que puede extenderse cuando sus contratos estén disponibles.

Antes de integrar, revisar el PR y ensayar migraciones pendientes en una copia propia. Este cierre no hace merge a main ni modifica registros de la principal.
