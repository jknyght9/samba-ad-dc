# Custom Samba AD Domain Controller Image
# Based on Ubuntu 22.04 with Samba 4.15+
#
# Fixes issues with the nowsci/samba-domain image:
# - Race condition during domain provisioning (samba starts twice)
# - Proper detection of existing domain data
# - Clean service startup sequencing via supervisor

FROM ubuntu:22.04

LABEL maintainer="Proxmox Lab"
LABEL description="Samba Active Directory Domain Controller"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install Samba AD DC and dependencies
RUN apt-get update && apt-get install -y \
    samba \
    samba-dsdb-modules \
    samba-vfs-modules \
    winbind \
    libpam-winbind \
    libnss-winbind \
    krb5-user \
    krb5-kdc \
    ldb-tools \
    ldap-utils \
    dnsutils \
    supervisor \
    netcat-openbsd \
    procps \
    net-tools \
    iputils-ping \
    python3 \
    python3-setproctitle \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /var/lib/samba/private \
    && mkdir -p /var/log/samba \
    && mkdir -p /var/log/supervisor \
    && mkdir -p /etc/krb5

# Copy configuration files
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /entrypoint.sh
COPY samba-wrapper.sh /samba-wrapper.sh

RUN chmod +x /entrypoint.sh /samba-wrapper.sh

# Samba AD DC ports
# DNS: 53, Kerberos: 88, LDAP: 389, LDAPS: 636, SMB: 445
# Global Catalog: 3268, 3269
# RPC: 135, 49152-65535
EXPOSE 53 88 389 636 445 3268 3269 135

# Health check - verify LDAP is responding
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD nc -z localhost 389 || exit 1

VOLUME ["/var/lib/samba", "/etc/krb5"]

ENTRYPOINT ["/entrypoint.sh"]
