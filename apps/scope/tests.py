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

    def test_subprojects_are_one_level_deep(self):
        root = self._post('/api/v2/projects/', {'name': 'Webstead'}).json()['data']
        child = self._post('/api/v2/projects/', {'name': 'Клиент', 'parent_id': root['id']}).json()['data']
        self.assertEqual(child['parent_id'], root['id'])

        deeper = self._post('/api/v2/projects/', {'name': 'Глубже', 'parent_id': child['id']})
        self.assertEqual(deeper.status_code, 400)
        self.assertEqual(self._patch(f"/api/v2/projects/{root['id']}/", {'parent_id': child['id']}).status_code, 400)
        self.assertEqual(self._patch(f"/api/v2/projects/{root['id']}/", {'parent_id': root['id']}).status_code, 400)
        self.assertIsNone(self._patch(f"/api/v2/projects/{child['id']}/", {'parent_id': None}).json()['data']['parent_id'])

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
