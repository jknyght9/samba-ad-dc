#!/bin/bash
set -e

# =============================================================================
# Samba AD DC Entrypoint Script
#
# Handles both domain provisioning (new domain) and domain join (replica DC)
# with proper detection of existing data to avoid race conditions.
# =============================================================================

# Required environment variables
: "${DOMAIN:?DOMAIN environment variable required (e.g., JDCLABS.LAN)}"
: "${DOMAINNAME:?DOMAINNAME environment variable required (e.g., JDCLABS)}"
: "${DOMAINPASS:?DOMAINPASS environment variable required}"
: "${HOSTIP:?HOSTIP environment variable required}"

# Optional environment variables with defaults
DNSFORWARDER="${DNSFORWARDER:-8.8.8.8}"
JOIN="${JOIN:-false}"
DCIP="${DCIP:-}"
JOINSITE="${JOINSITE:-Default-First-Site-Name}"
INSECURELDAP="${INSECURELDAP:-false}"
NOCOMPLEXITY="${NOCOMPLEXITY:-false}"

# Derived variables
REALM=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
DOMAIN_LOWER=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]')
HOSTNAME=$(hostname)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if domain is already provisioned (data exists)
is_provisioned() {
    [ -f "/var/lib/samba/private/sam.ldb" ]
}

# Check if this DC has joined a domain
is_joined() {
    [ -f "/var/lib/samba/private/secrets.ldb" ] && \
    [ -f "/var/lib/samba/private/sam.ldb" ]
}

# Stop any running samba processes (cleanup from previous runs)
stop_samba() {
    log "Stopping any existing Samba processes..."
    pkill -9 samba 2>/dev/null || true
    pkill -9 smbd 2>/dev/null || true
    pkill -9 nmbd 2>/dev/null || true
    pkill -9 winbindd 2>/dev/null || true
    sleep 2
}

# Configure Kerberos
configure_kerberos() {
    log "Configuring Kerberos for realm $REALM..."
    cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = false
    dns_lookup_kdc = true
    rdns = false

[realms]
    $REALM = {
        kdc = $HOSTNAME.$DOMAIN_LOWER
        admin_server = $HOSTNAME.$DOMAIN_LOWER
    }

[domain_realm]
    .$DOMAIN_LOWER = $REALM
    $DOMAIN_LOWER = $REALM
EOF

    # Copy to mounted volume for persistence
    cp /etc/krb5.conf /etc/krb5/krb5.conf 2>/dev/null || true
}

# Provision a new AD domain
provision_domain() {
    log "Provisioning new AD domain: $REALM"

    # Remove any stale data
    rm -rf /var/lib/samba/*
    rm -rf /var/cache/samba/*
    rm -f /etc/samba/smb.conf

    # Provision the domain
    samba-tool domain provision \
        --realm="$REALM" \
        --domain="$DOMAINNAME" \
        --server-role=dc \
        --dns-backend=SAMBA_INTERNAL \
        --adminpass="$DOMAINPASS" \
        --host-ip="$HOSTIP" \
        --option="dns forwarder = $DNSFORWARDER" \
        --use-rfc2307

    log "Domain provisioned successfully"
}

# Join an existing domain as a replica DC
join_domain() {
    log "Joining existing domain: $REALM as replica DC"

    if [ -z "$DCIP" ]; then
        log "ERROR: DCIP is required when JOIN=true"
        exit 1
    fi

    # Remove any stale data
    rm -rf /var/lib/samba/*
    rm -rf /var/cache/samba/*
    rm -f /etc/samba/smb.conf

    # Wait for primary DC to be available
    log "Waiting for primary DC at $DCIP to be available..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if nc -z "$DCIP" 389 2>/dev/null; then
            log "Primary DC is reachable"
            break
        fi
        log "Waiting for primary DC... ($retries attempts remaining)"
        sleep 10
        retries=$((retries - 1))
    done

    if [ $retries -eq 0 ]; then
        log "ERROR: Could not reach primary DC at $DCIP:389"
        exit 1
    fi

    # Join the domain
    samba-tool domain join "$REALM" DC \
        --dns-backend=SAMBA_INTERNAL \
        --realm="$REALM" \
        --username=Administrator \
        --password="$DOMAINPASS" \
        --server="$DCIP" \
        --site="$JOINSITE" \
        --option="dns forwarder = $DNSFORWARDER"

    log "Successfully joined domain as replica DC"
}

# Apply post-provisioning settings
apply_settings() {
    log "Applying post-provisioning settings..."

    # Disable password complexity if requested
    if [ "$NOCOMPLEXITY" = "true" ]; then
        log "Disabling password complexity..."
        samba-tool domain passwordsettings set --complexity=off 2>/dev/null || true
        samba-tool domain passwordsettings set --min-pwd-length=1 2>/dev/null || true
        samba-tool domain passwordsettings set --min-pwd-age=0 2>/dev/null || true
        samba-tool domain passwordsettings set --max-pwd-age=0 2>/dev/null || true
    fi

    # Enable insecure LDAP if requested (for testing)
    if [ "$INSECURELDAP" = "true" ]; then
        log "Enabling insecure LDAP binds..."
        if ! grep -q "ldap server require strong auth" /etc/samba/smb.conf; then
            sed -i '/\[global\]/a\\tldap server require strong auth = no' /etc/samba/smb.conf
        fi
    fi
}

# Update smb.conf with required settings
update_smb_conf() {
    log "Updating smb.conf..."

    # Ensure bind interfaces are set correctly
    if ! grep -q "interfaces" /etc/samba/smb.conf; then
        sed -i "/\[global\]/a\\\\tinterfaces = lo $HOSTIP\\n\\tbind interfaces only = yes" /etc/samba/smb.conf
    fi

    # Add DNS forwarder if not present
    if ! grep -q "dns forwarder" /etc/samba/smb.conf; then
        sed -i "/\[global\]/a\\\\tdns forwarder = $DNSFORWARDER" /etc/samba/smb.conf
    fi
}

# =============================================================================
# Main entrypoint logic
# =============================================================================

log "Starting Samba AD DC entrypoint..."
log "  DOMAIN: $DOMAIN"
log "  DOMAINNAME: $DOMAINNAME"
log "  HOSTIP: $HOSTIP"
log "  JOIN: $JOIN"
log "  DCIP: ${DCIP:-<not set>}"

# Always stop any existing samba processes first
stop_samba

# Configure Kerberos
configure_kerberos

# Check if we need to provision/join or just start
if is_provisioned && [ "$JOIN" = "false" ]; then
    log "Domain data exists, skipping provisioning"
elif is_joined && [ "$JOIN" = "true" ]; then
    log "Already joined to domain, skipping join"
else
    if [ "$JOIN" = "true" ]; then
        join_domain
    else
        provision_domain
    fi
    apply_settings
fi

# Update configuration
update_smb_conf

# Ensure samba is stopped before supervisor takes over
stop_samba

log "Starting supervisor to manage services..."
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
