'use strict';

(() => {
  const $ = (id) => document.getElementById(id);
  const lineas = new Map();
  let enviando = false;
  const moneda = (centavos) => `Q ${centavos / 100n}.${(centavos % 100n).toString().padStart(2, '0')}`;
  const centavos = (precio) => BigInt(precio.replace('.', ''));
  $('fecha').textContent = new Date().toLocaleDateString('es-GT');
  function mensaje(texto, tipo = 'danger') {
    $('mensaje').className = `alert alert-${tipo}`;
    $('mensaje').textContent = texto;
    $('mensaje').focus();
  }
  function dibujar() {
    $('lineas').replaceChildren();
    let subtotal = 0n;
    for (const [id, linea] of lineas) {
      const importe = linea.precio * BigInt(linea.Cantidad);
      subtotal += importe;
      const row = document.createElement('tr');
      for (const texto of [linea.descripcion, linea.Cantidad, moneda(linea.precio), moneda(importe)]) {
        const cell = document.createElement('td');
        cell.textContent = texto;
        row.append(cell);
      }
      const cell = document.createElement('td');
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'btn btn-sm btn-outline-danger';
      button.textContent = 'Quitar';
      button.setAttribute('aria-label', `Quitar ${linea.descripcion}`);
      button.addEventListener('click', () => { lineas.delete(id); dibujar(); });
      cell.append(button);
      row.append(cell);
      $('lineas').append(row);
    }
    const iva = (subtotal * 12n + 50n) / 100n;
    $('subtotal').textContent = moneda(subtotal);
    $('iva').textContent = moneda(iva);
    $('total').textContent = moneda(subtotal + iva);
    $('sin-lineas').hidden = lineas.size > 0;
    $('procesar').disabled = lineas.size === 0;
  }
  $('agregar').addEventListener('click', () => {
    const option = $('producto').selectedOptions[0];
    const cantidad = Number($('cantidad').value);
    if (!option.value || !Number.isInteger(cantidad) || cantidad < 1 || cantidad > 2147483647) {
      return mensaje('Selecciona un producto y una cantidad entera positiva.');
    }
    const id = Number(option.value);
    const acumulada = (lineas.get(id)?.Cantidad || 0) + cantidad;
    if (acumulada > Number(option.dataset.stock)) return mensaje('La cantidad supera las existencias mostradas.');
    if (!lineas.has(id) && lineas.size >= 100) return mensaje('La venta admite hasta 100 productos.');
    lineas.set(id, { ProductoId: id, Cantidad: acumulada, descripcion: option.dataset.descripcion,
      precio: centavos(option.dataset.precio) });
    $('mensaje').className = 'alert d-none';
    dibujar();
  });
  $('venta-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    if (enviando || !lineas.size || !$('cliente').value) return;
    enviando = true;
    $('venta-campos').disabled = true;
    $('procesar').textContent = 'Procesando…';
    let permitirCorreccion = false;
    try {
      const response = await fetch('/facturacion/procesar', {
        method: 'POST', redirect: 'error',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content },
        body: JSON.stringify({ ClienteId: Number($('cliente').value),
          Detalle: [...lineas.values()].map(({ ProductoId, Cantidad }) => ({ ProductoId, Cantidad })) }),
      });
      const data = await response.json();
      if (!response.ok) {
        permitirCorreccion = [400, 409].includes(response.status);
        mensaje(data.error);
        return;
      }
      const venta = data.venta;
      mensaje(`Venta registrada. Factura #${venta.FacturaId} · Subtotal Q ${venta.Subtotal} · IVA Q ${venta.IVA} · Total Q ${venta.Total}`, 'success');
      $('nueva-venta').classList.remove('d-none');
    } catch {
      mensaje('No fue posible confirmar el resultado o la sesión expiró. Consulta con el responsable antes de volver a enviar la venta.');
    } finally {
      // Solo errores de validación permiten corregir y reenviar. Nunca se reintenta
      // automáticamente ante un resultado incierto o después de una venta exitosa.
      if (permitirCorreccion) {
        enviando = false;
        $('venta-campos').disabled = false;
      }
      $('procesar').textContent = 'Procesar Venta';
    }
  });
})();
