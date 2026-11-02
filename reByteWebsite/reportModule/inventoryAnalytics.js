(function () {
  const API_BASES = ['http://localhost:3000', 'http://127.0.0.1:3000'];
  const PRODUCT_ENDPOINT = '/api/shop/admin/products';
  const STATUS_LABELS = ['Listed', 'Hidden', 'Draft', 'Rented', 'Sold', 'Lost', 'Other'];

  function toDate(value) {
    if (!value) return null;
    if (typeof value.toDate === 'function') return value.toDate();
    if (typeof value === 'object') {
      const seconds = Number(value.seconds ?? value._seconds);
      if (Number.isFinite(seconds) && seconds > 0) return new Date(seconds * 1000);
      return null;
    }
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  function productDate(product) {
    return toDate(product.dateAdded || product.createdAt || product.created_at);
  }

  function monthKey(date) {
    return date ? `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}` : '';
  }

  function getMonthKey(product) {
    return monthKey(productDate(product));
  }

  async function fetchProducts() {
    const attempts = [];
    for (const base of API_BASES) {
      const url = `${base}${PRODUCT_ENDPOINT}`;
      try {
        const response = await fetch(url, { headers: { Accept: 'application/json' } });
        if (response.status === 404) {
          attempts.push(`${url} returned HTTP 404`);
          continue;
        }
        const body = await response.text();
        let data;
        try {
          data = body ? JSON.parse(body) : {};
        } catch (_) {
          throw new Error(`${url} returned a non-JSON response (HTTP ${response.status}).`);
        }
        if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}: ${data.error || data.message || 'No error details returned.'}`);
        if (data.success === false || !Array.isArray(data.products)) {
          throw new Error(data.error || 'The products endpoint did not return a products list.');
        }
        return data.products;
      } catch (error) {
        if (error.message.startsWith('http')) throw error;
        attempts.push(`${url}: ${error.message || 'Network or CORS error'}`);
      }
    }
    throw new Error(`Could not load Firebase product records. ${attempts.join('; ')}`);
  }

  function availableMonths(products) {
    return [...new Set(products.map(getMonthKey).filter(Boolean))].sort((a, b) => b.localeCompare(a));
  }

  function getStatus(product) {
    const raw = String(product.listingStatus || product.rawStatus || product.status || '').toLowerCase();
    const rental = String(product.rentalStatus || '').toLowerCase();
    if (['lost', 'loss'].includes(raw) || ['lost', 'missing'].includes(rental)) return 'Lost';
    if (['sold', 'purchased'].includes(raw) || ['sold', 'purchased'].includes(rental)) return 'Sold';
    if (['renting', 'rented', 'returning', 'active'].includes(rental) || ['renting', 'rented', 'rent'].includes(raw)) return 'Rented';
    if (raw === 'listed' || raw === 'active') return 'Listed';
    if (raw === 'hidden') return 'Hidden';
    if (raw === 'draft') return 'Draft';
    return 'Other';
  }

  function getModel(product) {
    const model = String(product.model || '').trim();
    if (model) return model;
    const title = String(product.listingTitle || '').trim();
    if (title) return title;
    return `${product.brand || 'Unknown'} device`;
  }

  function summarize(products, selectedMonth) {
    const records = products.filter(product => getMonthKey(product) === selectedMonth);
    const statusCounts = Object.fromEntries(STATUS_LABELS.map(label => [label, 0]));
    const modelMap = new Map();
    const weeklyAdded = [0, 0, 0, 0, 0];

    records.forEach(product => {
      const status = getStatus(product);
      statusCounts[status] += 1;
      const model = getModel(product);
      if (!modelMap.has(model)) modelMap.set(model, { model, added: 0, active: 0, sold: 0, rented: 0 });
      const modelRow = modelMap.get(model);
      modelRow.added += 1;
      if (['Listed', 'Hidden', 'Draft'].includes(status)) modelRow.active += 1;
      if (status === 'Sold') modelRow.sold += 1;
      if (status === 'Rented') modelRow.rented += 1;

      const date = productDate(product);
      if (date) weeklyAdded[Math.min(4, Math.floor((date.getDate() - 1) / 7))] += 1;
    });

    const models = [...modelMap.values()].sort((a, b) => b.added - a.added || a.model.localeCompare(b.model));
    const availableStock = statusCounts.Listed + statusCounts.Hidden + statusCounts.Draft;
    const topModel = models[0] || null;
    const topFive = models.slice(0, 5);
    const bottomFive = [...models].sort((a, b) => a.added - b.added || a.model.localeCompare(b.model)).slice(0, 5);

    return {
      month: selectedMonth,
      totalAdded: records.length,
      availableStock,
      sold: statusCounts.Sold,
      rented: statusCounts.Rented,
      lost: statusCounts.Lost,
      topModel,
      topModelShare: records.length && topModel ? (topModel.added / records.length) * 100 : 0,
      statusCounts,
      models,
      topFive,
      bottomFive,
      weeklyAdded
    };
  }

  window.InventoryAnalytics = { fetchProducts, availableMonths, getMonthKey, summarize, STATUS_LABELS };
})();
