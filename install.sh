#!/data/data/com.termux/files/usr/bin/bash

# ============================================
# MBSFT — Minecraft Beta Server For Termux
# Мульти-сервер менеджер
# ============================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Пути
BASE_DIR="$HOME/mbsft-servers"
JAVA8_PATH="/data/data/com.termux/files/usr/lib/jvm/java-8-openjdk/bin/java"
POSEIDON_URL="https://ci.project-poseidon.com/job/Project-Poseidon/lastSuccessfulBuild/artifact/target/poseidon-1.1.8.jar"
VERSION="2.0"

# =====================
# Утилиты
# =====================

check_termux() {
    if [ ! -d "/data/data/com.termux" ]; then
        echo -e "${RED}Этот скрипт только для Termux!${NC}"
        exit 1
    fi
}

get_ip() {
    local ip=""
    if command -v ifconfig &>/dev/null; then
        ip=$(ifconfig wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}')
    fi
    if [ -z "$ip" ] && command -v ip &>/dev/null; then
        ip=$(ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    fi
    echo "${ip:-?}"
}

show_logo() {
    clear
    echo -e "${CYAN}"
    echo " __  __  ____   _____ ______ _______ "
    echo "|  \/  ||  _ \ / ____|  ____|__   __|"
    echo "| \  / || |_) | (___ | |__     | |   "
    echo "| |\/| ||  _ < \___ \|  __|    | |   "
    echo "| |  | || |_) |____) | |       | |   "
    echo "|_|  |_||____/|_____/|_|       |_|   "
    echo -e "${BOLD}Minecraft Beta Server For Termux v${VERSION}${NC}"
    echo ""
}

pause() {
    read -p "Enter для продолжения..."
}

# Валидация имени сервера
validate_name() {
    local name="$1"
    if [ -z "$name" ]; then
        return 1
    fi
    if ! echo "$name" | grep -qE '^[a-zA-Z0-9_-]+$'; then
        echo -e "${RED}Имя может содержать только: буквы, цифры, _ и -${NC}"
        return 1
    fi
    if [ ${#name} -gt 32 ]; then
        echo -e "${RED}Имя слишком длинное (макс 32 символа)${NC}"
        return 1
    fi
    return 0
}

# =====================
# Конфиг сервера
# =====================

# Записать конфиг сервера
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

# Прочитать конфиг сервера
read_server_conf() {
    local dir="$1"
    if [ -f "$dir/.mbsft.conf" ]; then
        source "$dir/.mbsft.conf"
    else
        NAME=$(basename "$dir")
        RAM="1G"
        PORT="25565"
        CORE="unknown"
        CREATED="?"
    fi
}

# Получить список всех серверов (папки с .mbsft.conf или server.jar)
get_servers() {
    local servers=()
    if [ -d "$BASE_DIR" ]; then
        for d in "$BASE_DIR"/*/; do
            [ -d "$d" ] || continue
            if [ -f "$d/.mbsft.conf" ] || [ -f "$d/server.jar" ]; then
                servers+=("$(basename "$d")")
            fi
        done
    fi
    echo "${servers[@]}"
}

# Проверить запущен ли сервер (screen сессия)
is_server_running() {
    local name="$1"
    if screen -list 2>/dev/null | grep -q "\.mbsft-${name}[[:space:]]"; then
        return 0
    fi
    return 1
}

# Получить порт из server.properties
get_actual_port() {
    local dir="$1"
    if [ -f "$dir/server.properties" ]; then
        grep "server-port=" "$dir/server.properties" 2>/dev/null | cut -d= -f2
    else
        read_server_conf "$dir"
        echo "$PORT"
    fi
}

# =====================
# Проверка зависимостей
# =====================

deps_installed() {
    [ -f "$JAVA8_PATH" ] && command -v screen &>/dev/null && command -v wget &>/dev/null
}

step_deps() {
    show_logo
    echo -e "${CYAN}${BOLD}[Установка зависимостей]${NC}"
    echo ""

    if deps_installed; then
        echo -e "${GREEN}Все зависимости уже установлены!${NC}"
        echo -e "  Java 8: $($JAVA8_PATH -version 2>&1 | head -1)"
        pause
        return
    fi

    echo -e "${CYAN}Обновление пакетов...${NC}"
    pkg update -y && pkg upgrade -y

    echo -e "${CYAN}Установка...${NC}"
    pkg install -y tur-repo
    pkg install -y wget screen termux-services openssh net-tools
    pkg install -y openjdk-8

    if [ -f "$JAVA8_PATH" ]; then
        echo -e "${GREEN}Готово! Java 8: $($JAVA8_PATH -version 2>&1 | head -1)${NC}"
    else
        echo -e "${RED}Java 8 не найдена. Перезапусти Termux и попробуй снова.${NC}"
    fi
    pause
}

# =====================
# Создание сервера
# =====================

create_server() {
    show_logo
    echo -e "${CYAN}${BOLD}[Создание нового сервера]${NC}"
    echo ""

    # Проверка зависимостей
    if ! deps_installed; then
        echo -e "${RED}Сначала установи зависимости (пункт 1)!${NC}"
        pause
        return
    fi

    # Имя
    read -p "Имя сервера (англ, без пробелов): " SV_NAME
    if ! validate_name "$SV_NAME"; then
        pause
        return
    fi

    local SV_DIR="$BASE_DIR/$SV_NAME"

    if [ -d "$SV_DIR" ] && [ -f "$SV_DIR/server.jar" ]; then
        echo -e "${RED}Сервер '$SV_NAME' уже существует!${NC}"
        pause
        return
    fi

    # RAM
    read -p "RAM (512M / 1G / 2G) [1G]: " SV_RAM
    SV_RAM=${SV_RAM:-1G}
    if ! echo "$SV_RAM" | grep -qE '^[0-9]+[MG]$'; then
        echo -e "${RED}Неверный формат RAM!${NC}"
        pause
        return
    fi

    # Порт
    local DEFAULT_PORT=25565
    # Авто-подбор свободного порта
    local existing_ports=()
    for srv in $(get_servers); do
        local p
        p=$(get_actual_port "$BASE_DIR/$srv")
        existing_ports+=("$p")
    done
    while printf '%s\n' "${existing_ports[@]}" | grep -qx "$DEFAULT_PORT" 2>/dev/null; do
        DEFAULT_PORT=$((DEFAULT_PORT + 1))
    done

    read -p "Порт [$DEFAULT_PORT]: " SV_PORT
    SV_PORT=${SV_PORT:-$DEFAULT_PORT}
    if ! echo "$SV_PORT" | grep -qE '^[0-9]+$'; then
        echo -e "${RED}Порт должен быть числом!${NC}"
        pause
        return
    fi

    # Ядро
    echo ""
    echo "Ядро:"
    echo "  1) Project Poseidon (Beta 1.7.3 — рекомендуется)"
    echo "  2) Закину server.jar вручную"
    read -p "Выбор [1]: " CORE_CHOICE
    CORE_CHOICE=${CORE_CHOICE:-1}

    mkdir -p "$SV_DIR"

    local CORE_NAME="custom"
    if [ "$CORE_CHOICE" == "1" ]; then
        CORE_NAME="poseidon"
        echo -e "${CYAN}Скачиваю Project Poseidon...${NC}"
        if ! wget -O "$SV_DIR/server.jar" "$POSEIDON_URL"; then
            echo -e "${RED}Ошибка загрузки!${NC}"
            rm -f "$SV_DIR/server.jar"
            pause
            return
        fi
        echo -e "${GREEN}Ядро скачано.${NC}"
    else
        echo ""
        echo -e "Закинь ${BOLD}server.jar${NC} в папку:"
        echo -e "${CYAN}$SV_DIR/${NC}"
        echo ""
        read -p "Файл на месте? (y/n): " READY
        if [ "$READY" != "y" ] || [ ! -f "$SV_DIR/server.jar" ]; then
            echo -e "${YELLOW}Когда закинешь — зайди в управление сервером.${NC}"
        fi
    fi

    # start.sh
    cat > "$SV_DIR/start.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
cd "$SV_DIR"
echo "[$SV_NAME] Запуск (RAM: $SV_RAM, Port: $SV_PORT)..."
"$JAVA8_PATH" -Xmx$SV_RAM -Xms$SV_RAM -jar server.jar nogui
EOF
    chmod +x "$SV_DIR/start.sh"

    # Конфиг
    write_server_conf "$SV_DIR" "$SV_NAME" "$SV_RAM" "$SV_PORT" "$CORE_NAME"

    echo ""
    echo -e "${GREEN}${BOLD}Сервер '$SV_NAME' создан!${NC}"
    echo -e "  Папка: $SV_DIR"
    echo -e "  RAM:   $SV_RAM"
    echo -e "  Порт:  $SV_PORT"
    echo ""

    # Предлагаем первый запуск
    if [ -f "$SV_DIR/server.jar" ]; then
        read -p "Выполнить первый запуск (генерация конфигов)? (y/n) [y]: " FIRST_RUN
        FIRST_RUN=${FIRST_RUN:-y}
        if [ "$FIRST_RUN" == "y" ]; then
            echo -e "${YELLOW}Дождись загрузки, затем Ctrl+C...${NC}"
            cd "$SV_DIR" && ./start.sh || true

            # EULA
            if [ -f "$SV_DIR/eula.txt" ]; then
                sed -i 's/eula=false/eula=true/g' "$SV_DIR/eula.txt"
                echo -e "${GREEN}EULA принята.${NC}"
            fi

            # Патч server.properties
            if [ -f "$SV_DIR/server.properties" ]; then
                sed -i "s/online-mode=true/online-mode=false/g" "$SV_DIR/server.properties"
                sed -i "s/verify-names=true/verify-names=false/g" "$SV_DIR/server.properties"
                sed -i "s/server-ip=.*/server-ip=/g" "$SV_DIR/server.properties"
                sed -i "s/server-port=.*/server-port=$SV_PORT/g" "$SV_DIR/server.properties"
                echo -e "${GREEN}Настройки применены (online-mode=false, port=$SV_PORT).${NC}"
            fi
        fi
    fi

    pause
}

# =====================
# Быстрое создание
# =====================

quick_create() {
    show_logo
    echo -e "${CYAN}${BOLD}[Быстрое создание сервера]${NC}"
    echo ""

    if ! deps_installed; then
        echo -e "${YELLOW}Сначала установлю зависимости...${NC}"
        pkg update -y && pkg upgrade -y
        pkg install -y tur-repo
        pkg install -y wget screen termux-services openssh net-tools
        pkg install -y openjdk-8
        if [ ! -f "$JAVA8_PATH" ]; then
            echo -e "${RED}Java 8 не установилась!${NC}"
            pause
            return
        fi
        echo -e "${GREEN}Зависимости ✓${NC}"
        echo ""
    fi

    read -p "Имя сервера: " SV_NAME
    if ! validate_name "$SV_NAME"; then
        pause
        return
    fi

    local SV_DIR="$BASE_DIR/$SV_NAME"
    if [ -d "$SV_DIR" ] && [ -f "$SV_DIR/server.jar" ]; then
        echo -e "${RED}Сервер '$SV_NAME' уже существует!${NC}"
        pause
        return
    fi

    # Авто-подбор порта
    local SV_PORT=25565
    local existing_ports=()
    for srv in $(get_servers); do
        local p
        p=$(get_actual_port "$BASE_DIR/$srv")
        existing_ports+=("$p")
    done
    while printf '%s\n' "${existing_ports[@]}" | grep -qx "$SV_PORT" 2>/dev/null; do
        SV_PORT=$((SV_PORT + 1))
    done

    echo ""
    echo "Ядро:    Project Poseidon (Beta 1.7.3)"
    echo "RAM:     1G"
    echo "Порт:    $SV_PORT"
    echo ""
    read -p "Создать? (y/n) [y]: " CONFIRM
    CONFIRM=${CONFIRM:-y}
    [ "$CONFIRM" != "y" ] && return

    mkdir -p "$SV_DIR"

    # Скачиваем ядро
    echo -e "${CYAN}Скачиваю ядро...${NC}"
    if ! wget -O "$SV_DIR/server.jar" "$POSEIDON_URL"; then
        echo -e "${RED}Ошибка загрузки!${NC}"
        rm -f "$SV_DIR/server.jar"
        pause
        return
    fi

    # start.sh
    cat > "$SV_DIR/start.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
cd "$SV_DIR"
echo "[$SV_NAME] Запуск (RAM: 1G, Port: $SV_PORT)..."
"$JAVA8_PATH" -Xmx1G -Xms1G -jar server.jar nogui
EOF
    chmod +x "$SV_DIR/start.sh"

    write_server_conf "$SV_DIR" "$SV_NAME" "1G" "$SV_PORT" "poseidon"

    # Первый запуск
    echo -e "${YELLOW}Первый запуск для генерации конфигов (Ctrl+C для остановки)...${NC}"
    cd "$SV_DIR" && ./start.sh || true

    # Патч
    if [ -f "$SV_DIR/eula.txt" ]; then
        sed -i 's/eula=false/eula=true/g' "$SV_DIR/eula.txt"
    fi
    if [ -f "$SV_DIR/server.properties" ]; then
        sed -i "s/online-mode=true/online-mode=false/g" "$SV_DIR/server.properties"
        sed -i "s/verify-names=true/verify-names=false/g" "$SV_DIR/server.properties"
        sed -i "s/server-ip=.*/server-ip=/g" "$SV_DIR/server.properties"
        sed -i "s/server-port=.*/server-port=$SV_PORT/g" "$SV_DIR/server.properties"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}Сервер '$SV_NAME' готов!${NC}"
    echo -e "  Папка: $SV_DIR"
    echo -e "  Порт:  $SV_PORT"
    echo -e "  Запуск через меню: Мои серверы → $SV_NAME → Запустить"
    pause
}

# =====================
# Список серверов
# =====================

list_servers_menu() {
    while true; do
        show_logo
        echo -e "${BOLD}[Мои серверы]${NC}"
        echo ""

        local servers
        read -ra servers <<< "$(get_servers)"

        if [ ${#servers[@]} -eq 0 ] || [ -z "${servers[0]}" ]; then
            echo -e "${DIM}  Серверов пока нет. Создай первый!${NC}"
            echo ""
            pause
            return
        fi

        # Заголовок таблицы
        printf "  ${BOLD}%-4s %-20s %-8s %-6s %-12s${NC}\n" "#" "Имя" "Порт" "RAM" "Статус"
        echo "  --------------------------------------------------------"

        local i=1
        for srv in "${servers[@]}"; do
            local sv_dir="$BASE_DIR/$srv"
            read_server_conf "$sv_dir"

            local actual_port
            actual_port=$(get_actual_port "$sv_dir")

            local status_text
            if is_server_running "$srv"; then
                status_text="${GREEN}РАБОТАЕТ${NC}"
            else
                status_text="${DIM}остановлен${NC}"
            fi

            printf "  %-4s %-20s %-8s %-6s " "$i" "$NAME" "$actual_port" "$RAM"
            echo -e "$status_text"
            i=$((i + 1))
        done

        echo ""
        echo -e "${DIM}  Введи номер сервера для управления${NC}"
        echo ""
        read -p "  Выбор (номер / b=назад): " CHOICE

        [ "$CHOICE" == "b" ] || [ "$CHOICE" == "B" ] && return

        if echo "$CHOICE" | grep -qE '^[0-9]+$'; then
            local idx=$((CHOICE - 1))
            if [ $idx -ge 0 ] && [ $idx -lt ${#servers[@]} ]; then
                server_manage_menu "${servers[$idx]}"
            fi
        fi
    done
}

# =====================
# Управление сервером
# =====================

server_manage_menu() {
    local srv_name="$1"
    local sv_dir="$BASE_DIR/$srv_name"

    while true; do
        show_logo
        read_server_conf "$sv_dir"

        local actual_port
        actual_port=$(get_actual_port "$sv_dir")

        local status_text
        if is_server_running "$srv_name"; then
            status_text="${GREEN}РАБОТАЕТ${NC}"
        else
            status_text="${RED}ОСТАНОВЛЕН${NC}"
        fi

        echo -e "${BOLD}Сервер: ${CYAN}$NAME${NC}  [$status_text${NC}]"
        echo -e "${DIM}  Папка: $sv_dir${NC}"
        echo -e "${DIM}  RAM: $RAM | Порт: $actual_port | Ядро: $CORE${NC}"
        echo ""

        echo "  1. Запустить"
        echo "  2. Остановить"
        echo "  3. Консоль (screen)"
        echo "  4. Перезапустить"
        echo ""
        echo "  5. Настройки (RAM, порт, online-mode)"
        echo "  6. Создать сервис (автозапуск + автосохранение)"
        echo ""
        echo -e "  ${RED}9. Удалить сервер${NC}"
        echo ""
        read -p "  Выбор (b=назад): " ACT

        case $ACT in
            1) server_start "$srv_name" ;;
            2) server_stop "$srv_name" ;;
            3) server_console "$srv_name" ;;
            4) server_stop "$srv_name"; sleep 1; server_start "$srv_name" ;;
            5) server_settings "$srv_name" ;;
            6) server_create_service "$srv_name" ;;
            9) server_delete "$srv_name" && return ;;
            b|B) return ;;
        esac
    done
}

# Запуск сервера
server_start() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"

    if is_server_running "$name"; then
        echo -e "${YELLOW}Сервер уже запущен!${NC}"
        pause
        return
    fi

    if [ ! -f "$sv_dir/server.jar" ]; then
        echo -e "${RED}server.jar не найден! Закинь его в $sv_dir/${NC}"
        pause
        return
    fi

    if [ ! -f "$sv_dir/start.sh" ]; then
        echo -e "${RED}start.sh не найден!${NC}"
        pause
        return
    fi

    echo -e "${CYAN}Запускаю '$name'...${NC}"
    cd "$sv_dir"
    screen -dmS "mbsft-${name}" ./start.sh
    sleep 1

    if is_server_running "$name"; then
        local actual_port
        actual_port=$(get_actual_port "$sv_dir")
        local ip
        ip=$(get_ip)
        echo -e "${GREEN}Сервер '$name' запущен!${NC}"
        echo -e "  Подключение: ${BOLD}${ip}:${actual_port}${NC}"
        echo -e "  Консоль:     ${CYAN}screen -r mbsft-${name}${NC}"
    else
        echo -e "${RED}Не удалось запустить. Проверь логи.${NC}"
    fi
    pause
}

# Остановка сервера
server_stop() {
    local name="$1"

    if ! is_server_running "$name"; then
        echo -e "${DIM}Сервер '$name' не запущен.${NC}"
        pause
        return
    fi

    echo -e "${YELLOW}Останавливаю '$name'...${NC}"
    # Отправляем stop в screen сессию
    screen -S "mbsft-${name}" -p 0 -X stuff "stop$(printf '\r')" 2>/dev/null

    # Ждём завершения (макс 15 секунд)
    local tries=0
    while is_server_running "$name" && [ $tries -lt 15 ]; do
        sleep 1
        tries=$((tries + 1))
    done

    # Если всё ещё работает — убиваем screen
    if is_server_running "$name"; then
        screen -S "mbsft-${name}" -X quit 2>/dev/null
    fi

    echo -e "${GREEN}Сервер '$name' остановлен.${NC}"
    pause
}

# Консоль
server_console() {
    local name="$1"

    if ! is_server_running "$name"; then
        echo -e "${RED}Сервер не запущен!${NC}"
        pause
        return
    fi

    echo -e "${CYAN}Подключаюсь к консоли '$name'...${NC}"
    echo -e "${DIM}Выход: Ctrl+A, затем D${NC}"
    sleep 1
    screen -r "mbsft-${name}"
}

# Настройки
server_settings() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"

    show_logo
    read_server_conf "$sv_dir"
    echo -e "${BOLD}[Настройки: $NAME]${NC}"
    echo ""

    # Текущие значения
    local actual_port
    actual_port=$(get_actual_port "$sv_dir")

    local online="?"
    if [ -f "$sv_dir/server.properties" ]; then
        online=$(grep "online-mode=" "$sv_dir/server.properties" 2>/dev/null | cut -d= -f2)
    fi

    echo "  Текущие:"
    echo "    RAM:         $RAM"
    echo "    Порт:        $actual_port"
    echo "    online-mode: $online"
    echo ""

    # RAM
    read -p "  Новый RAM [$RAM]: " NEW_RAM
    NEW_RAM=${NEW_RAM:-$RAM}
    if ! echo "$NEW_RAM" | grep -qE '^[0-9]+[MG]$'; then
        echo -e "${RED}Неверный формат RAM!${NC}"
        pause
        return
    fi

    # Порт
    read -p "  Новый порт [$actual_port]: " NEW_PORT
    NEW_PORT=${NEW_PORT:-$actual_port}

    # Online-mode
    read -p "  online-mode (true/false) [false]: " NEW_ONLINE
    NEW_ONLINE=${NEW_ONLINE:-false}

    # Применяем
    # start.sh
    cat > "$sv_dir/start.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
cd "$sv_dir"
echo "[$name] Запуск (RAM: $NEW_RAM, Port: $NEW_PORT)..."
"$JAVA8_PATH" -Xmx$NEW_RAM -Xms$NEW_RAM -jar server.jar nogui
EOF
    chmod +x "$sv_dir/start.sh"

    # server.properties
    if [ -f "$sv_dir/server.properties" ]; then
        sed -i "s/server-port=.*/server-port=$NEW_PORT/g" "$sv_dir/server.properties"
        sed -i "s/online-mode=.*/online-mode=$NEW_ONLINE/g" "$sv_dir/server.properties"
        sed -i "s/verify-names=.*/verify-names=$NEW_ONLINE/g" "$sv_dir/server.properties"
        sed -i "s/server-ip=.*/server-ip=/g" "$sv_dir/server.properties"
    fi

    # EULA
    if [ -f "$sv_dir/eula.txt" ]; then
        sed -i 's/eula=false/eula=true/g' "$sv_dir/eula.txt"
    fi

    # Обновляем конфиг
    write_server_conf "$sv_dir" "$name" "$NEW_RAM" "$NEW_PORT" "$CORE"

    echo ""
    echo -e "${GREEN}Настройки обновлены!${NC}"
    echo -e "${YELLOW}Перезапусти сервер чтобы изменения вступили в силу.${NC}"
    pause
}

# Создание сервиса
server_create_service() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"
    local sv_service="mbsft-${name}"
    local SVDIR="$PREFIX/var/service/$sv_service"

    mkdir -p "$SVDIR/log"

    cat > "$SVDIR/run" << SEOF
#!/data/data/com.termux/files/usr/bin/sh
cd "$sv_dir"

# Автосохранение каждые 10 минут
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

    if command -v sv-enable &>/dev/null; then
        sv-enable "$sv_service" 2>/dev/null || true
    fi

    echo ""
    echo -e "${GREEN}Сервис '$sv_service' создан!${NC}"
    echo ""
    echo "  Автозапуск при старте Termux"
    echo "  Автосохранение каждые 10 минут"
    echo ""
    echo "  Управление:"
    echo -e "    ${CYAN}sv up $sv_service${NC}     — запуск"
    echo -e "    ${CYAN}sv down $sv_service${NC}   — стоп"
    pause
}

# Удаление сервера
server_delete() {
    local name="$1"
    local sv_dir="$BASE_DIR/$name"

    echo ""
    echo -e "${RED}${BOLD}ВНИМАНИЕ: Это удалит сервер '$name' и ВСЕ его файлы!${NC}"
    echo -e "${RED}  Папка: $sv_dir${NC}"
    echo ""
    read -p "Введи имя сервера для подтверждения: " CONFIRM

    if [ "$CONFIRM" != "$name" ]; then
        echo -e "${YELLOW}Отменено.${NC}"
        pause
        return 1
    fi

    # Останавливаем если запущен
    if is_server_running "$name"; then
        screen -S "mbsft-${name}" -p 0 -X stuff "stop$(printf '\r')" 2>/dev/null
        sleep 3
        screen -S "mbsft-${name}" -X quit 2>/dev/null
    fi

    # Удаляем сервис если есть
    local sv_service="mbsft-${name}"
    if [ -d "$PREFIX/var/service/$sv_service" ]; then
        sv down "$sv_service" 2>/dev/null || true
        if command -v sv-disable &>/dev/null; then
            sv-disable "$sv_service" 2>/dev/null || true
        fi
        rm -rf "$PREFIX/var/service/$sv_service"
    fi

    # Удаляем папку
    rm -rf "$sv_dir"

    echo -e "${GREEN}Сервер '$name' удалён.${NC}"
    pause
    return 0
}

# =====================
# Дашборд
# =====================

dashboard() {
    show_logo
    echo -e "${BOLD}[Дашборд]${NC}"
    echo ""

    local ip
    ip=$(get_ip)

    # Зависимости
    if deps_installed; then
        echo -e "  Java 8:  ${GREEN}OK${NC}"
    else
        echo -e "  Java 8:  ${RED}не установлена${NC}"
    fi

    echo -e "  IP:      ${CYAN}$ip${NC}"

    if pidof sshd &>/dev/null; then
        echo -e "  SSH:     ${GREEN}порт 8022${NC}"
    else
        echo -e "  SSH:     ${DIM}выкл${NC}"
    fi

    echo ""

    local servers
    read -ra servers <<< "$(get_servers)"

    if [ ${#servers[@]} -eq 0 ] || [ -z "${servers[0]}" ]; then
        echo -e "  ${DIM}Серверов нет.${NC}"
        echo ""
        pause
        return
    fi

    printf "  ${BOLD}%-20s %-8s %-6s %-12s %-20s${NC}\n" "Имя" "Порт" "RAM" "Статус" "Подключение"
    echo "  --------------------------------------------------------------------------"

    for srv in "${servers[@]}"; do
        local sv_dir="$BASE_DIR/$srv"
        read_server_conf "$sv_dir"

        local actual_port
        actual_port=$(get_actual_port "$sv_dir")

        local status_text connect_text
        if is_server_running "$srv"; then
            status_text="${GREEN}РАБОТАЕТ${NC}"
            connect_text="${ip}:${actual_port}"
        else
            status_text="${DIM}остановлен${NC}"
            connect_text="${DIM}-${NC}"
        fi

        printf "  %-20s %-8s %-6s " "$NAME" "$actual_port" "$RAM"
        printf "%-12b %-20b\n" "$status_text" "$connect_text"
    done

    echo ""
    pause
}

# =====================
# SSH
# =====================

step_ssh() {
    show_logo
    echo -e "${CYAN}${BOLD}[Настройка SSH]${NC}"
    echo ""

    echo -e "${YELLOW}Придумай пароль для входа с ПК:${NC}"
    passwd

    sshd

    local user ip
    user=$(whoami)
    ip=$(get_ip)

    echo ""
    echo -e "${GREEN}SSH запущен на порту 8022!${NC}"
    echo "================================================"
    echo -e "  ${CYAN}ssh -p 8022 $user@$ip${NC}"
    echo "================================================"
    pause
}

# =====================
# Главное меню
# =====================

main_menu() {
    show_logo

    local servers
    read -ra servers <<< "$(get_servers)"
    local count=0
    [ -n "${servers[0]}" ] && count=${#servers[@]}

    local running=0
    for srv in "${servers[@]}"; do
        [ -z "$srv" ] && continue
        is_server_running "$srv" && running=$((running + 1))
    done

    if deps_installed; then
        echo -e "  Java: ${GREEN}OK${NC} | Серверов: ${BOLD}$count${NC} | Запущено: ${GREEN}$running${NC}"
    else
        echo -e "  ${YELLOW}Зависимости не установлены${NC}"
    fi
    echo ""

    echo "  1. Установить зависимости"
    echo "  2. Создать сервер (пошагово)"
    echo -e "  3. Быстрое создание ${DIM}(Poseidon + авто-настройка)${NC}"
    echo ""
    echo -e "  ${BOLD}4. Мои серверы${NC} ${DIM}[$count шт.]${NC}"
    echo -e "  5. Дашборд ${DIM}(статус всех серверов)${NC}"
    echo ""
    echo "  6. Настроить SSH"
    echo ""
    echo "  [q] Выход"
}

# =====================
# Main
# =====================

check_termux
mkdir -p "$BASE_DIR"

while true; do
    main_menu
    echo ""
    read -p "  Выбор: " OPT
    case $OPT in
        1) step_deps ;;
        2) create_server ;;
        3) quick_create ;;
        4) list_servers_menu ;;
        5) dashboard ;;
        6) step_ssh ;;
        q|Q) echo -e "${GREEN}Пока!${NC}"; exit 0 ;;
    esac
done
