# MBSFT v4.0
<img width="1920" height="1036" alt="изображение" src="https://github.com/user-attachments/assets/93519340-7f53-499c-bb4e-58497c5203d5" />

CLI manager for Minecraft Beta 1.7.3 servers on Termux (Android).

**v4.0**: Migrated to Ubuntu proot container with systemd services for improved reliability!

## Install

Run **once** in Termux to setup:

```bash
curl -sL https://raw.githubusercontent.com/FLEXIY0/MBSFT/main/bootstrap.sh | bash
```

This will:
- Install proot-distro and Ubuntu container
- Setup Java 8 + dependencies inside Ubuntu
- Create `mbsft` wrapper command

## Update

The script auto-updates on launch.

## Use

- **mbsft** - open menu (automatically enters Ubuntu proot)

## Features

- Multiple servers
- RAM/Port config
- **Auto-restart** (systemd watchdog service)
- **Auto-save** (systemd timer service)
- SSH management
- systemd service management (reliable, persistent)
- journalctl logging
- Servers: Poseidon, Reindev, FoxLoader

## What's New in v4.0

- ✅ **Ubuntu proot container** - Standard Linux environment
- ✅ **systemd services** - Reliable service management instead of PID files
- ✅ **journalctl logging** - Proper log management
- ✅ **Improved reliability** - No more service failures
- ✅ **Standard paths** - No Termux-specific hacks

## Upgrading from v3.x

v4.0 is a **breaking change**. To upgrade:

1. Backup your servers: `cp -r ~/mbsft-servers ~/mbsft-servers.backup`
2. Run new bootstrap: `curl -sL https://raw.githubusercontent.com/FLEXIY0/MBSFT/main/bootstrap.sh | bash`
3. Copy servers back if needed: `cp -r ~/mbsft-servers.backup/* ~/mbsft-servers/`
4. Re-enable services manually for each server (services don't auto-migrate)
