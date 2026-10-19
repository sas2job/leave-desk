# Очистка файлового кеша

Production использует Rails `FileStore` внутри web-контейнера. Истёкшие
счётчики неудачных входов логически перестают действовать через три минуты, но
без явной очистки их файлы остаются до замены контейнера. Таймер запускает
`Rails.cache.cleanup` каждые 15 минут и физически удаляет только истёкшие
записи.

Workflow выпуска копирует unit-файлы в `/root/projects/leave-desk`, но не
устанавливает их в systemd. После первого выпуска и после изменения файлов
установите или обновите их на VPS:

```sh
cd /root/projects/leave-desk
install -m 0644 leave-desk-cache-cleanup.service /etc/systemd/system/
install -m 0644 leave-desk-cache-cleanup.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now leave-desk-cache-cleanup.timer
systemctl restart leave-desk-cache-cleanup.timer
systemctl is-enabled leave-desk-cache-cleanup.timer
systemctl is-active leave-desk-cache-cleanup.timer
systemctl list-timers --all leave-desk-cache-cleanup.timer
```

Проверьте определение и пробный запуск без вывода ключей кеша:

```sh
systemctl cat leave-desk-cache-cleanup.service leave-desk-cache-cleanup.timer
systemctl start leave-desk-cache-cleanup.service
systemctl show -p Result -p ExecMainStatus leave-desk-cache-cleanup.service
```

Ожидаются `Result=success` и `ExecMainStatus=0`. Команда очистки ничего не
выводит при успехе. Не используйте `Rails.cache.clear`: он удалит также
действующие счётчики и временно ослабит ограничение попыток входа.
