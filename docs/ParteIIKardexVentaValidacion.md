# Validación ejecutada — 18 de octubre de 2026

Commit previo: `cc6e734`. Rama: `feature/parte-ii-kenneth`. La integración nueva permanece sin commit y sin staging.

Base nueva y conservada: `SecureFinanceERP_ParteII_Test_Kardex_65c03d7b4cf943e09fa7d8751e04869f`.

Resultado final: **95 PASS, 0 FAIL**. Detalle individual, mensajes y evidencias en ParteIIKardexVentaResultados.json. Son 33 comprobaciones de fundamentos/regresión antes de integrar, 33 después, 14 de integración, siete monetarias, seis de rollback y dos de concurrencia. Las migraciones 15–20 se aplicaron dos veces; 21 se aplicó dos veces antes de apertura y otra vez con libro activo.

## Evidencias principales

- C01: dos conexiones independientes, sesiones 61 y 62, bloqueo real LCK_M_U observado por una tercera conexión. Una venta aceptada y una rechazada; una factura, una caja, una salida y saldo cero.
- C02: dos ventas simultáneas con orden inverso en el TVP; dos éxitos, cuatro salidas, ambos saldos cero, sin deadlock observado. No constituye prueba de ausencia de deadlocks bajo cualquier carga.
- B01–B06: fallos después de factura, detalle, actualización de stock, inserción Kardex, antes de caja y en auditoría. Se compararon conteos y SHA256 de las seis tablas antes/después; ninguna operación parcial persistió.
- I13: el llamador conservó su transacción exterior y su rollback eliminó todos los efectos.
- I02/I03/I05: apertura repetible, sin duplicar existencias; saldo previo 20, apertura 20, venta 3 y saldo 17.
- I07: reintentar un movimiento no altera stock ni duplica registros. I08 demuestra expresamente que la venta completa todavía no es idempotente.
- I14: factura anterior al corte rechazada con 54409 y sin cambios en las seis tablas.
- I06: exactamente dos conjuntos de resultados; contrato de once columnas de cabecera y ocho de detalle, importes System.String, compatible con Node.
- I12 y regresiones: apertura denegada al usuario SQL de aplicación, RBAC y acceso mínimo conservados.

| Caso | Subtotal | Descuento | Neto | IVA | Total y caja |
|---|---:|---:|---:|---:|---:|
| Sin descuento | 71.80 | 0.00 | 71.80 | 8.62 | 80.42 |
| Cajero 10% | 71.80 | 7.18 | 64.62 | 7.75 | 72.37 |
| Administrador 25% | 71.80 | 17.95 | 53.85 | 6.46 | 60.31 |
| Administrador 100% | 71.80 | 71.80 | 0.00 | 0.00 | 0.00 |
| Dos productos | 102.55 | 21.03 | 81.52 | 9.78 | 91.30 |

También se rechazaron descuentos fuera de política y fuera de 0–100. Una comprobación adicional final ejecutó sp_ConsultarConciliacionInventario: 26 productos sin diferencias, cero triggers de inyección restantes y 53 módulos SQL. Kardex habilitado versión 2 únicamente en esta base temporal.

## Base original

Lecturas mediante ReadOriginalState.sql: coincidencia exacta antes/después de conteos y SHA256 de productos, facturas, detalles, caja, asignaciones usuario/rol, rol/permiso y definiciones de módulos. Producto conserva cuatro filas, Factura catorce y DetalleFactura diecinueve. Kardex y ConfiguracionInventario continúan NO_INSTALADO en SecureFinanceERP. No se ejecutaron migraciones ni procedimientos de negocio sobre esa base.

## Repositorio y defectos corregidos

`npm.cmd run check`: PASS. `npm.cmd test`: 43/43 PASS. `npm.cmd run test:ui`: PASS en Chromium, con servicios simulados. `git diff --check` y revisión de espacios finales en archivos nuevos: PASS. No se modificó frontend ni se creó un segundo commit, push o PR.

Se corrigieron dos defectos del ejecutor encontrados en intentos anteriores: opciones SET requeridas por índices filtrados en conexiones nuevas y acceso a claves del constructor de conexión ADO.NET desde PowerShell. Los intentos fallidos se conservan como tales en previousAttempts del JSON. El límite de factura de apertura agrega protección frente a reprocesamiento histórico; su caso pasó en la ejecución final.

Logs SQL de la ejecución final: `%TEMP%\securefinance-kardex-sales-OUlaz7`. No se eliminó ninguna base temporal. El plan de activación y recuperación está en ParteIIKardexVentaActivacion.md; no se ejecutó sobre producción.
