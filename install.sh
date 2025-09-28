#!/bin/bash

# install.sh - D1 Backup Tool Installer
# Quick installer for the D1 backup tool

#!/bin/bash

# install.sh - D1 Backup Tool Installer
# Downloads latest files from GitHub repository

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
REPO_URL="https://raw.githubusercontent.com/oliwebd/d1-backup/main"
# INSTALL_DIR="$HOME/d1-backup" update to option 1
# Option 1: relative to where you run the script
INSTALL_DIR="$PWD/d1-backup"

# Option 2: relative to script location
# SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# INSTALL_DIR="$SCRIPT_DIR/d1-backup"

echo "🚀 D1 Backup Tool Installer ${VERSION}"
echo "======================================"

# Check if curl or wget is available
if command -v curl >/dev/null 2>&1; then
    DOWNLOAD_CMD="curl -sSL"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOAD_CMD="wget -qO-"
else
    log_error "Neither curl nor wget is installed!"
    echo "Please install curl or wget first:"
    echo "  Ubuntu/Debian: sudo apt update && sudo apt install curl"
    echo "  CentOS/RHEL:   sudo yum install curl"
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    log_error "Node.js is not installed!"
    echo
    echo "Please install Node.js first:"
    echo "  Ubuntu/Debian: sudo apt update && sudo apt install nodejs npm"
    echo "  CentOS/RHEL:   sudo yum install nodejs npm"
    echo "  macOS:         brew install node"
    echo "  Or visit:      https://nodejs.org/"
    exit 1
fi

log_info "Node.js version: $(node --version)"

# Create installation directory
log_info "Creating installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download main Node.js script
log_info "Downloading d1-backup-exporter.js..."
if ! $DOWNLOAD_CMD "$REPO_URL/d1-backup-exporter.js" > "d1-backup-exporter.js"; then
    log_error "Failed to download d1-backup-exporter.js"
    exit 1
fi

# Download shell wrapper script
log_info "Downloading d1-backup.sh..."
if ! $DOWNLOAD_CMD "$REPO_URL/d1-backup.sh" > "d1-backup.sh"; then
    log_error "Failed to download d1-backup.sh"
    exit 1
fi

# Download README
log_info "Downloading README.md..."
if ! $DOWNLOAD_CMD "$REPO_URL/README.md" > "README.md"; then
    log_warning "Failed to download README.md (continuing anyway)"
fi

# Download example database list
log_info "Creating example database list..."
cat > "databases-example.txt" << 'EOF'
# Example database list file for batch operations
# One database ID per line
# Lines starting with # are comments and will be ignored

# Replace these with your actual database IDs:
# xdad5e9e8-afd8-4bb6-9498-ad585a72670c
# your-database-id-2
# your-database-id-3

# You can get your database IDs from:
# https://dash.cloudflare.com/
# Navigate to: Workers & Pages > D1 SQL Database
EOF

# Make shell script executable
chmod +x d1-backup.sh

# Verify downloaded files
log_info "Verifying installation..."
if [ ! -f "d1-backup-exporter.js" ] || [ ! -s "d1-backup-exporter.js" ]; then
    log_error "d1-backup-exporter.js is missing or empty"
    exit 1
fi

if [ ! -f "d1-backup.sh" ] || [ ! -s "d1-backup.sh" ]; then
    log_error "d1-backup.sh is missing or empty"
    exit 1
fi

# Test if the script works
log_info "Testing installation..."
if ./d1-backup.sh --help >/dev/null 2>&1; then
    log_success "Installation test passed!"
else
    log_warning "Installation test failed, but files are downloaded"
fi

log_success "Installation completed successfully!"
log_info "Installation directory: $INSTALL_DIR"

echo
echo "🎉 Installation Complete!"
echo "========================"
echo
echo "Files created:"
echo "  ✓ d1-backup.sh           - Main backup script"
echo "  ✓ d1-backup-exporter.js  - Node.js backend"
echo "  ✓ databases-example.txt  - Example database list"
if [ -f "README.md" ]; then
    echo "  ✓ README.md             - Documentation"
fi
echo
echo "📋 Next Steps:"
echo "1. cd $INSTALL_DIR"
echo "2. ./d1-backup.sh --config      # Setup your Cloudflare credentials"
echo "3. ./d1-backup.sh YOUR_DB_ID    # Backup your first database"
echo
echo "📚 For help:"
echo "  ./d1-backup.sh --help"
echo "  cat README.md"
echo
echo "🔧 Configuration:"
echo "  Your credentials will be stored in: $INSTALL_DIR/.d1-config"
echo "  Backups will be saved to: $INSTALL_DIR/d1_backups/"
echo
echo "🌟 Repository: https://github.com/oliwebd/Export-backup-D1-Database-As-Sql"
echo
