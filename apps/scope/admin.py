from django.contrib import admin
from .models import Task, Project, Tag, ChecklistItem, TaskNote, TaskLink, TaskAttachment


class ChecklistItemInline(admin.TabularInline):
    model = ChecklistItem
    extra = 0


class TaskNoteInline(admin.TabularInline):
    model = TaskNote
    extra = 0


class TaskLinkInline(admin.TabularInline):
    model = TaskLink
    extra = 0


class TaskAttachmentInline(admin.TabularInline):
    model = TaskAttachment
    extra = 0


@admin.register(Task)
class TaskAdmin(admin.ModelAdmin):
    list_display = ['title', 'project', 'priority', 'is_completed', 'due_date', 'created_at']
    list_filter = ['is_completed', 'priority', 'project', 'created_at']
    search_fields = ['title', 'description']
    filter_horizontal = ['tags']
    inlines = [ChecklistItemInline, TaskNoteInline, TaskLinkInline, TaskAttachmentInline]
    date_hierarchy = 'created_at'
    ordering = ['-created_at']


@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    list_display = ['name', 'task_count', 'is_archived', 'created_at']
    list_filter = ['is_archived', 'created_at']
    search_fields = ['name', 'description']


@admin.register(Tag)
class TagAdmin(admin.ModelAdmin):
    list_display = ['name', 'color']
    search_fields = ['name']


@admin.register(ChecklistItem)
class ChecklistItemAdmin(admin.ModelAdmin):
    list_display = ['text', 'task', 'is_completed']
    list_filter = ['is_completed']


@admin.register(TaskNote)
class TaskNoteAdmin(admin.ModelAdmin):
    list_display = ['task', 'created_at']
    list_filter = ['created_at']
