# Очистка истёкших сессий

Серверная сессия действует 30 дней от входа. Сайт отклоняет истёкшую запись
даже при действующей cookie. Ежедневный таймер удаляет старые записи, включая
сессии браузеров, которые больше не обращаются к сайту. IP-адрес и user-agent
удаляются вместе с записью. Очистка не пишет их в журнал.

После выпуска версии с `Session.prune_expired!` на VPS установите или обновите
таймер и службу из каталога `deploy`:

```sh
install -m 0644 leave-desk-session-prune.service /etc/systemd/system/
install -m 0644 leave-desk-session-prune.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now leave-desk-session-prune.timer
systemctl is-enabled leave-desk-session-prune.timer
systemctl is-active leave-desk-session-prune.timer
systemctl list-timers leave-desk-session-prune.timer
```

Команды выполняются от root из `/root/projects/leave-desk`, где находится
`compose.yml`. Перед установкой убедитесь, что `web` запущен и миграция с
индексом `sessions.created_at` выполнена. Для проверки запуска и результата:

```sh
systemctl start leave-desk-session-prune.service
systemctl show -p Result -p ExecMainStatus leave-desk-session-prune.service
```

Успешный результат — `Result=success` и `ExecMainStatus=0`. Таймер запускает
очистку в 03:00 UTC, после ежедневной копии БД. Повторный запуск безопасен.
