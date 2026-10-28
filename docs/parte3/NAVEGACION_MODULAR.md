# Contrato de navegación de Parte III

Entrega en `feature/p3-kenneth-cotizaciones`, propuesta para integrar mediante PR #12. No cambia contratos financieros ni las URL existentes.

## Arquitectura

`src/config/moduleCatalog.js` es la fuente común del menú y de `/modulos`. Define seis áreas: Inicio, Ventas, Inventario, Compras, Finanzas y Administración. `visibleAreas(usuario)` filtra exclusivamente por los permisos efectivos de sesión. El Centro requiere autenticación y conserva el cambio obligatorio de contraseña.

La barra compacta ofrece Inicio, Centro de módulos y cinco áreas. Cada área abre un panel con enlaces reales. Se abre mediante clic, Enter o espacio; Tab recorre sus enlaces y Escape cierra y devuelve el foco. Abrir otra área cierra la anterior. Las URL directas siguen funcionando y el módulo/área actuales se identifican visualmente. En móvil el panel ocupa el ancho disponible, con desplazamiento interno solo si necesita altura.

El ocultamiento de enlaces no sustituye autorización: permanecen todos los controles Express y SQL. Un área sin permisos muestra un estado vacío. Kardex sigue dentro de `/inventario`; no se creó una ruta artificial.

## Registrar un módulo

1. Implementar y probar primero la ruta Express real con autenticación, RBAC, CSRF para escrituras y autorización SQL.
2. Agregar la entrada al catálogo: identificador estable, área existente, nombre comercial, ruta, icono, descripción, permisos, disponibilidad y orden. Los permisos de entradas actuales usan semántica **cualquiera de**. Para requisitos conjuntos usar un permiso compuesto autorizado o ampliar el filtro con pruebas antes de publicar.
3. Mantener `available:false` y `route:null` mientras el módulo no esté integrado. Las entradas futuras no se publican en la interfaz. No basta cambiar su estado sin registrar la ruta.
4. Hacer que las vistas incluyan `partials/navigation` con `actual` igual al identificador registrado. Las vistas renderizadas fuera de Express deben recibir `moduleAreas: visibleAreas` explícitamente.
5. Para subfuncionalidades independientes, registrar entradas con identificadores propios dentro del área y permisos propios; compartir un identificador activo solo cuando sean pestañas del mismo módulo. No duplicar listas de enlaces en EJS. Los grupos pueden ampliarse en el catálogo cuando exista una necesidad real.

Integraciones reservadas: Edward registra Órdenes de compra/recepciones en Compras; José registra Promociones en Ventas; Dylan registra Créditos/cuentas por cobrar/abonos en Finanzas, Multibodega/transferencias en Inventario y Auditoría DDL en Administración. No confundir las notas de crédito actuales con cuentas por cobrar. Las entradas futuras actuales son informativas en configuración y no rutas disponibles.

## Diseño y verificación

Usar los nombres de iconos SVG existentes en `partials/icon.ejs`, sin mezclar familias. Mantener tema oscuro, textos descriptivos breves, foco visible y los estilos compartidos `navigation.css`. No depender de hover. Mantener cuenta, contraseña y cierre de sesión.

Antes de integrar: `npm.cmd run check`, `npm.cmd test`, `git diff --check`; verificar rutas sin 404, URL directas, permisos con y sin acceso, estado activo, teclado/Escape y móvil a 1366/1024/768/390/320. Las pruebas de escritura deben usar QA/VISUAL, nunca la demostración conservada ni `SecureFinanceERP`.
