# Instalación y demostración universitaria — 30/10/2026

## Requisitos

Windows con PowerShell, Git, Node.js **24 o superior**, npm y SQL Server **2017 o posterior**, compatibilidad de base 130 o superior. Habilitar TCP/IP para la instancia; el inicio automático descrito usa localhost:1433. Instalar sqlcmd (ODBC 17 o equivalente). SQL Server debe permitir autenticación mixta para el login dedicado de la aplicación. Chrome o Edge instalado permite repetir la prueba visual.

El operador que construye el laboratorio usa autenticación Windows y necesita CREATE DATABASE, CREATE LOGIN y permisos DDL en la base nueva. La aplicación usa un login dedicado sin sysadmin/db_owner; sus permisos se conceden mediante las migraciones. No ejecutar el servidor web como sa.

## Clonar e instalar

```powershell
git clone --branch integracion/p3-dylan-qa https://github.com/Kenneth30flp/SecureFinance-ERP-BD2.git
cd SecureFinance-ERP-BD2
npm.cmd ci
npm.cmd run check
npm.cmd test
node database/tests/promocionesLab.js --build --install
node scripts/integracion/install.cjs
node scripts/integracion/sql-qa.cjs
```

El nombre del constructor conserva su origen de Promociones, pero crea **una base nueva de todo el ERP**, instala Full + 15–26 + 30–44 + 60–63 y abre Kardex con datos sintéticos. No restaura ni requiere bases previas de Kenneth o Dylan. Después, `install.cjs` aplica exactamente el manifiesto de Dylan con una sola transacción. No ejecutar el archivo Full sin adaptar el destino: su USE histórico nombra la base principal.

No repetir `--build` esperando actualizar una base: siempre crea otra. El estado de la base nueva queda en `.data/promociones-lab.json` con el login exclusivo generado. `sql-qa.cjs` crea fixtures de laboratorio y una cuenta académica `P3_DYLAN_QA_ADMIN` con contraseña aleatoria local en `.data/integration-ui.json`; usar ese archivo localmente sin compartirlo. No publica contraseñas ni copia usuarios reales. Después de ejecutar las suites que consumen stock, repetir la suite completa requiere otro laboratorio limpio; nunca reajustar datos reales para satisfacer un test.

Para instalar sobre una instancia distinta debe configurarse el servidor del constructor con `PROMOCIONES_TEST_SERVER` y proporcionar al proceso web un endpoint TCP compatible; el recorrido validado aquí es localhost:1433. No se acreditó una instalación en Linux ni en una segunda computadora física.

## Arrancar y configurar

```powershell
node scripts/startIntegrationLab.cjs
```

Abrir http://127.0.0.1:3107. Este inicio carga el estado local del laboratorio y genera un secreto de sesión efímero; no carga credenciales de una base principal. El puerto debe estar libre.

Para un arranque convencional con `npm.cmd start`, copiar `.env.example` a `.env`, establecer `PORT=3107`, `DB_SERVER`, `DB_PORT`, `DB_NAME` con el nombre **exacto** generado, `DB_USER`/`DB_PASSWORD` con el login **local** dedicado y `SESSION_SECRET` aleatorio de al menos 32 caracteres. Mantener cifrado; `DB_TRUST_SERVER_CERTIFICATE=true` solo para certificado autofirmado del laboratorio. Ningún `.env` ni `.data` se agrega a Git. La muestra no incluye contraseñas.

Administrador dispone de las operaciones de los módulos. Auditor consulta DDL, créditos e inventario local y no autoriza créditos, registra abonos ni mueve transferencias. Cajero tiene los permisos que define el catálogo SQL (incluidos consultar créditos/registrar abonos), sin administración de perfiles ni captura DDL. Consultar `/dashboard#mis-permisos` para la sesión efectiva.

## Repetir verificaciones

Sobre un laboratorio preparado, en este orden:

```powershell
node scripts/integracion/sql-qa.cjs
node scripts/integracion/promociones-qa.cjs
node scripts/integracion/uc09-qa.cjs
node scripts/integracion/concurrency-qa.cjs
node scripts/integracion/matrix-qa.cjs
# Con el servidor de integración ya ejecutándose:
node scripts/integracion/browser-qa.cjs
git diff --check
```

Si `sql-qa.cjs` ya se ejecutó durante la instalación inicial, continuar desde Promociones. Las pruebas de concurrencia consumen fixtures; usar un laboratorio nuevo para repetir el recorrido completo. `fresh-install-qa.cjs` crea otro laboratorio para comprobar la instalación desde cero y después restaura el archivo de estado del laboratorio original. No elimina bases existentes.

Los runners administrativos verifican DB_NAME/autorización; solo sus archivos revisados pueden escribir en el laboratorio. No ejecutar instaladores antiguos que apuntan al laboratorio de Dylan ni scripts sueltos por orden numérico. La primera instalación no necesita respaldo de datos empresariales porque la base es nueva; el despliegue futuro sobre datos existentes sí requiere respaldo y restauración ensayada.

## Guion breve: seis áreas y módulos disponibles

1. **Inicio:** iniciar sesión real; abrir `/modulos` y mostrar las seis áreas y los permisos de la cuenta.
2. **Ventas:** crear cotización en `/cotizaciones`; mostrar conversión UC09 con precio pactado. En `/promociones` activar una regla sintética y registrar una venta normal con promoción desde Facturación. La cotización ya pactada conserva su precio.
3. **Finanzas / Créditos (M3):** autorizar límite y plazo del cliente; facturar una cotización al crédito; mostrar cuotas y ausencia del ingreso total en caja. Para el escenario exacto usar precio base Q1,785.71 con IVA Q214.29: factura Q2,000, abono Q500, saldo Q1,500 y abono Q1,500 hasta Q0. Consultar los recibos y la caja unificada.
4. **Inventario / Multibodega (M5):** preparar transferencia de cinco unidades, despachar (95 origen/5 tránsito), recibir (5 destino/0 tránsito). Mostrar conciliación y diferencia entre ledger local y Kardex global. Una compra con costo documental permite demostrar el promedio ponderado. No editar stocks directamente.
5. **Compras:** mostrar proveedores y recepciones reales. Órdenes de compra Parte III (M2) no llegó en estos PR y continúa planificado; no se presenta como terminado.
6. **Administración / Auditoría DDL (M6):** consultar `/auditoria/ddl`, filtrar CREATE/ALTER/DROP de TABLE y PROCEDURE, abrir detalle y texto. Repetir con Auditor para mostrar consulta y denegación de escritura. Las pruebas DDL usan objetos sintéticos y revierten su transacción; no crear tablas de demostración en la base principal.

Los módulos de Parte III disponibles son Cotizaciones (M1), Créditos (M3), Promociones (M4), Multibodega (M5) y DDL (M6). Las seis áreas del centro de módulos no equivalen a seis módulos de Parte III completados.
