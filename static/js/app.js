/**
 * SCOPE — Zen Task Planner
 * Full SPA experience: AJAX navigation, live sidebar, toast, custom controls
 */

// ====================================
// UTILITIES
// ====================================

function getCSRFToken() {
    return document.querySelector('[name=csrfmiddlewaretoken]')?.value ||
           document.cookie.split('; ').find(r => r.startsWith('csrftoken='))?.split('=')[1];
}

function escapeHtml(text) {
    if (!text) return '';
    const d = document.createElement('div');
    d.textContent = text;
    return d.innerHTML;
}

function isTyping() {
    const a = document.activeElement;
    return a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA' || a.isContentEditable);
}

function pluralize(n, one, few, many) {
    const m10 = n % 10, m100 = n % 100;
    if (m100 >= 11 && m100 <= 19) return many;
    if (m10 === 1) return one;
    if (m10 >= 2 && m10 <= 4) return few;
    return many;
}

async function apiFetch(url, opts = {}) {
    const defaults = {
        headers: {
            'X-CSRFToken': getCSRFToken(),
            'X-Requested-With': 'XMLHttpRequest',
        },
    };
    if (opts.body && typeof opts.body === 'string') {
        defaults.headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    const merged = { ...defaults, ...opts, headers: { ...defaults.headers, ...opts.headers } };
    let res;
    try {
        res = await fetch(url, merged);
    } catch {
        throw new Error('Нет сети или запрос заблокирован');
    }
    const text = await res.text();
    if (!text) return {};
    try {
        return JSON.parse(text);
    } catch {
        const hint = text.replace(/\s+/g, ' ').slice(0, 120);
        throw new Error(hint || `Ответ не JSON (${res.status})`);
    }
}

// ====================================
// TOAST NOTIFICATIONS
// ====================================

let toastContainer = null;

function ensureToastContainer() {
    if (!toastContainer || !toastContainer.parentNode) {
        toastContainer = document.createElement('div');
        toastContainer.className = 'toast-container';
        document.body.appendChild(toastContainer);
    }
    return toastContainer;
}

function showToast(message, type = 'success', duration = 3000) {
    const container = ensureToastContainer();
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    const icons = { success: 'ri-check-line', error: 'ri-error-warning-line', info: 'ri-information-line', warning: 'ri-alarm-warning-line' };
    toast.innerHTML = `<i class="${icons[type] || icons.info}"></i><span>${message}</span><button class="toast-close" onclick="this.closest('.toast').remove()"><i class="ri-close-line"></i></button>`;
    container.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));
    setTimeout(() => {
        toast.classList.remove('show');
        toast.classList.add('hiding');
        setTimeout(() => toast.remove(), 300);
    }, duration);
}

// ====================================
// SPA NAVIGATION
// ====================================

let _spaNavigating = false;

function isSPALink(href) {
    if (!href) return false;
    try {
        const url = new URL(href, location.origin);
        if (url.origin !== location.origin) return false;
        const p = url.pathname;
        if (['/', '/today/', '/calendar/', '/budget/', '/projects/', '/tags/'].includes(p)) return true;
        if (/^\/projects\/\d+\/$/.test(p)) return true;
        if (/^\/projects\/\d+\/edit\/$/.test(p)) return true;
        if (/^\/tasks\/\d+\/$/.test(p)) return true;
        if (/^\/tasks\/\d+\/edit\/$/.test(p)) return true;
        return false;
    } catch { return false; }
}

async function spaNavigate(url, pushState = true) {
    if (_spaNavigating) return;
    _spaNavigating = true;

    const content = document.querySelector('.content-body');
    const titleEl = document.querySelector('.page-title');
    if (!content) { _spaNavigating = false; location.href = url; return; }

    content.style.transition = 'opacity 0.15s ease, transform 0.15s ease';
    content.style.opacity = '0';
    content.style.transform = 'translateY(8px)';

    try {
        const response = await fetch(url, { headers: { 'X-Requested-With': 'XMLHttpRequest' } });

        if (response.redirected) {
            _spaNavigating = false;
            location.href = response.url;
            return;
        }
        if (!response.ok) {
            _spaNavigating = false;
            location.href = url;
            return;
        }

        const html = await response.text();
        const doc = new DOMParser().parseFromString(html, 'text/html');

        const newContent = doc.querySelector('.content-body');
        const newTitle = doc.querySelector('.page-title');
        const newDocTitle = doc.querySelector('title');

        await new Promise(r => setTimeout(r, 150));

        if (newContent) {
            content.innerHTML = newContent.innerHTML;
        }
        if (newTitle && titleEl) titleEl.textContent = newTitle.textContent;
        if (newDocTitle) document.title = newDocTitle.textContent;

        content.style.opacity = '1';
        content.style.transform = 'translateY(0)';

        if (pushState) history.pushState({ spa: true }, '', url);

        updateActiveNav(url);
        execContentScripts();
        reinitPage();
        refreshBudgetSidebar();

        // Close mobile sidebar on navigation
        const sidebar = document.querySelector('.sidebar');
        if (sidebar) sidebar.classList.remove('open');

    } catch (err) {
        content.style.opacity = '1';
        content.style.transform = 'translateY(0)';
        location.href = url;
    } finally {
        _spaNavigating = false;
    }
}

function execContentScripts() {
    document.querySelectorAll('.content-body script').forEach(old => {
        const s = document.createElement('script');
        s.textContent = old.textContent;
        old.parentNode.replaceChild(s, old);
    });
}

function reinitPage() {
    // Quick add
    const input = document.getElementById('quickAddInput');
    if (input && !input._spa) {
        input._spa = true;
        input.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') { e.preventDefault(); quickAddTask(); }
        });
    }
    // Stats widget
    const widget = document.getElementById('statsWidget');
    if (widget) loadStatsWidget();
    initBudgetPage();
}

function updateActiveNav(url) {
    const path = new URL(url, location.origin).pathname + new URL(url, location.origin).search;
    document.querySelectorAll('.sidebar-nav .nav-item').forEach(a => {
        const href = a.getAttribute('href');
        if (!href) return;
        a.classList.toggle('active', href === path || (path.startsWith(href) && href !== '/' && href.length > 1));
    });
    // Exact match for "/" (dashboard)
    const dashLink = document.querySelector('.sidebar-nav .nav-item[href="/"]');
    if (dashLink) {
        dashLink.classList.toggle('active', path === '/' || path.startsWith('/?'));
    }
    document.querySelectorAll('.nav-section-link').forEach(a => {
        const href = a.getAttribute('href');
        if (href) a.classList.toggle('active', path.startsWith(href));
    });
}

// Intercept link clicks
document.addEventListener('click', (e) => {
    // Close custom selects on click outside
    if (!e.target.closest('.custom-select-wrap')) {
        document.querySelectorAll('.custom-select-dropdown.open').forEach(d => d.classList.remove('open'));
    }

    // SPA link interception
    const link = e.target.closest('a[href]');
    if (!link) return;
    const href = link.getAttribute('href');
    if (!href || href.startsWith('#') || href.startsWith('javascript:')) return;
    if (link.target === '_blank' || link.hasAttribute('download')) return;
    if (e.ctrlKey || e.metaKey || e.shiftKey) return;

    const fullUrl = new URL(href, location.origin).href;
    if (isSPALink(fullUrl)) {
        e.preventDefault();
        spaNavigate(fullUrl);
    }
});

window.addEventListener('popstate', () => {
    spaNavigate(location.href, false);
});

// ====================================
// CUSTOM PROJECT SELECTOR
// ====================================

function toggleProjectDropdown() {
    const dd = document.getElementById('taskProjectDropdown');
    if (dd) dd.classList.toggle('open');
}

function pickProject(option) {
    const wrap = option.closest('.custom-select-wrap');
    const input = wrap.querySelector('input[type="hidden"]');
    const trigger = wrap.querySelector('.custom-select-trigger');
    const valueSpan = trigger.querySelector('.custom-select-value');
    const dd = wrap.querySelector('.custom-select-dropdown');

    input.value = option.dataset.value || '';

    const color = option.dataset.color;
    const textEl = option.querySelector('span:last-child');
    const text = textEl ? textEl.textContent : 'Без проекта';

    if (color) {
        valueSpan.innerHTML = `<span class="project-dot" style="background:${color}"></span>${escapeHtml(text)}`;
    } else {
        valueSpan.textContent = text;
    }

    dd.querySelectorAll('.custom-select-option').forEach(o => o.classList.remove('selected'));
    option.classList.add('selected');
    dd.classList.remove('open');
}

function refreshModalProjectSelect(projects) {
    const dd = document.getElementById('taskProjectDropdown');
    if (!dd) return;
    const wrap = dd.closest('.custom-select-wrap');
    const input = wrap.querySelector('input[type="hidden"]');
    const curVal = input ? input.value : '';

    let html = `<div class="custom-select-option ${!curVal ? 'selected' : ''}" data-value="" data-color="" onclick="pickProject(this)"><span>Без проекта</span></div>`;
    projects.forEach(p => {
        html += `<div class="custom-select-option ${String(p.id) === String(curVal) ? 'selected' : ''}" data-value="${p.id}" data-color="${p.color}" onclick="pickProject(this)">
            <span class="project-dot" style="background:${p.color}"></span>
            <span>${escapeHtml(p.name)}</span>
        </div>`;
    });
    dd.innerHTML = html;
}

// ====================================
// MODAL FUNCTIONS
// ====================================

function openTaskModal(defaults = {}) {
    const modal = document.getElementById('taskModal');
    if (!modal) return;
    modal.classList.add('active');
    const form = document.getElementById('taskForm');

    if (defaults.project) {
        const input = document.getElementById('taskProjectInput');
        if (input) input.value = defaults.project;
        const opt = document.querySelector(`#taskProjectDropdown .custom-select-option[data-value="${defaults.project}"]`);
        if (opt) pickProject(opt);
    }
    if (defaults.due_date) {
        const i = form.querySelector('input[name="due_date"]');
        if (i) i.value = defaults.due_date;
    }

    setTimeout(() => form.querySelector('input[name="title"]')?.focus(), 100);
}

function closeTaskModal() {
    const m = document.getElementById('taskModal');
    if (m) m.classList.remove('active');
    const f = document.getElementById('taskForm');
    if (f) f.reset();

    // Reset priority
    document.querySelectorAll('#taskModal .priority-btn').forEach(b => b.classList.remove('active'));
    const def = document.querySelector('#taskModal .priority-btn[data-val="2"]');
    if (def) def.classList.add('active');
    const pi = document.getElementById('taskPriorityInput');
    if (pi) pi.value = '2';

    // Reset project dropdown
    const projInput = document.getElementById('taskProjectInput');
    if (projInput) projInput.value = '';
    const trigger = document.getElementById('taskProjectTrigger');
    if (trigger) {
        const vs = trigger.querySelector('.custom-select-value');
        if (vs) vs.textContent = 'Без проекта';
    }
    const dd = document.getElementById('taskProjectDropdown');
    if (dd) {
        dd.classList.remove('open');
        dd.querySelectorAll('.custom-select-option').forEach(o => o.classList.remove('selected'));
        const first = dd.querySelector('.custom-select-option');
        if (first) first.classList.add('selected');
    }
}

function openProjectModal() {
    const m = document.getElementById('projectModal');
    if (m) m.classList.add('active');
    setTimeout(() => document.querySelector('#projectModal input[name="name"]')?.focus(), 100);
}

function closeProjectModal() {
    const m = document.getElementById('projectModal');
    if (m) m.classList.remove('active');
    const f = document.getElementById('projectForm');
    if (f) f.reset();
    const hex = document.getElementById('projectColorHex');
    if (hex) hex.value = '#7C3AED';
}

function openTagModal() {
    const m = document.getElementById('tagModal');
    if (m) m.classList.add('active');
    setTimeout(() => document.querySelector('#tagModal input[name="name"]')?.focus(), 100);
}

function closeTagModal() {
    const m = document.getElementById('tagModal');
    if (m) m.classList.remove('active');
    const f = document.getElementById('tagForm');
    if (f) f.reset();
    const hex = document.getElementById('tagColorHex');
    if (hex) hex.value = '#7C3AED';
}

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { closeTaskModal(); closeProjectModal(); closeTagModal(); }
});

// AJAX form handlers
function initFormHandlers() {
    const taskForm = document.getElementById('taskForm');
    if (taskForm && !taskForm._init) {
        taskForm._init = true;
        taskForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const fd = new FormData(taskForm);
            const body = new URLSearchParams(fd).toString();
            try {
                const data = await apiFetch(taskForm.action, { method: 'POST', body });
                if (data.success) {
                    closeTaskModal();
                    showToast('Задача создана');
                    if (refreshKanbanIfOnCalendar()) {
                        /* только API-перезагрузка календаря */
                    } else if (data.html) insertTaskIntoDOM(data.html, data.id);
                    else softReloadContent();
                    refreshSidebar();
                }
            } catch (err) { showToast('Ошибка при создании задачи', 'error'); }
        });
    }

    const projectForm = document.getElementById('projectForm');
    if (projectForm && !projectForm._init) {
        projectForm._init = true;
        projectForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const fd = new FormData(projectForm);
            const body = new URLSearchParams(fd).toString();
            try {
                const data = await apiFetch(projectForm.action, { method: 'POST', body });
                if (data.success) {
                    closeProjectModal();
                    showToast('Проект создан');
                    refreshSidebar();
                    if (location.pathname === '/projects/') softReloadContent();
                }
            } catch (err) { showToast('Ошибка при создании проекта', 'error'); }
        });
    }

    const tagForm = document.getElementById('tagForm');
    if (tagForm && !tagForm._init) {
        tagForm._init = true;
        tagForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const fd = new FormData(tagForm);
            const body = new URLSearchParams(fd).toString();
            try {
                const data = await apiFetch(tagForm.action, { method: 'POST', body });
                if (data.success) {
                    closeTagModal();
                    showToast('Тег создан');
                    refreshSidebar();
                    if (location.pathname === '/tags/') softReloadContent();
                }
            } catch (err) { showToast('Ошибка при создании тега', 'error'); }
        });
    }
}

document.addEventListener('DOMContentLoaded', initFormHandlers);

// ====================================
// SIDEBAR LIVE UPDATE
// ====================================

async function refreshSidebar() {
    try {
        const data = await apiFetch('/api/sidebar/');
        if (!Array.isArray(data.projects) || !Array.isArray(data.tags)) return;
        renderSidebarProjects(data.projects);
        renderSidebarTags(data.tags);
        renderSidebarCounts(data);
        refreshModalProjectSelect(data.projects);
        try {
            const stats = await apiFetch('/api/stats/');
            if (window.updateStatsWidget && typeof stats.streak === 'number') window.updateStatsWidget(stats);
        } catch {}
    } catch {}
}

function renderSidebarProjects(projects) {
    const sections = document.querySelectorAll('.sidebar-nav .nav-section');
    if (sections.length < 2) return;
    const sec = sections[1];
    const header = sec.querySelector('.nav-section-header');
    sec.querySelectorAll(':scope > .nav-item').forEach(el => el.remove());
    sec.querySelectorAll(':scope > .nav-empty-link').forEach(el => el.remove());

    if (projects.length === 0) {
        const p = document.createElement('a');
        p.href = '/projects/';
        p.className = 'nav-empty-link';
        p.textContent = 'Создать проект';
        sec.appendChild(p);
        return;
    }

    const curPath = location.pathname;
    const fragment = document.createDocumentFragment();
    projects.forEach(proj => {
        const a = document.createElement('a');
        a.href = `/projects/${proj.id}/`;
        a.className = 'nav-item';
        if (curPath === `/projects/${proj.id}/`) a.classList.add('active');
        a.innerHTML = `<span class="project-dot" style="background-color:${proj.color}"></span><span class="nav-label">${escapeHtml(proj.name)}</span>${proj.task_count ? `<span class="badge">${proj.task_count}</span>` : ''}`;
        fragment.appendChild(a);
    });
    if (header && header.nextSibling) {
        header.after(fragment);
    } else {
        sec.appendChild(fragment);
    }
}

function renderSidebarTags(tags) {
    const sections = document.querySelectorAll('.sidebar-nav .nav-section');
    if (sections.length < 3) return;
    const sec = sections[2];
    sec.querySelectorAll(':scope > .nav-item.nav-tag').forEach(el => el.remove());
    sec.querySelectorAll(':scope > .nav-empty').forEach(el => el.remove());

    if (tags.length === 0) {
        const p = document.createElement('p');
        p.className = 'nav-empty';
        p.textContent = 'Нет тегов';
        sec.appendChild(p);
        return;
    }

    tags.forEach(tag => {
        const a = document.createElement('a');
        a.href = `/?tag=${tag.id}`;
        a.className = 'nav-item nav-tag';
        a.innerHTML = `<span class="tag-dot" style="background-color:${tag.color}"></span><span class="nav-label">${escapeHtml(tag.name)}</span>`;
        sec.appendChild(a);
    });
}

function renderSidebarCounts(data) {
    const navItems = document.querySelectorAll('.sidebar-nav .nav-section:first-child .nav-item');
    if (navItems[0]) {
        let b = navItems[0].querySelector('.badge');
        if (data.all_count) {
            if (!b) { b = document.createElement('span'); b.className = 'badge'; navItems[0].appendChild(b); }
            b.textContent = data.all_count;
        } else if (b) b.remove();
    }
    if (navItems[1]) {
        let b = navItems[1].querySelector('.badge');
        if (data.today_count) {
            if (!b) { b = document.createElement('span'); b.className = 'badge'; navItems[1].appendChild(b); }
            b.textContent = data.today_count;
        } else if (b) b.remove();
    }
}

async function updateSidebarCounts() { return refreshSidebar(); }

// ====================================
// COLOR PICKER
// ====================================

function syncColorHex(colorInput, hexInputId) {
    const hex = document.getElementById(hexInputId);
    if (hex) hex.value = colorInput.value.toUpperCase();
}

function syncHexColor(hexInput, colorInputId) {
    const ci = document.getElementById(colorInputId);
    let v = hexInput.value;
    if (v && !v.startsWith('#')) { v = '#' + v; hexInput.value = v; }
    if (/^#[0-9A-Fa-f]{6}$/.test(v)) ci.value = v;
}

function setColor(color, colorInputId, hexInputId) {
    const ci = document.getElementById(colorInputId);
    const hi = document.getElementById(hexInputId);
    if (ci) ci.value = color;
    if (hi) hi.value = color.toUpperCase();
}

// ====================================
// TASK FUNCTIONS
// ====================================

async function toggleTask(taskId) {
    try {
        const data = await apiFetch(`/tasks/${taskId}/toggle/`, { method: 'POST' });
        if (data.success) {
            const item = document.querySelector(`.task-item[data-id="${taskId}"]`);
            if (item) {
                if (data.is_completed) {
                    item.classList.add('completed');
                    item.style.transition = 'all 0.4s ease';
                    item.style.opacity = '0';
                    item.style.transform = 'translateX(-30px) scale(0.95)';
                    setTimeout(() => {
                        item.style.maxHeight = item.offsetHeight + 'px';
                        requestAnimationFrame(() => { item.style.maxHeight = '0'; item.style.padding = '0 16px'; item.style.margin = '0'; item.style.overflow = 'hidden'; });
                        setTimeout(() => item.remove(), 300);
                    }, 300);
                    showToast('Задача завершена!', 'success');
                } else {
                    item.classList.remove('completed');
                    showToast('Задача возвращена', 'info');
                }
                refreshSidebar();
            }
            if (location.pathname === '/calendar/') refreshKanbanIfOnCalendar();
        }
    } catch { showToast('Ошибка', 'error'); }
}

async function deleteTask(taskId) {
    if (!confirm('Удалить задачу?')) return;
    try {
        const data = await apiFetch(`/tasks/${taskId}/delete/`, { method: 'POST' });
        if (data.success) {
            const item = document.querySelector(`.task-item[data-id="${taskId}"]`);
            if (item) { item.style.transition = 'all 0.3s ease'; item.style.opacity = '0'; item.style.transform = 'translateX(-40px)'; setTimeout(() => item.remove(), 300); }
            showToast('Задача удалена');
            refreshSidebar();
            refreshKanbanIfOnCalendar();
            if (location.pathname.match(/^\/tasks\/\d+\/$/)) {
                setTimeout(() => spaNavigate('/'), 400);
            }
        }
    } catch { showToast('Ошибка при удалении', 'error'); }
}

function insertTaskIntoDOM(html, taskId) {
    const list = document.querySelector('.task-list');
    if (!list) {
        if (refreshKanbanIfOnCalendar()) return;
        softReloadContent();
        return;
    }
    const tmp = document.createElement('div');
    tmp.innerHTML = html.trim();
    const newItem = tmp.firstElementChild;
    if (newItem) {
        newItem.style.opacity = '0';
        newItem.style.transform = 'translateY(-10px)';
        list.prepend(newItem);
        requestAnimationFrame(() => { newItem.style.transition = 'all 0.3s ease'; newItem.style.opacity = '1'; newItem.style.transform = 'translateY(0)'; });
        const c = document.querySelector('.task-section-count');
        if (c) c.textContent = parseInt(c.textContent || 0) + 1;
    }
    const empty = document.querySelector('.empty-state');
    if (empty) empty.style.display = 'none';
}

// ====================================
// QUICK ADD TASK
// ====================================

document.addEventListener('DOMContentLoaded', () => {
    const input = document.getElementById('quickAddInput');
    if (input) input.addEventListener('keypress', (e) => { if (e.key === 'Enter') { e.preventDefault(); quickAddTask(); } });
});

async function quickAddTask() {
    const input = document.getElementById('quickAddInput');
    if (!input) return;
    const title = input.value.trim();
    if (!title) return;
    const projectId = input.dataset.project || '';
    const dueDate = input.dataset.dueDate || '';
    input.disabled = true;
    try {
        const params = new URLSearchParams({ title });
        if (projectId) params.set('project', projectId);
        if (dueDate) params.set('due_date', dueDate);
        const data = await apiFetch('/tasks/create/', { method: 'POST', body: params.toString() });
        if (data.success) {
            input.value = '';
            showToast('Задача добавлена');
            if (refreshKanbanIfOnCalendar()) {
                /* календарь обновлён */
            } else if (data.html) insertTaskIntoDOM(data.html, data.id);
            else softReloadContent();
            refreshSidebar();
        }
    } catch { showToast('Ошибка при добавлении', 'error'); }
    finally { input.disabled = false; input.focus(); }
}

// ====================================
// CHECKLIST FUNCTIONS
// ====================================

async function addChecklistItem(taskId) {
    const input = document.getElementById('checklistInput');
    const text = input.value.trim();
    if (!text) return;
    try {
        const data = await apiFetch(`/tasks/${taskId}/checklist/add/`, { method: 'POST', body: `text=${encodeURIComponent(text)}` });
        if (data.success) {
            const cl = document.querySelector('.checklist');
            const ni = createChecklistItemElement(data.id, data.text);
            cl.insertBefore(ni, document.querySelector('.checklist-add'));
            input.value = '';
            ni.style.opacity = '0'; ni.style.transform = 'translateX(-10px)';
            requestAnimationFrame(() => { ni.style.transition = 'all 0.3s ease'; ni.style.opacity = '1'; ni.style.transform = 'translateX(0)'; });
            refreshChecklistProgress();
        }
    } catch { showToast('Ошибка', 'error'); }
}

async function toggleChecklistItem(itemId) {
    try {
        const data = await apiFetch(`/checklist/${itemId}/toggle/`, { method: 'POST' });
        if (data.success) {
            const item = document.querySelector(`.checklist-item[data-id="${itemId}"]`);
            if (item) item.classList.toggle('completed', data.is_completed);
            if (data.progress) updateChecklistProgressBar(data.progress);
        }
    } catch { showToast('Ошибка', 'error'); }
}

async function deleteChecklistItem(itemId) {
    try {
        const data = await apiFetch(`/checklist/${itemId}/delete/`, { method: 'POST' });
        if (data.success) {
            const item = document.querySelector(`.checklist-item[data-id="${itemId}"]`);
            if (item) { item.style.transition = 'all 0.2s ease'; item.style.opacity = '0'; item.style.transform = 'translateX(-20px)'; setTimeout(() => item.remove(), 200); }
            if (data.progress) updateChecklistProgressBar(data.progress);
            else { const bar = document.querySelector('.task-checklist-progress'); if (bar) bar.style.display = 'none'; }
        }
    } catch { showToast('Ошибка', 'error'); }
}

function createChecklistItemElement(id, text) {
    const div = document.createElement('div');
    div.className = 'checklist-item'; div.dataset.id = id;
    div.innerHTML = `<div class="task-checkbox"><input type="checkbox" id="check-${id}" onchange="toggleChecklistItem(${id})"><label for="check-${id}"></label></div><span class="checklist-text">${escapeHtml(text)}</span><button class="btn-icon checklist-delete" onclick="deleteChecklistItem(${id})"><i class="ri-close-line"></i></button>`;
    return div;
}

function updateChecklistProgressBar(progress) {
    const bar = document.querySelector('.progress-bar-fill');
    const text = document.querySelector('.checklist-progress-text');
    if (bar) bar.style.width = `${progress.percent}%`;
    if (text) text.textContent = `${progress.completed}/${progress.total}`;
}

function refreshChecklistProgress() {
    const total = document.querySelectorAll('.checklist-item').length;
    const completed = document.querySelectorAll('.checklist-item.completed').length;
    if (total > 0) updateChecklistProgressBar({ completed, total, percent: Math.round(completed / total * 100) });
}

// ====================================
// PROJECT FUNCTIONS
// ====================================

async function deleteProject(projectId) {
    if (!confirm('Удалить проект? Все задачи тоже будут удалены.')) return;
    try {
        const data = await apiFetch(`/projects/${projectId}/delete/`, { method: 'POST' });
        if (data.success) { showToast('Проект удалён'); refreshSidebar(); spaNavigate('/projects/'); }
    } catch { showToast('Ошибка', 'error'); }
}

async function archiveProject(projectId) {
    try {
        const data = await apiFetch(`/projects/${projectId}/edit/`, { method: 'POST', body: 'is_archived=true' });
        if (data.success) {
            const item = document.querySelector(`.project-list-item[data-id="${projectId}"]`);
            if (item) { item.style.transition = 'all 0.3s ease'; item.style.opacity = '0'; item.style.transform = 'translateX(-30px)'; setTimeout(() => { item.remove(); softReloadContent(); }, 300); }
            showToast('Проект архивирован'); refreshSidebar();
        }
    } catch { showToast('Ошибка', 'error'); }
}

async function restoreProject(projectId) {
    try {
        const data = await apiFetch(`/projects/${projectId}/restore/`, { method: 'POST' });
        if (data.success) {
            const item = document.querySelector(`.project-list-item[data-id="${projectId}"]`);
            if (item) { item.style.transition = 'all 0.3s ease'; item.style.opacity = '0'; setTimeout(() => { item.remove(); softReloadContent(); }, 300); }
            showToast('Проект восстановлен'); refreshSidebar();
        }
    } catch { showToast('Ошибка', 'error'); }
}

async function deleteProjectPermanent(projectId) {
    if (!confirm('Удалить проект навсегда?')) return;
    try {
        const data = await apiFetch(`/projects/${projectId}/delete/`, { method: 'POST' });
        if (data.success) {
            const item = document.querySelector(`.project-list-item[data-id="${projectId}"]`);
            if (item) { item.style.transition = 'all 0.3s ease'; item.style.opacity = '0'; item.style.transform = 'scale(0.9)'; setTimeout(() => item.remove(), 300); }
            showToast('Проект удалён'); refreshSidebar();
        }
    } catch { showToast('Ошибка', 'error'); }
}

// ====================================
// TAG FUNCTIONS
// ====================================

async function deleteTag(tagId) {
    if (!confirm('Удалить тег?')) return;
    try {
        const data = await apiFetch(`/tags/${tagId}/delete/`, { method: 'POST' });
        if (data.success) {
            const card = document.querySelector(`.tag-card[data-id="${tagId}"]`);
            if (card) { card.style.transition = 'all 0.3s ease'; card.style.opacity = '0'; card.style.transform = 'scale(0.9)'; setTimeout(() => card.remove(), 300); }
            showToast('Тег удалён'); refreshSidebar();
        }
    } catch { showToast('Ошибка', 'error'); }
}

// ====================================
// SEARCH
// ====================================

document.addEventListener('DOMContentLoaded', () => {
    const si = document.getElementById('searchInput');
    if (!si) return;
    let t;
    si.addEventListener('input', (e) => {
        clearTimeout(t);
        t = setTimeout(() => {
            const q = e.target.value.trim().toLowerCase();
            if (q.length >= 2) filterTasks(q);
            else if (q.length === 0) showAllTasks();
        }, 200);
    });
});

function filterTasks(query) {
    document.querySelectorAll('.task-item').forEach(task => {
        const title = task.querySelector('.task-title')?.textContent.toLowerCase() || '';
        const desc = task.querySelector('.task-description')?.textContent.toLowerCase() || '';
        task.style.display = (title.includes(query) || desc.includes(query)) ? '' : 'none';
    });
}

function showAllTasks() {
    document.querySelectorAll('.task-item').forEach(t => { t.style.display = ''; });
}

// ====================================
// KEYBOARD SHORTCUTS
// ====================================

document.addEventListener('keydown', (e) => {
    if (e.key === 'n' && !isTyping()) { e.preventDefault(); openTaskModal(); }
    if (e.key === 'p' && !isTyping()) { e.preventDefault(); openProjectModal(); }
    if (e.key === '/' && !isTyping()) { e.preventDefault(); document.getElementById('searchInput')?.focus(); }
});

// ====================================
// TASK CHECKBOX EVENT DELEGATION
// ====================================

document.addEventListener('change', (e) => {
    if (e.target.matches('.task-item .task-checkbox input')) {
        const taskId = e.target.closest('.task-item')?.dataset.id;
        if (taskId) toggleTask(taskId);
    }
});

// ====================================
// CALENDAR (избегаем softReload на /calendar/ — он ломает init скрипта)
// ====================================

function refreshKanbanIfOnCalendar() {
    if (location.pathname !== '/calendar/') return false;
    const k = window.kanbanCalendar;
    if (k && typeof k.reload === 'function') {
        void k.reload();
        return true;
    }
    return false;
}

// ====================================
// SOFT RELOAD CONTENT
// ====================================

async function softReloadContent() {
    try {
        const response = await fetch(location.href);
        const html = await response.text();
        const doc = new DOMParser().parseFromString(html, 'text/html');
        const newContent = doc.querySelector('.content-body');
        const currentContent = document.querySelector('.content-body');
        if (newContent && currentContent) {
            currentContent.style.opacity = '0';
            currentContent.style.transition = 'opacity 0.12s ease';
            setTimeout(() => {
                currentContent.innerHTML = newContent.innerHTML;
                currentContent.style.opacity = '1';
                execContentScripts();
                reinitPage();
            }, 120);
        }
    } catch { location.reload(); }
}

// ====================================
// STATS / MOTIVATION WIDGET
// ====================================

async function loadStatsWidget() {
    try {
        const d = await apiFetch('/api/stats/');
        if (typeof d.streak === 'number') renderStatsWidget(d);
    } catch {}
}

function renderStatsWidget(data) {
    const widget = document.getElementById('statsWidget');
    if (!widget) return;
    const se = data.streak >= 7 ? '🔥' : data.streak >= 3 ? '⚡' : '✨';
    const quotes = [
        'Каждая завершённая задача — шаг к цели',
        'Маленькие шаги ведут к большим результатам',
        'Фокус — ключ к продуктивности',
        'Ты на верном пути!',
        'Сегодня отличный день для свершений',
        'Дисциплина — это свобода',
        'Делай то, что важно прямо сейчас',
    ];
    widget.innerHTML = `
        <div class="stats-cards">
            <div class="stat-card stat-streak"><div class="stat-icon">${se}</div><div class="stat-info"><span class="stat-number">${data.streak}</span><span class="stat-label">${pluralize(data.streak, 'день', 'дня', 'дней')} подряд</span></div></div>
            <div class="stat-card stat-today-done"><div class="stat-icon"><i class="ri-check-double-line"></i></div><div class="stat-info"><span class="stat-number">${data.completed_today}</span><span class="stat-label">сегодня</span></div></div>
            <div class="stat-card stat-week-done"><div class="stat-icon"><i class="ri-bar-chart-line"></i></div><div class="stat-info"><span class="stat-number">${data.completed_this_week}</span><span class="stat-label">за неделю</span></div></div>
            ${data.overdue > 0 ? `<div class="stat-card stat-overdue"><div class="stat-icon"><i class="ri-alarm-warning-line"></i></div><div class="stat-info"><span class="stat-number">${data.overdue}</span><span class="stat-label">просрочено</span></div></div>` : ''}
        </div>
        <div class="stats-quote"><i class="ri-lightbulb-flash-line"></i><span>${quotes[new Date().getDay()]}</span></div>
    `;
    widget.style.animation = 'slideUp 0.4s ease';
    window.updateStatsWidget = (d) => renderStatsWidget(d);
}

// ====================================
// CSS ANIMATION HELPERS
// ====================================

const animStyle = document.createElement('style');
animStyle.textContent = `
    @keyframes fadeOut{from{opacity:1;transform:translateX(0)}to{opacity:0;transform:translateX(-20px)}}
    @keyframes slideIn{from{opacity:0;transform:translateY(-10px)}to{opacity:1;transform:translateY(0)}}
`;
document.head.appendChild(animStyle);

// ====================================
// БЮДЖЕТ — ДАННЫЕ И УТИЛИТЫ
// ====================================

function formatBudgetMoney(s) {
    const n = parseFloat(String(s).replace(',', '.'));
    return Number.isNaN(n) ? String(s) : String(Math.round(n));
}

// ====================================
// БЮДЖЕТ — САЙДБАР И СВОДКА
// ====================================

async function refreshBudgetSidebar() {
    const root = document.getElementById('budgetSidebarCard');
    if (!root) return;
    try {
        const data = await apiFetch('/api/budget/summary/');
        if (!data.success) return;
        const ml = document.getElementById('budgetSidebarMonthLabel');
        if (ml) ml.textContent = data.month_label_short || '';
    } catch {}
}

async function refreshBudgetPageSummary() {
    const page = document.getElementById('budgetPage');
    if (!page) return;
    try {
        const data = await apiFetch(`/api/budget/summary/?year=${page.dataset.year}&month=${page.dataset.month}`);
        if (!data.success) return;
        const set = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = `${formatBudgetMoney(val)} ₽`; };
        set('budgetCardPlanned', data.total_planned);
        set('budgetCardSetAside', data.total_set_aside);
        set('budgetCardRemain', data.total_remaining);
        set('budgetCardExpenses', data.expenses_month);
        const hint = document.getElementById('budgetCardSetAsideHint');
        if (hint) hint.textContent = `${data.progress_pct || 0}% от плана`;
    } catch {}
}

function initBudgetSidebarQuick() {
    const form = document.getElementById('budgetSidebarQuickExpense');
    if (!form || form._bound) return;
    form._bound = true;
    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const inp = form.querySelector('input[name="amount"]');
        const catInp = form.querySelector('input[name="category"]');
        const noteInp = form.querySelector('input[name="note"]');
        if (!inp) return;
        const amount = inp.value.trim();
        if (!amount) return;
        const category = (catInp?.value || '').trim();
        const note = (noteInp?.value || '').trim();
        try {
            const card = document.getElementById('budgetSidebarCard');
            const pid = card?.dataset?.dailyPeriodId;
            const payload = {
                amount,
                date: new Date().toISOString().slice(0, 10),
                note,
                category,
            };
            if (pid) payload.daily_budget_period_id = parseInt(pid, 10);
            const data = await apiFetch('/api/budget/expense/add/', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload),
            });
            if (data.success) {
                inp.value = '';
                if (catInp) catInp.value = '';
                if (noteInp) noteInp.value = '';
                showToast('Расход записан', 'success');
                refreshBudgetSidebar();
                refreshBudgetPageSummary();
                if (location.pathname === '/budget/') {
                    prependExpenseToList(data.expense);
                    if (data.expense.daily_budget_period_id && document.getElementById('dailyLedgerBody')) window.location.reload();
                }
            } else showToast(data.error || 'Ошибка', 'error');
        } catch (err) { showToast(err.message || 'Ошибка', 'error'); }
    });
}

// ====================================
// БЮДЖЕТ — ПОСТРОЕНИЕ DOM
// ====================================

function createBudgetItemRow(item) {
    const tr = document.createElement('tr');
    tr.dataset.id = item.id;
    tr.innerHTML = `
        <td><input type="text" class="form-input budget-in-title" value="${escapeHtml(item.title)}" aria-label="Название"></td>
        <td><input type="number" class="form-input budget-in-num" step="0.01" min="0.01" value="${escapeHtml(item.amount_planned)}" aria-label="Нужно"></td>
        <td><input type="number" class="form-input budget-in-num" step="0.01" min="0" value="${escapeHtml(item.amount_set_aside)}" aria-label="Отложено"></td>
        <td><button type="button" class="btn-icon budget-row-del" title="Удалить"><i class="ri-delete-bin-line"></i></button></td>`;
    return tr;
}

function syncBudgetMandatoryBadge() {
    const badge = document.querySelector('.budget-disclosure-badge');
    const body = document.getElementById('budgetItemsBody');
    if (!badge || !body) return;
    badge.textContent = String(body.querySelectorAll('tr[data-id]').length);
}

function prependExpenseToList(exp) {
    const list = document.getElementById('budgetExpenseList');
    if (!list || !exp) return;
    const empty = list.querySelector('.budget-expense-empty');
    if (empty) empty.remove();
    const li = document.createElement('li');
    li.className = 'budget-expense-item';
    li.dataset.id = exp.id;
    const d = exp.date.split('-');
    const dm = d.length === 3 ? `${d[2]}.${d[1]}` : exp.date;
    const cat = exp.category ? `<span class="budget-expense-cat">${escapeHtml(exp.category)}</span>` : '';
    const daily = exp.daily_budget_period_id ? '<span class="budget-expense-daily" title="В дневном лимите"><i class="ri-hand-coin-line"></i></span>' : '';
    if (exp.daily_budget_period_id) li.dataset.inDaily = '1';
    li.innerHTML = `<span class="budget-expense-date">${dm}</span><span class="budget-expense-amt">${formatBudgetMoney(exp.amount)} ₽</span>${cat}${daily}<span class="budget-expense-note">${escapeHtml(exp.note || '')}</span><button type="button" class="btn-icon budget-expense-del" title="Удалить"><i class="ri-close-line"></i></button>`;
    list.insertBefore(li, list.firstChild);
}

// ====================================
// БЮДЖЕТ — АВТО-СОХРАНЕНИЕ СТРОК
// ====================================

const _budgetRowTimers = new Map();

function scheduleBudgetRowSave(tr) {
    const id = tr.dataset.id;
    if (!id) return;
    clearTimeout(_budgetRowTimers.get(id));
    _budgetRowTimers.set(id, setTimeout(() => saveBudgetRow(tr), 450));
}

async function saveBudgetRow(tr) {
    const id = tr.dataset.id;
    if (!id) return;
    const nums = tr.querySelectorAll('.budget-in-num');
    const plannedRaw = nums[0]?.value?.trim();
    const asideRaw = nums[1]?.value?.trim();
    const body = {
        id: parseInt(id, 10),
    };
    const title = tr.querySelector('.budget-in-title')?.value?.trim();
    if (title) body.title = title;
    if (plannedRaw !== undefined && plannedRaw !== '') body.amount_planned = plannedRaw;
    body.amount_set_aside = asideRaw === '' || asideRaw === undefined ? '0' : asideRaw;
    try {
        const data = await apiFetch('/api/budget/item/update/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        });
        if (!data.success) {
            showToast(data.error || 'Не удалось сохранить строку', 'error');
            return;
        }
        refreshBudgetSidebar();
        refreshBudgetPageSummary();
    } catch (err) {
        showToast(err.message || 'Ошибка сохранения', 'error');
    }
}

// ====================================
// БЮДЖЕТ — ДЕЙСТВИЯ (API-вызовы)
// ====================================

async function budgetAddItem() {
    const page = document.getElementById('budgetPage');
    if (!page) return;
    const titleEl = document.getElementById('budgetNewTitle');
    const amtEl = document.getElementById('budgetNewAmount');
    const title = titleEl?.value?.trim();
    const amt = amtEl?.value?.trim();
    if (!title || !amt) { showToast('Укажите название и сумму', 'warning'); return; }
    try {
        const data = await apiFetch('/api/budget/item/add/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                title, amount_planned: amt,
                year: parseInt(page.dataset.year, 10),
                month: parseInt(page.dataset.month, 10),
            }),
        });
        if (data.success && data.item) {
            titleEl.value = '';
            amtEl.value = '';
            const body = document.getElementById('budgetItemsBody');
            const empty = body?.querySelector('.budget-table-empty');
            if (empty) empty.remove();
            body?.appendChild(createBudgetItemRow(data.item));
            syncBudgetMandatoryBadge();
            refreshBudgetSidebar();
            refreshBudgetPageSummary();
            showToast('Статья добавлена', 'success');
        } else showToast(data.error || 'Ошибка', 'error');
    } catch (err) { showToast(err.message || 'Ошибка', 'error'); }
}

async function budgetAddExpense() {
    const dateVal = document.getElementById('budgetExpDate')?.value;
    const amtVal = document.getElementById('budgetExpAmount')?.value?.trim();
    const note = document.getElementById('budgetExpNote')?.value?.trim() || '';
    const category = document.getElementById('budgetExpCat')?.value?.trim() || '';
    if (!dateVal || !amtVal) { showToast('Укажите дату и сумму', 'warning'); return; }
    try {
        const data = await apiFetch('/api/budget/expense/add/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ date: dateVal, amount: amtVal, note, category }),
        });
        if (data.success) {
            document.getElementById('budgetExpAmount').value = '';
            document.getElementById('budgetExpNote').value = '';
            document.getElementById('budgetExpCat').value = '';
            prependExpenseToList(data.expense);
            refreshBudgetSidebar();
            refreshBudgetPageSummary();
            showToast('Расход записан', 'success');
            if (data.expense.daily_budget_period_id && document.getElementById('dailyLedgerBody')) window.location.reload();
        } else showToast(data.error || 'Ошибка', 'error');
    } catch (err) { showToast(err.message || 'Ошибка', 'error'); }
}

async function budgetCreatePeriod() {
    const page = document.getElementById('budgetPage');
    if (!page) return;
    const title = document.getElementById('dailyNewTitle')?.value?.trim() || '';
    const start_date = document.getElementById('dailyNewStart')?.value;
    const end_date = document.getElementById('dailyNewEnd')?.value;
    const mode = page.querySelector('input[name="dailyMode"]:checked')?.value || 'daily';
    if (!start_date || !end_date) { showToast('Укажите даты периода', 'warning'); return; }
    const payload = { title, start_date, end_date, mode };
    if (mode === 'total') {
        const t = document.getElementById('dailyNewTotalAmt')?.value?.trim();
        if (!t) { showToast('Укажите сумму за период', 'warning'); return; }
        payload.total_amount = t;
    } else {
        const da = document.getElementById('dailyNewDailyAmt')?.value?.trim();
        if (!da) { showToast('Укажите норму в день', 'warning'); return; }
        payload.daily_allowance = da;
    }
    try {
        const data = await apiFetch('/api/budget/daily-period/add/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        if (data.success) {
            showToast('Период создан', 'success');
            const sd = data.period?.start_date;
            if (sd && /^\d{4}-\d{2}-\d{2}$/.test(sd)) {
                const [py, pm] = sd.split('-');
                window.location.href = `/budget/?year=${py}&month=${parseInt(pm, 10)}&daily_period=${data.period.id}`;
            } else {
                window.location.href = `/budget/?daily_period=${data.period.id}`;
            }
        } else showToast(data.error || 'Ошибка', 'error');
    } catch (err) { showToast(err.message || 'Ошибка', 'error'); }
}

async function budgetDeletePeriod(periodId) {
    if (!periodId) return;
    if (!confirm('Удалить период? Расходы останутся, но перестанут учитываться в дневном лимите.')) return;
    const page = document.getElementById('budgetPage');
    try {
        const data = await apiFetch('/api/budget/daily-period/delete/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id: parseInt(periodId, 10) }),
        });
        if (data.success) {
            showToast('Период удалён', 'success');
            if (page) window.location.href = `/budget/?year=${page.dataset.year}&month=${page.dataset.month}`;
            else window.location.href = '/budget/';
        } else showToast(data.error || 'Ошибка', 'error');
    } catch (err) { showToast(err.message || 'Ошибка', 'error'); }
}

async function budgetDeleteItemRow(tr) {
    if (!tr || !confirm('Удалить эту статью?')) return;
    try {
        const data = await apiFetch('/api/budget/item/delete/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id: parseInt(tr.dataset.id, 10) }),
        });
        if (data.success) {
            tr.remove();
            syncBudgetMandatoryBadge();
            refreshBudgetSidebar();
            refreshBudgetPageSummary();
            const body = document.getElementById('budgetItemsBody');
            if (body && !body.querySelector('tr[data-id]')) {
                body.innerHTML = '<tr class="budget-table-empty"><td colspan="4">Пока нет статей — добавьте первую ниже.</td></tr>';
            }
        } else showToast(data.error || 'Ошибка', 'error');
    } catch (err) { showToast(err.message || 'Ошибка', 'error'); }
}

async function budgetDeleteExpense(li) {
    if (!li) return;
    try {
        const data = await apiFetch('/api/budget/expense/delete/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id: parseInt(li.dataset.id, 10) }),
        });
        if (data.success) {
            const reloadDaily = li.dataset.inDaily === '1' && document.getElementById('dailyLedgerBody');
            li.remove();
            refreshBudgetSidebar();
            refreshBudgetPageSummary();
            const list = document.getElementById('budgetExpenseList');
            if (list && !list.querySelector('.budget-expense-item')) {
                list.innerHTML = '<li class="budget-expense-empty" id="budgetExpenseEmpty">За этот месяц расходов нет.</li>';
            }
            if (reloadDaily) window.location.reload();
        } else showToast(data.error || 'Ошибка', 'error');
    } catch (err) { showToast(err.message || 'Ошибка', 'error'); }
}

// ====================================
// БЮДЖЕТ — ИНИЦИАЛИЗАЦИЯ СТРАНИЦЫ
// ====================================

function syncBudgetDailyModeInputs() {
    const page = document.getElementById('budgetPage');
    if (!page) return;
    const checked = page.querySelector('input[name="dailyMode"]:checked');
    const isTotal = checked && checked.value === 'total';
    const da = document.getElementById('dailyNewDailyAmt');
    const ta = document.getElementById('dailyNewTotalAmt');
    if (da) da.disabled = !!isTotal;
    if (ta) ta.disabled = !isTotal;
}

function initBudgetPage() {
    const page = document.getElementById('budgetPage');
    if (!page) return;

    syncBudgetDailyModeInputs();

    // --- Кнопки: прямая привязка по ID (onclick= заменяет, не дублирует) ---

    const addItemBtn = document.getElementById('budgetAddItemBtn');
    if (addItemBtn) addItemBtn.onclick = () => budgetAddItem();

    const addExpBtn = document.getElementById('budgetAddExpenseBtn');
    if (addExpBtn) addExpBtn.onclick = () => budgetAddExpense();

    const createPeriodBtn = document.getElementById('dailyPeriodCreateBtn');
    if (createPeriodBtn) createPeriodBtn.onclick = () => budgetCreatePeriod();

    const delPeriodBtn = document.getElementById('dailyPeriodDeleteBtn');
    if (delPeriodBtn) delPeriodBtn.onclick = () => budgetDeletePeriod(delPeriodBtn.dataset.id);

    const periodSelect = document.getElementById('dailyPeriodSelect');
    if (periodSelect) periodSelect.onchange = () => {
        const id = periodSelect.value;
        const base = `/budget/?year=${page.dataset.year}&month=${page.dataset.month}`;
        window.location.href = id ? `${base}&daily_period=${id}` : base;
    };

    page.querySelectorAll('input[name="dailyMode"]').forEach(r => {
        r.onchange = syncBudgetDailyModeInputs;
    });

    // --- Делегирование на #budgetPage для динамических элементов ---
    if (page._budgetBound) return;
    page._budgetBound = true;

    page.addEventListener('click', (e) => {
        const del = e.target.closest('.budget-row-del');
        if (del) { budgetDeleteItemRow(del.closest('tr[data-id]')); return; }
        const expDel = e.target.closest('.budget-expense-del');
        if (expDel) budgetDeleteExpense(expDel.closest('.budget-expense-item'));
    });

    page.addEventListener('input', (e) => {
        const tr = e.target.closest('#budgetItemsBody tr[data-id]');
        if (tr && e.target.matches('.budget-in-title, .budget-in-num')) scheduleBudgetRowSave(tr);
    });
}
// ====================================
// MOBILE MENU
// ====================================

function toggleSidebar() {
    document.querySelector('.sidebar')?.classList.toggle('open');
}

const SIDEBAR_COLLAPSED_KEY = 'scopeSidebarCollapsed';

function updateSidebarCollapseButtonTitle() {
    const btn = document.querySelector('.sidebar-collapse-btn');
    if (!btn) return;
    const collapsed = document.body.classList.contains('sidebar-collapsed');
    btn.title = collapsed ? 'Развернуть меню' : 'Свернуть меню';
    btn.setAttribute('aria-label', collapsed ? 'Развернуть боковую панель' : 'Свернуть боковую панель');
}

function applySidebarCollapseFromStorage() {
    if (window.innerWidth <= 1024) {
        document.body.classList.remove('sidebar-collapsed');
    } else {
        try {
            if (localStorage.getItem(SIDEBAR_COLLAPSED_KEY) === '1') {
                document.body.classList.add('sidebar-collapsed');
            } else {
                document.body.classList.remove('sidebar-collapsed');
            }
        } catch {
            document.body.classList.remove('sidebar-collapsed');
        }
    }
    updateSidebarCollapseButtonTitle();
}

function toggleSidebarCollapse() {
    if (window.innerWidth <= 1024) return;
    document.body.classList.toggle('sidebar-collapsed');
    try {
        localStorage.setItem(SIDEBAR_COLLAPSED_KEY, document.body.classList.contains('sidebar-collapsed') ? '1' : '0');
    } catch { /* private mode */ }
    updateSidebarCollapseButtonTitle();
}

document.addEventListener('DOMContentLoaded', () => {
    applySidebarCollapseFromStorage();
    initBudgetSidebarQuick();
    reinitPage();
});
window.addEventListener('resize', () => { applySidebarCollapseFromStorage(); });

document.addEventListener('click', (e) => {
    const sidebar = document.querySelector('.sidebar');
    const menuBtn = e.target.closest('.mobile-menu-btn');
    if (menuBtn) return;
    if (window.innerWidth <= 1024 && sidebar?.classList.contains('open') && !sidebar.contains(e.target)) {
        sidebar.classList.remove('open');
    }
});
