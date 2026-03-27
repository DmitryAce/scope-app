from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('scope', '0004_daily_budget_period'),
    ]

    operations = [
        migrations.RemoveField(
            model_name='budgetmonthlyitem',
            name='status',
        ),
    ]
