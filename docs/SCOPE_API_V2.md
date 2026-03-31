# Scope API v2 — reference (headless / MCP)

Short spec for LLMs implementing clients or MCP servers. **Single JSON API** under `/api/v2/`. **No browser session** — only token auth. **No CSRF** for these routes.

---

## Base URL

```
{ORIGIN}/api/v2/
```

Example: `https://your-host.example/api/v2/` or `http://127.0.0.1:8000/api/v2/`

`ORIGIN` = scheme + host (+ port if not 80/443). MCP config should expose this as one variable (e.g. `SCOPE_API_BASE`).

---

## Authentication

Send **exactly one** of:

| Header | Value |
|--------|--------|
| `Authorization` | `Bearer <token>` |
| `X-API-Key` | `<token>` |

Token format (plaintext, shown once at creation): `scope_` + random string.

**Obtaining a token (server / CLI):**

```bash
python manage.py scope_create_api_token <django_username> --name=mcp
```

Store the printed token securely. DB keeps only SHA-256 hash. Revoke in Django admin (`ApiAccessToken`, set `is_active=false`).

**Requirements for clients**

- `GET`/`DELETE`: no body.
- `POST`/`PATCH`: `Content-Type: application/json`, UTF-8 body.
- Use HTTPS in production.

---

## Response shape

**Success:** JSON object with top-level `data` (object or array). Lists may include `meta`:

```json
{ "data": [ ... ], "meta": { "count": 0, "limit": 100, "offset": 0 } }
```

**Created:** `201` for `POST` creates.

**Error:** HTTP 4xx/5xx + JSON:

```json
{ "error": { "code": "unauthorized|bad_json|validation_error|not_found", "message": "..." } }
```

Optional: `error.details` (object).

---

## Endpoints

All paths are relative to `{ORIGIN}/api/v2`.

### `GET /`

Handshake / discovery.

**Response `data`:**

```json
{
  "api": "scope",
  "version": 2,
  "auth": ["Authorization: Bearer <token>", "X-API-Key: <token>"]
}
```

---

### `GET /me/`

Current user (from token).

**Response `data`:**

| Field | Type |
|-------|------|
| `id` | int |
| `username` | string |
| `email` | string |
| `is_staff` | bool |

---

### Projects

#### `GET /projects/`

**Query:**

| Param | Meaning |
|-------|---------|
| `archived` | `true` / `1` / `yes` → only archived; default → not archived |

**Response:** `data`: array of **project** objects; `meta.count`.

#### `POST /projects/`

**Body (JSON):**

| Field | Required | Default |
|-------|----------|---------|
| `name` | yes | — |
| `description` | no | `""` |
| `color` | no | `#7C3AED` |
| `icon` | no | `folder` |

**Response:** `201`, `data`: one project.

#### `GET /projects/{id}/`

**Response:** `data`: project.

#### `PATCH /projects/{id}/`

Partial update. Any subset of: `name`, `description`, `color`, `icon`, `is_archived` (bool).

#### `DELETE /projects/{id}/`

**Response:** `data`: `{ "deleted": true }`

---

### Tags

#### `GET /tags/`

**Response:** `data`: array of **tag** objects; `meta.count`.

#### `POST /tags/`

**Body:**

| Field | Required |
|-------|----------|
| `name` | yes |
| `color` | no (default `#7C3AED`) |

**Response:** `201`, `data`: tag.

---

### Tasks

#### `GET /tasks/`

**Query:**

| Param | Meaning |
|-------|---------|
| `project` | project id (int) |
| `completed` | `true` / `false` / `1` / `yes` — filter by completion |
| `due_before` | `YYYY-MM-DD` — `due_date <=` |
| `due_after` | `YYYY-MM-DD` — `due_date >=` |
| `limit` | default `100`, max `500` |
| `offset` | default `0` |

**Response:** `data`: task array; `meta`: `{ count, limit, offset }`.

#### `POST /tasks/`

**Body:**

| Field | Required | Notes |
|-------|----------|--------|
| `title` | yes | max 500 chars |
| `description` | no | |
| `project_id` | no | must belong to same user |
| `priority` | no | `1`–`4` (default `2`). `1` low … `4` urgent |
| `due_date` | no | `YYYY-MM-DD` |
| `due_time` | no | `HH:MM` or `HH:MM:SS` |
| `tag_ids` or `tags` | no | array of int tag ids (same user) |

**Response:** `201`, `data`: task.

#### `GET /tasks/{id}/`

**Response:** `data`: task.

#### `PATCH /tasks/{id}/`

Partial update. Supported keys:

- `title`, `description`, `priority` (1–4), `is_completed` (bool)
- `project_id`: number or `null`
- `due_date`: `YYYY-MM-DD` or empty string / logic for clearing (see server: empty clears)
- `due_time`: string or clear
- `tag_ids` or `tags`: array of ids, or clear tags per server rules

**Note:** `completed_at` is derived in the model when toggling completion via `save()`.

#### `DELETE /tasks/{id}/`

**Response:** `data`: `{ "deleted": true }`

#### `POST /tasks/{id}/toggle/`

Toggles `is_completed` (no body).

**Response:** `data`: `{ "id": <int>, "is_completed": <bool> }`

---

## Entity JSON shapes (as returned in `data`)

### Project

```json
{
  "id": 1,
  "name": "string",
  "description": "string",
  "color": "#RRGGBB",
  "icon": "string",
  "is_archived": false,
  "created_at": "ISO-8601 datetime or null",
  "updated_at": "ISO-8601 datetime or null"
}
```

### Tag

```json
{
  "id": 1,
  "name": "string",
  "color": "#RRGGBB"
}
```

### Task

```json
{
  "id": 1,
  "title": "string",
  "description": "string",
  "priority": 2,
  "priority_label": "string (localized display)",
  "is_completed": false,
  "completed_at": "ISO-8601 or null",
  "due_date": "YYYY-MM-DD or null",
  "due_time": "HH:MM or null",
  "reminder": "ISO-8601 or null",
  "project_id": null,
  "order": 0,
  "is_overdue": false,
  "tag_ids": [1, 2],
  "created_at": "ISO-8601 or null",
  "updated_at": "ISO-8601 or null"
}
```

---

## MCP implementation hints

1. **Config:** `SCOPE_API_BASE` = origin + `/api/v2` (no trailing slash required if client normalizes paths), `SCOPE_API_TOKEN` = full `scope_…` string.
2. **Default headers:** `Authorization: Bearer ${SCOPE_API_TOKEN}` (or `X-API-Key`).
3. **Health:** `GET /api/v2/` then optionally `GET /api/v2/me/`.
4. **Idempotency:** not built-in; retries may duplicate creates — use client-side dedup if needed.
5. **Rate limits:** none in app; add reverse-proxy limits if exposing publicly.

---

## Minimal `curl` examples

```bash
export ORIGIN=http://127.0.0.1:8000
export TOKEN='scope_xxxxxxxx'

curl -sS -H "Authorization: Bearer $TOKEN" "$ORIGIN/api/v2/me/"

curl -sS -H "Authorization: Bearer $TOKEN" "$ORIGIN/api/v2/tasks/?limit=10"

curl -sS -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"From API","priority":2}' "$ORIGIN/api/v2/tasks/"
```

---

## Error reference

| HTTP | Typical `error.code` |
|------|----------------------|
| 401 | `unauthorized` — missing/invalid token |
| 400 | `bad_json`, `validation_error` |
| 404 | `not_found` — wrong id or not owned by user |

---

*Generated for Scope app `apps/scope/api_v2`. Implementation: `apps/scope/api_v2/views.py`, `auth.py`, `serializers.py`.*
