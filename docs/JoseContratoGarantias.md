# Contrato de integración de garantías

La analítica de José no depende de `Ticket_Garantia` ni `Historial_Garantia`, porque esas tablas pertenecen al trabajo pendiente de Edward. Mientras no exista una fuente real instalada, el dashboard muestra **Módulo de garantías no integrado** y no inventa un conteo cero.

## Contrato de lectura esperado

La integración futura debe exponer, mediante un procedimiento o servicio autorizado, únicamente estos datos:

| Campo | Significado |
| --- | --- |
| `TicketId` | Identificador estable del ticket |
| `EstadoActual` | `Recibido`, `En revisión`, `Aprobado`, `Rechazado` o `Entregado` |
| `FechaCreacion` | Fecha UTC de creación |
| `FechaActualizacion` | Fecha UTC del último cambio |
| `FechaResolucion` | Fecha UTC de resolución, nullable |
| `HistorialEstados` | Secuencia de cambios con fecha y estado |
| `UsuarioResponsable` | Identidad autorizada responsable, nullable |

La fuente debe preservar el historial y devolver fechas UTC. José no creará tablas duplicadas ni importará scripts 24–26.

## Métricas futuras

Con ese contrato, el panel podrá calcular tickets activos, tickets por estado, aprobados, rechazados, duración promedio de resolución, tickets creados en un rango y tickets resueltos en un rango. Cada métrica debe distinguir “sin fuente integrada” de “cero registros”. La conexión final se realizará después de integrar la implementación real de Edward en `main`.
