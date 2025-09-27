#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_SCRIPT="${SCRIPT_DIR}/d1-backup-exporter.js"
CONFIG_FILE="${SCRIPT_DIR}/.d1-config"
BACKUP_DIR="${SCRIPT_DIR}/database_backups"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_usage() {
    cat << EOF
D1 Database Backup Tool

Usage: $0 [OPTIONS] [DATABASE_ID]

OPTIONS:
    -h, --help              Show this help message
    -c, --config            Setup configuration
    -d, --dir DIR          Backup directory (default: ./d1_backups)
    -m, --multiple         Backup multiple databases from file
    -f, --file FILE        File containing database IDs (one per line)
    --no-data              Export schema only (no data)
    --no-schema            Export data only (no schema)
    --tables TABLE1,TABLE2 Export specific tables only

EXAMPLES:
    $0 --config                           # Setup configuration
    $0 abc123-def456-ghi789               # Backup single database
    $0 -d /backups abc123-def456-ghi789   # Backup to specific directory
    $0 --multiple -f databases.txt        # Backup multiple databases

EOF
}

setup_config() {
    log_info "Setting up D1 Backup configuration..."
    
    echo
    echo "Choose authentication method:"
    echo "1) API Token (Recommended)"
    echo "2) Email + API Key"
    read -p "Select option (1 or 2): " auth_method
    
    cat > "$CONFIG_FILE" << EOF
# D1 Backup Configuration
# Generated on $(date)

EOF
    
    read -p "Enter your Cloudflare Account ID: " account_id
    echo "CLOUDFLARE_ACCOUNT_ID='$account_id'" >> "$CONFIG_FILE"
    
    if [ "$auth_method" = "1" ]; then
        read -s -p "Enter your Cloudflare API Token: " api_token
        echo
        echo "CLOUDFLARE_API_TOKEN='$api_token'" >> "$CONFIG_FILE"
    else
        read -p "Enter your Cloudflare Email: " email
        read -s -p "Enter your Cloudflare API Key: " api_key
        echo
        echo "CLOUDFLARE_EMAIL='$email'" >> "$CONFIG_FILE"
        echo "CLOUDFLARE_API_KEY='$api_key'" >> "$CONFIG_FILE"
    fi
    
    chmod 600 "$CONFIG_FILE"
    log_success "Configuration saved to $CONFIG_FILE"
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        log_info "Loaded configuration from $CONFIG_FILE"
    fi
}

check_prerequisites() {
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed."
        exit 1
    fi
    
    if [ ! -f "$NODE_SCRIPT" ]; then
        log_error "Node.js script not found: $NODE_SCRIPT"
        exit 1
    fi
    
    if [ -z "$CLOUDFLARE_ACCOUNT_ID" ]; then
        log_error "CLOUDFLARE_ACCOUNT_ID not set. Run '$0 --config'"
        exit 1
    fi
    
    if [ -z "$CLOUDFLARE_API_TOKEN" ] && ([ -z "$CLOUDFLARE_EMAIL" ] || [ -z "$CLOUDFLARE_API_KEY" ]); then
        log_error "Authentication not configured. Run '$0 --config'"
        exit 1
    fi
}

create_node_wrapper() {
    local database_id="$1"
    local dump_options="$2"
    local is_multiple="$3"
    local db_file="$4"
    
    cat > "/tmp/d1-backup-run.js" << EOF
const D1BackupExporter = require('$NODE_SCRIPT');

async function runBackup() {
    const config = {
        accountId: process.env.CLOUDFLARE_ACCOUNT_ID,
        apiToken: process.env.CLOUDFLARE_API_TOKEN,
        email: process.env.CLOUDFLARE_EMAIL,
        apiKey: process.env.CLOUDFLARE_API_KEY,
        backupDir: process.env.BACKUP_DIR || '$BACKUP_DIR'
    };

    const exporter = new D1BackupExporter(config);

    try {
        if ('$is_multiple' === 'true') {
            const fs = require('fs');
            const databaseIds = fs.readFileSync('$db_file', 'utf8')
                .split('\\n')
                .map(line => line.trim())
                .filter(line => line && !line.startsWith('#'));
            
            const results = await exporter.exportMultipleDatabases(databaseIds, {
                dumpOptions: $dump_options
            });
            
            console.log('\\n📊 Export Summary:');
            results.forEach(result => {
                if (result.success) {
                    console.log(\`✅ \${result.databaseId}: \${result.filename}\`);
                } else {
                    console.log(\`❌ \${result.databaseId}: \${result.error}\`);
                }
            });
        } else {
            const result = await exporter.exportDatabase('$database_id', {
                dumpOptions: $dump_options
            });
            
            console.log('\\n🎉 Export completed successfully!');
            console.log(\`File saved to: \${result.filePath}\`);
        }
    } catch (error) {
        console.error('❌ Export failed:', error.message);
        process.exit(1);
    }
}

runBackup();
EOF
}

main() {
    local database_id=""
    local dump_options="{}"
    local is_multiple="false"
    local db_file=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help) show_usage; exit 0 ;;
            -c|--config) setup_config; exit 0 ;;
            -d|--dir) BACKUP_DIR="$2"; shift 2 ;;
            -m|--multiple) is_multiple="true"; shift ;;
            -f|--file) db_file="$2"; shift 2 ;;
            --no-data) dump_options='{"no_data": true}'; shift ;;
            --no-schema) dump_options='{"no_schema": true}'; shift ;;
            --tables) 
                IFS=',' read -ra table_array <<< "$2"
                tables="[\"$(IFS='","'; echo "${table_array[*]}")\"]"
                dump_options="{\"tables\": $tables}"
                shift 2 ;;
            -*) log_error "Unknown option: $1"; exit 1 ;;
            *) 
                if [ -z "$database_id" ]; then
                    database_id="$1"
                else
                    log_error "Multiple database IDs provided"
                    exit 1
                fi
                shift ;;
        esac
    done
    
    load_config
    check_prerequisites
    
    if [ "$is_multiple" = "true" ] && [ -z "$db_file" ]; then
        log_error "Multiple backup requires --file option"
        exit 1
    fi
    
    if [ "$is_multiple" = "false" ] && [ -z "$database_id" ]; then
        log_error "Database ID required"
        exit 1
    fi
    
    mkdir -p "$BACKUP_DIR"
    
    export CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_API_TOKEN CLOUDFLARE_EMAIL CLOUDFLARE_API_KEY BACKUP_DIR
    
    create_node_wrapper "$database_id" "$dump_options" "$is_multiple" "$db_file"
    
    log_info "Starting D1 database backup..."
    node /tmp/d1-backup-run.js
    
    rm -f /tmp/d1-backup-run.js
    log_success "Backup process completed!"
}

main "$@"
