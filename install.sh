#!/data/data/com.termux/files/usr/bin/bash

# ============================================
# MBSFT — Minecraft Beta Server For Termux
# Мульти-сервер менеджер (dialog UI)
# ============================================

# =====================
# Автообновление
# =====================
SCRIPT_URL="https://raw.githubusercontent.com/FLEXIY0/MBSFT/main/install.sh"
SCRIPT_PATH="$HOME/install.sh"
CURRENT_VERSION="2.3"

auto_update() {
    # Пропускаем если скрипт запущен из временного файла
    if [[ "$0" == *".mbsft_install_"* ]] || [[ "$0" == "/tmp/"* ]]; then
        return 0
    fi
    
    # Проверяем наличие curl или wget
    local downloader=""
    if command -v curl &>/dev/null; then
        downloader="curl"
    elif command -v wget &>/dev/null; then
        downloader="wget"
    else
        return 0  # Нет загрузчика, пропускаем обновление
    fi
    
    # Скачиваем новую версию во временный файл
    local tmp_script=$(mktemp "$HOME/.mbsft_update_XXXXXX.sh")
    
    if [ "$downloader" = "curl" ]; then
        curl -sL "$SCRIPT_URL" -o "$tmp_script" 2>/dev/null || { rm -f "$tmp_script"; return 0; }
    else
        wget -qO "$tmp_script" "$SCRIPT_URL" 2>/dev/null || { rm -f "$tmp_script"; return 0; }
    fi
    
    # Проверяем что файл скачался
    if [ ! -s "$tmp_script" ]; then
        rm -f "$tmp_script"
        return 0
    fi
    
    # Извлекаем версию из скачанного файла
    local remote_version=$(grep '^CURRENT_VERSION=' "$tmp_script" | head -1 | cut -d'"' -f2)
    
    # Сравниваем версии
    if [ -n "$remote_version" ] && [ "$remote_version" != "$CURRENT_VERSION" ]; then
        echo "╔════════════════════════════════════════╗"
        echo "║   Обновление MBSFT                     ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        echo "  Текущая версия:  $CURRENT_VERSION"
        echo "  Новая версия:    $remote_version"
        echo ""
        echo "  Обновляю скрипт..."
        
        # Сохраняем новую версию
        cp "$tmp_script" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        rm -f "$tmp_script"
        
        echo "  ✓ Обновление завершено!"
        echo ""
        echo "  Перезапускаю скрипт..."
        sleep 2
        
        # Перезапускаем обновлённый скрипт
        exec bash "$SCRIPT_PATH" "$@"
        exit 0
    fi
    
    rm -f "$tmp_script"
}

# Запускаем автообновление
auto_update "$@"

# =====================
# Fix: curl | bash
# Если stdin — не терминал (пайп), сохраняем скрипт
# в постоянный файл и перезапускаем из него
# =====================
if [ ! -t 0 ]; then
    # Сохраняем в домашнюю директорию
    cat > "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║   MBSFT установлен!                    ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "  Скрипт сохранён: $SCRIPT_PATH"
    echo "  Для повторного запуска используй:"
    echo ""
    echo "    bash install.sh"
    echo ""
    echo "  Запускаю..."
    sleep 2
    exec bash "$SCRIPT_PATH" "$@"
    exit
fi

# Пути
BASE_DIR="$HOME/mbsft-servers"
POSEIDON_URL="https://ci.project-poseidon.com/job/Project-Poseidon/lastSuccessfulBuild/artifact/target/poseidon-1.1.8.jar"
JAVA8_INSTALL_SCRIPT="https://raw.githubusercontent.com/MasterDevX/Termux-Java/master/installjava"
VERSION="2.3"

# Java: будет найдена динамически
JAVA_BIN=""

# =====================
# Поиск Java
# =====================
find_java() {
    # Приоритет: только Java 8
    local paths=(
        "/data/data/com.termux/files/usr/lib/jvm/java-8-openjdk/bin/java"
        "/data/data/com.termux/files/usr/lib/jvm/java-8/bin/java"
        "$HOME/.jdk8/bin/java"
        "$PREFIX/share/jdk8/bin/java"
    )
    for p in "${paths[@]}"; do
        if [ -x "$p" ]; then
            JAVA_BIN="$p"
            return 0
        fi
    done
    # Последний шанс — java в PATH (только если это Java 8)
    if command -v java &>/dev/null; then
        local java_ver=$(java -version 2>&1 | head -1)
        if echo "$java_ver" | grep -q "1.8\|openjdk-8"; then
            JAVA_BIN="$(command -v java)"
            return 0
        fi
    fi
    return 1
}

# =====================
# Bootstrap: dialog
# =====================
if ! command -v dialog &>/dev/null; then
    echo "[MBSFT] Устанавливаю dialog..."
    pkg install -y dialog 2>/dev/null || {
        apt update -y 2>/dev/null && apt install -y dialog 2>/dev/null
    }
fi

if ! command -v dialog &>/dev/null; then
    echo "Ошибка: не удалось установить dialog"
    exit 1
fi

# Проверка Termux
if [ ! -d "/data/data/com.termux" ]; then
    dialog --title "Ошибка" --msgbox "Этот скрипт только для Termux!" 6 40
    exit 1
fi

mkdir -p "$BASE_DIR"
find_java

# =====================
# Утилиты
# =====================

TITLE="MBSFT v${VERSION}"

# Локальный IP (для подключения по Wi-Fi)
get_local_ip() {
    local ip=""
    # 1. net-tools (ifconfig) — ставим принудительно в deps
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

# Внешний IP
get_external_ip() {
    local ip=""
    if command -v curl &>/dev/null; then
        ip=$(curl -s --max-time 4 ifconfig.me 2>/dev/null)
    fi
    echo "${ip:-не определён}"
}

# Основная функция — локальный IP (для Minecraft / SSH)
get_ip() {
    get_local_ip
}

deps_installed() {
    find_java && command -v screen &>/dev/null && command -v wget &>/dev/null
}

validate_name() {
    echo "$1" | grep -qE '^[a-zA-Z0-9_-]+$'
}

# Конфиг сервера
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

# Патч конфигов сервера
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

# Генерация start.sh (использует найденную java)
make_start_sh() {
    local sv_dir="$1" name="$2" ram="$3" port="$4"
    find_java
    cat > "$sv_dir/start.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
cd "$sv_dir"
echo "[$name] Запуск (RAM: $ram, Port: $port)..."
"$JAVA_BIN" -Xmx$ram -Xms$ram -jar server.jar nogui
EOF
    chmod +x "$sv_dir/start.sh"
}

# =====================
# 1. Зависимости
# =====================

install_java() {
    echo ""
    echo "=== Установка Java 8 ==="
    echo ""

    # Способ 1: MasterDevX/Termux-Java (основной метод)
    echo "[1/3] Устанавливаю Java 8 через Termux-Java..."
    if ! command -v wget &>/dev/null; then
        echo "Устанавливаю wget..."
        pkg install -y wget
    fi
    
    # Скачиваем и запускаем установщик
    local tmpscript="/tmp/installjava_$$"
    if wget -O "$tmpscript" "$JAVA8_INSTALL_SCRIPT" 2>/dev/null; then
        bash "$tmpscript"
        rm -f "$tmpscript"
        if find_java; then
            echo ""
            echo "✓ OK: Java 8 установлена — $JAVA_BIN"
            return 0
        fi
    fi

    # Способ 2: openjdk-8 из tur-repo
    echo ""
    echo "[2/3] Пробую openjdk-8 (tur-repo)..."
    pkg install -y tur-repo 2>/dev/null
    pkg install -y openjdk-8
    if find_java; then
        echo ""
        echo "✓ OK: Java 8 найдена — $JAVA_BIN"
        return 0
    fi

    # Способ 3: прямая установка через pkg
    echo ""
    echo "[3/3] Пробую pkg install openjdk-8..."
    pkg install -y openjdk-8
    if find_java; then
        echo ""
        echo "✓ OK: Java 8 найдена — $JAVA_BIN"
        return 0
    fi

    echo ""
    echo "✗ ОШИБКА: Не удалось установить Java 8!"
    echo "Попробуй вручную:"
    echo "  pkg install wget && wget https://raw.githubusercontent.com/MasterDevX/Termux-Java/master/installjava && bash installjava"
    echo "  или: pkg install tur-repo && pkg install openjdk-8"
    return 1
}

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
# 2. Создание сервера
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
# 3. Быстрое создание
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
# 4. Мои серверы
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

server_console() {
    local name="$1"
    if ! is_server_running "$name"; then
        dialog --title "$name" --msgbox "Сервер не запущен!" 6 34
        return
    fi
    dialog --title "$name" --msgbox "Откроется консоль.\n\nВыход: Ctrl+A, затем D" 8 40
    screen -r "mbsft-${name}"
}

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

server_create_service() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"
    local sv_service="mbsft-${name}"
    local SVDIR="$PREFIX/var/service/$sv_service"

    mkdir -p "$SVDIR/log"

    cat > "$SVDIR/run" << SEOF
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

    cat > "$SVDIR/log/run" << LEOF
#!/data/data/com.termux/files/usr/bin/sh
mkdir -p "$sv_dir/logs/sv"
exec svlogd -tt "$sv_dir/logs/sv"
LEOF
    chmod +x "$SVDIR/log/run"
    command -v sv-enable &>/dev/null && sv-enable "$sv_service" 2>/dev/null || true

    dialog --title "$name" --msgbox "Сервис '$sv_service' создан!\n\nАвтозапуск + автосохранение\n\nУправление:\n  sv up $sv_service\n  sv down $sv_service" 12 48
}

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

    is_server_running "$name" && {
        screen -S "mbsft-${name}" -p 0 -X stuff "stop$(printf '\r')" 2>/dev/null
        sleep 3
        screen -S "mbsft-${name}" -X quit 2>/dev/null
    }

    local sv_service="mbsft-${name}"
    if [ -d "$PREFIX/var/service/$sv_service" ]; then
        sv down "$sv_service" 2>/dev/null || true
        command -v sv-disable &>/dev/null && sv-disable "$sv_service" 2>/dev/null || true
        rm -rf "$PREFIX/var/service/$sv_service"
    fi

    rm -rf "$sv_dir"
    dialog --title "$TITLE" --msgbox "Сервер '$name' удалён." 6 38
    return 0
}

# =====================
# 5. Дашборд
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
# 6. SSH
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

# =====================
# Main
# =====================
main_loop
