# Clone Infrastructure

A comprehensive infrastructure management toolkit for cloning, managing, and backing up Docker-based development infrastructure from production servers.

## Overview

This toolkit provides three powerful scripts to manage local development infrastructure:

- **`clone-infrastructure.sh`** - Clone production infrastructure to local development
- **`remove-infrastructure.sh`** - Safely remove infrastructure with dependency checking
- **`backup-infrastructure.sh`** - Automated backup management with Ofelia scheduling

## Features

- **Infrastructure-Centric Architecture** - All services organized under `~/.{infrastructure-name}/`
- **Automated SSH Management** - Automatic SSH key generation and configuration
- **Docker Services** - nginx-proxy, MySQL, Redis, Ofelia, Cloudflared support
- **Network Management** - Automatic Docker network creation and management
- **FlyWP Integration** - Tracks provision script changes and alerts on updates
- **Idempotent Operations** - Safe to run multiple times
- **Automated Backups** - Ofelia-based scheduled backups with flexible configuration

## Prerequisites

- macOS or Linux
- Docker and Docker Compose installed
- SSH access to production server
- `rsync` installed
- Production server provisioned with FlyWP or compatible setup

## Installation

### Quick Install (Recommended)

Install scripts to `~/.local/bin` for global CLI access:

```bash
# 1. Clone repository
git clone https://github.com/refine-digital/clone-infrastructure.git
cd clone-infrastructure

# 2. Run installer
./install.sh

# 3. Configure PATH (if prompted)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

After installation, commands are available globally:
- `clone-infrastructure` - Clone infrastructure
- `remove-infrastructure` - Remove infrastructure
- `backup-infrastructure` - Manage backups

### Manual Installation (Alternative)

If you prefer to run scripts from the project directory:

```bash
# 1. Clone repository
git clone https://github.com/refine-digital/clone-infrastructure.git
cd clone-infrastructure

# 2. Make scripts executable
chmod +x *.sh
```

Then run scripts with `./clone-infrastructure.sh` instead of `clone-infrastructure`.

### Updating

To update to the latest version:

```bash
cd clone-infrastructure
git pull
./install.sh  # Re-run installer to update commands
```

## Usage

### Clone Infrastructure

Clone production infrastructure to your local machine:

```bash
clone-infrastructure <infrastructure-name> <server-ip>
```

**Example:**
```bash
clone-infrastructure dev-fi-01 46.62.207.172
```

*Note: If using manual installation, use `./clone-infrastructure.sh` instead*

**What it does:**
1. Sets up SSH connection with automatic key generation
2. Downloads infrastructure files from production
3. Tracks FlyWP provision script for updates
4. Creates database directories
5. Sets up cloudflared configuration (if available)
6. Creates Docker networks (wordpress-sites)
7. Configures environment variables
8. Starts infrastructure services

**Output:**
- Infrastructure cloned to: `~/.{infrastructure-name}/`
- SSH config entry: `{infrastructure-name}-{server-ip}`
- Services: nginx-proxy, mysql, redis, ofelia (cloudflared optional)

**Re-clone with clean slate:**
```bash
clone-infrastructure dev-fi-01 46.62.207.172 --clean
```

### Remove Infrastructure

Safely remove infrastructure with dependency checking:

```bash
remove-infrastructure <infrastructure-name> [options]
```

**Examples:**
```bash
# Check dependencies and remove
remove-infrastructure dev-fi-01

# Force removal (skip dependency check)
remove-infrastructure dev-fi-01 --force

# Keep database and configuration data
remove-infrastructure dev-fi-01 --keep-data

# Remove SSH config and keys
remove-infrastructure dev-fi-01 --remove-ssh

# Remove everything including SSH
remove-infrastructure dev-fi-01 --force --remove-ssh
```

**Safety Features:**
- Checks for dependent WordPress sites before removal
- Lists all containers using infrastructure networks
- Warns about data loss
- Optional data preservation
- SSH key management

### Backup Infrastructure

Manage automated backups with Ofelia scheduling:

```bash
backup-infrastructure <command> <infrastructure-name> [options]
```

**Commands:**

**1. Add Backup Configuration**
```bash
backup-infrastructure add dev-fi-01 /Volumes/Backup/infrastructure
```

Options:
- `--db-schedule` - Database backup schedule (default: `@hourly`)
- `--files-schedule` - Files backup schedule (default: `@daily`)

**2. Remove Backup Configuration**
```bash
backup-infrastructure remove dev-fi-01
```

**3. View Backup Status**
```bash
backup-infrastructure status dev-fi-01
```

**4. Run Manual Backup**
```bash
backup-infrastructure run dev-fi-01

# Run specific backup type
backup-infrastructure run dev-fi-01 --type databases
backup-infrastructure run dev-fi-01 --type files
```

**5. Update Configuration**
```bash
backup-infrastructure config dev-fi-01 --db-schedule "@every 2h"
```

**Backup Details:**
- **Databases**: Each database exported as `{database-name}.sql.gz`
- **Files**: WordPress sites archived as `{domain}.tar.gz`
- Excludes WordPress core files, includes wp-config.php
- Automated scheduling via Ofelia cron
- Configurable schedules per infrastructure

## Infrastructure Structure

After cloning, infrastructure is organized as:

```
~/.{infrastructure-name}/
├── .env                          # Environment variables (MYSQL_ROOT_PASSWORD, etc.)
├── .provision-script-hash        # FlyWP provision script tracking
├── docker-compose.yml            # Infrastructure services definition
├── .provisions/                  # FlyWP provision scripts
│   └── initialize.sh
├── config/                       # Service configurations
│   ├── mysql/
│   │   └── my.cnf
│   ├── redis/
│   │   ├── redis.conf
│   │   └── users.acl
│   └── cloudflared/              # Optional: Cloudflare Tunnel
│       ├── config.yml
│       └── credentials.json
├── database/                     # MySQL data (persistent)
│   ├── mysql/
│   └── backups/
├── nginx/                        # nginx-proxy configuration
│   ├── conf.d/
│   ├── vhost/
│   └── html/
└── scripts/                      # Backup scripts (created by backup-infrastructure.sh)
    ├── backup-databases.sh
    └── backup-files.sh
```

## Docker Networks

The infrastructure creates and manages Docker networks:

- **`wordpress-sites`** (external: true) - Shared network for all WordPress sites and nginx-proxy
- **`db-network`** (managed by compose) - Bridge network for database connections

## SSH Configuration

The clone script automatically manages SSH:

**Key Naming Convention:**
- Production: `id_{infraname}_digops`
- Local: `id_local{infraname}_digops`

**SSH Config Entry:**
```
Host {infrastructure-name}-{server-ip}
  HostName {server-ip}
  User fly
  IdentityFile ~/.ssh/id_local{infraname}_digops
  IdentitiesOnly yes
```

## Environment Variables

The `.env` file in infrastructure directory contains:

```bash
MYSQL_ROOT_PASSWORD=<auto-generated>
# Add other environment variables as needed
```

These variables are automatically sourced by dependent scripts (like clone-wordpress).

## FlyWP Provision Script Tracking

The script tracks changes to FlyWP's master provision script:

**First clone:**
```
Downloaded provision script
First clone - stored provision script hash: 051cebc2bfc1...
```

**Subsequent clones:**
```
Provision script hash matches - no changes
```

**When FlyWP updates:**
```
WARNING: FlyWP provision script has been updated!
Previous hash: 051cebc2bfc1...
Current hash:  a72fe91d3ab2...

Consider re-cloning with --clean flag to apply latest provisioning:
  clone-infrastructure dev-fi-01 46.62.207.172 --clean
```

## Cloudflared Setup (Optional)

For HTTPS access via Cloudflare Tunnel:

1. Login to Cloudflare:
```bash
cloudflared tunnel login
```

2. Create tunnel:
```bash
cloudflared tunnel create local-{infrastructure-name}
```

3. Copy credentials:
```bash
cp ~/.cloudflared/*.json ~/.{infrastructure-name}/config/cloudflared/
```

4. Create config.yml:
```yaml
tunnel: <tunnel-id>
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: local-site1.example.com
    service: http://site1-container:8080
  - hostname: local-site2.example.com
    service: http://site2-container:8080
  - service: http_status:404
```

5. Restart infrastructure:
```bash
cd ~/.{infrastructure-name}
docker-compose up -d cloudflared
```

## Troubleshooting

### SSH Connection Failed

If you see "SSH connection failed":
```bash
# Option 1: Automatic (if you have password access)
ssh-copy-id -i ~/.ssh/id_local{infraname}_digops.pub fly@{server-ip}

# Option 2: Manual
# 1. Copy public key content
cat ~/.ssh/id_local{infraname}_digops.pub

# 2. SSH to server
ssh fly@{server-ip}

# 3. Add to authorized_keys
echo "{public-key-content}" >> ~/.ssh/authorized_keys
```

### Services Not Starting

Check Docker logs:
```bash
cd ~/.{infrastructure-name}
docker-compose logs -f
```

### Port Conflicts

If port 80/443 are in use:
```bash
# Find what's using the ports
lsof -i :80
lsof -i :443

# Stop conflicting services or modify docker-compose.yml ports
```

### Network Already Exists

If you get "network already exists" errors:
```bash
# Remove old networks
docker network rm wordpress-sites
docker network rm db-network

# Re-run clone script
clone-infrastructure {infrastructure-name} {server-ip}
```

### Database Connection Issues

Verify MySQL is running:
```bash
docker exec mysql mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SELECT 1"
```

## Best Practices

1. **Regular Updates**: Re-clone infrastructure periodically to sync latest configs
2. **Backup First**: Use `backup-infrastructure.sh` before major changes
3. **Clean Clones**: Use `--clean` flag after FlyWP updates
4. **Monitor Logs**: Check docker-compose logs for issues
5. **SSH Keys**: Keep SSH keys secure, never commit to version control
6. **Environment Files**: Never commit `.env` files with sensitive data

## Workflow Example

Complete workflow for setting up local development:

```bash
# 1. Clone infrastructure
clone-infrastructure dev-fi-01 46.62.207.172

# 2. Add SSH key to server (if prompted)
ssh-copy-id -i ~/.ssh/id_localdevfi01_digops.pub fly@46.62.207.172

# 3. Re-run to complete setup
clone-infrastructure dev-fi-01 46.62.207.172

# 4. Set up backups
backup-infrastructure add dev-fi-01 /Volumes/Backup/infrastructure

# 5. Verify services
cd ~/.dev-fi-01
docker-compose ps

# 6. Now ready to clone WordPress sites (see clone-wordpress project)
```

## Integration with clone-wordpress

This infrastructure is designed to work with the [clone-wordpress](https://github.com/refine-digital/clone-wordpress) project:

```bash
# After infrastructure is set up, clone WordPress sites:
cd /path/to/clone-wordpress
./clone-wordpress.sh dev-fi-01 example.com
```

The WordPress clone script will:
- Detect infrastructure at `~/.dev-fi-01/`
- Read credentials from infrastructure `.env`
- Use SSH config created by infrastructure clone
- Connect to infrastructure services (mysql, redis, nginx-proxy)

## Version History

- **v1.0.0** - Initial release with clone, remove, and backup functionality

## License

MIT License - See LICENSE file for details

## Contributing

Contributions welcome! Please open an issue or pull request.

## Support

For issues and questions:
- GitHub Issues: https://github.com/refine-digital/clone-infrastructure/issues
- Documentation: https://github.com/refine-digital/clone-infrastructure

## Author

Created for infrastructure-centric local development workflows.
