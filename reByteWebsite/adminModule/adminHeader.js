(function(){
  function initAdminHeader(){
    document.querySelectorAll('[data-admin-header]').forEach(function(header){
      const title = header.dataset.pageTitle || 'Admin';
      header.innerHTML = '<div class="admin-header-title"></div><div class="admin-header-right"><span class="admin-header-date"></span><div class="admin-header-profile-wrap"><button type="button" class="admin-header-profile" aria-label="Open account menu" aria-haspopup="true" aria-expanded="false"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path><circle cx="12" cy="7" r="4"></circle></svg></button><div class="admin-header-menu"><button type="button">Log Out</button></div></div></div>';
      header.querySelector('.admin-header-title').textContent = title;
      header.querySelector('.admin-header-date').textContent = new Intl.DateTimeFormat(undefined,{month:'long',day:'numeric',year:'numeric'}).format(new Date());
      const button = header.querySelector('.admin-header-profile');
      const menu = header.querySelector('.admin-header-menu');
      button.addEventListener('click',function(event){event.stopPropagation();const open=menu.classList.toggle('show');button.setAttribute('aria-expanded',String(open));});
      menu.querySelector('button').addEventListener('click',function(){
        if(typeof ReByteAuth!=='undefined') ReByteAuth.logout();
      });
      document.addEventListener('click',function(event){if(!header.contains(event.target)){menu.classList.remove('show');button.setAttribute('aria-expanded','false');}});
    });
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',initAdminHeader);else initAdminHeader();
})();
