#!/usr/bin/env bash
set -euo pipefail

cd /app

if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
    else
        touch .env
    fi
fi

if [ -z "${APP_KEY:-}" ] && ! grep -q '^APP_KEY=.\+' .env; then
    php artisan key:generate --force
fi

if [ "${DB_CONNECTION:-}" = "mysql" ] && [ -n "${DB_HOST:-}" ]; then
    echo "Waiting for MySQL at ${DB_HOST}:${DB_PORT:-3306}..."
    for i in $(seq 1 60); do
        if mysqladmin ping -h "${DB_HOST}" -P "${DB_PORT:-3306}" -u "${DB_USERNAME:-root}" -p"${DB_PASSWORD:-}" --silent >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
fi

if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
    php artisan migrate --force --no-interaction || true
fi

if [ "${APP_ENV:-production}" = "production" ]; then
    php artisan config:cache
    php artisan route:cache
    php artisan event:cache
else
    php artisan config:clear
    php artisan route:clear
fi

php artisan storage:link --force 2>/dev/null || true

exec "$@"
