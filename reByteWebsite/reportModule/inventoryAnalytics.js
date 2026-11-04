(function () {
  const API_BASES = ['http://localhost:3000', 'http://127.0.0.1:3000'];
  const PRODUCT_ENDPOINT = '/api/shop/admin/products';
  const STATUS_LABELS = ['Listed', 'Hidden', 'Draft', 'Rented', 'Sold', 'Lost', 'Other'];

  function toDate(value) {
    if (!value) return null;
    if (typeof value.toDate === 'function') return value.toDate();
    if (typeof value === 'number' || /^\d{10,13}$/.test(String(value))) {
      const numeric = Number(value);
      return new Date(numeric < 1e12 ? numeric * 1000 : numeric);
    }
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

  async function fetchSalesSummary(month) {
    const attempts = [];
    const path = `/api/transaction-management/analytics/summary?month=${encodeURIComponent(month)}`;
    for (const base of API_BASES) {
      const url = `${base}${path}`;
      try {
        const response = await fetch(url, { headers: { Accept: 'application/json' } });
        const body = await response.text();
        let data;
        try { data = body ? JSON.parse(body) : {}; }
        catch (_) { throw new Error(`${url} returned a non-JSON response (HTTP ${response.status}).`); }
        if (!response.ok || !data.success) throw new Error(`${url} returned HTTP ${response.status}: ${data.error || data.message || 'The analytics summary was unsuccessful.'}`);
        return data;
      } catch (error) {
        attempts.push(error.message || `${url} failed.`);
      }
    }
    throw new Error(`Could not load monthly sales transactions. ${attempts.join('; ')}`);
  }

  function cleanId(value) {
    return String(value || '').trim().replace(/^#/, '');
  }

  function transactionDate(transaction) {
    return toDate(transaction.transactionDate || transaction.dateTime || transaction.createdAt || transaction.created_at);
  }

  function transactionProductIds(transaction) {
    const ids = [];
    if (transaction.productID) ids.push(transaction.productID);
    if (Array.isArray(transaction.productIDs)) ids.push(...transaction.productIDs);
    if (Array.isArray(transaction.items)) {
      transaction.items.forEach(item => {
        if (item.productID) ids.push(item.productID);
        else if (item.id) ids.push(item.id);
      });
    }
    return [...new Set(ids.map(cleanId).filter(Boolean))];
  }

  function inventoryTransactionStatus(transaction) {
    const categories = [transaction.category, transaction.type, transaction.transactionType]
      .map(value => String(value || '').toLowerCase());
    if (categories.some(value => value.includes('refund'))) return 'Listed';
    if (categories.some(value => value.includes('purchase'))) return 'Sold';
    return '';
  }

  function isSuccessfulInventoryTransaction(transaction) {
    if (!inventoryTransactionStatus(transaction)) return false;
    if (inventoryTransactionStatus(transaction) === 'Sold' && transaction.isNegative === true) return false;
    const status = String(transaction.transactionStatus || transaction.status || '').toLowerCase();
    return !status || ['success', 'successful', 'completed', 'complete', 'paid', 'approved', 'succeeded', 'confirmed'].includes(status);
  }

  async function fetchInventoryTransactions() {
    const attempts = [];
    const limit = 100;
    for (const base of API_BASES) {
      const transactions = [];
      let failed = false;
      for (let page = 1; page <= 200; page += 1) {
        const query = new URLSearchParams({ category: 'all', page: String(page), limit: String(limit) });
        const url = `${base}/api/transaction-management/transactions?${query}`;
        try {
          const response = await fetch(url, { headers: { Accept: 'application/json' } });
          const body = await response.text();
          let data;
          try { data = body ? JSON.parse(body) : {}; }
          catch (_) { throw new Error(`${url} returned a non-JSON response (HTTP ${response.status}).`); }
          if (!response.ok || !data.success || !Array.isArray(data.transactions)) {
            throw new Error(`${url} returned HTTP ${response.status}: ${data.error || data.message || 'No transaction list returned.'}`);
          }
          transactions.push(...data.transactions.filter(isSuccessfulInventoryTransaction));
          const totalPages = Number(data.totalPages || data.pagination?.totalPages || 0);
          if ((totalPages && page >= totalPages) || (!totalPages && data.transactions.length < limit) || !data.transactions.length) break;
        } catch (error) {
          attempts.push(error.message || `${url} failed.`);
          failed = true;
          break;
        }
      }
      if (!failed) return transactions;
    }
    throw new Error(`Could not load purchase and refund transaction records. ${attempts.join('; ')}`);
  }

  async function fetchSaleEvents(products) {
    const transactions = await fetchInventoryTransactions();
    const productById = new Map();
    products.forEach(product => {
      [product.productID, product.id, product.documentID].map(cleanId).filter(Boolean).forEach(id => productById.set(id, product));
    });
    const knownProductIds = new Set(productById.keys());
    const inventoryEvents = [];
    let unlinkedPurchases = 0;
    transactions.forEach(transaction => {
      const date = transactionDate(transaction);
      if (!date) return;
      const productIds = transactionProductIds(transaction);
      const status = inventoryTransactionStatus(transaction);
      if (status === 'Sold' && !productIds.length && transaction.orderID) unlinkedPurchases += 1;
      productIds.forEach(productID => {
        if (knownProductIds.size && !knownProductIds.has(productID)) return;
        const transactionID = cleanId(transaction.transactionID || transaction.id || transaction.documentID);
        inventoryEvents.push({
          productID,
          date,
          status,
          previousStatus: status === 'Listed' ? 'Sold' : 'Listed',
          orderID: cleanId(transaction.orderID),
          transactionID
        });
      });
    });
    const successfulPurchasePairs = new Set(inventoryEvents
      .filter(event => event.status === 'Sold' && event.orderID)
      .map(event => `${event.orderID}|${event.productID}`));
    const acceptedEvents = inventoryEvents.filter(event => {
      if (event.status !== 'Listed') return true;
      if (!event.orderID || !successfulPurchasePairs.has(`${event.orderID}|${event.productID}`)) return false;

      const product = productById.get(event.productID);
      const currentStatus = product ? getStatus(product) : '';
      const isCurrentlyCarried = ['Draft', 'Listed', 'Hidden', 'Rented', 'Unknown Carried'].includes(currentStatus);
      const hasLaterSuccessfulSale = inventoryEvents.some(candidate =>
        candidate.productID === event.productID &&
        candidate.status === 'Sold' &&
        (candidate.date > event.date || (candidate.date.getTime() === event.date.getTime() && candidate.transactionID.localeCompare(event.transactionID) > 0))
      );
      return isCurrentlyCarried || hasLaterSuccessfulSale;
    });
    const sales = acceptedEvents.sort((a, b) => a.date - b.date || a.transactionID.localeCompare(b.transactionID) || a.productID.localeCompare(b.productID));
    if (unlinkedPurchases) {
      sales.warning = `${unlinkedPurchases} purchase transaction(s) have no product IDs in the transaction API response, so their sale dates cannot be assigned to individual products.`;
    }
    return sales;
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
    const brand = String(product.brand || '').trim();
    const model = String(product.model || '').trim();
    const title = String(product.listingTitle || '').trim();
    const label = model || title || `${brand || 'Unknown'} device`;
    return brand && !label.toLowerCase().startsWith(brand.toLowerCase()) ? `${brand} ${label}` : label;
  }

  function productId(product) {
    return cleanId(product.productID || product.id || product.documentID || product.productId);
  }

  function statusName(value) {
    const raw = String(value || '').toLowerCase();
    if (['lost', 'loss'].includes(raw)) return 'Lost';
    if (['sold', 'purchased'].includes(raw)) return 'Sold';
    if (['renting', 'rented', 'returning'].includes(raw)) return 'Rented';
    if (['listed', 'active'].includes(raw)) return 'Listed';
    if (raw === 'hidden') return 'Hidden';
    if (raw === 'draft') return 'Draft';
    return 'Other';
  }

  function historyEvents(product) {
    const history = product.statusHistory || product.inventoryHistory || product.statusChanges || [];
    const events = Array.isArray(history) ? history.map(event => ({
      date: toDate(event.changedAt || event.updatedAt || event.timestamp || event.createdAt || event.date),
      status: statusName(event.status || event.toStatus || event.newStatus || event.listingStatus),
      previousStatus: statusName(event.previousStatus || event.fromStatus || event.oldStatus)
    })).filter(event => event.date && event.status !== 'Other') : [];

    const current = getStatus(product);
    const statusDate = toDate(product.statusUpdatedAt || product.statusChangedAt || (current === 'Sold' ? product.soldAt || product.purchasedAt || product.dateSold : '') || (current === 'Lost' ? product.lostAt || product.dateLost || product.lossDate || product.updatedAt : ''));
    if (statusDate && ['Sold', 'Lost'].includes(current) && !events.some(event => event.status === current)) {
      events.push({ date: statusDate, status: current, previousStatus: '' });
    }
    return events.sort((a, b) => a.date - b.date);
  }

  function previousStatusForTransition(targetStatus) {
    if (['Listed', 'Rented'].includes(targetStatus)) return 'Draft';
    if (['Hidden', 'Sold'].includes(targetStatus)) return 'Listed';
    if (targetStatus === 'Lost') return 'Rented';
    return '';
  }

  function statusAt(product, cutoff, selectedMonthIsCurrent, salesByProductId) {
    const added = productDate(product);
    if (!added || added > cutoff) return { included: false, status: '' };
    if (selectedMonthIsCurrent) return { included: true, status: getStatus(product) };

    const saleEvents = salesByProductId?.get(productId(product)) || [];
    const timeline = [
      ...historyEvents(product),
      ...saleEvents.map(event => ({
        date: event.date,
        status: event.status || 'Sold',
        previousStatus: event.previousStatus || 'Listed',
        transactionID: event.transactionID || ''
      }))
    ].sort((a, b) => a.date - b.date || String(a.transactionID || '').localeCompare(String(b.transactionID || '')));
    const nextTransition = timeline.find(event => event.date > cutoff);
    if (nextTransition) {
      const previousStatus = nextTransition.previousStatus || previousStatusForTransition(nextTransition.status);
      if (previousStatus) return { included: true, status: previousStatus };
    }

    const eventsThroughCutoff = timeline.filter(event => event.date <= cutoff);
    if (eventsThroughCutoff.length) {
      const status = eventsThroughCutoff[eventsThroughCutoff.length - 1].status;
      if (status) return { included: true, status };
    }

    const updated = toDate(product.statusUpdatedAt || product.updatedAt || product.statusChangedAt);
    if (updated && updated > cutoff) {
      const current = getStatus(product);
      const previousStatus = previousStatusForTransition(current);
      if (previousStatus) return { included: true, status: previousStatus };
      return { included: true, status: '', unknown: true };
    }
    if (!updated && ['Sold', 'Lost'].includes(getStatus(product))) return { included: true, status: '', unknown: true };
    return { included: true, status: getStatus(product) };
  }

  function monthCutoff(month, endOfMonth) {
    const [year, number] = month.split('-').map(Number);
    return endOfMonth ? new Date(year, number, 0, 23, 59, 59, 999) : new Date(year, number - 1, 1, 0, 0, 0, 0);
  }

  function inventoryAt(products, cutoff, selectedMonthIsCurrent, salesByProductId) {
    const statusCounts = Object.fromEntries(STATUS_LABELS.map(label => [label, 0]));
    let unknown = 0;
    for (const product of products) {
      const result = statusAt(product, cutoff, selectedMonthIsCurrent, salesByProductId);
      if (!result.included) continue;
      if (result.unknown || !result.status) unknown += 1;
      else statusCounts[result.status] = (statusCounts[result.status] || 0) + 1;
    }
    const carried = statusCounts.Draft + statusCounts.Listed + statusCounts.Hidden + statusCounts.Rented + (statusCounts['Unknown Carried'] || 0);
    return { statusCounts, carried, complete: unknown === 0, unknown };
  }

  function summarize(products, selectedMonth, _salesSummary, saleEvents = []) {
    const records = products.filter(product => getMonthKey(product) === selectedMonth);
    const [year, month] = selectedMonth.split('-').map(Number);
    const selectedMonthIsCurrent = year === new Date().getFullYear() && month === new Date().getMonth() + 1;
    const openingCutoff = new Date(year, month - 1, 0, 23, 59, 59, 999);
    const closingCutoff = selectedMonthIsCurrent ? new Date() : monthCutoff(selectedMonth, true);
    const salesByProductId = new Map();
    saleEvents.forEach(event => {
      const key = cleanId(event.productID);
      if (!key) return;
      if (!salesByProductId.has(key)) salesByProductId.set(key, []);
      salesByProductId.get(key).push(event);
    });
    salesByProductId.forEach(events => events.sort((a, b) => a.date - b.date || String(a.transactionID || '').localeCompare(String(b.transactionID || ''))));
    const openingSnapshot = inventoryAt(products, openingCutoff, false, salesByProductId);
    const closingSnapshot = inventoryAt(products, closingCutoff, selectedMonthIsCurrent, salesByProductId);
    const modelMap = new Map();
    const ensureModel = model => {
      if (!modelMap.has(model)) modelMap.set(model, {
        model, openingStock: 0, unknownOpening: 0, added: 0,
        soldDuringMonth: 0, lostDuringMonth: 0, closingStock: 0, unknownClosing: 0
      });
      return modelMap.get(model);
    };
    const weeklyAdded = [0, 0, 0, 0, 0];
    const weeklyBrandCounts = Array.from({ length: 5 }, () => new Map());

    products.forEach(product => {
      const openingStatus = statusAt(product, openingCutoff, false, salesByProductId);
      if (!openingStatus.included) return;
      const row = ensureModel(getModel(product));
      if (openingStatus.unknown || !openingStatus.status) row.unknownOpening += 1;
      else if (['Draft', 'Listed', 'Hidden', 'Rented', 'Unknown Carried'].includes(openingStatus.status)) row.openingStock += 1;
    });

    records.forEach(product => {
      const model = getModel(product);
      ensureModel(model).added += 1;
      const date = productDate(product);
      if (date) {
        const weekIndex = Math.min(4, Math.floor((date.getDate() - 1) / 7));
        weeklyAdded[weekIndex] += 1;
        const brand = String(product.brand || product.brandName || product.manufacturer || 'Other').trim() || 'Other';
        weeklyBrandCounts[weekIndex].set(brand, (weeklyBrandCounts[weekIndex].get(brand) || 0) + 1);
      }
    });

    const soldByModel = new Map();
    const lostByModel = new Map();
    const unknownSoldByModel = new Set();
    const unknownLostByModel = new Set();
    const soldInPeriod = new Set();
    const lostInPeriod = new Set();
    const transactionEventsInPeriod = new Set();
    const latestPeriodEventByProductId = new Map();
    saleEvents.forEach(event => {
      if (monthKey(event.date) !== selectedMonth || !['Sold', 'Listed'].includes(event.status)) return;
      const id = cleanId(event.productID);
      if (!id) return;
      transactionEventsInPeriod.add(id);
      const previous = latestPeriodEventByProductId.get(id);
      if (!previous || event.date > previous.date || (event.date.getTime() === previous.date.getTime() && String(event.transactionID || '').localeCompare(String(previous.transactionID || '')) > 0)) {
        latestPeriodEventByProductId.set(id, event);
      }
    });
    latestPeriodEventByProductId.forEach((event, id) => {
      if (event.status !== 'Sold') return;
      const product = products.find(item => productId(item) === cleanId(event.productID));
      if (!product) return;
      if (soldInPeriod.has(id)) return;
      soldInPeriod.add(id);
      const model = getModel(product);
      ensureModel(model);
      soldByModel.set(model, (soldByModel.get(model) || 0) + 1);
    });
    products.forEach(product => {
      const model = getModel(product);
      const events = historyEvents(product);
      const productSales = salesByProductId.get(productId(product)) || [];
      if (getStatus(product) === 'Sold' && !productSales.some(event => event.status === 'Sold') && !events.some(event => event.status === 'Sold')) {
        unknownSoldByModel.add(model);
      }
      if (getStatus(product) === 'Lost' && !events.some(event => event.status === 'Lost')) unknownLostByModel.add(model);
      events.forEach(event => {
        if (monthKey(event.date) !== selectedMonth) return;
        if (event.status === 'Sold') {
          const id = productId(product);
          if (id && transactionEventsInPeriod.has(id)) return;
          if (!id || !soldInPeriod.has(id)) {
            if (id) soldInPeriod.add(id);
            soldByModel.set(model, (soldByModel.get(model) || 0) + 1);
          }
        }
        if (event.status === 'Lost') {
          const id = productId(product);
          if (id && lostInPeriod.has(id)) return;
          if (id) lostInPeriod.add(id);
          lostByModel.set(model, (lostByModel.get(model) || 0) + 1);
        }
      });
      const closingStatus = statusAt(product, closingCutoff, selectedMonthIsCurrent, salesByProductId);
      if (closingStatus.included && (closingStatus.unknown || !closingStatus.status)) {
        ensureModel(model).unknownClosing += 1;
      }
      if (closingStatus.included && ['Draft', 'Listed', 'Hidden', 'Rented', 'Unknown Carried'].includes(closingStatus.status)) {
        ensureModel(model).closingStock += 1;
      }
    });

    const overlappingExitByModel = new Map();
    soldInPeriod.forEach(id => {
      if (!lostInPeriod.has(id)) return;
      const product = products.find(item => productId(item) === id);
      if (!product) return;
      const model = getModel(product);
      overlappingExitByModel.set(model, (overlappingExitByModel.get(model) || 0) + 1);
    });

    const models = [...modelMap.values()].map(row => {
      const soldDuringMonth = soldByModel.has(row.model)
        ? soldByModel.get(row.model)
        : (unknownSoldByModel.has(row.model) ? null : 0);
      const lostDuringMonth = unknownLostByModel.has(row.model) && !lostByModel.has(row.model)
        ? null
        : (lostByModel.get(row.model) || 0);
      const availableForSale = row.openingStock + row.added;
      return {
        ...row,
        soldDuringMonth,
        lostDuringMonth,
        sellThroughRate: soldDuringMonth == null || row.unknownOpening
          ? null
          : (availableForSale ? soldDuringMonth / availableForSale * 100 : 0),
        unknownLostDuringMonth: unknownLostByModel.has(row.model),
        overlappingExitUnits: overlappingExitByModel.get(row.model) || 0
      };
    });
    const compareDescNullsLast = (a, b) => {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b - a;
    };
    const compareModelRank = (a, b) =>
      compareDescNullsLast(a.soldDuringMonth, b.soldDuringMonth) ||
      compareDescNullsLast(a.sellThroughRate, b.sellThroughRate) ||
      a.closingStock - b.closingStock ||
      a.model.localeCompare(b.model);
    models.sort((a, b) => b.added - a.added || compareModelRank(a, b));
    const bottomFive = [...models].sort((a, b) => a.added - b.added || compareModelRank(a, b)).slice(0, 5);
    const topFive = models.slice(0, 5);
    const soldEvents = soldInPeriod.size || [...soldByModel.values()].reduce((sum, value) => sum + value, 0);
    const soldDuringMonth = unknownSoldByModel.size ? null : soldEvents;
    const statusCounts = closingSnapshot.statusCounts;
    const lostDuringMonth = [...lostByModel.values()].reduce((sum, value) => sum + value, 0);
    const lostMovementKnown = unknownLostByModel.size === 0;
    const knownLostDuringMonth = lostMovementKnown || lostByModel.size ? lostDuringMonth : null;
    const closingInventory = closingSnapshot.complete ? closingSnapshot.carried : null;
    const openingInventory = openingSnapshot.complete
      ? openingSnapshot.carried
      : (selectedMonthIsCurrent && closingSnapshot.complete && soldDuringMonth != null && knownLostDuringMonth != null
        ? closingSnapshot.carried + soldDuringMonth + knownLostDuringMonth - records.length
        : null);
    const inventoryPeriodComplete = closingSnapshot.complete && (openingSnapshot.complete || openingInventory != null);

    return {
      month: selectedMonth,
      totalAdded: records.length,
      openingInventory,
      knownOpeningInventory: openingSnapshot.carried,
      closingInventory,
      knownClosingInventory: closingSnapshot.carried,
      currentInventory: closingInventory,
      historicalSnapshotAvailable: inventoryPeriodComplete,
      openingSnapshotAvailable: openingSnapshot.complete || openingInventory != null,
      closingSnapshotAvailable: closingSnapshot.complete,
      unknownSnapshotRecords: Math.max(openingSnapshot.unknown, closingSnapshot.unknown),
      soldDuringMonth,
      sold: soldDuringMonth,
      lostDuringMonth: knownLostDuringMonth,
      overlappingExitUnits: [...overlappingExitByModel.values()].reduce((sum, value) => sum + value, 0),
      availableStock: closingInventory,
      topModel: models[0] || null,
      topModelShare: records.length && models[0] ? (models[0].added / records.length) * 100 : 0,
      statusCounts,
      carryStatusCounts: { Draft: statusCounts.Draft, Listed: statusCounts.Listed, Hidden: statusCounts.Hidden, Rented: statusCounts.Rented, 'Unknown Carried': statusCounts['Unknown Carried'] || 0 },
      exitStatusCounts: { Sold: soldDuringMonth, Lost: knownLostDuringMonth },
      models,
      topFive,
      bottomFive,
      weeklyAdded,
      weeklyBrandBreakdown: weeklyBrandCounts.map(counts => [...counts.entries()]
        .map(([brand, count]) => ({ brand, count }))
        .sort((a, b) => b.count - a.count || a.brand.localeCompare(b.brand))
        .slice(0, 5))
    };
  }

  function summarizeCurrentStock(products) {
    const statusCounts = Object.fromEntries(STATUS_LABELS.map(label => [label, 0]));
    products.forEach(product => { statusCounts[getStatus(product)] += 1; });
    return {
      total: products.length,
      available: statusCounts.Listed + statusCounts.Hidden + statusCounts.Rented,
      statusCounts
    };
  }

  window.InventoryAnalytics = { fetchProducts, fetchSalesSummary, fetchSaleEvents, availableMonths, getMonthKey, summarize, summarizeCurrentStock, historyEvents, STATUS_LABELS };
})();
