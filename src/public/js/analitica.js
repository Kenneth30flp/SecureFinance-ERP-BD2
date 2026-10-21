'use strict';

(() => {
  const form = document.querySelector('[data-analytics-filter]');
  if (!form) return;
  const mode = form.querySelector('[name="modo"]');
  const from = form.querySelector('[name="fechaDesde"]');
  const to = form.querySelector('[name="fechaHasta"]');
  const updateDates = () => {
    const custom = mode.value === 'RANGO';
    from.required = custom;
    to.required = custom;
    from.disabled = !custom;
    to.disabled = !custom;
  };
  mode.addEventListener('change', updateDates);
  form.addEventListener('submit', () => {
    form.setAttribute('aria-busy', 'true');
    const state = document.querySelector('[data-analytics-state]');
    if (state) { state.hidden = false; state.textContent = 'Cargando resultados reales…'; }
  });
  updateDates();
})();
