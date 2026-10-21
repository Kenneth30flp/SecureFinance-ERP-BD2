# Resultados de validación Edward

Fecha: 2026-10-20. Rama: feature/edward-posventa-parte2. Entorno: Node 24.16.0, SQL Server local de laboratorio y Chromium. Ninguna prueba escribe en la base operativa.

| Comando | Resultado final |
|---|---|
| npm.cmd ci | PASS; instaladas 151 dependencias del lockfile existente |
| npm.cmd run check | PASS |
| npm.cmd test | PASS: 69 pruebas, 0 fallos, 0 omitidas |
| npm.cmd run test:ui | PASS: regresión Chromium existente del ERP |
| npm.cmd run test:ui:edward | PASS: páginas y flujos nuevos en Chromium |
| npm.cmd run test:sql:edward | PASS: instalación, repetibilidad, negocio, seguridad, rollback y concurrencia real |
| git diff --check | PASS |

## SQL real, aislado

Última ejecución completa: SecureFinanceERP_Edward_Test_47ba522afba2470381ec0095cbebfd6b. Se conserva localmente para inspección. Evidencia SQL temporal local: edward-sql-Bml6Q7. No se suben volcados, credenciales ni datos de instalaciones operativas.

Casos comprobados mediante assertions SQL y procesos sqlcmd:

- Factura inexistente y detalle ajeno: rechazados.
- Cantidad cero, superior y acumulada superior: rechazadas.
- Devolución parcial y total acumulada: importes y redondeos exactos.
- Precio/garantía de catálogo modificados después de vender: se conservan precio, descuento y cobertura de venta.
- IVA histórico distinto de 12%: acreditado desde la factura.
- Devolución de varios productos: una nota y un reingreso por línea apta, IVA total conservado.
- Producto apto: stock aumenta una sola vez; defecto: stock no aumenta.
- Idempotencia: un documento, una nota y un movimiento; otro contenido con el mismo UUID se rechaza.
- Rollback por fallo Kardex: sin devolución ni movimiento parciales.
- Transacción externa: éxito conserva la transacción abierta; rollback del llamador elimina efectos; fallo revierte todo.
- SQL RBAC y cuenta con EXECUTE sin DML: comprobados.
- Ticket e historial inicial idempotentes; revisión, diagnósticos adicionales, aprobación, rechazo y entrega válidos.
- Transición arbitraria y versión antigua: rechazadas; historial inmutable.
- Cobertura histórica desconocida: no se inventa; aprobación sin evidencia rechazada.
- Procedimientos de consulta ejecutados bajo securefinance_app.

Concurrencia con conexiones simultáneas:

A. Dos solicitudes para la última unidad: exactamente una aprobada; otra 54605.
B. Dos actualizaciones con la misma ROWVERSION: exactamente una aprobada; otra 54603.
C. Dos solicitudes con el mismo UUID: un documento y un Kardex.

## Node y navegador

La suite incluye las 66 pruebas anteriores sin modificarlas y 3 nuevas que agrupan validación, contratos de servicios y flujo HTTP/RBAC/CSRF. Comprueba actor de sesión, escape EJS, consultas sin sesión, cambio obligatorio de contraseña, cantidades inválidas, versiones, fecha inválida, permiso de consulta y escritura, y conflicto HTTP 409.

La prueba Chromium Edward comprueba 1366/768/390/320 px sin desbordamiento de página, diálogo de confirmación/cancelación, envío, comprobante, impresión, creación de ticket, conflicto que conserva el diagnóstico y foco en el mensaje. Capturas en .data/edward-ui, ignoradas por Git; revisadas visualmente tras corregir contraste y acentos.

La regresión Chromium existente comprueba además facturación, usuarios, auditoría, permisos y navegación, impresión, reduced-motion y tamaños 1920/1366/1024/768/390/320.

## Fallos detectados y corregidos

Durante desarrollo fallaron una definición CHECK de columna que referenciaba otra columna, el fixture Usuario_Rol sin columnas explícitas, una conversión textual de ROWVERSION del ejecutor y opciones SET del fixture histórico. Se corrigieron y se repitió la instalación desde una base nueva hasta obtener PASS completo.

La primera ejecución Node no pudo cargar sharp porque faltaban dependencias locales; npm ci lo resolvió. Se corrigieron una llave del doble de servicio y el cierre de sesión entre identidades en la nueva prueba HTTP. No se alteraron pruebas anteriores para ocultar fallos.

Pendiente de despliegue: aplicar migraciones y asignar permisos en la base elegida por su DBA. Las pruebas no son una activación operativa. npm ci reportó dos vulnerabilidades moderadas existentes; no se alteró el lockfile ni se aplicó npm audit fix.
