#!/bin/bash
# ============================================
# MBSFT Build Script
# Собирает install.sh из модулей
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "╔════════════════════════════════════════╗"
echo "║   MBSFT Build Script                   ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Проверяем наличие модулей
if [ ! -d "modules" ]; then
    echo "✗ Ошибка: директория modules/ не найдена!"
    exit 1
fi

required_modules=("core.sh" "java.sh" "server.sh" "ui.sh")
for module in "${required_modules[@]}"; do
    if [ ! -f "modules/$module" ]; then
        echo "✗ Ошибка: модуль modules/$module не найден!"
        exit 1
    fi
done

echo "✓ Все модули найдены"
echo ""

# Читаем версию из core.sh
VERSION=$(grep 'export MBSFT_VERSION=' modules/core.sh | head -1 | cut -d'"' -f2)
if [ -z "$VERSION" ]; then
    echo "✗ Ошибка: не удалось определить версию из modules/core.sh"
    exit 1
fi

echo "  Версия: $VERSION"
echo ""

# Создаём временный файл
TMP_FILE=$(mktemp)

# Записываем заголовок
cat > "$TMP_FILE" << 'HEADER'
#!/data/data/com.termux/files/usr/bin/bash
# ============================================
# MBSFT — Minecraft Beta Server For Termux
# Самораспаковывающийся модульный установщик
# ============================================

HEADER

# Добавляем версию и переменные
cat >> "$TMP_FILE" << VARS
export MBSFT_VERSION="$VERSION"
export SCRIPT_URL="https://raw.githubusercontent.com/FLEXIY0/MBSFT/main/install.sh"
export SCRIPT_PATH="\$HOME/install.sh"
export MODULES_DIR="\$HOME/.mbsft/modules"

VARS

# Добавляем основной код
cat >> "$TMP_FILE" << 'MAINCODE'
# =====================
# Самораспаковка модулей
# =====================
extract_modules() {
    mkdir -p "$MODULES_DIR"
    
    # Извлекаем модули из этого скрипта
    local extracting=0
    local current_module=""
    
    while IFS= read -r line; do
        if [[ "$line" == "### MODULE:"* ]]; then
            current_module="${line#*: }"
            extracting=1
            > "$MODULES_DIR/$current_module"
            continue
        elif [[ "$line" == "### END_MODULE" ]]; then
            extracting=0
            chmod +x "$MODULES_DIR/$current_module"
            current_module=""
            continue
        fi
        
        if [ $extracting -eq 1 ]; then
            echo "$line" >> "$MODULES_DIR/$current_module"
        fi
    done < "$0"
}

# =====================
# Автообновление
# =====================
auto_update() {
    # Пропускаем если скрипт запущен из временного файла
    if [[ "$0" == *".mbsft_"* ]] || [[ "$0" == "/tmp/"* ]]; then
        return 0
    fi
    
    # Проверяем наличие curl или wget
    local downloader=""
    if command -v curl &>/dev/null; then
        downloader="curl"
    elif command -v wget &>/dev/null; then
        downloader="wget"
    else
        return 0
    fi
    
    # Скачиваем новую версию
    local tmp_script=$(mktemp "$HOME/.mbsft_update_XXXXXX.sh")
    
    if [ "$downloader" = "curl" ]; then
        curl -sL "$SCRIPT_URL" -o "$tmp_script" 2>/dev/null || { rm -f "$tmp_script"; return 0; }
    else
        wget -qO "$tmp_script" "$SCRIPT_URL" 2>/dev/null || { rm -f "$tmp_script"; return 0; }
    fi
    
    [ ! -s "$tmp_script" ] && { rm -f "$tmp_script"; return 0; }
    
    # Проверяем версию
    local remote_version=$(grep '^export MBSFT_VERSION=' "$tmp_script" | head -1 | cut -d'"' -f2)
    
    if [ -n "$remote_version" ] && [ "$remote_version" != "$MBSFT_VERSION" ]; then
        echo "╔════════════════════════════════════════╗"
        echo "║   Обновление MBSFT                     ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        echo "  Текущая версия:  $MBSFT_VERSION"
        echo "  Новая версия:    $remote_version"
        echo ""
        echo "  Обновляю..."
        
        cp "$tmp_script" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        rm -f "$tmp_script"
        
        echo "  ✓ Готово! Перезапускаю..."
        sleep 2
        exec bash "$SCRIPT_PATH" "$@"
        exit 0
    fi
    
    rm -f "$tmp_script"
}

# =====================
# Fix: curl | bash
# =====================
if [ ! -t 0 ]; then
    cat > "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║   MBSFT установлен!                    ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "  Скрипт: $SCRIPT_PATH"
    echo "  Запуск: bash install.sh"
    echo ""
    echo "  Запускаю..."
    sleep 2
    exec bash "$SCRIPT_PATH" "$@"
    exit
fi

# =====================
# Bootstrap
# =====================
if ! command -v dialog &>/dev/null; then
    echo "[MBSFT] Устанавливаю dialog..."
    pkg install -y dialog 2>/dev/null || apt install -y dialog 2>/dev/null
fi

if ! command -v dialog &>/dev/null; then
    echo "Ошибка: не удалось установить dialog"
    exit 1
fi

if [ ! -d "/data/data/com.termux" ]; then
    dialog --title "Ошибка" --msgbox "Этот скрипт только для Termux!" 6 40
    exit 1
fi

# Запускаем автообновление
auto_update "$@"

# Распаковываем модули
extract_modules

# Загружаем модули
source "$MODULES_DIR/core.sh"
source "$MODULES_DIR/java.sh"
source "$MODULES_DIR/server.sh"
source "$MODULES_DIR/ui.sh"

# Инициализация
init_core
find_java

# Запускаем главное меню
main_loop

exit 0

# ============================================
# ВСТРОЕННЫЕ МОДУЛИ (не редактировать вручную)
# ============================================

MAINCODE

# Встраиваем модули
echo "  Встраиваю модули:"

for module in "${required_modules[@]}"; do
    echo "    - $module"
    echo "" >> "$TMP_FILE"
    echo "### MODULE: $module" >> "$TMP_FILE"
    cat "modules/$module" >> "$TMP_FILE"
    echo "### END_MODULE" >> "$TMP_FILE"
done

echo ""

# Заменяем install.sh
mv "$TMP_FILE" install.sh
chmod +x install.sh

echo "✓ Сборка завершена!"
echo ""
echo "  Файл: install.sh"
echo "  Размер: $(du -h install.sh | cut -f1)"
echo "  Версия: $VERSION"
echo ""
echo "╔════════════════════════════════════════╗"
echo "║   Готово!                              ║"
echo "╚════════════════════════════════════════╝"
