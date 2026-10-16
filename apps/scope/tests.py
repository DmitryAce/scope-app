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
