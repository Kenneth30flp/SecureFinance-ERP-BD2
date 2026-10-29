# Integración Parte III — Dylan / Kenneth

Rama de entrega: `integracion/p3-dylan-qa`, base exacta `02d85b519cc00a57599308bbbe24844b061bf0a7`. Destino: `integracion/parte3`. Fecha de entrega: viernes 30/10/2026. No fusionar automáticamente ni desplegar en la base principal.

## Procedencia y resolución

Se fusionaron conservando sus historiales los PR [#16 Auditoría DDL](https://github.com/Kenneth30flp/SecureFinance-ERP-BD2/pull/16), [#17 Créditos](https://github.com/Kenneth30flp/SecureFinance-ERP-BD2/pull/17) y [#18 Multibodega](https://github.com/Kenneth30flp/SecureFinance-ERP-BD2/pull/18). Los conflictos reales estuvieron en `package.json`, `server.js`, `src/config/moduleCatalog.js` y `src/views/partials/navigation.ejs`. Se conservaron Promociones y las rutas anteriores, sumando servicios, inyección de dependencias y navegación de los tres módulos. Créditos pertenece a Finanzas; Multibodega a Inventario; DDL a Administración. Siguen existiendo seis áreas de negocio.

La 76 se reconstruyó desde la definición completa de la 63, incorporando la financiación de Dylan y su conversor. Se preservaron el orden de parámetros históricos, `@P3CotizacionId`, `@P3AplicarPromociones`, descuentos, IVA, recordsets, bloqueos, hash histórico y registro de promociones. Se agregaron crédito y una huella vinculada a la bodega para contado. El núcleo es único; Kardex hace el descuento global y su espejo aplica el local en la misma transacción. Las transferencias internas solo cambian ubicación/tránsito y no inventan movimientos globales.

Las migraciones nuevas 70–78 y 80–89 utilizan una autorización de laboratorio ligada a servidor y DB_NAME mediante `dbo.P3_INT_Destino()`. La 95 rechaza con error el DDL fuera del laboratorio autorizado en lugar de retornar silenciosamente. Se corrigieron versiones binarias en respuestas de perfiles de crédito y consultas mediante conversión explícita a BINARY(8) antes de hexadecimal. Este defecto se detectó con SQL real y se verificó por HTTP real.

No se modificaron las migraciones históricas, 41–44 ni 60–63. No hubo force-push, eliminación de ramas de Dylan ni escrituras en `SecureFinanceERP`, demostraciones anteriores o `SecureFinanceERP_Lab_Dylan`.

## Contrato de ventas

| Origen y modalidad | Promociones nuevas | Resultado |
| --- | --- | --- |
| Venta normal, contado o crédito | Desactivadas/activadas | Permitido; con activadas se registra la aplicación real |
| Venta normal desde bodega, contado o crédito | Desactivadas/activadas | Permitido; stock local y global se descuentan una vez |
| Cotización convertida, contado o crédito, global o bodega | Desactivadas | Permitido; precios y descuentos pactados |
| Cotización convertida | Activadas | Rechazo 57111; sin reevaluar promociones |
| Contado con plazo o cuotas de crédito | Cualquiera | Rechazo 57002 |
| Misma referencia con otros datos/modo/bodega | Cualquiera | Rechazo; nunca una segunda factura |
| Crédito sin permiso, perfil, disponible o plazo válido | Cualquiera | Rechazo sin efectos parciales |
| Bodega sin existencia, versión obsoleta o contexto ajeno | Cualquiera | Rechazo/rollback; no se usa stock global como sustituto |

Se conserva `@P3AplicarPromociones` en su posición histórica y se añaden al final `@P3Credito`, `@P3PlazoDias` y `@P3NumeroCuotas`. Las rutas de Créditos y Multibodega facturan cotizaciones; la combinación de promoción nueva con crédito directo también está implementada en el procedimiento SQL y probada, pero no añade un selector nuevo a la mesa de facturación. Una factura al crédito crea una cuenta por cobrar sin MovimientoCaja por el total. Los abonos generan sus propios recibos reales de caja.

## Migraciones inequívocas

`database/integracion-manifest.json` es la lista exacta y contiene SHA-256 normalizados para Windows/Linux. No ejecutar por orden alfabético todos los archivos SQL.

1. Base histórica: cuerpo de `SecureFinanceERP_Full.sql`, 15–26, 30–44 y 60–63. El constructor de laboratorio adapta solamente el destino en memoria.
2. `integration/00_AutorizacionLaboratorio.sql` (bootstrap nuevo, fuera de los rangos de módulos).
3. 70, 71, 72, 73, 74, 75, **76 adaptada**, 77, **78_AjustesConsultas**.
4. 80, 81, 82, 83, **84 adaptada**, **85 adaptada**, 86, 87, 88, **89_Complementos**.
5. 90, 91, 92, 93, 94, **95 adaptada**. Después se concede al escritor interno únicamente EXECUTE del helper de autorización.

El grupo 2–5 se instala dentro de una sola transacción y conexión, abortando al primer error. Las referencias de procedimientos a módulos instalados después se resuelven al terminar el grupo; no existe una ventana comprometida con módulos incompletos.

**Verificación, no migración:** `78_P3_CRE_Verificacion.sql`, `79_P3_CRE_PruebasSinteticas.sql`, `89_P3_BOD_Verificacion.sql` y todo `database/tests`. Los instaladores antiguos de Dylan quedan como procedencia histórica; el instalador vigente es `scripts/integracion/install.cjs`.

70 y 80 crean estructura una sola vez; 88 toma el snapshot una sola vez. 90 no debe reaplicarse después de evolucionar su política en 93. El instalador registra versión y hash del manifiesto: con el mismo hash omite el grupo; ante otro hash exige revisar una actualización. `reapply.cjs` contiene exclusivamente las definiciones repetibles revisadas durante esta integración; no es un actualizador universal para futuros cambios.

## Evidencias ejecutadas

Laboratorio de pruebas e instancia web: `SecureFinanceERP_P3_PRO_20261029074958_097701fa`, servidor `9U8ICS2VLMRUE`. URL: http://127.0.0.1:3107. Node 24.14.0, npm 11.9.0.

- `npm.cmd run check`: sintaxis de módulos existentes y nuevos.
- `npm.cmd test`: 236 aprobadas, 0 fallos, 0 omitidas.
- `git diff --check`: sin errores de espacios.
- Créditos: 24 escenarios SQL, incluyendo factura Q2,000 → abono Q500 → saldo Q1,500 → abono Q1,500 → Q0, cuotas, morosidad, permisos y rechazo de sobreabonos.
- Multibodega: 100 → despacho de 5 → origen 95/tránsito 5 → recepción destino 5/tránsito 0; reintentos, estados, ocho rechazos, costo ponderado y rollback.
- Concurrencia real en conexiones separadas: Créditos C1–C3 y Multibodega C1–C4, más conciliación sin diferencias.
- Integraciones F1–F6: venta, devolución apta/defectuosa, notas de crédito, Kardex global/local y auditoría DML.
- DDL: seis tipos reales CREATE/ALTER/DROP TABLE/PROCEDURE y texto exacto de EVENTDATA, con rollback de los objetos sintéticos de prueba. SELECT directo del texto por el login web rechazado (229). Autorizaci?n revocada: el DDL falla con 54993, el objeto no existe y el rollback restaura la autorizaci?n.
- Promociones: 29 grupos SQL incluyendo reintentos, concurrencia, importes pactados, permisos y rollback. Su reaplicación instala 63+76 dentro de la misma transacción para no degradar el contrato.
- UC09: 27 grupos SQL, vigencia tras espera, documento ajeno, idempotencia y huella de registros anteriores. Esta corrida parte del contrato integrado; **no acredita una nueva venta emitida antes de instalar la 43**. El puente de pruebas usa UTF-8 explícito.
- Matriz: ocho combinaciones SQL de crédito/promoción/bodega; ingreso de contado o cuenta por cobrar según modalidad, stock −1 e idempotencia; dos comprobaciones adicionales de rechazo.
- Chrome real: 29 comprobaciones; seis páginas × 1366/768/390/320 px sin desbordamiento horizontal; login SQL y sesiones reales, actualización de perfil y abono Q50 con recibo, consulta de Auditor y denegación de escrituras con CSRF válido. Capturas en `evidencias/chrome`. No se sustituyó autenticación ni servicios por mocks.
- CHECKDB y CHECKCONSTRAINTS sin errores; conciliación global/local/tránsito sin diferencias en los controles ejecutados.

Los archivos de `evidencias/` corresponden a esta integración. Las evidencias originales dentro de las carpetas de Dylan son históricas y no se presentan como nuevas ejecuciones. `fresh-install.json` documenta además una instalación final desde cero y su segunda ejecución segura en otro laboratorio nuevo.

## Seguridad y alcance pendiente

El laboratorio y su login son nuevos, con datos sintéticos. El estado local `.data/promociones-lab.json` contiene credenciales efímeras y está ignorado por Git. No publicarlo. El texto DDL solo se sirve mediante procedimientos con permiso `AUDITORIA_DDL_CONSULTAR` para Administrador/Auditor; la tabla tiene DENY al usuario web y el escritor interno no tiene login ni roles.

No hay instalación productiva autorizada ni trigger instalado en `SecureFinanceERP`. Para una futura fase productiva: respaldo verificado, ensayo en una copia independiente autorizada, revisión de permisos y política de retención/redacción del SQL sensible, ventana de despliegue y actualización explícita de la política que hoy solo permite laboratorios. La captura DDL comparte la transacción del evento: los intentos revertidos no quedan registrados. La sesión web usa MemoryStore existente; no se acredita aquí preparación de infraestructura productiva.

**Órdenes de compra Parte III (Módulo 2) sigue planificado en la base recibida.** No se creó una pantalla ficticia: Compras mantiene proveedores y las recepciones existentes, incluidas las de Multibodega. Esta integración completa los tres módulos de Dylan y conserva las seis áreas, pero no afirma que un módulo de órdenes de compra ajeno a estos PR esté implementado.

Ver [INSTALACION_Y_DEMO.md](INSTALACION_Y_DEMO.md) para instalar en otra computadora y demostrar el sistema.
