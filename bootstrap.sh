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

VERSION="5.0.0"
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
echo "=== Step 1/5: Updating Termux packages ==="
echo "Running pkg update..."
pkg update -y || { echo "Error: pkg update failed"; exit 1; }

echo ""
echo "Upgrading packages (including proot-distro)..."
pkg upgrade -y || { echo "Error: pkg upgrade failed"; exit 1; }
echo "✓ Packages upgraded"

echo ""
echo "=== Step 2/5: Installing proot-distro ==="
if ! command -v proot-distro &>/dev/null; then
    echo "Installing proot-distro package..."
    pkg install -y proot-distro || { echo "Error: proot-distro install failed"; exit 1; }
    echo "✓ proot-distro installed"
else
    echo "✓ proot-distro already installed"
fi

echo ""
echo "=== Step 3/5: Installing Ubuntu container ==="
if [ ! -d "$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu" ]; then
    echo "Installing Ubuntu..."
    
    # Define source and target
    PD_CONF="$PREFIX/etc/proot-distro/ubuntu.sh"
    
    # Attempt to source the definition to get the official URL
    if [ -f "$PD_CONF" ]; then
        # Use a subshell to avoid polluting environment
        eval $(grep '^TARBALL_URL=' "$PD_CONF")
        eval $(grep '^TARBALL_SHA256=' "$PD_CONF")
    fi
    
    # Fallback if parsing failed
    if [ -z "$TARBALL_URL" ]; then
        # Default to a known recent version (hardcoded fallback)
        TARBALL_URL="https://github.com/termux/proot-distro/releases/download/v4.30.1/ubuntu-questing-aarch64-pd-v4.30.1.tar.xz"
    fi

    CACHE_DIR="$PREFIX/var/lib/proot-distro/dlcache"
    mkdir -p "$CACHE_DIR"
    FILENAME=$(basename "$TARBALL_URL")
    CACHE_FILE="$CACHE_DIR/$FILENAME"
    
    # List of mirrors to try
    MIRRORS=(
        "https://ghproxy.net/$TARBALL_URL"
        "https://mirror.ghproxy.com/$TARBALL_URL"
        "$TARBALL_URL"
    )
    
    if [ ! -f "$CACHE_FILE" ]; then
        echo "Downloading Ubuntu rootfs (trying multiple mirrors)..."
        DOWNLOAD_SUCCESS=false
        
        for url in "${MIRRORS[@]}"; do
            echo "Trying: $url"
            # Try to download using curl (resume supported)
            if curl -L -C - --connect-timeout 5 --max-time 600 -o "$CACHE_FILE.part" "$url"; then
                if [ -s "$CACHE_FILE.part" ]; then
                    mv "$CACHE_FILE.part" "$CACHE_FILE"
                    DOWNLOAD_SUCCESS=true
                    echo " Download successful!"
                    break
                fi
            fi
            echo " Mirror failed, trying next..."
        done
        
        if [ "$DOWNLOAD_SUCCESS" = false ]; then
             echo "Warning: All mirrors failed. proot-distro will do standard install."
             rm -f "$CACHE_FILE.part"
        fi
    else
        echo "Found cached Ubuntu rootfs."
    fi

    # Run installation (will use cache if valid)
    proot-distro install ubuntu || { echo "Error: Ubuntu installation failed"; exit 1; }
    echo "✓ Ubuntu container installed"
else
    echo "✓ Ubuntu container already exists"
fi

echo ""
echo "=== Step 4/5: Installing dependencies inside Ubuntu ==="
echo "Installing Java, tmux, SSH, fzf..."
proot-distro login $DISTRO -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt update -y && apt install -y openjdk-8-jre-headless wget tmux curl fzf openssh-server bc
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
