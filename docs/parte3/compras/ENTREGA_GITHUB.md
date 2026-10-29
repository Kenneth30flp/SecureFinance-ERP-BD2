# Preparación de commit y pull request

Rama de trabajo: `feature/p3-edward-compras`.
Base del PR: `integracion/parte3`.
No se realizó commit, push, creación de PR ni merge durante esta entrega.

Código listo para commit de implementación y revisión. **La validación SQL
real sigue pendiente**: no presentar el commit como certificación funcional
de base de datos ni desplegarlo antes de superar el laboratorio aislado.

## Mensaje de commit

```text
feat(compras): integrar ordenes, recepciones y valoracion de inventario

Agrega migraciones 50-55, aprobacion independiente, recepciones parciales
mediante el receptor existente y valoracion con costos documentados.
Integra interfaz EJS responsive, navegacion, CSRF y pruebas Node/navegador.
Prepara laboratorio Express restringido; validacion SQL real pendiente.
```

## Comandos manuales

Ejecutar desde la raíz después de revisar el contenido. No cambian de rama,
no hacen merge ni usan force-push. El primer comando debe mostrar la rama
indicada arriba. La selección explícita excluye `.env`, `.data` y capturas.

```powershell
git branch --show-current
git diff --check
git add -- database/50_P3_COM_EstructuraOrdenesCompra.sql database/51_P3_COM_OperacionesOrdenesCompra.sql database/52_P3_COM_RecepcionesOrden.sql database/53_P3_COM_Valoracion.sql database/54_P3_COM_ConsultasWeb.sql database/55_P3_COM_PermisosFinales.sql
git add -- database/tests/ComprasIntegration.js database/tests/comprasLabSafety.js scripts/prepareComprasLab.ps1
git add -- src/modules/compras src/views/compras src/public/css/compras.css src/public/js/compras.js
git add -- tests/compras.test.js tests/comprasWeb.test.js tests/helpers/comprasFixture.js tests/browser/compras.browser.js
git add -- server.js package.json src/config/moduleCatalog.js src/views/partials/navigation.ejs docs/parte3/CONTRATOS_INTEGRACION.md docs/parte3/compras
git diff --cached --stat
git diff --cached --check
git commit -m "feat(compras): integrar ordenes, recepciones y valoracion de inventario"
git push -u origin feature/p3-edward-compras
```

Si el push es rechazado por divergencia, detenerse y revisar con el integrador;
no sobrescribir la rama remota con force-push. No se actualizó el remoto para
esta revisión: las verificaciones de reserva de migraciones son locales.

## Título del PR

```text
Parte III · Compras: órdenes, aprobaciones, recepciones y valoración
```

## Descripción preparada

Las órdenes de compra ahora conservan proveedor, productos, cantidades y
costos pactados; requieren aprobación de otro usuario autorizado y permiten
registrar entregas parciales hasta completar lo solicitado. La recepción usa
`sp_RegistrarRecepcionCompra` una vez por producto y conserva el Kardex que
ese procedimiento genera, sin duplicar stock.

Se agregan las migraciones 50–55, seis tablas propias `P3_COM_`, procedimientos
parametrizados, auditoría de estados, idempotencia por UUID/huella, control de
versión y permisos separados. El libro auxiliar calcula valoración con costos
documentados e identifica saldos desconocidos sin usar el costo de catálogo.
Incluye el dominio completo del costo heredado `DECIMAL(19,2)`.

La interfaz EJS incorpora listado, alta, detalle imprimible, aprobación,
cancelación, recepción, pendientes, historial y valoración. Reutiliza el tema,
navegación, autenticación y proveedores del ERP; agrega CSRF propio, controles
responsive y conservación de referencias ante respuestas inciertas.

**Validación:** consultar `docs/parte3/compras/RESULTADOS.md` para los comandos
y resultados ejecutados de Node, navegador y revisión de Git. Las pruebas de
navegador utilizan datos sintéticos y servicios simulados.

**Pendiente antes de integrar/desplegar:** ejecutar las migraciones y escenarios
SQL en una base nueva `SecureFinanceERP_P3_COM_LAB_<UUID>` con una credencial
restringida. No hay credencial admisible disponible en esta entrega; no se
ejecutó SQL de escritura ni se certifican concurrencia/rollback contra el motor.
El instalador Express falla cerrado ante privilegios o destinos incompatibles.

**Compatibilidad:** no se modifican procedimientos/tablas compartidos de
inventario, recepción, Kardex o facturación. Los costos de recepción de cuatro
decimales quedan en el enlace propio; el campo heredado queda NULL cuando no
es representable exactamente a dos. La valoración se actualiza expresamente
desde su pantalla. Se opera con inventario global hasta el contrato real de
multibodega de Dylan. Los permisos nuevos requieren asignación administrativa.

Destino: `integracion/parte3`. Recomendación: PR en borrador mientras esté
pendiente el laboratorio SQL. Sin merge automático.
