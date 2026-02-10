#!/usr/bin/bash

# ============================================
# MBSFT — Minecraft Beta Server For Termux
# v4.0 - Ubuntu proot + systemd edition
# ============================================

# =====================
# Fix: curl | bash
# =====================
if [ ! -t 0 ]; then
    TMPSCRIPT=$(mktemp "$HOME/.mbsft_install_XXXXXX.sh")
    cat > "$TMPSCRIPT"
    chmod +x "$TMPSCRIPT"
    bash "$TMPSCRIPT" "$@" < /dev/tty
    rm -f "$TMPSCRIPT"
    exit
fi


# Пути
if [ -z "$MBSFT_BASE_DIR" ] && [ -d "/termux-home" ]; then
    BASE_DIR="/termux-home/mbsft-servers"
else
    BASE_DIR="${MBSFT_BASE_DIR:-$HOME/mbsft-servers}"
fi
VERSION="4.2.0"
# Java: будет найдена динамически
JAVA_BIN=""
_JAVA_CHECKED=""
_CACHED_JVER=""

# =====================
# Поиск Java
# =====================
find_java() {
    if [ -n "$JAVA_BIN" ] && [ "$_JAVA_CHECKED" == "true" ]; then
        return 0
    fi

    _CACHED_JVER=""

    # В Ubuntu просто проверяем system Java
    if command -v java &>/dev/null; then
        JAVA_BIN="java"
        _JAVA_CHECKED="true"
        return 0
    fi

    _JAVA_CHECKED="true"
    JAVA_BIN=""
    return 1
}

mkdir -p "$BASE_DIR"
find_java

# =====================
# Утилиты
# =====================

TITLE="MBSFT v${VERSION}"

get_local_ip() {
    [ -n "$CACHED_LOCAL_IP" ] && echo "$CACHED_LOCAL_IP" && return
    local ip=""
    if [ -z "$ip" ] && command -v ip &>/dev/null; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    fi
    if [ -z "$ip" ] && command -v ifconfig &>/dev/null; then
        ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | sed 's/addr://')
    fi
    if [ -z "$ip" ] && command -v hostname &>/dev/null; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    CACHED_LOCAL_IP="${ip:-не определён}"
    echo "$CACHED_LOCAL_IP"
}

get_external_ip() {
    [ -n "$CACHED_EXT_IP" ] && echo "$CACHED_EXT_IP" && return
    local ip=""
    if command -v curl &>/dev/null; then
        ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
    elif command -v wget &>/dev/null; then
        ip=$(wget -qO- --timeout=5 ifconfig.me 2>/dev/null)
    fi
    if echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        CACHED_EXT_IP="$ip"
        echo "$ip"
    else
        CACHED_EXT_IP="не определён"
        echo "не определён"
    fi
}

deps_installed() {
    find_java && command -v tmux &>/dev/null && command -v wget &>/dev/null
}

validate_name() {
    echo "$1" | grep -qE '^[a-zA-Z0-9_-]+$'
}

write_server_conf() {
    local dir="$1" name="$2" ram="$3" port="$4" core="$5"
    cat > "$dir/.mbsft.conf" << EOF
NAME=$name
RAM=$ram
PORT=$port
CORE=$core
CREATED="$(date '+%Y-%m-%d %H:%M')"
WATCHDOG_ENABLED=no
AUTOSAVE_ENABLED=no
AUTOSAVE_INTERVAL=5
EOF
}

# Меню со стрелочками через fzf
arrow_menu() {
    local -n items=$1
    local header="${2:-}"  # Опциональный header для отображения важной информации

    # Проверка наличия fzf
    if ! command -v fzf &>/dev/null; then
        echo "Устанавливаю fzf..." >&2
        apt install -y fzf || {
            echo "Ошибка установки fzf!" >&2
            echo "-1"
            return 1
        }
    fi

    # Формируем параметры fzf
    local fzf_params=(
        --height=40%
        --reverse
        --prompt="→ "
        --pointer="●"
        --color='fg:7,fg+:2,bg+:-1,pointer:2,prompt:2'
        --no-info
        --no-scrollbar
    )

    # Добавляем header если передан
    if [ -n "$header" ]; then
        fzf_params+=(--header="$header")
    fi

    # Показываем меню через fzf
    local selected
    selected=$(printf '%s\n' "${items[@]}" | fzf "${fzf_params[@]}")

    # Если ничего не выбрано (ESC), возвращаем -1
    if [ -z "$selected" ]; then
        echo "-1"
        return 1
    fi

    # Находим индекс выбранного элемента
    for i in "${!items[@]}"; do
        if [ "${items[$i]}" = "$selected" ]; then
            echo "$i"
            return 0
        fi
    done

    # Если не нашли (не должно случиться)
    echo "-1"
    return 1
}

read_server_conf() {
    local dir="$1"
    if [ -f "$dir/.mbsft.conf" ]; then
        # Исправляем старый формат CREATED без кавычек (миграция)
        if grep -q '^CREATED=[0-9]' "$dir/.mbsft.conf" && ! grep -q '^CREATED="' "$dir/.mbsft.conf"; then
            sed -i 's/^CREATED=\(.*\)/CREATED="\1"/' "$dir/.mbsft.conf"
        fi

        # Миграция: добавляем отсутствующие поля для старых конфигов
        if ! grep -q '^WATCHDOG_ENABLED=' "$dir/.mbsft.conf"; then
            echo "WATCHDOG_ENABLED=no" >> "$dir/.mbsft.conf"
        fi
        if ! grep -q '^AUTOSAVE_ENABLED=' "$dir/.mbsft.conf"; then
            echo "AUTOSAVE_ENABLED=no" >> "$dir/.mbsft.conf"
        fi
        if ! grep -q '^AUTOSAVE_INTERVAL=' "$dir/.mbsft.conf"; then
            echo "AUTOSAVE_INTERVAL=5" >> "$dir/.mbsft.conf"
        fi

        source "$dir/.mbsft.conf"
        # Значения по умолчанию для старых конфигов
        WATCHDOG_ENABLED="${WATCHDOG_ENABLED:-no}"
        AUTOSAVE_ENABLED="${AUTOSAVE_ENABLED:-no}"
        AUTOSAVE_INTERVAL="${AUTOSAVE_INTERVAL:-5}"
    else
        NAME=$(basename "$dir")
        RAM="1G"; PORT="25565"; CORE="unknown"; CREATED="?"
        WATCHDOG_ENABLED="no"
        AUTOSAVE_ENABLED="no"
        AUTOSAVE_INTERVAL="5"
    fi
}

get_servers() {
    local servers=()
    for d in "$BASE_DIR"/*/; do
        [ -d "$d" ] || continue
        if [ -f "$d/.mbsft.conf" ] || [ -f "$d/server.jar" ]; then
            servers+=("$(basename "$d")")
        fi
    done
    echo "${servers[@]}"
}

is_server_running() {
    local name="$1"
    tmux has-session -t "mbsft-$name" 2>/dev/null
}

get_actual_port() {
    local dir="$1"
    if [ -f "$dir/server.properties" ]; then
        grep "server-port=" "$dir/server.properties" 2>/dev/null | cut -d= -f2
    else
        read_server_conf "$dir"
        echo "$PORT"
    fi
}

next_free_port() {
    local port=25565
    local existing=()
    for srv in $(get_servers); do
        existing+=("$(get_actual_port "$BASE_DIR/$srv")")
    done
    while printf '%s\n' "${existing[@]}" | grep -qx "$port" 2>/dev/null; do
        port=$((port + 1))
    done
    echo "$port"
}

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

make_start_sh() {
    local sv_dir="$1" name="$2" ram="$3" port="$4" core="$5"
    local args="nogui"
    if [ "$core" == "foxloader" ]; then
        args="--server"
    fi

    # Ubuntu proot - простой bash скрипт
    cat > "$sv_dir/start.sh" << EOF
#!/usr/bin/bash
cd "$sv_dir"
echo "[$name] Starting server..."
echo "RAM: $ram, Port: $port, Core: $core"
java -Xmx$ram -Xms$ram -jar server.jar $args
EOF
    chmod +x "$sv_dir/start.sh"
}

check_deps_status() {
    echo "=== Статус зависимостей ==="
    if find_java; then
        echo "Java:       OK ($JAVA_BIN)"
    else
        echo "Java:       НЕТ"
    fi
    command -v tmux &>/dev/null && echo "tmux:       OK" || echo "tmux:       НЕТ"
    command -v wget &>/dev/null && echo "wget:       OK" || echo "wget:       НЕТ"
    command -v sshd &>/dev/null && echo "openssh:    OK" || echo "openssh:    НЕТ"
    command -v node &>/dev/null && echo "nodejs:     OK ($(node --version))" || echo "nodejs:     НЕТ"
    command -v npm &>/dev/null && echo "npm:        OK ($(npm --version))" || echo "npm:        НЕТ"
    echo ""
}

run_install_deps() {
    clear
    echo "=== Установка зависимостей ==="
    export DEBIAN_FRONTEND=noninteractive
    apt update -y && apt upgrade -y
    apt install -y wget tmux openssh-server iproute2 net-tools curl fzf nodejs npm

    # Java должна быть установлена через bootstrap
    if ! find_java; then
        echo "Установка Java 8..."
        apt install -y openjdk-8-jre-headless
    fi

    echo ""
    echo "✓ Зависимости установлены"
    echo ""
    read -r
}

run_uninstall_deps() {
    clear
    echo "=== Удаление зависимостей ==="
    echo "ВНИМАНИЕ! Будут удалены:"
    echo " - Пакеты: wget, tmux, openssh-server, iproute2, net-tools, nodejs, npm"
    echo ""
    read -p "Точно продолжить? (y/n): " yn
    if [[ "$yn" != "y" ]]; then return; fi

    echo "Удаление пакетов..."
    apt remove -y wget tmux openssh-server iproute2 net-tools nodejs npm

    echo "Готово."
    read -r
}

step_deps() {
    while true; do
        clear
        show_banner
        check_deps_status
        echo "=== Меню зависимостей ==="

        local menu_items=("Установить всё" "Удалить зависимости" "Назад")
        local choice
        choice=$(arrow_menu menu_items)

        case $choice in
            0) run_install_deps; return ;;
            1) run_uninstall_deps ;;
            2|-1) return ;;
        esac
    done
}

create_server() {
    if ! deps_installed; then
        echo "Сначала установи зависимости!"
        read -r
        return
    fi

    echo "=== Новый сервер ==="
    read -p "Имя сервера (англ, без пробелов): " name
    if [ -z "$name" ] || ! validate_name "$name"; then
        echo "Ошибка: Имя может содержать только буквы, цифры, _ и -"
        read -r
        return
    fi

    local sv_dir="$BASE_DIR/$name"
    if [ -d "$sv_dir" ] && [ -f "$sv_dir/server.jar" ]; then
        echo "Ошибка: Сервер '$name' уже существует!"
        read -r
        return
    fi

    echo "Сколько RAM выделить?"
    echo "1) 512M"
    echo "2) 1G"
    echo "3) 2G"
    echo "4) 4G"
    local ram="1G"
    while true; do
        read -p "Выбор (2): " r_choice
        case "${r_choice:-2}" in
            1) ram="512M"; break ;;
            2) ram="1G"; break ;;
            3) ram="2G"; break ;;
            4) ram="4G"; break ;;
            *) echo "Неверно. 1-4";;
        esac
    done

    local default_port=$(next_free_port)
    read -p "Порт сервера [$default_port]: " port
    port=${port:-$default_port}

    echo "Ядро сервера:"
    echo "1) poseidon (Beta 1.7.3)"
    echo "2) reindev (Beta 1.7.3 custom)"
    echo "3) foxloader (Beta 1.7.3 modloader)"
    echo "4) custom (свой файл)"

    local core_choice
    local poseidon_url="https://github.com/FLEXIY0/MBSFT/releases/download/servers/project-poseidon-1.1.8.jar"

    while true; do
        read -p "Выбор: " c_choice
        case $c_choice in
            1) core_choice="poseidon"; break ;;
            2) core_choice="reindev"; break ;;
            3) core_choice="foxloader"; break ;;
            4) core_choice="custom"; break ;;
            *) echo "Неверно. 1-4";;
        esac
    done

    mkdir -p "$sv_dir"

    if [ "$core_choice" == "poseidon" ]; then
        echo "Скачиваю Project Poseidon..."
        wget -O "$sv_dir/server.jar" "$poseidon_url" || { echo "Ошибка загрузки"; return; }
    elif [ "$core_choice" == "reindev" ]; then
        echo "Скачиваю Reindev..."
        wget -O "$sv_dir/server.jar" "https://github.com/FLEXIY0/MBSFT/releases/download/servers/reindev-server-2.9_03.jar" || { echo "Ошибка загрузки"; return; }
    elif [ "$core_choice" == "foxloader" ]; then
        echo "Скачиваю FoxLoader..."
        wget -O "$sv_dir/server.jar" "https://github.com/Fox2Code/FoxLoader/releases/download/2.0-alpha39/foxloader-2.0-alpha39-server.jar" || { echo "Ошибка загрузки"; return; }
    elif [ "$core_choice" == "custom" ]; then
        echo "Закинь server.jar в папку $sv_dir/ и нажми Enter"
        read -r
    fi

    make_start_sh "$sv_dir" "$name" "$ram" "$port" "$core_choice"
    write_server_conf "$sv_dir" "$name" "$ram" "$port" "$core_choice"

    cat > "$sv_dir/server.properties" << EOF
#Minecraft server properties
online-mode=false
server-port=$port
server-ip=
spawn-protection=16
verify-names=false
max-players=20
white-list=false
level-name=world
view-distance=10
enable-query=true
enable-rcon=false
motd=A Minecraft Server
EOF

    echo "Сервер создан!"
    read -p "Запустить сейчас? (y/n): " yn
    if [[ "$yn" == "y" ]]; then
        server_start "$name"
        server_console "$name"
    fi
}

server_start() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"

    if is_server_running "$name"; then
        echo "Сервер уже запущен!"
        read -r
        return
    fi

    cd "$sv_dir" || return
    # Запуск
    tmux new-session -d -s "mbsft-$name" "cd \"$sv_dir\" && ./start.sh; echo ''; echo '=== СЕРВЕР ОСТАНОВЛЕН ==='; echo 'Нажми Enter...'; read"
    sleep 2

    if is_server_running "$name"; then
        echo "Сервер запущен. Порт: $(get_actual_port "$sv_dir")"
    else
        echo "Не удалось запустить."
    fi
}

server_stop() {
    local name="$1"
    if ! is_server_running "$name"; then
        echo "Сервер не запущен."
        return
    fi

    tmux send-keys -t "mbsft-$name" "stop" C-m 2>/dev/null

    local tries=0
    while is_server_running "$name" && [ $tries -lt 15 ]; do
        sleep 1
        tries=$((tries+1))
    done

    if is_server_running "$name"; then
        tmux kill-session -t "mbsft-$name" 2>/dev/null
    fi
    echo "Сервер остановлен."
}

server_console() {
    local name="$1"
    if ! is_server_running "$name"; then
        echo "Сервер не запущен!"
        read -r
        return
    fi

    echo "Подключение к консоли $name..."

    # Проверяем находимся ли мы уже в tmux (вложенная сессия)
    if [ -n "$TMUX" ]; then
        echo "⚠️  Ты уже в tmux! Используй: Ctrl+B, затем B, затем D для выхода"
        echo "(Двойной prefix для вложенного tmux)"
    else
        echo "Нажми Ctrl+B, затем D чтобы выйти из консоли (оставить сервер работать)."
    fi

    sleep 2

    # Если мы в tmux - используем switch-client вместо attach
    if [ -n "$TMUX" ]; then
        tmux switch-client -t "mbsft-$name"
    else
        tmux attach-session -t "mbsft-$name"
    fi

    clear
}

server_delete() {
    local name="$1"
    read -p "ТОЧНО удалить сервер $name? (y/n): " yn
    if [[ "$yn" != "y" ]]; then return; fi

    server_stop "$name" 2>/dev/null
    remove_watchdog_service "$name" 2>/dev/null
    remove_autosave_service "$name" 2>/dev/null
    rm -rf "$BASE_DIR/$name"
    echo "Удалено."
    read -r
}

# =====================
# WATCHDOG SERVICE (nohup background process)
# =====================

setup_watchdog_service() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"
    local pid_file="$sv_dir/.watchdog.pid"
    local log_file="$sv_dir/.watchdog.log"

    # Если уже запущен - останавливаем
    if [ -f "$pid_file" ]; then
        local old_pid=$(cat "$pid_file")
        if kill -0 "$old_pid" 2>/dev/null; then
             kill "$old_pid" 2>/dev/null
        fi
        rm -f "$pid_file"
    fi

    # Запускаем фоновый процесс мониторинга
    nohup bash -c "
        while true; do
            if ! tmux has-session -t 'mbsft-$name' 2>/dev/null; then
                echo \"[\$(date)] Server crashed or stopped unexpectedly, restarting in 5 seconds...\"
                sleep 5
                cd '$sv_dir' || exit 1
                tmux new-session -d -s 'mbsft-$name' \"cd '$sv_dir' && ./start.sh; echo ''; echo '=== СЕРВЕР ОСТАНОВЛЕН ==='; echo 'Нажми Enter...'; read\"
                echo \"[\$(date)] Server restarted\"
            fi
            sleep 10
        done
    " > "$log_file" 2>&1 &

    local pid=$!
    echo $pid > "$pid_file"
    echo "✓ Автоперезапуск включен (PID: $pid)"
}

remove_watchdog_service() {
    local name="$1"
    local pid_file="$BASE_DIR/$name/.watchdog.pid"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        kill "$pid" 2>/dev/null
        rm -f "$pid_file"
    fi
    echo "✓ Автоперезапуск отключен"
}

toggle_watchdog() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"

    read_server_conf "$sv_dir"

    if [ "$WATCHDOG_ENABLED" = "yes" ]; then
        # Отключаем
        remove_watchdog_service "$name"
        sed -i 's/^WATCHDOG_ENABLED=.*/WATCHDOG_ENABLED=no/' "$sv_dir/.mbsft.conf"
    else
        # Включаем
        setup_watchdog_service "$name"
        sed -i 's/^WATCHDOG_ENABLED=.*/WATCHDOG_ENABLED=yes/' "$sv_dir/.mbsft.conf"
    fi
    read -r
}

# =====================
# AUTOSAVE SERVICE (nohup background process)
# =====================

setup_autosave_service() {
    local name="$1"
    local interval="$2"
    local sv_dir="$BASE_DIR/$name"
    local pid_file="$sv_dir/.autosave.pid"
    local log_file="$sv_dir/.autosave.log"

    local interval_seconds=$((interval * 60))

    # Если уже запущен - останавливаем
    if [ -f "$pid_file" ]; then
        local old_pid=$(cat "$pid_file")
        if kill -0 "$old_pid" 2>/dev/null; then
             kill "$old_pid" 2>/dev/null
        fi
        rm -f "$pid_file"
    fi

    # Запускаем фоновый процесс автосохранения
    nohup bash -c "
        echo \"[\$(date)] Autosave service started (interval: ${interval_seconds}s)\"
        while true; do
            sleep $interval_seconds
            if tmux has-session -t 'mbsft-$name' 2>/dev/null; then
                tmux send-keys -t 'mbsft-$name' 'save-all' C-m
                echo \"[\$(date)] Sent save-all to mbsft-$name\"
            fi
        done
    " > "$log_file" 2>&1 &

    local pid=$!
    echo $pid > "$pid_file"
    echo "✓ Автосохранение включено (интервал: $interval мин, PID: $pid)"
}

remove_autosave_service() {
    local name="$1"
    local pid_file="$BASE_DIR/$name/.autosave.pid"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        kill "$pid" 2>/dev/null
        rm -f "$pid_file"
    fi
    echo "✓ Автосохранение отключено"
}

show_server_debug() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"

    clear
    show_banner
    echo "=== DEBUG: $name ==="
    echo ""

    # 1. Config file
    echo "--- Конфиг (.mbsft.conf) ---"
    if [ -f "$sv_dir/.mbsft.conf" ]; then
        cat "$sv_dir/.mbsft.conf"
    else
        echo "Файл не найден!"
    fi
    echo ""

    # 2. Process status
    echo "--- Процессы (PID) ---"
    if [ -f "$sv_dir/.watchdog.pid" ]; then
        local wpid=$(cat "$sv_dir/.watchdog.pid")
        if kill -0 "$wpid" 2>/dev/null; then
             echo "Watchdog: RUNNING (PID $wpid)"
        else
             echo "Watchdog: DIED (PID $wpid file exists)"
        fi
    else
        echo "Watchdog: STOPPED"
    fi

    if [ -f "$sv_dir/.autosave.pid" ]; then
        local apid=$(cat "$sv_dir/.autosave.pid")
        if kill -0 "$apid" 2>/dev/null; then
             echo "Autosave: RUNNING (PID $apid)"
        else
             echo "Autosave: DIED (PID $apid file exists)"
        fi
    else
        echo "Autosave: STOPPED"
    fi
    echo ""

    # 3. Logs (last 10 lines)
    echo "--- Логи (последние 10 строк) ---"
    echo "Watchdog (.watchdog.log):"
    if [ -f "$sv_dir/.watchdog.log" ]; then
        tail -n 10 "$sv_dir/.watchdog.log"
    else
        echo "  (нет логов)"
    fi
    echo ""
    echo "Autosave (.autosave.log):"
    if [ -f "$sv_dir/.autosave.log" ]; then
        tail -n 10 "$sv_dir/.autosave.log"
    else
        echo "  (нет логов)"
    fi
    echo ""

    read -p "Нажми Enter..."
}

configure_autosave() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"

    clear
    show_banner

    read_server_conf "$sv_dir"

    local current_status="выкл"
    [ "$AUTOSAVE_ENABLED" = "yes" ] && current_status="вкл"

    local menu_items=("Включить автосохранение" "Отключить автосохранение" "Интервал: 3 минуты" "Интервал: 5 минут" "Интервал: 10 минут" "Свой интервал (ручной ввод)" "Назад")

    # Header с текущими настройками
    local menu_header="Настройка автосохранения: $name | Статус: $current_status | Интервал: $AUTOSAVE_INTERVAL мин"

    local choice
    choice=$(arrow_menu menu_items "$menu_header")

    case $choice in
        0)
            # Включить
            if [ "$AUTOSAVE_ENABLED" != "yes" ]; then
                setup_autosave_service "$name" "$AUTOSAVE_INTERVAL"
                sed -i 's/^AUTOSAVE_ENABLED=.*/AUTOSAVE_ENABLED=yes/' "$sv_dir/.mbsft.conf"
            else
                echo "Уже включено"
            fi
            read -r
            ;;
        1)
            # Отключить
            remove_autosave_service "$name"
            sed -i 's/^AUTOSAVE_ENABLED=.*/AUTOSAVE_ENABLED=no/' "$sv_dir/.mbsft.conf"
            read -r
            ;;
        2|3|4|5)
            # Установить интервал
            local new_interval=5
            case $choice in
                2) new_interval=3 ;;
                3) new_interval=5 ;;
                4) new_interval=10 ;;
                5)
                    read -p "Введи интервал в минутах: " new_interval
                    if ! [[ "$new_interval" =~ ^[0-9]+$ ]] || [ "$new_interval" -lt 1 ]; then
                        echo "Неверный интервал"
                        read -r
                        return
                    fi
                    ;;
            esac

            sed -i "s/^AUTOSAVE_INTERVAL=.*/AUTOSAVE_INTERVAL=$new_interval/" "$sv_dir/.mbsft.conf"

            # Если уже включено - пересоздаем сервис
            if [ "$AUTOSAVE_ENABLED" = "yes" ]; then
                remove_autosave_service "$name"
                setup_autosave_service "$name" "$new_interval"
            else
                echo "✓ Интервал установлен: $new_interval мин"
            fi
            read -r
            ;;
        6|-1)
            return
            ;;
    esac
}

server_manage() {
    local name="$1"
    while true; do
        clear
        show_banner
        local status="СТОП"
        is_server_running "$name" && status="РАБОТАЕТ"

        # Получаем порт сервера
        read_server_conf "$BASE_DIR/$name"
        local server_port="$PORT"

        # Статусы сервисов (проверка через PID)
        local watchdog_status="выкл"
        local watchdog_real_status=""
        if [ "$WATCHDOG_ENABLED" = "yes" ]; then
            watchdog_status="вкл"
            if [ -f "$BASE_DIR/$name/.watchdog.pid" ] && kill -0 $(cat "$BASE_DIR/$name/.watchdog.pid") 2>/dev/null; then
                watchdog_real_status=" ✓"
            else
                watchdog_real_status=" ✗"
            fi
        fi

        local autosave_status="выкл"
        local autosave_real_status=""
        if [ "$AUTOSAVE_ENABLED" = "yes" ]; then
            autosave_status="вкл (${AUTOSAVE_INTERVAL}м)"
            if [ -f "$BASE_DIR/$name/.autosave.pid" ] && kill -0 $(cat "$BASE_DIR/$name/.autosave.pid") 2>/dev/null; then
                autosave_real_status=" ✓"
            else
                autosave_real_status=" ✗"
            fi
        fi

        local menu_items=("Запустить" "Остановить" "Консоль" "Автоперезапуск" "Автосохранение" "Debug" "Удалить" "Назад")

        # Формируем header для fzf с информацией о сервере
        local menu_header="$name [$status] :$server_port | Перезапуск: $watchdog_status$watchdog_real_status Сохранение: $autosave_status$autosave_real_status"

        local choice
        choice=$(arrow_menu menu_items "$menu_header")

        case $choice in
            0) server_start "$name"; read -p "Enter..." r ;;
            1) server_stop "$name"; read -p "Enter..." r ;;
            2) server_console "$name" ;;
            3) toggle_watchdog "$name" ;;
            4) configure_autosave "$name" ;;
            5) show_server_debug "$name" ;;
            6) server_delete "$name" && return ;;
            7|-1) return ;;
        esac
    done
}

list_servers() {
    while true; do
        clear
        show_banner
        echo "=== Мои серверы ==="
        local servers
        read -ra servers <<< "$(get_servers)"
        if [ ${#servers[@]} -eq 0 ]; then
            echo "Нет серверов."
            read -p "Нажми Enter..."
            return
        else
            local menu_items=()
            local server_names=()

            # Формируем пункты меню с портами
            for srv in "${servers[@]}"; do
                read_server_conf "$BASE_DIR/$srv"
                menu_items+=("$srv :$PORT")
                server_names+=("$srv")
            done
            menu_items+=("Назад")

            local choice
            choice=$(arrow_menu menu_items)

            if [ $choice -eq ${#servers[@]} ] || [ $choice -eq -1 ]; then
                return
            else
                server_manage "${server_names[$choice]}"
            fi
        fi
    done
}

uninstall_all() {
    read -p "УДАЛИТЬ ВСЕ ДАННЫЕ? (y/n): " yn
    if [[ "$yn" == "y" ]]; then
        rm -rf "$BASE_DIR"
        echo "Готово."
    fi
}

step_ssh() {
    while true; do
        clear
        show_banner
        echo "=== SSH Управление (Ubuntu container) ==="
        echo ""

        # Check SSH status
        local ssh_running="OFF"
        if pgrep -x sshd >/dev/null 2>&1; then
            ssh_running="ON (port 2222)"
        fi
        echo "SSH Status: $ssh_running"
        echo ""

        local menu_items=("Start/Restart SSH" "Добавить SSH ключ" "Статус подключения" "Сменить пароль (root)" "Починить SSH" "DEBUG sshd" "Назад")
        local choice
        choice=$(arrow_menu menu_items)

        case $choice in
            0)
                echo "=== Запуск SSH ==="
                # Create privilege separation directory if missing
                mkdir -p /run/sshd
                chmod 0755 /run/sshd
                
                # Start SSH
                /usr/sbin/sshd 2>/dev/null

                # Check if started
                if pgrep -x sshd >/dev/null 2>&1; then
                    echo "✓ SSH запущен на порту 2222"
                else
                    echo "✗ Не удалось запустить SSH"
                    echo "Попробуйте 'DEBUG sshd' для диагностики"
                fi
                read -r
                ;;
            1)
                clear
                show_banner
                echo "=== Добавить ключ ==="
                local key_items=("github (по нику)" "manual (вставка)" "reset (сброс)" "Назад")
                local kchoice
                kchoice=$(arrow_menu key_items)

                case $kchoice in
                    0)
                        read -p "GitHub username: " gh_user
                        if [ -n "$gh_user" ]; then
                            curl -fsL "https://github.com/${gh_user}.keys" >> "$HOME/.ssh/authorized_keys" && echo "Ключи добавлены." || echo "Ошибка."
                        else
                             echo "Пустой ник."
                        fi
                        read -r
                        ;;
                    1)
                        read -p "Вставь pub-ключ (ssh-rsa ...): " key
                        if [[ "$key" == ssh-* ]]; then
                            mkdir -p "$HOME/.ssh"
                            echo "$key" >> "$HOME/.ssh/authorized_keys"
                            echo "Добавлено."
                        else
                            echo "Не похоже на ключ."
                        fi
                        read -r
                        ;;
                    2)
                        echo "" > "$HOME/.ssh/authorized_keys"
                        echo "Ключи сброшены."
                        read -r
                        ;;
                esac
                ;;
            2)
                local user="root" # Inside proot we are root
                local local_ip=$(get_local_ip)
                local ext_ip=$(get_external_ip)
                echo "=== SSH Connection Info ==="
                echo "User:     $user"
                echo "Local IP: $local_ip"
                echo "Ext IP:   $ext_ip"
                echo ""
                echo "Connect from Termux:"
                echo "  ssh -p 2222 $user@localhost"
                echo ""
                echo "Connect from network:"
                echo "  ssh -p 2222 $user@$local_ip"
                echo ""
                echo "Note: SSH runs inside proot, port 2222"
                read -r
                ;;
            3)
                echo "=== Change root password ==="
                passwd
                read -r
                ;;
            4)
                echo "=== Repair SSH ==="
                pkill sshd 2>/dev/null
                mkdir -p /run/sshd
                chmod 0755 /run/sshd
                chmod 700 /root /root/.ssh 2>/dev/null
                chmod 600 /root/.ssh/authorized_keys 2>/dev/null
                ssh-keygen -A
                /usr/sbin/sshd 2>/dev/null
                echo "✓ SSH repaired and restarted"
                read -r
                ;;
            5)
                echo "=== DEBUG sshd ==="
                echo "Starting sshd in debug mode..."
                echo "Press Ctrl+C to exit"
                echo ""
                pkill sshd 2>/dev/null
                mkdir -p /run/sshd
                chmod 0755 /run/sshd
                /usr/sbin/sshd -D -d -e -p 2222
                /usr/sbin/sshd 2>/dev/null
                read -r
                ;;
            6|-1)
                return
                ;;
        esac
    done
}

install_code_server() {
    while true; do
        clear
        show_banner
        echo "=== Web IDE (code-server) ==="
        echo ""
        echo "Code-Server — это VS Code в браузере."
        echo "Работает через веб-интерфейс на настраиваемом порту."
        echo ""

        # Проверяем установлен ли code-server
        local cs_installed="НЕТ"
        local cs_running="СТОП"

        if command -v code-server &>/dev/null; then
            cs_installed="ДА"
            cs_version=$(code-server --version 2>/dev/null | head -1 || echo "unknown")
        fi

        # Проверяем запущен ли code-server
        if pgrep -f "code-server" >/dev/null 2>&1; then
            cs_running="РАБОТАЕТ"
        fi

        # Определяем текущий порт из конфига
        local cs_port="8080"
        if [ -f "$HOME/.config/code-server/config.yaml" ]; then
            cs_port=$(grep "bind-addr:" "$HOME/.config/code-server/config.yaml" | cut -d: -f3 || echo "8080")
            [ -z "$cs_port" ] && cs_port="8080"
        fi

        echo "Установлен: $cs_installed"
        [ "$cs_installed" != "НЕТ" ] && echo "Версия: $cs_version"
        echo "Статус: $cs_running"
        echo "Порт: $cs_port"
        echo ""

        local menu_items=()

        if [ "$cs_installed" = "НЕТ" ]; then
            menu_items+=("Установить code-server")
        else
            menu_items+=("Переустановить")
        fi

        menu_items+=("Запустить" "Остановить" "Настроить пароль" "Настроить порт" "Удалить" "Статус подключения" "Назад")

        local choice
        choice=$(arrow_menu menu_items)

        case $choice in
            0)
                # Установка/переустановка
                clear
                echo "=== Установка Code-Server ==="
                echo ""

                # Определяем архитектуру
                local arch=$(uname -m)
                local cs_arch=""

                case "$arch" in
                    aarch64|arm64)
                        cs_arch="arm64"
                        ;;
                    x86_64|amd64)
                        cs_arch="amd64"
                        ;;
                    armv7l)
                        cs_arch="armv7"
                        ;;
                    *)
                        echo "✗ Неподдерживаемая архитектура: $arch"
                        read -r
                        continue
                        ;;
                esac

                echo "Архитектура: $arch -> code-server $cs_arch"
                echo ""

                # Очистка старых файлов перед установкой
                echo "Очистка старых файлов..."
                pkill -f "code-server" 2>/dev/null
                rm -f /usr/local/bin/code-server 2>/dev/null
                rm -rf /opt/code-server 2>/dev/null
                npm uninstall -g code-server 2>/dev/null
                echo ""

                # Получаем последнюю версию из GitHub API
                echo "Получаю последнюю версию code-server..."
                local latest_version
                latest_version=$(curl -sL https://api.github.com/repos/coder/code-server/releases/latest | grep '"tag_name"' | cut -d'"' -f4)

                if [ -z "$latest_version" ]; then
                    echo "⚠ Не удалось получить версию из GitHub, использую v4.96.2"
                    latest_version="v4.96.2"
                fi

                echo "Версия: $latest_version"
                echo ""

                # Формируем URL для скачивания standalone версии
                local download_url="https://github.com/coder/code-server/releases/download/${latest_version}/code-server-${latest_version#v}-linux-${cs_arch}.tar.gz"

                echo "Скачиваю standalone версию code-server..."
                echo "(содержит встроенный Node.js, не требует установки)"
                echo ""

                # Создаем временную директорию
                local tmp_dir=$(mktemp -d)

                # Скачиваем
                if ! wget --show-progress -O "$tmp_dir/code-server.tar.gz" "$download_url"; then
                    echo "✗ Ошибка скачивания!"
                    echo "URL: $download_url"
                    rm -rf "$tmp_dir"
                    read -r
                    continue
                fi

                echo ""
                echo "Распаковка..."
                tar -xzf "$tmp_dir/code-server.tar.gz" -C "$tmp_dir"

                # Находим директорию с распакованными файлами
                local extracted_dir=$(find "$tmp_dir" -maxdepth 1 -type d -name "code-server-*" | head -1)

                if [ -z "$extracted_dir" ]; then
                    echo "✗ Ошибка распаковки!"
                    rm -rf "$tmp_dir"
                    read -r
                    continue
                fi

                # Перемещаем в /opt
                echo "Установка в систему..."
                mkdir -p /opt
                mv "$extracted_dir" /opt/code-server

                # Создаем симлинк в /usr/local/bin
                ln -sf /opt/code-server/bin/code-server /usr/local/bin/code-server

                # Очистка
                rm -rf "$tmp_dir"

                echo "✓ Code-Server установлен!"
                if command -v code-server &>/dev/null; then
                    echo "Версия: $(code-server --version 2>/dev/null | head -1 || echo 'установлен')"
                fi
                echo ""

                # Настройка порта
                echo "=== Настройка порта ==="
                local cs_port="8080"
                read -p "Порт для code-server [8080]: " user_port
                if [ -n "$user_port" ]; then
                    if [[ "$user_port" =~ ^[0-9]+$ ]] && [ "$user_port" -ge 1024 ] && [ "$user_port" -le 65535 ]; then
                        cs_port="$user_port"
                    else
                        echo "⚠ Неверный порт, использую 8080"
                        cs_port="8080"
                    fi
                fi
                echo "Порт установлен: $cs_port"
                echo ""

                # Настройка пароля
                echo "=== Настройка пароля ==="
                read -p "Установить пароль для входа? (y/n): " yn
                if [[ "$yn" == "y" ]]; then
                    read -sp "Введи пароль: " cs_password
                    echo ""

                    # Создаем конфиг
                    mkdir -p "$HOME/.config/code-server"
                    cat > "$HOME/.config/code-server/config.yaml" << EOF
bind-addr: 0.0.0.0:$cs_port
auth: password
password: $cs_password
cert: false
EOF
                    echo "✓ Пароль установлен"
                else
                    # Конфиг без пароля
                    mkdir -p "$HOME/.config/code-server"
                    cat > "$HOME/.config/code-server/config.yaml" << EOF
bind-addr: 0.0.0.0:$cs_port
auth: none
cert: false
EOF
                    echo "⚠ Пароль не установлен (доступ без аутентификации!)"
                fi

                echo ""
                read -p "Запустить code-server сейчас? (y/n): " yn
                if [[ "$yn" == "y" ]]; then
                    # Останавливаем если запущен
                    pkill -f "code-server" 2>/dev/null

                    # Запускаем в фоне
                    nohup code-server --config "$HOME/.config/code-server/config.yaml" > "$HOME/.code-server.log" 2>&1 &
                    sleep 2

                    if pgrep -f "code-server" >/dev/null 2>&1; then
                        local local_ip=$(get_local_ip)
                        # Читаем порт из конфига
                        local install_port="8080"
                        if [ -f "$HOME/.config/code-server/config.yaml" ]; then
                            install_port=$(grep "bind-addr:" "$HOME/.config/code-server/config.yaml" | cut -d: -f3 || echo "8080")
                            [ -z "$install_port" ] && install_port="8080"
                        fi
                        echo "✓ Code-Server запущен!"
                        echo ""
                        echo "Открой в браузере:"
                        echo "  http://$local_ip:$install_port"
                        echo ""
                    else
                        echo "✗ Не удалось запустить. Проверьте логи: $HOME/.code-server.log"
                    fi
                fi

                read -r
                ;;
            1)
                # Запуск
                if pgrep -f "code-server" >/dev/null 2>&1; then
                    echo "Code-Server уже запущен!"
                    read -r
                    continue
                fi

                if ! command -v code-server &>/dev/null; then
                    echo "Code-Server не установлен!"
                    read -r
                    continue
                fi

                echo "=== Запуск Code-Server ==="

                # Проверяем конфиг
                if [ ! -f "$HOME/.config/code-server/config.yaml" ]; then
                    echo "Конфиг не найден, создаю с паролем по умолчанию..."
                    mkdir -p "$HOME/.config/code-server"
                    cat > "$HOME/.config/code-server/config.yaml" << EOF
bind-addr: 0.0.0.0:8080
auth: password
password: admin123
cert: false
EOF
                    echo "⚠ Пароль по умолчанию: admin123"
                    echo "  (можно сменить через 'Настроить пароль')"
                fi

                # Запускаем
                nohup code-server --config "$HOME/.config/code-server/config.yaml" > "$HOME/.code-server.log" 2>&1 &
                sleep 2

                if pgrep -f "code-server" >/dev/null 2>&1; then
                    local local_ip=$(get_local_ip)
                    # Читаем порт из конфига
                    local start_port="8080"
                    if [ -f "$HOME/.config/code-server/config.yaml" ]; then
                        start_port=$(grep "bind-addr:" "$HOME/.config/code-server/config.yaml" | cut -d: -f3 || echo "8080")
                        [ -z "$start_port" ] && start_port="8080"
                    fi
                    echo "✓ Code-Server запущен!"
                    echo ""
                    echo "Открой в браузере:"
                    echo "  http://$local_ip:$start_port"
                else
                    echo "✗ Ошибка запуска. Логи: $HOME/.code-server.log"
                fi
                echo ""
                read -r
                ;;
            2)
                # Остановка
                echo "=== Остановка Code-Server ==="
                pkill -f "code-server" 2>/dev/null
                sleep 1

                if ! pgrep -f "code-server" >/dev/null 2>&1; then
                    echo "✓ Code-Server остановлен"
                else
                    echo "✗ Не удалось остановить (попробуйте: pkill -9 -f code-server)"
                fi
                read -r
                ;;
            3)
                # Настройка пароля
                echo "=== Настройка пароля ==="
                echo ""
                echo "1) Установить пароль"
                echo "2) Отключить пароль (небезопасно!)"
                echo "3) Назад"
                read -p "Выбор: " pwd_choice

                case $pwd_choice in
                    1)
                        read -sp "Введи новый пароль: " new_pwd
                        echo ""

                        mkdir -p "$HOME/.config/code-server"
                        cat > "$HOME/.config/code-server/config.yaml" << EOF
bind-addr: 0.0.0.0:8080
auth: password
password: $new_pwd
cert: false
EOF
                        echo "✓ Пароль обновлен"
                        echo "  (для применения перезапусти code-server)"
                        read -r
                        ;;
                    2)
                        mkdir -p "$HOME/.config/code-server"
                        cat > "$HOME/.config/code-server/config.yaml" << EOF
bind-addr: 0.0.0.0:8080
auth: none
cert: false
EOF
                        echo "✓ Пароль отключен"
                        echo "⚠ ВНИМАНИЕ: Доступ без аутентификации!"
                        read -r
                        ;;
                esac
                ;;
            4)
                # Настройка порта
                echo "=== Настройка порта ==="
                echo ""

                # Читаем текущий порт
                local current_port="8080"
                if [ -f "$HOME/.config/code-server/config.yaml" ]; then
                    current_port=$(grep "bind-addr:" "$HOME/.config/code-server/config.yaml" | cut -d: -f3 || echo "8080")
                    [ -z "$current_port" ] && current_port="8080"
                fi

                echo "Текущий порт: $current_port"
                echo ""
                read -p "Введи новый порт (например, 3000, 8081): " new_port

                # Проверяем валидность порта
                if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1024 ] || [ "$new_port" -gt 65535 ]; then
                    echo "✗ Неверный порт! Используй порт от 1024 до 65535"
                    read -r
                    continue
                fi

                # Обновляем конфиг
                if [ -f "$HOME/.config/code-server/config.yaml" ]; then
                    # Читаем текущий пароль/режим авторизации
                    local auth_type=$(grep "^auth:" "$HOME/.config/code-server/config.yaml" | cut -d: -f2 | xargs)
                    local current_password=""

                    if [ "$auth_type" = "password" ]; then
                        current_password=$(grep "^password:" "$HOME/.config/code-server/config.yaml" | cut -d: -f2- | xargs)
                    fi

                    # Пересоздаём конфиг с новым портом
                    if [ "$auth_type" = "password" ] && [ -n "$current_password" ]; then
                        cat > "$HOME/.config/code-server/config.yaml" << EOF
bind-addr: 0.0.0.0:$new_port
auth: password
password: $current_password
cert: false
EOF
                    else
                        cat > "$HOME/.config/code-server/config.yaml" << EOF
bind-addr: 0.0.0.0:$new_port
auth: none
cert: false
EOF
                    fi
                else
                    # Создаём новый конфиг
                    mkdir -p "$HOME/.config/code-server"
                    cat > "$HOME/.config/code-server/config.yaml" << EOF
bind-addr: 0.0.0.0:$new_port
auth: password
password: admin123
cert: false
EOF
                fi

                echo "✓ Порт изменён на: $new_port"
                echo "  (для применения перезапусти code-server)"
                read -r
                ;;
            5)
                # Удаление
                echo "=== Удаление Code-Server ==="
                read -p "ТОЧНО удалить code-server? (y/n): " yn
                if [[ "$yn" == "y" ]]; then
                    pkill -f "code-server" 2>/dev/null
                    echo "Удаление code-server..."
                    rm -f /usr/local/bin/code-server 2>/dev/null
                    rm -rf /opt/code-server 2>/dev/null
                    npm uninstall -g code-server 2>/dev/null
                    rm -rf "$HOME/.config/code-server"
                    rm -f "$HOME/.code-server.log"
                    echo "✓ Code-Server удален"
                fi
                read -r
                ;;
            6)
                # Статус подключения
                local local_ip=$(get_local_ip)
                local ext_ip=$(get_external_ip)

                # Читаем порт из конфига
                local cs_port="8080"
                if [ -f "$HOME/.config/code-server/config.yaml" ]; then
                    cs_port=$(grep "bind-addr:" "$HOME/.config/code-server/config.yaml" | cut -d: -f3 || echo "8080")
                    [ -z "$cs_port" ] && cs_port="8080"
                fi

                echo "=== Информация о подключении ==="
                echo ""
                echo "Локальная сеть:"
                echo "  http://$local_ip:$cs_port"
                echo ""
                echo "Внешний IP (требуется проброс портов):"
                echo "  http://$ext_ip:$cs_port"
                echo ""

                if [ -f "$HOME/.config/code-server/config.yaml" ]; then
                    echo "Конфигурация:"
                    cat "$HOME/.config/code-server/config.yaml"
                fi
                echo ""

                if [ -f "$HOME/.code-server.log" ]; then
                    echo "Последние 10 строк лога:"
                    tail -n 10 "$HOME/.code-server.log"
                fi
                echo ""
                read -r
                ;;
            7|-1)
                return
                ;;
        esac
    done
}

dashboard() {
    clear
    local local_ip=$(get_local_ip)
    local ext_ip=$(get_external_ip)
    local java_ver="Не установлена"
    if find_java; then
        java_ver=$("$JAVA_BIN" -version 2>&1 | head -1)
    fi
    local ssh_status="OFF"
    pgrep -x sshd >/dev/null 2>&1 && ssh_status="ON (2222)"

    local cs_status="OFF"
    local cs_port="8080"
    if [ -f "$HOME/.config/code-server/config.yaml" ]; then
        cs_port=$(grep "bind-addr:" "$HOME/.config/code-server/config.yaml" | cut -d: -f3 || echo "8080")
        [ -z "$cs_port" ] && cs_port="8080"
    fi
    pgrep -f "code-server" >/dev/null 2>&1 && cs_status="ON ($cs_port)"

    echo "=== DASHBOARD ==="
    echo "Java:        $java_ver"
    echo "Local:       $local_ip"
    echo "Ext:         $ext_ip"
    echo "SSH:         $ssh_status"
    echo "Code-Server: $cs_status"
    echo ""
    echo "Серверы:"
    local servers
    read -ra servers <<< "$(get_servers)"
    if [ ${#servers[@]} -eq 0 ]; then
        echo "  (нет серверов)"
    else
        printf "%-15s %-6s %-10s\n" "Имя" "Порт" "Статус"
        for srv in "${servers[@]}"; do
            local sv_dir="$BASE_DIR/$srv"
            local port=$(get_actual_port "$sv_dir")
            local stat="STOPPED"
            is_server_running "$srv" && stat="RUNNING"
            printf "%-15s %-6s %-10s\n" "$srv" "$port" "$stat"
        done
        echo ""
        echo "=== Ссылки для подключения ==="
        for srv in "${servers[@]}"; do
             if is_server_running "$srv"; then
                 local sv_dir="$BASE_DIR/$srv"
                 local port=$(get_actual_port "$sv_dir")
                 echo "Minecraft ($srv):"
                 echo "  $local_ip:$port"
                 echo ""
             fi
        done
        if [[ "$ssh_status" == *"ON"* ]]; then
             local user=$(whoami)
             echo "SSH (Terminal):"
             echo "  ssh -p 2222 $user@$local_ip"
             echo ""
        fi
        if [[ "$cs_status" == *"ON"* ]]; then
             echo "Web IDE (Code-Server):"
             echo "  http://$local_ip:$cs_port"
             echo ""
        fi
    fi
    echo ""
    read -p "Enter..."
}

UPDATE_URL="https://raw.githubusercontent.com/FLEXIY0/MBSFT/main/mbsft.sh"

self_update() {
    local manual="${1:-no}"

    if [ "$manual" = "yes" ]; then
        echo "Проверка обновлений..."
    fi

    # Скачиваем скрипт во временную переменную (с усиленным обходом кэша)
    local remote_content
    remote_content=$(curl -sL \
        -H 'Cache-Control: no-store, no-cache, must-revalidate' \
        -H 'Pragma: no-cache' \
        -H 'Expires: 0' \
        --no-keepalive \
        --max-time 10 \
        "${UPDATE_URL}?nocache=$(date +%s)_$$_${RANDOM}")

    if [ -z "$remote_content" ]; then
        if [ "$manual" = "yes" ]; then
            echo "Ошибка: не удалось проверить обновления."
            echo "Проверь подключение к интернету."
            read -r
        fi
        return
    fi

    # Парсим версию (ищем строку VERSION="...")
    local remote_ver
    remote_ver=$(echo "$remote_content" | grep '^VERSION=' | head -1 | cut -d'"' -f2)

    # Если версии отличаются и remote_ver не пустая
    if [ -n "$remote_ver" ] && [ "$remote_ver" != "$VERSION" ]; then
        echo ""
        echo ">>> Доступна новая версия: $remote_ver (Текущая: $VERSION)"
        read -p "Обновить сейчас? (y/n): " yn
        if [[ "$yn" == "y" ]]; then
            echo "Обновление..."
            # Перезаписываем текущий запущенный файл
            echo "$remote_content" > "$0"
            chmod +x "$0"

            echo "Перезапуск..."
            echo ""
            # Перезапускаем скрипт
            exec bash "$0" "$@"
        fi
    else
        if [ "$manual" = "yes" ]; then
            echo "✓ Установлена последняя версия: $VERSION"
            read -r
        fi
    fi
}

manual_check_update() {
    clear
    show_banner
    self_update "yes"
}

show_banner() {
    local ORANGE='\033[38;5;208m'
    local NC='\033[0m' # No Color

    echo -e "${ORANGE}███╗   ███╗██████╗ ███████╗███████╗████████╗${NC}"
    echo -e "${ORANGE}████╗ ████║██╔══██╗██╔════╝██╔════╝╚══██╔══╝${NC}"
    echo -e "${ORANGE}██╔████╔██║██████╔╝███████╗█████╗     ██║   ${NC}"
    echo -e "${ORANGE}██║╚██╔╝██║██╔══██╗╚════██║██╔══╝     ██║   ${NC}"
    echo -e "${ORANGE}██║ ╚═╝ ██║██████╔╝███████║██║        ██║   ${NC}"
    echo -e "${ORANGE}╚═╝     ╚═╝╚═════╝ ╚══════╝╚═╝        ╚═╝   ${NC}"
    echo -e "${ORANGE}      Minecraft Beta Server        ${NC}"
    echo -e "${ORANGE}        Ubuntu proot    ${NC}"
    echo -e "${ORANGE}              v$VERSION     ${NC}"
    echo ""
}

# =====================
# Main Loop
# =====================
main_loop() {
    # Проверка обновлений при старте
    self_update

    while true; do
        clear
        show_banner

        local servers
        read -ra servers <<< "$(get_servers)"
        local srv_count=${#servers[@]}

        local menu_items=("Установить зависимости" "Создать сервер" "Мои серверы ($srv_count)" "Дашборд" "SSH" "Web IDE (code-server)" "Проверить обновление" "Удалить всё" "Выход")

        # Header с версией и количеством серверов
        local menu_header="MBSFT v$VERSION | Серверов: $srv_count"

        local choice
        choice=$(arrow_menu menu_items "$menu_header")

        case $choice in
            0) step_deps ;;
            1) create_server ;;
            2) list_servers ;;
            3) dashboard ;;
            4) step_ssh ;;
            5) install_code_server ;;
            6) manual_check_update ;;
            7) uninstall_all ;;
            8|-1) exit 0 ;;
        esac
    done
}

main_loop
