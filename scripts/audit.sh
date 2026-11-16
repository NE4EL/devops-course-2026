#!/usr/bin/env bash
set -uo pipefail

failures=0

check() {
    local description=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf 'PASS %s\n' "$description"
    else
        printf 'FAIL %s\n' "$description"
        failures=$((failures + 1))
    fi
}

db_healthy() {
    [ "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null)" = healthy ]
}

ports_local_only() {
    ss -H -tln | awk '
        $4 ~ /:(5000|5432)$/ && $4 !~ /^127[.]0[.]0[.]1:(5000|5432)$/ { bad = 1 }
        END { exit bad }
    '
}

env_permissions() {
    [ "$(stat -c '%a' "$HOME/app/.env" 2>/dev/null)" = 600 ]
}

kr2_redis_healthy() {
    local container_id
    container_id=$(docker compose --project-directory "$HOME/kr2" ps -q redis) || return 1
    [ -n "$container_id" ] || return 1
    [ "$(docker inspect -f '{{.State.Health.Status}}' "$container_id" 2>/dev/null)" = healthy ]
}

kr2_port_local_only() {
    [ "$(docker compose --project-directory "$HOME/kr2" port app 8001 2>/dev/null)" = '127.0.0.1:8001' ]
}

kr2_env_permissions() {
    [ "$(stat -c '%a' "$HOME/kr2/.env" 2>/dev/null)" = 600 ]
}

kr2_certificate_valid() {
    openssl x509 -in /etc/ssl/certs/kr2.crt -noout -checkend 2592000
}

kr2_site_enabled() {
    [ -L /etc/nginx/sites-enabled/kr2 ] &&
        [ "$(readlink -f /etc/nginx/sites-enabled/kr2)" = /etc/nginx/sites-available/kr2 ]
}

printf '[5] Контейнеризация\n'
check 'Служба Docker активна' systemctl is-active --quiet docker
check 'PostgreSQL healthy' db_healthy
check 'Порты 5000 и 5432 не опубликованы вовне' ports_local_only
check 'Права ~/app/.env равны 600' env_permissions

printf '[6] Контрольная работа № 2\n'
check 'Redis healthy' kr2_redis_healthy
check 'Порт 8001 опубликован только на 127.0.0.1' kr2_port_local_only
check 'Права ~/kr2/.env равны 600' kr2_env_permissions
check 'Сертификат kr2 действителен ещё 30 дней' kr2_certificate_valid
check 'Сайт kr2 активирован в Nginx' kr2_site_enabled

if [ "$failures" -eq 0 ]; then
    exit 0
fi
exit 1
