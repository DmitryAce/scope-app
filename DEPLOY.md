# 🚀 Scope - Deployment Guide

## General Deployment Instructions

This guide will help you deploy the application using Docker Compose. By default, SSL termination and proxying should be handled by your upstream proxy or router. The internal stack runs with HTTP.

### 1. Create and Configure the .env File
```bash
cp env.example .env
nano .env
```

Change the following variables in `.env` accordingly:
- `SECRET_KEY` - a long, random string for Django
- `POSTGRES_PASSWORD` - your database password
- `ADMIN_PASSWORD` - password for the admin user
- `APP_PORT` - port the application stack should listen on (default: 8080, but can be customized)

### 2. Start the Stack
```bash
docker-compose up -d
```

### 3. Configure Your Reverse Proxy or Router
Forward your domain and chosen port (`APP_PORT`) to the server running this stack. If using a router or external reverse proxy, set:
- **Domain**: (your chosen domain, e.g., myapp.example.com)
- **Destination Port**: 8080 (or the port set in `APP_PORT`)
- **Protocol**: HTTP (let the proxy handle SSL/TLS)

### 4. You're Ready! 🎉
- Access your app: `http://<your-domain>` (or through your proxy, possibly with HTTPS)
- Login: admin / (password set in `.env`)

---

## Useful Commands

```bash
# Start the stack
docker-compose up -d

# Stop the stack  
docker-compose down

# View logs
docker-compose logs -f

# Rebuild after code or configuration changes
docker-compose up -d --build

# Create a superuser
docker-compose exec web python manage.py createsuperuser

# Backup the database
docker-compose exec db pg_dump -U scope scope > backup.sql

# Restore the database
cat backup.sql | docker-compose exec -T db psql -U scope scope
```

---

## Directory Structure

```
scope-app/
├── docker-compose.yml    # PostgreSQL + Django + Nginx
├── Dockerfile            # Django image definition
├── .env                  # Configuration file
├── nginx/
│   └── nginx.conf        # Reverse proxy and static serving
└── docker/
    └── entrypoint.sh     # Entrypoint script
```

---

## Troubleshooting

### "Bad Gateway" or 502 Errors
```bash
docker-compose logs web    # check Django logs
docker-compose restart     # restart service
```

### Static Files Not Loading (CSS/JS)
```bash
docker-compose exec web python manage.py collectstatic --noinput
docker-compose restart nginx
```

### Reset Database
```bash
docker-compose down -v    # WARNING: This will remove all data!
docker-compose up -d
```

---

## Updating the Stack

```bash
git pull
docker-compose up -d --build
```
