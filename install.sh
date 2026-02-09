#!/data/data/com.termux/files/usr/bin/bash

# ============================================
# MBSFT — Minecraft Beta Server For Termux
# CLI Version (No dialog dependency)
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
BASE_DIR="$HOME/mbsft-servers"
VERSION="3.4"
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

    # 1. Проверяем Java 8 внутри proot-distro (Ubuntu)
    if command -v proot-distro &>/dev/null; then
        if proot-distro login ubuntu -- java -version &>/dev/null; then
             if proot-distro login ubuntu -- java -version 2>&1 | grep -q 'version "1\.8'; then
                 JAVA_BIN="proot-distro (ubuntu/java8)"
                 _JAVA_CHECKED="true"
                 return 0
             fi
        fi
    fi

    # 2. Проверяем нативную Java 8
    local paths=(
        "$PREFIX/share/jdk8/bin/java"
        "/data/data/com.termux/files/usr/lib/jvm/java-8-openjdk/bin/java"
        "$HOME/.jdk8/bin/java"
    )
    
    check_version() {
        "$1" -version 2>&1 | grep -q 'version "1\.8'
    }

    for p in "${paths[@]}"; do
        if [ -x "$p" ] && check_version "$p"; then
            JAVA_BIN="$p"
            _JAVA_CHECKED="true"
            return 0
        fi
    done

    _JAVA_CHECKED="true"
    JAVA_BIN=""
    return 1
}

# Проверка Termux
if [ ! -d "/data/data/com.termux" ]; then
    echo "Ошибка: Этот скрипт только для Termux!"
    exit 1
fi

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
    if [ -z "$ip" ] && command -v termux-wifi-connectioninfo &>/dev/null; then
        ip=$(termux-wifi-connectioninfo 2>/dev/null | grep '"ip"' | cut -d'"' -f4)
        [ "$ip" = "0.0.0.0" ] && ip=""
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
        pkg install -y fzf || {
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

    find_java

    if [[ "$JAVA_BIN" == *"proot-distro"* ]]; then
        cat > "$sv_dir/start.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
cd "$sv_dir"
echo "[$name] Запуск через Proot Ubuntu (Java 8)..."
echo "RAM: $ram, Port: $port, Core: $core"
# Важно! Сначала заходим в папку внутри proot, потом запускаем java
proot-distro login ubuntu --bind "$sv_dir:/server" -- bash -c "cd /server && java -Xmx$ram -Xms$ram -jar server.jar $args"
EOF
    else
        cat > "$sv_dir/start.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
cd "$sv_dir"
echo "[$name] Запуск (Native Java 8)..."
echo "RAM: $ram, Port: $port, Core: $core"
"$JAVA_BIN" -Xmx$ram -Xms$ram -jar server.jar $args
EOF
    fi
    chmod +x "$sv_dir/start.sh"
}

optimize_mirrors() {
    echo "=== Поиск быстрого зеркала ==="
    local mirrors=(
        "https://grimler.se/termux/termux-main"
        "https://mirror.mwt.me/termux/main"
        "https://termux.librehat.com/apt/termux-main"
        "https://packages.termux.dev/apt/termux-main"
    )
    local best_mirror=""
    local best_time=10000

    if ! command -v curl &>/dev/null; then
        pkg install -y -o Dpkg::Options::="--force-confnew" curl &>/dev/null || return 1
    fi

    echo "Тест скорости (время отклика):"
    for url in "${mirrors[@]}"; do
        local time
        time=$(curl -o /dev/null -s -w "%{time_total}" --connect-timeout 2 --max-time 3 "$url/dists/stable/Release")
        if [ -n "$time" ] && [ "$time" != "0.000000" ]; then
            echo "  $url -> ${time}s"
            local is_faster
            is_faster=$(awk -v t="$time" -v b="$best_time" 'BEGIN {print (t < b)}')
            if [ "$is_faster" -eq 1 ]; then
                best_time=$time
                best_mirror=$url
            fi
        else
            echo "  $url -> Тайм-аут"
        fi
    done

    if [ -n "$best_mirror" ] && [ "$best_time" != "10000" ]; then
        echo ""
        echo "Лучшее зеркало: $best_mirror"
        echo "Применяю..."
        cp "$PREFIX/etc/apt/sources.list" "$PREFIX/etc/apt/sources.list.bak"
        echo "deb $best_mirror stable main" > "$PREFIX/etc/apt/sources.list"
        echo "Обновление списков..."
        pkg update -y -o Dpkg::Options::="--force-confnew"
    else
        echo "Не удалось выбрать зеркало, оставляем текущее."
    fi
    echo ""
}

install_java() {
    echo ""
    echo "=== Установка Java 8 (Proot-Distro/Ubuntu) ==="
    echo "Это самый надежный способ запуска Java 8 на Android."
    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none

    echo "[0/4] Проверка скорости зеркал..."
    if ! command -v proot-distro &>/dev/null; then
        optimize_mirrors
    fi

    # 1. Установка proot-distro
    if ! command -v proot-distro &>/dev/null; then
        echo "[1/4] Установка proot-distro..."
        pkg install -y -o Dpkg::Options::="--force-confnew" proot-distro
        if [ $? -ne 0 ]; then
            echo "ОШИБКА: Не удалось установить proot-distro!"
            echo "1. Выполни: termux-change-repo"
            echo "2. Выбери самое быстрое зеркало"
            return 1
        fi
    fi

    # 2. Установка Ubuntu
    if [ ! -d "$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu" ]; then
        echo "[2/4] Скачивание и установка Ubuntu..."
        local alt_urls=(
            "https://github.com/termux/proot-distro/releases/download/v4.30.1/ubuntu-questing-aarch64-pd-v4.30.1.tar.xz"
            "https://mirror.ghproxy.com/https://github.com/termux/proot-distro/releases/download/v4.30.1/ubuntu-questing-aarch64-pd-v4.30.1.tar.xz"
            "https://cdn.jsdelivr.net/gh/termux/proot-distro@v4.30.1/releases/download/v4.30.1/ubuntu-questing-aarch64-pd-v4.30.1.tar.xz"
        )
        local cache_dir="$PREFIX/var/lib/proot-distro/dlcache"
        local tarball="$cache_dir/ubuntu-questing-aarch64-pd-v4.30.1.tar.xz"
        mkdir -p "$cache_dir"

        local downloaded=false
        for url in "${alt_urls[@]}"; do
            echo "Загрузка: $url"
            if timeout 120 wget -q --show-progress --progress=bar:force -O "$tarball" "$url"; then
                downloaded=true
                break
            fi
        done

        if [ "$downloaded" = true ]; then
            echo "Установка Ubuntu из кеша..."
            proot-distro install ubuntu
        else
            echo "Стандартная установка Ubuntu..."
            proot-distro install ubuntu
        fi
    else
        echo "[2/4] Ubuntu уже установлена."
    fi

    echo "[3/4] Обновление пакетов внутри Ubuntu..."
    proot-distro login ubuntu -- apt update -y

    echo "[4/4] Установка OpenJDK 8..."
    proot-distro login ubuntu -- apt install -y openjdk-8-jre-headless

    if find_java; then
        echo "УСПЕХ: Java 8 установлена!"
        return 0
    else
        echo "ОШИБКА: Java не найдена."
        return 1
    fi
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
    echo ""
}

run_install_deps() {
    clear
    echo "=== Установка зависимостей ==="
    export DEBIAN_FRONTEND=noninteractive
    pkg update -y && pkg upgrade -y -o Dpkg::Options::="--force-confnew"
    pkg install -y -o Dpkg::Options::="--force-confnew" wget tmux openssh iproute2 net-tools termux-api

    install_java
    echo ""
    echo "=== Установка MBSFT в систему ==="
    cp "$0" "$PREFIX/bin/mbsft"
    chmod +x "$PREFIX/bin/mbsft"
    echo "Теперь можно запускать командой: mbsft"

    echo ""
    echo "Нажми Enter..."
    read -r
}

run_uninstall_deps() {
    clear
    echo "=== Удаление зависимостей ==="
    echo "ВНИМАНИЕ! Будут удалены:"
    echo " - Java (Ubuntu/proot-distro и все данные внутри)"
    echo " - Пакеты: wget, tmux, openssh, iproute2, net-tools, termux-api"
    echo ""
    echo "Если вы подключены по SSH — соединение разорвется!"
    read -p "Точно продолжить? (y/n): " yn
    if [[ "$yn" != "y" ]]; then return; fi

    echo "Удаление Ubuntu..."
    if command -v proot-distro &>/dev/null; then
        proot-distro remove ubuntu 2>/dev/null
    fi

    echo "Удаление пакетов..."
    pkg uninstall -y proot-distro wget tmux openssh iproute2 net-tools termux-api

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
# WATCHDOG SERVICE (простой фоновый процесс)
# =====================

setup_watchdog_service() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"
    local pid_file="$sv_dir/.watchdog.pid"
    local log_file="$sv_dir/.watchdog.log"

    # Если уже запущен - останавливаем
    if [ -f "$pid_file" ]; then
        local old_pid=$(cat "$pid_file")
        kill "$old_pid" 2>/dev/null
        rm -f "$pid_file"
    fi

    # Запускаем фоновый процесс мониторинга
    nohup bash -c "
        while true; do
            if ! tmux has-session -t 'mbsft-$name' 2>/dev/null; then
                echo \"[\$(date)] Server crashed, restarting in 5 seconds...\"
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
}

toggle_watchdog() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"

    read_server_conf "$sv_dir"

    if [ "$WATCHDOG_ENABLED" = "yes" ]; then
        # Отключаем
        remove_watchdog_service "$name"
        sed -i 's/^WATCHDOG_ENABLED=.*/WATCHDOG_ENABLED=no/' "$sv_dir/.mbsft.conf"
        echo "✓ Автоперезапуск отключен"
    else
        # Включаем
        setup_watchdog_service "$name"
        sed -i 's/^WATCHDOG_ENABLED=.*/WATCHDOG_ENABLED=yes/' "$sv_dir/.mbsft.conf"
    fi
    read -r
}

# =====================
# AUTOSAVE SERVICE (простой фоновый процесс)
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
        kill "$old_pid" 2>/dev/null
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
}

show_server_debug() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"

    clear
    show_banner
    echo "=== DEBUG: $name ==="
    echo ""

    # 1. Конфиг файл
    echo "--- Конфиг (.mbsft.conf) ---"
    if [ -f "$sv_dir/.mbsft.conf" ]; then
        cat "$sv_dir/.mbsft.conf"
    else
        echo "Файл не найден!"
    fi
    echo ""

    # 2. PID файлы
    echo "--- PID файлы ---"
    echo -n "Watchdog PID файл: "
    if [ -f "$sv_dir/.watchdog.pid" ]; then
        local wpid=$(cat "$sv_dir/.watchdog.pid")
        echo "$wpid"
        echo -n "  Процесс живой? "
        if kill -0 "$wpid" 2>/dev/null; then
            echo "✓ ДА (PID $wpid запущен)"
        else
            echo "✗ НЕТ (процесс не существует)"
        fi
    else
        echo "Не существует"
    fi

    echo -n "Autosave PID файл: "
    if [ -f "$sv_dir/.autosave.pid" ]; then
        local apid=$(cat "$sv_dir/.autosave.pid")
        echo "$apid"
        echo -n "  Процесс живой? "
        if kill -0 "$apid" 2>/dev/null; then
            echo "✓ ДА (PID $apid запущен)"
        else
            echo "✗ НЕТ (процесс не существует)"
        fi
    else
        echo "Не существует"
    fi
    echo ""

    # 3. Логи
    echo "--- Последние 5 строк логов ---"
    if [ -f "$sv_dir/.watchdog.log" ]; then
        echo "Watchdog:"
        tail -5 "$sv_dir/.watchdog.log" 2>/dev/null || echo "  (пусто)"
    else
        echo "Watchdog: лог не существует"
    fi

    if [ -f "$sv_dir/.autosave.log" ]; then
        echo "Autosave:"
        tail -5 "$sv_dir/.autosave.log" 2>/dev/null || echo "  (пусто)"
    else
        echo "Autosave: лог не существует"
    fi
    echo ""

    # 4. Процессы bash
    echo "--- Связанные bash процессы ---"
    ps aux | grep -E "mbsft-$name|bash.*$sv_dir" | grep -v grep || echo "(нет)"

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
            echo "✓ Автосохранение отключено"
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

        # Статусы сервисов (проверка через pid файлы)
        local watchdog_status="выкл"
        local watchdog_real_status=""
        if [ "$WATCHDOG_ENABLED" = "yes" ]; then
            watchdog_status="вкл"
            local wd_pid_file="$BASE_DIR/$name/.watchdog.pid"
            if [ -f "$wd_pid_file" ] && kill -0 $(cat "$wd_pid_file") 2>/dev/null; then
                watchdog_real_status=" ✓"
            else
                watchdog_real_status=" ✗"
            fi
        fi

        local autosave_status="выкл"
        local autosave_real_status=""
        if [ "$AUTOSAVE_ENABLED" = "yes" ]; then
            autosave_status="вкл (${AUTOSAVE_INTERVAL}м)"
            local as_pid_file="$BASE_DIR/$name/.autosave.pid"
            if [ -f "$as_pid_file" ] && kill -0 $(cat "$as_pid_file") 2>/dev/null; then
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
        echo "=== SSH Управление ==="

        local menu_items=("Включить SSH + Автозапуск" "Добавить SSH ключ" "Статус подключения" "Сменить пароль" "Починить SSH" "DEBUG sshd" "Назад")
        local choice
        choice=$(arrow_menu menu_items)

        case $choice in
            0)
                echo "=== Настройка SSH ==="
                export DEBIAN_FRONTEND=noninteractive
                pkg install -y -o Dpkg::Options::="--force-confnew" openssh

                # Создаем автозапуск через boot-скрипт
                mkdir -p "$HOME/.termux/boot"
                cat > "$HOME/.termux/boot/start-sshd.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
sshd
EOF
                chmod +x "$HOME/.termux/boot/start-sshd.sh"

                if ! pgrep sshd >/dev/null; then sshd; fi

                read -p "Хочешь задать пароль? (y/n): " yn
                if [[ "$yn" == "y" ]]; then
                    passwd
                fi
                echo "SSH включен. Автозапуск настроен."
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
                local user=$(whoami)
                local local_ip=$(get_local_ip)
                local ext_ip=$(get_external_ip)
                echo "User: $user"
                echo "Local: $local_ip"
                echo "External: $ext_ip"
                echo "Connect: ssh -p 8022 $user@$local_ip"
                read -r
                ;;
            3)
                passwd
                read -r
                ;;
            4)
                echo "Ремонт..."
                pkill sshd
                chmod 700 "$HOME" "$HOME/.ssh"
                chmod 600 "$HOME/.ssh/authorized_keys" 2>/dev/null
                ssh-keygen -A
                sshd
                echo "Готово."
                read -r
                ;;
            5)
                echo "Запускаю sshd в режиме отладки..."
                echo "Нажми Ctrl+C для выхода."
                pkill sshd
                /data/data/com.termux/files/usr/bin/sshd -D -d -e -p 8022
                sshd
                read -r
                ;;
            6|-1)
                return
                ;;
        esac
    done
}

cleanup_old_services() {
    clear
    show_banner
    echo "=== Очистка старых сервисов ==="
    echo ""
    echo "Это удалит:"
    echo "  - Старые runit процессы (runsvdir, svlogd)"
    echo "  - Старые сервисы из $PREFIX/var/service"
    echo "  - Старые pid файлы"
    echo "  - Сбросит конфиги сервисов"
    echo ""
    read -p "Продолжить? (y/n): " yn
    if [[ "$yn" != "y" ]]; then return; fi

    echo ""
    echo "Остановка старых процессов..."
    pkill -9 runsvdir 2>/dev/null
    pkill -9 svlogd 2>/dev/null
    pkill -9 runsv 2>/dev/null
    pkill -f "mbsft-.*watchdog" 2>/dev/null
    pkill -f "mbsft-.*autosave" 2>/dev/null
    sleep 1

    echo "Удаление старых сервисов..."
    rm -rf "$PREFIX/var/service/mbsft-"* 2>/dev/null

    echo "Очистка pid файлов..."
    rm -f ~/mbsft-servers/*/.watchdog.pid 2>/dev/null
    rm -f ~/mbsft-servers/*/.autosave.pid 2>/dev/null

    echo "Сброс конфигов..."
    for conf in ~/mbsft-servers/*/.mbsft.conf; do
        if [ -f "$conf" ]; then
            sed -i 's/^WATCHDOG_ENABLED=.*/WATCHDOG_ENABLED=no/' "$conf"
            sed -i 's/^AUTOSAVE_ENABLED=.*/AUTOSAVE_ENABLED=no/' "$conf"
        fi
    done

    echo ""
    echo "✓ Очистка завершена!"
    echo ""
    echo "Теперь можно заново включить нужные сервисы."
    read -r
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
    pidof sshd &>/dev/null && ssh_status="ON (8022)"

    echo "=== DASHBOARD ==="
    echo "Java:    $java_ver"
    echo "Local:   $local_ip"
    echo "Ext:     $ext_ip"
    echo "SSH:     $ssh_status"
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
             echo "  ssh -p 8022 $user@$local_ip"
             echo ""
        fi
    fi
    echo ""
    read -p "Enter..."
}

UPDATE_URL="https://raw.githubusercontent.com/FLEXIY0/MBSFT/main/install.sh"

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

            # Если мы не в bin, но mbsft есть в bin — обновим и его
            if [ "$0" != "$PREFIX/bin/mbsft" ] && [ -f "$PREFIX/bin/mbsft" ]; then
                echo "$remote_content" > "$PREFIX/bin/mbsft"
                chmod +x "$PREFIX/bin/mbsft"
                echo "Системная команда также обновлена."
            fi

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
    echo -e "${ORANGE}            For Termux  ${NC}"
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

        local menu_items=("Установить зависимости" "Создать сервер" "Мои серверы ($srv_count)" "Дашборд" "SSH" "Очистка старых сервисов" "Проверить обновление" "Удалить всё" "Выход")

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
            5) cleanup_old_services ;;
            6) manual_check_update ;;
            7) uninstall_all ;;
            8|-1) exit 0 ;;
        esac
    done
}

main_loop
