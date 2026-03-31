from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('scope', '0006_budgetmonthlyitem_is_paid'),
    ]

    operations = [
        migrations.CreateModel(
            name='ApiAccessToken',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(blank=True, help_text='Подпись: MCP, скрипт, …', max_length=100)),
                ('key_prefix', models.CharField(help_text='Первые символы для отображения', max_length=16)),
                ('key_hash', models.CharField(db_index=True, max_length=64, unique=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('last_used_at', models.DateTimeField(blank=True, null=True)),
                ('is_active', models.BooleanField(default=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='api_tokens', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'ordering': ['-created_at'],
            },
        ),
        migrations.AddIndex(
            model_name='apiaccesstoken',
            index=models.Index(fields=['user', 'is_active'], name='scope_apiac_user_id_7e8b2f_idx'),
        ),
    ]
