# fabric-mc-server

All-in-one Fabric Minecraft server setup script. Downloads, installs, configures EULA, and generates launcher + backup + systemd service.

## Features

- Auto-download latest Fabric loader + installer from official Meta API
- Accept EULA automatically
- Generate `start.sh` (start/stop/restart/status/console via screen)
- Generate `backup.sh` (auto-backup with rotation)
- Generate systemd service for auto-start on boot
- Zero config — just run and go

## Quick Start

```bash
./fabric-setup.sh 1.21.1
cd fabric-server
./start.sh start
```

## Usage

```
./fabric-setup.sh [MC_VERSION] [LOADER_VERSION] [INSTALLER_VERSION] [INSTALL_DIR]
```

| Arg | Default | Description |
|-----|---------|-------------|
| MC_VERSION | 1.21.1 | Minecraft version |
| LOADER_VERSION | latest | Fabric loader version |
| INSTALLER_VERSION | latest | Fabric installer version |
| INSTALL_DIR | ./fabric-server | Output directory |

## Generated Files

```
fabric-server/
├── start.sh                  # Server launcher (screen-based)
├── backup.sh                 # Backup with auto-rotation
├── minecraft-fabric.service  # Systemd service file
├── fabric-server-*.jar       # Fabric server jar
├── eula.txt                  # Auto-accepted
├── libraries/                # Fabric dependencies
└── server.properties         # Minecraft config
```

## Commands

```bash
# Start/Stop
./start.sh start
./start.sh stop
./start.sh restart

# Monitor
./start.sh status
./start.sh console          # Ctrl+A, D to detach

# Custom RAM
JAVA_XMX=4G ./start.sh start
```

## Auto-Backup

```bash
# Manual
./backup.sh

# Cron (every 4 hours)
crontab -e
0 */4 * * * /path/to/fabric-server/backup.sh auto
```

Backups exclude `libraries`, `*.jar`, `logs`, `crash-reports`. Default: keep 24 latest.

## Systemd

```bash
sudo cp minecraft-fabric.service /etc/systemd/system/
sudo systemctl enable minecraft-fabric
sudo systemctl start minecraft-fabric
sudo systemctl status minecraft-fabric
```

## Requirements

- Java 17+
- screen
- curl, python3 (for setup script)
- tar (for backup)

## How It Works

1. Queries `https://meta.fabricmc.net/v2/versions/loader` for latest stable loader
2. Queries `https://meta.fabricmc.net/v2/versions/installer` for latest installer
3. Downloads installer jar from `maven.fabricmc.net`
4. Runs `java -jar fabric-installer.jar server -mcversion X -loader Y -downloadMinecraft`
5. Accepts EULA
6. Generates start.sh, backup.sh, systemd service
7. Cleans up installer jar

## License

MIT
