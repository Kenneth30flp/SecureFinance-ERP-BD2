'use strict';
window.SecureFinanceMessages = Object.freeze({
  show(target, text, tone = 'info') {
    const markers = { success: '✓', danger: '×', warning: '!', info: 'i' };
    const type = Object.hasOwn(markers, tone) ? tone : 'info';
    target.className = 'alert desk-message alert-' + type;
    target.setAttribute('data-marker', markers[type]);
    target.setAttribute('role', type === 'danger' || type === 'warning' ? 'alert' : 'status');
    target.setAttribute('aria-live', type === 'danger' || type === 'warning' ? 'assertive' : 'polite');
    target.setAttribute('aria-atomic', 'true');
    target.textContent = text;
    target.hidden = false;
  },
});
