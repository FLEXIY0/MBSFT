#!/data/data/com.termux/files/usr/bin/bash
# ============================================
# MBSFT UI Module
# Dialog интерфейс и меню
# ============================================

# =====================
# Установка зависимостей
# =====================
step_deps() {
    if deps_installed; then
        local jver
        jver=$("$JAVA_BIN" -version 2>&1 | head -1)
        dialog --title "$TITLE" --msgbox "Всё уже установлено!\n\nJava: $jver\nПуть: $JAVA_BIN\nscreen: $(which screen)\nwget: $(which wget)" 12 56
        return
    fi

    dialog --title "$TITLE" --yesno "Установить зависимости?\n\n• Java 8 (OpenJDK 8)\n• screen, wget\n• openssh, iproute2, net-tools\n• termux-services" 12 46
    [ $? -ne 0 ] && return

    clear
    echo "=== Установка зависимостей ==="
    echo ""
    pkg update -y && pkg upgrade -y

    echo ""
    echo "--- Основные пакеты ---"
    pkg install -y wget screen termux-services openssh

    echo ""
    echo "--- Сетевые утилиты ---"
    pkg install -y net-tools
    if ! command -v ifconfig &>/dev/null; then
        echo "ВНИМАНИЕ: net-tools не установился, пробую ещё раз..."
        apt install -y net-tools
    fi
    pkg install -y iproute2 2>/dev/null

    echo ""
    install_java
    local java_ok=$?

    # Проверка
    echo ""
    echo "=== Результат ==="
    command -v ifconfig &>/dev/null && echo "  ifconfig:  OK" || echo "  ifconfig:  НЕТ"
    command -v screen &>/dev/null   && echo "  screen:    OK" || echo "  screen:    НЕТ"
    command -v wget &>/dev/null     && echo "  wget:      OK" || echo "  wget:      НЕТ"
    [ $java_ok -eq 0 ]             && echo "  java:      OK ($JAVA_BIN)" || echo "  java:      НЕТ"
    echo ""
    echo "Нажми Enter..."
    read -r
}

# =====================
# Создание сервера
# =====================
create_server() {
    if ! deps_installed; then
        dialog --title "$TITLE" --msgbox "Сначала установи зависимости!" 6 44
        return
    fi

    local name
    name=$(dialog --title "Новый сервер" --inputbox "Имя сервера (англ, без пробелов):" 8 50 "" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return
    if [ -z "$name" ] || ! validate_name "$name"; then
        dialog --title "Ошибка" --msgbox "Имя может содержать только буквы, цифры, _ и -" 6 54
        return
    fi

    local sv_dir="$BASE_DIR/$name"
    if [ -d "$sv_dir" ] && [ -f "$sv_dir/server.jar" ]; then
        dialog --title "Ошибка" --msgbox "Сервер '$name' уже существует!" 6 44
        return
    fi

    local ram
    ram=$(dialog --title "Новый сервер: $name" --menu "Сколько RAM выделить?" 12 44 4 \
        "512M" "Для слабых устройств" \
        "1G"   "Рекомендуется" \
        "2G"   "Для мощных устройств" \
        "4G"   "Максимум" \
        3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return

    local default_port
    default_port=$(next_free_port)
    local port
    port=$(dialog --title "Новый сервер: $name" --inputbox "Порт сервера:" 8 40 "$default_port" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return

    local core_choice
    core_choice=$(dialog --title "Новый сервер: $name" --menu "Ядро сервера:" 10 54 2 \
        "poseidon" "Project Poseidon (Beta 1.7.3)" \
        "custom"   "Закину server.jar вручную" \
        3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return

    mkdir -p "$sv_dir"

    if [ "$core_choice" == "poseidon" ]; then
        clear
        echo "=== Скачиваю Project Poseidon ==="
        echo ""
        if ! wget -O "$sv_dir/server.jar" "$POSEIDON_URL"; then
            rm -f "$sv_dir/server.jar"
            dialog --title "Ошибка" --msgbox "Не удалось скачать! Проверь интернет." 6 50
            return
        fi
    else
        dialog --title "$name" --msgbox "Закинь server.jar в папку:\n\n$sv_dir/\n\nЗатем зайди в управление сервером." 10 54
    fi

    make_start_sh "$sv_dir" "$name" "$ram" "$port"
    write_server_conf "$sv_dir" "$name" "$ram" "$port" "$core_choice"

    if [ -f "$sv_dir/server.jar" ]; then
        dialog --title "$name" --yesno "Сервер создан!\n\nЗапустить первый раз для генерации конфигов?\n(Ctrl+C после загрузки)" 10 54
        if [ $? -eq 0 ]; then
            clear
            echo "=== Первый запуск $name ==="
            echo "Нажми Ctrl+C после загрузки"
            echo ""
            cd "$sv_dir" && ./start.sh || true
            patch_server "$sv_dir" "$port"
            echo ""
            echo "Нажми Enter..."
            read -r
        fi
    fi

    dialog --title "$TITLE" --msgbox "Сервер '$name' создан!\n\nПапка: $sv_dir\nRAM: $ram\nПорт: $port\n\nУправляй через «Мои серверы»" 12 50
}

# =====================
# Быстрое создание
# =====================
quick_create() {
    if ! deps_installed; then
        dialog --title "$TITLE" --yesno "Зависимости не установлены.\nУстановить сейчас?" 7 44
        if [ $? -eq 0 ]; then
            clear
            echo "=== Установка зависимостей ==="
            echo ""
            pkg update -y && pkg upgrade -y
            pkg install -y tur-repo 2>/dev/null
            pkg install -y wget screen termux-services openssh iproute2 net-tools
            install_java
            if ! find_java; then
                echo "Java не установлена!"
                read -r
                return
            fi
        else
            return
        fi
    fi

    local name
    name=$(dialog --title "Быстрое создание" --inputbox "Имя сервера:" 8 44 "" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return
    if [ -z "$name" ] || ! validate_name "$name"; then
        dialog --title "Ошибка" --msgbox "Неверное имя!" 6 30
        return
    fi

    local sv_dir="$BASE_DIR/$name"
    if [ -d "$sv_dir" ] && [ -f "$sv_dir/server.jar" ]; then
        dialog --title "Ошибка" --msgbox "Сервер '$name' уже существует!" 6 44
        return
    fi

    local port
    port=$(next_free_port)

    dialog --title "Быстрое создание" --yesno "Создать сервер:\n\nИмя:   $name\nЯдро:  Project Poseidon (Beta 1.7.3)\nRAM:   1G\nПорт:  $port" 12 44
    [ $? -ne 0 ] && return

    mkdir -p "$sv_dir"

    clear
    echo "=== Быстрое создание: $name ==="
    echo ""
    echo "[1/3] Скачиваю ядро..."
    if ! wget -O "$sv_dir/server.jar" "$POSEIDON_URL"; then
        rm -f "$sv_dir/server.jar"
        echo "ОШИБКА загрузки!"
        read -r
        return
    fi

    echo "[2/3] Настраиваю..."
    make_start_sh "$sv_dir" "$name" "1G" "$port"
    write_server_conf "$sv_dir" "$name" "1G" "$port" "poseidon"

    echo "[3/3] Первый запуск (Ctrl+C для остановки)..."
    echo ""
    cd "$sv_dir" && ./start.sh || true
    patch_server "$sv_dir" "$port"
    echo ""
    echo "Нажми Enter..."
    read -r

    dialog --title "$TITLE" --msgbox "Сервер '$name' готов!\n\nПорт: $port\nУправляй через «Мои серверы»" 9 44
}

# =====================
# Список серверов
# =====================
list_servers_menu() {
    while true; do
        local servers
        read -ra servers <<< "$(get_servers)"

        if [ ${#servers[@]} -eq 0 ] || [ -z "${servers[0]}" ]; then
            dialog --title "$TITLE" --msgbox "Серверов пока нет.\nСоздай первый!" 7 34
            return
        fi

        local items=()
        for srv in "${servers[@]}"; do
            local sv_dir="$BASE_DIR/$srv"
            read_server_conf "$sv_dir"
            local actual_port
            actual_port=$(get_actual_port "$sv_dir")
            local status="СТОП"
            is_server_running "$srv" && status="ЗАПУЩЕН"
            items+=("$srv" "Порт:$actual_port RAM:$RAM [$status]")
        done

        local choice
        choice=$(dialog --title "Мои серверы" --menu "Выбери сервер:" 18 56 10 "${items[@]}" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && return

        server_manage_menu "$choice"
    done
}

# =====================
# Управление сервером
# =====================
server_manage_menu() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"

    while true; do
        read_server_conf "$sv_dir"
        local actual_port
        actual_port=$(get_actual_port "$sv_dir")
        local status="ОСТАНОВЛЕН"
        is_server_running "$name" && status="РАБОТАЕТ"

        local choice
        choice=$(dialog --title "[$status] $name" \
            --menu "RAM: $RAM | Порт: $actual_port | Ядро: $CORE" 18 54 9 \
            "start"    "Запустить" \
            "stop"     "Остановить" \
            "restart"  "Перезапустить" \
            "console"  "Консоль (screen)" \
            "settings" "Настройки (RAM, порт)" \
            "service"  "Создать сервис (автосохр.)" \
            "---"      "─────────────────────" \
            "delete"   "Удалить сервер" \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && return

        case $choice in
            start)    server_start "$name" ;;
            stop)     server_stop "$name" ;;
            restart)  server_stop_silent "$name"; server_start "$name" ;;
            console)  server_console "$name" ;;
            settings) server_settings "$name" ;;
            service)  server_create_service "$name" ;;
            delete)   server_delete "$name" && return ;;
        esac
    done
}

# =====================
# Дашборд
# =====================
dashboard() {
    local local_ip ext_ip
    local_ip=$(get_local_ip)
    ext_ip=$(get_external_ip)

    local java_status="НЕ УСТАНОВЛЕНА"
    if find_java; then
        java_status="$($JAVA_BIN -version 2>&1 | head -1)"
    fi

    local ssh_status="выкл"
    pidof sshd &>/dev/null && ssh_status="порт 8022"

    local info="Java:       $java_status\nЛокальный:  $local_ip\nВнешний:    $ext_ip\nSSH:        $ssh_status\n\n"

    local servers
    read -ra servers <<< "$(get_servers)"

    if [ ${#servers[@]} -eq 0 ] || [ -z "${servers[0]}" ]; then
        info+="Серверов нет."
    else
        info+="$(printf '%-16s %-7s %-5s %-10s %s\n' 'Имя' 'Порт' 'RAM' 'Статус' 'Подключение')"
        info+="\n$(printf '%0.s─' {1..56})\n"
        for srv in "${servers[@]}"; do
            local sv_dir="$BASE_DIR/$srv"
            read_server_conf "$sv_dir"
            local actual_port
            actual_port=$(get_actual_port "$sv_dir")
            local status="стоп" connect="-"
            if is_server_running "$srv"; then
                status="РАБОТАЕТ"
                connect="$local_ip:$actual_port"
            fi
            info+="$(printf '%-16s %-7s %-5s %-10s %s' "$NAME" "$actual_port" "$RAM" "$status" "$connect")\n"
        done
    fi

    dialog --title "Дашборд" --msgbox "$info" 22 62
}

# =====================
# SSH
# =====================
step_ssh() {
    dialog --title "SSH" --yesno "Настроить SSH доступ?\n\nПосле этого сможешь управлять\nсервером с ПК через терминал." 9 44
    [ $? -ne 0 ] && return

    clear
    echo "=== Настройка SSH ==="
    echo ""
    echo "Придумай пароль:"
    passwd
    sshd
    echo ""

    local user local_ip ext_ip
    user=$(whoami)
    local_ip=$(get_local_ip)
    ext_ip=$(get_external_ip)
    echo "Готово! Нажми Enter..."
    read -r

    dialog --title "SSH" --msgbox "SSH запущен!\n\nЛокальный IP: $local_ip\nВнешний IP:   $ext_ip\n\nПодключение по Wi-Fi (из дома):\n  ssh -p 8022 $user@$local_ip\n\nПодключение извне:\n  ssh -p 8022 $user@$ext_ip" 15 52
}

# =====================
# Главное меню
# =====================
main_loop() {
    while true; do
        local servers
        read -ra servers <<< "$(get_servers)"
        local count=0
        [ -n "${servers[0]:-}" ] && count=${#servers[@]}

        local running=0
        for srv in "${servers[@]}"; do
            [ -z "$srv" ] && continue
            is_server_running "$srv" && running=$((running + 1))
        done

        local status_line="Серверов: $count | Запущено: $running"
        find_java &>/dev/null && status_line="Java: OK | $status_line"

        local choice
        choice=$(dialog --title "$TITLE" \
            --menu "$status_line" 17 52 8 \
            "deps"     "Установить зависимости" \
            "create"   "Создать сервер (пошагово)" \
            "quick"    "Быстрое создание" \
            "servers"  "Мои серверы [$count шт.]" \
            "dash"     "Дашборд" \
            "ssh"      "Настроить SSH" \
            "---"      "─────────────────────" \
            "quit"     "Выход" \
            3>&1 1>&2 2>&3)

        case $? in
            1|255) break ;;
        esac

        case $choice in
            deps)    step_deps ;;
            create)  create_server ;;
            quick)   quick_create ;;
            servers) list_servers_menu ;;
            dash)    dashboard ;;
            ssh)     step_ssh ;;
            quit)    break ;;
        esac
    done

    clear
}
