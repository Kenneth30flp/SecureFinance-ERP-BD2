# Parte II Edward: devoluciones, notas de crédito y garantías

Implementación en feature/edward-posventa-parte2. Stack existente Node 24, Express, EJS y SQL Server. No se modifican migraciones históricas ni archivos de José. La entrega no aplica cambios a la base operativa y no hace merge.

## Instalación y arranque

1. En una base propia con Parte I y migraciones 15–23, el DBA aplica en orden 24_Edward_Devoluciones.sql, 25_Edward_Garantias.sql y 26_Edward_ConsultasPermisos.sql. Seleccionar explícitamente la base; usar sqlcmd -b o SSMS con :ON ERROR EXIT y detenerse al primer error. No ejecutar Full en una base existente.
2. Ejemplo: sqlcmd -S <instancia> -E -C -b -d <base_propia> -i database/24_Edward_Devoluciones.sql. Repetir con 25 y 26. La instalación de laboratorio verifica repetibilidad.
3. Asignar explícitamente permisos de negocio a los roles responsables con el administrador/DBA. La migración crea códigos y permisos EXECUTE de la cuenta securefinance_app; no asigna roles a todos los usuarios.
4. Para devoluciones: DEVOLUCIONES_CONSULTAR, DEVOLUCIONES_REGISTRAR y DEVOLUCIONES_AUTORIZAR. El registro autorizado es una sola operación atómica, no una cola de aprobaciones. Para reingreso apto también INVENTARIO_REGISTRAR, requerido por el procedimiento central.
5. Para garantías: GARANTIAS_CONSULTAR y GARANTIAS_GESTIONAR. Cerrar sesión y entrar nuevamente después de cambiar permisos. SQL siempre revalida autorización vigente.
6. npm.cmd ci; configurar .env local según .env.example, con cuenta SQL dedicada, sin publicar credenciales. npm.cmd run check; npm.cmd test; npm.cmd start. Abrir http://localhost:3000/login y usar la navegación de posventa.

Kardex requiere la apertura y habilitación documentadas por Kenneth. No ejecutar el corte ni las pruebas sobre su base operativa. Mantener nested triggers habilitado y las restricciones confiables.

## Páginas

- /devoluciones: búsqueda de factura por número, cliente original, cantidades vendidas/devueltas/disponibles, selección de varias líneas, motivo, condición, confirmación y emisión. Se conserva UUID al reintentar una petición incierta. El listado permite filtrar por período.
- /notas-credito: consulta de notas emitidas y ficha/comprobante imprimible; precios históricos, descuentos, IVA, cantidades, actor y referencias Kardex. Crédito pendiente y ausencia de reembolso se muestran explícitamente.
- /garantias: búsqueda por ticket, cliente, factura, producto; estado y período; búsqueda de factura para crear ticket; ficha, cobertura, evidencia, responsable e historial cronológico. Permite diagnóstico, transición válida y entrega. Un conflicto 409 conserva el texto del diagnóstico en pantalla para copiarlo antes de recargar.

Los formularios de escritura requieren JavaScript. Consultas, filtros y navegación funcionan con enlaces/formularios GET. Diseño oscuro del ERP, tablas desplazables, tamaños móviles, controles etiquetados, diálogo de confirmación, foco visible y mensajes accesibles. Datos de pruebas se inyectan exclusivamente en los procesos de pruebas.

## Archivos y objetos

- database/24_Edward_Devoluciones.sql: DevolucionCliente, DetalleDevolucion, DevolucionKardex, NotaCredito; sp_ProcesarDevolucionCliente; tr_DetalleDevolucion_Reingreso.
- database/25_Edward_Garantias.sql: CoberturaGarantiaVenta, Ticket_Garantia, Historial_Garantia; sp_CrearTicketGarantia, sp_ActualizarEstadoGarantia; tr_DetalleFactura_CoberturaGarantia, tr_HistorialGarantia_Auditoria, tr_HistorialGarantia_Inmutable.
- database/26_Edward_ConsultasPermisos.sql: sp_Edward_ConsultarFactura, sp_Edward_ConsultarDevoluciones, sp_Edward_ConsultarGarantias; códigos RBAC, EXECUTE y DENY de acceso directo.
- src/modules/edward/: routes.js, controllers.js, services.js, validations.js, sqlContracts.js.
- src/views/edward/: posventa.ejs, unavailable.ejs. src/public/css/edward.css y src/public/js/edward.js.
- Integración mínima en server.js y src/views/partials/navigation.ejs. package.json agrega comandos y revisión de sintaxis.
- tests/edward.test.js, tests/browser/edward.browser.js, database/tests/EdwardTests.sql, database/tests/RunEdwardTests.js.
- Contratos reales y límites analíticos en EdwardContratosIntegracion.md.

## Seguridad y consistencia

Sesión y cambio obligatorio de contraseña reutilizados. Actor tomado exclusivamente de sesión. CSRF aleatorio por sesión y comparación de tiempo constante. POST protegidos por permisos de ruta y procedimientos. Consultas parametrizadas; datos EJS escapados; no se exponen errores internos ni datos ficticios ante indisponibilidad.

La cuenta de aplicación recibe EXECUTE por objeto y DENY DML/SELECT en tablas nuevas. No se concede db_owner. La auditoría de devolución se registra dentro de su transacción; Kardex reutiliza su auditoría existente; historial de garantías produce el evento de auditoría con actor, UUID, diagnóstico y evidencia. No se duplican eventos Kardex.

Transacciones ACID con XACT_ABORT, TRY/CATCH y rollback total; integridad por PK/FK/CHECK, unicidad UUID y relación 1:1 nota/devolución, enlaces Kardex únicos. Stock solo se modifica mediante el procedimiento central. Los documentos originales y el historial de diagnóstico se conservan.

## Verificación

Comandos ejecutados y resultados finales se registran en EdwardResultadosPruebas.md. Las pruebas Node y Chromium usan servicios controlados. Las pruebas SQL utilizan conexiones reales con autenticación Windows y una base recién creada y marcada, nunca las credenciales .env.

npm.cmd run test:sql:edward crea una base nueva SecureFinanceERP_Edward_Test_<UUID> en EDWARD_TEST_SERVER (por defecto .\\SQLEXPRESS). Requiere sqlcmd y permisos DBA de laboratorio. Conserva base y evidencias temporales para inspección; no ejecuta DROP ni restaura bases ajenas. El instalador Full se adapta únicamente en memoria para esa base nueva. Las migraciones 24–26 se repiten para comprobar idempotencia de instalación. Casos A/B/C usan procesos sqlcmd separados y conexiones simultáneas.

npm.cmd run test:ui:edward usa Chrome o Edge instalado; capturas locales en .data/edward-ui. npm.cmd run test:ui mantiene íntegra la regresión visual existente.

## Límites operativos

- No se aplicaron migraciones ni asignaciones de permisos en la base operativa. El despliegue y el corte de Kardex corresponden al DBA.
- Crédito emitido no equivale a reembolso; no se implementa desembolso ni compensación sin un contrato financiero aprobado.
- Históricos sin snapshot de garantía requieren evidencia documental; no se inventa plazo ni cobertura. Una referencia de evidencia representa la verificación del operador, no una integración con documentos externos.
- No hay seriales registrados en el esquema fuente. Defectuosos quedan documentados fuera del stock vendible; no se crea un segundo Kardex o almacén ficticio.
- Las skills opcionales securefinance-ui-redesign y securefinance-art-direction no estaban instaladas; se reutilizaron vistas y estilos del repositorio.
- npm ci informó dos vulnerabilidades moderadas en dependencias existentes; no se cambiaron versiones ni lockfile como parte de este módulo.
