from django.db import models
from django.contrib.auth.models import User
from django.utils import timezone


class Tag(models.Model):
    """Теги для категоризации задач"""
    name = models.CharField(max_length=50)
    color = models.CharField(max_length=7, default='#7C3AED')  # HEX цвет
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='tags', null=True, blank=True)
    
    class Meta:
        ordering = ['name']
    
    def __str__(self):
        return self.name


class Project(models.Model):
    """Проекты для группировки задач"""
    name = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    color = models.CharField(max_length=7, default='#7C3AED')
    icon = models.CharField(max_length=50, default='folder')  # Название иконки
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='projects', null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    is_archived = models.BooleanField(default=False)
    
    class Meta:
        ordering = ['-created_at']
    
    def __str__(self):
        return self.name
    
    @property
    def task_count(self):
        return self.tasks.filter(is_completed=False).count()
    
    @property
    def completed_task_count(self):
        return self.tasks.filter(is_completed=True).count()


class Task(models.Model):
    """Основная модель задач"""
    PRIORITY_CHOICES = [
        (1, 'Низкий'),
        (2, 'Средний'),
        (3, 'Высокий'),
        (4, 'Срочный'),
    ]
    
    title = models.CharField(max_length=500)
    description = models.TextField(blank=True)
    project = models.ForeignKey(Project, on_delete=models.CASCADE, related_name='tasks', null=True, blank=True)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='tasks', null=True, blank=True)
    tags = models.ManyToManyField(Tag, related_name='tasks', blank=True)
    
    priority = models.IntegerField(choices=PRIORITY_CHOICES, default=2)
    is_completed = models.BooleanField(default=False)
    completed_at = models.DateTimeField(null=True, blank=True)
    
    due_date = models.DateField(null=True, blank=True)
    due_time = models.TimeField(null=True, blank=True)
    reminder = models.DateTimeField(null=True, blank=True)
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    # Порядок сортировки внутри проекта
    order = models.IntegerField(default=0)
    
    class Meta:
        ordering = ['is_completed', '-priority', 'order', '-created_at']
    
    def __str__(self):
        return self.title
    
    def save(self, *args, **kwargs):
        if self.is_completed and not self.completed_at:
            self.completed_at = timezone.now()
        elif not self.is_completed:
            self.completed_at = None
        super().save(*args, **kwargs)
    
    @property
    def is_overdue(self):
        if self.due_date and not self.is_completed:
            return self.due_date < timezone.now().date()
        return False
    
    @property
    def checklist_progress(self):
        total = self.checklist_items.count()
        if total == 0:
            return None
        completed = self.checklist_items.filter(is_completed=True).count()
        return {'total': total, 'completed': completed, 'percent': int(completed / total * 100)}


class ChecklistItem(models.Model):
    """Элементы чек-листа внутри задачи"""
    task = models.ForeignKey(Task, on_delete=models.CASCADE, related_name='checklist_items')
    text = models.CharField(max_length=500)
    is_completed = models.BooleanField(default=False)
    order = models.IntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        ordering = ['order', 'created_at']
    
    def __str__(self):
        return self.text


class TaskNote(models.Model):
    """Заметки/комментарии к задачам"""
    task = models.ForeignKey(Task, on_delete=models.CASCADE, related_name='notes')
    content = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        ordering = ['-created_at']
    
    def __str__(self):
        return f"Заметка к {self.task.title[:30]}"


class TaskLink(models.Model):
    """Ссылки, прикреплённые к задаче"""
    task = models.ForeignKey(Task, on_delete=models.CASCADE, related_name='links')
    url = models.URLField(max_length=2000)
    title = models.CharField(max_length=200, blank=True)  # Название ссылки (опционально)
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        ordering = ['-created_at']
    
    def __str__(self):
        return self.title or self.url[:50]
    
    @property
    def display_title(self):
        """Возвращает название или домен из URL"""
        if self.title:
            return self.title
        # Извлекаем домен из URL
        from urllib.parse import urlparse
        parsed = urlparse(self.url)
        return parsed.netloc or self.url[:30]
    
    @property
    def favicon_url(self):
        """Возвращает URL фавиконки сайта"""
        from urllib.parse import urlparse
        parsed = urlparse(self.url)
        return f"https://www.google.com/s2/favicons?domain={parsed.netloc}&sz=32"


class TaskAttachment(models.Model):
    """Вложения к задаче"""
    task = models.ForeignKey(Task, on_delete=models.CASCADE, related_name='attachments')
    file = models.FileField(upload_to='attachments/%Y/%m/')
    filename = models.CharField(max_length=255)  # Оригинальное имя файла
    file_size = models.PositiveIntegerField(default=0)  # Размер в байтах
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        ordering = ['-created_at']
    
    def __str__(self):
        return self.filename
    
    @property
    def file_size_display(self):
        """Человекочитаемый размер файла"""
        size = self.file_size
        for unit in ['Б', 'КБ', 'МБ', 'ГБ']:
            if size < 1024:
                return f"{size:.1f} {unit}" if unit != 'Б' else f"{size} {unit}"
            size /= 1024
        return f"{size:.1f} ТБ"
    
    @property
    def file_icon(self):
        """Иконка в зависимости от типа файла"""
        ext = self.filename.split('.')[-1].lower() if '.' in self.filename else ''
        icons = {
            'pdf': 'ri-file-pdf-line',
            'doc': 'ri-file-word-line',
            'docx': 'ri-file-word-line',
            'xls': 'ri-file-excel-line',
            'xlsx': 'ri-file-excel-line',
            'ppt': 'ri-file-ppt-line',
            'pptx': 'ri-file-ppt-line',
            'zip': 'ri-file-zip-line',
            'rar': 'ri-file-zip-line',
            '7z': 'ri-file-zip-line',
            'jpg': 'ri-image-line',
            'jpeg': 'ri-image-line',
            'png': 'ri-image-line',
            'gif': 'ri-image-line',
            'webp': 'ri-image-line',
            'svg': 'ri-image-line',
            'mp3': 'ri-music-line',
            'wav': 'ri-music-line',
            'mp4': 'ri-video-line',
            'avi': 'ri-video-line',
            'mov': 'ri-video-line',
            'txt': 'ri-file-text-line',
            'md': 'ri-markdown-line',
            'py': 'ri-code-line',
            'js': 'ri-code-line',
            'html': 'ri-code-line',
            'css': 'ri-code-line',
            'json': 'ri-code-line',
        }
        return icons.get(ext, 'ri-file-line')
