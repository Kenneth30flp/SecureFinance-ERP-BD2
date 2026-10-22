# Reactivación administrativa de clientes

La ficha ofrece **Inactivar cliente** para clientes activos y **Reactivar cliente** para inactivos, según el permiso específico. La reactivación exige motivo y confirmación con el nombre del cliente, actualiza la ficha y elimina el filtro Inactivo para que el registro recién activado siga visible. La fecha/motivo de la última inactivación se conservan y se etiquetan como tales. Se muestran los últimos 20 cambios de estado; todos los eventos permanecen en la bitácora.

## SQL, permisos y reintentos

`40_ERP_ReactivarCliente.sql`, posterior a 39, añade:

- `sp_ReactivarCliente`: transacción con validación de existencia, estado Inactivo, ROWVERSION y motivo. Solo actualiza `Cliente.Activo`; no modifica NIT, contacto, facturas, devoluciones, créditos o tickets.
- `ReactivacionCliente`: libro inmutable por OperacionId, con usuario, cliente, versiones anterior/posterior, fecha UTC y motivo. Protege los reintentos incluso entre sesiones web.
- `sp_ConsultarHistorialEstadoCliente`: consulta acotada de los eventos de cambio de estado ya existentes; recupera los motivos de inactivación históricos desde su JSON cuando no se registraron como contexto independiente.
- `CLIENTES_REACTIVAR`: asignado inicialmente **solo al Administrador**. Express comprueba el permiso y CSRF; SQL vuelve a validar la autorización vigente. La cuenta de aplicación recibe EXECUTE, sin UPDATE directo sobre Cliente ni DML directo sobre el libro.

La referencia de operación se genera al presentar la ficha. SQL bloquea por referencia y por fila del cliente: dos solicitudes idénticas producen un único cambio y un único evento de auditoría. Si reutilizan la referencia con otro motivo, versión, usuario o cliente, se rechazan. Dos referencias distintas con la misma ROWVERSION permiten solo un cambio. Un reintento antiguo no puede deshacer una inactivación posterior.

Se reutiliza el trigger de auditoría de Cliente: registra usuario, fecha UTC, motivo, operación y JSON de estado anterior/nuevo. El procedimiento comprueba que exista exactamente un evento antes de confirmar; si no puede acreditarlo, revierte toda la transacción. El contexto de sesión se limpia en éxito y error. El motivo se valida como NVARCHAR(MAX) y se pasa a SESSION_CONTEXT mediante NVARCHAR(250), compatible con sql_variant.

La migración **no reactiva a nadie ni modifica filas de clientes**. Solo instala los objetos y el permiso inicial. No reescribe eventos anteriores ni recrea identidades.

## Pruebas ejecutadas

- `npm.cmd run check`: PASS.
- `npm.cmd test`: **95/95 PASS**, cero fallidas y omitidas.
- Pruebas dirigidas: botón según estado, motivo, confirmación, actor tomado de sesión, CSRF, permiso propio, campos inválidos, conflicto de versión y parámetros tipados sin NIT ni SQL directo: PASS.
- SQL real en copia: Activo → Inactivo → Activo; rechazo al Cajero, cliente inexistente y versión obsoleta; reintentos simultáneos idénticos y referencias diferentes; cambio de motivo rechazado; reintento antiguo tras nueva inactivación rechazado; auditoría única y contexto limpio: PASS.
- Se creó una factura de un cliente QA antes de inactivarlo, se comprobó el rechazo de nuevas ventas durante la inactivación y la disponibilidad en la lista de venta tras reactivar. Su comprobante anterior permaneció idéntico. Se cotejaron además los documentos previos completos mediante hash: PASS.
- Chromium con SQL real: inactivación y reactivación, cancelar/confirmar, ficha y mensaje actualizados, filtro inactivo limpiado, reintento sin duplicar bitácora y tamaños 1366/768/390/320: PASS. El ejecutor espera el cierre del diálogo y el foco restaurado antes de reenviar.
- `npm.cmd run test:ui` y `npm.cmd run test:ui:edward`: PASS.
- `git diff --check`: PASS.

Todas las escrituras QA se limitaron a clientes de prueba de la copia y excluyeron el ClienteId 3. La validación de SQL encontró inicialmente una incompatibilidad de SESSION_CONTEXT con NVARCHAR(MAX); se corrigió y se repitió sobre una nueva restauración antes de tocar la principal. La autenticación del navegador se sustituye únicamente por una sesión QA identificada; no acredita login manual ni captura contraseñas.

## Respaldo e integración

Se creó backup completo actual COPY_ONLY/CHECKSUM de SecureFinanceERP, se ejecutó VERIFYONLY y se restauró en `SecureFinanceERP_Clientes_20261022001219`. Pasaron CHECKDB, restricciones y conciliación de las **30 tablas anteriores**, incluyendo todos los clientes, documentos, relaciones y bitácora. Los hashes excluyen únicamente las filas nuevas esperadas de CLIENTES_REACTIVAR en Permiso/Rol_Permiso; se verifica por separado su asignación exclusiva al Administrador. El libro nuevo debe estar vacío al instalar.

`DeployClientReactivation40.ps1` permite Inspect, Prepare, Laboratory, Deploy y Verify. Comprueba la definición exacta de objetos, SHA-256 de la migración validada, permisos y preservación de filas. La ventana coordinada requiere backend detenido, ausencia de sesiones de escritura y RESTRICTED_USER durante actualización y conciliación. El arranque del backend exige los dos procedimientos nuevos. El despliegue final se registra tras completar esa ventana.

**Cliente principal reservado para operación manual:** Consumidor final DEMO, ClienteId 3, se encontró **Inactivo**, con seis facturas asociadas. No se reactiva automáticamente ni como parte de las pruebas. Su reactivación se hará mediante la interfaz después del despliegue.

Archivos de integración: migración 40; `clienteService.js`, `kennethController.js`, `kennethRoutes.js`, `clientes.ejs`, parcial `cliente-reactivacion.ejs`, JavaScript compartido, comprobación de arranque, pruebas unitarias, SQL y Chromium. No se ejecuta Full, no se cambian credenciales y no se fusiona main.
