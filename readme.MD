# 📦d1-backup: Export & Backup Cloudflare D1 Database As SQL file by API/CLI

Easy-to-use command line tool for exporting and backing up Cloudflare D1 databases to SQL files. Supports single and multiple database backups with advanced options.

## ✨ Features

- 🚀 **One-click installation** with automated setup
- 🔐 **Secure authentication** via API tokens or email/key
- 📊 **Single or batch backups** of multiple databases
- ⚙️ **Flexible export options** (schema-only, data-only, specific tables)
- 🔄 **Automatic polling** handles long-running exports
- 📁 **Organized file management** with timestamped backups
- 🎨 **Colored terminal output** for better visibility
- 🛡️ **Error handling** with detailed logging

## 🎯 Quick Start

### 1. Install the Tool

```bash
# Users run this:
curl -sSL https://raw.githubusercontent.com/oliwebd/d1-backup/main/install.sh | bash

```
## Or
```bash
# Or download and run:
wget https://raw.githubusercontent.com/oliwebd/d1-backup/main/install.sh
chmod +x install.sh
./install.sh
```

### 2. Navigate to Installation Directory

```bash
cd ./d1-backup
```

### 3. Setup Configuration

```bash
./d1-backup.sh --config
```

Follow the prompts to enter your Cloudflare credentials.

### 4. Backup Your First Database

```bash
./d1-backup.sh your-database-id
```

## 📋 Prerequisites

- **Node.js** (v12 or higher)
- **Cloudflare Account** with D1 databases
- **API Token** or **Email + API Key**

### Installing Node.js

**Ubuntu/Debian:**
```bash
sudo apt update && sudo apt install nodejs npm
```

**CentOS/RHEL:**
```bash
sudo yum install nodejs npm
```

**macOS:**
```bash
brew install node
```

**Or download from:** [nodejs.org](https://nodejs.org/)

## 🔧 Configuration

### Getting Your Cloudflare Credentials

1. **Account ID**: Found in your Cloudflare dashboard sidebar
2. **API Token** (Recommended):
   - Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
   - Click "Create Token"
   - Use "Custom token" with these permissions:
     - `Zone:Zone:Read`
     - `Zone:Zone Settings:Read` 
     - `Account:Cloudflare D1:Edit`

3. **Alternative - Email + API Key**:
   - Go to [Cloudflare API Keys](https://dash.cloudflare.com/profile/api-tokens)
   - Use your "Global API Key"

### Manual Configuration

Edit the configuration file directly:
```bash
nano ~/.d1-backup/.d1-config
```

```bash
# D1 Backup Configuration
CLOUDFLARE_ACCOUNT_ID='your-account-id'
CLOUDFLARE_API_TOKEN='your-api-token'
BACKUP_DIR='/path/to/database_backups'
```

## 🚀 Usage

### Basic Commands

```bash
# Show help
./d1-backup.sh --help

# Setup/reconfigure credentials
./d1-backup.sh --config

# Backup single database
./d1-backup.sh your-database-id

# Backup to specific directory
./d1-backup.sh -d /custom/backup/path your-database-id
```

### Advanced Options

```bash
# Export schema only (no data)
./d1-backup.sh --no-data your-database-id

# Export data only (no schema)  
./d1-backup.sh --no-schema your-database-id

# Export specific tables only
./d1-backup.sh --tables users,orders,products your-database-id
```

### Batch Operations

```bash
# Create database list file
cat > databases.txt << EOF
database-id-1
database-id-2  
database-id-3
# Comments are supported
EOF

# Backup multiple databases
./d1-backup.sh --multiple -f databases.txt
```

### Environment Variables

You can also set credentials via environment variables:

```bash
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
export CLOUDFLARE_API_TOKEN="your-api-token"
./d1-backup.sh your-database-id
```

## 📁 File Structure

After installation:

```
~/d1-backup/
├── d1-backup.sh              # Main shell script
├── d1-backup-exporter.js     # Node.js backend
├── .d1-config                # Configuration file
├── databases-example.txt     # Example database list
├── README.md                 # Documentation
└── database_backups/              # Default backup directory
    ├── database1_backup_2024-01-15.sql
    ├── database2_backup_2024-01-15.sql
    └── ...
```

## 🔍 Command Reference

| Option | Description | Example |
|--------|-------------|---------|
| `-h, --help` | Show help message | `./d1-backup.sh --help` |
| `-c, --config` | Setup configuration | `./d1-backup.sh --config` |
| `-d, --dir DIR` | Backup directory | `./d1-backup.sh -d /backups db-id` |
| `-m, --multiple` | Multiple database mode | `./d1-backup.sh -m -f list.txt` |
| `-f, --file FILE` | Database list file | `./d1-backup.sh -f databases.txt` |
| `--no-data` | Schema only export | `./d1-backup.sh --no-data db-id` |
| `--no-schema` | Data only export | `./d1-backup.sh --no-schema db-id` |
| `--tables LIST` | Specific tables | `./d1-backup.sh --tables users,orders db-id` |

## 🐛 Troubleshooting

### Common Issues

**"Node.js is not installed"**
```bash
# Install Node.js first (see Prerequisites section)
```

**"Authentication not configured"**
```bash
# Run configuration setup
./d1-backup.sh --config
```

**"Database ID not found"**
- Verify your database ID in Cloudflare dashboard
- Check your account ID and API permissions

**"Export failed with HTTP 403"**
- Verify API token has correct permissions
- Check account ID is correct

### Debug Mode

For verbose output, run with debug:
```bash
set -x
./d1-backup.sh your-database-id
```

### Log Files

Backup logs are displayed in terminal. For persistent logging:
```bash
./d1-backup.sh your-database-id 2>&1 | tee backup.log
```

## 🔒 Security

- Configuration files are created with `600` permissions (owner read/write only)
- API tokens are stored locally and never transmitted except to Cloudflare
- Use API tokens instead of global API keys when possible
- Keep your `.d1-config` file secure

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⭐ Support

If this tool helped you, please consider:
- ⭐ Starring this repository
- 🐛 Reporting issues
- 💡 Suggesting new features
- 🤝 Contributing improvements

## 📞 Support & Issues

- 🐛 **Bug Reports**: [Open an issue](https://github.com/oliwebd/Export-backup-D1-Database-As-Sql/issues)
- 💡 **Feature Requests**: [Open an issue](https://github.com/oliwebd/Export-backup-D1-Database-As-Sql/issues)
- 📖 **Documentation**: Check this README or [Cloudflare D1 Docs](https://developers.cloudflare.com/d1/)

## 🔗 Related Links

- [Cloudflare D1 Documentation](https://developers.cloudflare.com/d1/)
- [Cloudflare API Documentation](https://api.cloudflare.com/)
- [Node.js Downloads](https://nodejs.org/)

---

Made with ❤️ for the Cloudflare D1 dev community by a Bangladeshi — a farmer's son.  
Love hard work and staying active.
