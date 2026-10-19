# Plan de activación controlada — solo documentación

Este plan no autoriza ni ejecuta cambios sobre SecureFinanceERP. No se ha realizado el corte real. No contiene eliminación de bases ni reconstrucción de hechos históricos.

1. El DBA realiza respaldo completo con comprobación de checksum y verifica una restauración en otra base autorizada. Registra versión de aplicación, scripts, permisos y saldos previos. Confirma una ventana de mantenimiento y responsables de recuperación.
2. Ejecuta las prevalidaciones 15: objetos, NIT, referencias, restricciones y versiones. Revisa permisos y el estado del libro. Un Kardex activo sin apertura reconocida, o una apertura con límite histórico desconocido, exige diagnóstico; no se fuerza su aceptación.
3. Detiene aplicación, trabajos, integraciones y escritores manuales. Drena transacciones existentes. El bloqueo de aplicación nuevo no protege contra escritores de Parte I que todavía no lo utilizan. Conserva bloqueados todos esos escritores hasta terminar.
4. Selecciona explícitamente el contexto aprobado de la base, con conexión administrativa. Instala 15, 16, 17, 18, 19, 20 si faltan; instala 21 al final. No ejecuta el instalador Full sobre una base existente. No ejecuta procedimientos de venta antiguos después de 21.
5. Utiliza una conexión única y una transacción exterior revisada para instalación, apertura, validaciones y habilitación, con detención ante cualquier error. Los COMMIT internos no confirman esa transacción exterior. Verifica que no existan otros escritores y mantiene el bloqueo exclusivo del corte; el procedimiento también toma bloqueo exclusivo sobre productos.
6. Asigna INVENTARIO_APERTURAR exclusivamente al responsable autorizado del corte. No concede EXECUTE de apertura/habilitación a securefinance_app ni permisos DML sobre tablas. Registra el UUID estable y documento aprobado del corte.
7. Invoca sp_AbrirKardexInventario con ese UUID, actor y documento. Conserva el stock existente. Registra FacturaLimiteId y cantidad de productos; comprueba una apertura por producto previo y stock sin cambios. Si se repite, reutiliza exactamente los mismos parámetros.
8. Ejecuta conciliación independiente y sp_ConsultarConciliacionInventario: cero diferencias. Verifica versión 2, procedimientos integrados, importes DECIMAL, restricciones confiables, índices, permisos efectivos y ausencia de actualización directa de stock por la aplicación.
9. Invoca sp_HabilitarKardexInventario únicamente después de esas comprobaciones. Confirma la transacción exterior una sola vez. Ante cualquier fallo previo al COMMIT, realiza ROLLBACK y conserva escritores detenidos hasta verificar el estado.
10. Reactiva de forma controlada la aplicación. Comprueba una operación comercial legítima autorizada, sus detalles, caja, auditoría y exactamente una salida por línea; no introduce facturas ficticias en producción. Verifica nuevamente conciliación y monitoriza bloqueos/errores.

## Recuperación

Antes del COMMIT, el rollback revierte DDL y datos de instalación/apertura de la transacción exterior. Después del COMMIT, un fallo exige detener escritores, registrar el incidente y, si procede, deshabilitar el mecanismo mediante intervención administrativa controlada mientras se prepara una corrección. No se permite volver solamente al procedimiento antiguo de venta mientras existan movimientos integrados.

Nunca borrar Kardex, sumar de nuevo la apertura ni modificar saldos para ocultar diferencias. Una restauración o recuperación a un punto en el tiempo requiere decisión explícita del DBA y responsables contables, protección de operaciones posteriores y ensayo de recuperación. No se incluye ningún script destructivo automático.

Edward consumirá movimientos centrales y referencias a detalle/documento dentro de su transacción; todavía no se implementan devoluciones, notas de crédito ni garantías. José podrá leer contratos autorizados de productos, saldos y movimientos a través de procedimientos/funciones posteriormente revisados, sin permisos directos amplios sobre tablas sensibles.
