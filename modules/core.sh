#!/data/data/com.termux/files/usr/bin/bash
# ============================================
# MBSFT Core Module
# Базовые переменные и утилиты
# ============================================

# Версия и пути
export MBSFT_VERSION="2.4"
export BASE_DIR="$HOME/mbsft-servers"
export POSEIDON_URL="https://ci.project-poseidon.com/job/Project-Poseidon/lastSuccessfulBuild/artifact/target/poseidon-1.1.8.jar"
export JAVA8_INSTALL_SCRIPT="https://raw.githubusercontent.com/MasterDevX/Termux-Java/master/installjava"
export SCRIPT_URL="https://raw.githubusercontent.com/FLEXIY0/MBSFT/main/install.sh"
export SCRIPT_PATH="$HOME/install.sh"
export MODULES_DIR="$HOME/.mbsft/modules"

# Java путь (будет найден динамически)
export JAVA_BIN=""

# UI
export TITLE="MBSFT v${MBSFT_VERSION}"

# =====================
# Утилиты для работы с сетью
# =====================

get_local_ip() {
    local ip=""
    # 1. net-tools (ifconfig)
    if command -v ifconfig &>/dev/null; then
        ip=$(ifconfig wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}')
        [ -z "$ip" ] && ip=$(ifconfig eth0 2>/dev/null | grep 'inet ' | awk '{print $2}')
    fi
    # 2. iproute2
    if [ -z "$ip" ] && command -v ip &>/dev/null; then
        ip=$(ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        [ -z "$ip" ] && ip=$(ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    fi
    # 3. termux-wifi-connectioninfo
    if [ -z "$ip" ] && command -v termux-wifi-connectioninfo &>/dev/null; then
        ip=$(termux-wifi-connectioninfo 2>/dev/null | grep '"ip"' | cut -d'"' -f4)
    fi
    echo "${ip:-не определён}"
}

get_external_ip() {
    local ip=""
    if command -v curl &>/dev/null; then
        ip=$(curl -s --max-time 4 ifconfig.me 2>/dev/null)
    fi
    echo "${ip:-не определён}"
}

get_ip() {
    get_local_ip
}

# =====================
# Валидация
# =====================

validate_name() {
    echo "$1" | grep -qE '^[a-zA-Z0-9_-]+$'
}

# =====================
# Конфигурация сервера
# =====================

write_server_conf() {
    local dir="$1" name="$2" ram="$3" port="$4" core="$5"
    cat > "$dir/.mbsft.conf" <<EOF
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

# =====================
# Список серверов
# =====================

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
    screen -list 2>/dev/null | grep -q "\.mbsft-${1}[[:space:]]"
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

# =====================
# Инициализация
# =====================

init_core() {
    mkdir -p "$BASE_DIR"
    mkdir -p "$MODULES_DIR"
}
