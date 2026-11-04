'use strict';
(() => {
  const form = document.querySelector('#ldf-backup-form');
  if (!form) return;
  const message = document.querySelector('#ldf-message'), button = form.querySelector('button');
  const input = form.elements.OperacionId, reference = document.querySelector('#ldf-operation');
  const key = `ldf-pending:${document.body.dataset.ldfDatabase}:${document.body.dataset.ldfActor}`;
  const say = text => { message.textContent = text; message.hidden = false; message.focus(); };
  const storage = { get() { try { return sessionStorage.getItem(key); } catch { return null; } },
    set(value) { try { sessionStorage.setItem(key, value); return sessionStorage.getItem(key) === value; } catch { return false; } },
    clear() { try { sessionStorage.removeItem(key); } catch { /* no persistent storage */ } } };
  const pending = storage.get();
  if (pending && /^[a-f0-9-]{36}$/i.test(pending)) {
    const row = [...document.querySelectorAll('[data-ldf-operation]')].find(r => r.dataset.ldfOperation === pending.toLowerCase());
    if (row && ['CONFIRMADO','FALLIDO'].includes(row.dataset.ldfState)) storage.clear();
    else { input.value = pending; reference.textContent = pending; say('Hay una solicitud pendiente de confirmación. Consulta el historial; reintentar conserva su referencia y no crea otro respaldo.'); }
  }
  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (button.disabled) return;
    if (!storage.set(input.value)) { say('No se puede conservar la referencia en esta sesión. Habilita el almacenamiento de sesión antes de solicitar el respaldo. No se envió la operación.'); return; }
    button.disabled = true; button.textContent = 'Consultando resultado del respaldo…';
    say('SQL Server está comprobando y ejecutando la solicitud. Conserva esta referencia: ' + input.value);
    try {
      const response = await fetch(form.action, { method: 'POST', credentials: 'same-origin', headers: {
        'Content-Type': 'application/json', 'X-CSRF-Token': form.elements.csrf.value,
      }, body: JSON.stringify({ OperacionId: input.value }) });
      const result = await response.json();
      if (result.operation && ['CONFIRMADO','FALLIDO'].includes(result.operation.Estado)) {
        storage.clear();
        // New GET obtains real post-backup metrics and engine history, no invented progress or timer.
        window.location.assign('/dba/ldf?operation=' + encodeURIComponent(result.operation.OperacionId) + '#log-history'); return;
      }
      say(result.operation?.Mensaje || result.error || 'Respuesta sin confirmación. Consulta el historial antes de reintentar.');
    } catch {
      say('Se interrumpió la respuesta. El respaldo podría haberse completado. Conserva la referencia ' + input.value + ' y actualiza el historial antes de reintentar.');
    }
    button.disabled = false; button.textContent = 'Consultar / reintentar misma referencia';
  });
})();
