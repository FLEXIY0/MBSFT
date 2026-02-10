#!/data/data/com.termux/files/usr/bin/bash

# ============================================
# MBSFT v4.1 Bootstrap Script
# One-time setup for proot Ubuntu environment
# ============================================

# Fix: curl | bash (redirect stdin to terminal)
if [ ! -t 0 ]; then
    TMPSCRIPT=$(mktemp "$HOME/.mbsft_bootstrap_XXXXXX.sh")
    cat > "$TMPSCRIPT"
    chmod +x "$TMPSCRIPT"
    bash "$TMPSCRIPT" "$@" < /dev/tty
    rm -f "$TMPSCRIPT"
    exit
fi

VERSION="4.4"
DISTRO="ubuntu"
GITHUB_RAW="https://raw.githubusercontent.com/FLEXIY0/MBSFT/main"

clear
echo "============================================"
echo "  MBSFT v$VERSION Bootstrap"
echo "  Minecraft Beta Server For Termux"
echo "============================================"
echo ""
echo "This will setup proot Ubuntu environment with:"
echo "  • Ubuntu container via proot-distro"
echo "  • Java 8 + tmux + systemd"
echo "  • MBSFT main script"
echo "  • Wrapper for seamless access"
echo ""
read -p "Continue? (y/n): " yn
if [[ "$yn" != "y" ]]; then
    echo "Installation cancelled."
    exit 0
fi

echo ""
echo "=== Step 1/5: Installing proot-distro ==="
if ! command -v proot-distro &>/dev/null; then
    echo "Installing proot-distro package..."
    pkg update -y || { echo "Error: pkg update failed"; exit 1; }
    pkg install -y proot-distro || { echo "Error: proot-distro install failed"; exit 1; }
    echo "✓ proot-distro installed"
else
    echo "✓ proot-distro already installed"
fi

echo ""
echo "=== Step 2/5: Installing Ubuntu container ==="
if [ ! -d "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO" ]; then
    echo "Creating Ubuntu container (this may take a few minutes)..."

    # Fast download via CDN mirrors (avoid slow cloud-images.ubuntu.com)
    echo "Attempting fast download from CDN mirrors..."

    local alt_urls=(
        "https://github.com/termux/proot-distro/releases/download/v4.30.1/ubuntu-questing-aarch64-pd-v4.30.1.tar.xz"
        "https://mirror.ghproxy.com/https://github.com/termux/proot-distro/releases/download/v4.30.1/ubuntu-questing-aarch64-pd-v4.30.1.tar.xz"
        "https://cdn.jsdelivr.net/gh/termux/proot-distro@v4.30.1/releases/download/v4.30.1/ubuntu-questing-aarch64-pd-v4.30.1.tar.xz"
    )

    local cache_dir="$PREFIX/var/lib/proot-distro/dlcache"
    local tarball="$cache_dir/ubuntu-questing-aarch64-pd-v4.30.1.tar.xz"

    mkdir -p "$cache_dir"

    # Try downloading from fast CDN mirrors
    local downloaded=false
    for url in "${alt_urls[@]}"; do
        local mirror_name=$(echo $url | cut -d'/' -f3)
        echo "  Trying: $mirror_name"

        if timeout 120 wget --show-progress --progress=bar:force -O "$tarball" "$url" 2>&1; then
            # Check file size (should be > 40MB)
            local size=$(stat -c%s "$tarball" 2>/dev/null || echo 0)
            if [ "$size" -gt 40000000 ]; then
                echo "  ✓ Downloaded successfully ($(($size / 1024 / 1024))MB)"
                downloaded=true
                break
            else
                echo "  ✗ File corrupted, trying next mirror..."
                rm -f "$tarball"
            fi
        else
            echo "  ✗ Timeout or error, trying next mirror..."
            rm -f "$tarball"
        fi
    done

    # Install Ubuntu (will use cached file if downloaded)
    if [ "$downloaded" = true ]; then
        echo "Installing Ubuntu from cache..."
        proot-distro install $DISTRO || {
            echo "Cache install failed, trying default method..."
            rm -f "$tarball"
            downloaded=false
        }
    fi

    # Fallback to default if CDN mirrors failed
    if [ "$downloaded" = false ]; then
        echo "Using default proot-distro download (may be slow)..."
        proot-distro install $DISTRO || { echo "Error: Ubuntu installation failed"; exit 1; }
    fi

    echo "✓ Ubuntu container installed"
else
    echo "✓ Ubuntu container already exists"
fi

echo ""
echo "=== Step 3/6: Installing dependencies inside Ubuntu ==="
echo "Installing Java, tmux, SSH, fzf..."
proot-distro login $DISTRO -- bash -c "
    export DEBIAN_FRONTEND=noninteractive

    # Use Yandex mirror for Russia (fastest)
    echo 'Setting up Yandex mirror...'
    cat > /etc/apt/sources.list << 'EOF'
deb http://mirror.yandex.ru/ubuntu jammy main restricted universe multiverse
deb http://mirror.yandex.ru/ubuntu jammy-updates main restricted universe multiverse
deb http://mirror.yandex.ru/ubuntu jammy-security main restricted universe multiverse
EOF

    # apt update with retry
    for i in 1 2 3; do
        echo \"apt update attempt \$i/3...\"
        if apt update -y; then
            break
        fi
        [ \$i -lt 3 ] && sleep 2
    done

    # apt install with retry
    for i in 1 2 3; do
        echo \"apt install attempt \$i/3...\"
        if apt install -y openjdk-8-jre-headless wget tmux curl fzf openssh-server bc; then
            echo '✓ All packages installed'
            exit 0
        fi
        [ \$i -lt 3 ] && sleep 3
    done

    echo 'Error: Failed to install packages after 3 attempts'
    exit 1
" || { echo "Error: Package installation failed"; exit 1; }
echo "✓ Dependencies installed"

echo ""
echo "=== Step 5/7: Configuring SSH inside Ubuntu ==="
proot-distro login $DISTRO -- bash -c "
    # Create SSH directory
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    touch /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    # Generate host keys
    ssh-keygen -A 2>/dev/null

    # Configure SSH to allow root login
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config
    echo 'Port 2222' >> /etc/ssh/sshd_config
"
echo "✓ SSH configured (port 2222)"

echo ""
echo "=== Step 6/7: Installing MBSFT main script ==="
echo "Downloading mbsft.sh from GitHub..."
proot-distro login $DISTRO -- bash -c "
    mkdir -p /usr/local/bin
    # Cache busting with curl (stronger than wget)
    curl -sL \
        -H 'Cache-Control: no-store, no-cache, must-revalidate' \
        -H 'Pragma: no-cache' \
        -H 'Expires: 0' \
        --no-keepalive \
        -o /usr/local/bin/mbsft \
        '$GITHUB_RAW/mbsft.sh?nocache=\$(date +%s)_\$\$_\${RANDOM}' || exit 1
    chmod +x /usr/local/bin/mbsft
" || { echo "Error: Failed to download main script"; exit 1; }
echo "✓ Main script installed at /usr/local/bin/mbsft"

echo ""
echo "=== Step 7/7: Creating wrapper script ==="
cat > "$PREFIX/bin/mbsft" << 'WRAPPER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# MBSFT v4.0 Wrapper
# Automatically enters proot Ubuntu and runs main script

# Bind mount Termux home to access server data
TERMUX_HOME="/data/data/com.termux/files/home"

# Start SSH if not running (silent)
proot-distro login ubuntu -- bash -c "
    if ! pgrep -x sshd > /dev/null 2>&1; then
        /usr/sbin/sshd 2>/dev/null
    fi
" 2>/dev/null

proot-distro login ubuntu --bind "$TERMUX_HOME:/termux-home" -- bash -c "
    export MBSFT_BASE_DIR=/termux-home/mbsft-servers
    /usr/local/bin/mbsft \"\$@\"
" -- "$@"
WRAPPER_EOF

chmod +x "$PREFIX/bin/mbsft" || { echo "Error: Failed to create wrapper"; exit 1; }
echo "✓ Wrapper created at $PREFIX/bin/mbsft"

echo ""
echo "============================================"
echo "  ✓ Installation Complete!"
echo "============================================"
echo ""
echo "Quick Start:"
echo "  mbsft          - Launch MBSFT menu"
echo ""
echo "SSH Access (Ubuntu container):"
echo "  Port: 2222 (inside proot)"
echo "  User: root"
echo ""
echo "To setup SSH:"
echo "  1. Run: mbsft"
echo "  2. Go to: SSH → Add SSH key"
echo "  3. Or set password with 'passwd' inside proot"
echo ""
echo "SSH will auto-start when you run mbsft."
echo ""
