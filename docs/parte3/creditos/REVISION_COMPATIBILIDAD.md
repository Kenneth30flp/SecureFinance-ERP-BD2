# Revision de Compatibilidad y Matriz

Revision exclusiva de Creditos sobre 43 en `1bca099`. **SQL NO EJECUTADO**.
76 sigue PROPOSED pendiente de revision escrita de Kenneth. No se modifican
43, 39, 21, TVP, Full, Kardex ni informes de otros responsables.

## Defaults de 76 Frente a 43

La revision no se limita al hash. Tres tests Node extraen cada procedimiento
completo, proyectan exclusivamente el default `@P3Credito=0` eliminando los
sitios explicitos de la extension y comparan todos los tokens con 43. Solo
ignoran comentarios, whitespace, terminadores y AS opcional; preservan
literales y su contenido. Esto acredita igualdad del codigo fuente proyectado,
**no metadatos de SQL Server, compilacion ni equivalencia observada en SQL**.

| Contrato anterior | Regla conservada en default |
| --- | --- |
| Firmas | Parametros originales, orden, tipos, defaults y FacturaId OUTPUT; financiacion agregada al final |
| SET/transaccion | NOCOUNT, XACT_ABORT, opciones aritmeticas del motor, transaccion propia solo cuando corresponde y rollback completo en CATCH |
| Actor/contexto | Validacion de usuario activo y limpieza ParteII.Actor/Operacion/Motivo al entrar y salir del motor, tambien en error |
| Politica | Misma fn_ObtenerPoliticaVenta, limite de descuento, motivos permitidos, hasta 100 lineas unicas, cantidades positivas |
| Producto | Cliente/producto activos, precio y stock bloqueados por PK ascendente; ningun UPDATE temporal de precio |
| Pacto UC09 | P3_COT_ValidarOrigen con TVP y motivo originales; precio desde P3_COT_Detalle, expiracion y montos revalidados tras espera |
| Aritmetica | DECIMAL, descuento por linea, IVA 12% sobre neto global con ROUND y mismo orden de calculo |
| Emision | Misma Factura/DetalleFactura; trigger snapshot 39 no modificado. Identidad textual al emitir segun 39; no sustituirla por texto del pacto |
| Kardex | Una llamada central por detalle, mismo UUID interno y linea; sin otro descuento global |
| Caja contado | Un INSERT MovimientoCaja del total, incluso cero cuando una venta autorizada tiene descuento 100%; nunca crea cuenta |
| Recordsets | Motor/wrapper: cabecera y detalle con orden/tipos/strings monetarios originales. Converter: agrega metadatos CotizacionId/FacturaId/Estado/OperacionId |
| Replay | Mismas dos huellas de contado y SolicitudVentaERP; app lock ERP.Venta.UUID, JSON original, rechazo de carga distinta y validacion del vinculo UC09 |
| Cierre | Transicion ACTIVA -> PROCESADA, factura e historia/auditoria atomicas; motivos de contado identicos |

Para credito, el hash envuelve el hash anterior con plazo, cuotas y bodega.
El total definitivo ya esta incluido por lineas y precios pactados del hash
de cotizacion. Un replay identico no vuelve a crear cuenta, plan, caja o stock;
cambiar plazo/cuotas/modalidad debe fallar 54803. Se requiere permiso actual
CREDITOS_FACTURAR, y BOD valida permiso/bodega actual cuando se solicita.
Perfil/cliente luego inactivos no impiden cobrar deuda ni devolver el replay
confirmado global; si se intenta una venta nueva se rechaza. Credito de total
cero se rechaza 57005 y no hereda la excepcion de contado cero.

## Fallos Corregidos

77 borraba contexto BOD ajeno al entrar. Ahora lo rechaza antes de TRY/BEGIN y
solo limpia una clave establecida con exito por el propio modulo. La prueba
SQL preparada 21 instala su contexto sintetico 999, espera 57009, verifica que
sigue intacto y solo el harness lo retira. No se considero como prueba SQL
ejecutada. Helper BOD interno sin GRANT app: se usa EXEC estatico con cadena
dbo, no una consulta OBJECT_ID que pueda confundir metadata oculta con ausencia.

Deuda: SUM se mantiene DECIMAL(38,2). Se comprueba Deuda <= Limite antes de
reducir a DECIMAL(19,2); despues se compara Total <= Limite - Deuda. No se suma
DECIMAL(38,2) con otro decimal, evitando reduccion de escala y rechazo tardio
por overflow de conversion de una suma anomala. Administrar usa tambien SUM
ancho para rechazar un limite inferior. No se agregan constraints imposibles
de agregado entre filas: el bloqueo de Credito_Cliente y los escritores
encapsulados siguen siendo parte necesaria de la invariante. Un DBA que eluda
procedimientos requiere conciliacion, no se oculta el problema.

Caja: SUM global permanece DECIMAL(38,2) y sale en VARCHAR(40), sin conversion
a DECIMAL(19,2), sin sumar dos SUM anchos y sin calculo JS. El reporte materializa
MovimientoCaja UNION ALL recibos efectivamente abonados; no suma Factura.Total
ni vuelve a sumar el abono junto a su recibo. No modifica informes legacy.

## SQL 79 Preparado

Los INSERT de Cliente y Producto son fixtures artificiales aislados. Stock
entra por Kardex. El documento comercial se crea mediante P3_COT_Crear y la
factura mediante el converter real; no se inyecta Factura, DetalleFactura o
Cuenta. Se comprueba pacto 1785.71 + IVA 214.29 = 2000, lineas de emision,
limite inicial 5000, saldo tras abono 500 de 1500, liquidacion 1500, disponible
final 5000 y efectivo solo 2000 por recibos. La prueba no altera Precio para
simular congelacion: la independencia de precio actual todavia requiere una
prueba SQL adicional controlada y revisada por Kenneth.

| Caso | Escenario preparado | Resultado esperado, NO EJECUTADO |
| --- | --- | --- |
| 1 | Venta, perfil replay, conversion replay, abonos 500+1500 y replay antiguo | Una factura, tres cuotas, dos abonos/recibos, saldo 0 |
| 2-5 | Sobrepago, cero, negativo, otro cliente | 57006 / 57002 / 57002 / 57004 y rollback |
| 6 | Mismo UUID de abono, monto distinto | 57003 |
| 7-9 | Cupo insuficiente, cotizacion cancelada/vencida | 57005 / 54903 / 54910 |
| 10-11 | Version obsoleta, editar recibo | 57003 / 57007 |
| 12-14 | Cambiar cuotas, stock insuficiente, cuota vencida | 54803 / 52010 / estado derivado VENCIDA hasta liquidar |
| 15-16 | Perfil o cliente inactivo antes de venta | 57005 / 57004 |
| 17 | Inactivar despues de vender, replay y cobrar | Sin reconsumo y cobros permitidos hasta liquidar |
| 18-20 | Limite menor que deuda, plazo no autorizado, cambiar plazo del replay | 57005 / 57005 / 54803 |
| 21 | Contexto BOD ajeno ya establecido | 57009, clave ajena sin modificar |
| 22-23 | Total cero con descuento 100%, credito y default contado | Credito rechaza 57005; contado conserva total/caja cero y replay unico |
| 24 | Reusar UUID de credito como contado | 54803 |

## Permisos y Pendientes

| Perfil inicial | Consulta cartera/recibos/caja | Administrar | Abonar | Facturar credito |
| --- | --- | --- | --- | --- |
| Administrador | Si | Si | Si | Si, ademas COTIZACIONES_CONVERTIR y VENTAS_REGISTRAR |
| Auditor | Si | No | No | No |
| Cajero | Si | No | Si | No |
| Sin permisos | No | No | No | No |

HTTP con estas sesiones fixture y SQL revocando permiso (error simulado 54101)
se ejecutan en Node. **Matriz de permisos SQL real NO EJECUTADA**: verificar
usuarios activos y permisos actuales, no deducirlos del nombre del rol cuando
existan asignaciones personalizadas. No se crean usuarios/passwords de prueba.

Pendientes reales: ejecutar 79; comparar metadata/resultsets default contra
43 antes/despues; concurrencia mismo cliente y mismo/distinto UUID; permisos
efectivos bajo securefinance_app (incluido helper BOD sin GRANT directo),
bodega activa/inactiva y helper ausente con cero efectos; fallo de trigger BOD
y limpieza del contexto propio en exito/error; inyeccion de fallo al registrar
recibo; extremos monetarios y cupos agotados; reporte real con mezcla de
contado, credito sin cobro y abonos; independencia del precio actual;
navegador visual desktop/movil y recuperacion ensayada de respaldo.

El contrato BOD81/85 se registra desde la instruccion del usuario; no se leyo,
modifico o valido otro worktree. Nada de esta matriz certifica ejecucion SQL.
