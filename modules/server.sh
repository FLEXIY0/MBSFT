#!/data/data/com.termux/files/usr/bin/bash
# ============================================
# MBSFT Server Module
# Управление серверами
# ============================================

# =====================
# Патч конфигов сервера
# =====================
patch_server() {
    local sv_dir="$1" port="$2"
    if [ -f "$sv_dir/eula.txt" ]; then
        sed -i 's/eula=false/eula=true/g' "$sv_dir/eula.txt"
    fi
    if [ -f "$sv_dir/server.properties" ]; then
        sed -i "s/online-mode=true/online-mode=false/g" "$sv_dir/server.properties"
        sed -i "s/verify-names=true/verify-names=false/g" "$sv_dir/server.properties"
        sed -i "s/server-ip=.*/server-ip=/g" "$sv_dir/server.properties"
        sed -i "s/server-port=.*/server-port=$port/g" "$sv_dir/server.properties"
    fi
}

# =====================
# Генерация start.sh
# =====================
make_start_sh() {
    local sv_dir="$1" name="$2" ram="$3" port="$4"
    find_java
    cat > "$sv_dir/start.sh" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
cd "$sv_dir"
echo "[$name] Запуск (RAM: $ram, Port: $port)..."
"$JAVA_BIN" -Xmx$ram -Xms$ram -jar server.jar nogui
EOF
    chmod +x "$sv_dir/start.sh"
}

# =====================
# Запуск сервера
# =====================
server_start() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"

    if is_server_running "$name"; then
        dialog --title "$name" --msgbox "Уже запущен!" 6 30
        return
    fi
    if [ ! -f "$sv_dir/server.jar" ]; then
        dialog --title "$name" --msgbox "server.jar не найден!\nЗакинь в: $sv_dir/" 7 50
        return
    fi

    cd "$sv_dir"
    screen -dmS "mbsft-${name}" ./start.sh
    sleep 2

    if is_server_running "$name"; then
        local ip port
        ip=$(get_local_ip)
        port=$(get_actual_port "$sv_dir")
        dialog --title "$name" --msgbox "Сервер запущен!\n\nПодключение: $ip:$port\nКонсоль: screen -r mbsft-${name}" 9 50
    else
        dialog --title "$name" --msgbox "Не удалось запустить.\nПроверь логи в $sv_dir/" 7 50
    fi
}

# =====================
# Остановка сервера
# =====================
server_stop() {
    local name="$1"
    if ! is_server_running "$name"; then
        dialog --title "$name" --msgbox "Сервер не запущен." 6 34
        return
    fi

    screen -S "mbsft-${name}" -p 0 -X stuff "stop$(printf '\r')" 2>/dev/null
    local tries=0
    while is_server_running "$name" && [ $tries -lt 15 ]; do
        sleep 1
        tries=$((tries + 1))
    done
    is_server_running "$name" && screen -S "mbsft-${name}" -X quit 2>/dev/null

    dialog --title "$name" --msgbox "Сервер остановлен." 6 34
}

# =====================
# Остановка без диалога
# =====================
server_stop_silent() {
    local name="$1"
    is_server_running "$name" || return
    screen -S "mbsft-${name}" -p 0 -X stuff "stop$(printf '\r')" 2>/dev/null
    local tries=0
    while is_server_running "$name" && [ $tries -lt 15 ]; do
        sleep 1
        tries=$((tries + 1))
    done
    is_server_running "$name" && screen -S "mbsft-${name}" -X quit 2>/dev/null
}

# =====================
# Принудительная остановка
# =====================
server_force_stop() {
    local name="$1"
    if is_server_running "$name"; then
        # Пытаемся graceful shutdown
        screen -S "mbsft-${name}" -p 0 -X stuff "stop$(printf '\r')" 2>/dev/null
        local tries=0
        while is_server_running "$name" && [ $tries -lt 10 ]; do
            sleep 1
            tries=$((tries + 1))
        done
        # Если не остановился — убиваем
        if is_server_running "$name"; then
            screen -S "mbsft-${name}" -X quit 2>/dev/null
            sleep 1
        fi
        # Последняя проверка
        if is_server_running "$name"; then
            # Убиваем процесс напрямую
            pkill -f "mbsft-${name}" 2>/dev/null
        fi
    fi
}

# =====================
# Консоль
# =====================
server_console() {
    local name="$1"
    if ! is_server_running "$name"; then
        dialog --title "$name" --msgbox "Сервер не запущен!" 6 34
        return
    fi
    dialog --title "$name" --msgbox "Откроется консоль.\n\nВыход: Ctrl+A, затем D" 8 40
    screen -r "mbsft-${name}"
}

# =====================
# Настройки
# =====================
server_settings() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"
    read_server_conf "$sv_dir"

    local actual_port
    actual_port=$(get_actual_port "$sv_dir")
    local online="?"
    [ -f "$sv_dir/server.properties" ] && online=$(grep "online-mode=" "$sv_dir/server.properties" 2>/dev/null | cut -d= -f2)

    local new_ram
    new_ram=$(dialog --title "Настройки: $name" --menu "RAM (сейчас: $RAM):" 12 44 4 \
        "512M" "Для слабых устройств" \
        "1G"   "Рекомендуется" \
        "2G"   "Для мощных устройств" \
        "4G"   "Максимум" \
        3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return

    local new_port
    new_port=$(dialog --title "Настройки: $name" --inputbox "Порт (сейчас: $actual_port):" 8 40 "$actual_port" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return

    local new_online=false
    dialog --title "Настройки: $name" --yesno "Включить online-mode?\n(Сейчас: $online)\n\nДа = лицензия нужна\nНет = пираты могут заходить" 10 44
    [ $? -eq 0 ] && new_online=true

    make_start_sh "$sv_dir" "$name" "$new_ram" "$new_port"

    if [ -f "$sv_dir/server.properties" ]; then
        sed -i "s/server-port=.*/server-port=$new_port/g" "$sv_dir/server.properties"
        sed -i "s/online-mode=.*/online-mode=$new_online/g" "$sv_dir/server.properties"
        sed -i "s/verify-names=.*/verify-names=$new_online/g" "$sv_dir/server.properties"
        sed -i "s/server-ip=.*/server-ip=/g" "$sv_dir/server.properties"
    fi
    [ -f "$sv_dir/eula.txt" ] && sed -i 's/eula=false/eula=true/g' "$sv_dir/eula.txt"

    write_server_conf "$sv_dir" "$name" "$new_ram" "$new_port" "$CORE"

    dialog --title "$name" --msgbox "Настройки обновлены!\n\nRAM: $new_ram\nПорт: $new_port\nonline-mode: $new_online\n\nПерезапусти сервер." 11 40
}

# =====================
# Создание сервиса
# =====================
server_create_service() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"
    local sv_service="mbsft-${name}"
    local SVDIR="$PREFIX/var/service/$sv_service"

    mkdir -p "$SVDIR/log"

    cat > "$SVDIR/run" <<SEOF
#!/data/data/com.termux/files/usr/bin/sh
cd "$sv_dir"
(
    while true; do
        sleep 600
        screen -S "mbsft-${name}" -p 0 -X stuff "save-all\$(printf \\\\r)" 2>/dev/null
    done
) &
SAVE_PID=\$!
trap "kill \$SAVE_PID 2>/dev/null" EXIT TERM INT
exec screen -DmS "mbsft-${name}" ./start.sh
SEOF
    chmod +x "$SVDIR/run"

    cat > "$SVDIR/log/run" <<LEOF
#!/data/data/com.termux/files/usr/bin/sh
mkdir -p "$sv_dir/logs/sv"
exec svlogd -tt "$sv_dir/logs/sv"
LEOF
    chmod +x "$SVDIR/log/run"
    command -v sv-enable &>/dev/null && sv-enable "$sv_service" 2>/dev/null || true

    dialog --title "$name" --msgbox "Сервис '$sv_service' создан!\n\nАвтозапуск + автосохранение\n\nУправление:\n  sv up $sv_service\n  sv down $sv_service" 12 48
}

# =====================
# Удаление сервера (с принудительной остановкой)
# =====================
server_delete() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"

    dialog --title "УДАЛЕНИЕ" --yesno "Удалить сервер '$name' и ВСЕ его файлы?\n\n$sv_dir" 8 50
    [ $? -ne 0 ] && return 1

    local confirm
    confirm=$(dialog --title "ПОДТВЕРЖДЕНИЕ" --inputbox "Введи имя сервера для подтверждения:" 8 50 "" 3>&1 1>&2 2>&3)
    if [ "$confirm" != "$name" ]; then
        dialog --title "$TITLE" --msgbox "Отменено." 6 24
        return 1
    fi

    # ИСПРАВЛЕНИЕ: Принудительная остановка сервера
    if is_server_running "$name"; then
        dialog --title "УДАЛЕНИЕ" --infobox "Останавливаю сервер '$name'..." 5 40
        server_force_stop "$name"
        sleep 2
    fi

    # Удаляем сервис если есть
    local sv_service="mbsft-${name}"
    if [ -d "$PREFIX/var/service/$sv_service" ]; then
        sv down "$sv_service" 2>/dev/null || true
        command -v sv-disable &>/dev/null && sv-disable "$sv_service" 2>/dev/null || true
        rm -rf "$PREFIX/var/service/$sv_service"
    fi

    # Удаляем папку сервера
    rm -rf "$sv_dir"
    
    dialog --title "$TITLE" --msgbox "Сервер '$name' удалён.\n\nВсе процессы остановлены." 7 38
    return 0
}
