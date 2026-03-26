/**
 * SCOPE — Zen Task Planner
 * Main JavaScript — Full AJAX, smooth transitions, toast notifications
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
    const res = await fetch(url, merged);
    return res.json();
}

// ====================================
// TOAST NOTIFICATIONS
// ====================================

const toastQueue = [];
let toastContainer = null;

function ensureToastContainer() {
    if (!toastContainer) {
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

    const icons = {
        success: 'ri-check-line',
        error: 'ri-error-warning-line',
        info: 'ri-information-line',
        warning: 'ri-alarm-warning-line',
    };

    toast.innerHTML = `
        <i class="${icons[type] || icons.info}"></i>
        <span>${message}</span>
        <button class="toast-close" onclick="this.closest('.toast').remove()">
            <i class="ri-close-line"></i>
        </button>
    `;

    container.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('show'));

    setTimeout(() => {
        toast.classList.remove('show');
        toast.classList.add('hiding');
        setTimeout(() => toast.remove(), 300);
    }, duration);
}

// ====================================
// MODAL FUNCTIONS (with AJAX submit)
// ====================================

function openTaskModal(defaults = {}) {
    const modal = document.getElementById('taskModal');
    modal.classList.add('active');
    const form = document.getElementById('taskForm');

    if (defaults.project) {
        const sel = form.querySelector('select[name="project"]');
        if (sel) sel.value = defaults.project;
    }
    if (defaults.due_date) {
        const inp = form.querySelector('input[name="due_date"]');
        if (inp) inp.value = defaults.due_date;
    }

    setTimeout(() => form.querySelector('input[name="title"]')?.focus(), 100);
}

function closeTaskModal() {
    document.getElementById('taskModal').classList.remove('active');
    document.getElementById('taskForm').reset();
}

function openProjectModal() {
    document.getElementById('projectModal').classList.add('active');
    setTimeout(() => document.querySelector('#projectModal input[name="name"]')?.focus(), 100);
}

function closeProjectModal() {
    document.getElementById('projectModal').classList.remove('active');
    document.getElementById('projectForm').reset();
    const hex = document.getElementById('projectColorHex');
    if (hex) hex.value = '#7C3AED';
}

function openTagModal() {
    document.getElementById('tagModal').classList.add('active');
    setTimeout(() => document.querySelector('#tagModal input[name="name"]')?.focus(), 100);
}

function closeTagModal() {
    document.getElementById('tagModal').classList.remove('active');
    document.getElementById('tagForm').reset();
    const hex = document.getElementById('tagColorHex');
    if (hex) hex.value = '#7C3AED';
}

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        closeTaskModal();
        closeProjectModal();
        closeTagModal();
    }
});

// AJAX form handlers
document.addEventListener('DOMContentLoaded', () => {
    // Task form
    const taskForm = document.getElementById('taskForm');
    if (taskForm) {
        taskForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const fd = new FormData(taskForm);
            const body = new URLSearchParams(fd).toString();
            try {
                const data = await apiFetch(taskForm.action, { method: 'POST', body });
                if (data.success) {
                    closeTaskModal();
                    showToast('Задача создана');
                    if (data.html) {
                        insertTaskIntoDOM(data.html, data.id);
                    } else {
                        softReloadContent();
                    }
                    updateSidebarCounts();
                }
            } catch (err) {
                showToast('Ошибка при создании задачи', 'error');
            }
        });
    }

    // Project form
    const projectForm = document.getElementById('projectForm');
    if (projectForm) {
        projectForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const fd = new FormData(projectForm);
            const body = new URLSearchParams(fd).toString();
            try {
                const data = await apiFetch(projectForm.action, { method: 'POST', body });
                if (data.success) {
                    closeProjectModal();
                    showToast('Проект создан');
                    addProjectToSidebar(data);
                    if (window.location.pathname === '/projects/') {
                        softReloadContent();
                    }
                }
            } catch (err) {
                showToast('Ошибка при создании проекта', 'error');
            }
        });
    }

    // Tag form
    const tagForm = document.getElementById('tagForm');
    if (tagForm) {
        tagForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const fd = new FormData(tagForm);
            const body = new URLSearchParams(fd).toString();
            try {
                const data = await apiFetch(tagForm.action, { method: 'POST', body });
                if (data.success) {
                    closeTagModal();
                    showToast('Тег создан');
                    addTagToSidebar(data);
                    if (window.location.pathname === '/tags/') {
                        softReloadContent();
                    }
                }
            } catch (err) {
                showToast('Ошибка при создании тега', 'error');
            }
        });
    }
});

function addProjectToSidebar(project) {
    const navSections = document.querySelectorAll('.nav-section');
    if (navSections.length < 2) return;
    const projectsSection = navSections[1];
    const emptyLink = projectsSection.querySelector('.nav-empty-link');
    if (emptyLink) emptyLink.remove();

    const a = document.createElement('a');
    a.href = `/projects/${project.id}/`;
    a.className = 'nav-item';
    a.innerHTML = `
        <span class="project-dot" style="background-color: ${project.color || '#7C3AED'}"></span>
        <span>${escapeHtml(project.name)}</span>
    `;
    a.style.animation = 'slideUp 0.3s ease';
    const header = projectsSection.querySelector('.nav-section-header');
    if (header) header.insertAdjacentElement('afterend', a);
}

function addTagToSidebar(tag) {
    const navSections = document.querySelectorAll('.nav-section');
    if (navSections.length < 3) return;
    const tagsSection = navSections[2];
    const emptyP = tagsSection.querySelector('.nav-empty');
    if (emptyP) emptyP.remove();

    const a = document.createElement('a');
    a.href = `/?tag=${tag.id}`;
    a.className = 'nav-item nav-tag';
    a.innerHTML = `
        <span class="tag-dot" style="background-color: ${tag.color || '#7C3AED'}"></span>
        <span>${escapeHtml(tag.name)}</span>
    `;
    a.style.animation = 'slideUp 0.3s ease';
    tagsSection.appendChild(a);
}

// ====================================
// COLOR PICKER
// ====================================

function syncColorHex(colorInput, hexInputId) {
    const hex = document.getElementById(hexInputId);
    if (hex) hex.value = colorInput.value.toUpperCase();
}

function syncHexColor(hexInput, colorInputId) {
    const colorInput = document.getElementById(colorInputId);
    let v = hexInput.value;
    if (v && !v.startsWith('#')) { v = '#' + v; hexInput.value = v; }
    if (/^#[0-9A-Fa-f]{6}$/.test(v)) colorInput.value = v;
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
                        requestAnimationFrame(() => {
                            item.style.maxHeight = '0';
                            item.style.padding = '0 16px';
                            item.style.margin = '0';
                            item.style.overflow = 'hidden';
                        });
                        setTimeout(() => item.remove(), 300);
                    }, 300);
                    showToast('Задача завершена! ✓', 'success');
                } else {
                    item.classList.remove('completed');
                    showToast('Задача возвращена', 'info');
                }
                updateSidebarCounts();
            }
            // Calendar kanban update
            if (window.kanbanCalendar) window.kanbanCalendar.reload();
        }
    } catch (err) {
        showToast('Ошибка', 'error');
    }
}

async function deleteTask(taskId) {
    if (!confirm('Удалить задачу?')) return;
    try {
        const data = await apiFetch(`/tasks/${taskId}/delete/`, { method: 'POST' });
        if (data.success) {
            const item = document.querySelector(`.task-item[data-id="${taskId}"]`);
            if (item) {
                item.style.transition = 'all 0.3s ease';
                item.style.opacity = '0';
                item.style.transform = 'translateX(-40px)';
                setTimeout(() => item.remove(), 300);
            }
            showToast('Задача удалена');
            updateSidebarCounts();

            // If on task detail page, go back
            if (window.location.pathname.match(/^\/tasks\/\d+\/$/)) {
                setTimeout(() => { window.location.href = '/'; }, 500);
            }
        }
    } catch (err) {
        showToast('Ошибка при удалении', 'error');
    }
}

function insertTaskIntoDOM(html, taskId) {
    const list = document.querySelector('.task-list');
    if (!list) { softReloadContent(); return; }

    const temp = document.createElement('div');
    temp.innerHTML = html.trim();
    const newItem = temp.firstElementChild;
    if (newItem) {
        newItem.style.opacity = '0';
        newItem.style.transform = 'translateY(-10px)';
        list.prepend(newItem);
        requestAnimationFrame(() => {
            newItem.style.transition = 'all 0.3s ease';
            newItem.style.opacity = '1';
            newItem.style.transform = 'translateY(0)';
        });

        // Update count
        const countEl = document.querySelector('.task-section-count');
        if (countEl) countEl.textContent = parseInt(countEl.textContent || 0) + 1;
    }

    // Hide empty state
    const empty = document.querySelector('.empty-state');
    if (empty) empty.style.display = 'none';
}

// ====================================
// QUICK ADD TASK (NO RELOAD)
// ====================================

document.addEventListener('DOMContentLoaded', () => {
    const input = document.getElementById('quickAddInput');
    if (input) {
        input.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') { e.preventDefault(); quickAddTask(); }
        });
    }
});

async function quickAddTask() {
    const input = document.getElementById('quickAddInput');
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
            if (data.html) {
                insertTaskIntoDOM(data.html, data.id);
            } else {
                softReloadContent();
            }
            updateSidebarCounts();
        }
    } catch (err) {
        showToast('Ошибка при добавлении', 'error');
    } finally {
        input.disabled = false;
        input.focus();
    }
}

// ====================================
// CHECKLIST FUNCTIONS (fixed)
// ====================================

async function addChecklistItem(taskId) {
    const input = document.getElementById('checklistInput');
    const text = input.value.trim();
    if (!text) return;

    try {
        const data = await apiFetch(`/tasks/${taskId}/checklist/add/`, {
            method: 'POST',
            body: `text=${encodeURIComponent(text)}`,
        });
        if (data.success) {
            const checklist = document.querySelector('.checklist');
            const newItem = createChecklistItemElement(data.id, data.text);
            checklist.insertBefore(newItem, document.querySelector('.checklist-add'));
            input.value = '';
            // Animate in
            newItem.style.opacity = '0';
            newItem.style.transform = 'translateX(-10px)';
            requestAnimationFrame(() => {
                newItem.style.transition = 'all 0.3s ease';
                newItem.style.opacity = '1';
                newItem.style.transform = 'translateX(0)';
            });
            // Refresh progress
            refreshChecklistProgress(taskId);
        }
    } catch (err) {
        showToast('Ошибка', 'error');
    }
}

async function toggleChecklistItem(itemId) {
    try {
        const data = await apiFetch(`/checklist/${itemId}/toggle/`, { method: 'POST' });
        if (data.success) {
            const item = document.querySelector(`.checklist-item[data-id="${itemId}"]`);
            if (item) item.classList.toggle('completed', data.is_completed);
            if (data.progress) updateChecklistProgressBar(data.progress);
        }
    } catch (err) {
        showToast('Ошибка', 'error');
    }
}

async function deleteChecklistItem(itemId) {
    try {
        const data = await apiFetch(`/checklist/${itemId}/delete/`, { method: 'POST' });
        if (data.success) {
            const item = document.querySelector(`.checklist-item[data-id="${itemId}"]`);
            if (item) {
                item.style.transition = 'all 0.2s ease';
                item.style.opacity = '0';
                item.style.transform = 'translateX(-20px)';
                setTimeout(() => item.remove(), 200);
            }
            if (data.progress) updateChecklistProgressBar(data.progress);
            else {
                const bar = document.querySelector('.task-checklist-progress');
                if (bar) bar.style.display = 'none';
            }
        }
    } catch (err) {
        showToast('Ошибка', 'error');
    }
}

function createChecklistItemElement(id, text) {
    const div = document.createElement('div');
    div.className = 'checklist-item';
    div.dataset.id = id;
    div.innerHTML = `
        <div class="task-checkbox">
            <input type="checkbox" id="check-${id}" onchange="toggleChecklistItem(${id})">
            <label for="check-${id}"></label>
        </div>
        <span class="checklist-text">${escapeHtml(text)}</span>
        <button class="btn-icon checklist-delete" onclick="deleteChecklistItem(${id})">
            <i class="ri-close-line"></i>
        </button>
    `;
    return div;
}

function updateChecklistProgressBar(progress) {
    const bar = document.querySelector('.progress-bar-fill');
    const text = document.querySelector('.checklist-progress-text');
    if (bar) bar.style.width = `${progress.percent}%`;
    if (text) text.textContent = `${progress.completed}/${progress.total}`;
}

function refreshChecklistProgress(taskId) {
    const items = document.querySelectorAll('.checklist-item');
    const total = items.length;
    const completed = document.querySelectorAll('.checklist-item.completed').length;
    if (total > 0) {
        updateChecklistProgressBar({ completed, total, percent: Math.round(completed / total * 100) });
    }
}

// ====================================
// PROJECT FUNCTIONS
// ====================================

async function deleteProject(projectId) {
    if (!confirm('Удалить проект? Все задачи тоже будут удалены.')) return;
    try {
        const data = await apiFetch(`/projects/${projectId}/delete/`, { method: 'POST' });
        if (data.success) {
            showToast('Проект удалён');
            window.location.href = '/projects/';
        }
    } catch (err) {
        showToast('Ошибка', 'error');
    }
}

async function archiveProject(projectId) {
    try {
        const data = await apiFetch(`/projects/${projectId}/edit/`, {
            method: 'POST', body: 'is_archived=true',
        });
        if (data.success) {
            const item = document.querySelector(`.project-list-item[data-id="${projectId}"]`);
            if (item) {
                item.style.transition = 'all 0.3s ease';
                item.style.opacity = '0';
                item.style.transform = 'translateX(-30px)';
                setTimeout(() => { item.remove(); softReloadContent(); }, 300);
            }
            showToast('Проект архивирован');
        }
    } catch (err) {
        showToast('Ошибка', 'error');
    }
}

async function restoreProject(projectId) {
    try {
        const data = await apiFetch(`/projects/${projectId}/restore/`, { method: 'POST' });
        if (data.success) {
            const item = document.querySelector(`.project-list-item[data-id="${projectId}"]`);
            if (item) {
                item.style.transition = 'all 0.3s ease';
                item.style.opacity = '0';
                setTimeout(() => { item.remove(); softReloadContent(); }, 300);
            }
            showToast('Проект восстановлен');
        }
    } catch (err) {
        showToast('Ошибка', 'error');
    }
}

async function deleteProjectPermanent(projectId) {
    if (!confirm('Удалить проект навсегда? Все задачи тоже будут удалены.')) return;
    try {
        const data = await apiFetch(`/projects/${projectId}/delete/`, { method: 'POST' });
        if (data.success) {
            const item = document.querySelector(`.project-list-item[data-id="${projectId}"]`);
            if (item) {
                item.style.transition = 'all 0.3s ease';
                item.style.opacity = '0';
                item.style.transform = 'scale(0.9)';
                setTimeout(() => item.remove(), 300);
            }
            showToast('Проект удалён');
        }
    } catch (err) {
        showToast('Ошибка', 'error');
    }
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
            if (card) {
                card.style.transition = 'all 0.3s ease';
                card.style.opacity = '0';
                card.style.transform = 'scale(0.9)';
                setTimeout(() => card.remove(), 300);
            }
            showToast('Тег удалён');
        }
    } catch (err) {
        showToast('Ошибка', 'error');
    }
}

// ====================================
// SEARCH (debounced client-side)
// ====================================

document.addEventListener('DOMContentLoaded', () => {
    const searchInput = document.getElementById('searchInput');
    if (!searchInput) return;

    let timeout;
    searchInput.addEventListener('input', (e) => {
        clearTimeout(timeout);
        timeout = setTimeout(() => {
            const q = e.target.value.trim().toLowerCase();
            if (q.length >= 2) {
                filterTasks(q);
            } else if (q.length === 0) {
                showAllTasks();
            }
        }, 200);
    });
});

function filterTasks(query) {
    document.querySelectorAll('.task-item').forEach(task => {
        const title = task.querySelector('.task-title')?.textContent.toLowerCase() || '';
        const desc = task.querySelector('.task-description')?.textContent.toLowerCase() || '';
        const match = title.includes(query) || desc.includes(query);
        task.style.display = match ? '' : 'none';
        task.style.transition = 'opacity 0.2s ease';
        task.style.opacity = match ? '1' : '0';
    });
}

function showAllTasks() {
    document.querySelectorAll('.task-item').forEach(task => {
        task.style.display = '';
        task.style.opacity = '1';
    });
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
// SIDEBAR COUNTS UPDATE
// ====================================

async function updateSidebarCounts() {
    try {
        const data = await apiFetch('/api/stats/');
        // Update "Все задачи" badge
        const allBadge = document.querySelector('.nav-item[href="/"] .badge, .sidebar-nav .nav-section:first-child .nav-item:first-child .badge');
        if (allBadge) allBadge.textContent = data.total_active;

        // Update "Сегодня" badge
        const todayBadge = document.querySelector('.nav-item[href="/today/"] .badge, .sidebar-nav .nav-section:first-child .nav-item:nth-child(2) .badge');
        if (todayBadge) {
            todayBadge.textContent = data.today_tasks;
            if (!data.today_tasks) todayBadge.style.display = 'none';
            else todayBadge.style.display = '';
        }

        // Update stats widget if present
        if (window.updateStatsWidget) window.updateStatsWidget(data);
    } catch (err) {
        // silent fail
    }
}

// ====================================
// SOFT RELOAD CONTENT
// ====================================

async function softReloadContent() {
    try {
        const response = await fetch(window.location.href, {
            headers: { 'X-Requested-With': 'XMLHttpRequest' }
        });
        const html = await response.text();
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const newContent = doc.querySelector('.content-body');
        const currentContent = document.querySelector('.content-body');

        if (newContent && currentContent) {
            currentContent.style.opacity = '0';
            currentContent.style.transition = 'opacity 0.15s ease';
            setTimeout(() => {
                currentContent.innerHTML = newContent.innerHTML;
                currentContent.style.opacity = '1';
                // Re-init quick add
                const input = document.getElementById('quickAddInput');
                if (input) {
                    input.addEventListener('keypress', (e) => {
                        if (e.key === 'Enter') { e.preventDefault(); quickAddTask(); }
                    });
                }
            }, 150);
        }
    } catch (err) {
        window.location.reload();
    }
}

// ====================================
// STATS / MOTIVATION WIDGET
// ====================================

document.addEventListener('DOMContentLoaded', () => {
    const widget = document.getElementById('statsWidget');
    if (widget) loadStatsWidget();
});

async function loadStatsWidget() {
    try {
        const data = await apiFetch('/api/stats/');
        renderStatsWidget(data);
    } catch (err) { /* silent */ }
}

function renderStatsWidget(data) {
    const widget = document.getElementById('statsWidget');
    if (!widget) return;

    const streakEmoji = data.streak >= 7 ? '🔥' : data.streak >= 3 ? '⚡' : '✨';
    const motivations = [
        'Каждая завершённая задача — шаг к цели',
        'Маленькие шаги ведут к большим результатам',
        'Фокус — ключ к продуктивности',
        'Ты на верном пути!',
        'Сегодня отличный день для свершений',
        'Дисциплина — это свобода',
        'Делай то, что важно прямо сейчас',
    ];
    const quote = motivations[new Date().getDay()];

    widget.innerHTML = `
        <div class="stats-cards">
            <div class="stat-card stat-streak">
                <div class="stat-icon">${streakEmoji}</div>
                <div class="stat-info">
                    <span class="stat-number">${data.streak}</span>
                    <span class="stat-label">${pluralize(data.streak, 'день', 'дня', 'дней')} подряд</span>
                </div>
            </div>
            <div class="stat-card stat-today-done">
                <div class="stat-icon"><i class="ri-check-double-line"></i></div>
                <div class="stat-info">
                    <span class="stat-number">${data.completed_today}</span>
                    <span class="stat-label">сегодня</span>
                </div>
            </div>
            <div class="stat-card stat-week-done">
                <div class="stat-icon"><i class="ri-bar-chart-line"></i></div>
                <div class="stat-info">
                    <span class="stat-number">${data.completed_this_week}</span>
                    <span class="stat-label">за неделю</span>
                </div>
            </div>
            ${data.overdue > 0 ? `
            <div class="stat-card stat-overdue">
                <div class="stat-icon"><i class="ri-alarm-warning-line"></i></div>
                <div class="stat-info">
                    <span class="stat-number">${data.overdue}</span>
                    <span class="stat-label">просрочено</span>
                </div>
            </div>` : ''}
        </div>
        <div class="stats-quote">
            <i class="ri-lightbulb-flash-line"></i>
            <span>${quote}</span>
        </div>
    `;
    widget.style.animation = 'slideUp 0.4s ease';

    window.updateStatsWidget = (newData) => renderStatsWidget(newData);
}

// ====================================
// CSS ANIMATION HELPERS
// ====================================

const animStyle = document.createElement('style');
animStyle.textContent = `
    @keyframes fadeOut { from { opacity:1; transform:translateX(0); } to { opacity:0; transform:translateX(-20px); } }
    @keyframes slideIn { from { opacity:0; transform:translateY(-10px); } to { opacity:1; transform:translateY(0); } }
`;
document.head.appendChild(animStyle);

// ====================================
// MOBILE MENU
// ====================================

function toggleSidebar() {
    document.querySelector('.sidebar')?.classList.toggle('open');
}

document.addEventListener('click', (e) => {
    const sidebar = document.querySelector('.sidebar');
    if (window.innerWidth <= 1024 && sidebar?.classList.contains('open') && !sidebar.contains(e.target)) {
        sidebar.classList.remove('open');
    }
});
