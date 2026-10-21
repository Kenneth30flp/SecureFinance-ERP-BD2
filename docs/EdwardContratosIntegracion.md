# Edward: contratos de integración de posventa

Migraciones: 24_Edward_Devoluciones.sql → 25_Edward_Garantias.sql → 26_Edward_ConsultasPermisos.sql, después de 15–23. No requieren servicios ni migraciones futuras de José.

## Contratos SQL de consulta

Todos validan al actor activo mediante dbo.sp_ParteII_ValidarPermiso. La cuenta SQL ejecuta procedimientos concretos; no necesita SELECT sobre tablas.

| Procedimiento | Parámetros reales |
|---|---|
| dbo.sp_Edward_ConsultarFactura | @ActorUsuarioId INT, @FacturaId INT, @Garantia BIT=0 |
| dbo.sp_Edward_ConsultarDevoluciones | @ActorUsuarioId INT, @Id INT=NULL, @Desde DATETIME2(3)=NULL, @Hasta DATETIME2(3)=NULL, @Desplazamiento INT=0 |
| dbo.sp_Edward_ConsultarGarantias | @ActorUsuarioId INT, @Id INT=NULL, @Buscar NVARCHAR(150)=N'', @Estado VARCHAR(15)=NULL, @Desde DATETIME2(3)=NULL, @Hasta DATETIME2(3)=NULL, @Desplazamiento INT=0, @SoloActivos BIT=0 |

Fechas UTC, intervalo [Desde, Hasta). La web convierte la fecha final inclusiva al inicio UTC del día siguiente. Consultas paginadas devuelven hasta 51 registros: mostrar 50 y usar el adicional para habilitar la siguiente página. Las consultas con @Id devuelven una segunda tabla con detalle o historial. @Id de devoluciones identifica DevolucionId, no NotaCreditoId.

- Factura: cabecera FacturaId, ClienteId, Cliente, NIT, FechaHora, Total; segunda tabla con DetalleFacturaId, ProductoId, Descripcion, Cantidad, Devuelto, Disponible, PrecioUnitario, DescuentoMonto.
- Devoluciones/notas emitidas: DevolucionId, OperacionId, FacturaId, ClienteId, Cliente, NIT, FechaHora, Motivo, Responsable, NotaCreditoId, Estado, EstadoCredito, Subtotal, Descuento, IVA, Total. Detalles incluyen DetalleFacturaId, cantidades, condición, precio y porcentaje históricos, importes acreditados y KardexId.
- Garantías: TicketId, DetalleFacturaId, FacturaId, ClienteId, Cliente, ProductoId, Descripcion, Estado, Cobertura, Evidencia, Motivo, ResponsableId, Responsable, FechaApertura, FechaResolucion, Version. Historial: HistorialId, EstadoAnterior, EstadoNuevo, FechaHora, Diagnostico, Responsable.
- Tickets por estado: @Estado; activos: @SoloActivos=1 (excluye ENTREGADO); período: fecha de apertura. FechaResolucion se fija al entregar.
- Importes de consulta son VARCHAR(21), producidos desde DECIMAL(19,2), para no perder precisión al pasar por JavaScript. Version es BINARY(8) en SQL y hexadecimal de 16 caracteres en el servicio.
- Para totales analíticos, José debe consumir todas las páginas o agregar un contrato autorizado propio. Una página no representa un total global. Las devoluciones no cambian la venta bruta original.

## Contratos de escritura

| Procedimiento | Parámetros |
|---|---|
| dbo.sp_ProcesarDevolucionCliente | @ActorUsuarioId INT, @FacturaId INT, @OperacionId UNIQUEIDENTIFIER, @Motivo NVARCHAR(MAX), @Detalles NVARCHAR(MAX) |
| dbo.sp_CrearTicketGarantia | @ActorUsuarioId INT, @DetalleFacturaId INT, @OperacionId UNIQUEIDENTIFIER, @Motivo NVARCHAR(MAX) |
| dbo.sp_ActualizarEstadoGarantia | @ActorUsuarioId INT, @TicketId INT, @VersionEsperada BINARY(8), @Estado VARCHAR(15), @Diagnostico NVARCHAR(MAX), @Evidencia NVARCHAR(MAX)=NULL |

Detalles es JSON: [{"DetalleFacturaId":123,"Cantidad":1,"Reingresar":true}]. Entre 1 y 100 líneas distintas, cantidades enteras positivas. La referencia UUID se conserva al reintentar. Reutilizarla con otra carga produce 54603. Respuesta de devolución: DevolucionId, NotaCreditoId. Respuesta de tickets: TicketId, Version.

Motivo se limita a 250 caracteres, Diagnostico a 2000, Evidencia a 250. SQL verifica límites además de JavaScript. 54603 representa conflicto de versión/idempotencia; 54604 referencia inexistente; 54605 exceso acumulado; 54606 transición/cobertura prohibida. 54101 es RBAC vigente.

## Integración con Kenneth

Se conserva el contrato real de sp_RegistrarMovimientoKardex:
@ProductoId INT, @TipoMovimiento VARCHAR(25), @Cantidad INT, @ActorUsuarioId INT,
@DocumentoRespaldo NVARCHAR(MAX), @OperacionId UNIQUEIDENTIFIER, @LineaOperacion INT,
@Motivo NVARCHAR(MAX), @DetalleFacturaId INT=NULL, @VersionEsperada BINARY(8)=NULL, @DevolverResultado BIT=1.

El trigger tr_DetalleDevolucion_Reingreso lo invoca con DEVOLUCION y @DevolverResultado=0. DetalleFacturaId del Kardex queda NULL: su CHECK actual solo admite referencias directas para VENTA. La trazabilidad concreta es DetalleDevolucion → DetalleFactura, y DevolucionKardex relaciona por FK cada detalle devuelto con un único KardexId. No se altera ese CHECK ni el índice único de ventas.

El actor necesita INVENTARIO_REGISTRAR para líneas aptas. Los defectuosos quedan documentados sin aumentar stock. Kardex debe estar abierto, conciliado y habilitado versión 2. No se activa automáticamente.

sp_ProcesarVentaTransaccional conserva @ClienteId INT, @UsuarioId INT, @Detalle dbo.TipoDetalleVentaDescuento READONLY, @FacturaId INT=NULL OUTPUT, @MotivoDescuento NVARCHAR(80)=NULL. El nuevo trigger de cobertura actúa solamente en detalles recién insertados.

La devolución toma UPDLOCK/HOLDLOCK sobre Factura y bloqueo de aplicación por UUID. Garantía usa ROWVERSION y bloqueo del ticket. Los procedimientos confirman solo transacciones propias; ante error revierten toda transacción activa, incluyendo la externa, igual que el contrato central Kardex. El llamador debe contemplar ese rollback completo.

## Modelo financiero y cobertura

NotaCredito se relaciona de forma única con DevolucionCliente; esta conserva FacturaId y sus líneas originales. Cliente, precios, descuentos y fecha se consultan desde las relaciones originales. No se edita Factura ni MovimientoCaja.

El IVA histórico de cabecera se distribuye mediante diferencias de cuotas acumuladas ordenadas por DetalleFacturaId. En cada devolución parcial se acreditan diferencias de importes acumulados redondeados a centavos. La última unidad recupera el residuo. La suma de notas nunca puede exceder Total original.

Estado de nota: EMITIDA. EstadoCredito: PENDIENTE. No hay reembolso registrado ni conexión de pagos. Una futura aplicación/reembolso requiere su contrato financiero y evidencia propios; no inferir que emitir crédito equivale a pagar.

CoberturaGarantiaVenta captura GarantiaMeses y vencimiento únicamente al vender después de instalar 25. NULL o ausencia de snapshot significa NO_VERIFICADA; no se usa el catálogo actual para reconstruir el pasado. La aprobación de estos casos exige referencia documental verificada, conservada y auditada. VENCIDA/SIN_COBERTURA no se pueden aprobar. Se evalúa vigencia al recibir el ticket. No se exige número de serie, porque el modelo actual no lo registra.

RECIBIDO → EN_REVISION → APROBADO/RECHAZADO → ENTREGADO. Un estado no terminal puede conservarse para agregar diagnóstico sin perder historial. ENTREGADO es terminal. ResponsableId pasa al actor que registra el seguimiento.
