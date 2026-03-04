# Samba AD Domain Controller

A Docker image for running Samba as an Active Directory Domain Controller.

[![Build and Push](https://github.com/jknyght9/samba-ad-dc/actions/workflows/build.yml/badge.svg)](https://github.com/jknyght9/samba-ad-dc/actions/workflows/build.yml)

## Features

- **Provision new AD domains** or **join existing domains as replica DC**
- **Clean startup sequencing** - No race conditions during provisioning
- **Supervisor managed** - Reliable service management with auto-restart
- **Health checks** - Built-in LDAP health verification
- Based on Ubuntu 22.04 with Samba 4.15+

## Quick Start

### Primary Domain Controller (New Domain)

```bash
docker run -d \
  --name dc01 \
  --hostname dc01 \
  --privileged \
  --network host \
  -e DOMAIN=EXAMPLE.COM \
  -e DOMAINNAME=EXAMPLE \
  -e DOMAINPASS=YourSecurePassword123 \
  -e HOSTIP=192.168.1.10 \
  -v dc01-data:/var/lib/samba \
  -v dc01-krb5:/etc/krb5 \
  ghcr.io/jknyght9/samba-ad-dc:latest
```

### Replica Domain Controller (Join Existing)

```bash
docker run -d \
  --name dc02 \
  --hostname dc02 \
  --privileged \
  --network host \
  -e DOMAIN=EXAMPLE.COM \
  -e DOMAINNAME=EXAMPLE \
  -e DOMAINPASS=YourSecurePassword123 \
  -e HOSTIP=192.168.1.11 \
  -e DCIP=192.168.1.10 \
  -e JOIN=true \
  -v dc02-data:/var/lib/samba \
  -v dc02-krb5:/etc/krb5 \
  ghcr.io/jknyght9/samba-ad-dc:latest
```

## Environment Variables

| Variable       | Required | Default                   | Description                                      |
|----------------|----------|---------------------------|--------------------------------------------------|
| `DOMAIN`       | Yes      | -                         | AD realm in uppercase (e.g., `EXAMPLE.COM`)      |
| `DOMAINNAME`   | Yes      | -                         | NetBIOS name, max 15 chars (e.g., `EXAMPLE`)     |
| `DOMAINPASS`   | Yes      | -                         | Administrator password                           |
| `HOSTIP`       | Yes      | -                         | IP address of this domain controller             |
| `DNSFORWARDER` | No       | `8.8.8.8`                 | Upstream DNS server for forwarding               |
| `JOIN`         | No       | `false`                   | Set to `true` to join existing domain as replica |
| `DCIP`         | No       | -                         | Primary DC IP address (required if `JOIN=true`)  |
| `JOINSITE`     | No       | `Default-First-Site-Name` | AD site name for replica                         |
| `INSECURELDAP` | No       | `false`                   | Allow insecure LDAP binds (for testing)          |
| `NOCOMPLEXITY` | No       | `false`                   | Disable password complexity requirements         |

## Volumes

| Path             | Description                       |
|------------------|-----------------------------------|
| `/var/lib/samba` | Samba database, sysvol, and state |
| `/etc/krb5`      | Kerberos configuration            |

**Important:** Use persistent volumes to retain domain data across container restarts.

## Ports

| Port | Protocol | Service                  |
|------|----------|--------------------------|
| 53   | TCP/UDP  | DNS                      |
| 88   | TCP/UDP  | Kerberos                 |
| 135  | TCP      | RPC Endpoint Mapper      |
| 389  | TCP/UDP  | LDAP                     |
| 445  | TCP      | SMB                      |
| 464  | TCP/UDP  | Kerberos Password Change |
| 636  | TCP      | LDAPS (TLS)              |
| 3268 | TCP      | Global Catalog           |
| 3269 | TCP      | Global Catalog SSL       |

## Container Orchestration

### Docker Compose

```yaml
version: '3.8'
services:
  dc01:
    image: ghcr.io/jknyght9/samba-ad-dc:latest
    hostname: dc01
    privileged: true
    network_mode: host
    environment:
      DOMAIN: EXAMPLE.COM
      DOMAINNAME: EXAMPLE
      DOMAINPASS: YourSecurePassword123
      HOSTIP: 192.168.1.10
    volumes:
      - dc01-data:/var/lib/samba
      - dc01-krb5:/etc/krb5

volumes:
  dc01-data:
  dc01-krb5:
```

### HashiCorp Nomad

```hcl
job "samba-dc" {
  group "dc01" {
    task "samba" {
      driver = "docker"
      config {
        image        = "ghcr.io/jknyght9/samba-ad-dc:latest"
        network_mode = "host"
        privileged   = true
        volumes      = ["/opt/samba-dc01:/var/lib/samba"]
      }
      env {
        DOMAIN     = "EXAMPLE.COM"
        DOMAINNAME = "EXAMPLE"
        DOMAINPASS = "YourSecurePassword123"
        HOSTIP     = "192.168.1.10"
      }
    }
  }
}
```

## Verification

```bash
# Check domain functional level
docker exec dc01 samba-tool domain level show

# List domain users
docker exec dc01 samba-tool user list

# Check replication status (run on primary DC)
docker exec dc01 samba-tool drs showrepl

# Test Kerberos authentication
docker exec dc01 kinit administrator@EXAMPLE.COM

# Test LDAP search
docker exec dc01 ldapsearch -H ldap://localhost -b "dc=example,dc=com" "(objectClass=user)"
```

## Joining Clients

### Windows

1. Set DNS to point to DC IP address
2. System Properties → Computer Name → Change → Domain
3. Enter domain name (e.g., `EXAMPLE.COM`)
4. Authenticate with `Administrator` and your `DOMAINPASS`

### Linux (SSSD)

```bash
sudo apt install sssd-ad realmd adcli
sudo realm discover EXAMPLE.COM
sudo realm join EXAMPLE.COM -U Administrator
```

## Troubleshooting

### Check service status
```bash
docker exec dc01 supervisorctl status
```

### View logs
```bash
docker logs dc01
docker exec dc01 cat /var/log/supervisor/samba-stderr.log
```

### Domain join fails for replica
1. Verify primary DC is running: `nc -zv <DCIP> 389`
2. Check DNS resolution: `dig @<DCIP> _ldap._tcp.<domain> SRV`
3. Ensure clocks are synchronized (Kerberos requires <5 min skew)

## License

MIT License - see [LICENSE](LICENSE)

## Contributing

Contributions welcome! Please open an issue or pull request.
