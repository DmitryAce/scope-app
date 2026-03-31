from django.contrib import admin
from .models import (
    Task,
    Project,
    Tag,
    ChecklistItem,
    TaskNote,
    TaskLink,
    TaskAttachment,
    BudgetMonthlyItem,
    ExpenseEntry,
    DailyBudgetPeriod,
    ApiAccessToken,
)


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


@admin.register(ApiAccessToken)
class ApiAccessTokenAdmin(admin.ModelAdmin):
    list_display = ['key_prefix', 'user', 'name', 'created_at', 'last_used_at', 'is_active']
    list_filter = ['is_active', 'created_at']
    search_fields = ['user__username', 'name', 'key_prefix']
    readonly_fields = ['key_prefix', 'key_hash', 'created_at', 'last_used_at']
    ordering = ['-created_at']

    def has_add_permission(self, request):
        return False


@admin.register(BudgetMonthlyItem)
class BudgetMonthlyItemAdmin(admin.ModelAdmin):
    list_display = ['title', 'user', 'year', 'month', 'amount_planned', 'amount_set_aside', 'is_paid']
    list_filter = ['year', 'month', 'is_paid']
    search_fields = ['title', 'notes']


@admin.register(ExpenseEntry)
class ExpenseEntryAdmin(admin.ModelAdmin):
    list_display = ['date', 'amount', 'note', 'category', 'daily_budget_period', 'user']
    list_filter = ['date', 'category', 'daily_budget_period']
    date_hierarchy = 'date'


@admin.register(DailyBudgetPeriod)
class DailyBudgetPeriodAdmin(admin.ModelAdmin):
    list_display = ['title', 'user', 'start_date', 'end_date', 'daily_allowance']
    list_filter = ['start_date']
    date_hierarchy = 'start_date'
