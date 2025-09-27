#!/bin/bash

# install.sh - D1 Backup Tool Installer
# Quick installer for the D1 backup tool

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

INSTALL_DIR="$HOME/d1-backup"

echo "🚀 D1 Backup Tool Installer"
echo "=========================="

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    log_error "Node.js is not installed!"
    echo
    echo "Please install Node.js first:"
    echo "  Ubuntu/Debian: sudo apt update && sudo apt install nodejs npm"
    echo "  CentOS/RHEL:   sudo yum install nodejs npm"
    echo "  Or visit:      https://nodejs.org/"
    exit 1
fi

log_info "Node.js version: $(node --version)"

# Create installation directory
log_info "Creating installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create the main Node.js script
log_info "Creating D1 backup exporter script..."
cat > "d1-backup-exporter.js" << 'NODESCRIPT'
const https = require('https');
const fs = require('fs');
const path = require('path');

class D1BackupExporter {
  constructor(config) {
    this.accountId = config.accountId;
    this.apiToken = config.apiToken;
    this.email = config.email;
    this.apiKey = config.apiKey;
    this.baseUrl = 'api.cloudflare.com';
    this.backupDir = config.backupDir || './backups';
    
    // Ensure backup directory exists
    if (!fs.existsSync(this.backupDir)) {
      fs.mkdirSync(this.backupDir, { recursive: true });
    }
  }

  async makeRequest(method, endpoint, data = null) {
    return new Promise((resolve, reject) => {
      const options = {
        hostname: this.baseUrl,
        path: endpoint,
        method: method,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'D1-Backup-Exporter/1.0'
        }
      };

      if (this.apiToken) {
        options.headers['Authorization'] = `Bearer ${this.apiToken}`;
      } else if (this.email && this.apiKey) {
        options.headers['X-Auth-Email'] = this.email;
        options.headers['X-Auth-Key'] = this.apiKey;
      } else {
        return reject(new Error('Either API token or email/API key must be provided'));
      }

      const req = https.request(options, (res) => {
        let responseBody = '';
        
        res.on('data', (chunk) => {
          responseBody += chunk;
        });

        res.on('end', () => {
          try {
            const parsedResponse = JSON.parse(responseBody);
            
            if (res.statusCode >= 200 && res.statusCode < 300) {
              resolve(parsedResponse);
            } else {
              reject(new Error(`HTTP ${res.statusCode}: ${parsedResponse.errors?.[0]?.message || 'Unknown error'}`));
            }
          } catch (parseError) {
            reject(new Error(`Failed to parse response: ${parseError.message}`));
          }
        });
      });

      req.on('error', (error) => {
        reject(error);
      });

      if (data) {
        req.write(JSON.stringify(data));
      }

      req.end();
    });
  }

  async startExport(databaseId, options = {}) {
    const endpoint = `/client/v4/accounts/${this.accountId}/d1/database/${databaseId}/export`;
    
    const requestBody = {
      output_format: 'polling',
      ...options
    };

    console.log(`Starting export for database: ${databaseId}`);
    
    try {
      const response = await this.makeRequest('POST', endpoint, requestBody);
      
      if (!response.success) {
        throw new Error(`Export failed: ${response.errors?.[0]?.message || 'Unknown error'}`);
      }

      return response.result;
    } catch (error) {
      throw new Error(`Failed to start export: ${error.message}`);
    }
  }

  async pollExport(databaseId, bookmark) {
    const endpoint = `/client/v4/accounts/${this.accountId}/d1/database/${databaseId}/export`;
    
    const requestBody = {
      output_format: 'polling',
      current_bookmark: bookmark
    };

    try {
      const response = await this.makeRequest('POST', endpoint, requestBody);
      
      if (!response.success) {
        throw new Error(`Polling failed: ${response.errors?.[0]?.message || 'Unknown error'}`);
      }

      return response.result;
    } catch (error) {
      throw new Error(`Failed to poll export: ${error.message}`);
    }
  }

  async downloadFile(url, filename) {
    return new Promise((resolve, reject) => {
      const filePath = path.join(this.backupDir, filename);
      const file = fs.createWriteStream(filePath);

      https.get(url, (response) => {
        if (response.statusCode !== 200) {
          reject(new Error(`Download failed with status: ${response.statusCode}`));
          return;
        }

        response.pipe(file);

        file.on('finish', () => {
          file.close();
          console.log(`Downloaded: ${filePath}`);
          resolve(filePath);
        });

        file.on('error', (error) => {
          fs.unlink(filePath, () => {});
          reject(error);
        });
      }).on('error', (error) => {
        reject(error);
      });
    });
  }

  async exportDatabase(databaseId, options = {}) {
    try {
      let exportResult = await this.startExport(databaseId, options.dumpOptions);
      console.log(`Export status: ${exportResult.status}`);

      while (exportResult.status === 'in-progress') {
        console.log(`Polling export... Bookmark: ${exportResult.at_bookmark}`);
        await new Promise(resolve => setTimeout(resolve, 5000));
        
        exportResult = await this.pollExport(databaseId, exportResult.at_bookmark);
        console.log(`Export status: ${exportResult.status}`);
      }

      if (exportResult.status === 'complete' && exportResult.result?.signed_url) {
        const filename = exportResult.result.filename || `${databaseId}_backup_${new Date().toISOString().split('T')[0]}.sql`;
        const filePath = await this.downloadFile(exportResult.result.signed_url, filename);
        
        return {
          success: true,
          filePath,
          filename,
          databaseId
        };
      } else if (exportResult.status === 'error') {
        throw new Error(`Export failed: ${exportResult.error || 'Unknown error'}`);
      } else {
        throw new Error(`Export completed with unexpected status: ${exportResult.status}`);
      }

    } catch (error) {
      throw new Error(`Database export failed: ${error.message}`);
    }
  }

  async exportMultipleDatabases(databaseIds, options = {}) {
    const results = [];
    
    for (const databaseId of databaseIds) {
      try {
        console.log(`\n--- Exporting database: ${databaseId} ---`);
        const result = await this.exportDatabase(databaseId, options);
        results.push(result);
        console.log(`✅ Successfully exported: ${result.filename}`);
      } catch (error) {
        console.error(`❌ Failed to export ${databaseId}: ${error.message}`);
        results.push({
          success: false,
          error: error.message,
          databaseId
        });
      }
    }

    return results;
  }
}

module.exports = D1BackupExporter;
NODESCRIPT

# Create shell wrapper (the full shell script from the previous artifact)
log_info "Creating shell wrapper script..."
cat > "d1-backup.sh" << 'SHELLSCRIPT'
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
BACKUP_DIR="${SCRIPT_DIR}/d1_backups"

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
SHELLSCRIPT

# Make scripts executable
chmod +x d1-backup.sh

# Create example database list file
cat > "databases-example.txt" << 'DBLIST'
# Example database list file
# One database ID per line
# Lines starting with # are comments

# your-database-id-1
# your-database-id-2
# your-database-id-3
DBLIST

# Create a quick start guide
cat > "README.md" << 'README'
# D1 Backup Tool

Easy-to-use command line tool for backing up Cloudflare D1 databases.

## Quick Start

1. **Setup configuration:**
   ```bash
   ./d1-backup.sh --config
   ```

2. **Backup a single database:**
   ```bash
   ./d1-backup.sh your-database-id
   ```

3. **Backup multiple databases:**
   ```bash
   # Edit databases.txt with your database IDs
   ./d1-backup.sh --multiple -f databases.txt
   ```

## Usage Examples

```bash
# Show help
./d1-backup.sh --help

# Setup credentials
./d1-backup.sh --config

# Basic backup
./d1-backup.sh abc123-def456-ghi789

# Backup to specific directory
./d1-backup.sh -d /path/to/backups abc123-def456-ghi789

# Schema only backup
./d1-backup.sh --no-data abc123-def456-ghi789

# Backup specific tables only
./d1-backup.sh --tables users,orders abc123-def456-ghi789
```

## Files

- `d1-backup.sh` - Main shell script
- `d1-backup-exporter.js` - Node.js backend
- `.d1-config` - Configuration file (created after setup)
- `databases-example.txt` - Example database list
