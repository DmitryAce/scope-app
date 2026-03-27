from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('scope', '0005_remove_budgetmonthlyitem_status'),
    ]

    operations = [
        migrations.AddField(
            model_name='budgetmonthlyitem',
            name='is_paid',
            field=models.BooleanField(default=False, help_text='Отметка «уже оплатил»'),
        ),
    ]
