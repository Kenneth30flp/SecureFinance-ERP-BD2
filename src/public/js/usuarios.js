'use strict';
const panel = document.getElementById('roles-panel');
const form = document.getElementById('roles-form');
const message = document.getElementById('roles-message');
let selected = null;
let opener = null;
let busy = false;
const dialogMessage = document.getElementById('roles-dialog-message');
const notify = (text, tone = 'danger') => window.SecureFinanceMessages.show(panel.open ? dialogMessage : message, text, tone);
function controls(disabled) {
  busy = disabled;
  form.setAttribute('aria-busy', String(disabled));
  document.getElementById('save-roles').textContent = disabled && panel.open ? 'Guardando…' : 'Guardar cambios';
  document.querySelectorAll('[data-user-id], #roles-form button, #roles-form input').forEach(el => { el.disabled = disabled; });
}
async function json(response) {
  const data = await response.json().catch(() => ({}));
  if (!response.ok || response.redirected) throw new Error(data.error || 'No fue posible completar la solicitud. Actualiza la página.');
  return data;
}
document.querySelectorAll('[data-user-id]').forEach(button => button.addEventListener('click', async () => {
  if (busy) return;
  controls(true); message.hidden = true; dialogMessage.hidden = true;
  try {
    const data = await json(await fetch('/usuarios/' + button.dataset.userId + '/roles'));
    selected = button.dataset.userId; opener = button;
    document.getElementById('selected-user').textContent = button.dataset.userName;
    document.getElementById('selected-fullname').textContent = button.dataset.userFullname;
    document.getElementById('selected-state').textContent = button.dataset.userActive;
    form.querySelectorAll('input').forEach(input => { input.checked = data.roles.some(r => r.RolId === Number(input.value)); });
    panel.showModal(); document.getElementById('roles-title').focus();
  } catch (error) { notify(error.message); }
  finally { controls(false); }
}));
function cancel() { if (busy) return; panel.close(); selected = null; opener?.focus(); }
document.getElementById('cancel-roles').addEventListener('click', cancel);
panel.addEventListener('cancel', event => { event.preventDefault(); cancel(); });
form.addEventListener('submit', async event => {
  event.preventDefault(); if (busy || !selected) return;
  const Roles = [...form.querySelectorAll('input:checked')].map(input => Number(input.value));
  controls(true); message.hidden = true; dialogMessage.hidden = true;
  try {
    const data = await json(await fetch('/usuarios/' + selected + '/roles', {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': form.dataset.csrf }, body: JSON.stringify({ Roles }),
    }));
    const names = [...form.querySelectorAll('input:checked')].map(input => input.nextElementSibling.querySelector('strong').textContent);
    opener.closest('tr').children[4].textContent = names.join(', ') || 'Sin roles activos';
    panel.close(); selected = null; notify(data.mensaje, 'success');
  } catch (error) { notify(error.message); }
  finally { controls(false); if (!panel.open) opener?.focus(); }
});
