#!/bin/bash

################################################################################
# Infrastructure Cloner
# Clones production infrastructure to local development environment
#
# Usage: ./clone-infrastructure.sh <infrastructure-name> <server-ip> [--clean]
# Example: ./clone-infrastructure.sh refine-digital-app 65.108.48.82
#          ./clone-infrastructure.sh refine-digital-app 65.108.48.82 --clean
#
# Options:
#   --clean    Remove existing infrastructure before cloning
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PRODUCTION_USER="fly"
PRODUCTION_INFRA_DIR="/home/fly/.fly"  # Production infrastructure location
LOCAL_USER_HOME="${HOME}"
SSH_CONFIG="${HOME}/.ssh/config"
SSH_KEY_TYPE="ed25519"  # Modern, secure key type
SSH_KEY_ROLE="digops"   # SSH key role suffix

# Parse arguments
CLEAN_MODE=false
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo -e "${RED}Usage: $0 <infrastructure-name> <server-ip> [--clean]${NC}"
    echo "Example: $0 refine-digital-app 65.108.48.82"
    echo ""
    echo "Options:"
    echo "  --clean    Remove existing infrastructure before cloning"
    exit 1
fi

if [ $# -eq 3 ] && [ "$3" == "--clean" ]; then
    CLEAN_MODE=true
fi

INFRA_NAME=$1
SERVER_IP=$2

# Generate SSH key name following convention: id_localrefinedigitalapp_digops
# Remove dashes and dots from infrastructure name
INFRA_NAME_CLEAN=$(echo "${INFRA_NAME}" | tr -d '.-')
SSH_KEY_NAME="id_local${INFRA_NAME_CLEAN}_${SSH_KEY_ROLE}"
SSH_KEY_PATH="${HOME}/.ssh/${SSH_KEY_NAME}"

# SSH host alias for config
SSH_HOST_ALIAS="${INFRA_NAME}-${SERVER_IP}"

# Local infrastructure in hidden directory: ~/.refine-digital-app
LOCAL_INFRA_DIR="${LOCAL_USER_HOME}/.${INFRA_NAME}"

# Setup logging
LOG_FILE="${LOCAL_USER_HOME}/infrastructure-clone-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo -e "${GREEN}=== Infrastructure Cloner ===${NC}"
echo "Infrastructure: ${INFRA_NAME}"
echo "Production: ${PRODUCTION_USER}@${SERVER_IP}"
echo "Local: ${LOCAL_INFRA_DIR}"
echo "Clean mode: ${CLEAN_MODE}"
echo "Log file: ${LOG_FILE}"
echo ""

################################################################################
# SSH Setup & Verification
################################################################################
echo -e "${YELLOW}Setting up SSH connection...${NC}"

# Step 1: Check if SSH key exists
# SSH_KEY_PATH already set above: ~/.ssh/id_localrefinedigitalapp_digops
if [ ! -f "${SSH_KEY_PATH}" ]; then
    echo -e "${YELLOW}No SSH key found. Generating ${SSH_KEY_TYPE} key...${NC}"
    echo -e "${BLUE}Key name: ${SSH_KEY_NAME}${NC}"
    ssh-keygen -t ${SSH_KEY_TYPE} -f "${SSH_KEY_PATH}" -N "" -C "${USER}@$(hostname)-${INFRA_NAME}"
    echo -e "${GREEN}✓ SSH key generated: ${SSH_KEY_PATH}${NC}"
else
    echo -e "${GREEN}✓ SSH key found: ${SSH_KEY_PATH}${NC}"
fi

# Step 2: Ensure SSH config exists
if [ ! -f "${SSH_CONFIG}" ]; then
    mkdir -p "${HOME}/.ssh"
    touch "${SSH_CONFIG}"
    chmod 600 "${SSH_CONFIG}"
    echo -e "${GREEN}✓ Created SSH config: ${SSH_CONFIG}${NC}"
fi

# Step 3: Check if this host is already in SSH config
if grep -q "^Host ${SSH_HOST_ALIAS}$" "${SSH_CONFIG}"; then
    echo -e "${GREEN}✓ SSH config entry exists for ${SSH_HOST_ALIAS}${NC}"
else
    echo -e "${YELLOW}Adding SSH config entry for ${SSH_HOST_ALIAS}...${NC}"

    # Add entry to SSH config
    cat >> "${SSH_CONFIG}" << EOF

# Infrastructure: ${INFRA_NAME}
Host ${SSH_HOST_ALIAS}
  HostName ${SERVER_IP}
  User ${PRODUCTION_USER}
  IdentityFile ${SSH_KEY_PATH}
  IdentitiesOnly yes
EOF

    echo -e "${GREEN}✓ Added to SSH config${NC}"
fi

# Step 4: Add server host key to known_hosts
echo -e "${YELLOW}Adding server host key to known_hosts...${NC}"

# Check if host key is already in known_hosts
if ! ssh-keygen -F ${SERVER_IP} > /dev/null 2>&1; then
    # Add host key to known_hosts
    ssh-keyscan -H ${SERVER_IP} >> ~/.ssh/known_hosts 2>/dev/null
    echo -e "${GREEN}✓ Server host key added${NC}"
else
    echo -e "${GREEN}✓ Server host key already exists${NC}"
fi

# Step 5: Test SSH connection
echo -e "${YELLOW}Testing SSH connection...${NC}"

if ssh -o ConnectTimeout=5 -o BatchMode=yes ${SSH_HOST_ALIAS} "echo 'Connection successful'" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ SSH connection successful${NC}"
else
    echo -e "${RED}✗ SSH connection failed${NC}"
    echo ""
    echo -e "${YELLOW}Your SSH public key needs to be added to the production server.${NC}"
    echo ""
    echo "Your public key ($(basename ${SSH_KEY_PATH}.pub)):"
    echo -e "${BLUE}$(cat ${SSH_KEY_PATH}.pub)${NC}"
    echo ""
    echo "To fix this, run ONE of these commands:"
    echo ""
    echo "  Option 1 (Automatic - if you have password access):"
    echo "    ssh-copy-id -i ${SSH_KEY_PATH}.pub ${PRODUCTION_USER}@${SERVER_IP}"
    echo ""
    echo "  Option 2 (Manual - add the above key to server):"
    echo "    1. Copy the public key above"
    echo "    2. SSH to server: ssh ${PRODUCTION_USER}@${SERVER_IP}"
    echo "    3. Add to: ~/.ssh/authorized_keys"
    echo ""
    echo "After adding the key, run this script again."
    exit 1
fi

# Step 5: Verify infrastructure exists on production
echo -e "${YELLOW}Verifying infrastructure on production...${NC}"

if ! ssh ${SSH_HOST_ALIAS} "[ -d ${PRODUCTION_INFRA_DIR} ] && [ -f ${PRODUCTION_INFRA_DIR}/docker-compose.yml ]" 2>/dev/null; then
    echo -e "${RED}Error: Infrastructure not found on production server${NC}"
    echo ""
    echo "Expected to find:"
    echo "  Directory: ${PRODUCTION_INFRA_DIR}"
    echo "  File: ${PRODUCTION_INFRA_DIR}/docker-compose.yml"
    echo ""
    echo "Please verify:"
    echo "  1. Infrastructure exists on the server"
    echo "  2. You're connecting to the correct server (${SERVER_IP})"
    echo "  3. The username is correct (${PRODUCTION_USER})"
    exit 1
fi

echo -e "${GREEN}✓ Infrastructure found on production${NC}"
echo ""

################################################################################
# Step 0: Clean up existing installation if --clean flag is set
################################################################################
if [ "$CLEAN_MODE" == "true" ]; then
    echo -e "${BLUE}[0/7] Cleaning up existing installation...${NC}"

    # Stop and remove containers
    if [ -d "${LOCAL_INFRA_DIR}" ]; then
        cd "${LOCAL_INFRA_DIR}"
        docker-compose down 2>/dev/null || true
    fi

    # Remove directory
    if [ -d "${LOCAL_INFRA_DIR}" ]; then
        rm -rf "${LOCAL_INFRA_DIR}"
        echo "  Removed ${LOCAL_INFRA_DIR}"
    fi

    echo ""
fi

################################################################################
# Step 1: Download infrastructure files
################################################################################
echo -e "${YELLOW}[1/7] Downloading infrastructure files...${NC}"

# Create target directory if it doesn't exist
mkdir -p "${LOCAL_INFRA_DIR}"

# Use rsync to efficiently sync infrastructure files
# Exclude database and certificate directories (we'll handle those separately)
rsync -avz --delete \
    --exclude 'database/' \
    --exclude 'nginx/certs/' \
    --exclude 'config/cloudflared/cert.pem' \
    --exclude 'config/cloudflared/*.json' \
    --exclude '.provision-script-hash' \
    ${SSH_HOST_ALIAS}:${PRODUCTION_INFRA_DIR}/ \
    "${LOCAL_INFRA_DIR}/"

echo "  Synced infrastructure files"

################################################################################
# Step 2: Download and track FlyWP provision script
################################################################################
echo -e "${YELLOW}[2/8] Downloading FlyWP provision script...${NC}"

# Create provisions directory
mkdir -p "${LOCAL_INFRA_DIR}/.provisions"

# Store hash file location (outside .provisions to avoid rsync overwrite)
HASH_FILE="${LOCAL_INFRA_DIR}/.provision-script-hash"

# Read previous hash before downloading (if it exists)
PREVIOUS_HASH=""
if [ -f "$HASH_FILE" ]; then
    PREVIOUS_HASH=$(cat "$HASH_FILE")
fi

# Download provision script
if rsync -avz ${SSH_HOST_ALIAS}:/home/fly/.provisions/ "${LOCAL_INFRA_DIR}/.provisions/" > /dev/null 2>&1; then
    echo "  Downloaded provision script"

    # Calculate hash of the newly downloaded provision script
    PROVISION_SCRIPT="${LOCAL_INFRA_DIR}/.provisions/initialize.sh"
    if [ -f "$PROVISION_SCRIPT" ]; then
        CURRENT_HASH=$(shasum -a 256 "$PROVISION_SCRIPT" | cut -d' ' -f1)

        # Compare with previous hash
        if [ -n "$PREVIOUS_HASH" ]; then
            if [ "$CURRENT_HASH" != "$PREVIOUS_HASH" ]; then
                echo -e "${YELLOW}  ⚠️  FlyWP provision script has been UPDATED since last clone!${NC}"
                echo -e "${YELLOW}  Previous: ${PREVIOUS_HASH:0:12}...${NC}"
                echo -e "${YELLOW}  Current:  ${CURRENT_HASH:0:12}...${NC}"
                echo -e "${YELLOW}  Consider reviewing changes or re-cloning with --clean${NC}"
                echo ""
            else
                echo "  Provision script unchanged (hash: ${CURRENT_HASH:0:12}...)"
            fi
        else
            echo "  First clone - stored provision script hash: ${CURRENT_HASH:0:12}..."
        fi

        # Store current hash
        echo "$CURRENT_HASH" > "$HASH_FILE"
    fi
else
    echo -e "${YELLOW}  ⚠️  Could not download provision script (may not exist on server)${NC}"
fi

################################################################################
# Step 3: Create database directories (empty for local)
################################################################################
echo -e "${YELLOW}[3/8] Creating database directories...${NC}"

mkdir -p "${LOCAL_INFRA_DIR}/database/mysql"
mkdir -p "${LOCAL_INFRA_DIR}/database/redis"

echo "  Created database directories"

################################################################################
# Step 3: Setup local cloudflared configuration
################################################################################
echo -e "${YELLOW}[4/8] Setting up cloudflared configuration...${NC}"

# Check if cloudflared tunnel already exists locally
if [ ! -d "${LOCAL_INFRA_DIR}/config/cloudflared" ]; then
    mkdir -p "${LOCAL_INFRA_DIR}/config/cloudflared"
fi

# Check if tunnel credentials exist
TUNNEL_CREDS=$(ls "${LOCAL_INFRA_DIR}/config/cloudflared/"*.json 2>/dev/null | head -1)

if [ -z "$TUNNEL_CREDS" ]; then
    echo -e "${YELLOW}  No cloudflared tunnel found.${NC}"
    echo ""
    echo "  To enable HTTPS access via Cloudflare Tunnel:"
    echo "    1. Login: cloudflared tunnel login"
    echo "    2. Create tunnel: cloudflared tunnel create local-${INFRA_NAME%-app}"
    echo "    3. Copy credentials JSON to: ${LOCAL_INFRA_DIR}/config/cloudflared/"
    echo "    4. Create config.yml in: ${LOCAL_INFRA_DIR}/config/cloudflared/"
    echo ""
    echo "  Skipping cloudflared setup for now..."
else
    echo "  Cloudflared credentials found: $(basename $TUNNEL_CREDS)"
fi

################################################################################
# Step 4: Create Docker networks
################################################################################
echo -e "${YELLOW}[5/8] Creating Docker networks...${NC}"

# Only create wordpress-sites network (external network shared across all sites)
# db-network will be created by docker-compose as a managed bridge network
if ! docker network ls --format '{{.Name}}' | grep -q "^wordpress-sites$"; then
    docker network create wordpress-sites
    echo "  Created network: wordpress-sites"
else
    echo "  Network already exists: wordpress-sites"
fi

echo "  Note: db-network will be created by docker-compose"

################################################################################
# Step 5: Configure environment variables
################################################################################
echo -e "${YELLOW}[6/8] Configuring environment variables...${NC}"

if [ ! -f "${LOCAL_INFRA_DIR}/.env" ]; then
    echo "MYSQL_ROOT_PASSWORD=vI5LZaWCPpWkyvBVqrAA" > "${LOCAL_INFRA_DIR}/.env"
    echo "CLOUDFLARED_TUNNEL_NAME=local-${INFRA_NAME%-app}" >> "${LOCAL_INFRA_DIR}/.env"
    echo "  Created .env file"
else
    # Update cloudflared tunnel name if it exists
    if grep -q "CLOUDFLARED_TUNNEL_NAME" "${LOCAL_INFRA_DIR}/.env"; then
        sed -i.bak "s/CLOUDFLARED_TUNNEL_NAME=.*/CLOUDFLARED_TUNNEL_NAME=local-${INFRA_NAME%-app}/" "${LOCAL_INFRA_DIR}/.env"
        rm -f "${LOCAL_INFRA_DIR}/.env.bak"
    else
        echo "CLOUDFLARED_TUNNEL_NAME=local-${INFRA_NAME%-app}" >> "${LOCAL_INFRA_DIR}/.env"
    fi
    echo "  Updated .env file"
fi

################################################################################
# Step 6: Verify docker-compose.yml
################################################################################
echo -e "${YELLOW}[7/8] Verifying docker-compose.yml...${NC}"

if [ ! -f "${LOCAL_INFRA_DIR}/docker-compose.yml" ]; then
    echo -e "${RED}Error: docker-compose.yml not found!${NC}"
    echo "The production infrastructure might not have a docker-compose.yml file."
    exit 1
fi

echo "  docker-compose.yml verified"

################################################################################
# Step 7: Start infrastructure
################################################################################
echo -e "${YELLOW}[8/8] Starting infrastructure...${NC}"

cd "${LOCAL_INFRA_DIR}"

# Start infrastructure (excluding cloudflared if not configured)
if [ -f "config/cloudflared/config.yml" ] && [ -n "$TUNNEL_CREDS" ]; then
    docker-compose up -d
    echo "  Started all services including cloudflared"
else
    # Start without cloudflared
    docker-compose up -d proxy mysql redis ofelia 2>/dev/null || docker-compose up -d
    echo "  Started infrastructure (cloudflared not configured)"
fi

echo ""
echo -e "${GREEN}=== Infrastructure Clone Complete! ===${NC}"
echo ""
echo "Infrastructure: ${INFRA_NAME}"
echo "Location: ${LOCAL_INFRA_DIR}"
echo "SSH Config: ${SSH_HOST_ALIAS}"
echo ""
echo "Services running:"
docker-compose ps
echo ""
echo "Next steps:"
echo ""
echo "1. Verify services are running:"
echo "   cd ${LOCAL_INFRA_DIR}"
echo "   docker-compose ps"
echo ""
if [ -z "$TUNNEL_CREDS" ]; then
    echo "2. Setup cloudflared tunnel for HTTPS access:"
    echo "   - Login: cloudflared tunnel login"
    echo "   - Create: cloudflared tunnel create local-${INFRA_NAME%-app}"
    echo "   - Copy credentials to: ${LOCAL_INFRA_DIR}/config/cloudflared/"
    echo "   - Create config.yml in: ${LOCAL_INFRA_DIR}/config/cloudflared/"
    echo "   - Restart: cd ${LOCAL_INFRA_DIR} && docker-compose up -d cloudflared"
    echo ""
fi
echo "3. To re-clone this infrastructure:"
echo "   ./clone-infrastructure.sh ${INFRA_NAME} ${SERVER_IP} --clean"
echo ""
echo "Log file: ${LOG_FILE}"
