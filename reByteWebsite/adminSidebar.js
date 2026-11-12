(function () {
  const navItems = [
    { label: 'Dashboard', href: '/adminModule/adminDashboard.html', icon: '<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/>' },
    { label: 'Listing', href: '/listingModule/listing.html', icon: '<path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z"/><path d="M3 6h18"/><path d="M16 10a4 4 0 0 1-8 0"/>' },
    { label: 'System Config', href: '/sysConfigModule/index.html', icon: '<path d="M19.14 12.94c.04-.31.06-.63.06-.94s-.02-.63-.07-.94l2.03-1.58a.5.5 0 0 0 .12-.63l-1.92-3.32a.5.5 0 0 0-.61-.22l-2.39.96a7.3 7.3 0 0 0-1.62-.94l-.36-2.54a.5.5 0 0 0-.49-.42h-3.84a.5.5 0 0 0-.49.42L9.2 5.33c-.59.22-1.13.53-1.62.94l-2.39-.96a.5.5 0 0 0-.61.22L2.66 8.85a.5.5 0 0 0 .12.63l2.03 1.58a6.2 6.2 0 0 0 0 1.88l-2.03 1.58a.5.5 0 0 0-.12.63l1.92 3.32a.5.5 0 0 0 .61.22l2.39-.96c.49.4 1.03.72 1.62.94l.36 2.54a.5.5 0 0 0 .49.42h3.84a.5.5 0 0 0 .49-.42l.36-2.54c.59-.22 1.13-.53 1.62-.94l2.39.96a.5.5 0 0 0 .61-.22l1.92-3.32a.5.5 0 0 0-.12-.63zM12 15.5a3.5 3.5 0 1 1 0-7 3.5 3.5 0 0 1 0 7z"/>' },
    { label: 'Finance', href: '/transactionManagementModule/index.html', icon: '<path d="M12 2v20M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>' },
    { label: 'Analytics', href: '/adminModule/analyticsHub.html', icon: '<path d="M3 3v18h18"/><path d="m19 9-5 5-4-4-5 5"/>' },
    { label: 'Task Assignment', href: '/taskAssignmentModule/taskAssignment.html', icon: '<rect x="3" y="4" width="18" height="17" rx="2"/><path d="M16 2v4M8 2v4M3 10h18M8 15l2 2 5-5"/>' },
    { label: 'Leave Management', href: '/leaveManagementModule/leaveManagement.html', icon: '<path d="M8 2v4M16 2v4M3 10h18M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z"/><path d="m9 16 2 2 4-4"/>' },
    { label: 'Customer Management', href: '/adminModule/customerManagement.html', icon: '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>' },
    { label: 'Staff Management', href: '/adminModule/staffManagement.html', icon: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M20 8v6M17 11h6"/>' },
    { label: 'Communication', href: '/communicationModule/requestManagement.html', icon: '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>' }
  ];

  const tabsByRole = {
    admin: ['Dashboard', 'Listing', 'System Config', 'Analytics', 'Task Assignment', 'Leave Management', 'Customer Management', 'Staff Management'],
    'customer support': ['Dashboard', 'Customer Management', 'Communication'],
    operator: ['Dashboard', 'Listing', 'Finance', 'Task Assignment']
  };

  function renderSidebar() {
    let user = null;
    try {
      user = typeof ReByteAuth !== 'undefined'
        ? ReByteAuth.getUser() : JSON.parse(localStorage.getItem('rebyte_current_user'));
    } catch {}
    const role = String(user?.role || user?.systemRole || '').trim().toLowerCase();
    const tabs = tabsByRole[role] || [];
    document.querySelectorAll('[data-admin-sidebar]').forEach(sidebar => {
      sidebar.innerHTML = `
        <a class="sidebar-brand" href="/adminModule/adminDashboard.html">
          <img src="/accountManagementModule/assets/images/rebyte_logo.png" alt="ReByte">
          <span>ReByte</span>
        </a>
        <nav class="sidebar-nav-list" aria-label="Admin navigation">
          ${navItems.filter(item => tabs.includes(item.label)).map(item => {
            const active = item.label === sidebar.dataset.adminSidebar;
            return `<a href="${item.href}" class="sidebar-nav-item${active ? ' active' : ''}"${active ? ' aria-current="page"' : ''}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">${item.icon}</svg><span>${item.label}</span></a>`;
          }).join('')}
        </nav>`;
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', renderSidebar);
  else renderSidebar();
})();
