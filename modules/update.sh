#!/data/data/com.termux/files/usr/bin/bash
# ============================================
# MBSFT Update Module
# Автообновление скрипта
# ============================================

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
    local remote_version=$(grep '^export MBSFT_VERSION=' "$tmp_script" | head -1 | cut -d'"' -f2)
    
    # Сравниваем версии
    if [ -n "$remote_version" ] && [ "$remote_version" != "$MBSFT_VERSION" ]; then
        echo "╔════════════════════════════════════════╗"
        echo "║   Обновление MBSFT                     ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        echo "  Текущая версия:  $MBSFT_VERSION"
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
