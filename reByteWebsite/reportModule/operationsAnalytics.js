(function () {
  const API_BASES = ['http://localhost:3000', 'http://127.0.0.1:3000'];
  const PAGE_SIZE = 5;

  function toDate(value) {
    if (!value) return null;
    if (typeof value.toDate === 'function') return value.toDate();
    if (typeof value === 'object') {
      const seconds = Number(value.seconds ?? value._seconds);
      if (Number.isFinite(seconds) && seconds > 0) return new Date(seconds * 1000);
      return null;
    }
    if (typeof value === 'number' || /^\d{10,13}$/.test(String(value))) {
      const numeric = Number(value);
      return new Date(numeric < 1e12 ? numeric * 1000 : numeric);
    }
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  function taskDate(task) {
    return toDate(task.createdAtMs || task.createdAt || task.orderDate || task.created_at);
  }

  function monthKey(date) {
    return date ? `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}` : '';
  }

  function taskMonth(task) {
    return monthKey(taskDate(task));
  }

  function normalizeStatus(task) {
    return String(task.displayStatus || task.statusBadge || task.status || task.requestStatus || 'Unknown').trim().replace(/[-_]+/g, ' ').replace(/\b\w/g, letter => letter.toUpperCase());
  }

  function taskType(task) {
    const raw = String(task.taskType || task.fulfillmentType || task.type || task.requestType || '').toLowerCase();
    if (raw.includes('collect')) return 'Collection';
    if (raw.includes('deliver')) return 'Delivery';
    if (raw.includes('inspect') || task.tradeInRequestID) return 'Inspection';
    return 'Other';
  }

  function isCompleted(task) {
    const status = normalizeStatus(task).toLowerCase();
    return ['completed', 'delivered', 'collected'].includes(status);
  }

  async function fetchTasks() {
    const attempts = [];
    const tabs = ['unassigned', 'assigned', 'cancelled', 'refunded', 'terminated', 'inspecting', 'completed'];
    for (const base of API_BASES) {
      const tasks = [];
      let failed = false;
      for (const tab of tabs) {
        for (let page = 1; page <= 100; page += 1) {
          const url = `${base}/api/task-assignment/admin/tasks?tab=${encodeURIComponent(tab)}&page=${page}&limit=${PAGE_SIZE}`;
          try {
            const response = await fetch(url, { headers: { Accept: 'application/json' } });
            const body = await response.text();
            let data;
            try { data = body ? JSON.parse(body) : {}; }
            catch (_) { throw new Error(`${url} returned a non-JSON response (HTTP ${response.status}).`); }
            if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}: ${data.error || data.message || 'No error details returned.'}`);
            if (!data.success || !Array.isArray(data.tasks)) throw new Error(data.error || `The tasks endpoint did not return a tasks list for ${tab}.`);
            tasks.push(...data.tasks);
            const totalPages = Number(data.pagination?.totalPages || data.pagination?.pages || 0);
            if ((totalPages && page >= totalPages) || (!totalPages && data.tasks.length < PAGE_SIZE) || !data.tasks.length) break;
          } catch (error) {
            attempts.push(error.message || `${url} failed.`);
            failed = true;
            break;
          }
        }
        if (failed) break;
      }
      if (!failed) {
        const unique = new Map();
        tasks.forEach((task, index) => {
          const key = task.taskID || task.taskId || task.id || (task.orderID ? `${task.orderID}-${taskType(task)}` : `${taskType(task)}-${index}`);
          if (!unique.has(String(key))) unique.set(String(key), task);
        });
        return [...unique.values()];
      }
    }
    throw new Error(`Could not load Firebase task records from the backend. ${attempts.join('; ')}`);
  }

  function availableMonths(tasks) {
    return [...new Set(tasks.map(taskMonth).filter(Boolean))].sort((a, b) => b.localeCompare(a));
  }

  function summarize(tasks, selectedMonth) {
    const records = tasks.filter(task => taskMonth(task) === selectedMonth);
    const statusCounts = {};
    const typeCounts = { Collection: 0, Delivery: 0, Inspection: 0, Other: 0 };
    const weeklyTasks = [0, 0, 0, 0, 0];
    let completed = 0;
    let active = 0;

    records.forEach(task => {
      const status = normalizeStatus(task);
      statusCounts[status] = (statusCounts[status] || 0) + 1;
      const type = taskType(task);
      typeCounts[type] += 1;
      if (isCompleted(task)) completed += 1;
      else if (!['cancelled', 'terminated', 'refunded', 'declined', 'rejected'].includes(status.toLowerCase())) active += 1;
      const date = taskDate(task);
      if (date) weeklyTasks[Math.min(4, Math.floor((date.getDate() - 1) / 7))] += 1;
    });

    return {
      month: selectedMonth,
      totalTasks: records.length,
      completed,
      active,
      collection: typeCounts.Collection,
      delivery: typeCounts.Delivery,
      typeCounts,
      statusCounts,
      weeklyTasks,
      completionRate: records.length ? completed / records.length * 100 : 0
    };
  }

  window.OperationsAnalytics = { fetchTasks, availableMonths, taskMonth, summarize };
})();
