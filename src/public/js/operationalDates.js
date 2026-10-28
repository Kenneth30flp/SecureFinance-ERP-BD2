'use strict';

// Shared by Node date-filter services and the browser. SQL timestamps remain UTC.
(() => {
  const timeZone = 'America/Guatemala';
  const zoneLabel = 'Guatemala (UTC−6)';
  const options = { timeZone, day: '2-digit', month: '2-digit', year: 'numeric' };
  const dateFormatter = new Intl.DateTimeFormat('es-GT', options);
  const timeFormatter = new Intl.DateTimeFormat('es-GT', {
    ...options, hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
  });
  function instant(value) {
    if (value === null || value === undefined || value === '') return null;
    // DATETIME2 strings without an offset represent UTC, never the host timezone.
    if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(value)
      && !/(?:Z|[+-]\d{2}:\d{2})$/i.test(value)) value += 'Z';
    const date = new Date(value);
    return Number.isFinite(date.getTime()) ? date : null;
  }
  const formatDate = value => { const date = instant(value); return date ? dateFormatter.format(date) : 'No registrada'; };
  const formatDateTime = value => { const date = instant(value); return date ? timeFormatter.format(date) : 'No registrada'; };
  function localDayBoundary(value, end = false, inclusive = false) {
    if (!value) return null;
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new RangeError('Fecha inválida.');
    const utc = new Date(value + 'T00:00:00.000Z');
    if (!Number.isFinite(utc.getTime()) || utc.toISOString().slice(0, 10) !== value) throw new RangeError('Fecha inválida.');
    // Guatemala's operational calendar is UTC−6, with no daylight saving time.
    return new Date(utc.getTime() + 6 * 3600000 + (end ? 86400000 - (inclusive ? 1 : 0) : 0));
  }
  const api = { timeZone, zoneLabel, formatDate, formatDateTime, localDayBoundary };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else globalThis.SecureFinanceDates = api;
})();
