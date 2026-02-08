#!/data/data/com.termux/files/usr/bin/bash

# ============================================
# MBSFT — Minecraft Beta Server For Termux
# Установщик и менеджер сервера
# ============================================

set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Состояние шагов
DONE_DEPS=0
DONE_JAR=0
DONE_SCRIPT=0
DONE_FIX=0
DONE_SERVICE=0
DONE_SSH=0

SERVER_DIR="$HOME/minecraft-server"
JAVA8_PATH="/data/data/com.termux/files/usr/lib/jvm/java-8-openjdk/bin/java"
POSEIDON_URL="https://ci.project-poseidon.com/job/Project-Poseidon/lastSuccessfulBuild/artifact/target/poseidon-1.1.8.jar"

# Проверка что мы в Termux
check_termux() {
    if [ ! -d "/data/data/com.termux" ]; then
        echo -e "${RED}Ошибка: Этот скрипт предназначен только для Termux!${NC}"
        exit 1
    fi
}

# Логотип
show_logo() {
    clear
    echo -e "${CYAN}"
    echo " __  __  ____   _____ ______ _______ "
    echo "|  \/  ||  _ \ / ____|  ____|__   __|"
    echo "| \  / || |_) | (___ | |__     | |   "
    echo "| |\/| ||  _ < \___ \|  __|    | |   "
    echo "| |  | || |_) |____) | |       | |   "
    echo "|_|  |_||____/|_____/|_|       |_|   "
    echo -e "${BOLD}Minecraft Beta Server For Termux${NC}"
    echo ""
}

# Получить IP адрес
get_ip() {
    local ip=""
    # Пробуем ifconfig
    if command -v ifconfig &>/dev/null; then
        ip=$(ifconfig wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}')
    fi
    # Фоллбэк на ip addr
    if [ -z "$ip" ] && command -v ip &>/dev/null; then
        ip=$(ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    fi
    echo "${ip:-<не определён — проверь Wi-Fi>}"
}

# Проверить что шаг выполнен ранее (автодетект)
auto_detect_state() {
    # Зависимости: проверяем java
    if [ -f "$JAVA8_PATH" ] && command -v screen &>/dev/null && command -v wget &>/dev/null; then
        DONE_DEPS=1
    fi
    # Ядро
    if [ -f "$SERVER_DIR/server.jar" ]; then
        DONE_JAR=1
    fi
    # Скрипт запуска
    if [ -f "$SERVER_DIR/start.sh" ]; then
        DONE_SCRIPT=1
    fi
    # Фикс настроек
    if [ -f "$SERVER_DIR/server.properties" ]; then
        if grep -q "online-mode=false" "$SERVER_DIR/server.properties" 2>/dev/null; then
            DONE_FIX=1
        fi
    fi
    # SSH
    if pidof sshd &>/dev/null; then
        DONE_SSH=1
    fi
}

show_menu() {
    show_logo
    echo -e "Папка сервера: ${BOLD}$SERVER_DIR${NC}"
    echo ""

    [[ $DONE_DEPS -eq 1 ]] && M1="${GREEN}[✓]${NC}" || M1="[ ]"
    echo -e "$M1 1. Установить зависимости (Java 8, screen, wget)"

    [[ $DONE_JAR -eq 1 ]] && M2="${GREEN}[✓]${NC}" || M2="[ ]"
    echo -e "$M2 2. Подготовка ядра (server.jar)"

    [[ $DONE_SCRIPT -eq 1 ]] && M3="${GREEN}[✓]${NC}" || M3="[ ]"
    echo -e "$M3 3. Создать start.sh (Запуск)"

    [[ $DONE_FIX -eq 1 ]] && M4="${GREEN}[✓]${NC}" || M4="[ ]"
    echo -e "$M4 4. FIX настроек (online-mode=false, EULA)"

    [[ $DONE_SERVICE -eq 1 ]] && M5="${GREEN}[✓]${NC}" || M5="[ ]"
    echo -e "$M5 5. Создать авто-сервис (AutoSave + Reboot)"

    echo ""
    echo -e "${YELLOW}--- Управление ---${NC}"

    [[ $DONE_SSH -eq 1 ]] && M6="${GREEN}[✓]${NC}" || M6="[ ]"
    echo -e "$M6 6. Настроить SSH (Управление с ПК)"

    echo ""
    echo -e "${CYAN}    7. Быстрая установка (всё сразу: 1-4)${NC}"
    echo ""
    echo -e "    8. Показать статус / IP"
    echo ""
    echo "[q] Выход"
}

# =====================
# 1. Зависимости
# =====================
step_deps() {
    echo -e "${CYAN}Обновление пакетов...${NC}"
    pkg update -y && pkg upgrade -y

    echo -e "${CYAN}Установка пакетов...${NC}"
    pkg install -y tur-repo
    pkg install -y wget screen termux-services openssh net-tools
    pkg install -y openjdk-8

    # Проверяем установку java
    if [ -f "$JAVA8_PATH" ]; then
        echo -e "${GREEN}Java 8 установлена: $($JAVA8_PATH -version 2>&1 | head -1)${NC}"
    else
        echo -e "${RED}Ошибка: Java 8 не найдена по пути $JAVA8_PATH${NC}"
        echo "Попробуй перезапустить Termux и запустить скрипт снова."
        read -p "Enter..."
        return
    fi

    DONE_DEPS=1
    echo -e "${GREEN}Все зависимости установлены!${NC}"
    read -p "Enter..."
}

# =====================
# 2. Ядро
# =====================
step_jar() {
    mkdir -p "$SERVER_DIR"
    cd "$SERVER_DIR"

    if [ -f "server.jar" ]; then
        echo -e "${GREEN}Файл server.jar уже на месте!${NC}"
        DONE_JAR=1
        read -p "Enter..."
        return
    fi

    echo -e "${YELLOW}Файл server.jar не найден.${NC}"
    echo ""
    echo "1) Скачать Project Poseidon (Beta 1.7.3 — рекомендуется)"
    echo "2) Я закину свой файл сам"
    echo ""
    read -p "Выбор [1]: " JCHOICE
    JCHOICE=${JCHOICE:-1}

    if [ "$JCHOICE" == "1" ]; then
        echo -e "${CYAN}Скачиваю Project Poseidon...${NC}"
        if wget -O server.jar "$POSEIDON_URL"; then
            echo -e "${GREEN}Ядро скачано!${NC}"
            DONE_JAR=1
        else
            echo -e "${RED}Ошибка загрузки! Проверь интернет.${NC}"
            rm -f server.jar
        fi
    else
        echo ""
        echo -e "Закинь файл ${BOLD}server.jar${NC} в папку:"
        echo -e "${CYAN}$SERVER_DIR${NC}"
        echo "Затем нажми пункт 2 снова."
    fi
    read -p "Enter..."
}

# =====================
# 3. Скрипт запуска
# =====================
step_script() {
    if [ $DONE_JAR -eq 0 ]; then
        echo -e "${RED}Сначала подготовь ядро (пункт 2)!${NC}"
        sleep 2
        return
    fi

    cd "$SERVER_DIR"

    read -p "Сколько RAM выделить? (512M / 1G / 2G) [1G]: " RAM
    RAM=${RAM:-1G}

    # Валидация формата RAM
    if ! echo "$RAM" | grep -qE '^[0-9]+[MG]$'; then
        echo -e "${RED}Неверный формат! Используй например: 512M, 1G, 2G${NC}"
        sleep 2
        return
    fi

    cat > start.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
cd "$SERVER_DIR"
echo "Запуск Minecraft сервера (RAM: $RAM)..."
"$JAVA8_PATH" -Xmx$RAM -Xms$RAM -jar server.jar nogui
EOF
    chmod +x start.sh

    echo -e "${GREEN}Скрипт start.sh создан!${NC}"
    echo ""
    echo -e "${YELLOW}Первый запуск нужен чтобы сервер создал конфиги.${NC}"
    echo "После запуска дождись появления файлов и останови сервер (Ctrl+C)."
    echo ""
    read -p "Запустить первый старт сейчас? (y/n) [y]: " RUNNOW
    RUNNOW=${RUNNOW:-y}

    if [ "$RUNNOW" == "y" ]; then
        echo -e "${CYAN}Запуск сервера... (Ctrl+C для остановки)${NC}"
        ./start.sh || true
        # После первого запуска принимаем EULA
        if [ -f "eula.txt" ]; then
            sed -i 's/eula=false/eula=true/g' eula.txt
            echo -e "${GREEN}EULA автоматически принята.${NC}"
        fi
    fi

    DONE_SCRIPT=1
    read -p "Enter..."
}

# =====================
# 4. Фикс настроек
# =====================
step_fix() {
    cd "$SERVER_DIR"

    # Принимаем EULA если есть
    if [ -f "eula.txt" ]; then
        sed -i 's/eula=false/eula=true/g' eula.txt
        echo -e "${GREEN}EULA принята.${NC}"
    fi

    if [ ! -f "server.properties" ]; then
        echo -e "${RED}Файл server.properties не найден!${NC}"
        echo "Сначала запусти сервер (пункт 3), чтобы он создал конфиги."
        sleep 3
        return
    fi

    echo -e "${CYAN}Патчим server.properties...${NC}"

    # online-mode=false (для пиратов)
    sed -i 's/online-mode=true/online-mode=false/g' server.properties
    # verify-names (для Poseidon)
    sed -i 's/verify-names=true/verify-names=false/g' server.properties
    # Убираем привязку к конкретному IP
    sed -i 's/server-ip=.*/server-ip=/g' server.properties

    # Показываем порт
    PORT=$(grep "server-port=" server.properties | cut -d= -f2)
    PORT=${PORT:-25565}

    echo ""
    echo -e "${GREEN}Настройки применены!${NC}"
    echo -e "  online-mode = ${BOLD}false${NC} (пираты могут заходить)"
    echo -e "  server-port = ${BOLD}$PORT${NC}"
    echo ""

    DONE_FIX=1
    read -p "Enter..."
}

# =====================
# 5. Сервис
# =====================
step_service() {
    if [ $DONE_SCRIPT -eq 0 ]; then
        echo -e "${RED}Сначала создай start.sh (пункт 3)!${NC}"
        sleep 2
        return
    fi

    read -p "Имя сервера (англ, без пробелов) [mcserver]: " SVNAME
    SVNAME=${SVNAME:-mcserver}

    # Валидация имени
    if ! echo "$SVNAME" | grep -qE '^[a-zA-Z0-9_-]+$'; then
        echo -e "${RED}Имя должно содержать только буквы, цифры, _ и -${NC}"
        sleep 2
        return
    fi

    SVDIR="$PREFIX/var/service/$SVNAME"
    mkdir -p "$SVDIR/log"

    # Run script с корректным завершением фонового процесса
    cat > "$SVDIR/run" << SEOF
#!/data/data/com.termux/files/usr/bin/sh
cd "$SERVER_DIR"

# Автосохранение каждые 10 минут
(
    while true; do
        sleep 600
        screen -S $SVNAME -p 0 -X stuff "save-all\$(printf \\\\r)" 2>/dev/null
    done
) &
SAVE_PID=\$!

# Убиваем фоновый процесс при остановке
trap "kill \$SAVE_PID 2>/dev/null" EXIT TERM INT

exec screen -DmS $SVNAME ./start.sh
SEOF
    chmod +x "$SVDIR/run"

    # Log script
    cat > "$SVDIR/log/run" << LEOF
#!/data/data/com.termux/files/usr/bin/sh
exec svlogd -tt "$SERVER_DIR/logs/sv"
LEOF
    chmod +x "$SVDIR/log/run"
    mkdir -p "$SERVER_DIR/logs/sv"

    # Активируем сервис
    if command -v sv-enable &>/dev/null; then
        sv-enable "$SVNAME" 2>/dev/null || true
    fi

    echo ""
    echo -e "${GREEN}Сервис '$SVNAME' создан!${NC}"
    echo ""
    echo "Управление:"
    echo -e "  Запуск:    ${CYAN}sv up $SVNAME${NC}"
    echo -e "  Стоп:      ${CYAN}sv down $SVNAME${NC}"
    echo -e "  Консоль:   ${CYAN}screen -r $SVNAME${NC}"
    echo -e "  Выход:     Ctrl+A, затем D"
    echo ""

    DONE_SERVICE=1
    read -p "Enter..."
}

# =====================
# 6. SSH
# =====================
step_ssh() {
    echo -e "${CYAN}Настройка удалённого доступа...${NC}"
    echo ""

    echo -e "${YELLOW}Придумай пароль для входа с ПК:${NC}"
    passwd

    # Запускаем SSH демон
    sshd

    USER=$(whoami)
    IP=$(get_ip)

    echo ""
    echo -e "${GREEN}SSH запущен на порту 8022!${NC}"
    echo "================================================"
    echo -e "Подключение с ПК (PowerShell / Terminal):"
    echo ""
    echo -e "  ${CYAN}ssh -p 8022 $USER@$IP${NC}"
    echo ""
    echo "================================================"

    DONE_SSH=1
    read -p "Enter..."
}

# =====================
# 7. Быстрая установка
# =====================
step_quick() {
    echo -e "${CYAN}${BOLD}=== Быстрая установка ===${NC}"
    echo ""
    echo "Будут выполнены шаги 1-4 автоматически."
    echo "Ядро: Project Poseidon (Beta 1.7.3)"
    echo "RAM: 1G"
    echo ""
    read -p "Продолжить? (y/n) [y]: " CONFIRM
    CONFIRM=${CONFIRM:-y}
    [ "$CONFIRM" != "y" ] && return

    # 1. Зависимости
    echo ""
    echo -e "${CYAN}[1/4] Установка зависимостей...${NC}"
    pkg update -y && pkg upgrade -y
    pkg install -y tur-repo
    pkg install -y wget screen termux-services openssh net-tools
    pkg install -y openjdk-8
    if [ ! -f "$JAVA8_PATH" ]; then
        echo -e "${RED}Java 8 не установилась. Прерываю.${NC}"
        read -p "Enter..."
        return
    fi
    DONE_DEPS=1
    echo -e "${GREEN}[1/4] Зависимости ✓${NC}"

    # 2. Ядро
    echo ""
    echo -e "${CYAN}[2/4] Скачиваю ядро...${NC}"
    mkdir -p "$SERVER_DIR"
    cd "$SERVER_DIR"
    if [ ! -f "server.jar" ]; then
        if ! wget -O server.jar "$POSEIDON_URL"; then
            echo -e "${RED}Ошибка загрузки ядра!${NC}"
            rm -f server.jar
            read -p "Enter..."
            return
        fi
    fi
    DONE_JAR=1
    echo -e "${GREEN}[2/4] Ядро ✓${NC}"

    # 3. Скрипт запуска
    echo ""
    echo -e "${CYAN}[3/4] Создаю start.sh...${NC}"
    cat > start.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash
cd "$SERVER_DIR"
echo "Запуск Minecraft сервера (RAM: 1G)..."
"$JAVA8_PATH" -Xmx1G -Xms1G -jar server.jar nogui
EOF
    chmod +x start.sh
    DONE_SCRIPT=1
    echo -e "${GREEN}[3/4] start.sh ✓${NC}"

    # Первый запуск для генерации конфигов
    echo ""
    echo -e "${YELLOW}Первый запуск сервера для генерации конфигов...${NC}"
    echo -e "${YELLOW}Дождись загрузки и нажми Ctrl+C для остановки.${NC}"
    echo ""
    ./start.sh || true

    # 4. Фикс настроек
    echo ""
    echo -e "${CYAN}[4/4] Применяю настройки...${NC}"

    if [ -f "eula.txt" ]; then
        sed -i 's/eula=false/eula=true/g' eula.txt
    fi

    if [ -f "server.properties" ]; then
        sed -i 's/online-mode=true/online-mode=false/g' server.properties
        sed -i 's/verify-names=true/verify-names=false/g' server.properties
        sed -i 's/server-ip=.*/server-ip=/g' server.properties
        DONE_FIX=1
        echo -e "${GREEN}[4/4] Настройки ✓${NC}"
    else
        echo -e "${YELLOW}[4/4] server.properties не найден — запусти сервер ещё раз.${NC}"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}Установка завершена!${NC}"
    echo ""
    echo "Запуск сервера:"
    echo -e "  ${CYAN}cd $SERVER_DIR && ./start.sh${NC}"
    echo ""

    read -p "Enter..."
}

# =====================
# 8. Статус
# =====================
step_status() {
    show_logo
    echo -e "${BOLD}Статус:${NC}"
    echo ""

    # Java
    if [ -f "$JAVA8_PATH" ]; then
        echo -e "  Java 8:      ${GREEN}установлена${NC}"
    else
        echo -e "  Java 8:      ${RED}не найдена${NC}"
    fi

    # Ядро
    if [ -f "$SERVER_DIR/server.jar" ]; then
        SIZE=$(du -h "$SERVER_DIR/server.jar" | awk '{print $1}')
        echo -e "  server.jar:  ${GREEN}есть ($SIZE)${NC}"
    else
        echo -e "  server.jar:  ${RED}нет${NC}"
    fi

    # Конфиги
    if [ -f "$SERVER_DIR/server.properties" ]; then
        PORT=$(grep "server-port=" "$SERVER_DIR/server.properties" | cut -d= -f2)
        ONLINE=$(grep "online-mode=" "$SERVER_DIR/server.properties" | cut -d= -f2)
        echo -e "  Порт:        ${CYAN}$PORT${NC}"
        echo -e "  online-mode: ${CYAN}$ONLINE${NC}"
    fi

    # IP
    IP=$(get_ip)
    echo -e "  IP (Wi-Fi):  ${CYAN}$IP${NC}"

    # SSH
    if pidof sshd &>/dev/null; then
        echo -e "  SSH:         ${GREEN}работает (порт 8022)${NC}"
    else
        echo -e "  SSH:         ${YELLOW}не запущен${NC}"
    fi

    echo ""
    echo "Подключение к серверу из Minecraft:"
    echo -e "  ${BOLD}$IP:${PORT:-25565}${NC}"
    echo ""

    read -p "Enter..."
}

# =====================
# Main
# =====================
check_termux
mkdir -p "$SERVER_DIR"
auto_detect_state

while true; do
    show_menu
    read -p "Выбор: " OPT
    case $OPT in
        1) step_deps ;;
        2) step_jar ;;
        3) step_script ;;
        4) step_fix ;;
        5) step_service ;;
        6) step_ssh ;;
        7) step_quick ;;
        8) step_status ;;
        q|Q) echo -e "${GREEN}Пока!${NC}"; exit 0 ;;
        *) ;;
    esac
done
