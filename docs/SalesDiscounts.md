# Descuentos de facturación

La aplicación envía únicamente `ClienteId` y líneas con `ProductoId`, `Cantidad`
y `DescuentoPorcentaje`. La sesión aporta el usuario. El porcentaje omitido
equivale a cero; NULL, negativos, valores superiores a 100 y más de dos decimales
se rechazan en Node. SQL valida el TVP independientemente.

SQL obtiene precio y stock de Producto con UPDLOCK/HOLDLOCK. Descuentos, factura,
detalles, stock, auditoría y caja pertenecen a la misma transacción con XACT_ABORT.
Los importes del navegador nunca se usan para persistir la venta.

## Importes y redondeo

- `Factura.Subtotal` y `DetalleFactura.Subtotal` mantienen el importe bruto.
- `Factura.DescuentoTotal` suma los descuentos monetarios de cada línea.
- `DetalleFactura.DescuentoPorcentaje` es DECIMAL(5,2), entre 0.00 y 100.00.
- `DetalleFactura.DescuentoMonto` es DECIMAL(19,2).
- `DetalleFactura.SubtotalNeto` es una columna calculada PERSISTED: bruto menos descuento.
- Cada descuento se redondea a dos decimales antes de sumar.
- El IVA se redondea sobre el neto global, una sola vez.
- SQL usa ROUND; para importes no negativos, las mitades suben al siguiente centavo.
  La vista reproduce ese criterio con BigInt y porcentajes en centésimas.

Ejemplo verificado: bruto Q35.90, descuento 10% = Q3.59, neto Q32.31,
IVA Q3.88 y total Q36.19. Un descuento del 100% autorizado para Administrador da neto, IVA y total cero;
la venta igualmente consume stock y registra caja con importe cero.

## Aplicar a SecureFinanceERP existente

1. Detener el proceso Node de la aplicación para evitar ventas durante el cambio de TVP.
2. En SSMS, respaldar la base `SecureFinanceERP` con la cuenta administradora.
3. Desde la raíz del proyecto, ejecutar en PowerShell con autenticación Windows:

   ```powershell
   sqlcmd -S localhost -E -C -b -f 65001 -i ".\database\12_SalesDiscounts.sql"
   ```

   `localhost` corresponde a la instancia local predeterminada usada en las pruebas.
   Si tu base está en otra instancia, sustituirlo por ese nombre de servidor/instancia.
   Alternativamente abrir `database/12_SalesDiscounts.sql` en SSMS y ejecutarlo
   completo como administrador. Debe aparecer `OK: sales discounts migration applied.`
   Si falla, no iniciar la versión nueva de Node hasta resolver el error.
4. Para la versión actual de la aplicación, aplicar después `database/13_OperationsDesk.sql`
   antes de iniciar Node. Agrega la política por rol, el motivo opcional y el resultado
   del comprobante. Consultar `docs/OperationsDesk.md` para el orden completo.
   No reaplicar 12 después de 13 sin volver a aplicar 13.

   ```powershell
   sqlcmd -S localhost -E -C -b -f 65001 -i ".\database\13_OperationsDesk.sql"
   ```

5. Verificar en SSMS:

   ```sql
   USE [SecureFinanceERP];
   SELECT TOP (20) FacturaId, Subtotal, DescuentoTotal, IVA, Total
   FROM dbo.Factura ORDER BY FacturaId DESC;
   SELECT TOP (20) DetalleFacturaId, Subtotal, DescuentoPorcentaje,
       DescuentoMonto, SubtotalNeto
   FROM dbo.DetalleFactura ORDER BY DetalleFacturaId DESC;
   SELECT TYPE_ID(N'dbo.TipoDetalleVentaDescuento') AS NuevoTipo;
   EXEC dbo.sp_ConsultarHistoricoVentas;
   ```

   Las ventas anteriores mantienen todos sus importes y descuentos en cero.
6. Iniciar la aplicación actualizada con `npm.cmd start` y verificar Facturación.

La migración incluye los procedimientos, la función de histórico, el trigger y los
permisos del nuevo tipo para el usuario de base `securefinance_app` si ya existe.
No es necesario ejecutar de nuevo los scripts 05, 06, 07, 08 ni el instalador completo.
Si aún no existe ese usuario, configurar su login y ejecutar
`database/10_AppPermissions.sql` después de instalar los módulos actuales.
Ese script conserva permisos mínimos sin dar acceso directo a tablas.

La migración puede repetirse y aplica todos sus cambios dentro de una transacción.
No elimina el tipo anterior `dbo.TipoDetalleVenta`. Los clientes que usaban ese TVP
deben cambiar su llamada a `dbo.sp_ProcesarVentaSinDescuento`; SQL Server no permite
pasar el tipo anterior al parámetro nuevo del mismo procedimiento.

`12_PasswordRecovery.sql` y `12_SalesDiscounts.sql` son migraciones independientes.
No se reemplaza ni se vuelve a ejecutar recuperación de contraseña para agregar descuentos.
`SecureFinanceERP_Full.sql` es exclusivamente para instalaciones nuevas.

## Pruebas

```powershell
npm.cmd run check
npm.cmd test
git diff --check
node database/tests/TransactionIntegrationTests.js localhost
node database/tests/UserAdministrationIntegrationTests.js localhost
```

Las pruebas SQL usan autenticación Windows y necesitan permiso CREATE DATABASE.
Crean y eliminan únicamente bases temporales; no aplican cambios a SecureFinanceERP.
El primer ejecutor también lee con `git show HEAD` los scripts anteriores para probar
la migración sobre una factura histórica. No hace checkout ni modifica Git.

El motivo opcional por factura se incorpora en `13_OperationsDesk.sql`.
