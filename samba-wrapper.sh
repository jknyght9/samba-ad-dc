#!/bin/bash
# =============================================================================
# Samba Wrapper Script for Supervisor
#
# Ensures clean startup of Samba AD DC with proper process management
# =============================================================================

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [samba-wrapper] $1"
}

# Wait a moment to ensure any previous samba processes are fully stopped
sleep 2

# Kill any zombie samba processes (shouldn't happen but just in case)
pkill -9 samba 2>/dev/null || true
pkill -9 smbd 2>/dev/null || true
sleep 1

# Verify smb.conf exists
if [ ! -f /etc/samba/smb.conf ]; then
    log "ERROR: /etc/samba/smb.conf not found!"
    exit 1
fi

# Verify domain data exists
if [ ! -f /var/lib/samba/private/sam.ldb ]; then
    log "ERROR: Domain data not found! Run provisioning first."
    exit 1
fi

log "Starting Samba AD DC..."

# Start samba in foreground mode
# -i: interactive (foreground)
# -M single: don't fork child processes for each connection
exec /usr/sbin/samba -i --debug-stderr
