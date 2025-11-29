/**
 * SCOPE - Task Tracking App
 * Main JavaScript File
 */

// ====================================
// MODAL FUNCTIONS
// ====================================

function openTaskModal() {
    document.getElementById('taskModal').classList.add('active');
    document.querySelector('#taskModal input[name="title"]').focus();
}

function closeTaskModal() {
    document.getElementById('taskModal').classList.remove('active');
    document.getElementById('taskForm').reset();
}

function openProjectModal() {
    document.getElementById('projectModal').classList.add('active');
    document.querySelector('#projectModal input[name="name"]').focus();
}

function closeProjectModal() {
    document.getElementById('projectModal').classList.remove('active');
    document.getElementById('projectForm').reset();
    // Reset hex input to default
    const hexInput = document.getElementById('projectColorHex');
    if (hexInput) hexInput.value = '#7C3AED';
}

function openTagModal() {
    document.getElementById('tagModal').classList.add('active');
    document.querySelector('#tagModal input[name="name"]').focus();
}

function closeTagModal() {
    document.getElementById('tagModal').classList.remove('active');
    document.getElementById('tagForm').reset();
    // Reset hex input to default
    const hexInput = document.getElementById('tagColorHex');
    if (hexInput) hexInput.value = '#7C3AED';
}

// Close modals on Escape key
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        closeTaskModal();
        closeProjectModal();
        closeTagModal();
    }
});

// ====================================
// COLOR PICKER FUNCTIONS
// ====================================

function syncColorHex(colorInput, hexInputId) {
    const hexInput = document.getElementById(hexInputId);
    if (hexInput) {
        hexInput.value = colorInput.value.toUpperCase();
    }
}

function syncHexColor(hexInput, colorInputId) {
    const colorInput = document.getElementById(colorInputId);
    let value = hexInput.value;
    
    // Add # if missing
    if (value && !value.startsWith('#')) {
        value = '#' + value;
        hexInput.value = value;
    }
    
    // Validate and apply
    if (/^#[0-9A-Fa-f]{6}$/.test(value)) {
        colorInput.value = value;
    }
}

function setColor(color, colorInputId, hexInputId) {
    const colorInput = document.getElementById(colorInputId);
    const hexInput = document.getElementById(hexInputId);
    
    if (colorInput) colorInput.value = color;
    if (hexInput) hexInput.value = color.toUpperCase();
}

// ====================================
// TASK FUNCTIONS
// ====================================

function toggleTask(taskId) {
    fetch(`/tasks/${taskId}/toggle/`, {
        method: 'POST',
        headers: {
            'X-CSRFToken': getCSRFToken(),
            'X-Requested-With': 'XMLHttpRequest',
        },
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            const taskItem = document.querySelector(`.task-item[data-id="${taskId}"]`);
            if (taskItem) {
                taskItem.classList.toggle('completed', data.is_completed);
                
                // Animate the task out if completed
                if (data.is_completed) {
                    taskItem.style.animation = 'fadeOut 0.3s ease forwards';
                    setTimeout(() => {
                        taskItem.style.display = 'none';
                        updateTaskCounts();
                    }, 300);
                }
            }
        }
    })
    .catch(error => console.error('Error:', error));
}

function deleteTask(taskId) {
    if (!confirm('Удалить эту задачу?')) return;
    
    fetch(`/tasks/${taskId}/delete/`, {
        method: 'POST',
        headers: {
            'X-CSRFToken': getCSRFToken(),
            'X-Requested-With': 'XMLHttpRequest',
        },
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            const taskItem = document.querySelector(`.task-item[data-id="${taskId}"]`);
            if (taskItem) {
                taskItem.style.animation = 'fadeOut 0.3s ease forwards';
                setTimeout(() => {
                    taskItem.remove();
                    updateTaskCounts();
                }, 300);
            }
        }
    })
    .catch(error => console.error('Error:', error));
}

// ====================================
// CHECKLIST FUNCTIONS
// ====================================

function addChecklistItem(taskId) {
    const input = document.getElementById('checklistInput');
    const text = input.value.trim();
    
    if (!text) return;
    
    fetch(`/tasks/${taskId}/checklist/add/`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-CSRFToken': getCSRFToken(),
            'X-Requested-With': 'XMLHttpRequest',
        },
        body: `text=${encodeURIComponent(text)}`,
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            const checklist = document.querySelector('.checklist');
            const newItem = createChecklistItemElement(data.id, data.text);
            checklist.insertBefore(newItem, document.querySelector('.checklist-add'));
            input.value = '';
            updateChecklistProgress();
        }
    })
    .catch(error => console.error('Error:', error));
}

function toggleChecklistItem(itemId) {
    fetch(`/checklist/${itemId}/toggle/`, {
        method: 'POST',
        headers: {
            'X-CSRFToken': getCSRFToken(),
            'X-Requested-With': 'XMLHttpRequest',
        },
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            const item = document.querySelector(`.checklist-item[data-id="${itemId}"]`);
            if (item) {
                item.classList.toggle('completed', data.is_completed);
            }
            if (data.progress) {
                updateChecklistProgressBar(data.progress);
            }
        }
    })
    .catch(error => console.error('Error:', error));
}

function deleteChecklistItem(itemId) {
    fetch(`/checklist/${itemId}/delete/`, {
        method: 'POST',
        headers: {
            'X-CSRFToken': getCSRFToken(),
            'X-Requested-With': 'XMLHttpRequest',
        },
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            const item = document.querySelector(`.checklist-item[data-id="${itemId}"]`);
            if (item) {
                item.remove();
            }
            if (data.progress) {
                updateChecklistProgressBar(data.progress);
            }
        }
    })
    .catch(error => console.error('Error:', error));
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
    if (bar) {
        bar.style.width = `${progress.percent}%`;
    }
    if (text) {
        text.textContent = `${progress.completed}/${progress.total}`;
    }
}

// ====================================
// PROJECT FUNCTIONS
// ====================================

function deleteProject(projectId) {
    if (!confirm('Удалить этот проект? Все задачи проекта также будут удалены.')) return;
    
    fetch(`/projects/${projectId}/delete/`, {
        method: 'POST',
        headers: {
            'X-CSRFToken': getCSRFToken(),
            'X-Requested-With': 'XMLHttpRequest',
        },
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            window.location.href = '/projects/';
        }
    })
    .catch(error => console.error('Error:', error));
}

// ====================================
// COLOR PICKER
// ====================================

document.querySelectorAll('.color-preset').forEach(btn => {
    btn.addEventListener('click', () => {
        const color = btn.dataset.color;
        const colorInput = btn.closest('.color-picker').querySelector('.color-input');
        colorInput.value = color;
        
        // Update active state
        btn.closest('.color-presets').querySelectorAll('.color-preset').forEach(b => {
            b.classList.remove('active');
        });
        btn.classList.add('active');
    });
});

// ====================================
// SEARCH
// ====================================

const searchInput = document.getElementById('searchInput');
if (searchInput) {
    let searchTimeout;
    searchInput.addEventListener('input', (e) => {
        clearTimeout(searchTimeout);
        searchTimeout = setTimeout(() => {
            const query = e.target.value.trim();
            if (query.length >= 2) {
                filterTasks(query);
            } else if (query.length === 0) {
                showAllTasks();
            }
        }, 300);
    });
}

function filterTasks(query) {
    const tasks = document.querySelectorAll('.task-item');
    const lowerQuery = query.toLowerCase();
    
    tasks.forEach(task => {
        const title = task.querySelector('.task-title').textContent.toLowerCase();
        const description = task.querySelector('.task-description')?.textContent.toLowerCase() || '';
        
        if (title.includes(lowerQuery) || description.includes(lowerQuery)) {
            task.style.display = '';
        } else {
            task.style.display = 'none';
        }
    });
}

function showAllTasks() {
    document.querySelectorAll('.task-item').forEach(task => {
        task.style.display = '';
    });
}

// ====================================
// QUICK ADD TASK
// ====================================

const quickAddInput = document.getElementById('quickAddInput');
if (quickAddInput) {
    quickAddInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            quickAddTask();
        }
    });
}

function quickAddTask() {
    const input = document.getElementById('quickAddInput');
    const title = input.value.trim();
    
    if (!title) return;
    
    const projectId = input.dataset.project || '';
    
    fetch('/tasks/create/', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-CSRFToken': getCSRFToken(),
            'X-Requested-With': 'XMLHttpRequest',
        },
        body: `title=${encodeURIComponent(title)}&project=${projectId}`,
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            // Reload page to show new task
            window.location.reload();
        }
    })
    .catch(error => console.error('Error:', error));
}

// ====================================
// KEYBOARD SHORTCUTS
// ====================================

document.addEventListener('keydown', (e) => {
    // N - New task
    if (e.key === 'n' && !isTyping()) {
        e.preventDefault();
        openTaskModal();
    }
    
    // P - New project
    if (e.key === 'p' && !isTyping()) {
        e.preventDefault();
        openProjectModal();
    }
    
    // / - Focus search
    if (e.key === '/' && !isTyping()) {
        e.preventDefault();
        document.getElementById('searchInput')?.focus();
    }
});

function isTyping() {
    const active = document.activeElement;
    return active.tagName === 'INPUT' || active.tagName === 'TEXTAREA' || active.isContentEditable;
}

// ====================================
// UTILITY FUNCTIONS
// ====================================

function getCSRFToken() {
    return document.querySelector('[name=csrfmiddlewaretoken]')?.value || 
           document.cookie.split('; ').find(row => row.startsWith('csrftoken='))?.split('=')[1];
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function updateTaskCounts() {
    // Could implement AJAX call to update sidebar counts
}

// ====================================
// TASK CHECKBOX EVENT DELEGATION
// ====================================

document.addEventListener('change', (e) => {
    if (e.target.matches('.task-item .task-checkbox input')) {
        const taskItem = e.target.closest('.task-item');
        const taskId = taskItem.dataset.id;
        toggleTask(taskId);
    }
});

// ====================================
// CALENDAR
// ====================================

class ScopeCalendar {
    constructor(container) {
        this.container = container;
        this.currentDate = new Date();
        this.selectedDate = null;
        this.events = [];
        
        this.init();
    }
    
    // Форматирует дату в YYYY-MM-DD без проблем с часовым поясом
    formatDateStr(year, month, day) {
        const m = String(month + 1).padStart(2, '0');
        const d = String(day).padStart(2, '0');
        return `${year}-${m}-${d}`;
    }
    
    // Получает сегодняшнюю дату в формате YYYY-MM-DD
    getTodayStr() {
        const today = new Date();
        return this.formatDateStr(today.getFullYear(), today.getMonth(), today.getDate());
    }
    
    async init() {
        await this.loadEvents();
        this.render();
    }
    
    async loadEvents() {
        const year = this.currentDate.getFullYear();
        const month = this.currentDate.getMonth();
        const start = this.formatDateStr(year, month, 1);
        const lastDay = new Date(year, month + 1, 0).getDate();
        const end = this.formatDateStr(year, month, lastDay);
        
        try {
            const response = await fetch(`/api/calendar-events/?start=${start}&end=${end}`);
            this.events = await response.json();
        } catch (error) {
            console.error('Error loading calendar events:', error);
        }
    }
    
    render() {
        const year = this.currentDate.getFullYear();
        const month = this.currentDate.getMonth();
        
        const monthNames = [
            'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
            'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
        ];
        
        const dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
        
        const firstDay = new Date(year, month, 1);
        const lastDay = new Date(year, month + 1, 0);
        
        // Get the day of week (0-6, where 0 is Sunday)
        let startDay = firstDay.getDay();
        // Convert to Monday-first (0 = Monday)
        startDay = startDay === 0 ? 6 : startDay - 1;
        
        const todayStr = this.getTodayStr();
        
        let html = `
            <div class="calendar-header">
                <h2 class="calendar-title">${monthNames[month]} ${year}</h2>
                <div class="calendar-nav">
                    <button class="btn-icon" onclick="calendar.prevMonth()">
                        <i class="ri-arrow-left-s-line"></i>
                    </button>
                    <button class="btn btn-ghost btn-sm" onclick="calendar.goToToday()">Сегодня</button>
                    <button class="btn-icon" onclick="calendar.nextMonth()">
                        <i class="ri-arrow-right-s-line"></i>
                    </button>
                </div>
            </div>
            <div class="calendar-grid">
        `;
        
        // Day headers
        dayNames.forEach(day => {
            html += `<div class="calendar-day-header">${day}</div>`;
        });
        
        // Previous month days
        const prevMonthLastDay = new Date(year, month, 0);
        for (let i = startDay - 1; i >= 0; i--) {
            const day = prevMonthLastDay.getDate() - i;
            html += `<div class="calendar-day other-month"><span class="calendar-day-number">${day}</span></div>`;
        }
        
        // Current month days
        for (let day = 1; day <= lastDay.getDate(); day++) {
            const dateStr = this.formatDateStr(year, month, day);
            const isToday = dateStr === todayStr;
            const isSelected = dateStr === this.selectedDate;
            const dayEvents = this.events.filter(e => e.start === dateStr);
            
            let dayClass = 'calendar-day';
            if (isToday) dayClass += ' today';
            if (isSelected) dayClass += ' selected';
            
            html += `
                <div class="${dayClass}" onclick="calendar.selectDate('${dateStr}')">
                    <span class="calendar-day-number">${day}</span>
                    ${dayEvents.length > 0 ? `
                        <div class="calendar-day-tasks">
                            ${dayEvents.slice(0, 3).map(e => `<span class="calendar-day-dot" style="background: ${e.color}"></span>`).join('')}
                        </div>
                    ` : ''}
                </div>
            `;
        }
        
        // Next month days
        const totalCells = startDay + lastDay.getDate();
        const rows = Math.ceil(totalCells / 7);
        const remainingCells = (rows * 7) - totalCells;
        for (let day = 1; day <= remainingCells; day++) {
            html += `<div class="calendar-day other-month"><span class="calendar-day-number">${day}</span></div>`;
        }
        
        html += '</div>';
        
        // Events list for selected date or today
        const selectedDateStr = this.selectedDate || todayStr;
        const selectedEvents = this.events.filter(e => e.start === selectedDateStr);
        
        // Показываем секцию событий даже если пусто при выбранной дате
        html += `
            <div class="calendar-events">
                <h3 class="task-section-title">Задачи на ${this.formatDisplayDate(selectedDateStr)}</h3>
                ${selectedEvents.length > 0 ? `
                    <div class="task-list">
                        ${selectedEvents.map(e => `
                            <a href="${e.url}" class="task-item ${e.completed ? 'completed' : ''}" style="border-left: 3px solid ${e.color}">
                                <div class="task-content">
                                    <span class="task-title">${e.title}</span>
                                </div>
                            </a>
                        `).join('')}
                    </div>
                ` : `
                    <p class="calendar-no-events">Нет задач на этот день</p>
                `}
            </div>
        `;
        
        this.container.innerHTML = html;
    }
    
    formatDisplayDate(dateStr) {
        // Парсим строку YYYY-MM-DD напрямую
        const [year, month, day] = dateStr.split('-').map(Number);
        const months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
                       'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
        return `${day} ${months[month - 1]}`;
    }
    
    prevMonth() {
        this.currentDate.setMonth(this.currentDate.getMonth() - 1);
        this.selectedDate = null;
        this.init();
    }
    
    nextMonth() {
        this.currentDate.setMonth(this.currentDate.getMonth() + 1);
        this.selectedDate = null;
        this.init();
    }
    
    goToToday() {
        this.currentDate = new Date();
        this.selectedDate = null;
        this.init();
    }
    
    selectDate(dateStr) {
        this.selectedDate = dateStr;
        this.render();
    }
}

// Calendar is initialized in the template that uses it
// Variable 'calendar' is set on window object in the template

// ====================================
// CSS ANIMATION HELPERS
// ====================================

// Add fadeOut animation
const style = document.createElement('style');
style.textContent = `
    @keyframes fadeOut {
        from { opacity: 1; transform: translateX(0); }
        to { opacity: 0; transform: translateX(-20px); }
    }
`;
document.head.appendChild(style);

// ====================================
// MOBILE MENU
// ====================================

function toggleSidebar() {
    document.querySelector('.sidebar').classList.toggle('open');
}

// Close sidebar when clicking outside on mobile
document.addEventListener('click', (e) => {
    const sidebar = document.querySelector('.sidebar');
    if (window.innerWidth <= 1024 && 
        sidebar.classList.contains('open') && 
        !sidebar.contains(e.target)) {
        sidebar.classList.remove('open');
    }
});

