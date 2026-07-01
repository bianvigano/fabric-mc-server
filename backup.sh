#!/bin/bash
# backup.sh — Fabric Minecraft Server Backup
# Usage: ./backup.sh [label]
# Cron: 0 */4 * * * /path/to/backup.sh auto

set -e

SERVER_DIR="$(cd "$(dirname "$0")/" && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$SERVER_DIR/../minecraft-backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LABEL="${1:-manual}"
BACKUP_NAME="fabric-${LABEL}-${TIMESTAMP}"
MAX_BACKUPS="${MAX_BACKUPS:-24}"
PID_FILE="$SERVER_DIR/.server.pid"
SESSION_NAME="minecraft-fabric"

mkdir -p "$BACKUP_DIR"

echo "[*] Starting backup: $BACKUP_NAME"
echo "    From: $SERVER_DIR"
echo "    To:   $BACKUP_DIR"

# --- Tell server to save (auto-detect backend) ---
send_cmd() {
    local cmd="$1"
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        tmux send-keys -t "$SESSION_NAME" "$cmd" Enter
    elif screen -list | grep -q "$SESSION_NAME" 2>/dev/null; then
        screen -S "$SESSION_NAME" -p 0 -X stuff "${cmd}^M"
    else
        # nohup: no way to send commands directly
        return 0
    fi
}

# Check if server is running
server_running() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        return 0
    elif tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        return 0
    elif screen -list | grep -q "$SESSION_NAME" 2>/dev/null; then
        return 0
    fi
    return 1
}

if server_running; then
    echo "[*] Server jalan — telling it to save..."
    send_cmd "say [Backup] Starting backup..."
    send_cmd "save-all"
    sleep 5
    send_cmd "save-off"
    sleep 2
fi

# --- Create backup ---
cd "$SERVER_DIR"
tar czf "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" \
    --exclude='libraries' \
    --exclude='*.jar' \
    --exclude='logs' \
    --exclude='crash-reports' \
    --exclude='world/session.lock' \
    .

BACKUP_SIZE=$(du -h "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" | cut -f1)
echo "[*] Backup created: ${BACKUP_NAME}.tar.gz ($BACKUP_SIZE)"

# --- Re-enable saves ---
if server_running; then
    send_cmd "save-on"
    send_cmd "say [Backup] Done!"
fi

# --- Cleanup old backups ---
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/fabric-*.tar.gz 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
    DELETED=$(ls -1t "$BACKUP_DIR"/fabric-*.tar.gz | tail -n +$((MAX_BACKUPS + 1)) | wc -l)
    ls -1t "$BACKUP_DIR"/fabric-*.tar.gz | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f
    echo "[*] Cleaned $DELETED old backups (keeping last $MAX_BACKUPS)"
fi

echo "[*] Backup complete."

# --- List current backups ---
echo ""
echo "Backups di $BACKUP_DIR:"
ls -lh "$BACKUP_DIR"/fabric-*.tar.gz 2>/dev/null | tail -5
