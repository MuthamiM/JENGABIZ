(() => {
  'use strict';

  const API = '/email-auth/admin';
  const TOKEN_KEY = 'jengabiz_admin_session';
  const DEFAULT_PAGE_SIZE = 20;
  const pageContent = document.getElementById('page-content');
  const authScreen = document.getElementById('auth-screen');
  const loginForm = document.getElementById('login-form');
  const authError = document.getElementById('auth-error');
  const loginButton = document.getElementById('login-button');
  const sidebar = document.getElementById('sidebar');
  const scrim = document.getElementById('sidebar-scrim');
  const toast = document.getElementById('toast');
  let token = sessionStorage.getItem(TOKEN_KEY) || '';
  let admin = null;
  let currentPage = 'overview';
  const recordState = {
    users: { query: '', status: 'all', offset: 0 },
    inventory: { query: '', offset: 0 },
    referrals: { query: '', offset: 0 },
  };
  let currentRows = [];
  let currentTotal = 0;
  let currentLimit = DEFAULT_PAGE_SIZE;
  let userView = 'list';
  let inventoryView = 'list';
  let referralView = 'list';
  let detailUserId = '';
  let searchTimer = 0;
  let toastTimer = 0;
  let requestNumber = 0;

  const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[char]);
  const number = (value) => new Intl.NumberFormat('en-KE').format(Number(value) || 0);
  const date = (value, epoch = false) => {
    if (value === null || value === undefined || value === '') return '—';
    const parsed = new Date(epoch ? Number(value) : value);
    return Number.isNaN(parsed.getTime()) ? '—' : new Intl.DateTimeFormat('en-KE', {
      day: 'numeric', month: 'short', year: 'numeric',
    }).format(parsed);
  };
  const icon = (path) => `<svg viewBox="0 0 24 24" aria-hidden="true">${path}</svg>`;

  function responsivePageSize(isGrid) {
    const width = window.innerWidth || document.documentElement.clientWidth || 1400;
    const height = window.innerHeight || document.documentElement.clientHeight || 800;
    if (isGrid) {
      const availableWidth = Math.max(340, width - 320);
      const columns = Math.max(1, Math.min(5, Math.floor(availableWidth / 320)));
      return Math.max(8, columns * (height >= 950 ? 3 : 2));
    }
    if (height >= 1100) return 30;
    if (height >= 880) return 25;
    if (height >= 700) return 20;
    return 15;
  }

  async function request(path, options = {}, authToken = token) {
    const headers = { accept: 'application/json', ...(options.headers || {}) };
    if (authToken) headers.authorization = `Bearer ${authToken}`;
    if (options.body) headers['content-type'] = 'application/json';
    const response = await fetch(`${API}${path}`, { ...options, headers, cache: 'no-store' });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = new Error(body.message || `Request failed (${response.status}).`);
      error.status = response.status;
      throw error;
    }
    return body;
  }

  function showToast(message) {
    toast.textContent = message;
    toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => toast.classList.remove('show'), 3200);
  }

  function showAuth(message = '') {
    authScreen.hidden = false;
    if (message) {
      authError.textContent = message;
      authError.hidden = false;
    } else {
      authError.textContent = '';
      authError.hidden = true;
    }
    document.getElementById('email').focus();
  }

  function hideAuth() {
    authScreen.hidden = true;
    authError.textContent = '';
    authError.hidden = true;
  }

  function setAdmin(value) {
    admin = value || admin;
    if (!admin) return;
    document.getElementById('user-name').textContent = admin.name || 'JengaBiz Admin';
    document.getElementById('user-email').textContent = admin.email || '';
    document.getElementById('user-avatar').textContent = (admin.name || 'A').trim().slice(0, 1).toUpperCase();
  }

  function setPageChrome(page) {
    const labels = {
      overview: 'Overview', users: 'User accounts', inventory: 'Inventory',
      referrals: 'Referrals', exports: 'Data exports', admins: 'Admin access',
    };
    document.getElementById('breadcrumb-current').textContent = labels[page] || 'Overview';
    document.querySelectorAll('.nav-item').forEach((button) => {
      const selected = button.dataset.page === page;
      button.classList.toggle('active', selected);
      if (selected) button.setAttribute('aria-current', 'page');
      else button.removeAttribute('aria-current');
    });
    sidebar.classList.remove('open');
    scrim.classList.remove('open');
  }

  function setPage(page) {
    currentPage = page;
    requestNumber += 1;
    setPageChrome(page);
    if (page === 'overview') return void renderOverview();
    if (page === 'users') return void renderUsers();
    if (page === 'inventory') return void renderInventory();
    if (page === 'referrals') return void renderReferrals();
    if (page === 'exports') return renderExports();
    if (page === 'admins') return void renderAdmins();
  }

  function heading(title, subtitle, updated = false) {
    const timestamp = new Intl.DateTimeFormat('en-KE', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date());
    return `<div class="page-heading"><div><h1>${title}</h1><p>${subtitle}</p></div>${updated ? `<span class="date-caption">Updated ${timestamp}</span>` : ''}</div>`;
  }

  function panel(title, subtitle, body, tools = '') {
    return `<section class="panel"><header class="panel-header"><div><h2>${title}</h2>${subtitle ? `<span class="panel-subtitle">${subtitle}</span>` : ''}</div>${tools}</header>${body}</section>`;
  }

  function emptyRow(columns, text) {
    return `<tr><td colspan="${columns}" class="table-empty">${text}</td></tr>`;
  }

  function tableShell(headers, rows, emptyMessage = 'No records found.') {
    return `<div class="table-wrap"><table><thead><tr>${headers.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody>${rows || emptyRow(headers.length, emptyMessage)}</tbody></table></div>`;
  }

  function statusPill(status) {
    const cls = status === 'suspended' ? 'suspended' : status === 'Out of stock' ? 'out' : status === 'Low stock' ? 'low' : '';
    return `<span class="status-pill ${cls}">${escapeHtml(status || 'active')}</span>`;
  }

  function pagination(total, offset, limit) {
    const totalPages = Math.ceil(total / limit);
    if (totalPages <= 1) return '';
    const start = total ? offset + 1 : 0;
    const end = Math.min(total, offset + limit);
    const current = Math.floor(offset / limit) + 1;
    const candidates = new Set([1, totalPages, current - 1, current, current + 1]
      .filter((page) => page >= 1 && page <= totalPages));
    const pages = [...candidates].sort((a, b) => a - b);
    let previous = 0;
    const buttons = pages.map((page) => {
      const ellipsis = page - previous > 1 ? '<span class="pagination-ellipsis" aria-hidden="true">…</span>' : '';
      previous = page;
      return `${ellipsis}<button class="page-number ${page === current ? 'active' : ''}" data-page-offset="${(page - 1) * limit}" ${page === current ? 'aria-current="page"' : ''} type="button">${page}</button>`;
    }).join('');
    return `<div class="pagination-row"><span>Showing ${number(start)}–${number(end)} of ${number(total)}</span><div class="pagination-actions"><button class="small-button" data-page-offset="${Math.max(0, offset - limit)}" ${offset <= 0 ? 'disabled' : ''} type="button">Previous</button>${buttons}<button class="small-button" data-page-offset="${offset + limit}" ${end >= total ? 'disabled' : ''} type="button">Next</button></div></div>`;
  }

  function viewToggle(kind, selected) {
    const listIcon = '<line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><path d="M3 6h.01M3 12h.01M3 18h.01"/>';
    const gridIcon = '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/>';
    return `<div class="view-toggle"><button class="view-button ${selected === 'list' ? 'active' : ''}" data-view="list" data-kind="${kind}" type="button">${icon(listIcon)} List</button><button class="view-button ${selected === 'grid' ? 'active' : ''}" data-view="grid" data-kind="${kind}" type="button">${icon(gridIcon)} Grid</button></div>`;
  }

  function searchToolbar(placeholder, pageKey, statusFilter = false) {
    const searchIcon = '<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>';
    const state = recordState[pageKey];
    return `<div class="table-toolbar"><label class="search-box">${icon(searchIcon)}<input id="record-search" type="search" value="${escapeHtml(state.query)}" placeholder="${placeholder}" autocomplete="off" /></label>${statusFilter ? `<select class="filter-select" id="status-filter" aria-label="Filter customers by status"><option value="all" ${state.status === 'all' ? 'selected' : ''}>All customers</option><option value="active" ${state.status === 'active' ? 'selected' : ''}>Active</option><option value="suspended" ${state.status === 'suspended' ? 'selected' : ''}>Suspended</option></select>` : ''}</div>`;
  }

  function attachSearch(load, pageKey) {
    const state = recordState[pageKey];
    const input = document.getElementById('record-search');
    input?.addEventListener('input', () => {
      clearTimeout(searchTimer);
      state.query = input.value;
      state.offset = 0;
      searchTimer = window.setTimeout(load, 260);
    });
    document.getElementById('status-filter')?.addEventListener('change', (event) => {
      state.status = event.target.value;
      state.offset = 0;
      void load();
    });
  }

  function attachPagination(pageKey, load) {
    const root = document.getElementById('records-pagination');
    root?.querySelectorAll('[data-page-offset]').forEach((button) => button.addEventListener('click', () => {
      recordState[pageKey].offset = Number(button.dataset.pageOffset) || 0;
      void load();
    }));
  }

  async function renderOverview({ showLoading = true } = {}) {
    if (showLoading) {
      pageContent.innerHTML = '<div class="loading-state"><span class="spinner"></span><span>Loading business data…</span></div>';
    }
    try {
      const data = await request('/overview');
      if (currentPage !== 'overview') return;
      const scrollY = window.scrollY;
      renderOverviewFromResult(data);
      window.scrollTo(0, scrollY);
    } catch (error) {
      handleRequestError(error);
    }
  }

  function userRows(rows) {
    return rows.map((user) => `<tr><td><strong>${escapeHtml(user.name)}</strong><small>${escapeHtml(user.shopName)}</small></td><td>${escapeHtml(user.email)}</td><td>${escapeHtml(user.phoneMasked || '—')}</td><td>${escapeHtml([user.county, user.country].filter(Boolean).join(', ') || '—')}</td><td class="number-cell">${number(user.productCount)}</td><td>${number(user.unitsOnHand)} / ${number(user.unitsSold)}</td><td>${statusPill(user.status)}</td><td><button class="small-button" data-open-user="${escapeHtml(user.id)}" type="button">Manage</button></td></tr>`).join('');
  }

  function userCards(rows) {
    const mailIcon = '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m4 7 8 6 8-6"/>';
    const phoneIcon = '<path d="M7 3H4a1 1 0 0 0-1 1c0 9.4 7.6 17 17 17a1 1 0 0 0 1-1v-3l-4-2-2 2a14 14 0 0 1-6-6l2-2-2-4-2-2z"/>';
    const placeIcon = '<path d="M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0z"/><circle cx="12" cy="10" r="2"/>';
    return rows.map((user) => {
      const initials = String(user.name || 'U').trim().split(/\s+/).slice(0, 2).map((part) => part[0]).join('').toUpperCase();
      const location = [user.county, user.country].filter(Boolean).join(', ') || 'Location not set';
      return `<article class="record-card account-card">
        <div class="card-topline"><div class="card-identity"><span class="record-avatar">${escapeHtml(initials)}</span><div class="card-heading"><h3 title="${escapeHtml(user.shopName)}">${escapeHtml(user.shopName)}</h3><p>${escapeHtml(user.name)}</p></div></div>${statusPill(user.status)}</div>
        <div class="card-contact"><div>${icon(mailIcon)}<span title="${escapeHtml(user.email)}">${escapeHtml(user.email)}</span></div><div>${icon(phoneIcon)}<span>${escapeHtml(user.phoneMasked || 'No phone')}</span></div><div>${icon(placeIcon)}<span>${escapeHtml(location)}</span></div></div>
        <div class="card-metrics"><div><strong>${number(user.productCount)}</strong><span>Products</span></div><div><strong>${number(user.unitsOnHand)}</strong><span>On hand</span></div><div><strong>${number(user.unitsSold)}</strong><span>Units sold</span></div></div>
        <footer class="card-footer"><span>Joined ${date(user.createdAt)}</span><button class="card-action" data-open-user="${escapeHtml(user.id)}" type="button">Manage account ${icon('<path d="M5 12h14M13 6l6 6-6 6"/>')}</button></footer>
      </article>`;
    }).join('');
  }

  async function renderUsers() {
    currentPage = 'users';
    setPageChrome('users');
    pageContent.innerHTML = `${heading('Customer accounts', 'Search and manage customer profiles, shop activity, and account status.')}${searchToolbar('Search name, shop, email, county, or phone…', 'users', true)}<div class="page-tools">${viewToggle('users', userView)}<span class="result-count" id="row-count">Loading customers…</span></div><div id="records-view"></div><div id="records-pagination"></div>`;
    attachSearch(loadUserRows, 'users');
    pageContent.querySelectorAll('[data-kind="users"]').forEach((button) => button.addEventListener('click', () => {
      if (userView === button.dataset.view) return;
      userView = button.dataset.view;
      recordState.users.offset = 0;
      pageContent.querySelectorAll('[data-kind="users"]').forEach((candidate) => candidate.classList.toggle('active', candidate.dataset.view === userView));
      void loadUserRows();
    }));
    await loadUserRows();
  }

  async function loadUserRows() {
    const serial = ++requestNumber;
    const state = recordState.users;
    const limit = responsivePageSize(userView === 'grid');
    const params = new URLSearchParams({ q: state.query, status: state.status, limit: String(limit), offset: String(state.offset) });
    try {
      const result = await request(`/users?${params}`);
      if (currentPage !== 'users' || serial !== requestNumber) return;
      currentRows = result.items || [];
      currentTotal = Number(result.total) || 0;
      currentLimit = Number(result.limit) || limit;
      paintUserRows();
    } catch (error) { handleRequestError(error); }
  }

  function paintUserRows() {
    const container = document.getElementById('records-view');
    if (!container) return;
    if (userView === 'grid') {
      container.innerHTML = `<div class="record-grid">${userCards(currentRows) || '<div class="table-empty">No customer accounts found.</div>'}</div>`;
    } else {
      const rows = userRows(currentRows);
      container.innerHTML = panel('All customers', 'Customer profile and shop activity', tableShell(['Customer / shop', 'Email', 'Phone', 'Location', 'Items', 'On hand / sold', 'Status', 'Manage'], rows, 'No customer accounts found.'));
    }
    const count = document.getElementById('row-count');
    if (count) count.textContent = `${number(currentTotal)} customers`;
    const paginationRoot = document.getElementById('records-pagination');
    if (paginationRoot) paginationRoot.innerHTML = pagination(currentTotal, recordState.users.offset, currentLimit);
    container.querySelectorAll('[data-open-user]').forEach((button) => button.addEventListener('click', () => void renderUserDetails(button.dataset.openUser)));
    attachPagination('users', loadUserRows);
  }

  async function renderUserDetails(id) {
    detailUserId = id;
    pageContent.innerHTML = '<div class="loading-state"><span class="spinner"></span><span>Loading customer records…</span></div>';
    try {
      const result = await request(`/users/${encodeURIComponent(id)}`);
      if (currentPage !== 'users' || detailUserId !== id) return;
      const user = result.user;
      const stockRows = (result.stock || []).map((item) => `<tr><td><strong>${escapeHtml(item.name)}</strong><small>${escapeHtml(item.sku || 'No SKU')}</small></td><td>${escapeHtml(item.category)}</td><td>${number(item.stockRemaining)}</td><td>${number(item.unitsSold)}</td><td>${number(item.price)}</td><td>${item.hasImage ? 'Image saved' : '—'}</td></tr>`).join('');
      const referralRows = (result.referrals || []).map((ref) => `<tr><td>${escapeHtml(ref.direction)}</td><td><strong>${escapeHtml(ref.otherShop)}</strong><small>${escapeHtml(ref.otherName)} · ${escapeHtml(ref.otherEmail)}</small></td><td>${number(ref.points)}</td><td>${date(ref.createdAt, true)}</td></tr>`).join('');
      const isSuspended = user.status === 'suspended';
      pageContent.innerHTML = `${heading(user.shopName, `${user.name} · Customer account`)}<div class="detail-toolbar"><button class="small-button" id="back-users" type="button">← All customers</button><span>${statusPill(user.status)}</span><button class="${isSuspended ? 'success-button' : 'danger-button'}" id="change-customer-status" type="button">${isSuspended ? 'Reactivate account' : 'Suspend account'}</button></div>
        <div class="detail-grid"><section class="panel detail-panel"><header class="panel-header"><div><h2>Customer profile</h2><span class="panel-subtitle">Sensitive contact information shown to administrators</span></div></header><dl class="detail-fields"><div><dt>Name</dt><dd>${escapeHtml(user.name)}</dd></div><div><dt>Email</dt><dd>${escapeHtml(user.email)}</dd></div><div><dt>Phone</dt><dd>${escapeHtml(user.phone || 'Not provided')}</dd></div><div><dt>Phone fingerprint</dt><dd class="hash-value">${escapeHtml(user.phoneHash || 'Not provided')}</dd></div><div><dt>Location</dt><dd>${escapeHtml([user.county, user.country].filter(Boolean).join(', ') || 'Not set')}</dd></div><div><dt>Joined</dt><dd>${date(user.createdAt)}</dd></div><div><dt>Referral code</dt><dd>${escapeHtml(user.referralCode || '—')}</dd></div><div><dt>Account ID</dt><dd class="hash-value">${escapeHtml(user.id)}</dd></div></dl></section>
        <section class="panel detail-panel"><header class="panel-header"><div><h2>Account activity</h2><span class="panel-subtitle">No session or push tokens are exposed</span></div></header><div class="activity-grid"><div><strong>${number(result.activity?.sessionCount)}</strong><span>Sessions</span></div><div><strong>${number(result.activity?.deviceCount)}</strong><span>Push devices</span></div><div><strong>${number(result.activity?.imageCount)}</strong><span>Product images</span></div></div></section></div>
        ${panel('Inventory records', `${number((result.stock || []).length)} products`, tableShell(['Product', 'Category', 'On hand', 'Units sold', 'Price', 'Image'], stockRows, 'No products saved.'))}
        ${panel('Referral records', `${number((result.referrals || []).length)} related referrals`, tableShell(['Direction', 'Other account', 'Points', 'Date'], referralRows, 'No referral records.'))}`;
      document.getElementById('back-users').addEventListener('click', () => void renderUsers());
      document.getElementById('change-customer-status').addEventListener('click', () => void changeStatus(user.id, isSuspended ? 'active' : 'suspended'));
    } catch (error) { handleRequestError(error); }
  }

  async function changeStatus(id, status) {
    const action = status === 'suspended' ? 'suspend' : 'reactivate';
    if (!window.confirm(`Confirm ${action} for this customer account?`)) return;
    try {
      await request(`/users/${encodeURIComponent(id)}/status`, { method: 'PATCH', body: JSON.stringify({ status }) });
      showToast(status === 'suspended' ? 'Customer suspended; their app sessions were revoked.' : 'Customer account reactivated.');
      await renderUserDetails(id);
    } catch (error) { showToast(error.message || 'Could not update account status.'); }
  }

  function inventoryRows(rows) {
    return rows.map((item) => `<tr><td><strong>${escapeHtml(item.name)}</strong><small>${escapeHtml(item.sku || 'No SKU')}</small></td><td>${escapeHtml(item.shopName)}<small>${escapeHtml(item.accountEmail)}</small></td><td>${escapeHtml(item.category)}</td><td>${number(item.stockRemaining)}</td><td>${number(item.unitsSold)}</td><td>${number(item.price)}</td><td>${statusPill(item.status)}</td></tr>`).join('');
  }

  function inventoryCards(rows) {
    return rows.map((item) => `<article class="record-card inventory-card">
      <div class="card-topline"><span class="category-chip">${escapeHtml(item.category || 'General')}</span>${statusPill(item.status)}</div>
      <div class="inventory-title-row"><div><h3 title="${escapeHtml(item.name)}">${escapeHtml(item.name)}</h3><p class="item-sku">${item.sku ? `SKU ${escapeHtml(item.sku)}` : 'No SKU recorded'}</p></div><strong class="item-price">KES ${number(item.price)}</strong></div>
      <div class="stock-overview"><div class="stock-on-hand"><span>AVAILABLE</span><strong>${number(item.stockRemaining)}</strong></div><div class="stock-secondary"><div><span>Units sold</span><strong>${number(item.unitsSold)}</strong></div><div><span>Restock at</span><strong>${number(item.reorderLevel)}</strong></div></div></div>
      <footer class="card-footer inventory-footer"><span class="shop-label">${escapeHtml(item.shopName)}</span><span title="${escapeHtml(item.accountEmail)}">${escapeHtml(item.accountEmail)}</span></footer>
    </article>`).join('');
  }

  async function renderInventory() {
    currentPage = 'inventory';
    setPageChrome('inventory');
    pageContent.innerHTML = `${heading('Inventory', 'Review customer products, pricing, quantities, and reorder status.')}${searchToolbar('Search product, category, SKU, shop, or email…', 'inventory')}<div class="page-tools">${viewToggle('inventory', inventoryView)}<span class="result-count" id="row-count">Loading inventory…</span></div><div id="records-view"></div><div id="records-pagination"></div>`;
    attachSearch(loadInventoryRows, 'inventory');
    pageContent.querySelectorAll('[data-kind="inventory"]').forEach((button) => button.addEventListener('click', () => {
      if (inventoryView === button.dataset.view) return;
      inventoryView = button.dataset.view;
      recordState.inventory.offset = 0;
      pageContent.querySelectorAll('[data-kind="inventory"]').forEach((candidate) => candidate.classList.toggle('active', candidate.dataset.view === inventoryView));
      void loadInventoryRows();
    }));
    await loadInventoryRows();
  }

  async function loadInventoryRows() {
    const serial = ++requestNumber;
    const state = recordState.inventory;
    const limit = responsivePageSize(inventoryView === 'grid');
    const params = new URLSearchParams({ q: state.query, limit: String(limit), offset: String(state.offset) });
    try {
      const result = await request(`/inventory?${params}`);
      if (currentPage !== 'inventory' || serial !== requestNumber) return;
      currentRows = result.items || [];
      currentTotal = Number(result.total) || 0;
      currentLimit = Number(result.limit) || limit;
      paintInventoryRows();
    } catch (error) { handleRequestError(error); }
  }

  function paintInventoryRows() {
    const container = document.getElementById('records-view');
    if (!container) return;
    container.innerHTML = inventoryView === 'grid'
      ? `<div class="record-grid">${inventoryCards(currentRows) || '<div class="table-empty">No inventory records found.</div>'}</div>`
      : panel('All inventory records', 'Live product data across customer accounts', tableShell(['Product / SKU', 'Customer shop', 'Category', 'On hand', 'Sold', 'Selling price', 'Status'], inventoryRows(currentRows), 'No inventory records found.'));
    const count = document.getElementById('row-count');
    if (count) count.textContent = `${number(currentTotal)} products`;
    const paginationRoot = document.getElementById('records-pagination');
    if (paginationRoot) paginationRoot.innerHTML = pagination(currentTotal, recordState.inventory.offset, currentLimit);
    attachPagination('inventory', loadInventoryRows);
  }

  function referralRows(rows) {
    return rows.map((row) => `<tr><td><strong>${escapeHtml(row.referrerShop)}</strong><small>${escapeHtml(row.referrerEmail)}</small></td><td><strong>${escapeHtml(row.referredShop)}</strong><small>${escapeHtml(row.referredEmail)}</small></td><td><span class="points-pill">${number(row.points)}</span></td><td>${date(row.createdAt, true)}</td></tr>`).join('');
  }

  function referralCards(rows) {
    return rows.map((row) => `<article class="record-card referral-card">
      <header class="card-topline"><span class="referral-label">COMPLETED REFERRAL</span><span class="points-pill">+${number(row.points)} pts</span></header>
      <div class="referral-party"><span>REFERRED BY</span><strong title="${escapeHtml(row.referrerShop)}">${escapeHtml(row.referrerShop)}</strong><small title="${escapeHtml(row.referrerEmail)}">${escapeHtml(row.referrerEmail)}</small></div>
      <div class="referral-connector"><span></span><b>${icon('<path d="M5 12h14M13 6l6 6-6 6"/>')}</b><span></span></div>
      <div class="referral-party referral-recipient"><span>NEW ACCOUNT</span><strong title="${escapeHtml(row.referredShop)}">${escapeHtml(row.referredShop)}</strong><small title="${escapeHtml(row.referredEmail)}">${escapeHtml(row.referredEmail)}</small></div>
      <footer class="card-footer"><span>Recorded ${date(row.createdAt, true)}</span><span class="referral-earned">${number(row.points)} points awarded</span></footer>
    </article>`).join('');
  }

  async function renderReferrals() {
    currentPage = 'referrals';
    setPageChrome('referrals');
    pageContent.innerHTML = `${heading('Referrals', 'Review referral points and the customer accounts connected to them.')}${searchToolbar('Search shop names or account emails…', 'referrals')}<div class="page-tools">${viewToggle('referrals', referralView)}<span class="result-count" id="row-count">Loading referrals…</span></div><div id="records-view"></div><div id="records-pagination"></div>`;
    attachSearch(loadReferralRows, 'referrals');
    pageContent.querySelectorAll('[data-kind="referrals"]').forEach((button) => button.addEventListener('click', () => {
      if (referralView === button.dataset.view) return;
      referralView = button.dataset.view;
      recordState.referrals.offset = 0;
      pageContent.querySelectorAll('[data-kind="referrals"]').forEach((candidate) => candidate.classList.toggle('active', candidate.dataset.view === referralView));
      void loadReferralRows();
    }));
    await loadReferralRows();
  }

  async function loadReferralRows() {
    const serial = ++requestNumber;
    const state = recordState.referrals;
    const limit = responsivePageSize(referralView === 'grid');
    const params = new URLSearchParams({ q: state.query, limit: String(limit), offset: String(state.offset) });
    try {
      const result = await request(`/referrals?${params}`);
      if (currentPage !== 'referrals' || serial !== requestNumber) return;
      currentRows = result.referrals || [];
      currentTotal = Number(result.total) || 0;
      currentLimit = Number(result.limit) || limit;
      paintReferralRows();
    } catch (error) { handleRequestError(error); }
  }

  function paintReferralRows() {
    const container = document.getElementById('records-view');
    if (!container) return;
    container.innerHTML = referralView === 'grid'
      ? `<div class="record-grid">${referralCards(currentRows) || '<div class="table-empty">No referral records found.</div>'}</div>`
      : panel('Referral records', 'All completed referrals', tableShell(['Referring customer', 'New customer', 'Points', 'Date'], referralRows(currentRows), 'No referral records found.'));
    const count = document.getElementById('row-count');
    if (count) count.textContent = `${number(currentTotal)} referrals`;
    const paginationRoot = document.getElementById('records-pagination');
    if (paginationRoot) paginationRoot.innerHTML = pagination(currentTotal, recordState.referrals.offset, currentLimit);
    attachPagination('referrals', loadReferralRows);
  }

  function renderExports() {
    pageContent.innerHTML = `${heading('Data exports', 'Download customer and business records for reporting or backup.')}
      <div class="export-grid">
        <article class="export-card"><span class="export-icon">${icon('<path d="M12 3v12M7 10l5 5 5-5M4 17v4h16v-4"/>')}</span><h2>Customer accounts</h2><p>Profiles, protected phone details, status, and account activity totals.</p><button class="primary-button" data-export="users" type="button">Export customers</button></article>
        <article class="export-card"><span class="export-icon">${icon('<path d="M3 7l9-4 9 4-9 4-9-4zM3 7v10l9 4 9-4V7M12 11v10"/>')}</span><h2>Inventory</h2><p>Product categories, quantities, selling and buying prices, SKU, and image flags.</p><button class="primary-button" data-export="inventory" type="button">Export inventory</button></article>
        <article class="export-card"><span class="export-icon">${icon('<path d="M7 17 17 7M8 7h9v9M5 12v7h7"/>')}</span><h2>Referral records</h2><p>Inviter, new account, points, and referral dates.</p><button class="primary-button" data-export="referrals" type="button">Export referrals</button></article>
        <article class="export-card export-card-featured"><span class="export-icon">${icon('<path d="M4 4h16v16H4zM8 8h8M8 12h8M8 16h5"/>')}</span><h2>Full data bundle</h2><p>All customer, inventory, and referral records in one JSON file.</p><button class="primary-button" data-export="all" data-format="json" type="button">Download full JSON</button></article>
      </div>
      <div class="export-note"><strong>Credential safety</strong><span>Passwords, password hashes, admin sessions, customer sessions, and push notification tokens are never included. Customer phone numbers are encrypted in the database and are revealed only through this authenticated admin interface.</span></div>`;
    pageContent.querySelectorAll('[data-export]').forEach((button) => button.addEventListener('click', () => void exportData(button.dataset.export, button.dataset.format || 'csv')));
  }

  async function exportData(dataset, format) {
    try {
      const response = await fetch(`${API}/export?dataset=${encodeURIComponent(dataset)}&format=${encodeURIComponent(format)}`, {
        headers: { authorization: `Bearer ${token}`, accept: format === 'csv' ? 'text/csv' : 'application/json' },
        cache: 'no-store',
      });
      if (!response.ok) {
        const payload = await response.json().catch(() => ({}));
        throw Object.assign(new Error(payload.message || `Export failed (${response.status}).`), { status: response.status });
      }
      const blob = await response.blob();
      const filename = response.headers.get('Content-Disposition')?.match(/filename="?([^";]+)"?/i)?.[1] || `jengabiz-${dataset}.${format}`;
      const objectUrl = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = objectUrl;
      link.download = filename;
      link.click();
      URL.revokeObjectURL(objectUrl);
      showToast(`${dataset === 'all' ? 'Full data bundle' : dataset} export downloaded.`);
    } catch (error) { handleRequestError(error); }
  }

  async function renderAdmins({ showLoading = true } = {}) {
    if (showLoading) {
      pageContent.innerHTML = '<div class="loading-state"><span class="spinner"></span><span>Loading administrator access…</span></div>';
    }
    try {
      const result = await request('/admins');
      const rows = (result.admins || []).map((entry) => `<tr><td><strong>${escapeHtml(entry.name)}</strong></td><td>${escapeHtml(entry.email)}</td><td>${escapeHtml(entry.role)}</td><td>${statusPill(entry.status)}</td><td>${date(entry.createdAt)}</td><td>${date(entry.lastLoginAt)}</td></tr>`).join('');
      pageContent.innerHTML = `${heading('Admin access', 'Administrator identities are separate from customer accounts.')}${panel('Administrator accounts', 'Only administrator records can sign in here.', tableShell(['Administrator', 'Email', 'Role', 'Status', 'Created', 'Last sign-in'], rows, 'No administrator account is configured.'))}<div class="export-note"><strong>Role separation</strong><span>Customer credentials cannot open admin routes. Administrator passwords are stored as scrypt hashes and admin sessions are stored as token hashes.</span></div>`;
    } catch (error) { handleRequestError(error); }
  }

  function handleRequestError(error) {
    if (error.status === 401 || error.status === 403) {
      token = '';
      sessionStorage.removeItem(TOKEN_KEY);
      showAuth(error.status === 403 ? 'This administrator does not have access to this view.' : 'Administrator sign-in is required.');
      return;
    }
    pageContent.innerHTML = `<div class="error-banner"><div><strong>Could not load JengaBiz data</strong>${escapeHtml(error.message || 'Check your connection and try again.')}</div></div>`;
  }

  loginForm.addEventListener('submit', async (event) => {
    event.preventDefault();
    authError.hidden = true;
    loginButton.disabled = true;
    loginButton.textContent = 'Signing in…';
    const form = new FormData(loginForm);
    try {
      const result = await request('/login', {
        method: 'POST',
        body: JSON.stringify({ email: form.get('email'), password: form.get('password') }),
      }, '');
      token = result.sessionToken;
      setAdmin(result.admin);
      const overview = await request('/overview');
      sessionStorage.setItem(TOKEN_KEY, token);
      hideAuth();
      currentPage = 'overview';
      setPageChrome('overview');
      await paintOverviewFromData(overview);
    } catch (error) {
      const rejectedToken = token;
      token = '';
      sessionStorage.removeItem(TOKEN_KEY);
      if (rejectedToken) void request('/logout', { method: 'POST', body: '{}' }, rejectedToken).catch(() => {});
      authError.textContent = error.status === 401 ? 'Administrator email or password is incorrect.' : error.message || 'Could not connect. Try again.';
      authError.hidden = false;
    } finally {
      loginButton.disabled = false;
      loginButton.innerHTML = 'Sign in securely <span aria-hidden="true">→</span>';
    }
  });

  function paintOverviewFromData(data) {
    currentPage = 'overview';
    setPageChrome('overview');
    renderOverviewFromResult(data);
  }

  function renderOverviewFromResult(data) {
    const t = data.totals;
    const shopIcon = '<path d="M3 10h18l-1 11H4L3 10zM2 10l2-7h16l2 7M9 21v-7h6v7"/>';
    const itemIcon = '<path d="M3 7l9-4 9 4-9 4-9-4zM3 7v10l9 4 9-4V7M12 11v10"/>';
    const qtyIcon = '<path d="M4 19V9M10 19V5M16 19v-7M22 19H2"/>';
    const referralIcon = '<path d="M7 17 17 7M8 7h9v9M5 12v7h7"/>';
    const activeIcon = '<path d="M20 6 9 17l-5-5"/>';
    const kpi = (label, value, sub, path) => `<article class="kpi-card"><div class="kpi-top"><span class="kpi-label">${label}</span><span class="kpi-icon">${icon(path)}</span></div><strong class="kpi-value">${number(value)}</strong><span class="kpi-foot">${sub}</span></article>`;
    const signupRows = data.signups || [];
    const max = Math.max(...signupRows.map((row) => Number(row.count)), 1);
    const signupChart = signupRows.map((row) => {
      const level = Math.max(0, Math.min(100, Math.ceil((Number(row.count) / max) * 10) * 10));
      return `<div class="bar-column"><span class="bar-count">${number(row.count)}</span><div class="bar-track"><div class="bar h${level}"></div></div><span class="bar-label">${escapeHtml(row.label)}</span></div>`;
    }).join('');
    const recentRows = (data.recentShops || []).map((user) => `<tr><td><strong>${escapeHtml(user.name)}</strong><small>${escapeHtml(user.shopName)}</small></td><td>${escapeHtml(user.email)}</td><td>${statusPill(user.status || 'active')}</td><td>${number(user.productCount)}</td><td>${date(user.createdAt)}</td></tr>`).join('');
    const lowRows = (data.lowStockItems || []).slice(0, 5).map((item) => `<div class="attention-row"><div><strong>${escapeHtml(item.name)}</strong><small>${escapeHtml(item.shopName)} · ${escapeHtml(item.category)}</small></div><span class="attention-quantity ${Number(item.stockRemaining) === 0 ? 'empty' : ''}">${number(item.stockRemaining)} left</span></div>`).join('');
    pageContent.innerHTML = `${heading('Platform overview', 'Manage customer accounts and review the records saved across JengaBiz.', true)}
      <div class="kpi-grid">${kpi('Customer accounts', t.shops, 'All registered shops', shopIcon)}${kpi('Active accounts', t.activeUsers, `${number(t.suspendedUsers)} suspended`, activeIcon)}${kpi('Products tracked', t.products, 'Across all customers', itemIcon)}${kpi('Units on hand', t.unitsOnHand, `${number(t.unitsSold)} recorded sold`, qtyIcon)}${kpi('Referral points', t.referralPoints, `${number(t.referrals)} completed referrals`, referralIcon)}</div>
      <div class="dashboard-grid"><section class="panel"><header class="panel-header"><div><h2>Customer signups</h2><span class="panel-subtitle">Last six months</span></div><span class="chart-legend"><i></i> New accounts</span></header><div class="chart-wrap"><div class="bar-chart">${signupChart}</div></div></section>
      ${panel('Inventory attention', 'Low and out-of-stock products', `<div class="stock-summary">${lowRows || '<div class="attention-empty">No low stock records.</div>'}</div>`, '<button class="text-link" data-go="inventory" type="button">View inventory</button>')}</div>
      ${panel('Recently joined customers', 'Latest JengaBiz accounts', tableShell(['Customer / shop', 'Email', 'Status', 'Products', 'Joined'], recentRows, 'No customers registered yet.'), '<button class="text-link" data-go="users" type="button">Manage users</button>')}`;
    pageContent.querySelectorAll('[data-go]').forEach((button) => button.addEventListener('click', () => setPage(button.dataset.go)));
  }

  document.querySelectorAll('.nav-item').forEach((button) => button.addEventListener('click', () => setPage(button.dataset.page)));
  async function refreshCurrentPage() {
    const button = document.getElementById('refresh-button');
    if (button.disabled) return;
    button.disabled = true;
    button.classList.add('refreshing');
    button.setAttribute('aria-busy', 'true');
    try {
      if (currentPage === 'overview') await renderOverview({ showLoading: false });
      else if (currentPage === 'users') await loadUserRows();
      else if (currentPage === 'inventory') await loadInventoryRows();
      else if (currentPage === 'referrals') await loadReferralRows();
      else if (currentPage === 'admins') await renderAdmins({ showLoading: false });
      else showToast('Your export options are up to date.');
    } finally {
      button.disabled = false;
      button.classList.remove('refreshing');
      button.removeAttribute('aria-busy');
    }
  }
  document.getElementById('refresh-button').addEventListener('click', () => void refreshCurrentPage());
  document.getElementById('menu-button').addEventListener('click', () => {
    sidebar.classList.toggle('open');
    scrim.classList.toggle('open');
  });
  scrim.addEventListener('click', () => {
    sidebar.classList.remove('open');
    scrim.classList.remove('open');
  });
  document.getElementById('logout-button').addEventListener('click', () => {
    const oldToken = token;
    token = '';
    sessionStorage.removeItem(TOKEN_KEY);
    showAuth();
    showToast('You have signed out.');
    void request('/logout', { method: 'POST', body: '{}' }, oldToken).catch(() => {});
  });

  async function start() {
    if (!token) return showAuth();
    try {
      const result = await request('/me');
      setAdmin(result.admin);
      hideAuth();
      await renderOverview();
    } catch (error) { handleRequestError(error); }
  }

  void start();
})();
