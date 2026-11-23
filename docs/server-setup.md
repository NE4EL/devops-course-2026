# Настройка учебной VM

## 10. Ansible

Проект находится в `ansible/` репозитория `NE4EL/devops-course-2026`.
Управляющий узел — macOS с Ansible; управляемый — VirtualBox VM
`devops-vm`, Ubuntu Server 24.04 ARM64, Host-only IP `192.168.56.2`.
Все команды Ansible ниже выполняются из каталога `ansible/`.

### Подключения и роли

`inventory/bootstrap.ini` подключается к порту 22 как `evtushenko`
(имя локального пользователя вместо `student` в методических указаниях).
Первый запуск запрашивает пароли SSH и sudo.
`inventory/prod.ini` использует `devops`, порт 22 и `~/.ssh/devops_vm`.
Ключ защищён парольной фразой и перед запуском должен быть загружен в SSH agent.
Закрытый ключ, пароли и токены в репозитории отсутствуют.

Роль `base` проверяет ОС и архитектуру, устанавливает зависимости модулей,
Docker Engine из официального репозитория Docker и запускает Docker.
`python3-debian` нужен для deb822, `python3-requests` — для Docker API.
На этой VM DNS VirtualBox `10.0.2.3` не отвечал: роль сохраняет проверенный
DNS `8.8.8.8` в drop-in systemd-resolved до первого обращения к APT.

Роль `ssh` создаёт `devops`, устанавливает публичный ключ, проверенный
файл sudoers (`visudo -cf`) и SSH-конфигурацию (`sshd -t -f`).
Ключ устанавливается до отключения паролей. UFW разрешает 22/tcp и 80/tcp.
`AllowUsers` сохраняет оба имени: `evtushenko devops`.
Учебный `NOPASSWD:ALL` даёт полный административный доступ; для production
нужны более узкие разрешения и отдельный защищённый ключ автоматизации.

Роль `nginx` отключает default site и настраивает reverse proxy на loopback.
Handlers сначала проверяют `nginx -t`, затем выполняют reload.
В `ansible.cfg` включён `force_handlers = True`.
После роли app выполняются уведомлённые handlers и отдельная проверка
`http://127.0.0.1/health`, исключающая возврат плейбука до готовности новых workers Nginx.

Роль `app` сначала загружает образ, затем меняет контейнер и ожидает `/health`.
Образ: `ghcr.io/ne4el/devops-ci-app`.
Полный проверенный SHA: `9b957428609ffdb38b9f3d3fa2d9014b44ca4c80`.
Успешный CI: https://github.com/NE4EL/devops-ci-app/actions/runs/45142720980
Контейнер `devops-ci-app` публикует `127.0.0.1:5000:5000`, Nginx — порт 80.
Внешняя проверка: `http://192.168.56.2/health`, ожидается `{"status":"ok"}`.

Опубликованный в ПР10 образ имеет архитектуру amd64. На ARM64 VM роль base
устанавливает QEMU и binfmt; роль app задаёт `platform: linux/amd64`.
Образ на сервере не собирается. При публикации arm64-образа следует сменить
`app_platform` и полный SHA в `group_vars/all.yml`.

### Запуски

```sh
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/bootstrap.ini site.yml --syntax-check
ansible-playbook site.yml --syntax-check
ansible-playbook -i inventory/bootstrap.ini site.yml --ask-pass --ask-become-pass
ssh -i ~/.ssh/devops_vm devops@192.168.56.2 'whoami && sudo -n true'
ansible all -m ping
ansible-playbook site.yml
ansible-playbook verify.yml
curl --fail http://192.168.56.2/health
```

Повторный `site.yml` должен давать `changed=0, failed=0`. `verify.yml`
проверяет SSH, состояние контейнера и JSON `/health`, не изменяя VM.
`changed_when: false` у `sshd -T` отражает то, что команда только читает конфигурацию.

### Проверка восстановления

При drift контейнер удаляется, upstream Nginx меняется на 5001, внешний запрос
возвращает 502. `site.yml` восстанавливает шаблон, контейнер и доступность HTTP.
При временной подстановке несуществующего SHA из 40 нулей загрузка образа
завершается ошибкой до задачи управления контейнером: прежний ID контейнера
и успешный `/health` сохраняются. После эксперимента возвращается зафиксированный SHA.
Остановка контейнера должна вызывать отказ `verify.yml`; восстановление
выполняется основным `site.yml`, затем аудит снова проходит с `changed=0`.
