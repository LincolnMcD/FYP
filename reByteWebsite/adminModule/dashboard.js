const dashboardNumber = new Intl.NumberFormat('en-MY');
const dashboardAmount = new Intl.NumberFormat('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const dashboardCurrency = new Intl.NumberFormat('en-MY', { style: 'currency', currency: 'MYR' });
const dashboardDate = new Intl.DateTimeFormat('en-MY', {
  timeZone: 'Asia/Kuala_Lumpur',
  dateStyle: 'medium',
  timeStyle: 'short'
});
const administratorMetricIcons = {
  'Total Users': '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
  'Active Staff': '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="m16 11 2 2 4-4"/>',
  'Monthly Sales': '<rect x="2" y="5" width="20" height="14" rx="2"/><circle cx="12" cy="12" r="3"/><path d="M6 12h.01M18 12h.01"/>',
  'Active Rentals': '<rect x="6" y="2" width="12" height="20" rx="2"/><path d="M10 18h4"/>'
};

const metricIcons = {
  'Pending Leave Requests': '☷', 'Unassigned Tasks': '☐',
  'Pending Requests': '≡', 'In Progress': '◷', 'Unread Chats': '✉', 'Resolved Today': '✓',
  'Active Listings': '▤', 'Listings Awaiting Publication': '☷', 'Inspecting Tasks': '⌕', 'Pending Returns': '↶'
};

function dashboardElement(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text != null) element.textContent = text;
  return element;
}

function unreadChatCount(user, chats) {
  const identity = user.uid || user.userId || user.email;
  if (!identity) return null;
  try {
    return chats.filter(chat => {
      const key = `rebyte:help-desk:seen:${encodeURIComponent(identity)}:${encodeURIComponent(chat.id)}`;
      return chat.date > (localStorage.getItem(key) || '');
    }).length;
  } catch {
    return null;
  }
}

const adminDashboardLinks = {
  'Total Customers': 'customerManagement.html',
  'Active Staff': 'staffManagement.html',
  'Pending Leave Requests': '../leaveManagementModule/leaveManagement.html?tab=pending',
  'Unassigned Tasks': '../taskAssignmentModule/taskAssignment.html',
  'Pending Leave Actions': '../leaveManagementModule/leaveManagement.html?tab=pending',
  'Recent Leave Decisions': '../leaveManagementModule/leaveManagement.html'
};

const operatorDashboardLinks = {
  'Inspecting Tasks': '../taskAssignmentModule/taskAssignment.html?tab=inspecting',
  'Active Listings': '../listingModule/listing.html?tab=listed',
  'Listings Awaiting Publication': '../listingModule/listing.html?tab=draft',
  'Pending Returns': '../transactionManagementModule/depositManagement.html?status=pending',
  'Listings to Review': '../listingModule/listing.html?tab=draft',
  'Recent Transactions': '../transactionManagementModule/index.html'
};

function renderDashboardMetric(metric, unreadCount, href) {
  const card = dashboardElement(href ? 'a' : 'article', href ? 'stat-card dashboard-link' : 'stat-card');
  if (href) card.href = href;
  let value = metric.value;
  let note;
  if (metric.format === 'unread') {
    value = unreadCount;
    note = 'Read status on this browser';
  }
  const display = value == null ? '—' : metric.format === 'currency'
    ? dashboardCurrency.format(value) : dashboardNumber.format(value);
  const heading = dashboardElement('div', 'stat-heading');
  const icon = dashboardElement('span', 'stat-icon');
  const artwork = administratorMetricIcons[metric.label === 'Total Customers' ? 'Total Users' : metric.label];
  if (artwork) {
    icon.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${artwork}</svg>`;
  } else {
    icon.textContent = metricIcons[metric.label] || '•';
  }
  icon.setAttribute('aria-hidden', 'true');
  heading.append(icon, dashboardElement('h2', 'stat-header', metric.label));
  card.append(heading, dashboardElement('p', 'stat-val', display));
  if (note) card.append(dashboardElement('p', 'stat-note', note));
  return card;
}

function renderDashboardPanel(panel, index, href) {
  const card = dashboardElement('section', 'card');
  const heading = dashboardElement('h2', 'card-title');
  if (href) {
    const link = dashboardElement('a', 'dashboard-link', panel.title + ' →');
    link.href = href;
    heading.append(link);
  } else {
    heading.textContent = panel.title;
  }
  card.append(heading);
  if (!panel.rows.length) {
    const empty = dashboardElement('div', 'dashboard-empty');
    const icon = dashboardElement('span', 'dashboard-empty-icon', '☷');
    icon.setAttribute('aria-hidden', 'true');
    empty.append(icon, dashboardElement('p', '', 'No records to display'));
    card.append(empty);
    return card;
  }
  if (index === 1) {
    const transactions = panel.title === 'Recent Transactions';
    const decisions = panel.title === 'Recent Leave Decisions';
    const table = dashboardElement('table', 'activity-table');
    const head = table.createTHead().insertRow();
    const columns = decisions ? ['Staff', 'Leave Type', 'Reviewed', 'Decision']
      : transactions ? ['Transaction ID', 'Type / Item', 'Amount (RM)', 'Status']
        : ['Reference', 'Activity', 'Updated', 'Status'];
    for (const label of columns) {
      const cell = dashboardElement('th', '', label);
      cell.scope = 'col';
      head.append(cell);
    }
    const body = table.createTBody();
    for (const row of panel.rows.slice(0, 5)) {
      const item = body.insertRow();
      const title = [row.title, row.detail].filter(Boolean).join(' · ');
      const value = transactions && row.amount != null ? dashboardAmount.format(row.amount)
        : !transactions && row.date ? dashboardDate.format(new Date(row.date)) : '—';
      item.append(dashboardElement('td', 'activity-reference', row.id), dashboardElement('td', '', title),
        dashboardElement('td', '', value));
      const status = dashboardElement('td', '');
      status.append(dashboardStatusBadge(row.status));
      item.append(status);
    }
    const wrapper = dashboardElement('div', 'activity-table-wrap');
    wrapper.append(table);
    card.append(wrapper);
    return card;
  }
  const list = dashboardElement('ul', 'actions-list');
  const pendingLeaves = panel.title === 'Pending Leave Actions';
  const draftListings = panel.title === 'Listings to Review';
  for (const row of panel.rows) {
    const item = dashboardElement('li', 'action-item');
    const icon = dashboardElement('span', 'action-icon', panel.title === 'Pending Support' ? '✉' : '☷');
    icon.setAttribute('aria-hidden', 'true');
    const content = dashboardElement('div', 'action-content');
    const details = pendingLeaves || draftListings ? row.detail : [row.id, row.detail].filter(Boolean).join(' · ');
    content.append(dashboardElement('h3', '', row.title));
    if (details) content.append(dashboardElement('p', '', details));
    const state = dashboardElement('div', 'action-state');
    const value = [row.status, row.amount == null ? null : dashboardCurrency.format(row.amount)].filter(Boolean).join(' · ');
    if (value) state.append(dashboardStatusBadge(value, row.status));
    if (row.date) {
      const time = dashboardElement('time', '', dashboardDate.format(new Date(row.date)));
      time.dateTime = row.date;
      const date = dashboardElement('p', '');
      date.append(time);
      state.append(date);
    }
    item.append(icon, content, state);
    list.append(item);
  }
  card.append(list);
  return card;
}

function dashboardStatusBadge(value, status = value) {
  const badge = dashboardElement('span', 'action-status', value || '—');
  const state = String(status || '').toLowerCase();
  if (/success|complete|resolved|approved|paid|active/.test(state)) badge.classList.add('is-positive');
  else if (/fail|reject|cancel/.test(state)) badge.classList.add('is-negative');
  else if (/pending|hold|progress|assigned/.test(state)) badge.classList.add('is-pending');
  return badge;
}

function renderDashboard(summary, user) {
  const unread = summary.unreadCandidates ? unreadChatCount(user, summary.unreadCandidates) : null;
  const role = String(user.role).trim().toLowerCase();
  const isAdmin = role === 'admin';
  const links = isAdmin ? adminDashboardLinks : role === 'operator' ? operatorDashboardLinks : null;
  document.getElementById('dashboardTitle').textContent = isAdmin ? 'System Overview' : summary.title;
  document.getElementById('dashboardMetrics').replaceChildren(
    ...summary.metrics.map(metric => renderDashboardMetric(metric, unread, links?.[metric.label]))
  );
  document.getElementById('dashboardPanels').replaceChildren(
    ...summary.panels.map((panel, index) => renderDashboardPanel(panel, index, links?.[panel.title]))
  );
}

async function loadDashboard() {
  const user = ReByteAuth.getUser();
  if (!user) {
    window.location.href = '../accountManagementModule/login.html';
    return;
  }
  if (!ReByteAuth.canOpenAdminDashboard(user.role)) {
    window.location.href = user.role === 'Staff'
      ? '../staffModule/staffDashboard.html' : '../accountManagementModule/home.html';
    return;
  }

  const status = document.getElementById('dashboardStatus');
  const cacheKeyFor = account => {
    const identity = account?.uid || account?.userId || account?.email;
    return identity ? `rebyte:dashboard:v1:${encodeURIComponent(identity)}:${encodeURIComponent(account.role)}` : null;
  };
  const cacheKey = cacheKeyFor(user);
  let cached = null;
  try {
    const saved = cacheKey && JSON.parse(sessionStorage.getItem(cacheKey));
    if (saved && Number.isFinite(saved.updatedAt)) {
      renderDashboard(saved.summary, user);
      cached = saved;
    }
  } catch {
    // A blocked storage area or unusable entry does not prevent a fresh load.
  }
  const savedTime = cached ? dashboardDate.format(new Date(cached.updatedAt)) : '';
  status.textContent = cached ? `Updating… · Last updated ${savedTime}` : 'Loading dashboard data…';
  try {
    const response = await ReByteAuth.authFetch(`${API_BASE_URL}/api/dashboard/summary`, {
      preferCachedToken: true
    });
    const summary = await response.json();
    if (cacheKeyFor(ReByteAuth.getUser()) !== cacheKey) {
      window.location.reload();
      return;
    }
    if (!response.ok) {
      if ([401, 403].includes(response.status)) {
        try { if (cacheKey) sessionStorage.removeItem(cacheKey); } catch {}
        document.getElementById('dashboardMetrics').replaceChildren();
        document.getElementById('dashboardPanels').replaceChildren();
        cached = null;
      }
      status.textContent = cached ? `Could not update · Last updated ${savedTime}`
        : summary.error || 'Dashboard data could not be loaded.';
      return;
    }
    renderDashboard(summary, user);
    const updatedAt = Date.now();
    try {
      if (cacheKey) sessionStorage.setItem(cacheKey, JSON.stringify({ summary, updatedAt }));
    } catch {}
    status.textContent = `Live metrics · Last updated ${dashboardDate.format(new Date(updatedAt))}`;
  } catch {
    status.textContent = cached ? `Could not update · Last updated ${savedTime}`
      : 'Dashboard data could not be loaded. Check that the backend is running, then refresh.';
  }
}

document.addEventListener('DOMContentLoaded', loadDashboard);
window.addEventListener('pageshow', event => {
  if (event.persisted) loadDashboard();
});
