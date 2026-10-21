# Analítica avanzada y dashboard ejecutivo — José

## Arquitectura

El módulo es independiente del `/dashboard` operativo de Kenneth y se sirve en `/analitica`. La lógica Node está en `src/modules/jose/`: validación de filtros, servicio parametrizado, controlador y rutas. La vista `src/views/analitica.ejs` usa el tema corporativo existente y tablas accesibles; no carga facturas completas al navegador.

## SQL creado

Las migraciones propias son incrementales y no destructivas:

* `database/30_Jose_FuncionesAnaliticas.sql`: vista de líneas históricas y tres inline TVF.
* `database/31_Jose_DashboardVentas.sql`: índices justificados para filtros de fecha y detalle por factura, y `sp_ObtenerDashboardVentas`.
* `database/32_Jose_PermisosConsultas.sql`: permisos de consulta y asignación inicial al rol Administrador.

No se modifican las migraciones 15–26. Los índices nuevos cubren el patrón de lectura `Factura.FechaHora` y el acceso de agregación `DetalleFactura.FacturaId`; no duplican los índices existentes por producto o cliente.

## TVF y cálculos

* `dbo.fn_ProductosMasVendidos(@DesdeUtc, @HastaUtc)` agrupa ventas emitidas por producto, usa `Cantidad`, `SubtotalNeto`, cuenta facturas sin duplicar líneas y ordena empates por unidades, importe y `ProductoId`.
* `dbo.fn_ProductosPorComprar(@IncluirInactivos)` separa `BajoMinimo` de `EnReorden`, calcula déficit y `max(PuntoReorden - Stock, 0)`, conserva inactivos y marca proveedor pendiente.
* `dbo.fn_AnalisisClientesFrecuentes(@DesdeUtc, @HastaUtc)` cuenta una compra por factura, conserva clientes inactivos, calcula total, última compra y ticket promedio, sin exponer NIT.

Todos los importes son `DECIMAL`. Los filtros son `[inicio local, fin local exclusivo)`; el procedimiento transforma la jornada Guatemala (`Central America Standard Time`, UTC−6) a UTC antes de leer `Factura.FechaHora`.

## Procedimiento y permisos

`dbo.sp_ObtenerDashboardVentas` recibe `@ActorUsuarioId`, `@Modo` (`DIARIO`, `SEMANAL`, `MENSUAL`, `RANGO`), fechas opcionales y paginación. Valida permisos con `sp_ParteII_ValidarPermiso`, rechaza rangos invertidos y devuelve cinco conjuntos: KPIs, productos vendidos, clientes, abastecimiento y contrato de garantías no integrado.

Los permisos propios son `ANALITICA_CONSULTAR` y `REPORTES_EJECUTIVOS_CONSULTAR`. La cuenta de aplicación solo recibe `EXECUTE` sobre el procedimiento; no se concede `db_owner`, DML general ni acceso directo a costos.

## Interfaz y estados

La pantalla tiene selector temporal, KPIs de día/mes/rango, tabla de ranking, clientes, abastecimiento y estado de garantías. Usa Q/GTQ, estados sin resultados, carga, error y acceso denegado. La paginación limita a 10 filas por conjunto y usa consultas SQL parametrizadas. No hay gráficos falsos ni estadísticas inventadas.

La prueba UI existente genera capturas y artefactos temporales fuera del repositorio. No se incorporan capturas de sesiones ni datos de laboratorio al commit.

## Instalación

En una base de laboratorio propia, aplicar 30, 31 y 32 después de las migraciones 15–23 y detenerse ante el primer error. Configurar `.env` localmente y ejecutar `npm.cmd run check`, `npm.cmd test`, `npm.cmd run test:ui` y `git diff --check`. No ejecutar sobre la base principal sin respaldo y autorización DBA. No se incluyen credenciales, datos personales ni exportaciones.

## Garantías y dependencias

Ventas, clientes y abastecimiento funcionan sin Edward. La única dependencia futura es el contrato descrito en [JoseContratoGarantias.md](./JoseContratoGarantias.md); hasta entonces el panel informa que la fuente no está integrada.

## Validación de entrega

Los resultados de las pruebas se registran en el informe de entrega, únicamente después de ejecutar cada comando. Una prueba SQL requiere una base de laboratorio aislada; si no existe conexión, se reporta como no ejecutada y no como PASS.
