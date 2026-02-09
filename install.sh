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
    exec bash "$TMPSCRIPT" "$@"
    exit
fi

# Пути
BASE_DIR="$HOME/mbsft-servers"
VERSION="2.4-cli"
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
CREATED=$(date '+%Y-%m-%d %H:%M')
EOF
}

read_server_conf() {
    local dir="$1"
    if [ -f "$dir/.mbsft.conf" ]; then
        source "$dir/.mbsft.conf"
    else
        NAME=$(basename "$dir")
        RAM="1G"; PORT="25565"; CORE="unknown"; CREATED="?"
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
proot-distro login ubuntu --bind "$sv_dir:/server" -- java -Xmx$ram -Xms$ram -jar /server/server.jar $args
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
    pkg install -y -o Dpkg::Options::="--force-confnew" wget tmux termux-services openssh iproute2 net-tools
    install_java
    echo ""
    echo "Нажми Enter..."
    read -r
}

step_deps() {
    while true; do
        clear
        check_deps_status
        echo "Меню зависимостей:"
        select opt in "Установить всё" "Назад"; do
            case $opt in
                "Установить всё") run_install_deps; break ;;
                "Назад") return ;;
                *) echo "Неверный выбор";;
            esac
        done
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
    local ram="1G"
    select r in "512M" "1G" "2G" "4G"; do
        if [ -n "$r" ]; then
            ram=$r
            break
        fi
    done

    local default_port=$(next_free_port)
    read -p "Порт сервера [$default_port]: " port
    port=${port:-$default_port}

    echo "Ядро сервера:"
    local core_choice
    local poseidon_url="https://github.com/FLEXIY0/MBSFT/releases/download/servers/project-poseidon-1.1.8.jar"
    select c in "poseidon" "reindev" "foxloader" "custom"; do
        if [ -n "$c" ]; then
            core_choice=$c
            break
        fi
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
    echo "Нажми 'Ctrl+B, затем D' чтобы выйти из консоли (оставить сервер работать)."
    sleep 2
    tmux attach-session -t "mbsft-$name"
    clear
}

server_delete() {
    local name="$1"
    read -p "ТОЧНО удалить сервер $name? (y/n): " yn
    if [[ "$yn" != "y" ]]; then return; fi
    
    server_stop "$name" 2>/dev/null
    rm -rf "$BASE_DIR/$name"
    if [ -d "$PREFIX/var/service/mbsft-$name" ]; then
        sv down "mbsft-$name" 2>/dev/null
        rm -rf "$PREFIX/var/service/mbsft-$name"
    fi
    echo "Удалено."
    read -r
}

server_manage() {
    local name="$1"
    while true; do
        clear
        local status="СТОП"
        is_server_running "$name" && status="РАБОТАЕТ"
        echo "=== Управление: $name [$status] ==="
        select opt in "Запустить" "Остановить" "Консоль" "Удалить" "Назад"; do
            case $opt in
                "Запустить") server_start "$name"; read -p "Enter..." r; break ;;
                "Остановить") server_stop "$name"; read -p "Enter..." r; break ;;
                "Консоль") server_console "$name"; break ;;
                "Удалить") server_delete "$name"; return ;;
                "Назад") return ;;
                *) echo "Неверно";;
            esac
        done
    done
}

list_servers() {
    while true; do
        clear
        echo "=== Мои серверы ==="
        local servers
        read -ra servers <<< "$(get_servers)"
        if [ ${#servers[@]} -eq 0 ]; then
            echo "Нет серверов."
            read -r
            return
        fi

        local opts=("${servers[@]}" "Назад")
        select srv in "${opts[@]}"; do
            if [[ "$srv" == "Назад" ]]; then
                return
            elif [ -n "$srv" ]; then
                server_manage "$srv"
                break
            fi
        done
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
        echo "=== SSH Управление ==="
        select opt in "Включить SSH + Автозапуск" "Добавить SSH ключ" "Статус подключения" "Сменить пароль" "Починить SSH" "DEBUG sshd" "Назад"; do
            case $opt in
                "Включить SSH + Автозапуск")
                    echo "=== Настройка SSH ==="
                    export DEBIAN_FRONTEND=noninteractive
                    pkg install -y -o Dpkg::Options::="--force-confnew" openssh termux-services
                    sv-enable sshd
                    if ! pgrep sshd >/dev/null; then sshd; fi
                    
                    read -p "Хочешь задать пароль? (y/n): " yn
                    if [[ "$yn" == "y" ]]; then
                        passwd
                    fi
                    echo "SSH включен."
                    read -r
                    break
                    ;;
                "Добавить SSH ключ")
                    echo "Как добавить ключ?"
                    select kopt in "github" "manual" "reset" "back"; do
                        case $kopt in
                            "github")
                                read -p "GitHub username: " gh_user
                                if [ -n "$gh_user" ]; then
                                    curl -fsL "https://github.com/${gh_user}.keys" >> "$HOME/.ssh/authorized_keys" && echo "Ключи добавлены." || echo "Ошибка."
                                fi
                                break
                                ;;
                            "manual")
                                read -p "Вставь pub-ключ (ssh-rsa ...): " key
                                if [[ "$key" == ssh-* ]]; then
                                    mkdir -p "$HOME/.ssh"
                                    echo "$key" >> "$HOME/.ssh/authorized_keys"
                                    echo "Добавлено."
                                else
                                    echo "Не похоже на ключ."
                                fi
                                break
                                ;;
                            "reset")
                                echo "" > "$HOME/.ssh/authorized_keys"
                                echo "Ключи сброшены."
                                break
                                ;;
                            "back") break ;;
                        esac
                    done
                    break
                    ;;
                "Статус подключения")
                    local user=$(whoami)
                    local local_ip=$(get_local_ip)
                    local ext_ip=$(get_external_ip)
                    echo "User: $user"
                    echo "Local: $local_ip"
                    echo "External: $ext_ip"
                    echo "Connect: ssh -p 8022 $user@$local_ip"
                    read -r
                    break
                    ;;
                "Сменить пароль")
                    passwd
                    read -r
                    break
                    ;;
                "Починить SSH")
                    echo "Ремонт..."
                    pkill sshd
                    sv-disable sshd 2>/dev/null
                    chmod 700 "$HOME" "$HOME/.ssh"
                    chmod 600 "$HOME/.ssh/authorized_keys" 2>/dev/null
                    ssh-keygen -A
                    source "$PREFIX/etc/profile.d/start-services.sh" 2>/dev/null
                    sv-enable sshd
                    sshd
                    echo "Готово."
                    read -r
                    break
                    ;;
                "DEBUG sshd")
                    echo "Запускаю sshd в режиме отладки..."
                    echo "Нажми Ctrl+C для выхода."
                    pkill sshd
                    /data/data/com.termux/files/usr/bin/sshd -D -d -e -p 8022
                    sshd
                    break
                    ;;
                "Назад") return ;;
            esac
        done
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
    fi
    echo ""
    read -p "Enter..."
}

# =====================
# Main Loop
# =====================
main_loop() {
    while true; do
        clear
        echo "=== MBSFT v${VERSION} CLI ==="
        echo "1) Установить зависимости"
        echo "2) Создать сервер"
        echo "3) Мои серверы"
        echo "4) Дашборд"
        echo "5) SSH"
        echo "6) Удалить всё"
        echo "7) Выход"
        read -p "Выбор: " choice
        case $choice in
            1) step_deps ;;
            2) create_server ;;
            3) list_servers ;;
            4) dashboard ;;
            5) step_ssh ;;
            6) uninstall_all ;;
            7) exit 0 ;;
            *) echo "Неверно." ;;
        esac
    done
}

main_loop
