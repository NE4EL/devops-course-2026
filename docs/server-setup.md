# Настройка сервера

## 9. Контейнеризация

На Ubuntu Server 24.04 установлен Docker Engine 29.9.3 (`docker-ce` из официального репозитория `https://download.docker.com/linux/ubuntu`, канал `noble/stable`) и Docker Compose 5.7.1. Проверка: `docker version`, `docker compose version`. Служба Docker должна быть активна: `systemctl is-active docker`. В группе `docker` состоит пользователь `devops` (`getent group docker`); членство в этой группе предоставляет фактически привилегии root, поэтому его следует выдавать только доверенным пользователям с правом sudo.

Код хранится в репозитории `devops-course-2026` на хостовой системе, ветка `feature/docker`, каталог `app/`. На VM проект размещён в `/home/devops/app`. Доставка из корня репозитория:

```sh
rsync -avz --delete --exclude=.env --exclude=venv/ app/ devops-vm:app/
```

Файл `/home/devops/app/.env` создаётся только на VM из `.env.example`, содержит `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` и `DB_HOST=db`. Пароль генерируется командой `openssl rand -hex 16`. Права файла — `600`, владелец — `devops`. `.env` исключён из Git, контекста Docker и синхронизации. Проверка: `stat -c '%a %n' ~/app/.env`.

В `/home/devops/app/docker-compose.yml` определены сервисы `app` и `db` в сети `app_backend`. Приложение собирается из `Dockerfile` в образ `devops-app:1.0`, запускается от непривилегированного пользователя `app` и обращается к PostgreSQL по имени `db` через DNS сети Compose. СУБД использует образ `postgres:16-alpine`; запуск приложения ожидает её состояние `healthy`. Данные PostgreSQL находятся в именованном томе `app_db_data`. Обычная команда `docker compose down` сохраняет том, а `docker compose down -v` удаляет его и все данные.

Порт приложения опубликован только на `127.0.0.1:5000` VM; порт 5432 на хосте не опубликован. Проверка: `ss -tln | grep -E ':(5000|5432)\b'`. Nginx в `/etc/nginx/sites-available/devops-site` принимает HTTPS на `devops.local:443` и передаёт `/app/` на `http://127.0.0.1:5000/`, сохраняя исходные заголовки `Host`, `X-Real-IP`, `X-Forwarded-For` и `X-Forwarded-Proto`. Статический ресурс в `location /` сохранён. Сертификат и ключ находятся в `/etc/ssl/certs/devops.crt` и `/etc/ssl/private/devops.key`.

После перезагрузки VM проверить `cd ~/app && docker compose ps`, `docker compose exec app id`, `docker compose exec app getent hosts db`, `curl -i http://127.0.0.1:5000/health`, а с хоста — `curl --cacert ~/devops.crt https://devops.local/app/health`. Проверить Nginx: `sudo nginx -t && sudo systemctl status nginx`.
