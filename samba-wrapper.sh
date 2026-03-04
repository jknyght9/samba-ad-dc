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

log "Samba wrapper starting..."

# Brief pause to ensure entrypoint cleanup is complete
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
# --debug-stdout: send debug output to stdout (captured by supervisor)
exec /usr/sbin/samba -i --debug-stdout
