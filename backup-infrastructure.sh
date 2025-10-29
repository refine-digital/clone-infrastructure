#!/bin/bash

################################################################################
# Infrastructure Backup Management Script
# Manages Ofelia-based automated backups for local WordPress sites
################################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Usage
################################################################################
show_usage() {
    echo "Usage: $0 <command> <infrastructure-name> [options]"
    echo ""
    echo "Commands:"
    echo "  add       Add/enable backups for infrastructure"
    echo "  remove    Remove/disable backups"
    echo "  config    Configure backup settings"
    echo "  status    Show backup status and recent backups"
    echo "  run       Run backups manually"
    echo ""
    echo "Options for 'add' command:"
    echo "  --backup-path PATH        Path to store backups (default: ~/Backups/infrastructure)"
    echo "  --db-schedule CRON        Database backup schedule (default: @hourly)"
    echo "  --files-schedule CRON     Files backup schedule (default: 0 2 * * *)"
    echo "  --retention-days DAYS     How many days to keep backups (default: 7 for db, 30 for files)"
    echo ""
    echo "Options for 'config' command:"
    echo "  Same as 'add' command options"
    echo ""
    echo "Options for 'run' command:"
    echo "  --db-only                 Run only database backup"
    echo "  --files-only              Run only files backup"
    echo ""
    echo "Examples:"
    echo "  $0 add dev-fi-01"
    echo "  $0 add dev-fi-01 --backup-path /Volumes/External/Backups"
    echo "  $0 add dev-fi-01 --db-schedule '0 */2 * * *' --files-schedule '0 3 * * *'"
    echo "  $0 config dev-fi-01 --retention-days 14"
    echo "  $0 status dev-fi-01"
    echo "  $0 run dev-fi-01"
    echo "  $0 run dev-fi-01 --db-only"
    echo "  $0 remove dev-fi-01"
    echo ""
}

if [ $# -lt 2 ]; then
    show_usage
    exit 1
fi

################################################################################
# Parse command and infrastructure name
################################################################################
COMMAND=$1
INFRA_NAME=$2
shift 2

# Default configuration
BACKUP_BASE_PATH="${HOME}/Backups/infrastructure"
DB_BACKUP_SCHEDULE="@hourly"
FILES_BACKUP_SCHEDULE="0 2 * * *"
DB_RETENTION_DAYS=7
FILES_RETENTION_DAYS=30
DB_ONLY=false
FILES_ONLY=false

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-path)
            BACKUP_BASE_PATH="$2"
            shift 2
            ;;
        --db-schedule)
            DB_BACKUP_SCHEDULE="$2"
            shift 2
            ;;
        --files-schedule)
            FILES_BACKUP_SCHEDULE="$2"
            shift 2
            ;;
        --retention-days)
            DB_RETENTION_DAYS="$2"
            FILES_RETENTION_DAYS="$2"
            shift 2
            ;;
        --db-only)
            DB_ONLY=true
            shift
            ;;
        --files-only)
            FILES_ONLY=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done

################################################################################
# Configuration
################################################################################
BACKUP_PATH="${BACKUP_BASE_PATH}/${INFRA_NAME}"
LOCAL_USER_HOME="${HOME}"
LOCAL_INFRA_DIR="${LOCAL_USER_HOME}/.${INFRA_NAME}"
SCRIPTS_DIR="${LOCAL_INFRA_DIR}/backup-scripts"
DOCKER_COMPOSE="${LOCAL_INFRA_DIR}/docker-compose.yml"
WORDPRESS_BASE="${LOCAL_USER_HOME}/ProjectFiles/wordpress"

################################################################################
# Helper Functions
################################################################################

verify_infrastructure() {
    if [ ! -d "${LOCAL_INFRA_DIR}" ]; then
        echo -e "${RED}Error: Infrastructure not found at ${LOCAL_INFRA_DIR}${NC}"
        echo "Please clone the infrastructure first:"
        echo "  ./clone-infrastructure.sh ${INFRA_NAME} <server-ip>"
        exit 1
    fi
}

check_ofelia() {
    if ! docker ps | grep -q "ofelia"; then
        echo -e "${RED}Error: Ofelia container is not running${NC}"
        echo "Please start the infrastructure:"
        echo "  cd ${LOCAL_INFRA_DIR} && docker-compose up -d"
        exit 1
    fi
}

create_backup_scripts() {
    mkdir -p "${SCRIPTS_DIR}"

    # Database backup script
    cat > "${SCRIPTS_DIR}/backup-databases.sh" << 'SCRIPT_END'
#!/bin/bash

BACKUP_DIR="{{BACKUP_PATH}}/databases"
LOG_FILE="{{BACKUP_PATH}}/logs/db-backup-$(date +%Y%m%d-%H%M).log"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR" "$(dirname "$LOG_FILE")"

echo "[$(date)] Starting database backups..." | tee -a "$LOG_FILE"

# Get MySQL root password from infrastructure
MYSQL_ROOT_PASSWORD=$(grep MYSQL_ROOT_PASSWORD {{INFRA_DIR}}/.env | cut -d'=' -f2)

# Get list of all WordPress databases (exclude system databases)
DATABASES=$(docker exec mysql mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "^(Database|information_schema|performance_schema|mysql|sys)$")

if [ -z "$DATABASES" ]; then
    echo "[$(date)] No WordPress databases found" | tee -a "$LOG_FILE"
    exit 0
fi

# Backup each database
for db in $DATABASES; do
    BACKUP_FILE="${BACKUP_DIR}/${db}.sql"
    echo "[$(date)] Backing up database: ${db}" | tee -a "$LOG_FILE"

    docker exec mysql mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} \
        --single-transaction \
        --quick \
        --lock-tables=false \
        "${db}" > "${BACKUP_FILE}" 2>> "$LOG_FILE"

    if [ $? -eq 0 ]; then
        gzip -f "${BACKUP_FILE}"
        echo "[$(date)]   ✓ Saved: ${BACKUP_FILE}.gz" | tee -a "$LOG_FILE"
    else
        echo "[$(date)]   ✗ Failed to backup ${db}" | tee -a "$LOG_FILE"
    fi
done

# Clean up old backups
find "${BACKUP_DIR}" -name "*.sql.gz" -mtime +{{DB_RETENTION_DAYS}} -delete 2>> "$LOG_FILE"

echo "[$(date)] Database backup complete" | tee -a "$LOG_FILE"
SCRIPT_END

    # Files backup script
    cat > "${SCRIPTS_DIR}/backup-files.sh" << 'SCRIPT_END'
#!/bin/bash

BACKUP_DIR="{{BACKUP_PATH}}/files"
LOG_FILE="{{BACKUP_PATH}}/logs/files-backup-$(date +%Y%m%d).log"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
WORDPRESS_BASE="{{WORDPRESS_BASE}}"

mkdir -p "$BACKUP_DIR" "$(dirname "$LOG_FILE")"

echo "[$(date)] Starting files backup..." | tee -a "$LOG_FILE"

# Find all WordPress sites
for site_dir in "${WORDPRESS_BASE}"/*; do
    if [ ! -d "$site_dir" ]; then
        continue
    fi

    DOMAIN=$(basename "$site_dir")
    PUBLIC_DIR="${site_dir}/app/public"

    if [ ! -d "$PUBLIC_DIR" ]; then
        echo "[$(date)] Skipping ${DOMAIN} - no public directory" | tee -a "$LOG_FILE"
        continue
    fi

    echo "[$(date)] Backing up: ${DOMAIN}" | tee -a "$LOG_FILE"

    # Create temporary directory for this site's backup
    TEMP_DIR=$(mktemp -d)
    SITE_BACKUP_DIR="${TEMP_DIR}/${DOMAIN}"
    mkdir -p "${SITE_BACKUP_DIR}"

    # Backup wp-content directory (custom themes, plugins, uploads)
    if [ -d "${PUBLIC_DIR}/wp-content" ]; then
        echo "[$(date)]   Copying wp-content..." | tee -a "$LOG_FILE"
        rsync -a "${PUBLIC_DIR}/wp-content/" "${SITE_BACKUP_DIR}/wp-content/" >> "$LOG_FILE" 2>&1
    fi

    # Backup wp-config.php
    if [ -f "${PUBLIC_DIR}/wp-config.php" ]; then
        echo "[$(date)]   Copying wp-config.php..." | tee -a "$LOG_FILE"
        cp "${PUBLIC_DIR}/wp-config.php" "${SITE_BACKUP_DIR}/"
    fi

    # Backup .htaccess if exists
    if [ -f "${PUBLIC_DIR}/.htaccess" ]; then
        cp "${PUBLIC_DIR}/.htaccess" "${SITE_BACKUP_DIR}/"
    fi

    # Create compressed archive
    BACKUP_FILE="${BACKUP_DIR}/${DOMAIN}-${TIMESTAMP}.tar.gz"
    echo "[$(date)]   Creating archive..." | tee -a "$LOG_FILE"
    tar -czf "${BACKUP_FILE}" -C "${TEMP_DIR}" "${DOMAIN}" >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        # Create/update symlink to latest backup
        ln -sf "$(basename ${BACKUP_FILE})" "${BACKUP_DIR}/${DOMAIN}-latest.tar.gz"
        echo "[$(date)]   ✓ Saved: ${BACKUP_FILE}" | tee -a "$LOG_FILE"
    else
        echo "[$(date)]   ✗ Failed to create archive for ${DOMAIN}" | tee -a "$LOG_FILE"
    fi

    # Cleanup temp directory
    rm -rf "${TEMP_DIR}"
done

# Clean up old file backups
find "${BACKUP_DIR}" -name "*.tar.gz" ! -name "*-latest.tar.gz" -mtime +{{FILES_RETENTION_DAYS}} -delete 2>> "$LOG_FILE"

echo "[$(date)] Files backup complete" | tee -a "$LOG_FILE"
SCRIPT_END

    # Replace placeholders in both scripts
    for script in backup-databases.sh backup-files.sh; do
        sed -i.bak "s|{{BACKUP_PATH}}|${BACKUP_PATH}|g" "${SCRIPTS_DIR}/${script}"
        sed -i.bak "s|{{INFRA_DIR}}|${LOCAL_INFRA_DIR}|g" "${SCRIPTS_DIR}/${script}"
        sed -i.bak "s|{{WORDPRESS_BASE}}|${WORDPRESS_BASE}|g" "${SCRIPTS_DIR}/${script}"
        sed -i.bak "s|{{DB_RETENTION_DAYS}}|${DB_RETENTION_DAYS}|g" "${SCRIPTS_DIR}/${script}"
        sed -i.bak "s|{{FILES_RETENTION_DAYS}}|${FILES_RETENTION_DAYS}|g" "${SCRIPTS_DIR}/${script}"
        rm -f "${SCRIPTS_DIR}/${script}.bak"
        chmod +x "${SCRIPTS_DIR}/${script}"
    done
}

################################################################################
# Command: add
################################################################################
cmd_add() {
    echo -e "${GREEN}=== Adding Backup Configuration ===${NC}"
    echo "Infrastructure: ${INFRA_NAME}"
    echo "Backup location: ${BACKUP_PATH}"
    echo ""

    verify_infrastructure
    check_ofelia

    echo -e "${YELLOW}[1/5] Creating backup directories...${NC}"
    mkdir -p "${BACKUP_PATH}/databases"
    mkdir -p "${BACKUP_PATH}/files"
    mkdir -p "${BACKUP_PATH}/logs"
    echo "  ✓ Created backup directories"

    echo -e "${YELLOW}[2/5] Creating backup scripts...${NC}"
    create_backup_scripts
    echo "  ✓ Created: backup-databases.sh"
    echo "  ✓ Created: backup-files.sh"

    echo -e "${YELLOW}[3/5] Configuring Ofelia backup jobs...${NC}"

    # Check if backup-scheduler already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^backup-scheduler$"; then
        echo "  ⚠️  backup-scheduler already exists - updating configuration"
        docker rm -f backup-scheduler 2>/dev/null || true
    fi

    # Check if service exists in docker-compose
    if grep -q "backup-scheduler:" "${DOCKER_COMPOSE}"; then
        echo "  ⚠️  backup-scheduler service already in docker-compose.yml"
        echo "  Remove it manually or run: $0 remove ${INFRA_NAME}"
        exit 1
    fi

    # Backup docker-compose.yml
    cp "${DOCKER_COMPOSE}" "${DOCKER_COMPOSE}.backup-$(date +%Y%m%d-%H%M%S)"

    # Add backup-scheduler service
    cat >> "${DOCKER_COMPOSE}" << EOF

  # Backup scheduler service (added by backup-infrastructure.sh)
  backup-scheduler:
    image: alpine:latest
    container_name: backup-scheduler
    volumes:
      - ${SCRIPTS_DIR}:/backup-scripts:ro
      - ${BACKUP_PATH}:/backups
      - ${WORDPRESS_BASE}:/wordpress:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    labels:
      ofelia.enabled: "true"
      # Database backup
      ofelia.job-exec.backup-db.schedule: "${DB_BACKUP_SCHEDULE}"
      ofelia.job-exec.backup-db.command: "sh -c '/backup-scripts/backup-databases.sh'"
      ofelia.job-exec.backup-db.no-overlap: "true"
      # Files backup
      ofelia.job-exec.backup-files.schedule: "${FILES_BACKUP_SCHEDULE}"
      ofelia.job-exec.backup-files.command: "sh -c '/backup-scripts/backup-files.sh'"
      ofelia.job-exec.backup-files.no-overlap: "true"
    networks:
      - wordpress-sites
      - db-network
    command: sleep infinity
    restart: always
EOF

    echo "  ✓ Added backup-scheduler to docker-compose.yml"
    echo "  ✓ Database schedule: ${DB_BACKUP_SCHEDULE}"
    echo "  ✓ Files schedule: ${FILES_BACKUP_SCHEDULE}"

    echo -e "${YELLOW}[4/5] Restarting infrastructure...${NC}"
    cd "${LOCAL_INFRA_DIR}"
    docker-compose up -d
    sleep 3
    echo "  ✓ Infrastructure restarted"

    echo -e "${YELLOW}[5/5] Testing backup...${NC}"
    "${SCRIPTS_DIR}/backup-databases.sh" > /dev/null 2>&1 || true
    if [ -n "$(ls -A ${BACKUP_PATH}/databases/*.gz 2>/dev/null)" ]; then
        echo "  ✓ Database backup test successful"
    else
        echo "  ⚠️  No database backups created (may be normal if no WordPress sites exist)"
    fi

    echo ""
    echo -e "${GREEN}=== Backup Configuration Complete ===${NC}"
    echo ""
    echo "Backup location: ${BACKUP_PATH}"
    echo "Database schedule: ${DB_BACKUP_SCHEDULE}"
    echo "Files schedule: ${FILES_BACKUP_SCHEDULE}"
    echo "Retention: ${DB_RETENTION_DAYS} days (db), ${FILES_RETENTION_DAYS} days (files)"
    echo ""
    echo "View status: $0 status ${INFRA_NAME}"
    echo "Run manually: $0 run ${INFRA_NAME}"
}

################################################################################
# Command: remove
################################################################################
cmd_remove() {
    echo -e "${YELLOW}=== Removing Backup Configuration ===${NC}"
    echo "Infrastructure: ${INFRA_NAME}"
    echo ""

    verify_infrastructure

    echo -e "${YELLOW}[1/3] Stopping backup-scheduler...${NC}"
    docker rm -f backup-scheduler 2>/dev/null && echo "  ✓ Stopped backup-scheduler" || echo "  ⚠️  backup-scheduler not running"

    echo -e "${YELLOW}[2/3] Removing from docker-compose.yml...${NC}"
    if grep -q "backup-scheduler:" "${DOCKER_COMPOSE}"; then
        # Backup docker-compose.yml
        cp "${DOCKER_COMPOSE}" "${DOCKER_COMPOSE}.backup-$(date +%Y%m%d-%H%M%S)"

        # Remove backup-scheduler service (from the comment line to the end)
        sed -i.tmp '/# Backup scheduler service/,/^$/d' "${DOCKER_COMPOSE}"
        rm -f "${DOCKER_COMPOSE}.tmp"

        echo "  ✓ Removed backup-scheduler from docker-compose.yml"
    else
        echo "  ⚠️  backup-scheduler not found in docker-compose.yml"
    fi

    echo -e "${YELLOW}[3/3] Cleanup...${NC}"
    echo "  Backup scripts preserved at: ${SCRIPTS_DIR}"
    echo "  Backup data preserved at: ${BACKUP_PATH}"
    echo "  To delete backups: rm -rf ${BACKUP_PATH}"

    echo ""
    echo -e "${GREEN}=== Backup Configuration Removed ===${NC}"
    echo ""
    echo "Backup data still exists at: ${BACKUP_PATH}"
    echo "To re-enable: $0 add ${INFRA_NAME}"
}

################################################################################
# Command: config
################################################################################
cmd_config() {
    echo -e "${YELLOW}=== Updating Backup Configuration ===${NC}"
    echo "Infrastructure: ${INFRA_NAME}"
    echo ""

    verify_infrastructure

    echo "Removing existing configuration..."
    cmd_remove

    echo ""
    echo "Adding new configuration..."
    cmd_add
}

################################################################################
# Command: status
################################################################################
cmd_status() {
    echo -e "${GREEN}=== Backup Status ===${NC}"
    echo "Infrastructure: ${INFRA_NAME}"
    echo ""

    verify_infrastructure

    echo -e "${YELLOW}Configuration:${NC}"
    if [ -d "${SCRIPTS_DIR}" ]; then
        echo "  Backup scripts: ✓ Installed"
    else
        echo "  Backup scripts: ✗ Not installed"
        echo ""
        echo "To enable backups: $0 add ${INFRA_NAME}"
        exit 0
    fi

    if docker ps --format '{{.Names}}' | grep -q "^backup-scheduler$"; then
        echo "  Scheduler: ✓ Running"
    else
        echo "  Scheduler: ✗ Not running"
    fi

    echo ""
    echo -e "${YELLOW}Ofelia Jobs:${NC}"
    docker exec ofelia ofelia status 2>/dev/null || echo "  Cannot connect to Ofelia"

    echo ""
    echo -e "${YELLOW}Recent Database Backups:${NC}"
    if [ -d "${BACKUP_PATH}/databases" ]; then
        ls -lht "${BACKUP_PATH}/databases"/*.gz 2>/dev/null | head -5 | awk '{print "  " $9 " (" $6 " " $7 " " $8 ")"}' || echo "  No backups found"
    else
        echo "  No backup directory"
    fi

    echo ""
    echo -e "${YELLOW}Recent File Backups:${NC}"
    if [ -d "${BACKUP_PATH}/files" ]; then
        ls -lht "${BACKUP_PATH}/files"/*-latest.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $6 " " $7 " " $8 ")"}' || echo "  No backups found"
    else
        echo "  No backup directory"
    fi

    echo ""
    echo -e "${YELLOW}Disk Usage:${NC}"
    if [ -d "${BACKUP_PATH}" ]; then
        du -sh "${BACKUP_PATH}" 2>/dev/null | awk '{print "  Total: " $1}'
        du -sh "${BACKUP_PATH}/databases" 2>/dev/null | awk '{print "  Databases: " $1}'
        du -sh "${BACKUP_PATH}/files" 2>/dev/null | awk '{print "  Files: " $1}'
    else
        echo "  No backup directory"
    fi

    echo ""
    echo "Recent logs: tail -f ${BACKUP_PATH}/logs/*.log"
}

################################################################################
# Command: run
################################################################################
cmd_run() {
    echo -e "${GREEN}=== Running Manual Backup ===${NC}"
    echo "Infrastructure: ${INFRA_NAME}"
    echo ""

    verify_infrastructure

    if [ ! -d "${SCRIPTS_DIR}" ]; then
        echo -e "${RED}Error: Backup scripts not found${NC}"
        echo "Please enable backups first: $0 add ${INFRA_NAME}"
        exit 1
    fi

    if [ "$FILES_ONLY" = false ]; then
        echo -e "${YELLOW}Running database backup...${NC}"
        "${SCRIPTS_DIR}/backup-databases.sh"
        echo "  ✓ Database backup complete"
    fi

    if [ "$DB_ONLY" = false ]; then
        echo -e "${YELLOW}Running files backup...${NC}"
        "${SCRIPTS_DIR}/backup-files.sh"
        echo "  ✓ Files backup complete"
    fi

    echo ""
    echo -e "${GREEN}Manual backup complete${NC}"
    echo ""
    echo "View status: $0 status ${INFRA_NAME}"
}

################################################################################
# Main
################################################################################

case $COMMAND in
    add)
        cmd_add
        ;;
    remove)
        cmd_remove
        ;;
    config)
        cmd_config
        ;;
    status)
        cmd_status
        ;;
    run)
        cmd_run
        ;;
    *)
        echo -e "${RED}Unknown command: ${COMMAND}${NC}"
        echo ""
        show_usage
        exit 1
        ;;
esac
