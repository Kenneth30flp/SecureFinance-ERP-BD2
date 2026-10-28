# Probar Cotizaciones desde Chrome — Windows PowerShell

La copia utilizada en esta entrega es
`SecureFinanceERP_P3_COT_20261027213647_67c25f5a`, migraciones 41–43 instaladas.
El lanzador lee el laboratorio vigente de `.data/cotizaciones-lab.json`, fuerza
DB_NAME solo en su proceso y comprueba identidad SQL, contrato y EXECUTE.
No cambia `.env`, no usa login fixture y no inicia la instancia normal 3000.

```powershell
Set-Location -LiteralPath 'C:\Users\kenne\OneDrive\Desktop\CLASES\SEMESTRE 2 2026\Base de Datos 2\proyecto SecureFinance-ERP-BD2\SecureFinance-ERP-BD2'
git branch --show-current
npm.cmd run start:lab:cotizaciones -- --port 3103
```

Debe indicar `feature/p3-kenneth-cotizaciones`. El comando queda ejecutándose
en esa consola; dejarla abierta. Si ya está preparado y ejecutándose el proceso
de entrega en 3103, basta abrir la URL; no iniciar otro sobre el mismo puerto.
Un puerto ocupado produce error sin detener ni reemplazar la instancia ajena.
Para otra sesión independiente usar `--port 3104`, conservando la misma copia.

Abrir Chrome en **http://localhost:3103/cotizaciones**. Iniciar sesión con
credenciales existentes que sean válidas en la copia restaurada. No se crearon
contraseñas de demostración ni se cambiaron las existentes. Si la cuenta exige
cambio de contraseña, hacerlo únicamente mediante el flujo normal de esta copia;
no se elimina esa obligación para preparar la visualización.

Para verificar la base:

1. La consola imprime `COTIZACIONES_LAB_RUNTIME` con database, sqlLogin, PID,
   puerto, rama y commit, después de consultar DB_NAME y permisos efectivos.
2. Con sesión autenticada, abrir **http://localhost:3103/laboratorio/estado**.
   Devuelve el DB_NAME consultado otra vez, PID, puerto y contrato instalado.
3. En Cotizaciones aparece un aviso de laboratorio con base y puerto.

La instancia anterior **http://localhost:3000** puede seguir mostrando código
viejo o usando la principal. No usarla para estas pruebas. Cambiar de rama no
recarga un proceso Node ya iniciado; verificar puerto, aviso y PID, no solo URL.

Permisos necesarios del usuario de la copia: COTIZACIONES_CONSULTAR,
COTIZACIONES_CREAR, COTIZACIONES_CONVERTIR, VENTAS_REGISTRAR y FACTURAS_CONSULTAR.
Administrador activo los tiene en la instalación verificada. Para ver Kardex:
INVENTARIO_CONSULTAR; cancelar requiere COTIZACIONES_CANCELAR. SQL revalida
permisos y acceso al documento en cada operación, aunque la sesión sea anterior.

Si no aparece el menú: comprobar rama/puerto/DB_NAME, cerrar sesión y entrar
otra vez para refrescar permisos. No editar permisos a ciegas en la principal.
Si aparece el módulo pero no convertir: revisar estado ACTIVA, vigencia, permisos
y que el lanzador confirme 43 y EXECUTE. Un documento PROCESADA no muestra botón.

Flujo manual: Nueva cotización → seleccionar cliente activo y producto QA con
stock → vigencia y cantidades → guardar → convertir y confirmar contado →
abrir factura → Inventario y Kardex del mismo producto. Las pruebas automáticas
ya dejaron documentos/productos QA identificados en esta copia. No confundir
QA con una operación comercial real; se conservaron los documentos anteriores.

Para verificar si el proceso de entrega sigue vivo, leer
`.data/cotizaciones-preview.json` y consultar:

```powershell
Get-Content .data/cotizaciones-preview.json
Invoke-RestMethod http://localhost:3103/health
```

`/health` acredita HTTP, no identidad SQL; contrastar con el registro de arranque
y `/laboratorio/estado`. Al ejecutar en primer plano, detener con Ctrl+C.
Los logs de la instancia preparada quedan en `.data/cotizaciones-lab.stdout.log`
y `.data/cotizaciones-lab.stderr.log`, ignorados por Git.

Las capturas automatizadas usan una sesión QA identificada; no acreditan login
con contraseña real. El lanzador que abre el usuario sí conserva autenticación
normal y no ofrece ningún bypass.
