'use strict';
// Presentation only: observe existing DOM updates, never sales/access state.
(() => {
  const revealPermissions=()=>{
    if(location.hash!=='#mis-permisos')return;
    const panel=document.getElementById('mis-permisos');
    if(panel){panel.open=true;panel.querySelector('summary')?.focus();}
  };
  window.addEventListener('hashchange',revealPermissions);
  revealPermissions();
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
  const timers = new WeakMap();
  const flash = target => {
    if (reduced.matches || target.hidden) return;
    clearTimeout(timers.get(target));
    target.classList.remove('visual-feedback');
    requestAnimationFrame(() => {
      if (reduced.matches || !target.isConnected) return;
      target.classList.add('visual-feedback');
      timers.set(target, setTimeout(() => target.classList.remove('visual-feedback'), 260));
    });
  };
  for (const id of ['total', 'descuento-total']) {
    const target = document.getElementById(id);
    if (!target) continue;
    let previous = target.textContent;
    new MutationObserver(() => {
      if (target.textContent === previous) return;
      previous = target.textContent;
      flash(target);
    }).observe(target, { childList: true, characterData: true, subtree: true });
  }
  const menu = document.querySelector('.account-menu');
  // Mirror the already-rendered customer identity inside the persistent desk.
  const customer = document.getElementById('cliente-actual-nombre');
  const summaryCustomer = document.querySelector('.summary-client-name');
  if (customer && summaryCustomer) {
    const syncCustomer = () => { summaryCustomer.textContent = customer.textContent.trim() || 'Sin seleccionar'; };
    syncCustomer();
    new MutationObserver(syncCustomer).observe(customer, { childList: true, characterData: true, subtree: true });
  }
  if (menu) {
    document.addEventListener('keydown', event => {
      if (event.key === 'Escape' && menu.open) {
        menu.open = false;
        menu.querySelector('summary').focus();
      }
    });
    document.addEventListener('click', event => {
      if (menu.open && !menu.contains(event.target)) menu.open = false;
    });
  }
})();
