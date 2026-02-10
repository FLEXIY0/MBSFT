#!/data/data/com.termux/files/usr/bin/bash

# ============================================
# MBSFT v4.0 Bootstrap Script
# One-time setup for proot Ubuntu environment
# ============================================

VERSION="4.0"
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
    proot-distro install $DISTRO || { echo "Error: Ubuntu installation failed"; exit 1; }
    echo "✓ Ubuntu container installed"
else
    echo "✓ Ubuntu container already exists"
fi

echo ""
echo "=== Step 3/5: Installing dependencies inside Ubuntu ==="
echo "Installing Java, tmux, systemd, fzf..."
proot-distro login $DISTRO -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt update -y 2>/dev/null
    apt install -y openjdk-8-jre-headless wget tmux curl fzf 2>/dev/null
" || { echo "Warning: Some packages may not have installed"; }
echo "✓ Dependencies installed"

echo ""
echo "=== Step 4/5: Installing MBSFT main script ==="
echo "Downloading mbsft.sh from GitHub..."
proot-distro login $DISTRO -- bash -c "
    mkdir -p /usr/local/bin
    wget -q -O /usr/local/bin/mbsft '$GITHUB_RAW/mbsft.sh' || exit 1
    chmod +x /usr/local/bin/mbsft
" || { echo "Error: Failed to download main script"; exit 1; }
echo "✓ Main script installed at /usr/local/bin/mbsft"

echo ""
echo "=== Step 5/5: Creating wrapper script ==="
cat > "$PREFIX/bin/mbsft" << 'WRAPPER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# MBSFT v4.0 Wrapper
# Automatically enters proot Ubuntu and runs main script

# Bind mount Termux home to access server data
TERMUX_HOME="/data/data/com.termux/files/home"
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
echo "Run: mbsft"
echo ""
echo "This will automatically enter Ubuntu proot"
echo "and launch the MBSFT menu."
echo ""
