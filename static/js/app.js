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
        if (['/', '/today/', '/calendar/', '/bullet-tasks/', '/budget/', '/projects/', '/tags/'].includes(p)) return true;
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
        /* translateY(0) всё равно создаёт containing block и ломает position:fixed у модалок внутри .content-body */
        content.style.transform = 'none';

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
        content.style.transform = 'none';
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
    if (typeof window.bulletTasksPageInit === 'function') {
        window.bulletTasksPageInit();
    }
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

function syncBudgetRowPaidClass(tr) {
    const cb = tr.querySelector('.budget-in-paid');
    tr.classList.toggle('budget-item-row--paid', !!(cb && cb.checked));
}

function createBudgetItemRow(item) {
    const tr = document.createElement('tr');
    tr.dataset.id = item.id;
    const paid = !!item.is_paid;
    tr.innerHTML = `
        <td><input type="text" class="form-input budget-in-title" value="${escapeHtml(item.title)}" aria-label="Название"></td>
        <td><input type="number" class="form-input budget-in-num" step="0.01" min="0.01" value="${escapeHtml(item.amount_planned)}" aria-label="Нужно"></td>
        <td><input type="number" class="form-input budget-in-num" step="0.01" min="0" value="${escapeHtml(item.amount_set_aside)}" aria-label="Отложено"></td>
        <td class="budget-paid-cell">
            <label class="budget-paid-label">
                <input type="checkbox" class="budget-in-paid" ${paid ? 'checked' : ''} aria-label="Оплатил">
                <span class="budget-paid-text">Оплатил</span>
            </label>
        </td>
        <td><button type="button" class="btn-icon budget-row-del" title="Удалить"><i class="ri-delete-bin-line"></i></button></td>`;
    if (paid) tr.classList.add('budget-item-row--paid');
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
    const paidCb = tr.querySelector('.budget-in-paid');
    if (paidCb) body.is_paid = paidCb.checked;
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
        if (data.item && paidCb) {
            paidCb.checked = !!data.item.is_paid;
            syncBudgetRowPaidClass(tr);
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
                body.innerHTML = '<tr class="budget-table-empty"><td colspan="5">Пока нет статей — добавьте первую ниже.</td></tr>';
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

    page.addEventListener('change', (e) => {
        const tr = e.target.closest('#budgetItemsBody tr[data-id]');
        if (tr && e.target.matches('.budget-in-paid')) {
            syncBudgetRowPaidClass(tr);
            scheduleBudgetRowSave(tr);
        }
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

// ====================================
// BULLETTASKS (раньше static/js/bullet_tasks.js — один бандл, без второго URL / MIME)
// ====================================
(function () {
    const BULLET_COLORS = [
        '#7C3AED', '#EC4899', '#F59E0B', '#10B981', '#3B82F6',
        '#EF4444', '#6366F1', '#14B8A6', '#8B5CF6', '#F97316',
        '#06B6D4', '#84CC16', '#A855F7', '#F472B6', '#64748B',
        '#78716C', '#0EA5E9', '#22C55E', '#EAB308', '#94A3B8',
    ];
    const BULLET_ICONS = [
        'fitness_center', 'task_alt', 'directions_run', 'self_improvement', 'water_drop',
        'restaurant', 'bed', 'book', 'code', 'music_note', 'savings', 'favorite',
        'star', 'bolt', 'timer', 'checklist', 'emoji_events', 'local_cafe', 'wb_sunny',
        'psychology', 'groups', 'home', 'sports_esports', 'pool',
    ];
    const WD_LABELS = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    const MONTHS_RU = [
        '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
        'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
    ];

    let _pickColor = BULLET_COLORS[0];
    let _pickIcon = BULLET_ICONS[0];
    const state = { tasks: [], histYear: null, histMonth: null };

    function isBulletPath() {
        return /\/bullet-tasks\/?$/.test(location.pathname);
    }

    function todayStr() {
        const t = new Date();
        return `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, '0')}-${String(t.getDate()).padStart(2, '0')}`;
    }

    function setWeekdayUIFromMask(mask) {
        const m = (mask && mask.length === 7) ? mask : '1111111';
        const row = document.getElementById('bulletWeekdayRow');
        if (!row) return;
        row.querySelectorAll('.bullet-wd').forEach((btn, i) => {
            btn.classList.toggle('is-on', m[i] === '1');
        });
    }

    function getMaskFromUI() {
        const row = document.getElementById('bulletWeekdayRow');
        if (!row) return '1111111';
        return Array.from(row.querySelectorAll('.bullet-wd'))
            .map(b => b.classList.contains('is-on') ? '1' : '0')
            .join('');
    }

    function initBulletStaticUI() {
        const cList = document.getElementById('bulletColorList');
        const iList = document.getElementById('bulletIconList');
        const row = document.getElementById('bulletWeekdayRow');
        const sInput = document.getElementById('bulletFormStart');
        if (sInput && !sInput.value) sInput.value = todayStr();

        if (cList && cList.children.length === 0) {
            cList.innerHTML = BULLET_COLORS.map(c => `
                <button type="button" class="bullet-swatch" data-c="${c}" style="--sw:${c};background-color:${c};" title="${c}" aria-label="цвет ${c}"></button>
            `).join('');
            cList.addEventListener('click', (e) => {
                const b = e.target.closest('.bullet-swatch');
                if (!b) return;
                _pickColor = b.dataset.c;
                cList.querySelectorAll('.bullet-swatch').forEach(x => x.classList.remove('is-picked'));
                b.classList.add('is-picked');
            });
        }
        if (iList && iList.children.length === 0) {
            iList.innerHTML = BULLET_ICONS.map(n => `
                <button type="button" class="bullet-ico" data-ico="${n}" title="${n}" aria-label="иконка ${n}">
                    <span class="material-symbols-outlined bullet-micon">${n}</span>
                </button>
            `).join('');
            iList.addEventListener('click', (e) => {
                const b = e.target.closest('.bullet-ico');
                if (!b) return;
                _pickIcon = b.dataset.ico;
                iList.querySelectorAll('.bullet-ico').forEach(x => x.classList.remove('is-picked'));
                b.classList.add('is-picked');
            });
        }
        if (row && row.children.length === 0) {
            row.innerHTML = WD_LABELS.map((lb, i) => `
                <button type="button" class="bullet-wd is-on" data-i="${i}">${lb}</button>
            `).join('');
            row.addEventListener('click', (e) => {
                const b = e.target.closest('.bullet-wd');
                if (!b) return;
                b.classList.toggle('is-on');
            });
        }
    }

    function pickDefaultModal(task) {
        initBulletStaticUI();
        const cList = document.getElementById('bulletColorList');
        const iList = document.getElementById('bulletIconList');
        if (task) {
            _pickColor = task.color;
            _pickIcon = task.icon;
            cList && cList.querySelectorAll('.bullet-swatch').forEach(x => {
                x.classList.toggle('is-picked', x.dataset.c === _pickColor);
            });
            iList && iList.querySelectorAll('.bullet-ico').forEach(x => {
                x.classList.toggle('is-picked', x.dataset.ico === _pickIcon);
            });
        } else {
            _pickColor = BULLET_COLORS[0];
            _pickIcon = BULLET_ICONS[0];
            cList && cList.querySelectorAll('.bullet-swatch').forEach((x, j) => x.classList.toggle('is-picked', j === 0));
            iList && iList.querySelectorAll('.bullet-ico').forEach((x, j) => x.classList.toggle('is-picked', j === 0));
        }
    }

    function phase(t, tStr) {
        if (tStr < t.start_date) return 'upcoming';
        if (tStr > t.end_date) return 'ended';
        return 'active';
    }

    /* две квадратные кнопки в ряд: ~44px + 44px (друг за другом, не столбиком) */
    const BULLET_REVEAL_PX = 88;

    function renderTaskCard(t, opts) {
        const dim = (opts && opts.dim) || false;
        const prog = t.progress;
        const pct = Math.min(100, Math.round(100 * prog.done / Math.max(1, prog.total)));
        const p = phase(t, state.today || todayStr());
        const phaseTag = p === 'upcoming' ? 'Скоро' : p === 'ended' ? 'Завершена' : '';
        const isTodayCol = !!(opts && opts.isTodayCol);
        const showToggle = !!(opts && opts.showToggle);
        const pts = t.total_points != null ? t.total_points : 0;
        const titleExtra = isTodayCol
            ? ''
            : (phaseTag
                ? `<span class="bullet-phase">${phaseTag}</span>`
                : `<span class="bullet-card-frac" title="Прогресс дней">${prog.done}/${prog.total}</span>`);
        const hairline = !isTodayCol
            ? `<div class="bullet-goals-hairline" aria-hidden="true"><span class="bullet-goals-hairline-in" style="width:${pct}%;background:${t.color}"></span></div>`
            : '';
        return `
        <div class="bullet-card bullet-card--swipe ${dim ? 'bullet-card--dim' : ''} ${!isTodayCol ? 'bullet-card--goals' : ''}" data-id="${t.id}" style="--bcol: ${t.color}; --reveal: ${BULLET_REVEAL_PX}px">
            <div class="bullet-card__track">
                <div class="bullet-card__face">
                    <div class="bullet-card__face-top">
                        <div class="bullet-card-accent" style="background:${t.color}"></div>
                        <div class="bullet-card-icon-wrap">
                            <span class="material-symbols-outlined bullet-micon">${t.icon}</span>
                        </div>
                        <div class="bullet-card-mid">
                            <div class="bullet-card-titleline">
                                <div class="bullet-card-title" title="${escapeHtml(t.title)}">${escapeHtml(t.title)}</div>
                                ${titleExtra}
                            </div>
                        </div>
                        <div class="bullet-card-pts" aria-label="Суммарно очков">
                            <i class="ri-star-fill" aria-hidden="true"></i><span>${pts}</span>
                        </div>
                        ${showToggle
                            ? `<button type="button" class="bullet-toggle-circle bullet-toggle" data-id="${t.id}" title="Выполнить" aria-label="Отметить выполнение">
                                <span class="bullet-toggle-circle__ring" aria-hidden="true"></span>
                               </button>`
                            : '<span class="bullet-toggle-spacer" aria-hidden="true"></span>'}
                    </div>
                    ${hairline}
                </div>
                <div class="bullet-card__reveal" aria-label="Действия">
                    <button type="button" class="bullet-reveal-btn bullet-reveal-btn--edit" data-edit="${t.id}" title="Изменить"><i class="ri-pencil-line"></i></button>
                    <button type="button" class="bullet-reveal-btn bullet-reveal-btn--del bullet-del" data-id="${t.id}" title="Удалить"><i class="ri-delete-bin-line"></i></button>
                </div>
            </div>
        </div>`;
    }

    function bindBulletCardSwipes() {
        const root = document.getElementById('bulletTasksRoot');
        if (!root) return;
        const resetTrack = (c) => {
            const t = c.querySelector('.bullet-card__track');
            if (t) t.style.removeProperty('transform');
        };
        const hideAll = () => {
            root.querySelectorAll('.bullet-card--swipe.is-revealed').forEach((c) => {
                c.classList.remove('is-revealed');
                resetTrack(c);
            });
        };
        if (!root._bulletDocClose) {
            root._bulletDocClose = true;
            document.addEventListener('click', (e) => {
                if (!e.target.closest('#bulletTasksRoot .bullet-card--swipe')) hideAll();
            });
        }
        root.querySelectorAll('.bullet-card--swipe').forEach((card) => {
            if (card._bulletSwipe) return;
            card._bulletSwipe = true;
            const track = card.querySelector('.bullet-card__track');
            const face = card.querySelector('.bullet-card__face');
            if (!track || !face) return;
            const wpx = () => (parseInt(getComputedStyle(card).getPropertyValue('--reveal'), 10) || BULLET_REVEAL_PX);
            let startX = 0;
            let baseTx = 0;
            let dragging = false;
            const setTx = (tx) => {
                const m = wpx();
                if (tx > 0) tx = 0;
                if (tx < -m) tx = -m;
                track.style.transition = 'none';
                track.style.transform = `translate3d(${tx}px,0,0)`;
            };
            face.addEventListener('pointerdown', (e) => {
                if (e.target.closest('button, .bullet-toggle-circle, .bullet-toggle')) return;
                dragging = true;
                startX = e.clientX;
                baseTx = card.classList.contains('is-revealed') ? -wpx() : 0;
                if (track.style.transform) {
                    const mm = /translate3d\((-?\d+(?:\.\d+)?)px/.exec(track.style.transform);
                    if (mm) baseTx = parseFloat(mm[1], 10);
                }
                face.setPointerCapture(e.pointerId);
            });
            face.addEventListener('pointermove', (e) => {
                if (!dragging) return;
                if (!e.buttons) return;
                setTx(baseTx + (e.clientX - startX));
            });
            face.addEventListener('pointerup', (e) => {
                if (!dragging) return;
                dragging = false;
                const m = wpx();
                const endTx = baseTx + (e.clientX - startX);
                const threshold = -m * 0.45;
                const on = endTx < threshold;
                if (on) {
                    card.classList.add('is-revealed');
                    root.querySelectorAll('.bullet-card--swipe.is-revealed').forEach((c) => {
                        if (c !== card) { c.classList.remove('is-revealed'); resetTrack(c); }
                    });
                } else {
                    card.classList.remove('is-revealed');
                }
                track.style.removeProperty('transform');
                try { face.releasePointerCapture(e.pointerId); } catch { /* */ }
            });
            face.addEventListener('pointercancel', () => {
                dragging = false;
                track.style.removeProperty('transform');
            });
        });
    }

    function renderAll() {
        const active = state.tasks.filter(x => x.today.scheduled && !x.today.done);
        const done = state.tasks.filter(x => x.today.scheduled && x.today.done);
        const elA = document.getElementById('bulletListActive');
        const elD = document.getElementById('bulletListDone');
        const g = document.getElementById('bulletGoalsGrid');
        if (elA) {
            elA.innerHTML = active.length
                ? active.map(t => renderTaskCard(t, { showToggle: true, dim: false, isTodayCol: true })).join('')
                : '<p class="bullet-empty">Нет задач на сегодня — добавьте цель или проверьте дни недели</p>';
        }
        if (elD) {
            elD.innerHTML = done.length
                ? done.map(t => renderTaskCard(t, { showToggle: true, dim: true, isTodayCol: true })).join('')
                : '<p class="bullet-empty bullet-empty--muted">Пока пусто</p>';
        }
        if (g) {
            g.innerHTML = state.tasks.length
                ? state.tasks.map(t => renderTaskCard(t, { showToggle: false, dim: false, isTodayCol: false })).join('')
                : '<p class="bullet-empty">Создайте первую микроцель</p>';
        }
        bindBulletCardSwipes();
    }

    async function loadTasks() {
        try {
            const res = await fetch('/api/bullet-tasks/');
            const d = await res.json();
            if (d.success) {
                state.today = d.today;
                state.tasks = d.tasks || [];
                renderAll();
            }
        } catch (e) {
            const elA = document.getElementById('bulletListActive');
            if (elA) elA.innerHTML = '<p class="bullet-empty">Не удалось загрузить</p>';
        }
    }

    async function loadHistory() {
        if (!document.getElementById('bulletHistoryList')) return;
        const t = new Date();
        if (state.histYear == null) state.histYear = t.getFullYear();
        if (state.histMonth == null) state.histMonth = t.getMonth() + 1;
        const y = state.histYear, m = state.histMonth;
        const label = document.getElementById('bulletHistLabel');
        if (label) label.textContent = `${MONTHS_RU[m]} ${y}`;
        const el = document.getElementById('bulletHistoryList');
        if (el) el.innerHTML = '<p class="bullet-empty">Загрузка…</p>';
        try {
            const res = await fetch(`/api/bullet-tasks/history/?year=${y}&month=${m}`);
            const d = await res.json();
            if (!d.success) throw new Error();
            if (!d.days || d.days.length === 0) {
                if (el) el.innerHTML = '<p class="bullet-empty bullet-empty--muted">За этот месяц нет отметок</p>';
                return;
            }
            if (el) {
                el.innerHTML = d.days.map(day => `
                    <div class="bullet-hist-day">
                        <div class="bullet-hist-date">${day.date}</div>
                        <div class="bullet-hist-items">
                            ${day.items.map(it => `
                                <div class="bullet-hist-pill" style="border-color:${it.color}33;background:${it.color}14">
                                    <span class="material-symbols-outlined bullet-micon" style="color:${it.color}">${it.icon}</span>
                                    <span>${escapeHtml(it.title)}</span>
                                    <span class="bullet-hist-pts">+${it.points}</span>
                                </div>
                            `).join('')}
                        </div>
                    </div>
                `).join('');
            }
        } catch (e) {
            if (el) el.innerHTML = '<p class="bullet-empty">Ошибка загрузки истории</p>';
        }
    }

    function openModal(t) {
        initBulletStaticUI();
        const modal = document.getElementById('bulletTaskModal');
        const title = document.getElementById('bulletModalTitle');
        const fid = document.getElementById('bulletFormId');
        const ft = document.getElementById('bulletFormTitle');
        const fd = document.getElementById('bulletFormDuration');
        const fp = document.getElementById('bulletFormPoints');
        const fs = document.getElementById('bulletFormStart');
        if (!modal) return;
        if (t) {
            if (title) title.textContent = 'Редактирование';
            if (fid) fid.value = t.id;
            if (ft) ft.value = t.title;
            if (fd) fd.value = t.duration_days;
            if (fp) fp.value = t.points_per_completion;
            if (fs) fs.value = t.start_date;
            setWeekdayUIFromMask(t.weekday_mask);
            pickDefaultModal(t);
        } else {
            if (title) title.textContent = 'Новая микрозадача';
            if (fid) fid.value = '';
            if (ft) ft.value = '';
            if (fd) fd.value = '15';
            if (fp) fp.value = '10';
            if (fs) fs.value = todayStr();
            setWeekdayUIFromMask('1111111');
            pickDefaultModal(null);
        }
        modal.classList.add('active');
    }

    function closeModal() {
        const modal = document.getElementById('bulletTaskModal');
        if (modal) modal.classList.remove('active');
    }

    async function saveForm() {
        const idEl = document.getElementById('bulletFormId');
        const id = idEl && idEl.value ? parseInt(idEl.value, 10) : null;
        const body = {
            id: id || undefined,
            title: (document.getElementById('bulletFormTitle') || {}).value,
            color: _pickColor,
            icon: _pickIcon,
            duration_days: parseInt((document.getElementById('bulletFormDuration') || {}).value, 10) || 15,
            points_per_completion: parseInt((document.getElementById('bulletFormPoints') || {}).value, 10) || 10,
            start_date: (document.getElementById('bulletFormStart') || {}).value,
            weekday_mask: getMaskFromUI(),
        };
        if (!getMaskFromUI().includes('1')) {
            showToast('Выберите хотя бы один день недели', 'error');
            return;
        }
        const data = await apiFetch('/api/bullet-tasks/save/', {
            method: 'POST',
            body: JSON.stringify(body),
            headers: { 'Content-Type': 'application/json' },
        });
        if (data.success) {
            showToast('Сохранено', 'success');
            closeModal();
            await loadTasks();
        } else {
            showToast(data.error || 'Ошибка', 'error');
        }
    }

    window.openBulletTaskModal = function (taskId) {
        if (taskId != null) {
            const t = state.tasks.find(x => x.id === taskId);
            return openModal(t);
        }
        openModal(null);
    };
    window.closeBulletTaskModal = closeModal;
    window.submitBulletTaskForm = function () { void saveForm(); };

    window.bulletTasksPageInit = function () {
        if (!isBulletPath()) return;
        initBulletStaticUI();
        void loadTasks();
        void loadHistory();
    };

    document.addEventListener('click', (e) => {
        if (!e.target.closest('.bullet-tasks-add')) return;
        e.preventDefault();
        openModal(null);
    }, true);

    document.addEventListener('click', async (e) => {
        const inRoot = e.target.closest('#bulletTasksRoot');
        if (inRoot) {
            const ed = e.target.closest('[data-edit]');
            if (ed) {
                openModal(state.tasks.find(x => x.id === +ed.dataset.edit));
                return;
            }
            const del = e.target.closest('.bullet-del');
            if (del) {
                const id = +del.dataset.id;
                if (!confirm('Удалить эту микроцель?')) return;
                const data = await apiFetch('/api/bullet-tasks/delete/', {
                    method: 'POST',
                    body: JSON.stringify({ id }),
                    headers: { 'Content-Type': 'application/json' },
                });
                if (data.success) { showToast('Удалено', 'info'); await loadTasks(); }
                return;
            }
            const tog = e.target.closest('.bullet-toggle');
            if (tog) {
                const id = +tog.dataset.id;
                const data = await apiFetch('/api/bullet-tasks/toggle/', {
                    method: 'POST',
                    body: JSON.stringify({ id }),
                    headers: { 'Content-Type': 'application/json' },
                });
                if (data.success) {
                    if (data.done === true) showToast(`+${data.points} очков`, 'success');
                    else showToast('Отметка снята', 'info');
                    await loadTasks();
                } else {
                    showToast(data.error || 'Ошибка', 'error');
                }
                return;
            }
        }
        if (e.target.closest('#bulletHistPrev')) {
            if (state.histMonth == null) return;
            e.preventDefault();
            state.histMonth -= 1;
            if (state.histMonth < 1) { state.histMonth = 12; state.histYear -= 1; }
            void loadHistory();
            return;
        }
        if (e.target.closest('#bulletHistNext')) {
            if (state.histMonth == null) return;
            e.preventDefault();
            state.histMonth += 1;
            if (state.histMonth > 12) { state.histMonth = 1; state.histYear += 1; }
            void loadHistory();
        }
    });

    initBulletStaticUI();
    if (isBulletPath()) {
        void loadTasks();
        void loadHistory();
    }
})();
