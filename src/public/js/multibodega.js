'use strict';
(() => {
  const message = document.querySelector('#bod-message');
  function announce(text, url) {
    message.replaceChildren(document.createTextNode(text));
    if (url) { const a = document.createElement('a'); a.href = url; a.textContent = 'Consultar evidencia'; message.append(a); }
    message.hidden = false;
    message.focus();
  }
  document.querySelector('[data-bod-print]')?.addEventListener('click', () => window.print());
  for (const form of document.querySelectorAll('[data-bod-flow]')) {
    const key = 'P3_BOD:' + document.body.dataset.bodActor + ':' + location.pathname + ':' + form.dataset.bodFlow;
    const submit = form.querySelector('[type=submit]'), retry = form.querySelector('[data-bod-retry]'), newRequest = form.querySelector('[data-bod-new]');
    const reference = form.querySelector('[data-bod-reference]'), status = form.querySelector('[data-bod-status]');
    let saved = null, busy = false, storageReady = true;
    function lock() {
      form.dataset.locked = 'true';
      for (const control of form.querySelectorAll('input,select')) control.disabled = true;
      submit.disabled = true;
      retry.hidden = saved?.confirmed === true;
      newRequest.hidden = saved?.confirmed !== true && saved?.rejected !== true;
      reference.textContent = 'Referencia conservada: ' + saved.payload.OperacionId;
      status.href = '/multibodega/operaciones/' + saved.payload.OperacionId;
      status.hidden = false;
    }
    try {
      const raw = sessionStorage.getItem(key);
      if (raw) {
        saved = JSON.parse(raw);
        if (saved.action !== form.getAttribute('action') || !saved.payload || !/^[a-f0-9-]{36}$/.test(saved.payload.OperacionId)) throw new Error('Estado incompatible');
        for (const [name, value] of Object.entries(saved.payload)) {
          const control = form.elements.namedItem(name);
          if (control && typeof value === 'string') control.value = value;
        }
        lock();
      }
      // Comprobar almacenamiento ANTES de una escritura, incluso en navegacion privada.
      sessionStorage.setItem('P3_BOD:probe', '1'); sessionStorage.removeItem('P3_BOD:probe');
    } catch {
      storageReady = false; submit.disabled = true; retry.disabled = true;
      announce('No se puede conservar una referencia segura en esta pestana. Escrituras bloqueadas; las consultas siguen disponibles.');
    }
    async function send() {
      if (busy || !storageReady || saved?.confirmed) return;
      busy = true; retry.disabled = true;
      try {
        const response = await fetch(saved.action, { method: 'POST', credentials: 'same-origin', redirect: 'error', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name=csrf-token]').content }, body: JSON.stringify(saved.payload) });
        const data = await response.json();
        if (!response.ok) {
          saved.rejected = [400, 403, 404].includes(response.status) && data.incierto === false;
          sessionStorage.setItem(key, JSON.stringify(saved));
          newRequest.hidden = !saved.rejected;
          announce(data.error || 'Resultado no confirmado. Consulta la referencia.', status.href);
          return;
        }
        saved.confirmed = true;
        sessionStorage.setItem(key, JSON.stringify(saved));
        retry.hidden = true;
        newRequest.hidden = false;
        announce('Operacion confirmada. La referencia queda bloqueada para evitar un segundo envio.', data.url);
      } catch { announce('Respuesta incierta. No se ha reenviado automaticamente. Conserva la referencia y consulta antes de reintentar la MISMA carga.', status.href); }
      finally { busy = false; retry.disabled = false; }
    }
    form.addEventListener('submit', event => {
      event.preventDefault();
      if (saved || !storageReady || !form.reportValidity()) return;
      const payload = Object.fromEntries(new FormData(form));
      saved = { action: form.getAttribute('action'), payload, confirmed: false };
      try { sessionStorage.setItem(key, JSON.stringify(saved)); }
      catch { saved = null; storageReady = false; submit.disabled = true; announce('No se envio: no fue posible conservar la referencia.'); return; }
      lock();
      void send();
    });
    retry.addEventListener('click', () => {
      if (window.confirm('Consulta primero la referencia. Reintentar conserva exactamente el UUID, version y carga originales. Continuar?')) void send();
    });
    newRequest.addEventListener('click', () => {
      if ((saved?.confirmed || saved?.rejected) && window.confirm('La operacion anterior esta confirmada o fue rechazada sin incertidumbre. Iniciar OTRA solicitud con una referencia nueva?')) {
        sessionStorage.removeItem(key);
        location.reload();
      }
    });
  }
})();
