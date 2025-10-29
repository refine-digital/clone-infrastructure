#!/bin/bash

################################################################################
# Infrastructure Removal Script
# Safely removes cloned infrastructure with dependency checks
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
if [ $# -lt 1 ]; then
    echo "Usage: $0 <infrastructure-name> [options]"
    echo ""
    echo "Options:"
    echo "  --force              Remove even if WordPress sites are running"
    echo "  --keep-data          Keep database and provision script data"
    echo "  --keep-ssh           Keep SSH keys and configuration"
    echo "  --keep-networks      Keep Docker networks (if no sites depend on them)"
    echo ""
    echo "Examples:"
    echo "  $0 dev-fi-01                    # Safe removal with checks"
    echo "  $0 dev-fi-01 --force            # Force removal"
    echo "  $0 dev-fi-01 --keep-data        # Keep databases"
    echo "  $0 refine-digital-app --keep-ssh --keep-data"
    echo ""
    exit 1
fi

################################################################################
# Parse arguments
################################################################################
INFRA_NAME=$1
shift

FORCE_MODE=false
KEEP_DATA=false
KEEP_SSH=false
KEEP_NETWORKS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_MODE=true
            shift
            ;;
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        --keep-ssh)
            KEEP_SSH=true
            shift
            ;;
        --keep-networks)
            KEEP_NETWORKS=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

################################################################################
# Configuration
################################################################################
LOCAL_USER_HOME="${HOME}"
LOCAL_INFRA_DIR="${LOCAL_USER_HOME}/.${INFRA_NAME}"

# SSH key pattern
INFRA_NAME_CLEAN=$(echo "${INFRA_NAME}" | tr -d '.-')
SSH_KEY_PATTERN="id_local${INFRA_NAME_CLEAN}_*"
SSH_KEY_PATH="${HOME}/.ssh/id_local${INFRA_NAME_CLEAN}_digops"

# Backup directory for data preservation
BACKUP_DIR="${LOCAL_USER_HOME}/.infrastructure-backups/${INFRA_NAME}-$(date +%Y%m%d-%H%M%S)"

################################################################################
# Header
################################################################################
echo -e "${RED}=== Infrastructure Removal ===${NC}"
echo "Infrastructure: ${INFRA_NAME}"
echo "Location: ${LOCAL_INFRA_DIR}"
echo "Force mode: ${FORCE_MODE}"
echo "Keep data: ${KEEP_DATA}"
echo "Keep SSH: ${KEEP_SSH}"
echo "Keep networks: ${KEEP_NETWORKS}"
echo ""

################################################################################
# Step 1: Check if infrastructure exists
################################################################################
if [ ! -d "${LOCAL_INFRA_DIR}" ]; then
    echo -e "${YELLOW}Infrastructure directory does not exist: ${LOCAL_INFRA_DIR}${NC}"
    echo "Nothing to remove."
    exit 0
fi

################################################################################
# Step 2: Check for dependent WordPress sites
################################################################################
echo -e "${YELLOW}[1/7] Checking for dependent WordPress sites...${NC}"

# Check if any containers are connected to wordpress-sites or db-network
WORDPRESS_SITES_CONTAINERS=$(docker network inspect wordpress-sites -f '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "")
DB_NETWORK_CONTAINERS=$(docker network inspect db-network -f '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "")

# Filter out infrastructure containers
INFRA_CONTAINERS="nginx-proxy mysql redis ofelia cloudflared"
DEPENDENT_SITES=""

for container in $WORDPRESS_SITES_CONTAINERS $DB_NETWORK_CONTAINERS; do
    if ! echo "$INFRA_CONTAINERS" | grep -q "$container"; then
        DEPENDENT_SITES="$DEPENDENT_SITES $container"
    fi
done

if [ -n "$DEPENDENT_SITES" ]; then
    echo -e "${RED}⚠️  WARNING: Found WordPress sites depending on this infrastructure:${NC}"
    for site in $DEPENDENT_SITES; do
        echo "  - $site"
    done
    echo ""

    if [ "$FORCE_MODE" = false ]; then
        echo -e "${RED}Cannot remove infrastructure while WordPress sites are running.${NC}"
        echo ""
        echo "Options:"
        echo "  1. Stop WordPress sites first:"
        echo "     cd /path/to/wordpress-site && docker-compose down"
        echo ""
        echo "  2. Force removal (sites will break):"
        echo "     $0 ${INFRA_NAME} --force"
        echo ""
        exit 1
    else
        echo -e "${YELLOW}Force mode enabled - proceeding with removal...${NC}"
        echo -e "${YELLOW}WordPress sites will lose database and network connectivity!${NC}"
        echo ""
    fi
else
    echo "  ✓ No dependent WordPress sites found"
fi

################################################################################
# Step 3: Backup data (if requested)
################################################################################
if [ "$KEEP_DATA" = true ]; then
    echo -e "${YELLOW}[2/7] Backing up infrastructure data...${NC}"

    mkdir -p "${BACKUP_DIR}"

    # Backup databases
    if [ -d "${LOCAL_INFRA_DIR}/database" ]; then
        echo "  Backing up databases to: ${BACKUP_DIR}/database/"
        cp -r "${LOCAL_INFRA_DIR}/database" "${BACKUP_DIR}/"
        echo "  ✓ Database backup complete"
    fi

    # Backup provision script and hash
    if [ -f "${LOCAL_INFRA_DIR}/.provision-script-hash" ]; then
        mkdir -p "${BACKUP_DIR}/.provisions"
        cp "${LOCAL_INFRA_DIR}/.provision-script-hash" "${BACKUP_DIR}/"
        cp -r "${LOCAL_INFRA_DIR}/.provisions"/* "${BACKUP_DIR}/.provisions/" 2>/dev/null || true
        echo "  ✓ Provision script backup complete"
    fi

    # Backup .env
    if [ -f "${LOCAL_INFRA_DIR}/.env" ]; then
        cp "${LOCAL_INFRA_DIR}/.env" "${BACKUP_DIR}/"
        echo "  ✓ Environment backup complete"
    fi

    echo ""
    echo "  Data backed up to: ${BACKUP_DIR}"
else
    echo -e "${YELLOW}[2/7] Skipping data backup...${NC}"
fi

################################################################################
# Step 4: Stop infrastructure services
################################################################################
echo -e "${YELLOW}[3/7] Stopping infrastructure services...${NC}"

if [ -f "${LOCAL_INFRA_DIR}/docker-compose.yml" ]; then
    cd "${LOCAL_INFRA_DIR}"
    docker-compose down 2>/dev/null || true
    echo "  ✓ Services stopped"
else
    echo "  ⚠️  No docker-compose.yml found"
fi

################################################################################
# Step 5: Remove Docker networks
################################################################################
if [ "$KEEP_NETWORKS" = false ]; then
    echo -e "${YELLOW}[4/7] Removing Docker networks...${NC}"

    # Only remove if no other containers are using them
    if [ -z "$DEPENDENT_SITES" ]; then
        docker network rm wordpress-sites 2>/dev/null && echo "  ✓ Removed wordpress-sites network" || echo "  ⚠️  wordpress-sites network not found or in use"
        docker network rm db-network 2>/dev/null && echo "  ✓ Removed db-network" || echo "  ⚠️  db-network not found or in use"
    else
        echo "  ⚠️  Skipping network removal (dependent sites found)"
    fi
else
    echo -e "${YELLOW}[4/7] Keeping Docker networks...${NC}"
fi

################################################################################
# Step 6: Remove infrastructure directory
################################################################################
echo -e "${YELLOW}[5/7] Removing infrastructure directory...${NC}"

if [ "$KEEP_DATA" = true ]; then
    # Remove everything except database directory
    cd "${LOCAL_INFRA_DIR}"
    for item in *; do
        if [ "$item" != "database" ]; then
            rm -rf "$item"
        fi
    done
    rm -rf .provisions .provision-script-hash .env 2>/dev/null || true
    echo "  ✓ Infrastructure removed (database preserved)"
else
    rm -rf "${LOCAL_INFRA_DIR}"
    echo "  ✓ Infrastructure directory removed"
fi

################################################################################
# Step 7: Remove SSH configuration
################################################################################
if [ "$KEEP_SSH" = false ]; then
    echo -e "${YELLOW}[6/7] Removing SSH configuration...${NC}"

    # Remove SSH keys
    if [ -f "${SSH_KEY_PATH}" ]; then
        rm -f "${SSH_KEY_PATH}" "${SSH_KEY_PATH}.pub"
        echo "  ✓ Removed SSH keys: $(basename ${SSH_KEY_PATH})"
    else
        echo "  ⚠️  SSH keys not found"
    fi

    # Remove from SSH config
    if grep -q "local${INFRA_NAME_CLEAN}" ~/.ssh/config 2>/dev/null; then
        # Create a temporary file without the infrastructure entries
        grep -v "local${INFRA_NAME_CLEAN}" ~/.ssh/config > ~/.ssh/config.tmp || true
        mv ~/.ssh/config.tmp ~/.ssh/config
        echo "  ✓ Removed SSH config entries"
    else
        echo "  ⚠️  No SSH config entries found"
    fi

    # Remove from known_hosts (optional, less critical)
    # We can't easily identify which entries belong to this infrastructure
    echo "  Note: known_hosts entries preserved (harmless)"
else
    echo -e "${YELLOW}[6/7] Keeping SSH configuration...${NC}"
fi

################################################################################
# Step 8: Summary
################################################################################
echo -e "${YELLOW}[7/7] Cleanup complete${NC}"
echo ""

echo -e "${GREEN}=== Removal Summary ===${NC}"
echo ""
echo "Infrastructure: ${INFRA_NAME}"
echo ""

if [ "$KEEP_DATA" = true ]; then
    echo "Data backup: ${BACKUP_DIR}"
    echo ""
    echo "To restore data:"
    echo "  1. Clone infrastructure again: ./clone-infrastructure.sh ${INFRA_NAME} <ip>"
    echo "  2. Restore databases: cp -r ${BACKUP_DIR}/database/* ~/.${INFRA_NAME}/database/"
    echo "  3. Restart: cd ~/.${INFRA_NAME} && docker-compose restart"
    echo ""
fi

if [ -n "$DEPENDENT_SITES" ]; then
    echo -e "${RED}⚠️  WARNING: The following WordPress sites may be affected:${NC}"
    for site in $DEPENDENT_SITES; do
        echo "  - $site"
    done
    echo ""
    echo "These sites will need database reconnection or removal."
    echo ""
fi

echo "Infrastructure has been removed."
echo ""
