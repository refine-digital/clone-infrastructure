#!/bin/bash

################################################################################
# Installation Script for clone-infrastructure
# Installs scripts to ~/.local/bin for system-wide CLI access
# Supports updates when new releases are available
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VERSION="1.0.0"

echo -e "${GREEN}=== Installing clone-infrastructure v${VERSION} ===${NC}"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Target installation directory
INSTALL_DIR="${HOME}/.local/bin"

# Create installation directory if it doesn't exist
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}Creating installation directory: ${INSTALL_DIR}${NC}"
    mkdir -p "$INSTALL_DIR"
fi

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    echo -e "${YELLOW}Warning: ${INSTALL_DIR} is not in your PATH${NC}"
    echo ""
    echo "Add this line to your shell configuration file:"
    echo -e "${BLUE}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
    echo ""

    # Detect shell and suggest appropriate file
    if [ -n "$ZSH_VERSION" ]; then
        SHELL_CONFIG="~/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        SHELL_CONFIG="~/.bashrc"
    else
        SHELL_CONFIG="your shell configuration file"
    fi

    echo "For example, run:"
    echo -e "${BLUE}echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ${SHELL_CONFIG}${NC}"
    echo -e "${BLUE}source ${SHELL_CONFIG}${NC}"
    echo ""

    read -p "Continue with installation? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
fi

# Check if already installed (for updates)
UPDATING=false
if [ -f "${INSTALL_DIR}/clone-infrastructure" ]; then
    UPDATING=true
    echo -e "${YELLOW}Existing installation found - updating...${NC}"
fi

# Install scripts
if [ "$UPDATING" = true ]; then
    echo -e "${YELLOW}Updating scripts...${NC}"
else
    echo -e "${YELLOW}Installing scripts...${NC}"
fi

# Copy and rename (remove .sh extension)
cp "${SCRIPT_DIR}/clone-infrastructure.sh" "${INSTALL_DIR}/clone-infrastructure"
cp "${SCRIPT_DIR}/remove-infrastructure.sh" "${INSTALL_DIR}/remove-infrastructure"
cp "${SCRIPT_DIR}/backup-infrastructure.sh" "${INSTALL_DIR}/backup-infrastructure"

# Make executable
chmod +x "${INSTALL_DIR}/clone-infrastructure"
chmod +x "${INSTALL_DIR}/remove-infrastructure"
chmod +x "${INSTALL_DIR}/backup-infrastructure"

if [ "$UPDATING" = true ]; then
    echo -e "${GREEN}✓ Updated clone-infrastructure${NC}"
    echo -e "${GREEN}✓ Updated remove-infrastructure${NC}"
    echo -e "${GREEN}✓ Updated backup-infrastructure${NC}"
else
    echo -e "${GREEN}✓ Installed clone-infrastructure${NC}"
    echo -e "${GREEN}✓ Installed remove-infrastructure${NC}"
    echo -e "${GREEN}✓ Installed backup-infrastructure${NC}"
fi
echo ""

# Verify installation
echo -e "${YELLOW}Verifying installation...${NC}"
if command -v clone-infrastructure &> /dev/null; then
    echo -e "${GREEN}✓ clone-infrastructure is available in PATH${NC}"
else
    echo -e "${YELLOW}⚠ clone-infrastructure not found in PATH${NC}"
    echo "  You may need to restart your terminal or run: source ${SHELL_CONFIG}"
fi

echo ""
if [ "$UPDATING" = true ]; then
    echo -e "${GREEN}=== Update Complete ===${NC}"
else
    echo -e "${GREEN}=== Installation Complete ===${NC}"
fi
echo ""
echo "Installed commands:"
echo "  • clone-infrastructure - Clone production infrastructure"
echo "  • remove-infrastructure - Remove infrastructure safely"
echo "  • backup-infrastructure - Manage backups"
echo ""
echo "Usage examples:"
echo "  clone-infrastructure dev-fi-01 46.62.207.172"
echo "  backup-infrastructure add dev-fi-01 /Volumes/Backup"
echo "  remove-infrastructure dev-fi-01"
echo ""
echo "For more information:"
echo "  https://github.com/refine-digital/clone-infrastructure"
echo ""

# Check if PATH was modified
if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    echo -e "${YELLOW}Remember to add ${INSTALL_DIR} to your PATH:${NC}"
    echo -e "${BLUE}echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ${SHELL_CONFIG}${NC}"
    echo -e "${BLUE}source ${SHELL_CONFIG}${NC}"
    echo ""
fi

# Update instructions
if [ "$UPDATING" = true ]; then
    echo -e "${BLUE}To check for future updates:${NC}"
    echo "  cd ${SCRIPT_DIR}"
    echo "  git pull"
    echo "  ./install.sh"
    echo ""
fi
