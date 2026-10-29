'use strict';
(() => {
  document.querySelector('[data-cre-print]')?.addEventListener('click', () => window.print());
  const notice = document.getElementById('cre-message');
  function message(text, url) {
    notice.replaceChildren(document.createTextNode(text));
    if (url && /^\/creditos(?:[/?]|$)/.test(url)) {
      const link = document.createElement('a'); link.href = url; link.textContent = 'Consultar documento'; notice.append(link);
    }
    notice.hidden = false; notice.focus();
  }
  for (const form of document.querySelectorAll('[data-cre-form]')) {
    const actor = document.querySelector('body[data-cre-actor]')?.dataset.creActor || 'session';
    const key = 'P3_CRE.pending.' + actor + '.' + form.dataset.creForm, button = form.querySelector('button[type="submit"],button:not([type])');
    const initialLabel = button.textContent;
    let pending = null, busy = false, completed = false, storageReady = true, uncertain = false;
    const controls = [...form.elements].filter(el => el.name && !['csrf', 'OperacionId'].includes(el.name));
    function freeze(value) {
      for (const el of controls) el.disabled = value;
      form.dataset.uncertain = String(value);
    }
    try {
      const stored = sessionStorage.getItem(key);
      if (stored) {
        pending = JSON.parse(stored);
        if (!pending || typeof pending !== 'object' || typeof pending.OperacionId !== 'string') throw new Error();
        for (const el of form.elements) if (el.name !== 'csrf' && Object.hasOwn(pending, el.name)) el.value = pending[el.name];
        const reference = form.querySelector('[data-cre-operation]');
        if (reference) reference.textContent = pending.OperacionId;
        uncertain = true;
        freeze(true); button.textContent = 'Reintentar misma solicitud';
        message('Hay un envio sin confirmar: cliente ' + (pending.ClienteId || '-') + ', factura ' + (pending.FacturaId || '-')
          + ', cotizacion ' + (pending.CotizacionId || '-') + ', UUID ' + pending.OperacionId + '. Se conservan los datos originales.');
      }
    } catch {
      storageReady = false; button.disabled = true;
      message('No se puede conservar la referencia en esta sesion del navegador. Habilita almacenamiento de sesion antes de operar.');
    }
    form.addEventListener('submit', async event => {
      event.preventDefault();
      if (busy || completed || !storageReady) return;
      const payload = pending || Object.fromEntries(new FormData(form));
      delete payload.csrf;
      try { sessionStorage.setItem(key, JSON.stringify(payload)); }
      catch { message('No se pudo conservar el UUID. No se envio la operacion.'); return; }
      busy = true; pending = payload; button.disabled = true; button.textContent = 'Confirmando...'; freeze(true);
      try {
        const response = await fetch(form.action, { method: 'POST', credentials: 'same-origin', redirect: 'error',
          headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content },
          body: JSON.stringify(payload) });
        const data = await response.json();
        if (!response.ok) {
          message((data.error || 'No se confirmo el resultado.') + (data.incierto ? ' UUID: ' + payload.OperacionId : ''));
          // A later CSRF/permission/validation failure does not resolve an earlier uncertain commit.
          if (!data.incierto && !uncertain) { sessionStorage.removeItem(key); pending = null; freeze(false); }
          else { uncertain = true; }
        } else {
          sessionStorage.removeItem(key); pending = null; completed = true;
          message(data.mensaje || 'Operacion confirmada.', data.url);
        }
      } catch {
        uncertain = true;
        message('Resultado incierto. Se conservaron UUID y datos. Consulta el historial antes de reenviar. UUID: ' + payload.OperacionId);
      } finally {
        busy = false; button.disabled = completed;
        button.textContent = completed ? 'Confirmado' : pending ? 'Reintentar misma solicitud' : initialLabel;
      }
    });
  }
})();
