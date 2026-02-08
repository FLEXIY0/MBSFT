#!/data/data/com.termux/files/usr/bin/bash
# ============================================
# MBSFT Java Module
# Управление Java
# ============================================

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
# Установка Java
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

# =====================
# Проверка зависимостей
# =====================
deps_installed() {
    find_java && command -v screen &>/dev/null && command -v wget &>/dev/null
}
