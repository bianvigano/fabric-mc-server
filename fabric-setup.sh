#!/bin/bash
# fabric-setup.sh
# All-in-one: download Fabric server + auto start + backup + systemd
# Usage: ./fabric-setup.sh [MC_VERSION] [LOADER_VERSION] [INSTALLER_VERSION]
# Example: ./fabric-setup.sh 1.21.1

set -e

MC_VERSION="${1:-1.21.1}"
LOADER_VERSION="$2"
INSTALLER_VERSION="$3"
INSTALL_DIR="${4:-./fabric-server}"
META_BASE="https://meta.fabricmc.net/v2"

echo "========================================"
echo "  Fabric Server Setup & Launcher"
echo "========================================"
echo "MC Version: $MC_VERSION"
echo "Install Dir: $INSTALL_DIR"
echo ""

# --- Step 1: Resolve loader version ---
if [ -z "$LOADER_VERSION" ]; then
    echo "[1/7] Mendapatkan latest loader version..."
    LOADER_VERSION=$(curl -s "$META_BASE/versions/loader" | python3 -c "
import sys, json
data = json.load(sys.stdin)
stable = [x for x in data if x.get('stable')]
print(stable[0]['version'])
")
fi
echo "  Loader: $LOADER_VERSION"

# --- Step 2: Resolve installer version ---
if [ -z "$INSTALLER_VERSION" ]; then
    echo "[2/7] Mendapatkan latest installer version..."
    INSTALLER_VERSION=$(curl -s "$META_BASE/versions/installer" | python3 -c "
import sys, json
data = json.load(sys.stdin)
stable = [x for x in data if x.get('stable')]
print(stable[0]['version'])
")
fi
echo "  Installer: $INSTALLER_VERSION"

# --- Step 3: Download installer jar ---
INSTALLER_JAR="fabric-installer-${INSTALLER_VERSION}.jar"
INSTALLER_URL="https://maven.fabricmc.net/net/fabricmc/fabric-installer/${INSTALLER_VERSION}/${INSTALLER_JAR}"

echo "[3/7] Downloading installer jar..."
mkdir -p "$INSTALL_DIR"
curl -fsSL -o "$INSTALL_DIR/$INSTALLER_JAR" "$INSTALLER_URL"
echo "  Saved: $INSTALL_DIR/$INSTALLER_JAR"

# --- Step 4: Install Fabric server ---
echo "[4/7] Installing Fabric server..."
cd "$INSTALL_DIR"
java -jar "$INSTALLER_JAR" server \
    -mcversion "$MC_VERSION" \
    -loader "$LOADER_VERSION" \
    -downloadMinecraft

# --- Step 5: Accept EULA ---
echo "[5/7] Accepting EULA..."
if [ -f "eula.txt" ]; then
    sed -i 's/eula=false/eula=true/' eula.txt
else
    echo "eula=true" > eula.txt
fi
echo "  EULA accepted."

# --- Step 6: Create start script + backup script + systemd service ---
SERVER_JAR=$(ls -1 fabric-server-*.jar 2>/dev/null | head -1)

echo "[6/7] Creating scripts and service..."

# --- Start script ---
cat > start.sh << STARTEOF
#!/bin/bash
# Auto-generated start script for Fabric $MC_VERSION / Loader $LOADER_VERSION
# Usage: ./start.sh {start|stop|restart|status|console}
# Auto-detects: tmux > screen > nohup fallback

set -e

SESSION_NAME="minecraft-fabric"
JAVA_XMS="\${JAVA_XMS:-1G}"
JAVA_XMX="\${JAVA_XMX:-2G}"
JAVA_FLAGS="-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200"
SERVER_JAR="$SERVER_JAR"
PID_FILE=".server.pid"

# Detect available multiplexer
detect_backend() {
    if command -v tmux &>/dev/null; then
        echo "tmux"
    elif command -v screen &>/dev/null; then
        echo "screen"
    else
        echo "nohup"
    fi
}

BACKEND="\${FORCE_BACKEND:-\$(detect_backend)}"

is_running() {
    case "\$BACKEND" in
        tmux)
            tmux has-session -t "\$SESSION_NAME" 2>/dev/null
            ;;
        screen)
            screen -list | grep -q "\$SESSION_NAME"
            ;;
        nohup)
            [ -f "\$PID_FILE" ] && kill -0 "\$(cat "\$PID_FILE")" 2>/dev/null
            ;;
    esac
}

do_start() {
    if is_running; then
        echo "[*] Server sudah jalan (\$BACKEND: \$SESSION_NAME)"
        return
    fi
    echo "[*] Starting Fabric server (MC $MC_VERSION, Loader $LOADER_VERSION)..."
    echo "    RAM: \$JAVA_XMS - \$JAVA_XMX"
    echo "    Backend: \$BACKEND"

    case "\$BACKEND" in
        tmux)
            tmux new-session -d -s "\$SESSION_NAME" "java \$JAVA_FLAGS -Xms\$JAVA_XMS -Xmx\$JAVA_XMX -jar \$SERVER_JAR nogui"
            echo "    Attach: tmux attach -t \$SESSION_NAME"
            echo "    Detach: Ctrl+B, D"
            ;;
        screen)
            screen -dmS "\$SESSION_NAME" java \$JAVA_FLAGS -Xms"\$JAVA_XMS" -Xmx"\$JAVA_XMX" -jar "\$SERVER_JAR" nogui
            echo "    Attach: screen -r \$SESSION_NAME"
            echo "    Detach: Ctrl+A, D"
            ;;
        nohup)
            mkdir -p logs
            nohup java \$JAVA_FLAGS -Xms"\$JAVA_XMS" -Xmx"\$JAVA_XMX" -jar "\$SERVER_JAR" nogui > logs/console.log 2>&1 &
            echo \$! > "\$PID_FILE"
            echo "    Log: tail -f logs/console.log"
            ;;
    esac

    sleep 3
    if is_running; then
        echo "[*] Server started successfully."
    else
        echo "[ERROR] Server gagal start. Cek log."
        exit 1
    fi
}

do_stop() {
    if ! is_running; then
        echo "[*] Server tidak jalan."
        rm -f "\$PID_FILE"
        return
    fi
    echo "[*] Stopping server..."

    case "\$BACKEND" in
        tmux)
            tmux send-keys -t "\$SESSION_NAME" "save-all" Enter
            sleep 2
            tmux send-keys -t "\$SESSION_NAME" "stop" Enter
            ;;
        screen)
            screen -S "\$SESSION_NAME" -p 0 -X stuff "save-all^M"
            sleep 2
            screen -S "\$SESSION_NAME" -p 0 -X stuff "stop^M"
            ;;
        nohup)
            if [ -f "\$PID_FILE" ]; then
                kill "\$(cat "\$PID_FILE")" 2>/dev/null || true
            fi
            ;;
    esac

    for i in \$(seq 1 30); do
        if ! is_running; then
            echo "[*] Server stopped."
            rm -f "\$PID_FILE"
            return
        fi
        sleep 1
    done

    echo "[WARN] Force killing..."
    case "\$BACKEND" in
        tmux)   tmux kill-session -t "\$SESSION_NAME" 2>/dev/null || true ;;
        screen) screen -S "\$SESSION_NAME" -X quit 2>/dev/null || true ;;
        nohup)  kill -9 "\$(cat "\$PID_FILE")" 2>/dev/null || true ;;
    esac
    rm -f "\$PID_FILE"
}

do_status() {
    if is_running; then
        echo "[*] Server status: RUNNING (\$BACKEND: \$SESSION_NAME)"
    else
        echo "[*] Server status: STOPPED"
    fi
}

do_console() {
    if ! is_running; then
        echo "[*] Server tidak jalan."
        exit 1
    fi
    case "\$BACKEND" in
        tmux)
            echo "[*] Attaching (Ctrl+B, D to detach)..."
            sleep 1
            tmux attach -t "\$SESSION_NAME"
            ;;
        screen)
            echo "[*] Attaching (Ctrl+A, D to detach)..."
            sleep 1
            screen -r "\$SESSION_NAME"
            ;;
        nohup)
            echo "[*] Tailing console log (Ctrl+C to stop tailing)..."
            tail -f logs/console.log
            ;;
    esac
}

case "\${1}" in
    start)          do_start ;;
    stop)           do_stop ;;
    restart)        do_stop; sleep 2; do_start ;;
    status)         do_status ;;
    console|attach) do_console ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|console}"
        echo ""
        echo "Env vars:"
        echo "  JAVA_XMS       Min RAM  (default: 1G)"
        echo "  JAVA_XMX       Max RAM  (default: 2G)"
        echo "  FORCE_BACKEND  tmux|screen|nohup (auto-detected)"
        echo ""
        echo "Examples:"
        echo "  ./start.sh start"
        echo "  JAVA_XMX=4G ./start.sh start"
        echo "  FORCE_BACKEND=nohup ./start.sh start"
        ;;
esac
STARTEOF
chmod +x start.sh

# --- Backup script ---
BACKUP_DIR="$(dirname "$INSTALL_DIR")/minecraft-backups"

cat > backup.sh << BACKEOF
#!/bin/bash
# Auto-generated backup script
# Usage: ./backup.sh [label]
# Or add to crontab: 0 */4 * * * /path/to/backup.sh hourly

set -e

SERVER_DIR="$(cd "$(dirname "$0")/" && pwd)"
BACKUP_DIR="$(dirname "$SERVER_DIR")/minecraft-backups"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
LABEL="\${1:-manual}"
BACKUP_NAME="fabric-mc${MC_VERSION}-\${LABEL}-\${TIMESTAMP}"
MAX_BACKUPS="\${MAX_BACKUPS:-24}"

mkdir -p "\$BACKUP_DIR"

echo "[*] Starting backup: \$BACKUP_NAME"
echo "    From: \$SERVER_DIR"
echo "    To:   \$BACKUP_DIR"

# Tell server to save
if screen -list | grep -q "minecraft-fabric" 2>/dev/null; then
    screen -S minecraft-fabric -p 0 -X stuff "say [Backup] Starting backup...^M"
    screen -S minecraft-fabric -p 0 -X stuff "save-all^M"
    sleep 5
    screen -S minecraft-fabric -p 0 -X stuff "save-off^M"
    sleep 3
elif tmux has-session -t minecraft-fabric 2>/dev/null; then
    tmux send-keys -t minecraft-fabric "say [Backup] Starting backup..." Enter
    tmux send-keys -t minecraft-fabric "save-all" Enter
    sleep 5
    tmux send-keys -t minecraft-fabric "save-off" Enter
    sleep 3
fi

# Create tar.gz
cd "\$SERVER_DIR"
tar czf "\$BACKUP_DIR/\${BACKUP_NAME}.tar.gz" \
    --exclude='libraries' \
    --exclude='*.jar' \
    --exclude='logs' \
    --exclude='crash-reports' \
    .

# Re-enable saves
if screen -list | grep -q "minecraft-fabric" 2>/dev/null; then
    screen -S minecraft-fabric -p 0 -X stuff "save-on^M"
    screen -S minecraft-fabric -p 0 -X stuff "say [Backup] Done!^M"
elif tmux has-session -t minecraft-fabric 2>/dev/null; then
    tmux send-keys -t minecraft-fabric "save-on" Enter
    tmux send-keys -t minecraft-fabric "say [Backup] Done!" Enter
fi

# Cleanup old backups
if [ -d "\$BACKUP_DIR" ]; then
    BACKUP_COUNT=\$(ls -1 "\$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)
    if [ "\$BACKUP_COUNT" -gt "\$MAX_BACKUPS" ]; then
        ls -1t "\$BACKUP_DIR"/*.tar.gz | tail -n +\$((MAX_BACKUPS + 1)) | xargs rm -f
        echo "  Cleaned old backups (keeping last \$MAX_BACKUPS)"
    fi
fi

echo "[*] Backup complete: \$BACKUP_DIR/\${BACKUP_NAME}.tar.gz"
echo "  Size: \$(du -h "\$BACKUP_DIR/\${BACKUP_NAME}.tar.gz" | cut -f1)"
BACKEOF
chmod +x backup.sh

# --- Systemd service ---
SERVICE_FILE="minecraft-fabric.service"

cat > "$SERVICE_FILE" << SERVICEEOF
[Unit]
Description=Fabric Minecraft Server (MC $MC_VERSION, Loader $LOADER_VERSION)
After=network.target
StartLimitIntervalSec=600
StartLimitBurst=3

[Service]
Type=forking
User=$(whoami)
Group=$(id -gn)
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/screen -dmS minecraft-fabric java -Xms1G -Xmx2G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -jar $SERVER_JAR nogui
ExecStop=/usr/bin/screen -S minecraft-fabric -p 0 -X stuff "save-all^M"
ExecStop=/bin/sleep 3
ExecStop=/usr/bin/screen -S minecraft-fabric -p 0 -X stuff "stop^M"
ExecStop=/bin/sleep 20
ExecStop=/usr/bin/screen -S minecraft-fabric -X quit
Restart=on-failure
RestartSec=30
StandardOutput=append:$INSTALL_DIR/logs/systemd.log
StandardError=append:$INSTALL_DIR/logs/systemd.log

[Install]
WantedBy=multi-user.target
SERVICEEOF

chmod +x "$SERVICE_FILE"

# --- Caddy config (if Caddy is installed) ---
if command -v caddy &> /dev/null; then
    # Detected installed Caddy so provide MINECRAFT Caddyfile
    CADDYFILE="$INSTALL_DIR/Caddyfile"
    cat > "$CADDYFILE" << CADDEOF
# Caddy config for Minecraft reverse proxy
# Place this in /etc/caddy/Caddyfile or include it
# Usage: caddy config --adapter caddyfile /etc/caddy/Caddyfile

:25565 {
    reverse_proxy localhost:25565
}
CADDEOF
    echo "  Caddy config written to: $CADDYFILE"
    echo "  (Applied automatically via `caddy reload` if you place it in /etc/caddy/Caddyfile)"
fi

# --- Cleanup installer jar ---
rm -f "$INSTALLER_JAR"

echo "  Created:    start.sh"
echo "  Created:    backup.sh"
echo "  Created:    $SERVICE_FILE
echo "  Backup dir: $BACKUP_DIR"

# --- Step 7: Print summary ---
echo ""
echo "========================================"
echo "  Setup Complete!"
echo "========================================"
echo ""
echo "Server ada di: $INSTALL_DIR/"
echo "Isi folder:"
echo "  - server.jar, libraries, mods, config, dll"
echo ""
echo "Perintah:"
echo "  cd $INSTALL_DIR"
echo "  ./start.sh start            # Start server"
echo "  ./start.sh stop             # Stop server"
echo "  ./start.sh console          # Attach ke console"
echo "  ./backup.sh                 # Backup manual"
echo "  JAVA_XMX=4G ./start.sh start   # Start dengan 4GB RAM"
echo ""
echo "Systemd service (auto-start on boot):"
echo "  sudo cp $SERVICE_FILE /etc/systemd/system/"
echo "  sudo systemctl enable minecraft-fabric"
echo "  sudo systemctl start minecraft-fabric"
echo "  sudo systemctl status minecraft-fabric"
echo ""
echo "Backup otomatis dengan cron:"
echo "  crontab -e"
echo "  # Backup tiap 4 jam:  0 */4 * * * $INSTALL_DIR/backup.sh auto"
echo ""
echo "All set! Happy crafting."
