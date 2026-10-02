'use strict';

(() => {
  const $ = (id) => document.getElementById(id);
  const lineas = new Map();
  const maxDescuento = BigInt(Math.round(Number($('venta-form').dataset.maxDescuento) * 100));
  let enviando = false;
  let confirmando = false;
  let registrada = false;
  const moneda = (valor) => 'Q ' + valor / 100n + '.' + (valor % 100n).toString().padStart(2, '0');
  const centavos = (precio) => BigInt(precio.replace('.', ''));
  const dineroSQL = (valor) => valor == null ? '-' : 'Q ' + valor;
  const ahorro = (linea) => (linea.precio * BigInt(linea.Cantidad) * linea.descuento + 5000n) / 10000n;
  $('fecha').textContent = new Date().toLocaleDateString('es-GT');
  function mensaje(texto, tipo = 'danger') {
    window.SecureFinanceMessages.show($('mensaje'), texto, tipo);
    $('mensaje').focus();
  }
  function puntosDescuento(valor) {
    if (!/^\d{1,3}(?:\.\d{0,2})?$/.test(valor)) return null;
    const [entero, decimal = ''] = valor.split('.');
    const puntos = BigInt(entero) * 100n + BigInt(decimal.padEnd(2, '0'));
    return puntos <= 10000n ? puntos : null;
  }
  function resumen() {
    let bruto = 0n;
    let descuento = 0n;
    for (const linea of lineas.values()) {
      bruto += linea.precio * BigInt(linea.Cantidad);
      descuento += ahorro(linea);
    }
    const neto = bruto - descuento;
    const iva = (neto * 12n + 50n) / 100n;
    $('subtotal').textContent = moneda(bruto);
    $('descuento-total').textContent = '− ' + moneda(descuento);
    $('subtotal-neto').textContent = moneda(neto);
    $('iva').textContent = moneda(iva);
    $('total').textContent = moneda(neto + iva);
    $('sin-lineas').hidden = lineas.size > 0;
    $('procesar').disabled = lineas.size === 0;
    const conDescuento = [...lineas.values()].some((linea) => linea.descuento > 0n);
    $('motivo-campo').hidden = !conDescuento;
    if (!conDescuento) $('motivo-descuento').value = '';
  }
  function celda(texto, clase = '') {
    const td = document.createElement('td');
    td.textContent = texto;
    td.className = clase;
    return td;
  }
  function dibujar() {
    $('lineas').replaceChildren();
    for (const [id, linea] of lineas) {
      // Al reconstruir la tabla se muestran los últimos valores aceptados.
      linea.cantidadValida = true; linea.descuentoValido = true;
      const row = document.createElement('tr');
      const producto = celda('');
      const nombre = document.createElement('strong'); nombre.textContent = linea.descripcion;
      const stock = document.createElement('small'); stock.className = 'line-stock';
      const stockBadge = document.createElement('span'); stockBadge.className = 'stock-low-badge'; stockBadge.textContent = 'STOCK BAJO';
      producto.append(nombre); producto.append(stock); producto.append(stockBadge); row.append(producto);
      const cantidadCell = celda('');
      const cantidad = document.createElement('input');
      cantidad.type = 'number'; cantidad.min = '1'; cantidad.max = String(linea.stock); cantidad.step = '1'; cantidad.required = true;
      cantidad.className = 'form-control form-control-sm line-quantity'; cantidad.value = String(linea.Cantidad);
      cantidad.setAttribute('aria-label', 'Cantidad de ' + linea.descripcion);
      cantidadCell.append(cantidad); row.append(cantidadCell); row.append(celda(moneda(linea.precio)));
      const descuentoCell = celda('');
      const grupo = document.createElement('div'); grupo.className = 'discount-entry';
      const input = document.createElement('input');
      input.type = 'number'; input.min = '0'; input.max = String(Number(maxDescuento) / 100); input.step = '0.01'; input.required = true;
      input.className = 'form-control form-control-sm'; input.value = linea.DescuentoPorcentaje;
      input.setAttribute('aria-label', 'Descuento porcentual de ' + linea.descripcion);
      const signo = document.createElement('span'); signo.textContent = '%';
      grupo.append(input); grupo.append(signo); descuentoCell.append(grupo); row.append(descuentoCell);
      const ahorroCell = celda('', 'discount-reduction'); row.append(ahorroCell);
      const netoCell = celda('', 'line-net'); row.append(netoCell);
      const actualizar = () => {
        const monto = ahorro(linea);
        ahorroCell.textContent = '− ' + moneda(monto);
        netoCell.textContent = moneda(linea.precio * BigInt(linea.Cantidad) - monto);
        stock.textContent = 'Stock actual: ' + linea.stock + ' · Después: ' + (linea.stock - linea.Cantidad);
        stockBadge.hidden = linea.stock - linea.Cantidad > 5;
        resumen();
      };
      cantidad.addEventListener('input', () => {
        const valor = Number(cantidad.value);
        linea.cantidadValida = /^[1-9]\d*$/.test(cantidad.value) && Number.isInteger(valor) && valor <= 2147483647 && valor <= linea.stock;
        cantidad.setCustomValidity(linea.cantidadValida ? '' : 'Usa una cantidad entera positiva que no supere el stock mostrado.');
        if (!linea.cantidadValida) return;
        linea.Cantidad = valor; actualizar();
      });
      input.addEventListener('input', () => {
        const puntos = puntosDescuento(input.value);
        linea.descuentoValido = puntos !== null && puntos <= maxDescuento;
        input.setCustomValidity(linea.descuentoValido ? '' : puntos !== null && puntos > maxDescuento
          ? 'El descuento máximo autorizado para tu rol es ' + Number(maxDescuento) / 100 + '%.'
          : 'Usa un descuento entre 0.00 y 100.00 con hasta dos decimales.');
        if (!linea.descuentoValido) return;
        linea.descuento = puntos;
        linea.DescuentoPorcentaje = puntos / 100n + '.' + (puntos % 100n).toString().padStart(2, '0');
        actualizar();
      });
      const quitarCell = celda('');
      const button = document.createElement('button'); button.type = 'button';
      button.className = 'btn btn-sm btn-outline-danger'; button.textContent = 'Quitar';
      button.setAttribute('aria-label', 'Quitar ' + linea.descripcion);
      button.addEventListener('click', () => { lineas.delete(id); dibujar(); });
      quitarCell.append(button); row.append(quitarCell); $('lineas').append(row);
      actualizar();
    }
    resumen();
  }
  function buscar(inputId, selectId) {
    const select = $(selectId);
    const opciones = Array.from(select.options);
    const normalizar = (texto) => texto.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();
    $(inputId).addEventListener('input', () => {
      const consulta = normalizar($(inputId).value.trim());
      for (const opcion of opciones) {
        opcion.hidden = Boolean(opcion.value) && !normalizar(opcion.dataset.search || opcion.textContent).includes(consulta);
        if (opcion.hidden && opcion.selected) select.value = '';
      }
      if (selectId === 'cliente') mostrarCliente();
    });
  }
  buscar('buscar-producto', 'producto'); buscar('buscar-cliente', 'cliente');
  function mostrarCliente() {
    const opcion = $('cliente').selectedOptions[0];
    $('cliente-actual').hidden = !opcion?.value;
    $('cliente-actual-nombre').textContent = opcion?.value ? opcion.dataset.nombre : '';
    $('cliente-actual-nit').textContent = opcion?.value ? 'NIT: ' + opcion.dataset.nit : '';
  }
  $('cliente').addEventListener('change', mostrarCliente);
  $('agregar').addEventListener('click', () => {
    const option = $('producto').selectedOptions[0];
    const cantidad = Number($('cantidad').value);
    if (!option?.value || !/^[1-9]\d*$/.test($('cantidad').value) || !Number.isInteger(cantidad) || cantidad > 2147483647) {
      return mensaje('Selecciona un producto y una cantidad entera positiva.');
    }
    const id = Number(option.value);
    const acumulada = (lineas.get(id)?.Cantidad || 0) + cantidad;
    if (acumulada > Number(option.dataset.stock)) return mensaje('La cantidad supera las existencias mostradas.');
    if (!lineas.has(id) && lineas.size >= 100) return mensaje('La venta admite hasta 100 productos.');
    lineas.set(id, { ProductoId: id, Cantidad: acumulada, descripcion: option.dataset.descripcion,
      stock: Number(option.dataset.stock), precio: centavos(option.dataset.precio),
      descuento: lineas.get(id)?.descuento ?? 0n, DescuentoPorcentaje: lineas.get(id)?.DescuentoPorcentaje ?? '0.00',
      cantidadValida: true, descuentoValido: true });
    $('mensaje').className = 'alert d-none'; dibujar();
  });
  function cancelar() {
    if (!confirmando || enviando) return;
    confirmando = false; $('confirmacion').close(); $('venta-campos').disabled = false; $('procesar').focus();
  }
  $('cancelar-venta').addEventListener('click', cancelar);
  $('confirmacion').addEventListener('cancel', (event) => { event.preventDefault(); cancelar(); });
  $('venta-form').addEventListener('submit', (event) => {
    event.preventDefault();
    if (enviando || confirmando || registrada || !lineas.size || !$('cliente').value) return;
    if ([...lineas.values()].some((linea) => !linea.cantidadValida || !linea.descuentoValido)
        || !$('venta-form').checkValidity()) return mensaje('Corrige las cantidades o descuentos indicados antes de continuar.');
    const option = $('cliente').selectedOptions[0];
    $('confirmar-cliente').textContent = option.dataset.nombre || option.textContent;
    $('confirmar-productos').replaceChildren();
    for (const linea of lineas.values()) {
      const item = document.createElement('li');
      item.textContent = linea.Cantidad + ' × ' + linea.descripcion + ' · Descuento ' + linea.DescuentoPorcentaje + '%';
      $('confirmar-productos').append(item);
    }
    for (const [destino, origen] of [['subtotal', 'subtotal'], ['descuento', 'descuento-total'], ['neto', 'subtotal-neto'], ['iva', 'iva'], ['total', 'total']]) {
      $('confirmar-' + destino).textContent = $(origen).textContent;
    }
    confirmando = true; $('venta-campos').disabled = true; $('confirmacion').showModal();
  });
  function comprobante(venta) {
    for (const [campo, valor] of [['factura', '#' + venta.FacturaId], ['cliente', venta.Cliente], ['nit', venta.NIT], ['cajero', venta.Cajero],
      ['fecha', new Date(venta.FechaHora).toLocaleString('es-GT', { timeZone: 'America/Guatemala' })], ['motivo', venta.MotivoDescuento || 'Sin motivo']]) {
      $('recibo-' + campo).textContent = valor ?? '-';
    }
    for (const [campo, valor] of [['subtotal', venta.Subtotal], ['neto', venta.SubtotalNeto], ['iva', venta.IVA], ['total', venta.Total]]) {
      $('recibo-' + campo).textContent = dineroSQL(valor);
    }
    $('recibo-descuento').textContent = '− ' + dineroSQL(venta.Descuento);
    $('recibo-detalle').replaceChildren();
    for (const linea of venta.Detalle || []) {
      const row = document.createElement('tr');
      for (const texto of [linea.Descripcion, linea.Cantidad, dineroSQL(linea.PrecioUnitario), linea.DescuentoPorcentaje + '%',
        '− ' + dineroSQL(linea.DescuentoMonto), dineroSQL(linea.SubtotalNeto)]) row.append(celda(texto));
      $('recibo-detalle').append(row);
    }
    $('venta-form').hidden = true; $('comprobante').hidden = false; $('comprobante').focus();
  }
  $('confirmar-venta').addEventListener('click', async () => {
    if (!confirmando || enviando || registrada) return;
    confirmando = false; enviando = true; $('confirmacion').close();
    $('confirmar-venta').disabled = true; $('cancelar-venta').disabled = true;
    $('confirmar-venta').textContent = 'Procesando…'; $('venta-form').setAttribute('aria-busy', 'true');
    $('procesar').textContent = 'Procesando…';
    let permitirCorreccion = false;
    try {
      const response = await fetch('/facturacion/procesar', {
        method: 'POST', redirect: 'error',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content },
        body: JSON.stringify({ ClienteId: Number($('cliente').value),
          MotivoDescuento: $('motivo-descuento').value || null,
          Detalle: [...lineas.values()].map(({ ProductoId, Cantidad, DescuentoPorcentaje }) => ({ ProductoId, Cantidad, DescuentoPorcentaje })) }),
      });
      const data = await response.json();
      if (!response.ok) {
        permitirCorreccion = [400, 409].includes(response.status); mensaje(data.error, response.status === 409 ? 'warning' : 'danger'); return;
      }
      registrada = true;
      comprobante(data.venta);
      mensaje('Venta registrada. Factura #' + data.venta.FacturaId + ' · Total Q ' + data.venta.Total, 'success');
    } catch {
      mensaje('No fue posible confirmar el resultado o la sesión expiró. Consulta con el responsable antes de volver a enviar la venta.');
    } finally {
      // Nunca se reintenta un resultado incierto, una revocación o una venta exitosa.
      if (permitirCorreccion) { enviando = false; $('venta-campos').disabled = false; $('confirmar-venta').disabled = false; $('cancelar-venta').disabled = false; }
      $('confirmar-venta').textContent = 'Confirmar venta'; $('venta-form').setAttribute('aria-busy', 'false');
      $('procesar').textContent = 'Procesar Venta';
    }
  });
  $('imprimir-comprobante').addEventListener('click', () => { if (registrada) window.print(); });
})();
