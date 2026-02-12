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

VERSION="5.1.0"
DISTRO="ubuntu"
GITHUB_RAW="https://raw.githubusercontent.com/FLEXIY0/MBSFT/main"
SERVICE_AVAILABLE=true  # Flag for service installation

clear
echo "============================================"
echo "  MBSFT v$VERSION Bootstrap"
echo "  Minecraft Beta Server For Termux"
echo "============================================"
echo ""
echo "This will setup proot Ubuntu environment with:"
echo "  • Ubuntu container via proot-distro"
echo "  • Java 8 + tmux + SSH daemon"
echo "  • MBSFT main script"
echo "  • Wrapper for seamless access"
echo "  • Persistent service (keeps MBSFT running)"
echo ""
read -p "Continue? (y/n): " yn
if [[ "$yn" != "y" ]]; then
    echo "Installation cancelled."
    exit 0
fi

echo ""
echo "=== Step 1/9: Updating Termux packages ==="
echo "Running pkg update..."
pkg update -y || { echo "Error: pkg update failed"; exit 1; }

echo ""
echo "Upgrading packages (including proot-distro)..."
pkg upgrade -y || { echo "Error: pkg upgrade failed"; exit 1; }
echo "✓ Packages upgraded"

echo ""
echo "=== Step 2/9: Installing proot-distro ==="
if ! command -v proot-distro &>/dev/null; then
    echo "Installing proot-distro package..."
    pkg install -y proot-distro || { echo "Error: proot-distro install failed"; exit 1; }
    echo "✓ proot-distro installed"
else
    echo "✓ proot-distro already installed"
fi

echo ""
echo "=== Step 3/9: Installing Ubuntu container ==="
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
            echo "  (Min speed: 1MB/s, Tolerance: 4s)"
            # -f: fail on HTTP errors
            # -L: follow redirects
            # -C -: resume
            # --speed-limit 1000000: abort if speed < 1MB/s
            # --speed-time 4: ...for 4 seconds
            if curl -fL -C - --connect-timeout 10 --speed-limit 1000000 --speed-time 4 --max-time 1200 --retry 1 -o "$CACHE_FILE.part" "$url"; then
                
                # 1. Check size (min 5MB to avoid broken downloads/error pages)
                FSIZE=$(wc -c < "$CACHE_FILE.part")
                if [ "$FSIZE" -lt 5000000 ]; then
                    echo "  Error: File too small ($FSIZE bytes). Likely corrupted."
                    rm -f "$CACHE_FILE.part"
                    continue
                fi

                # 2. Checksum validation (if available in proot-distro config)
                if [ -n "$TARBALL_SHA256" ] && command -v sha256sum >/dev/null; then
                     echo "  Verifying checksum..."
                     FILE_SHA=$(sha256sum "$CACHE_FILE.part" | cut -d' ' -f1)
                     if [ "$FILE_SHA" != "$TARBALL_SHA256" ]; then
                         echo "  Error: Checksum mismatch!"
                         echo "  Expected: $TARBALL_SHA256"
                         echo "  Got:      $FILE_SHA"
                         rm -f "$CACHE_FILE.part"
                         continue
                     fi
                     echo "  Checksum verified."
                fi

                mv "$CACHE_FILE.part" "$CACHE_FILE"
                DOWNLOAD_SUCCESS=true
                echo " Download successful!"
                break
            fi
            echo " Mirror failed or connection error, trying next..."
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
echo "=== Step 4/9: Installing dependencies inside Ubuntu ==="
echo "Installing Java, tmux, SSH, fzf, and IDE libs..."
proot-distro login $DISTRO -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt update -y && apt install -y openjdk-8-jre-headless wget tmux curl fzf openssh-server bc libatomic1 tar gzip ca-certificates procps build-essential python3 python3-pip libstdc++6 libgcc1 libgomp1 libitm1
" || { echo "Error: Package installation failed"; exit 1; }
echo "✓ Dependencies installed"

echo ""
echo "=== Step 5/9: Configuring SSH inside Ubuntu ==="
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
    # Ensure Port is set to 2222 (remove old entries to avoid duplicates)
    sed -i '/^Port/d' /etc/ssh/sshd_config
    echo 'Port 2222' >> /etc/ssh/sshd_config
"
echo "✓ SSH configured (port 2222)"

echo ""
echo "=== Step 6/9: Installing MBSFT main script ==="
echo "Downloading mbsft.sh from GitHub..."
proot-distro login $DISTRO -- bash -c "
    mkdir -p /usr/local/bin
    
    # List of mirrors (Proxy first for speed/access)
    URLS=(
        'https://ghproxy.net/https://raw.githubusercontent.com/FLEXIY0/MBSFT/main/mbsft.sh'
        'https://mirror.ghproxy.com/https://raw.githubusercontent.com/FLEXIY0/MBSFT/main/mbsft.sh'
        '$GITHUB_RAW/mbsft.sh'
    )

    DOWNLOAD_OK=false
    for url in \"\${URLS[@]}\"; do
        echo \"Downloading from: \$url\"
        # Add cache buster
        target_url=\"\$url?t=\$(date +%s)\"
        
        if curl -sL --connect-timeout 10 --max-time 30 -o /usr/local/bin/mbsft \"\$target_url\"; then
            # Verify file is not empty and looks like a script
            if [ -s /usr/local/bin/mbsft ] && grep -q 'bash' /usr/local/bin/mbsft; then
                chmod +x /usr/local/bin/mbsft
                DOWNLOAD_OK=true
                break
            fi
        fi
        echo \"  Failed, trying next...\"
    done

    if [ \"\$DOWNLOAD_OK\" = false ]; then
        exit 1
    fi
" || { echo "Error: Failed to download main script from any mirror"; exit 1; }
echo "✓ Main script installed at /usr/local/bin/mbsft"

echo ""
echo "=== Step 7/9: Creating wrapper script ==="
cat > "$PREFIX/bin/mbsft" << 'WRAPPER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# MBSFT v4.0 Wrapper
# Automatically enters proot Ubuntu and runs main script

# Bind mount Termux home to access server data
TERMUX_HOME="/data/data/com.termux/files/home"

# Start SSH with bind mount if not running (silent)
proot-distro login ubuntu --bind "$TERMUX_HOME:/termux-home" -- bash -c "
    if ! pgrep -x sshd > /dev/null 2>&1; then
        mkdir -p /run/sshd
        chmod 0755 /run/sshd
        /usr/sbin/sshd 2>/dev/null
    fi
" 2>/dev/null

# Run main script with bind mount
proot-distro login ubuntu --bind "$TERMUX_HOME:/termux-home" -- bash -c "
    if [ -z \"$MBSFT_BASE_DIR\" ]; then
         export MBSFT_BASE_DIR=/termux-home/mbsft-servers
    fi
    /usr/local/bin/mbsft \"\$@\"
" -- "$@"
WRAPPER_EOF

chmod +x "$PREFIX/bin/mbsft" || { echo "Error: Failed to create wrapper"; exit 1; }
echo "✓ Wrapper created at $PREFIX/bin/mbsft"

echo ""
echo "=== Step 8/9: Installing Termux service packages ==="
echo "Installing termux-services and termux-api..."

# Install termux-services (for runit service management)
if ! command -v sv &>/dev/null; then
    pkg install -y termux-services || {
        echo "Warning: termux-services install failed. Service will not be available."
        SERVICE_AVAILABLE=false
    }
else
    echo "✓ termux-services already installed"
fi

# Install termux-api (for wake-lock functionality)
if ! command -v termux-wake-lock &>/dev/null; then
    pkg install -y termux-api || {
        echo "Warning: termux-api install failed. Wake-lock feature will not be available."
    }
else
    echo "✓ termux-api already installed"
fi

if [ "$SERVICE_AVAILABLE" = true ]; then
    echo "✓ Service packages installed"
    echo ""
    echo "IMPORTANT: You need to restart Termux to activate termux-services!"
    echo "After restart, the service-daemon will be available."
else
    echo "⚠ Service installation incomplete - manual setup may be required"
fi

echo ""
echo "=== Step 9/9: Setting up MBSFT persistent service ==="

if [ "$SERVICE_AVAILABLE" = true ]; then
    echo "Creating MBSFT service structure..."

    # Create service directory
    SERVICE_DIR="$PREFIX/var/service/mbsft"
    mkdir -p "$SERVICE_DIR/log"

    # Check if service files exist in repo
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

    if [ -d "$SCRIPT_DIR/service/mbsft" ]; then
        echo "Installing service scripts from local repository..."

        # Copy run script
        if [ -f "$SCRIPT_DIR/service/mbsft/run" ]; then
            cp "$SCRIPT_DIR/service/mbsft/run" "$SERVICE_DIR/run"
            chmod +x "$SERVICE_DIR/run"
            echo "  ✓ Main service script installed"
        fi

        # Copy log/run script
        if [ -f "$SCRIPT_DIR/service/mbsft/log/run" ]; then
            cp "$SCRIPT_DIR/service/mbsft/log/run" "$SERVICE_DIR/log/run"
            chmod +x "$SERVICE_DIR/log/run"
            echo "  ✓ Log service script installed"
        fi

        # Copy finish script
        if [ -f "$SCRIPT_DIR/service/mbsft/finish" ]; then
            cp "$SCRIPT_DIR/service/mbsft/finish" "$SERVICE_DIR/finish"
            chmod +x "$SERVICE_DIR/finish"
            echo "  ✓ Finish script installed"
        fi
    else
        echo "Downloading service scripts from GitHub..."

        # Download run script
        curl -sL "$GITHUB_RAW/service/mbsft/run?t=$(date +%s)" -o "$SERVICE_DIR/run" && \
            chmod +x "$SERVICE_DIR/run" && \
            echo "  ✓ Main service script installed" || \
            echo "  ⚠ Failed to download main service script"

        # Download log/run script
        curl -sL "$GITHUB_RAW/service/mbsft/log/run?t=$(date +%s)" -o "$SERVICE_DIR/log/run" && \
            chmod +x "$SERVICE_DIR/log/run" && \
            echo "  ✓ Log service script installed" || \
            echo "  ⚠ Failed to download log service script"

        # Download finish script
        curl -sL "$GITHUB_RAW/service/mbsft/finish?t=$(date +%s)" -o "$SERVICE_DIR/finish" && \
            chmod +x "$SERVICE_DIR/finish" && \
            echo "  ✓ Finish script installed" || \
            echo "  ⚠ Failed to download finish script"
    fi

    # Create log directory
    mkdir -p "$HOME/.mbsft-service-logs"

    echo "✓ Service structure created"
    echo ""
    echo "Service is installed but NOT enabled by default."
    echo "To enable persistent service (keeps MBSFT running):"
    echo "  1. Restart Termux (close and reopen app)"
    echo "  2. Run: sv-enable mbsft"
    echo "  3. Start service: sv up mbsft"
    echo ""
    echo "Service commands:"
    echo "  sv up mbsft       - Start service"
    echo "  sv down mbsft     - Stop service"
    echo "  sv status mbsft   - Check status"
    echo "  sv restart mbsft  - Restart service"
    echo ""
    echo "View logs:"
    echo "  tail -f ~/.mbsft-service-logs/current"
else
    echo "⚠ Skipping service setup (termux-services not available)"
    echo "You can still use MBSFT normally with: mbsft"
fi

echo ""
echo "============================================"
echo "  ✓ Installation Complete!"
echo "============================================"
echo ""
echo "Quick Start:"
echo "  mbsft          - Launch MBSFT menu"
echo ""

if [ "$SERVICE_AVAILABLE" = true ]; then
    echo "Persistent Service (Recommended):"
    echo "  After restarting Termux:"
    echo "    sv-enable mbsft   - Enable service (auto-start on boot)"
    echo "    sv up mbsft       - Start service now"
    echo ""
    echo "  Benefits:"
    echo "    • MBSFT keeps running even when Termux is closed"
    echo "    • SSH daemon stays active"
    echo "    • Server watchdogs/autosave persist"
    echo "    • Automatic restart on crash"
    echo ""
fi

echo "SSH Access (Ubuntu container):"
echo "  Port: 2222 (inside proot)"
echo "  User: root"
echo ""
echo "To setup SSH:"
echo "  1. Run: mbsft"
echo "  2. Go to: SSH → Add SSH key"
echo "  3. Or set password with 'passwd' inside proot"
echo ""
echo "SSH will auto-start when you run mbsft or when service is running."
echo ""
