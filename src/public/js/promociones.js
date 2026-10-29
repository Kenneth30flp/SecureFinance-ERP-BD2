'use strict';
(() => {
  const $ = (id) => document.getElementById(id);
  const csrf = () => document.querySelector('meta[name="csrf-token"]').content;
  function show(text, ok = false) {
    const box = $('pro-message'); if (!box) return;
    box.textContent = text; box.hidden = false;
    box.classList.toggle('cot-notice-error', !ok); box.classList.toggle('pro-notice-ok', ok); box.focus();
  }
  // Un resultado incierto conserva la misma referencia: reenviar repite la operación una sola vez.
  async function send(url, body, button) {
    if (button.dataset.busy === 'true') return null;
    button.dataset.busy = 'true'; button.disabled = true; const label = button.textContent; button.textContent = 'Procesando…';
    try {
      const response = await fetch(url, { method: 'POST', redirect: 'error', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() }, body: JSON.stringify(body) });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) { show(data.error || 'No fue posible completar la operación.'); return null; }
      return data;
    } catch {
      show('No fue posible confirmar el resultado. Consulta la promoción antes de reenviar; se conservará la misma referencia.');
      return null;
    } finally { button.dataset.busy = 'false'; button.disabled = false; button.textContent = label; }
  }
  function picker({ input, panel, status, results, categoria, onPick }) {
    let timer, sequence = 0;
    const close = () => { panel.hidden = true; input.setAttribute('aria-expanded', 'false'); };
    input.addEventListener('input', () => {
      clearTimeout(timer); const q = input.value.trim();
      if (q.length < 2) { close(); return; }
      timer = setTimeout(async () => {
        const current = ++sequence; panel.hidden = false; input.setAttribute('aria-expanded', 'true'); status.textContent = 'Buscando…'; results.replaceChildren();
        try {
          const params = new URLSearchParams({ q }); if (categoria) params.set('categoria', categoria);
          const response = await fetch('/promociones/buscar/productos?' + params, { headers: { Accept: 'application/json' } });
          const data = await response.json(); if (current !== sequence) return;
          if (!response.ok) { status.textContent = data.error || 'No fue posible buscar.'; return; }
          status.textContent = data.rows.length ? (data.next ? 'Mostrando 8 resultados; precisa la búsqueda.' : data.rows.length + ' resultado(s)') : 'Sin resultados.';
          for (const row of data.rows) {
            const option = document.createElement('div'); option.className = 'cot-option'; option.setAttribute('role', 'option'); option.tabIndex = 0;
            const left = document.createElement('div'); const name = document.createElement('strong'); name.textContent = row.Descripcion;
            const sku = document.createElement('small'); sku.textContent = row.Codigo + (row.Categoria ? ' · ' + row.Categoria : ' · Sin categoría'); left.append(name, sku);
            const right = document.createElement('div'); right.className = 'cot-option-price'; const price = document.createElement('strong'); price.textContent = 'Q ' + row.Precio; right.append(price);
            option.append(left, right);
            const pick = () => { onPick(row); input.value = ''; close(); input.focus(); };
            option.addEventListener('click', pick); option.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); pick(); } });
            results.append(option);
          }
        } catch { if (current === sequence) status.textContent = 'No fue posible buscar.'; }
      }, 250);
    });
    input.addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); if (e.key === 'ArrowDown') results.querySelector('.cot-option')?.focus(); });
    document.addEventListener('click', (e) => { if (!panel.contains(e.target) && e.target !== input) close(); });
  }
  const form = $('pro-form');
  if (form) {
    const chips = $('pro-products');
    const selectedType = () => form.querySelector('input[name="TipoCodigo"]:checked');
    function refreshType() {
      const type = selectedType(); const eligibility = type?.dataset.eligibility || 'PRODUCTO'; const code = type?.value;
      for (const section of form.querySelectorAll('section[data-eligibility]')) section.hidden = section.dataset.eligibility !== eligibility;
      form.querySelector('[data-field="porcentaje"]').hidden = code === 'DOS_POR_UNO';
      form.querySelector('[data-field="minima"]').hidden = code === 'DOS_POR_UNO';
      form.querySelector('.pro-twoforone').hidden = code !== 'DOS_POR_UNO';
      $('pro-minimum').required = code === 'VOLUMEN'; $('pro-minimum').min = code === 'VOLUMEN' ? '2' : '1';
      $('pro-minimum-hint').textContent = code === 'VOLUMEN' ? 'Obligatoria: la línea debe tener al menos esta cantidad.' : 'Opcional: cantidad mínima en la línea para aplicar.';
    }
    form.querySelectorAll('input[name="TipoCodigo"]').forEach((r) => r.addEventListener('change', refreshType)); refreshType();
    const emptyHint = () => { $('pro-products-empty').hidden = chips.children.length > 0; };
    chips.addEventListener('click', (e) => { if (e.target.closest('.pro-chip-remove')) { e.target.closest('li').remove(); emptyHint(); } });
    if ($('pro-product-search')) picker({ input: $('pro-product-search'), panel: $('pro-product-panel'), status: $('pro-product-status'), results: $('pro-product-results'), onPick(row) {
      if (chips.querySelector('[data-id="' + row.ProductoId + '"]')) return;
      if (chips.children.length >= 200) { show('Selecciona como máximo 200 productos.'); return; }
      const li = document.createElement('li'); li.dataset.id = row.ProductoId; const span = document.createElement('span'); const code = document.createElement('strong'); code.textContent = row.Codigo; span.append(code, ' ' + row.Descripcion);
      const remove = document.createElement('button'); remove.type = 'button'; remove.className = 'pro-chip-remove'; remove.textContent = '×'; remove.setAttribute('aria-label', 'Quitar ' + row.Descripcion);
      li.append(span, remove); chips.append(li); emptyHint();
    } });
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const type = selectedType()?.value, value = (id) => $(id).value.trim();
      const body = { OperacionId: form.dataset.operation, TipoCodigo: type, Nombre: value('pro-name'), Descripcion: value('pro-description'),
        Porcentaje: type === 'DOS_POR_UNO' ? null : value('pro-percent'), CantidadMinima: type === 'DOS_POR_UNO' ? 2 : value('pro-minimum') || null,
        TopeDescuento: value('pro-cap') || null, Desde: value('pro-from'), Hasta: value('pro-to'), Motivo: value('pro-reason'),
        Productos: type === 'CATEGORIA' ? [] : [...chips.children].map((li) => Number(li.dataset.id)),
        Categorias: type === 'CATEGORIA' ? [...form.querySelectorAll('input[name="Categorias"]:checked')].map((c) => Number(c.value)) : [] };
      if (form.dataset.mode === 'edit') body.Version = form.dataset.version; else body.Codigo = value('pro-code');
      if (!body.Motivo) { show('Indica el motivo.'); $('pro-reason').focus(); return; }
      const data = await send(form.dataset.mode === 'edit' ? '/promociones/' + form.dataset.id : '/promociones', body, $('pro-submit'));
      if (data) window.location.assign(data.url);
    });
  }
  const state = $('pro-state');
  if (state) state.addEventListener('submit', async (e) => {
    e.preventDefault(); const reason = $('pro-state-reason').value.trim();
    if (!reason) { show('Indica el motivo del cambio de estado.'); $('pro-state-reason').focus(); return; }
    const data = await send('/promociones/' + state.dataset.id + '/estado', { OperacionId: state.dataset.operation, Version: state.dataset.version, Activa: state.dataset.activa === 'true', Motivo: reason }, state.querySelector('button'));
    if (data) window.location.assign(data.url);
  });
  const category = $('pro-category-form');
  if (category) category.addEventListener('submit', async (e) => {
    e.preventDefault();
    const data = await send('/promociones/categorias', { OperacionId: category.dataset.operation, Nombre: $('pro-category-name').value.trim(), Motivo: $('pro-category-reason').value.trim() }, category.querySelector('button'));
    if (data) window.location.reload();
  });
  const assign = $('pro-assign-form');
  if (assign) {
    let product = null;
    picker({ input: $('pro-assign-search'), panel: $('pro-assign-panel'), status: $('pro-assign-status'), results: $('pro-assign-results'), onPick(row) {
      product = row; const box = $('pro-assign-selected'); box.hidden = false; box.textContent = row.Codigo + ' · ' + row.Descripcion + ' · Actual: ' + (row.Categoria || 'Sin categoría');
    } });
    assign.addEventListener('submit', async (e) => {
      e.preventDefault(); if (!product) { show('Selecciona un producto.'); return; }
      const data = await send('/promociones/categorias/asignar', { OperacionId: assign.dataset.operation, ProductoId: product.ProductoId, CategoriaId: $('pro-assign-category').value || null, Motivo: $('pro-assign-reason').value.trim() }, assign.querySelector('button'));
      if (data) window.location.reload();
    });
  }
})();
