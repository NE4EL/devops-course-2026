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

printf '[5] Контейнеризация\n'
check 'Служба Docker активна' systemctl is-active --quiet docker
check 'PostgreSQL healthy' db_healthy
check 'Порты 5000 и 5432 не опубликованы вовне' ports_local_only
check 'Права ~/app/.env равны 600' env_permissions

if [ "$failures" -eq 0 ]; then
    exit 0
fi
exit 1
