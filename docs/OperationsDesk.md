# Facturación y Auditoría: Operations Desk

## Aplicación sobre una base existente

La base real no se modifica mediante las pruebas. Detener Node y respaldar
`SecureFinanceERP` antes de aplicar los cambios como administrador.

Si la migración anterior de descuentos **ya está aplicada**, ejecutar únicamente:

```powershell
sqlcmd -S localhost -E -C -b -f 65001 -i ".\database\13_OperationsDesk.sql"
```

Si descuentos todavía no está aplicado, ejecutar en este orden:

```powershell
sqlcmd -S localhost -E -C -b -f 65001 -i ".\database\12_SalesDiscounts.sql"
if ($LASTEXITCODE -ne 0) { throw 'Falló la migración de descuentos.' }
sqlcmd -S localhost -E -C -b -f 65001 -i ".\database\13_OperationsDesk.sql"
if ($LASTEXITCODE -ne 0) { throw 'Falló la migración de Operations Desk.' }
```

Sustituir `localhost` si se usa otra instancia. Alternativamente ejecutar cada
archivo completo en SSMS con autenticación administradora. El script 13 debe
mostrar `OK: Operations Desk policy, reason and receipt installed.`
Es repetible y atómico. No ejecutar 05 ni el instalador completo sobre esta base.
No volver a ejecutar 12 después de 13: contiene la versión anterior del SP.
Si se ejecuta por error, reaplicar 13 antes de iniciar Node.

El script 13 agrega `Factura.MotivoDescuento NVARCHAR(80) NULL` con CHECK para
los cinco motivos disponibles. Los registros históricos quedan con NULL y sus
importes permanecen intactos. Conserva los TABLE TYPE existentes.
Incluye función de política, procedimiento para consultarla, procedimiento de
venta, trigger de factura y permisos EXECUTE mínimos si `securefinance_app` existe.
No agrega acceso directo a tablas ni funciones al usuario de la aplicación.
`10_AppPermissions.sql` y `SecureFinanceERP_Full.sql` están sincronizados para
instalaciones nuevas y la administración de permisos.

Verificar con SSMS:

```sql
USE [SecureFinanceERP];
SELECT TOP (10) FacturaId, Subtotal, DescuentoTotal, MotivoDescuento, IVA, Total
FROM dbo.Factura ORDER BY FacturaId DESC;
DECLARE @Admin INT = (SELECT UsuarioId FROM dbo.Usuario WHERE NombreUsuario = N'admin');
EXEC dbo.sp_ObtenerPoliticaVenta @UsuarioId = @Admin;
EXEC dbo.sp_ConsultarHistoricoVentas;
```

Iniciar la aplicación actualizada con `npm.cmd start` una vez que 13 termine
correctamente. Las migraciones de contraseñas y Usuarios y Roles se conservan;
esta mejora presupone que esos módulos ya están instalados y no los reinstala.

## Política de descuentos y seguridad

La política consulta el usuario de sesión contra Usuario, Usuario_Rol, Rol,
Rol_Permiso y Permiso activos. No acepta UsuarioId, RolId ni límites del navegador.
Administrador con VENTAS_REGISTRAR tiene máximo 100%; Cajero, 10%.
Un usuario con ambos roles conserva el máximo de Administrador. Otros roles
personalizados con VENTAS_REGISTRAR reciben el límite conservador de 10%.
Auditor sin permiso de ventas es rechazado por RBAC y SQL.

El backend consulta nuevamente la política antes de llamar al SP. El SP la valida
dentro de su transacción y conserva los bloqueos de lectura del RBAC hasta COMMIT.
Una revocación ya efectiva se rechaza aunque la sesión todavía contenga el permiso.
Se conservan XACT_ABORT, TRY/CATCH, ROLLBACK y los bloqueos UPDLOCK/HOLDLOCK de stock.

El motivo es opcional, seleccionado de un catálogo corto, **por factura** y aplicable
a sus descuentos. Se guarda solo si alguna línea tiene descuento porcentual positivo.
El trigger incluye motivo y DescuentoTotal en el JSON de la factura. No se aceptan
textos libres, credenciales ni motivos enviados como código SQL.

Los importes siguen usando centavos y BigInt en la vista y DECIMAL/ROUND en SQL:
descuento redondeado por línea, IVA sobre el neto global. El navegador envía
ClienteId, MotivoDescuento y, por línea, ProductoId, Cantidad y DescuentoPorcentaje.
SQL devuelve metadatos de factura y un segundo recordset con detalle, precios y
descuentos confirmados. El comprobante usa exclusivamente ese resultado, incluso
cuando los precios actuales difieren de la estimación mostrada.

## Interfaz

Auditoría usa subnav GET (`vista=acceso|dml|ventas`), una sola sección renderizada,
filtros contextuales y limpieza que mantiene la vista. Los otros indicadores muestran
los registros sin esos filtros. No requiere JavaScript para navegar ni filtrar.
Las tablas tienen scroll interno y encabezados fijos. DML permite desplegar JSON
indentado, con contenido escapado. El histórico usa SubtotalNeto disponible en SQL.
Las fechas de los filtros conservan el criterio UTC existente; la presentación
convierte los horarios a Guatemala.

Facturación permite editar cantidad, visualizar ahorro y stock posterior estimado,
buscar productos/clientes, confirmar/cancelar y presentar/imprimir un comprobante.
Cancelar o presionar Escape no envía ventas. La confirmación inmoviliza los campos
de preparación; se bloquea el doble envío. Los resultados inciertos y revocaciones
no se reintentan automáticamente. El comprobante es interno/académico, sin SAT.

Método de pago queda recomendado para una siguiente migración: persistir método,
monto recibido y cambio, con validación SQL dentro de la misma transacción y
tratamiento coherente en MovimientoCaja. No se agrega un control visual sin respaldo
persistente. El descuento y el cobro actual mantienen su significado.

## Validación

```powershell
npm.cmd run check
npm.cmd test
git diff --check
node database/tests/TransactionIntegrationTests.js localhost
node database/tests/UserAdministrationIntegrationTests.js localhost
npm.cmd run test:ui
```

Los ejecutores SQL crean y eliminan solamente sus bases temporales con autenticación
Windows. Incluyen migración histórica repetida, política por rol, motivos, stock,
caja, auditoría, rollback, concurrencia y pruebas anteriores.
`test:ui` requiere Chrome o Edge instalado; usa servicios simulados y un perfil
temporal independiente. Genera capturas y PDF en TEMP, valida 1366×768 y 1920×1080,
las tres vistas, confirmación/cancelación, comprobante, impresión y el límite Cajero.
No usa la conexión SQL de la aplicación para la prueba visual.

Comprobar visualmente con usuarios reales después de migrar:

1. Las tres vistas de Auditoría, filtros, limpieza, scroll y JSON desplegable.
2. Administrador: Cable HDMI Q35.90, cantidad 2, descuento 25%, ahorro Q17.95,
   neto Q53.85, IVA Q6.46 y total Q60.31. Cancelar no registra nada.
3. Cajero: 10% permitido, 25% rechazado. Auditor sin acceso a Facturación.
4. Búsquedas por código/descripción y NIT/nombre; cantidad inválida o superior a stock.
5. Comprobante, motivo guardado, impresión sin sidebar ni botones, Nueva venta.
6. Sidebar por permisos, login, contraseñas y Usuarios y Roles.
