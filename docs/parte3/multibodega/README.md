# Mod5: Gestion Multibodega

Estado de entrega: implementacion preparada en `feature/p3-dylan-multibodega`, base `1bca099`, exclusivamente en el worktree `SecureFinance-ERP-BD2-multibodega`. Sin commit, push, merge, cambios de rama, conexion SQL ni despliegue. No modifica el worktree original, Creditos, Auditoria DDL ni migraciones historicas. No se afirma cumplimiento academico del 100%: no estan disponibles el PDF academico de Parte III ni el prompt de Kenneth; se trabajaron los requisitos expresos del usuario y los contratos existentes.

## Alcance Operativo

- Ruta integrada `/multibodega`, catalogo `id:multibodega`, area Inventario. Factories inyectables en `server.js`, archivos propios en `src/modules/multibodega`, vistas EJS, CSS y JS propios. Se conserva tema, iconos y navegacion existentes.
- Directorio: alta, edicion, central predeterminada y baja logica con ROWVERSION, UUID y motivo. No hay DELETE fisico. No se permite inactivar una bodega con stock o transferencias PREPARADAS/DESPACHADAS.
- Inventario: filtro por producto/bodega, stock global/local/transito, conciliacion y KPIs. Historial y Kardex local paginados de 20 filas, fechas operativas Guatemala mediante el helper UTC existente.
- Transferencia de UN producto y cantidad entera por documento. Preparar persiste propuesta, no reserva ni mueve stock. Despachar vuelve a validar disponibilidad y version. Recibir exige despacho previo y mueve unidades al destino una sola vez.
- Detalle imprimible de solo lectura: referencia, ubicaciones, cantidad, motivo, actor, UTC y evidencia inmutable. No genera salida/entrada en el Kardex global porque no es una venta/compra.
- Formularios propios de recepcion por bodega con costo promedio ponderado y conversion de cotizacion contado/credito. Los identificadores se introducen explicitamente; no se descarga un catalogo completo ni se fabrican datos. El recibo distingue costo unitario documental, promedio aplicado y PrecioCosto resultante.

## Modelo E Invariante

`Producto.Stock` sigue representando TODO el negocio, incluido transito. Las tablas nuevas son `P3_BOD_Bodega`, `P3_BOD_Configuracion`, `P3_BOD_Stock`, `P3_BOD_Snapshot`, `P3_BOD_Transferencia`, `P3_BOD_Operacion` y `P3_BOD_Ledger`.

```text
Fase          Central  Destino  Transito  Producto.Stock
Inicial       100      0        0         100
PREPARADA     100      0        0         100
DESPACHADA     95      0        5         100
RECIBIDA       95      5        0         100
```

El transito es DERIVADO de transferencias con estado DESPACHADA, no otro contador mutable. La vista `dbo.P3_BOD_Conciliacion` expone por producto `StockLocal`, `Transito`, `Stock` y `Diferencia`. Todas las sumas de cantidades se hacen con `BIGINT`. Los escritores validan la conciliacion bajo bloqueo de Producto; las consultas web son operativas, no reemplazan un cierre con escritores detenidos o aislamiento consistente autorizado.

Las tres bodegas iniciales son datos de instalacion: Bodega Central, Tienda Z1 y Tienda Z10. Ningun procedimiento selecciona por esos nombres. El indice filtrado permite una sola `IsCentral=1`, la configuracion guarda su ID y el procedimiento administrativo mantiene ambas representaciones en la misma transaccion. Cambiar central no mueve existencias ya ubicadas.

88 toma `Producto.Stock` UNA vez con bloqueo de tabla y guarda un snapshot nuevo con UUID y fecha UTC de instalacion. No inventa compras antiguas ni inserta APERTURA global/local. Reinstalar aborta; no vuelve a repartir stock. Los productos nuevos del catalogo deben seguir naciendo con stock cero y recibir entradas mediante el motor central. No se habilita ni abre `ConfiguracionInventario` automaticamente.

## Contratos SQL Publicos

Los cinco mutadores siguientes devuelven al final un recordset de una fila `Respuesta NVARCHAR(MAX)` con JSON persistido. El servicio consume SOLO ese recibo final; los motores existentes pueden emitir recordsets previos que no constituyen confirmacion BOD. Un reintento identico devuelve exactamente el recibo conservado aunque el documento haya avanzado despues. Las consultas/autorizacion tienen sus resultados separados descritos abajo.

```sql
dbo.sp_TransferirStockBodegas
 @ActorUsuarioId INT, @OperacionId UNIQUEIDENTIFIER,
 @ProductoId INT, @OrigenId INT, @DestinoId INT,
 @Cantidad INT, @Motivo NVARCHAR(250)
-- Persiste PREPARADA. JSON: TransferenciaId, Estado, Version hexadecimal, OperacionId.

dbo.P3_BOD_AvanzarTransferencia
 @ActorUsuarioId INT, @OperacionId UNIQUEIDENTIFIER, @TransferenciaId INT,
 @Accion VARCHAR(10), @VersionEsperada BINARY(8), @Motivo NVARCHAR(250)
-- Accion DESPACHAR o RECIBIR. Mismo formato de recibo.

dbo.P3_BOD_GuardarBodega
 @ActorUsuarioId INT, @OperacionId UNIQUEIDENTIFIER, @Nombre NVARCHAR(100),
 @Activo BIT, @IsCentral BIT, @Motivo NVARCHAR(250),
 @BodegaId INT=NULL, @VersionEsperada BINARY(8)=NULL
-- Alta sin ID; edicion/baja con ID y version. JSON con datos y version resultantes.

dbo.P3_BOD_RegistrarCompra
 @ActorUsuarioId INT, @OperacionId UNIQUEIDENTIFIER, @BodegaId INT,
 @ProductoId INT, @ProveedorId INT, @Cantidad INT,
 @DocumentoRespaldo NVARCHAR(100), @Motivo NVARCHAR(250),
 @CostoUnitario DECIMAL(19,2)=NULL
-- JSON: RecepcionId como cadena, OperacionId, BodegaId,
-- CostoUnitario, CostoPromedio, PrecioCostoResultante como cadenas/null,
-- CostoPromedioAplicado BIT/boolean y PoliticaCosto.

dbo.P3_BOD_ConvertirCotizacion
 @ActorUsuarioId INT, @CotizacionId INT, @OperacionId UNIQUEIDENTIFIER,
 @BodegaId INT, @Credito BIT=0, @PlazoDias INT=NULL, @NumeroCuotas INT=1
-- JSON: CotizacionId, FacturaId, Estado, BodegaId, Credito, OperacionId.

dbo.P3_BOD_Autorizar @ActorUsuarioId INT, @Permiso NVARCHAR(100)
-- Sin resultset: base exacta, usuario activo y permiso SQL vigente.

dbo.P3_BOD_Consultar
 @ActorUsuarioId INT, @Seccion VARCHAR(15), @BodegaId INT=NULL,
 @ProductoId INT=NULL, @TransferenciaId INT=NULL, @Desplazamiento INT=0,
 @Desde DATETIME2(3)=NULL, @Hasta DATETIME2(3)=NULL
-- Seccion bodegas/inventario/transferencias/kardex/detalle.
-- Primer set: hasta 21 filas (adelanto de pagina). Inventario: segundo set KPIs.
-- Detalle exige ID; segundo set: ledger de la transferencia.

dbo.P3_BOD_ConsultarOperacion @ActorUsuarioId INT, @OperacionId UNIQUEIDENTIFIER
-- Solo operaciones del actor: OperacionId, Respuesta, FechaHora. Sin fila si no es visible.
```

Helpers sin ejecucion directa para la aplicacion: `P3_BOD_ValidarBodegaVenta`, `P3_BOD_Reintento`, `P3_BOD_BloquearUbicaciones` y `P3_BOD_ValidarSaldo`. Vista: `P3_BOD_Conciliacion`. Triggers nuevos: `P3_BOD_EspejoKardex`, `P3_BOD_LedgerInmutable`, `P3_BOD_OperacionInmutable`, `P3_BOD_SnapshotInmutable` y `P3_BOD_TransferenciaIdentidad`. Restricciones e indices explicitos usan tambien el prefijo reservado. La unica excepcion de nombre es el procedimiento academico obligatorio `sp_TransferirStockBodegas`.

```sql
dbo.P3_BOD_ValidarBodegaVenta @ActorUsuarioId INT, @BodegaId INT

dbo.P3_BOD_Reintento
 @ActorUsuarioId INT, @OperacionId UNIQUEIDENTIFIER,
 @Carga NVARCHAR(MAX), @Respuesta NVARCHAR(MAX) OUTPUT

dbo.P3_BOD_BloquearUbicaciones
 @ProductoId INT, @OrigenId INT, @DestinoId INT

dbo.P3_BOD_ValidarSaldo @ProductoId INT
```

Los helpers de ubicaciones/saldo requieren que el escritor ya tenga el bloqueo de Producto. `P3_BOD_ValidarBodegaVenta` es el contrato interno requerido por Creditos 76/77 segun la revision cruzada: valida BODEGAS_CONSULTAR vigente e ID activo, no emite recordsets ni modifica stock y no retiene locks de ubicacion antes de entrar al core. No tiene GRANT app; 87 deniega ejecucion directa y los modulos dbo lo llaman por ownership chaining. 89 comprueba sus dos parametros INT. No se inspecciono ni modifico el worktree de Creditos.

## Seguridad Y Reintentos

- HTTP obtiene actor SOLO de `req.session.usuario.usuarioId`. CSRF de 32 bytes propio del flujo, comparacion constante, encabezado `X-CSRF-Token`. No reutiliza tokens de otras pantallas. GET no realiza mutaciones de negocio.
- Permisos de sesion filtran UI/HTTP. Cada peticion autorizada consulta de nuevo SQL; cada SP mutador vuelve a validar RBAC dentro de su transaccion. Usuario/rol/permiso deben estar activos. Agregar permisos requiere renovar la sesion si esta no los contiene.
- Permisos nuevos: BODEGAS_CONSULTAR, BODEGAS_ADMINISTRAR, TRANSFERENCIAS_CREAR, TRANSFERENCIAS_DESPACHAR y TRANSFERENCIAS_RECIBIR. 87 asigna los cinco al Administrador y solo consulta al Auditor. No concede permisos globales existentes, DML directo, db_owner ni ejecucion de todos los SP.
- Libro inmutable por UUID conserva actor, carga JSON completa y respuesta. Compara bytes, no solo hash. La carga incluye fase, ID, version, cantidades, motivo, bodega/modalidad/plazo/cuotas/costo segun flujo. Un UUID de compra/venta heredada no se adopta silenciosamente en el wrapper BOD.
- `sp_getapplock` serializa el UUID antes de tocar datos del negocio. TRANSFERENCIAS: Producto global primero, ubicaciones deterministas y cabecera de transferencia al final; nunca tocan cotizacion/credito. CONVERSION: el wrapper no prebloquea Producto/locales ni comprueba stock; delega al core el orden cotizacion -> credito (si aplica) -> productos -> espejo local. El helper solo valida bodega y el espejo impone la validacion final atomica. El replay BOD se resuelve antes de ese helper; no se rechaza por disponibilidad local antes de que el core pueda resolver su replay. Administracion infrecuente conserva TABLOCKX de Producto antes de bodegas.
- Se conserva transaccion externa en exito. En error se admite rollback de TODA la transaccion externa, como los motores existentes. El llamador no debe continuar ni confirmar trabajo previo tras ese error.
- Frontend persiste UUID, version y carga en sessionStorage ANTES del POST; bloquea doble clic y campos; un resultado incierto no crea otra referencia ni se reenvia automaticamente. Restaurar la pagina conserva esa misma carga. El reintento exige accion manual y confirmacion; la consulta de referencia es de solo lectura y no prueba fallo si no hay registro. Se puede iniciar otra solicitud explicitamente solo tras confirmacion o rechazo seguro 400/403/404.
- sessionStorage es por pestana, no respaldo durable ni mecanismo RBAC. No cerrar la pestana ante incertidumbre; conservar UUID. Si almacenamiento no funciona se bloquea la escritura. Las operaciones no se almacenan en localStorage compartido entre usuarios.
- EJS escapa texto; JS usa nodos de texto, no HTML de respuestas. Costos viajan como cadenas decimales hasta SQL: RPC VARCHAR tipado convertido por SQL al parametro DECIMAL(19,2), sin parseFloat/Number financiero. Version viaja como hexadecimal de 16 caracteres y llega como BINARY(8).
- Errores HTTP son mensajes controlados, nunca `error.message` de SQL. Fallas no reconocidas se presentan como 503 incierto. No se oculta un conflicto ni se afirma exito antes del recibo final.

## Integracion Compartida

Leer [PROPUESTA_INTEGRACION.md](PROPUESTA_INTEGRACION.md) ANTES de desplegar. El espejo de 84 y la extension de costo de 85 sobre Producto son propuestas pendientes de revision escrita de Kenneth. No se atribuye aprobacion ni ejecucion; ningun archivo historico ni procedimiento compartido se edita.

Se preservan los procedimientos originales de Kardex/venta/cotizacion, sus triggers y todos los archivos 17/18/21/34/43. El trigger nuevo refleja COMPRA, VENTA, ajustes y DEVOLUCION, ignora solo APERTURA y rechaza tipo desconocido, bodega invalida/inactiva, falta de permisos o saldo local insuficiente. Bloquea todos los productos en orden ascendente y procesa filas por ProductoId/KardexId; no reduce a un saldo neto que esconda un saldo intermedio negativo. Un fallo revierte tambien la factura/compra/caja original. NUNCA actualiza Producto.Stock ni PrecioCosto.

SESSION_CONTEXT `P3_BOD.BodegaId` selecciona ubicacion; sin contexto usa la central configurada para flujos heredados. Los wrappers son propietarios raiz, rechazan un contexto ya ocupado sin borrarlo, establecen/limpian el propio contexto en exito/error. No usar contexto read_only. Credito recibe la bodega por el contrato publico acordado y es propietario de su contexto raiz; Mod5 no modifica ni instala Mod4.

34 guarda costo unitario documental y NO hace promedio ponderado ni cambia PrecioCosto. Ahora el wrapper de 85 agrega esa valoracion sin editar 34: toma StockAnterior GLOBAL (incluye transito) y PrecioCostoAnterior bajo el mismo UPDLOCK/HOLDLOCK, calcula el promedio, llama 34 UNA vez con el CostoUnitario ORIGINAL y despues actualiza SOLO PrecioCosto si cambia. No llama Kardex otra vez ni escribe Stock. Replay devuelve el recibo persistido sin recalcular ni actualizar costo.

Con costo conocido y stock cero se usa el nuevo costo (`INICIAL`); con stock positivo se exige costo previo conocido (`PONDERADO`). Costo previo NULL no se transforma en cero: rechaza 58008. El numerador se calcula con DECIMAL; cociente/resto en centavos aplica mitades hacia arriba exactamente, sin un redondeo intermedio de la division SQL. Se comprueban Stock INT y costo final DECIMAL(12,2), incluidos los desbordamientos posteriores al redondeo. El caso preparado es 100@20 + 25@30 = 125@22.

Con CostoUnitario NULL se conserva PrecioCosto sin asignar valor a las nuevas unidades: `CostoPromedio=NULL`, `CostoPromedioAplicado=false`, `PoliticaCosto=SIN_COSTO_RECEPCION`. `PrecioCostoResultante` muestra el valor conservado, no un promedio actualizado ni garantia de valoracion completa. Un costo explicito 0.00 es distinto de desconocido. La recepcion/detalle inmutable conserva el costo documental; el trigger DML original de Producto audita el cambio de PrecioCosto con actor/operacion/motivo cuando cambia. Son evidencias distintas, no una segunda entrada de stock. El wrapper restaura ParteII.Actor/Operacion/Motivo anteriores en exito/error despues de usarlos para esa auditoria.

La conversion contado llama `dbo.sp_ConvertirCotizacionAFactura`; no replica el motor de precios pactados. Credito llama opcionalmente:

```sql
dbo.P3_CRE_ConvertirCotizacionCredito
 @ActorUsuarioId INT, @CotizacionId INT, @OperacionId UNIQUEIDENTIFIER,
 @PlazoDias INT, @NumeroCuotas INT=1, @BodegaId INT=NULL
```

## Instalacion Preparada

**No ejecutar ahora.** No hay conexion SQL funcional con cadena TLS confiable; no se intento conectar, aceptar certificados ni desactivar cifrado. El administrador debe corregir la confianza de certificados fuera de este cambio y autorizar una validacion futura.

1. Obtener aprobacion escrita para el espejo 84, la extension ponderada 85 y el contrato de Creditos si se va a probar esa modalidad. Revisar hashes de procedimientos/triggers compartidos antes/despues; este rango no altera sus definiciones.
2. Usar una copia aislada llamada EXACTAMENTE `SecureFinanceERP_Lab_Dylan`, con esquema hasta 43, usuario SQL de aplicacion y roles Administrador/Auditor existentes. No ejecutar Full ni seeds de seguridad sobre la base original. Definir respaldo recuperable y probar restauracion en otra copia antes de cualquier despliegue.
3. Detener todos los escritores. Preparar explicitamente `database/tests/P3_BOD_Fixture100.sql` ANTES de instalar: crea un proveedor y dos productos sinteticos, uno con 100 unidades a costo 20 y otro con stock cero/costo NULL; no crea usuarios ni claves. El DBA proporciona `SESSION_CONTEXT(N'P3_BOD.TestActor')` en esa conexion. Nunca modifica un producto existente.
4. Revisar y, solo con autorizacion futura, usar `database/tests/P3_BOD_InstallLab.sql` en modo SQLCMD desde `database/`, con conexion previamente aprobada. No se incluye cadena de conexion ni credenciales. `:ON ERROR EXIT` aborta al primer fallo. UNA conexion, UNA transaccion externa a traves de TODOS los GO; cada archivo 80..89 vuelve a comprobar nombre exacto y transaccion activa. No seleccionar batches sueltos ni confirmar parcialmente. La desconexion tras fallo revierte lo pendiente.
5. Orden: 80 estructura; 81 helpers/inmutabilidad; 82 transferencias; 83 bodegas; 84 espejo; 85 wrappers; 86 consultas; 87 permisos; 88 snapshot unico; 89 verificacion. Un error se investiga con los escritores detenidos; no se intenta reinstalar encima ni borrar historia.
6. 89 verifica central, snapshot, restricciones, espejo y auditoria compartida. Confirmar permisos efectivos con la cuenta de aplicacion, reiniciar sesion y consultar conciliacion. Conservar respaldo, version, fecha y salida real, sin secretos.
7. La apertura/habilitacion global de 21 sigue siendo una accion DBA SEPARADA y aprobada. Mod5 no la hace. Si esta deshabilitada, las transferencias locales funcionan, pero ventas/recepciones centrales siguen bloqueadas por el contrato existente.
8. Recuperacion: ante error ANTES del COMMIT, rollback/cierre de la conexion externa. Despues del COMMIT, no existe down destructivo automatico: detener escritores, respaldar evidencia y restaurar la copia probada o aplicar una correccion incremental revisada. No eliminar ledger, reaplicar snapshot ni desactivar el espejo dejando ventas activas.

## Pruebas Y Evidencia

[VALIDACION.md](VALIDACION.md) separa pruebas realmente ejecutadas de scripts preparados y enumera la matriz de concurrencia pendiente. `npm test` descubre `tests/multibodega.test.js` automaticamente sin cambiar dependencias ni package-lock.

## Explicacion Para Exposicion

El inventario global responde cuantas unidades son del negocio; el local responde donde estan. Un despacho no vende ni elimina cinco unidades: las saca de una ubicacion y las deja pendientes de recepcion. Por eso el total permanece cien. Recibir cambia la ubicacion de esas cinco, no vuelve a ingresarlas al negocio. La propuesta no reserva stock, por lo que se valida otra vez al despachar.

ROWVERSION evita confirmar sobre un estado que otro operador cambio. El UUID evita duplicar una operacion si la respuesta de red se pierde; no sustituye permisos ni CSRF. Guardar carga y respuesta permite distinguir un reintento de una solicitud diferente. El trigger refleja solo eventos nuevos del motor central y participa de su transaccion: si una venta intenta consumir transito o stock de otra bodega, se revierte todo. El snapshot no es una compra: solo documenta donde empieza la distribucion desde la fecha de instalacion.

## Limites Explicitos

- SQL preparado pero NO compilado ni ejecutado contra SQL Server. Ninguna prueba concurrente SQL real ni captura de navegador real se declara realizada.
- Espejo y extension ponderada pendientes de revision de Kenneth. La integracion opcional de Creditos requiere comprobar firma, contexto, permisos, caja y cierre de cotizacion reales, sin acceder a ese worktree aqui.
- Se retiro el ciclo concreto de conversion: ya no existe el prelock Producto/local antes de cotizacion/credito. Esto no demuestra ausencia total de deadlocks. Compras conserva el bloqueo de Producto para valorar y 34 tiene ordenes propios; faltan ensayos con recepciones directas y demas escritores. Un deadlock/timeout no dispara un reintento automatico.
- El ponderado esta implementado en SQL preparado, NO validado en SQL real. No se implementa cancelacion de propuestas, recepcion parcial, transferencia de multiples productos en un documento ni seleccion automatica de bodega de devolucion. Los estados exigidos son exactamente PREPARADA/DESPACHADA/RECIBIDA. Una propuesta pendiente debe resolverse antes de inactivar su bodega.
- Los flujos heredados, incluidas devoluciones, usan la central vigente si no reciben contexto; no se infiere ubicacion de facturas antiguas. No se inserta historia falsa para ocultar esta limitacion.
- Consultas operativas y KPIs pueden corresponder a instantes diferentes bajo READ COMMITTED. Para cierre/auditoria consistente usar escritores detenidos o aislamiento de snapshot previamente aprobado; los escritores validan la invariante con el bloqueo global del producto.
- Atenciones/cancelacion de lote o perdida fisica de conexion no son excepciones TRY/CATCH ordinarias de SQL Server. No reutilizar una conexion cancelada con contexto potencialmente ocupado; el wrapper lo rechaza si detecta contexto ajeno. Validar cancelacion y comportamiento del pool en laboratorio antes de produccion.
- Responsive y print tienen CSS propio y vistas renderizadas verificadas en HTTP; no equivalen a certificacion visual de 1366/1024/768/390/320 ni a prueba de accesibilidad completa.
