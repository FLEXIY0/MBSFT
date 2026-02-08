#!/data/data/com.termux/files/usr/bin/bash

# ============================================
# MBSFT — Minecraft Beta Server For Termux
# Мульти-сервер менеджер (dialog UI)
# ============================================

# =====================
# Fix: curl | bash
# Если stdin — не терминал (пайп), сохраняем скрипт
# во временный файл и перезапускаем из файла
# =====================
if [ ! -t 0 ]; then
    TMPSCRIPT=$(mktemp "$HOME/.mbsft_install_XXXXXX.sh")
    cat > "$TMPSCRIPT"
    exec bash "$TMPSCRIPT" "$@"
    exit
fi

# Пути
BASE_DIR="$HOME/mbsft-servers"
VERSION="2.3"
# Java: будет найдена динамически
JAVA_BIN=""

# =====================
# Поиск Java
# =====================
find_java() {
    # Кэширование: если уже нашли, не проверяем снова
    if [ -n "$JAVA_BIN" ] && [ "$_JAVA_CHECKED" == "true" ]; then
        return 0
    fi
    
    # Сброс кэша версии
    _CACHED_JVER=""

    # 1. Проверяем Java 8 внутри proot-distro (Ubuntu)
    if command -v proot-distro &>/dev/null; then
        # Простая проверка: если java запускается и выдает версию
        if proot-distro login ubuntu -- java -version &>/dev/null; then
             # Дополнительно проверим, что это версия 1.8
             if proot-distro login ubuntu -- java -version 2>&1 | grep -q 'version "1\.8'; then
                 JAVA_BIN="proot-distro (ubuntu/java8)"
                 _JAVA_CHECKED="true"
                 return 0
             fi
        fi
    fi

    # 2. Проверяем нативную Java 8 (Hax4us/Package)
    # Если Proot не найден или там нет Java, ищем локально
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

    _JAVA_CHECKED="true" # Проверили, но не нашли
    JAVA_BIN=""
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

# =====================
# Тема dialog: чёрный фон, оранжевые акценты
# =====================
setup_dialog_theme() {
    local rc="$HOME/.mbsft_dialogrc"
    cat > "$rc" << 'THEOF'
# MBSFT dialog theme — dark + orange
aspect = 0
separate_widget = ""
tab_len = 0
visit_items = ON
use_shadow = ON
use_colors = ON
screen_color = (WHITE,BLACK,ON)
shadow_color = (BLACK,BLACK,ON)
dialog_color = (WHITE,BLACK,OFF)
title_color = (YELLOW,BLACK,ON)
border_color = (WHITE,BLACK,ON)
border2_color = (WHITE,BLACK,ON)
button_active_color = (BLACK,YELLOW,ON)
button_inactive_color = (WHITE,BLACK,OFF)
button_key_active_color = (BLACK,YELLOW,ON)
button_key_inactive_color = (YELLOW,BLACK,OFF)
button_label_active_color = (BLACK,YELLOW,ON)
button_label_inactive_color = (WHITE,BLACK,OFF)
inputbox_color = (WHITE,BLACK,OFF)
inputbox_border_color = (YELLOW,BLACK,ON)
inputbox_border2_color = (YELLOW,BLACK,ON)
searchbox_color = (WHITE,BLACK,OFF)
searchbox_title_color = (YELLOW,BLACK,ON)
searchbox_border_color = (YELLOW,BLACK,ON)
searchbox_border2_color = (YELLOW,BLACK,ON)
position_indicator_color = (YELLOW,BLACK,ON)
menubox_color = (WHITE,BLACK,OFF)
menubox_border_color = (YELLOW,BLACK,ON)
menubox_border2_color = (YELLOW,BLACK,ON)
item_color = (WHITE,BLACK,OFF)
item_selected_color = (BLACK,YELLOW,ON)
tag_color = (YELLOW,BLACK,OFF)
tag_selected_color = (BLACK,YELLOW,ON)
tag_key_color = (YELLOW,BLACK,ON)
tag_key_selected_color = (BLACK,YELLOW,ON)
check_color = (WHITE,BLACK,OFF)
check_selected_color = (BLACK,YELLOW,ON)
uarrow_color = (YELLOW,BLACK,ON)
darrow_color = (YELLOW,BLACK,ON)
itemhelp_color = (WHITE,BLACK,OFF)
form_active_text_color = (YELLOW,BLACK,ON)
form_text_color = (WHITE,BLACK,OFF)
form_item_readonly_color = (WHITE,BLACK,OFF)
gauge_color = (YELLOW,BLACK,ON)
THEOF
    export DIALOGRC="$rc"
}
setup_dialog_theme

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
    [ -n "$CACHED_LOCAL_IP" ] && echo "$CACHED_LOCAL_IP" && return
    local ip=""
    # 1. ip route — самый надёжный способ в Linux/Termux
    if [ -z "$ip" ] && command -v ip &>/dev/null; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    fi
    # 2. ifconfig — проверяем все интерфейсы
    if [ -z "$ip" ] && command -v ifconfig &>/dev/null; then
        ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | sed 's/addr://')
    fi
    # 3. termux-wifi-connectioninfo (нужен termux-api)
    if [ -z "$ip" ] && command -v termux-wifi-connectioninfo &>/dev/null; then
        ip=$(termux-wifi-connectioninfo 2>/dev/null | grep '"ip"' | cut -d'"' -f4)
        [ "$ip" = "0.0.0.0" ] && ip=""
    fi
    # 4. hostname -I
    if [ -z "$ip" ] && command -v hostname &>/dev/null; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    CACHED_LOCAL_IP="${ip:-не определён}"
    echo "$CACHED_LOCAL_IP"
}

# Внешний IP (через интернет)
get_external_ip() {
    [ -n "$CACHED_EXT_IP" ] && echo "$CACHED_EXT_IP" && return
    local ip=""
    if command -v curl &>/dev/null; then
        ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
    elif command -v wget &>/dev/null; then
        ip=$(wget -qO- --timeout=5 ifconfig.me 2>/dev/null)
    fi
    # Проверяем что результат похож на IP
    if echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        CACHED_EXT_IP="$ip"
        echo "$ip"
    else
        CACHED_EXT_IP="не определён"
        echo "не определён"
    fi
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
    local name="$1"
    # Сервер работает, только если статус (Detached) или (Attached)
    # Игнорируем (Remote or dead) и (Dead)
    screen -ls 2>/dev/null | grep "mbsft-$name" | grep -E '\(Detached\)|\(Attached\)' >/dev/null
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
# Генерация start.sh (использует proot-distro)
# Генерация start.sh (использует proot-distro или нативную java)
make_start_sh() {
    local sv_dir="$1" name="$2" ram="$3" port="$4" core="$5"
    
    # Флаги запуска в зависимости от ядра
    local args="nogui"
    if [ "$core" == "foxloader" ]; then
        args="--server"
    fi

    # Убедимся, что JAVA_BIN актуальна
    find_java

    if [[ "$JAVA_BIN" == *"proot-distro"* ]]; then
        # Режим Proot:
        cat > "$sv_dir/start.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
cd "$sv_dir"
echo "[$name] Запуск через Proot Ubuntu (Java 8)..."
echo "RAM: $ram, Port: $port, Core: $core"

# Запуск Java внутри Ubuntu
proot-distro login ubuntu --bind "$sv_dir:/server" -- java -Xmx$ram -Xms$ram -jar /server/server.jar $args
EOF
    else
        # Режим Native:
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

# =====================
# Выбор быстрого зеркала
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
    
    # Нужен curl для теста
    if ! command -v curl &>/dev/null; then
        pkg install -y curl &>/dev/null || return 1
    fi

    echo "Тест скорости (время отклика):"
    
    for url in "${mirrors[@]}"; do
        # Замеряем время скачивания Release файла (head request или маленький файл)
        local time
        time=$(curl -o /dev/null -s -w "%{time_total}" --connect-timeout 2 --max-time 3 "$url/dists/stable/Release")
        
        if [ -n "$time" ] && [ "$time" != "0.000000" ]; then
            echo "  $url -> ${time}s"
            # Сравниваем float (через bc или awk, но awk надежнее)
            local is_faster
            is_faster=$(echo "$time < $best_time" | awk '{print ($1)}')
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
        
        # Бэкап
        cp "$PREFIX/etc/apt/sources.list" "$PREFIX/etc/apt/sources.list.bak"
        # Запись
        echo "deb $best_mirror stable main" > "$PREFIX/etc/apt/sources.list"
        
        echo "Обновление списков..."
        pkg update -y
    else
        echo "Не удалось выбрать зеркало, оставляем текущее."
    fi
    echo ""
}

# Генерация start.sh (использует proot-distro)

install_java() {
    echo ""
    echo "=== Установка Java 8 (Proot-Distro/Ubuntu) ==="
    echo "Это самый надежный способ запуска Java 8 на Android."
    echo "Будет установлена Ubuntu (~80MB) и OpenJDK 8 внутри неё."
    echo ""

    # 1. Установка proot-distro
    if ! command -v proot-distro &>/dev/null; then
        echo "[1/4] Установка proot-distro..."
        
        # Сначала пробуем установить так
        pkg install -y proot-distro
        
        # Если не вышло — ищем зеркала
        if [ $? -ne 0 ]; then
            echo ""
            echo "ОШИБКА загрузки. Пробую найти быстрые зеркала..."
            optimize_mirrors
            pkg install -y proot-distro
            
            if [ $? -ne 0 ]; then
                echo ""
                echo "ОШИБКА: Не удалось установить proot-distro даже с новыми зеркалами!"
                echo "Попробуй выполнить 'termux-change-repo' вручную."
                return 1
            fi
        fi
    fi

    # 2. Установка Ubuntu
    if ! proot-distro list | grep -q "ubuntu.*installed"; then
        echo "[2/4] Скачивание и установка Ubuntu..."
        proot-distro install ubuntu
        if [ $? -ne 0 ]; then
            echo "ОШИБКА: Не удалось установить Ubuntu."
            return 1
        fi
    else
        echo "[2/4] Ubuntu уже установлена."
    fi

    # 3. Обновление пакетов внутри Ubuntu
    echo "[3/4] Обновление пакетов внутри Ubuntu (apt update)..."
    proot-distro login ubuntu -- apt update -y

    # 4. Установка Java 8
    echo "[4/4] Установка OpenJDK 8..."
    proot-distro login ubuntu -- apt install -y openjdk-8-jre-headless

    echo ""
    echo "Проверка..."
    if find_java; then
        echo "УСПЕХ: Java 8 установлена в Ubuntu!"
        return 0
    else
        echo "ОШИБКА: Java не найдена внутри Ubuntu."
        return 1
    fi
}

check_deps_status() {
    local result=""
    local all_ok=true

    # Java
    if find_java; then
        if [ -z "$_CACHED_JVER" ]; then
            if [[ "$JAVA_BIN" == *"proot"* ]]; then
                # Очистка вывода от ANSI кодов и Warning'ов
                _CACHED_JVER=$(proot-distro login ubuntu -- java -version 2>&1 | grep "version" | head -1 | sed 's/\x1b\[[0-9;]*m//g' | sed 's/Warning.*//g')
            else
                _CACHED_JVER=$("$JAVA_BIN" -version 2>&1 | head -1)
            fi
        fi
        result+="Java:              OK  ($_CACHED_JVER)\n"
    else
        result+="Java:              НЕТ\n"
        all_ok=false
    fi

    # screen
    if command -v screen &>/dev/null; then
        result+="screen:         OK\n"
    else
        result+="screen:         НЕТ\n"
        all_ok=false
    fi

    # wget
    if command -v wget &>/dev/null; then
        result+="wget:           OK\n"
    else
        result+="wget:           НЕТ\n"
        all_ok=false
    fi

    # openssh
    if command -v sshd &>/dev/null; then
        result+="openssh:        OK\n"
    else
        result+="openssh:        НЕТ\n"
    fi

    # iproute2
    if command -v ip &>/dev/null; then
        result+="iproute2 (ip):  OK\n"
    else
        result+="iproute2 (ip):  НЕТ\n"
    fi

    # net-tools
    if command -v ifconfig &>/dev/null; then
        result+="net-tools:      OK\n"
    else
        result+="net-tools:      НЕТ\n"
    fi

    # IP check
    local lip eip
    lip=$(get_local_ip)
    eip=$(get_external_ip)
    result+="\nЛокальный IP:   $lip\n"
    result+="Внешний IP:     $eip\n"

    echo -e "$result"
    $all_ok
}

run_install_deps() {
    clear
    echo "=== Установка зависимостей ==="
    echo ""
    pkg update -y && pkg upgrade -y

    echo ""
    echo "--- Основные пакеты ---"
    pkg install -y wget screen termux-services openssh

    echo ""
    echo "--- Сетевые утилиты ---"
    pkg install -y iproute2
    pkg install -y net-tools
    if ! command -v ifconfig &>/dev/null; then
        echo "ВНИМАНИЕ: net-tools не установился, пробую ещё раз..."
        apt install -y net-tools
    fi

    echo ""
    install_java
    local java_ok=$?

    echo ""
    echo "=== Результат ==="
    command -v ip &>/dev/null       && echo "  ip:        OK" || echo "  ip:        НЕТ"
    command -v ifconfig &>/dev/null && echo "  ifconfig:  OK" || echo "  ifconfig:  НЕТ"
    command -v screen &>/dev/null   && echo "  screen:    OK" || echo "  screen:    НЕТ"
    command -v wget &>/dev/null     && echo "  wget:      OK" || echo "  wget:      НЕТ"
    [ $java_ok -eq 0 ]             && echo "  java:      OK ($JAVA_BIN)" || echo "  java:      НЕТ"
    echo ""
    echo "Нажми Enter..."
    read -r
}

step_deps() {
    while true; do
        local status_text
        status_text=$(check_deps_status)
        local all_ok=$?

        local choice
        choice=$(dialog --title "Зависимости" \
            --menu "$status_text" 22 58 4 \
            "install" "Установить всё" \
            "check"   "Повторная проверка" \
            "---"     "─────────────────────" \
            "back"    "Назад" \
            3>&1 1>&2 2>&3)

        case $? in
            1|255) return ;;
        esac

        case $choice in
            install) run_install_deps ;;
            check)   continue ;;  # просто обновит статус при следующей итерации
            back)    return ;;
        esac
    done
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
    core_choice=$(dialog --title "Новый сервер: $name" --menu "Ядро сервера:" 13 54 5 \
        "poseidon"  "Project Poseidon (Beta 1.7.3)" \
        "reindev"   "Reindev 2.9_03 (Modded)" \
        "foxloader" "FoxLoader 1.2-alpha39 (Modding)" \
        "custom"    "Закину server.jar вручную" \
        3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && return

    mkdir -p "$sv_dir"

    if [ "$core_choice" == "poseidon" ]; then
        clear
        echo "=== Скачиваю Project Poseidon ==="
        if ! wget -O "$sv_dir/server.jar" "$POSEIDON_URL"; then
            rm -f "$sv_dir/server.jar"
            dialog --title "Ошибка" --msgbox "Не удалось скачать! Проверь интернет." 6 50
            return
        fi
    elif [ "$core_choice" == "reindev" ]; then
        clear
        echo "=== Скачиваю Reindev 2.9_03 ==="
        # Ссылка на релиз (тег servers)
        REINDEV_URL="https://github.com/FLEXIY0/MBSFT/releases/download/servers/reindev-server-2.9_03.jar"
        if ! wget -O "$sv_dir/server.jar" "$REINDEV_URL"; then
            rm -f "$sv_dir/server.jar"
            dialog --title "Ошибка" --msgbox "Не удалось скачать Reindev!\n\nУбедись, что файл есть в релизе 'servers'." 8 50
            return
        fi
    elif [ "$core_choice" == "foxloader" ]; then
        clear
        echo "=== Скачиваю FoxLoader ==="
        FOX_URL="https://github.com/Fox2Code/FoxLoader/releases/download/2.0-alpha39/foxloader-2.0-alpha39-server.jar"
        if ! wget -O "$sv_dir/server.jar" "$FOX_URL"; then
            rm -f "$sv_dir/server.jar"
            dialog --title "Ошибка" --msgbox "Не удалось скачать FoxLoader!" 6 50
            return
        fi
    else
        dialog --title "$name" --msgbox "Закинь server.jar в папку:\n\n$sv_dir/\n\nЗатем зайди в управление сервером." 10 54
    fi

    # Передаем тип ядра для правильной генерации start.sh (аргументы запуска)
    make_start_sh "$sv_dir" "$name" "$ram" "$port" "$core_choice"
    write_server_conf "$sv_dir" "$name" "$ram" "$port" "$core_choice"

    # Предварительно создаем server.properties, чтобы сервер сразу встал на нужный порт
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

    if [ -f "$sv_dir/server.jar" ]; then
        dialog --title "$name" --yesno "Сервер создан!\n\nЗапустить сейчас?\n(Сервер запустится в фоне, откроется консоль)" 10 54
        if [ $? -eq 0 ]; then
            clear
            echo "=== Запуск $name ==="
            server_start "$name"
            
            echo "Сервер запущен в screen!"
            echo "Сейчас откроется консоль."
            echo "Чтобы выйти из консоли (оставив сервер работать), нажми: Ctrl+A, затем D"
            echo "Чтобы остановить сервер: напиши 'stop' в консоли."
            echo ""
            echo "Нажми Enter..."
            read -r
            server_console "$name"
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
    
    # Очищаем мертвые сессии перед стартом
    screen -wipe >/dev/null 2>&1

    if is_server_running "$name"; then
        dialog --title "$name" --msgbox "Уже запущен!" 6 30
        return
    fi

    # Жесткая очистка "зомби" сессий (Remote or dead)
    # Находим все сессии с именем mbsft-$name, берем их PID и убиваем
    local zombie_pids
    zombie_pids=$(screen -ls | grep "mbsft-$name" | awk '{print $1}' | cut -d. -f1)
    
    if [ -n "$zombie_pids" ]; then
        echo "Обнаружены старые сессии, очистка..."
        for pid in $zombie_pids; do
            # Проверяем, число ли это (защита от ошибок парсинга)
            if [[ "$pid" =~ ^[0-9]+$ ]]; then
                kill -9 "$pid" 2>/dev/null
            fi
        done
        # После убийства процессов, wipe удалит сокеты
        screen -wipe >/dev/null 2>&1
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
    local sv_service="mbsft-${name}"
    local sv_screen="mbsft-${name}"

    dialog --title "УДАЛЕНИЕ" --yesno "Удалить сервер '$name' и ВСЕ его файлы?\n\n$sv_dir" 8 50
    [ $? -ne 0 ] && return 1

    local confirm
    confirm=$(dialog --title "ПОДТВЕРЖДЕНИЕ" --inputbox "Введи имя сервера для подтверждения:" 8 50 "" 3>&1 1>&2 2>&3)
    if [ "$confirm" != "$name" ]; then
        dialog --title "$TITLE" --msgbox "Отменено: имя не совпадает." 6 30
        return 1
    fi

    echo "Остановка процессов..."
    
    # 1. Остановка сервиса (runit)
    if [ -d "$PREFIX/var/service/$sv_service" ]; then
        sv down "$sv_service" 2>/dev/null || true
        # Даем время на остановку
        sleep 2
        command -v sv-disable &>/dev/null && sv-disable "$sv_service" 2>/dev/null || true
        rm -rf "$PREFIX/var/service/$sv_service"
    fi

    # 2. Остановка Screen сессии
    if screen -list | grep -q "\.${sv_screen}[[:space:]]"; then
        # Попытка мягкой остановки
        screen -S "$sv_screen" -p 0 -X stuff "stop$(printf '\r')" 2>/dev/null
        sleep 3
        # Принудительное убийство сессии
        screen -S "$sv_screen" -X quit 2>/dev/null
    fi
    
    # 3. Дополнительная проверка на зависшие процессы screen
    # (иногда screen -ls показывает мертвые сессии, чистим их)
    screen -wipe &>/dev/null

    # 4. Проверка процессов Java, запущенных из папки сервера
    # Это сложно сделать точно без pgrep -f с полным путем, но попробуем
    # Если pgrep есть
    if command -v pgrep &>/dev/null; then
        # Ищем процессы java, у которых cwd или аргументы содержат путь к серверу?
        # В Android/Termux сложно получить cwd чужого процесса без рута иногда.
        # Но мы можем поискать screen процесс с именем
        pgrep -f "mbsft-${name}" | xargs kill -9 2>/dev/null
    fi

    # Финальная проверка: существует ли папка сервиса или screen
    if [ -d "$PREFIX/var/service/$sv_service" ]; then
        dialog --title "ОШИБКА" --msgbox "Не удалось удалить сервис '$sv_service'!" 6 40
        return 1
    fi
    if screen -list | grep -q "\.${sv_screen}[[:space:]]"; then
        dialog --title "ОШИБКА" --msgbox "Не удалось остановить screen сессию '$sv_screen'!" 6 40
        return 1
    fi

    if [ -d "$sv_dir" ]; then
        rm -rf "$sv_dir"
        dialog --title "$TITLE" --msgbox "Сервер '$name' и все его данные удалены." 6 40
    else
        dialog --title "$TITLE" --msgbox "Папка сервера не найдена, но сервисы очищены." 6 40
    fi
    
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
        # Если кэш пуст, наполняем (хотя find_java должен был это сделать)
        [ -z "$_CACHED_JVER" ] && _CACHED_JVER="$($JAVA_BIN -version 2>&1 | head -1)"
        java_status="$_CACHED_JVER"
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
# Удаление всего
# =====================
uninstall_all() {
    dialog --title "ОПАСНО!" --yesno "Ты точно хочешь удалить ВСЕ серверы и данные MBSFT?\n\nЭто действие нельзя отменить!" 8 50
    [ $? -ne 0 ] && return

    dialog --title "ПОДТВЕРЖДЕНИЕ" --yesno "Последний шанс!\n\nУдалить папку $BASE_DIR?" 7 40
    [ $? -ne 0 ] && return

    clear
    echo "=== Остановка серверов ==="
    
    # Получаем список
    local servers
    read -ra servers <<< "$(get_servers)"
    
    for srv in "${servers[@]}"; do
        [ -z "$srv" ] && continue
        echo "Останавливаю $srv..."
        server_stop_silent "$srv"
        # Удаляем сервис runit (если есть)
        local sv_service_dir="$PREFIX/var/service/mbsft-$srv"
        if [ -d "$sv_service_dir" ]; then
             rm "$sv_service_dir"
            # Перезагружаем сервис-менеджер, если нужно, но rm достаточно
        fi
    done
    
    echo "=== Удаление файлов ==="
    rm -rf "$BASE_DIR"
    
    dialog --title "Готово" --msgbox "Все данные MBSFT удалены.\n\nЗависимости (Java, dialog) остались." 8 45
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
            "uninstall" "Удалить всё (СБРОС)" \
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
            uninstall) uninstall_all ;;
        esac
    done

    clear
}

# =====================
# Main
# =====================
# Очистка мертвых сессий screen
screen -wipe >/dev/null 2>&1

main_loop
