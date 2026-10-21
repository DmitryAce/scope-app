import json

from django.contrib.auth.models import User
from django.test import TestCase


class ApiLoginTests(TestCase):
    def setUp(self):
        User.objects.create_user('alice', password='secret-pass')

    def _login(self, password):
        return self.client.post(
            '/api/v2/auth/login/',
            json.dumps({'username': 'alice', 'password': password, 'device': 'test'}),
            content_type='application/json',
        )

    def test_login_issues_working_token_and_logout_revokes_it(self):
        res = self._login('secret-pass')
        self.assertEqual(res.status_code, 201)
        token = res.json()['data']['token']
        auth = {'HTTP_AUTHORIZATION': f'Bearer {token}'}

        self.assertEqual(self.client.get('/api/v2/me/', **auth).json()['data']['username'], 'alice')
        self.assertEqual(self.client.post('/api/v2/housekeeping/', **auth).status_code, 200)
        self.assertEqual(self.client.post('/api/v2/auth/logout/', **auth).status_code, 200)
        self.assertEqual(self.client.get('/api/v2/me/', **auth).status_code, 401)

    def test_wrong_password_is_rejected_then_throttled(self):
        for _ in range(8):
            self.assertEqual(self._login('nope').status_code, 401)
        self.assertEqual(self._login('secret-pass').status_code, 429)


class ProjectTreeAndAvatarTests(TestCase):
    def setUp(self):
        import tempfile

        from django.test import override_settings

        from apps.scope.models import ApiAccessToken

        self._media = override_settings(MEDIA_ROOT=tempfile.mkdtemp())
        self._media.enable()
        user = User.objects.create_user('bob', password='x')
        raw, _ = ApiAccessToken.issue(user)
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {raw}'}

    def tearDown(self):
        self._media.disable()

    def _post(self, url, body):
        return self.client.post(url, json.dumps(body), content_type='application/json', **self.auth)

    def _patch(self, url, body):
        return self.client.patch(url, json.dumps(body), content_type='application/json', **self.auth)

    def test_nesting_up_to_four_levels_without_cycles(self):
        ids = []
        parent = None
        for name in ['Webstead', 'Клиент', 'Сайт', 'Блог']:
            body = {'name': name, 'parent_id': parent}
            parent = self._post('/api/v2/projects/', body).json()['data']['id']
            ids.append(parent)
        # Пятый уровень — нельзя.
        self.assertEqual(self._post('/api/v2/projects/', {'name': 'Пост', 'parent_id': ids[-1]}).status_code, 400)
        # Цикл: корень внутрь своего потомка.
        self.assertEqual(self._patch(f'/api/v2/projects/{ids[0]}/', {'parent_id': ids[2]}).status_code, 400)
        self.assertEqual(self._patch(f'/api/v2/projects/{ids[0]}/', {'parent_id': ids[0]}).status_code, 400)
        # Ветку вместе с её подпроектом можно перевесить под другой корень.
        other = self._post('/api/v2/projects/', {'name': 'Другое'}).json()['data']['id']
        self.assertEqual(self._patch(f'/api/v2/projects/{ids[2]}/', {'parent_id': other}).status_code, 200)
        self.assertIsNone(self._patch(f'/api/v2/projects/{ids[1]}/', {'parent_id': None}).json()['data']['parent_id'])

    def test_avatar_upload_and_remove(self):
        from django.core.files.uploadedfile import SimpleUploadedFile

        p = self._post('/api/v2/projects/', {'name': 'Ava'}).json()['data']
        url = f"/api/v2/projects/{p['id']}/avatar/"

        bad = SimpleUploadedFile('a.txt', b'hello', content_type='text/plain')
        self.assertEqual(self.client.post(url, {'file': bad}, **self.auth).status_code, 400)

        img = SimpleUploadedFile('a.png', b'\x89PNG fake', content_type='image/png')
        data = self.client.post(url, {'file': img}, **self.auth).json()['data']
        self.assertTrue(data['avatar'].startswith('/media/project_avatars/'))

        self.assertIsNone(self.client.delete(url, **self.auth).json()['data']['avatar'])


class ChecklistApiTests(TestCase):
    def setUp(self):
        from apps.scope.models import ApiAccessToken

        user = User.objects.create_user('carol', password='x')
        raw, _ = ApiAccessToken.issue(user)
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {raw}'}

    def _req(self, method, url, body=None):
        return getattr(self.client, method)(url, json.dumps(body or {}), content_type='application/json', **self.auth)

    def test_add_toggle_delete_items(self):
        task = self._req('post', '/api/v2/tasks/', {'title': 'Сборы'}).json()['data']
        self.assertEqual(task['checklist'], [])

        task = self._req('post', f"/api/v2/tasks/{task['id']}/checklist/", {'text': 'Паспорт'}).json()['data']
        task = self._req('post', f"/api/v2/tasks/{task['id']}/checklist/", {'text': 'Зарядка'}).json()['data']
        self.assertEqual([c['text'] for c in task['checklist']], ['Паспорт', 'Зарядка'])

        first = task['checklist'][0]['id']
        task = self._req('patch', f'/api/v2/checklist/{first}/', {'is_completed': True}).json()['data']
        self.assertTrue(task['checklist'][0]['is_completed'])

        task = self._req('delete', f'/api/v2/checklist/{first}/').json()['data']
        self.assertEqual([c['text'] for c in task['checklist']], ['Зарядка'])
        listed = self.client.get('/api/v2/tasks/', **self.auth).json()['data'][0]
        self.assertEqual(len(listed['checklist']), 1)


class OrderingTagsAutoDeleteTests(TestCase):
    def setUp(self):
        from apps.scope.models import ApiAccessToken

        self.user = User.objects.create_user('dave', password='x')
        raw, _ = ApiAccessToken.issue(self.user)
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {raw}'}

    def _req(self, method, url, body=None):
        return getattr(self.client, method)(url, json.dumps(body or {}), content_type='application/json', **self.auth)

    def test_reorder_and_pin(self):
        a, b, c = (self._req('post', '/api/v2/projects/', {'name': n}).json()['data']['id'] for n in 'abc')
        self.assertEqual(self._req('post', '/api/v2/projects/reorder/', {'ids': [b, c, a]}).status_code, 200)
        names = [p['name'] for p in self.client.get('/api/v2/projects/', **self.auth).json()['data']]
        self.assertEqual(names, ['b', 'c', 'a'])
        self._req('patch', f'/api/v2/projects/{a}/', {'is_pinned': True})
        names = [p['name'] for p in self.client.get('/api/v2/projects/', **self.auth).json()['data']]
        self.assertEqual(names, ['a', 'b', 'c'])

    def test_tag_edit_and_delete(self):
        tag = self._req('post', '/api/v2/tags/', {'name': 'x'}).json()['data']
        self.assertEqual(self._req('patch', f"/api/v2/tags/{tag['id']}/", {'name': 'дом', 'color': '#22C55E'}).json()['data']['name'], 'дом')
        self.assertEqual(self._req('delete', f"/api/v2/tags/{tag['id']}/").status_code, 200)
        self.assertEqual(self.client.get('/api/v2/tags/', **self.auth).json()['data'], [])

    def test_auto_delete_removes_past_tasks(self):
        from datetime import date, timedelta

        from apps.scope.models import Task

        yesterday = (date.today() - timedelta(days=1)).isoformat()
        self._req('post', '/api/v2/tasks/', {'title': 'одноразовая', 'due_date': yesterday, 'auto_delete': True})
        self._req('post', '/api/v2/tasks/', {'title': 'обычная', 'due_date': yesterday})
        self._req('post', '/api/v2/housekeeping/')
        self.assertEqual(list(Task.objects.filter(user=self.user).values_list('title', flat=True)), ['обычная'])


class AppReleaseTests(TestCase):
    def test_publish_and_fetch_latest(self):
        import tempfile
        from pathlib import Path

        from django.core.management import call_command
        from django.test import override_settings

        from apps.scope.models import ApiAccessToken

        user = User.objects.create_user('erin', password='x')
        raw, _ = ApiAccessToken.issue(user)
        auth = {'HTTP_AUTHORIZATION': f'Bearer {raw}'}
        with tempfile.TemporaryDirectory() as media, override_settings(MEDIA_ROOT=media):
            self.assertIsNone(self.client.get('/api/v2/app/latest/?platform=android', **auth).json()['data'])
            apk = Path(media) / 'build.apk'
            apk.write_bytes(b'apk')
            call_command('scope_publish_app', 'android', '1.4.0', '5', str(apk), notes='Подпроекты')
            data = self.client.get('/api/v2/app/latest/?platform=android', **auth).json()['data']
            self.assertEqual((data['version'], data['build'], data['notes']), ('1.4.0', 5, 'Подпроекты'))
            self.assertTrue(data['url'].endswith('/app_releases/Scope-1.4.0-android.apk'))
            self.assertEqual(self.client.get('/api/v2/app/latest/?platform=ios', **auth).status_code, 400)


class ErpSyncTests(TestCase):
    """Подключения ERP: у каждого пользователя свои, только чтение, закрытие в Scope — локальное."""

    def setUp(self):
        from apps.scope.models import ErpConnection

        self.user = User.objects.create_user('xeno', password='x')
        self.conn = ErpConnection(user=self.user, source='webstead', name='Webstead',
                                  base_url='https://erp.example', color='#B3365B')
        self.conn.token = 'tok-xeno'
        self.conn.save()
        self.erp = [self._item(109, 'Чистка ERP', '2026-11-05'), self._item(423, 'Контроль оплаты', None, 'urgent')]

    @staticmethod
    def _item(i, title, deadline, priority='normal'):
        return {
            'id': i, 'code': f'ERP ДТ-{i}', 'title': title, 'description': 'описание', 'deadline': deadline,
            'url': f'https://erp.example/t/{i}', 'priority': {'code': priority},
            'status': {'label': 'В работе'}, 'project': {'id': 1, 'name': 'ERP Дверной Тон'},
        }

    def _opener(self, url, token):
        assert token == 'tok-xeno', 'в ERP должен уходить токен владельца подключения'
        return {'tasks': self.erp, 'has_more': False}

    def _sync(self):
        from apps.scope.erp_sync import sync_connection

        return sync_connection(self.conn, opener=self._opener)

    def test_token_is_encrypted_at_rest(self):
        from apps.scope.models import ErpConnection

        raw = ErpConnection.objects.values_list('token_encrypted', flat=True).get()
        self.assertNotIn('tok-xeno', raw)
        self.assertEqual(ErpConnection.objects.get().token, 'tok-xeno')

    def test_import_update_and_local_close(self):
        from datetime import date

        from apps.scope.models import Task

        self.assertEqual(self._sync()['created'], 2)
        t = Task.objects.get(external_id='109')
        self.assertEqual((t.title, t.external_code, t.due_date), ('Чистка ERP', 'ERP ДТ-109', date(2026, 11, 5)))
        self.assertEqual((t.project.name, t.project.parent.name), ('ERP Дверной Тон', 'ERP · Webstead'))
        self.assertEqual(Task.objects.get(external_id='423').priority, 4)

        # Свой перенос и своё закрытие не затираются, пока в ERP не менялся срок.
        Task.objects.filter(pk=t.pk).update(due_date=date(2026, 11, 1), is_completed=True)
        self.erp[0]['title'] = 'Чистка ERP v2'
        self.assertEqual(self._sync()['created'], 0)
        t.refresh_from_db()
        self.assertEqual((t.title, t.due_date, t.is_completed), ('Чистка ERP v2', date(2026, 11, 1), True))

        # Срок сдвинули в ERP — он приезжает.
        self.erp[0]['deadline'] = '2026-12-01'
        self._sync()
        t.refresh_from_db()
        self.assertEqual(t.due_date, date(2026, 12, 1))

        # Задачу закрыли в ERP (пропала из открытых) — закрывается и в Scope.
        self.erp.pop(1)
        self.assertEqual(self._sync()['closed'], 1)
        self.assertTrue(Task.objects.get(external_id='423').is_completed)

    def test_network_error_changes_nothing(self):
        from apps.scope.erp_sync import ErpError, sync_connection
        from apps.scope.models import Task

        self._sync()

        def broken(url, token):
            raise ErpError('ERP недоступна')

        self.assertIn('error', sync_connection(self.conn, opener=broken))
        self.assertFalse(Task.objects.filter(is_completed=True).exists())
        self.conn.refresh_from_db()
        self.assertEqual(self.conn.last_error, 'ERP недоступна')

    def test_users_are_isolated(self):
        from apps.scope.erp_sync import sync_connection
        from apps.scope.models import ErpConnection, Task

        other = User.objects.create_user('anna', password='x')
        conn = ErpConnection(user=other, source='webstead', name='Webstead', base_url='https://erp.example')
        conn.token = 'tok-anna'
        conn.save()
        self._sync()
        sync_connection(conn, opener=lambda url, token: {'tasks': [self._item(7, 'Задача Анны', None)], 'has_more': False})
        self.assertEqual(sorted(Task.objects.filter(user=self.user).values_list('external_id', flat=True)), ['109', '423'])
        self.assertEqual(list(Task.objects.filter(user=other).values_list('external_id', flat=True)), ['7'])

    def test_connect_checks_token_and_host(self):
        from apps.scope.erp_sync import ErpError, check_public_https, connect

        for bad in ['http://erp.webstead.ru', 'https://127.0.0.1', 'https://192.168.1.93:1230', 'https://localhost']:
            with self.assertRaises(ErpError):
                check_public_https(bad)

        def reject(url, token):
            raise ErpError('ERP не приняла токен')

        with self.assertRaises(ErpError):
            connect(self.user, token='bad', preset='omniwebers', opener=reject, check_host=False)
        conn = connect(self.user, token='good', preset='omniwebers', check_host=False,
                       opener=lambda url, token: {'tasks': [], 'has_more': False})
        self.assertEqual((conn.source, conn.name, conn.token), ('omniwebers', 'OmniWebers', 'good'))
        custom = connect(self.user, token='t', base_url='https://erp.acme.example', name='Acme', check_host=False,
                         opener=lambda url, token: {'tasks': [], 'has_more': False})
        self.assertEqual(custom.source, f'erp-{custom.pk}')

    def test_disconnect_close_or_delete(self):
        from apps.scope.erp_sync import disconnect
        from apps.scope.models import ErpConnection, Project, Task

        self._sync()
        disconnect(self.conn)
        self.assertEqual(Task.objects.filter(is_completed=False).count(), 0)
        self.assertFalse(ErpConnection.objects.exists())

        self.conn.pk = None
        self.conn.save()
        disconnect(self.conn, delete_tasks=True)
        self.assertFalse(Task.objects.filter(external_source='webstead').exists())
        self.assertFalse(Project.objects.filter(external_source='webstead').exists())

    def test_api_never_returns_token(self):
        from apps.scope.models import ApiAccessToken

        raw, _ = ApiAccessToken.issue(self.user)
        body = self.client.get('/api/v2/erp/connections/', HTTP_AUTHORIZATION=f'Bearer {raw}').content.decode()
        self.assertIn('Webstead', body)
        self.assertNotIn('tok-xeno', body)
        self.assertNotIn('token', json.loads(body)['data']['connections'][0])
