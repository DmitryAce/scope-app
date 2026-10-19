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
