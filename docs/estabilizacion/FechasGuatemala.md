# Fechas operativas de Guatemala

Se corrige la presentación de fechas en `feature/estabilizacion-funcional-erp` sin modificar SQL Server ni los registros históricos. `22/10/2026 04:19 UTC` se presenta como **21/10/2026, 22:19:00** en Guatemala.

## Presentación

- Kardex, devoluciones, garantías (apertura, resolución e historial), notas de crédito y aplicaciones usan `America/Guatemala`, idioma `es-GT` y horas de 24 horas. Tablas, comprobantes y formularios indican Guatemala / UTC−6.
- Facturación conserva la conversión local del comprobante, la uniforma a 24 horas y corrige la fecha preliminar para que tampoco dependa de la zona del navegador. Ambos lugares identifican Guatemala.
- Auditoría ya convertía las horas a Guatemala; ahora mantiene el mismo formato y etiqueta sus tres vistas, incluido el histórico de ventas.
- Las fechas de registro e inactivación de Clientes tenían el mismo problema y también se muestran en Guatemala.
- La presentación EJS se centraliza en `partials/operational-date.ejs`, sin depender de nuevos locals al arrancar Express. El navegador y los servicios de filtros usan `operationalDates.js`.
- Los atributos `datetime` legibles por máquinas siguen expresando el instante original en UTC. Los períodos de Dashboard y Analítica ya estaban definidos como jornadas de Guatemala; no se les vuelve a aplicar un desplazamiento.

## Filtros

Los filtros de Kardex, devoluciones, garantías, notas de crédito y auditoría pasan de días UTC a **días de Guatemala**, conforme a sus nuevas etiquetas. No cambia el contrato de los procedimientos ni la zona de almacenamiento.

Para filtrar únicamente el 21/10/2026:

| Límite | Valor enviado a SQL |
| --- | --- |
| Inicio inclusivo: 21/10 00:00 Guatemala | `2026-10-21T06:00:00.000Z` |
| Fin exclusivo de Kardex y posventa: 22/10 00:00 Guatemala | `2026-10-22T06:00:00.000Z` |
| Fin inclusivo de auditoría: 21/10 23:59:59.999 Guatemala | `2026-10-22T05:59:59.999Z` |

Se respetan las comparaciones existentes (`< @Hasta` frente a `<= @FechaFinal`) y la precisión `DATETIME2(3)`. Los parámetros siguen siendo tipados. Una compra de las 22:19 locales aparece al filtrar ese día local aunque su fecha UTC pertenezca al día siguiente. Los campos vacíos siguen enviando `NULL`.

## Pruebas

`tests/operational-dates.test.js` comprueba la conversión solicitada, Date y cadenas UTC/con offset, medianoche local, cambio de año, año bisiesto, fecha inválida, límites inclusivos/exclusivos y parámetros de todos los servicios afectados. También renderiza módulos EJS con el mismo instante y verifica fecha visible, etiquetas y conservación del `datetime` UTC. La prueba del comprobante de facturación verifica exactamente `21/10/2026, 22:19:00`.

- Pruebas relacionadas de fechas, Kenneth, Edward, crédito, auditoría y facturación: **43/43 PASS** en la versión final de las plantillas.
- Regresión general: `npm.cmd test`, **85/85 PASS**.
- `npm.cmd run check`: PASS.
- Pruebas de fechas ejecutadas también con `TZ=Asia/Tokyo`: **4/4 PASS**, confirmando independencia de la zona del proceso.
- `npm.cmd run test:ui`: PASS, Chromium con servicios simulados.
- `npm.cmd run test:ui:edward`: PASS, Chromium con servicios simulados.
- `git diff --check`: PASS.

Las pruebas usan fixtures y puertos efímeros. No se ejecutaron migraciones, escrituras SQL, operaciones de negocio en la principal, reinicios del ERP ni comandos de despliegue. Se conserva la apariencia corporativa, RBAC y CSRF. El cambio se entrega en el PR #11 para revisión; no se fusiona a `main`.
