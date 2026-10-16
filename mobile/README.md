# Scope для Android

Flutter-клиент к API v2. Дома по Wi-Fi ходит напрямую на `https://192.168.1.93:1230`
(самоподписанный сертификат принимается только для этого хоста), иначе — на
`https://scope.drxeno.netcraze.pro`. Режим и адреса меняются в «Ещё → Сервер».

Вход — логином и паролем веб-версии (`POST /api/v2/auth/login/` выдаёт токен).

```bash
flutter build apk --release
```

Готовый файл: `build/app/outputs/flutter-apk/app-release.apk`.
Для теста с локальным Django: `--dart-define=SCOPE_LOCAL=http://10.0.2.2:8000`.
