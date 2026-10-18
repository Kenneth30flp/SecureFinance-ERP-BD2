'use strict';

// Optional real Chromium test. Uses local simulated services, never the real DB.
// node tests/browser/operationsDesk.browser.js [chrome-or-edge-path]
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const { once } = require('node:events');
const { mkdtemp, mkdir, writeFile, rm } = require('node:fs/promises');
const { existsSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const net = require('node:net');
const { createApp } = require('../../server');
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function main() {
  const browserPath = process.argv[2] || [
    'C:/Program Files/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  ].find(existsSync);
  if (!browserPath) throw new Error('Pass the path to an installed Chromium browser.');
  const directory = await mkdtemp(path.join(tmpdir(), 'securefinance-ui-'));
  const profile = path.join(directory, 'profile');
  const artifacts = path.join(directory, 'artifacts');
  await mkdir(artifacts);
  let sales = 0; let roleWrites = 0;
  let assignedRoles = [{ RolId: 2 }];
  const products = [
    { ProductoId: 1, Codigo: 'HDMI', Descripcion: 'Cable HDMI', Precio: 35.90, Stock: 97 },
    { ProductoId: 2, Codigo: 'USB', Descripcion: 'Cable USB', Precio: 10.25, Stock: 4 },
  ];
  const app = createApp({ secret: 'local-browser-test-secret-operations-desk-123456', production: false,
    passwordService: { solicitar: async () => 'a'.repeat(64), validar: async token => token === 'a'.repeat(64), restablecer: async () => {}, cambiar: async () => {} },
    authService: { login: async (name) => ({ codigo: 0, usuario: { usuarioId: name === 'cajero' ? 2 : name === 'auditor' ? 3 : 1,
      nombreUsuario: name, debeCambiarPassword: name === 'obligatorio', permisos: name === 'auditor' ? ['AUDITORIA_CONSULTAR'] : ['VENTAS_REGISTRAR', 'AUDITORIA_CONSULTAR', ...(name === 'admin' ? ['USUARIOS_ADMINISTRAR'] : [])] } }) },
    dashboardService: { obtenerResumen: async () => ({ VentasDia: '1245.50', FacturasDia: '12', ProductosStockBajo: '3', EventosDMLDia: '18', FechaOperacion: '2026-10-01', RolesActuales: 'Administrador' }) },
    usuarioService: {
      permisosActuales: async id => id === 1 ? [{ Codigo: 'USUARIOS_ADMINISTRAR' }] : [],
      listarUsuarios: async () => [{ UsuarioId: 1, NombreUsuario: 'admin', NombreCompleto: 'Administrador DEMO', Correo: 'admin@example.invalid', Activo: true, Roles: 'Administrador' }, { UsuarioId: 2, NombreUsuario: 'cajero', NombreCompleto: 'Cajero DEMO', Correo: 'cashier@example.invalid', Activo: true, Roles: 'Cajero' }],
      listarRolesActivos: async () => [{ RolId: 1, Nombre: 'Administrador' }, { RolId: 2, Nombre: 'Cajero' }, { RolId: 3, Nombre: 'Auditor' }],
      obtenerRolesUsuario: async id => id === 1 ? [{ RolId: 1 }] : assignedRoles,
      actualizarRoles: async (id, roles, actor) => { assert.equal(actor, 1); if (id === 1 && !roles.includes(1)) throw Object.assign(new Error('Last admin'), { number: 53003 }); roleWrites += 1; assignedRoles = roles.map(RolId => ({ RolId })); },
    },
    ventaService: {
      listarClientes: async () => [{ ClienteId: 1, NIT: '123456-7', Nombre: 'Comercial Aurora DEMO' }],
      listarProductos: async () => products,
      obtenerPolitica: async (id) => ({ MaxDescuento: id === 1 ? 100 : 10 }),
      procesarVenta: async () => { sales += 1; return { FacturaId: 15, FechaHora: '2026-10-01T15:00:00Z', Cliente: 'Comercial Aurora DEMO',
        NIT: '123456-7', Cajero: 'admin', MotivoDescuento: 'Cliente frecuente', Subtotal: '71.80', Descuento: '17.95',
        SubtotalNeto: '53.85', IVA: '6.46', Total: '60.31', Detalle: [{ Descripcion: 'Cable HDMI', Cantidad: 2, PrecioUnitario: '35.90',
          DescuentoPorcentaje: '25.00', DescuentoMonto: '17.95', SubtotalNeto: '53.85' }] }; },
    },
    auditoriaService: {
      getBitacoraAcceso: async () => Array.from({ length: 60 }, (_, i) => ({ FechaHora: '2026-10-01T15:00:00Z', NombreUsuarioIntentado: 'admin',
        Resultado: ['EXITOSO', 'PASSWORD_INCORRECTA', 'USUARIO_INEXISTENTE', 'USUARIO_INACTIVO'][i % 4], HostName: 'OPERATIONS-01',
        AppName: 'SecureFinanceERP-Node', UsuarioSQL: 'securefinance_app', IpConexionSQL: '127.0.0.1' })),
      getAuditoriaDml: async () => Array.from({ length: 24 }, (_, i) => ({ FechaHora: '2026-10-01T15:00:00Z', TablaAfectada: 'Factura', Operacion: 'INSERT',
        IdentificadorRegistro: String(i + 1), UsuarioSQL: 'securefinance_app', HostName: 'OPERATIONS-01', AppName: 'SecureFinanceERP-Node',
        ValorAnterior: null, ValorNuevo: JSON.stringify({ FacturaId: i + 1, Subtotal: 71.80, DescuentoTotal: 17.95, MotivoDescuento: 'Cliente frecuente', IVA: 6.46, Total: 60.31 }) })),
      getHistoricoVentas: async () => Array.from({ length: 24 }, (_, i) => ({ Factura: i + 1, Fecha: '2026-10-01T15:00:00Z', Cliente: 'Comercial Aurora DEMO',
        Usuario: 'admin', Subtotal: '71.80', Descuento: '17.95', SubtotalNeto: '53.85', IVA: '6.46', Total: '60.31' })),
    },
  });
  const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
  const base = 'http://127.0.0.1:' + server.address().port;
  const reservation = net.createServer(); reservation.listen(0, '127.0.0.1'); await once(reservation, 'listening');
  const debugPort = reservation.address().port; await new Promise((resolve) => reservation.close(resolve));
  const browser = spawn(browserPath, ['--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--remote-debugging-port=' + debugPort, '--user-data-dir=' + profile, 'about:blank'], { windowsHide: true, stdio: 'ignore' });
  let socket;
  try {
    let pages;
    for (let i = 0; i < 100; i += 1) {
      try { pages = await (await fetch('http://127.0.0.1:' + debugPort + '/json/list')).json(); if (pages.some((p) => p.type === 'page')) break; } catch {}
      await delay(100);
    }
    const page = pages?.find((p) => p.type === 'page'); assert.ok(page, 'Headless browser did not start.');
    socket = new WebSocket(page.webSocketDebuggerUrl); await once(socket, 'open');
    let sequence = 0; const pending = new Map(); const errors = [];
    socket.addEventListener('message', (event) => {
      const message = JSON.parse(event.data);
      if (message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails.text);
      const task = pending.get(message.id);
      if (task) { pending.delete(message.id); clearTimeout(task.timer); message.error ? task.reject(new Error(message.error.message)) : task.resolve(message.result); }
    });
    const cdp = (method, params = {}) => new Promise((resolve, reject) => {
      const id = ++sequence; const timer = setTimeout(() => { pending.delete(id); reject(new Error('CDP timeout: ' + method)); }, 10000);
      pending.set(id, { resolve, reject, timer }); socket.send(JSON.stringify({ id, method, params }));
    });
    const evaluate = async (expression) => {
      const result = await cdp('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
      if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
      return result.result.value;
    };
    const wait = async (expression) => { for (let i = 0; i < 100; i += 1) { if (await evaluate(expression)) return; await delay(50); } throw new Error('DOM timeout: ' + expression); };
    const navigate = async (route, selector) => { await cdp('Page.navigate', { url: base + route }); await wait('location.href === ' + JSON.stringify(base + route) + ' && document.readyState === "complete" && Boolean(document.querySelector(' + JSON.stringify(selector) + '))'); };
    const screenshot = async (name) => { await delay(300); const result = await cdp('Page.captureScreenshot'); await writeFile(path.join(artifacts, name + '.png'), Buffer.from(result.data, 'base64')); };
    const fullScreenshot = async (name) => {
      await delay(300);
      const { cssContentSize } = await cdp('Page.getLayoutMetrics');
      const result = await cdp('Page.captureScreenshot', { captureBeyondViewport: true, clip: { x: 0, y: 0, width: cssContentSize.width, height: cssContentSize.height, scale: 1 } });
      await writeFile(path.join(artifacts, name + '-completa.png'), Buffer.from(result.data, 'base64'));
    };
    const noOverflow = async (label) => assert.equal(await evaluate('document.documentElement.scrollWidth <= document.documentElement.clientWidth'), true, label);
    const contrast = async (label) => {
      await delay(250);
      const failures = await evaluate(`(() => {
        const rgb = value => (value.match(/[\\d.]+/g) || []).map(Number);
        const blend = (front, back) => { const alpha = front[3] ?? 1; return front.slice(0,3).map((n,i) => n*alpha + back[i]*(1-alpha)); };
        const luminance = color => color.slice(0,3).map(n => { n/=255; return n<=.04045 ? n/12.92 : ((n+.055)/1.055)**2.4; }).reduce((sum,n,i) => sum+n*[.2126,.7152,.0722][i],0);
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); const failed=[]; let node;
        while ((node=walker.nextNode())) {
          const el=node.parentElement, text=node.textContent.trim();
          if (!text || el.closest('script,style,option,[aria-hidden=true]') || !el.getClientRects().length) continue;
          const style=getComputedStyle(el); if (style.visibility==='hidden') continue;
          const ancestors=[]; for(let p=el;p;p=p.parentElement) ancestors.unshift(p);
          let background=[255,255,255]; for(const p of ancestors) background=blend(rgb(getComputedStyle(p).backgroundColor),background);
          const fg=luminance(blend(rgb(style.color),background)), bg=luminance(background);
          const ratio=(Math.max(fg,bg)+.05)/(Math.min(fg,bg)+.05);
          const large=parseFloat(style.fontSize)>=24 || (parseFloat(style.fontSize)>=18.66 && parseInt(style.fontWeight)>=700);
          if(ratio<(large?3:4.5)-.02) failed.push({text:text.slice(0,65),ratio:ratio.toFixed(2),color:style.color});
        }
        return failed.slice(0,20);
      })()`);
      assert.deepEqual(failures, [], 'Text contrast ' + label);
    };
    await cdp('Page.enable'); await cdp('Runtime.enable');
    await cdp('Emulation.setDeviceMetricsOverride', { width: 1366, height: 768, deviceScaleFactor: 1, mobile: false });
    await navigate('/login', 'form');
    await contrast('login');
    await screenshot('login-1366');
    for (const width of [1920, 1024, 768, 390, 320]) {
      await cdp('Emulation.setDeviceMetricsOverride', { width, height: width < 768 ? 844 : 1080, deviceScaleFactor: 1, mobile: false });
      await navigate('/login', 'form'); await noOverflow('Login overflow ' + width); await screenshot('login-' + width);
    }
    await cdp('Emulation.setDeviceMetricsOverride', { width: 1366, height: 768, deviceScaleFactor: 1, mobile: false });
    for (const [route, name] of [['/recuperar-password', 'recuperacion'], ['/restablecer-password?token=' + 'a'.repeat(64), 'reset-valido'], ['/restablecer-password?token=invalid', 'reset-invalido']]) {
      await navigate(route, '#portal-access'); await contrast(name); await screenshot(name + '-1366');
      await cdp('Emulation.setDeviceMetricsOverride', { width: 320, height: 844, deviceScaleFactor: 1, mobile: false });
      await noOverflow(name + ' overflow'); await screenshot(name + '-320');
      await cdp('Emulation.setDeviceMetricsOverride', { width: 1366, height: 768, deviceScaleFactor: 1, mobile: false });
    }
    await navigate('/restablecer-password?token=' + 'a'.repeat(64), 'form');
    await evaluate("document.getElementById('password-nueva').value='test-password';document.getElementById('password-confirmar').value='test-password';document.querySelector('form').requestSubmit()");
    await wait("!document.querySelector('form') && Boolean(document.querySelector('[role=status]'))");
    await screenshot('reset-completado-1366');
    await navigate('/login', 'form');
    await evaluate("fetch('/login',{method:'POST',body:new URLSearchParams({NombreUsuario:'admin',Password:'test'})}).then(r=>r.status)");
    for (const [width, height] of [[1366, 768], [1920, 1080]]) {
      await cdp('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
      await navigate('/dashboard', '.dashboard-kpis');
      await contrast('dashboard');
      assert.equal(await evaluate("document.querySelectorAll('.kpi-card').length"), 4);
      assert.equal(await evaluate('document.documentElement.scrollWidth <= innerWidth'), true);
      await screenshot('dashboard-' + width);
      await navigate('/usuarios', '[data-user-id]');
      await contrast('usuarios');
      await screenshot('usuarios-' + width);
      await evaluate("document.querySelector('[data-user-id=\"2\"]').click()");
      await wait("document.getElementById('roles-panel').open");
      await contrast('roles drawer');
      assert.equal(await evaluate("document.querySelector('#roles-form input[value=\"2\"]').checked"), true);
      assert.equal(await evaluate("document.querySelector('#roles-form input[value=\"1\"]').checked"), false);
      assert.equal(await evaluate("document.getElementById('roles-panel').getBoundingClientRect().bottom <= innerHeight"), true);
      await screenshot('usuarios-modal-' + width);
      await cdp('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 });
      await wait("!document.getElementById('roles-panel').open");
      assert.equal(await evaluate("document.activeElement.dataset.userId"), '2');
      await evaluate("document.getElementById('cancel-roles').click()");
      assert.equal(roleWrites, 0);
      await navigate('/facturacion', '#agregar');
      await contrast('facturacion');
      await evaluate("document.getElementById('cliente').value='1';document.getElementById('cliente').dispatchEvent(new Event('change'));document.getElementById('producto').value='1';document.getElementById('agregar').click()");
      assert.equal(await evaluate('document.documentElement.scrollWidth <= innerWidth'), true, 'Page overflow in sales at ' + width);
      assert.equal(await evaluate("document.getElementById('cliente-actual').hidden"), false);
      assert.match(await evaluate("document.getElementById('cliente-actual-nit').textContent"), /123456-7/);
      await screenshot('facturacion-' + width);
      assert.equal(await evaluate("document.querySelector('.summary-client-name').textContent"), 'Comercial Aurora DEMO');
      assert.equal(await evaluate("getComputedStyle(document.querySelector('.sale-summary')).position"), 'sticky');
      assert.equal(await evaluate("document.getElementById('procesar').getBoundingClientRect().bottom <= innerHeight"), true, 'Primary sale action visible at ' + width);
      assert.equal(await evaluate("document.getElementById('total').getBoundingClientRect().bottom <= innerHeight"), true, 'Total visible at ' + width);
      await fullScreenshot('facturacion-' + width);
      for (const vista of ['acceso', 'dml', 'ventas']) {
        await navigate('/auditoria?vista=' + vista, '#vista-' + vista);
        await contrast('auditoria-' + vista);
        assert.equal(await evaluate("document.querySelectorAll('.log-panel').length"), 1);
        assert.equal(await evaluate('document.documentElement.scrollWidth <= innerWidth'), true, 'Page overflow in audit at ' + width);
        assert.equal(await evaluate("document.querySelector('.audit-scroll').scrollHeight > document.querySelector('.audit-scroll').clientHeight"), true);
        if (vista === 'dml') await evaluate("document.querySelectorAll('.json-disclosure')[1].open=true");
        await screenshot('auditoria-' + vista + '-' + width);
        if (vista === 'dml') {
          await evaluate("const sc=document.querySelector('.audit-scroll');sc.scrollLeft=sc.scrollWidth");
          await screenshot('auditoria-json-' + width);
        }
      }
    }
    for (const width of [1024, 768, 390, 320]) {
      await cdp('Emulation.setDeviceMetricsOverride', { width, height: 844, deviceScaleFactor: 1, mobile: false });
      for (const [route, selector, name] of [['/dashboard', '.dashboard-kpis', 'dashboard'], ['/facturacion', '#agregar', 'facturacion'], ['/auditoria?vista=dml', '#vista-dml', 'auditoria-dml'], ['/usuarios', '[data-user-id]', 'usuarios'], ['/cambiar-password', 'form', 'password']]) {
        await navigate(route, selector);
        if (name === 'facturacion') await evaluate("document.getElementById('cliente').value='1';document.getElementById('cliente').dispatchEvent(new Event('change'));document.getElementById('producto').value='1';document.getElementById('agregar').click()");
        await noOverflow(name + ' overflow ' + width); await screenshot(name + '-' + width);
        if (name === 'facturacion' || name === 'auditoria-dml') await fullScreenshot(name + '-' + width);
        if (name === 'usuarios') {
          await evaluate("document.querySelector('[data-user-id=\"2\"]').click()"); await wait("document.getElementById('roles-panel').open");
          await delay(250);
          assert.equal(await evaluate("(()=>{const r=document.getElementById('roles-panel').getBoundingClientRect();return r.left>=0 && r.right<=innerWidth+1 && r.top>=0 && r.bottom<=innerHeight+1})()"), true, 'Drawer bounds ' + width);
          await screenshot('usuarios-drawer-' + width);
        }
        if (name === 'facturacion') {
          await evaluate("document.getElementById('procesar').click()");
          assert.equal(await evaluate("document.getElementById('confirmacion').open"), true);
          await delay(250);
          assert.equal(await evaluate("(()=>{const r=document.getElementById('confirmacion').getBoundingClientRect();return r.left>=0 && r.right<=innerWidth+1 && r.top>=0 && r.bottom<=innerHeight+1})()"), true, 'Confirmation bounds ' + width);
          await screenshot('confirmacion-' + width);
        }
      }
    }
    // 200% zoom: emulate the effective CSS viewport of a 1366x768 display,
    // with device scale 2, preserving actual browser media-query reflow.
    await cdp('Emulation.setDeviceMetricsOverride', { width: 683, height: 384, deviceScaleFactor: 2, mobile: false });
    for (const route of ['/dashboard', '/facturacion', '/auditoria?vista=dml', '/usuarios', '/cambiar-password']) {
      await navigate(route, 'main'); await noOverflow('200% reflow ' + route);
      await screenshot('zoom-200-' + route.split('?')[0].slice(1));
    }
    await cdp('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] });
    await navigate('/dashboard', 'main');
    assert.equal(await evaluate("getComputedStyle(document.querySelector('main')).animationName"), 'none');
    await cdp('Emulation.setEmulatedMedia', { features: [] });
    await cdp('Emulation.setDeviceMetricsOverride', { width: 1366, height: 768, deviceScaleFactor: 1, mobile: false });
    await navigate('/usuarios', '[data-user-id]');
    await evaluate("document.querySelector('[data-user-id=\"2\"]').click()");
    await wait("document.getElementById('roles-panel').open");
    await evaluate("document.querySelector('#roles-form input[value=\"3\"]').checked=true;document.getElementById('roles-form').requestSubmit();document.getElementById('roles-form').requestSubmit()");
    await wait("!document.getElementById('roles-panel').open"); assert.equal(roleWrites, 1);
    await evaluate("document.querySelector('[data-user-id=\"1\"]').click()");
    await wait("document.getElementById('roles-panel').open");
    await evaluate("document.querySelector('#roles-form input[value=\"1\"]').checked=false;document.getElementById('roles-form').requestSubmit()");
    await wait("!document.getElementById('roles-dialog-message').hidden");
    assert.match(await evaluate("document.getElementById('roles-dialog-message').textContent"), /administrador activo/);
    await evaluate("document.getElementById('cancel-roles').click()");
    await navigate('/facturacion', '#agregar');
    await evaluate("document.getElementById('buscar-producto').value='hdmi';document.getElementById('buscar-producto').dispatchEvent(new Event('input'))");
    assert.equal(await evaluate("document.querySelector('#producto option[value=\"2\"]').hidden"), true);
    await evaluate("document.getElementById('cliente').value='1';document.getElementById('cliente').dispatchEvent(new Event('change'));document.getElementById('producto').value='1';document.getElementById('agregar').click();const q=document.querySelector('.line-quantity');q.value='2';q.dispatchEvent(new Event('input'));const d=document.querySelector('.discount-entry input');d.value='25';d.dispatchEvent(new Event('input'));document.getElementById('motivo-descuento').value='Cliente frecuente';document.getElementById('procesar').click()");
    assert.equal(await evaluate("document.getElementById('confirmacion').open"), true);
    assert.equal(await evaluate("document.getElementById('confirmar-total').textContent"), 'Q 60.31');
    assert.equal(sales, 0); await screenshot('confirmacion-1366');
    await evaluate("document.getElementById('cancelar-venta').click()"); assert.equal(sales, 0);
    await evaluate("document.getElementById('procesar').click();document.getElementById('confirmar-venta').click()");
    await wait("!document.getElementById('comprobante').hidden"); assert.equal(sales, 1);
    await screenshot('comprobante-1366');
    await cdp('Emulation.setEmulatedMedia', { media: 'print' });
    assert.equal(await evaluate("getComputedStyle(document.querySelector('.sidebar')).display"), 'none');
    assert.equal(await evaluate("getComputedStyle(document.querySelector('.receipt-actions')).display"), 'none');
    await screenshot('comprobante-impresion');
    const pdf = await cdp('Page.printToPDF', { printBackground: false, preferCSSPageSize: true });
    await writeFile(path.join(artifacts, 'comprobante.pdf'), Buffer.from(pdf.data, 'base64'));
    await cdp('Emulation.setEmulatedMedia', { media: '' });
    await cdp('Page.navigate', { url: base + '/logout' });
    await wait('location.pathname === "/login" && document.readyState === "complete"');
    await evaluate("fetch('/login',{method:'POST',body:new URLSearchParams({NombreUsuario:'cajero',Password:'test'})})");
    await navigate('/facturacion', '#agregar');
    await evaluate("document.getElementById('cliente').value='1';document.getElementById('cliente').dispatchEvent(new Event('change'));document.getElementById('producto').value='1';document.getElementById('agregar').click();const d=document.querySelector('.discount-entry input');d.value='25';d.dispatchEvent(new Event('input'));document.getElementById('procesar').click()");
    assert.equal(await evaluate("document.getElementById('confirmacion').open"), false);
    assert.match(await evaluate("document.querySelector('.discount-entry input').validationMessage"), /10%/);
    assert.equal(await evaluate("Boolean(document.querySelector('a[href=\"/usuarios\"]'))"), false, 'Cashier access navigation');
    await cdp('Page.navigate', { url: base + '/logout' }); await wait('location.pathname === "/login" && document.readyState === "complete"');
    await evaluate("fetch('/login',{method:'POST',body:new URLSearchParams({NombreUsuario:'auditor',Password:'test'})})");
    await navigate('/dashboard', 'main');
    assert.equal(await evaluate("Boolean(document.querySelector('a[href=\"/facturacion\"]'))"), false, 'Auditor sale navigation');
    await screenshot('dashboard-auditor-1366');
    await cdp('Page.navigate', { url: base + '/logout' }); await wait('location.pathname === "/login" && document.readyState === "complete"');
    await evaluate("fetch('/login',{method:'POST',body:new URLSearchParams({NombreUsuario:'obligatorio',Password:'test'})})");
    await navigate('/cambiar-password', 'form'); await screenshot('password-obligatorio-1366');
    assert.deepEqual(errors, []);
    console.log('OK: Chromium, 1920/1366/1024/768/390/320, 200% effective viewport, reduced motion, password states, role navigation, drawer, keyboard focus, audit, sale confirmation, receipt, print and cashier policy.');
    console.log('Artifacts: ' + artifacts);
  } finally {
    if (socket) socket.close();
    await new Promise((resolve) => { server.close(resolve); server.closeAllConnections(); });
    const closed = browser.exitCode === null ? once(browser, 'exit') : Promise.resolve(); browser.kill(); await closed;
    const resolved = path.resolve(profile);
    if (resolved !== path.join(path.resolve(directory), 'profile') || !path.basename(directory).startsWith('securefinance-ui-')) throw new Error('Unexpected browser profile path.');
    await rm(resolved, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
  }
}
main().catch((error) => { console.error(error.stack); process.exitCode = 1; });
