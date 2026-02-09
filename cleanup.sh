#!/data/data/com.termux/files/usr/bin/bash
# Скрипт очистки старых runit сервисов

echo "=== Очистка старых сервисов ==="

# 1. Убиваем все runit процессы
echo "Остановка runit процессов..."
pkill -9 runsvdir 2>/dev/null
pkill -9 svlogd 2>/dev/null
pkill -9 runsv 2>/dev/null
sleep 1

# 2. Удаляем директории старых сервисов
echo "Удаление старых сервисов..."
rm -rf "$PREFIX/var/service/mbsft-"* 2>/dev/null

# 3. Убиваем старые bash процессы watchdog/autosave
echo "Остановка старых фоновых процессов..."
pkill -f "mbsft-.*watchdog" 2>/dev/null
pkill -f "mbsft-.*autosave" 2>/dev/null
pkill -f "mbsft-test-autosave" 2>/dev/null

# 4. Чистим pid файлы
echo "Очистка pid файлов..."
rm -f ~/mbsft-servers/*/.watchdog.pid 2>/dev/null
rm -f ~/mbsft-servers/*/.autosave.pid 2>/dev/null

# 5. Сбрасываем конфиги (ставим все в "no")
echo "Сброс конфигов сервисов..."
for conf in ~/mbsft-servers/*/.mbsft.conf; do
    if [ -f "$conf" ]; then
        sed -i 's/^WATCHDOG_ENABLED=.*/WATCHDOG_ENABLED=no/' "$conf"
        sed -i 's/^AUTOSAVE_ENABLED=.*/AUTOSAVE_ENABLED=no/' "$conf"
        echo "Сброшен: $conf"
    fi
done

echo ""
echo "✓ Очистка завершена!"
echo ""
echo "Теперь запусти: mbsft"
echo "И заново включи нужные сервисы."
