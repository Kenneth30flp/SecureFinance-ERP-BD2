# Integración de facturación y Kardex — Kenneth, fase 2

## Alcance y revisión de Parte I

El commit local `cc6e734` conserva los fundamentos validados. Esta integración queda pendiente de revisión, sin segundo commit. No modifica Node, interfaz, devoluciones, garantías ni analítica.

Se revisaron las definiciones de venta en 06, 12, 13 y el instalador completo. La definición leída del servidor coincide, normalizando comentarios y espacios, con 06, 13 y Full; 12 contiene una versión histórica anterior. SHA-256 del texto vigente leído: `5f20cfbba7032a7574507e8f2868a19e8c9f51b3ec59f77a599b9d973e380355`. La migración 21 conserva sus validaciones, política de descuentos, TVP, redondeo DECIMAL, IVA 12%, comprobante y dos conjuntos de resultados. No sustituye la venta por una implementación abreviada.

## Diseño

La venta conserva bloqueos UPDLOCK/HOLDLOCK sobre productos en orden ascendente. Crea factura y detalles y llama una vez por línea a `sp_RegistrarMovimientoKardex`. Solo ese mecanismo actualiza Producto.Stock e inserta su movimiento. Después registra caja; la auditoría participa en la misma transacción. Un fallo revierte factura, detalles, stock, Kardex, caja y bitácora.

Se utiliza XACT_ABORT, TRY/CATCH y THROW. Los procedimientos abren y confirman una transacción únicamente cuando no existe una exterior. Ante error revierten toda la transacción, conservando el contrato de fallos de Parte I; un llamador no debe esperar continuar una transacción exterior fallida. La prueba I13 comprueba que una venta exitosa no confirma la transacción del llamador.

`sp_RegistrarMovimientoKardex` conserva sus parámetros anteriores; agrega `@DevolverResultado BIT=1`. La venta utiliza 0 para evitar conjuntos de resultados intermedios y preservar el contrato del backend. El actor continúa proviniendo de la sesión autenticada del backend; SQL valida RBAC. No se incorporan actores enviados libremente por el navegador.

## Apertura

`Apertura_Inventario` identifica un único corte mediante UUID, documento, responsable, fecha, cantidad de productos y límite de factura. `sp_AbrirKardexInventario` registra una línea APERTURA por producto existente, incluidos inactivos y saldos cero, sin actualizar sus existencias. Un saldo 20 produce apertura 20 y conserva Stock=20; una venta de 3 deja ambos saldos en 17.

El reintento requiere idéntico UUID, actor, documento y motivo. Una restricción única impide otra apertura por producto y un trigger impide modificar o eliminar la cabecera. No se reconstruyen movimientos históricos. El límite FacturaLimiteId impide descontar mediante Kardex una factura anterior al corte. Una apertura antigua sin ese límite conocido se rechaza explícitamente.

Las operaciones usan bloqueo de aplicación compartido `InventarioCorteParteII`; apertura y habilitación usan el exclusivo, con propietario Transaction. `sp_HabilitarKardexInventario` exige integración versión 2, apertura completa y conciliación. Instalar 21 no abre ni habilita inventario.

Productos creados después del corte empiezan con saldo cero; sus ingresos se registran por el mecanismo central. La conciliación suma aperturas y movimientos con signo y compara contra Producto.Stock. `sp_ConsultarConciliacionInventario` expone esa consulta operativa con permiso INVENTARIO_CONSULTAR.

## Seguridad e idempotencia

INVENTARIO_APERTURAR se crea sin asignarlo automáticamente a roles. La cuenta SQL de aplicación tiene prohibida la ejecución de apertura/habilitación y el acceso directo a la cabecera. No recibe actualización directa de stock. El responsable autorizado del corte requiere asignación explícita por el DBA.

La clave operación/línea protege el movimiento contra reintentos y compara su contenido. La venta comercial completa **no es idempotente**: todavía no hay una clave estable de solicitud que impida crear dos facturas. No deben añadirse reintentos automáticos de ventas con resultado incierto.

## Pruebas y reproducción

Ejecutar `node database/tests/RunKardexSalesIntegration.js --run --server localhost,1433 --trust-server-certificate` con autenticación Windows autorizada. El ejecutor crea una base nueva `SecureFinanceERP_ParteII_Test_Kardex_<uuid>`, valida contexto y marca de propiedad en cada conexión, reemplaza contextos del instalador y no elimina bases. Requiere sqlcmd y permisos administrativos exclusivamente para preparar esa base de pruebas.

Se conservan 28 casos Kenneth, cuatro complementarios y regresión histórica, antes y después de 21. Se añaden pruebas de apertura, repetición de migración, contratos de resultados, descuentos, IVA, caja, RBAC, seis fallos transaccionales, transacción exterior, idempotencia y conciliación. Dos procesos sqlcmd independientes sincronizan sus sesiones; un observador comprueba bloqueos reales mediante DMV. Se prueban la última unidad y dos productos recibidos en orden inverso.

Cada resultado y evidencia se guarda en `ParteIIKardexVentaResultados.json`; también se conservan intentos fallidos. Los primeros intentos detectaron opciones SET incorrectas en conexiones nuevas y una clave del constructor de conexión de PowerShell. Se corrigieron únicamente los ejecutores. Los logs SQL permanecen en el directorio temporal indicado por el informe; no contienen copias de datos personales de producción.

## Límites

Estas pruebas no sustituyen pruebas de carga ni un ensayo de restauración. No debe reinstalarse 06, 12, 13, 18 ni Full encima de 21: podrían reemplazar la venta integrada. La cadena de instalación debe terminar siempre en 21. La activación real requiere la ventana y verificaciones descritas en ParteIIKardexVentaActivacion.md.
