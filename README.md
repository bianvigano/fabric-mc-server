# fabric-mc-server

All-in-one Fabric Minecraft server setup. Downloads, installs, configures EULA, and generates launcher + backup + systemd service.

## Features

- Auto-download latest Fabric loader + installer from official Meta API
- Accept EULA automatically
- Generate `start.sh` — server launcher (auto-detect tmux/screen/nohup)
- Generate `backup.sh` — auto-backup with rotation
- Generate systemd service for auto-start on boot
- Config command to edit `server.properties` from CLI
- Auto-kill stale processes on the configured port before start
- Zero config — just run and go

## Quick Start

```bash
# 1. Setup
./fabric-setup.sh 1.21.1

# 2. Start server
cd fabric-server
./start.sh start
```

## Setup Script

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
├── start.sh                  # Server launcher (tmux/screen/nohup)
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
./start.sh console          # tmux/screen: attach, nohup: tail log

# Custom RAM
JAVA_XMX=4G ./start.sh start

# Force specific backend
FORCE_BACKEND=nohup ./start.sh start
```

## Config (server.properties)

```bash
# View all properties
./start.sh config

# Read a property
./start.sh config server-port

# Set a property
./start.sh config server-port 25566
./start.sh config motd "My Cool Server"
./start.sh config difficulty hard
./start.sh config gamemode creative
./start.sh config max-players 20
./start.sh config online-mode false
```

Common keys:

| Key | Values | Default |
|-----|--------|---------|
| server-port | 1-65535 | 25565 |
| gamemode | survival/creative/adventure/spectator | survival |
| difficulty | peaceful/easy/normal/hard | normal |
| max-players | number | 20 |
| motd | text | A Minecraft Server |
| online-mode | true/false | true |
| pvp | true/false | true |
| level-seed | number/text | random |
| view-distance | 2-32 | 10 |
| simulation-distance | 2-32 | 10 |
| white-list | true/false | false |
| enforce-whitelist | true/false | false |

## Auto-Port Kill

If the configured port is still in use by an old process, start.sh auto-kills it before launching:

```
./start.sh start
[!] Port 25565 sudah dipakai. Killing: 12345
[*] Starting Fabric server...
    Port: 25565
```

## Backup

```bash
# Manual backup
./backup.sh

# Labeled backup
./backup.sh before-mods

# Custom location
BACKUP_DIR=/mnt/backup ./backup.sh

# Keep more backups (default: 24)
MAX_BACKUPS=48 ./backup.sh
```

### Auto-Backup (cron)

```bash
crontab -e
```

Add one of:

```bash
# Every 4 hours
0 */4 * * * /root/fabric-server/backup.sh auto

# Every hour
0 * * * * /root/fabric-server/backup.sh hourly

# Every 12 hours
0 */12 * * * /root/fabric-server/backup.sh auto
```

Backups exclude `libraries/`, `*.jar`, `logs/`, `crash-reports/`, and `world/session.lock`.

## Systemd (auto-start on boot)

```bash
sudo cp minecraft-fabric.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable minecraft-fabric
sudo systemctl start minecraft-fabric

# Status & logs
sudo systemctl status minecraft-fabric
sudo journalctl -u minecraft-fabric -f
```

## Backend Detection

`start.sh` auto-detects the best multiplexer:

1. **tmux** — test if session creation works
2. **screen** — test if session creation works
3. **nohup** — fallback, logs to `logs/console.log`

Force specific backend:
```bash
FORCE_BACKEND=tmux ./start.sh start
FORCE_BACKEND=screen ./start.sh start
FORCE_BACKEND=nohup ./start.sh start
```

## Updating

```bash
# Update launcher/backup scripts
cd ~/fabric-server
curl -fsSL https://raw.githubusercontent.com/bianvigano/fabric-mc-server/main/start.sh -o start.sh
curl -fsSL https://raw.githubusercontent.com/bianvigano/fabric-mc-server/main/backup.sh -o backup.sh
chmod +x start.sh backup.sh
```

## Requirements

- Java 17+
- curl, python3 (for setup script only)
- tmux or screen (optional, auto-detects)
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
