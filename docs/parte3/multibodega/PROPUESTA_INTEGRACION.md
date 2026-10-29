# Propuesta De Integracion Mod5

**Pendiente de revision escrita de Kenneth antes de cualquier despliegue.** Implementacion preparada por instruccion expresa del usuario, no aprobacion atribuida al integrador. No se modifico ningun procedimiento, trigger o archivo historico compartido. El nuevo trigger de 84 y la valoracion ponderada de 85 sobre Producto son extensiones propias de comportamiento compartido y requieren revision. Nada fue ejecutado en SQL Server.

## Punto De Extension

Fuente revisada: contratos de Parte III, 17/18/21 para Kardex, 34 para recepciones, 41/43 para cotizaciones e inmutabilidad. Se preservan firmas y contenido de `sp_RegistrarMovimientoKardex`, `sp_ProcesarVentaTransaccional`, `sp_ERP_ProcesarVenta`, `sp_ConvertirCotizacionAFactura`, TVP y triggers de auditoria/devolucion existentes.

84 crea `dbo.P3_BOD_EspejoKardex AFTER INSERT ON dbo.Kardex_Inventario`. Su trabajo es reflejar el efecto del evento global NUEVO en el stock y ledger locales. El global ya fue modificado por el SP central. No actualiza Producto, no vuelve a registrar el movimiento global, no altera triggers existentes ni establece orden de triggers. Se ignora APERTURA porque la distribucion inicial procede del snapshot de 88.

Tipo desconocido no se descarta. Bodega explicita invalida/inactiva no cae a la central. Contexto ausente usa `P3_BOD_Configuracion.CentralId`. Contexto presente debe ser INT positivo; un texto convertible no se acepta silenciosamente. Las cantidades se procesan por producto/KardexId, con saldos intermedios y sumas BIGINT. Los errores revierten la transaccion que origino la insercion, incluidos factura, caja, recepcion y devolucion si corresponde.

## Contexto Y Propiedad

Clave unica: `SESSION_CONTEXT(N'P3_BOD.BodegaId')`. No se tocan las claves ParteII.Actor/Operacion/Motivo ajenas desde el trigger. El actor del espejo procede de la fila Kardex, no de texto enviado por web; se revalida contra RBAC SQL.

Los wrappers compra/contado se invocan con contexto BOD nulo. Si existe, abortan SIN sobreescribirlo ni limpiarlo: el propietario externo debe resolverlo. Una vez tomado el contexto propio, se limpia tanto antes de confirmar como en CATCH despues del rollback. No usar `read_only=1`. El error puede revertir toda la transaccion externa; no continuar con ella.

Credito: llamar exactamente al public `P3_CRE_ConvertirCotizacionCredito` con ActorUsuarioId, CotizacionId, OperacionId, PlazoDias, NumeroCuotas y BodegaId. Mod5 no instala credito ni altera su motor. Para esta rama el contexto sigue nulo al delegar: el public de Creditos debe tomarlo y limpiarlo en ambas rutas, usar esa bodega para el egreso real, preservar el precio pactado, cerrar la cotizacion y NO crear caja de contado. Mod5 tambien limpia la clave al salir. Esta compatibilidad NO se ha probado contra el worktree paralelo.

Los procedimientos internos no se conceden directamente a la aplicacion; ownership chaining del propietario dbo permite los llamados internos sin conceder DML global. No se usa EXECUTE AS OWNER para saltar RBAC funcional.

Revision cruzada recibida: Creditos 76/77 invocan `dbo.P3_BOD_ValidarBodegaVenta @ActorUsuarioId INT,@BodegaId INT`. 81 ahora define EXACTAMENTE esa firma: `P3_BOD_Autorizar` con BODEGAS_CONSULTAR, ID positivo y bodega activa; sin recordsets, cambios de stock, locks de Producto ni locks de ubicacion retenidos. 87 no le concede EXECUTE app y lo deniega directamente; se usa desde modulos dbo. El espejo realiza bloqueos/validacion finales. 89 comprueba existencia y ambos parametros INT. Este contrato procede de la revision comunicada; no se leyo ni modifico el worktree de Creditos.

Para auditar la valoracion, compra conserva las tres claves ParteII.Actor/Operacion/Motivo previas. Despues de que 34 retorna y limpia sus claves, el wrapper establece actor/UUID/motivo para su UPDATE de PrecioCosto y restaura los valores anteriores tanto en exito como en error. No deja el actor del ajuste de costo contaminando el pool.

## Idempotencia Y Concurrencia

El libro propio conserva carga y actor incluso si el motor heredado tiene su propio libro. No se cambia una huella historica ni se adopta un UUID que ya corresponda a una venta/recepcion heredada. El resultado BOD de un reintento es el mismo JSON persistido, no una reconstruccion con el catalogo actual. La consulta de referencia solo muestra filas del actor autorizado.

Los escritores BOD serializan UUID por application lock. TRANSFERENCIAS bloquean Producto global antes de ubicaciones y cabecera de transferencia; no leen ni bloquean cotizacion/credito. Preparar no reserva. Despachar exige PREPARADA y version exacta; recibir exige DESPACHADA y version exacta. Los indices unicos de ledger impiden duplicar fase o Kardex reflejado. Stock y transito quedan en la misma transaccion. El ledger local y el libro son inmutables; las mutaciones propias documentales agregan INSERT/UPDATE a Bitacora_Transacciones, respetando su CHECK existente. No se simulan operaciones DDL en esa bitacora.

**Correccion del ciclo detectado en conversion:** se eliminaron AMBOS bucles de prelocks Producto/locales y el chequeo anticipado de stock de `P3_BOD_ConvertirCotizacion`. Tras resolver el replay BOD se valida solamente la bodega mediante el helper y se delega. El orden de la conversion es el del core: cotizacion -> credito si aplica -> productos -> stock local del espejo. No se adquiere Producto antes de entrar a un converter que necesita cotizacion/credito, ni se rechaza por stock local antes del replay del core. Las transferencias no esperan cotizaciones/creditos, por lo que no introducen la arista inversa.

**Pendiente de ensayo, no garantia global:** probar converter directo versus wrapper con misma cotizacion/UUID, replays con stock local ya consumido y modalidad credito. Compra requiere Product bloqueado para leer el costo anterior antes de llamar 34; 34 toma recepcion/proveedor en su propio orden. Las combinaciones con recepcion heredada directa siguen en la matriz de riesgos y no se declara ausencia universal de deadlocks. No se cambia 34/43/70 aqui. Cualquier extension adicional de contratos compartidos debe tener UN propietario y migracion del rango autorizado.

## Costo De Compra

Comportamiento verificado EN FUENTE de 34: `sp_RegistrarRecepcionCompra` guarda CostoUnitario en DetalleRecepcionCompra y llama una sola vez al Kardex central. NO actualiza PrecioCosto ni calcula promedio ponderado. 34 queda intacto. La extension de 85 esta ahora IMPLEMENTADA como SQL preparado, pendiente de revision de Kenneth y NO ejecutada.

El wrapper, SOLO en primera ejecucion del UUID, lee StockAnterior GLOBAL y PrecioCostoAnterior con UPDLOCK/HOLDLOCK del mismo Producto. StockAnterior incluye transito, no solo la bodega de ingreso. Con costo conocido y stock cero toma ese costo; con stock positivo exige costo previo no NULL y no negativo. No inventa costo cero para datos desconocidos.

```text
CostoPromedio = (StockAnterior * CostoAnterior + Cantidad * CostoUnitario)
                / (StockAnterior + Cantidad)
100 @ 20.00 + 25 @ 30.00 = 125 @ 22.00
```

Los importes parciales usan DECIMAL(30,2) y centavos DECIMAL(31,0). Los limites de entrada INT y DECIMAL(19,2) caben en esos intermedios. El cociente entero y resto de centavos aplican mitades hacia arriba SIN redondear antes una division DECIMAL de escala limitada. Se comprueba suma de stock <= INT_MAX y centavos finales <= 999999999999 (DECIMAL(12,2)), incluida una subida por redondeo. Un inicial fuera de rango o costo previo desconocido con stock positivo produce 58008 y rollback total; HTTP emite un mensaje seguro 400.

Se llama 34 UNA vez con el costo unitario ORIGINAL. Despues se actualiza SOLAMENTE PrecioCosto si el resultado conocido difiere del valor almacenado. No se cambia Stock ni se llama Kardex de nuevo. La misma transaccion contiene recepcion, Kardex/espejo, costo, auditoria y libro. Replay no vuelve a leer ni calcular costo: devuelve el JSON conservado aunque el costo actual haya cambiado despues.

Antes del UPDATE de costo, todavia bajo el bloqueo de Producto, se exige Stock=StockAnterior+Cantidad. Esto tambien evita adoptar/valorar por segunda vez un replay NATIVO si un flujo heredado gano el UUID despues de la primera comprobacion del libro. El stock lo debe haber escrito 34; esta guarda no vuelve a modificarlo. El ensayo real de esa carrera sigue pendiente.

Costo de recepcion desconocido: conservar PrecioCosto, no calcular promedio y no valorar las unidades nuevas. El recibo expresa `CostoPromedio:null`, `CostoPromedioAplicado:false`, `PoliticaCosto:"SIN_COSTO_RECEPCION"`, ademas de `PrecioCostoResultante` como cadena/null. Mantener un costo anterior no prueba valoracion completa del inventario. Costo conocido usa `INICIAL` o `PONDERADO`, promedio como cadena y boolean true. Un 0.00 explicito es costo conocido, no NULL.

Auditoria en dos niveles: DetalleRecepcionCompra conserva Cantidad/CostoUnitario documental, y el registro nativo de recepcion/Kardex conserva su identidad. El UPDATE adicional solo de PrecioCosto dispara el trigger DML existente de Producto con valores antes/despues, actor, UUID y motivo del wrapper. El UPDATE de Stock hecho por el core tambien conserva su auditoria normal: varios eventos auditados no son varios ingresos. Si el promedio coincide, no se fuerza un UPDATE de costo innecesario; el recibo conserva la politica aplicada. No se agregan costos a eventos antiguos ni se reescriben documentos de recepcion.

## Condiciones De Aceptacion

1. Aprobar/ajustar por escrito espejo, costo ponderado, helper compartido de validacion, nombres de permisos, snapshot y contexto raiz.
2. Validar instalacion atomica en la base EXACTA autorizada, con escritores detenidos y respaldo restaurable.
3. Ejecutar scripts SQL preparados y matriz concurrente. Comparar hashes/firmas de objetos compartidos antes/despues.
4. Probar compra 100@20+25@30, cero stock, costo desconocido, overflow/redondeo, replay y doble evidencia de costo; venta contado, cotizacion congelada, devolucion, ajustes, APERTURA ignorada, multirow y credito opcional con permisos reales.
5. Confirmar que el origen insuficiente revierte TODO el motor heredado, y que resultados inciertos conservan UUID/carga sin compensaciones automaticas.
6. Registrar resultados reales, pool/timeout/cancelacion y capturas de UI; solo entonces considerar despliegue posterior autorizado.
