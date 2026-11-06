(function () {
  const API_BASE = 'http://localhost:3000';
  function isPastMonth(month) {
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(String(month || ''))) return false;
    const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kuala_Lumpur', year: 'numeric', month: '2-digit' }).formatToParts(new Date());
    const current = `${parts.find(part => part.type === 'year').value}-${parts.find(part => part.type === 'month').value}`;
    return month < current;
  }
  function localKey(type, month) {
    return 'rebyte-report-snapshot:' + type + ':' + month;
  }
  function getLocal(type, month) {
    try {
      const value = localStorage.getItem(localKey(type, month));
      return value ? JSON.parse(value) : null;
    } catch (_) { return null; }
  }
  function saveLocal(type, month, data) {
    try { localStorage.setItem(localKey(type, month), JSON.stringify(data)); }
    catch (error) { console.warn('Could not keep a local report snapshot:', error.message); }
  }
  function cachedMonths(type) {
    const prefix = 'rebyte-report-snapshot:' + type + ':';
    const months = [];
    try {
      for (let index = 0; index < localStorage.length; index += 1) {
        const key = localStorage.key(index);
        if (!key || !key.startsWith(prefix)) continue;
        const month = key.slice(prefix.length);
        if (/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) months.push(month);
      }
    } catch (_) {}
    return [...new Set(months)].sort((a, b) => b.localeCompare(a));
  }
  async function request(path, options) {
    if (typeof ReByteAuth === 'undefined' || typeof ReByteAuth.authFetch !== 'function') {
      throw new Error('Administrator sign-in is required to access saved report snapshots.');
    }
    const response = await ReByteAuth.authFetch(API_BASE + path, options);
    const body = await response.text();
    let data;
    try { data = body ? JSON.parse(body) : {}; }
    catch (_) { throw new Error('Report snapshot API returned an invalid response (HTTP ' + response.status + ').'); }
    if (!response.ok || data.success === false) {
      throw new Error(data.error || ('Report snapshot API returned HTTP ' + response.status + '.'));
    }
    return data;
  }
  async function get(type, month) {
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(String(month || ''))) return null;
    const local = getLocal(type, month);
    if (local) return local;
    try {
      const data = await request('/api/report-cache/' + encodeURIComponent(type) + '/' + encodeURIComponent(month), {
        headers: { Accept: 'application/json' }
      });
      const report = data.found && data.report ? data.report.data : null;
      if (report) saveLocal(type, month, report);
      return report;
    } catch (error) {
      console.warn('Could not read saved report snapshot:', error.message);
      return null;
    }
  }
  async function months(type) {
    const localMonths = cachedMonths(type);
    try {
      const data = await request('/api/report-cache/' + encodeURIComponent(type), {
        headers: { Accept: 'application/json' }
      });
      return [...new Set([...localMonths, ...(Array.isArray(data.months) ? data.months : [])])].sort((a, b) => b.localeCompare(a));
    } catch (error) {
      console.warn('Could not list saved report months:', error.message);
      return localMonths;
    }
  }
  async function save(type, month, data) {
    const parts = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kuala_Lumpur', year: 'numeric', month: '2-digit' }).formatToParts(new Date());
    const current = `${parts.find(part => part.type === 'year').value}-${parts.find(part => part.type === 'month').value}`;
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(String(month || '')) || month > current || !data || typeof data !== 'object') return null;
    saveLocal(type, month, data);
    try {
      const result = await request('/api/report-cache', {
        method: 'PUT',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        body: JSON.stringify({ reportType: type, month: month, data: data })
      });
      return result.report && result.report.data ? result.report.data : data;
    } catch (error) {
      console.warn('Could not save report snapshot:', error.message);
      return null;
    }
  }
  window.ReportSnapshots = { get: get, months: months, cachedMonths: cachedMonths, save: save, isPastMonth: isPastMonth };
})();
