const https = require('https');
const fs = require('fs');
const path = require('path');

class D1BackupExporter {
  constructor(config) {
    // Validate required configuration
    if (!config.accountId) {
      throw new Error('Account ID is required');
    }
    
    if (!config.apiToken && (!config.email || !config.apiKey)) {
      throw new Error('Either API token or email/API key combination is required');
    }

    this.accountId = config.accountId;
    this.apiToken = config.apiToken;
    this.email = config.email;
    this.apiKey = config.apiKey;
    this.baseUrl = 'api.cloudflare.com';
    this.backupDir = config.backupDir || './backups';
    this.timeout = config.timeout || 30000; // 30 seconds default timeout
    this.maxRetries = config.maxRetries || 3;
    this.retryDelay = config.retryDelay || 1000; // 1 second
    
    // Ensure backup directory exists
    if (!fs.existsSync(this.backupDir)) {
      fs.mkdirSync(this.backupDir, { recursive: true });
    }
  }

  /**
   * Sleep utility function
   */
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Make HTTP request to Cloudflare API with retry logic
   */
  async makeRequest(method, endpoint, data = null, retryCount = 0) {
    return new Promise((resolve, reject) => {
      const options = {
        hostname: this.baseUrl,
        path: endpoint,
        method: method,
        timeout: this.timeout,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'D1-Backup-Exporter/1.0'
        }
      };

      // Add authentication headers
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
              // Handle rate limiting with retry
              if (res.statusCode === 429 && retryCount < this.maxRetries) {
                console.log(`Rate limited. Retrying in ${this.retryDelay}ms... (attempt ${retryCount + 1})`);
                setTimeout(() => {
                  this.makeRequest(method, endpoint, data, retryCount + 1)
                    .then(resolve)
                    .catch(reject);
                }, this.retryDelay * Math.pow(2, retryCount)); // Exponential backoff
              } else {
                const errorMsg = parsedResponse.errors?.[0]?.message || 'Unknown error';
                reject(new Error(`HTTP ${res.statusCode}: ${errorMsg}`));
              }
            }
          } catch (parseError) {
            reject(new Error(`Failed to parse response: ${parseError.message}`));
          }
        });
      });

      req.on('timeout', () => {
        req.destroy();
        if (retryCount < this.maxRetries) {
          console.log(`Request timeout. Retrying... (attempt ${retryCount + 1})`);
          setTimeout(() => {
            this.makeRequest(method, endpoint, data, retryCount + 1)
              .then(resolve)
              .catch(reject);
          }, this.retryDelay);
        } else {
          reject(new Error(`Request timeout after ${this.maxRetries} retries`));
        }
      });

      req.on('error', (error) => {
        if (retryCount < this.maxRetries) {
          console.log(`Request error: ${error.message}. Retrying... (attempt ${retryCount + 1})`);
          setTimeout(() => {
            this.makeRequest(method, endpoint, data, retryCount + 1)
              .then(resolve)
              .catch(reject);
          }, this.retryDelay);
        } else {
          reject(new Error(`Request failed after ${this.maxRetries} retries: ${error.message}`));
        }
      });

      if (data) {
        req.write(JSON.stringify(data));
      }

      req.end();
    });
  }

  /**
   * Start database export
   */
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

  /**
   * Poll export status
   */
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

  /**
   * Download file from URL with progress and retry logic
   */
  async downloadFile(url, filename, retryCount = 0) {
    return new Promise((resolve, reject) => {
      const filePath = path.join(this.backupDir, filename);
      const file = fs.createWriteStream(filePath);
      
      // Add progress tracking
      let downloadedBytes = 0;
      let totalBytes = 0;

      const request = https.get(url, (response) => {
        if (response.statusCode === 302 || response.statusCode === 301) {
          // Handle redirects
          file.close();
          fs.unlink(filePath, () => {});
          return this.downloadFile(response.headers.location, filename, retryCount)
            .then(resolve)
            .catch(reject);
        }

        if (response.statusCode !== 200) {
          file.close();
          fs.unlink(filePath, () => {});
          
          if (retryCount < this.maxRetries) {
            console.log(`Download failed with status ${response.statusCode}. Retrying... (attempt ${retryCount + 1})`);
            setTimeout(() => {
              this.downloadFile(url, filename, retryCount + 1)
                .then(resolve)
                .catch(reject);
            }, this.retryDelay);
          } else {
            reject(new Error(`Download failed with status: ${response.statusCode}`));
          }
          return;
        }

        totalBytes = parseInt(response.headers['content-length'] || '0');
        if (totalBytes > 0) {
          console.log(`Downloading ${filename} (${(totalBytes / 1024 / 1024).toFixed(2)} MB)`);
        }

        response.on('data', (chunk) => {
          downloadedBytes += chunk.length;
          if (totalBytes > 0) {
            const progress = ((downloadedBytes / totalBytes) * 100).toFixed(1);
            process.stdout.write(`\rProgress: ${progress}%`);
          }
        });

        response.pipe(file);

        file.on('finish', () => {
          file.close();
          if (totalBytes > 0) {
            console.log(`\nDownloaded: ${filePath} (${(downloadedBytes / 1024 / 1024).toFixed(2)} MB)`);
          } else {
            console.log(`Downloaded: ${filePath}`);
          }
          resolve(filePath);
        });

        file.on('error', (error) => {
          fs.unlink(filePath, () => {});
          
          if (retryCount < this.maxRetries) {
            console.log(`\nFile write error: ${error.message}. Retrying... (attempt ${retryCount + 1})`);
            setTimeout(() => {
              this.downloadFile(url, filename, retryCount + 1)
                .then(resolve)
                .catch(reject);
            }, this.retryDelay);
          } else {
            reject(error);
          }
        });
      });

      request.on('error', (error) => {
        file.close();
        fs.unlink(filePath, () => {});
        
        if (retryCount < this.maxRetries) {
          console.log(`Download request error: ${error.message}. Retrying... (attempt ${retryCount + 1})`);
          setTimeout(() => {
            this.downloadFile(url, filename, retryCount + 1)
              .then(resolve)
              .catch(reject);
          }, this.retryDelay);
        } else {
          reject(error);
        }
      });

      request.setTimeout(this.timeout, () => {
        request.destroy();
        file.close();
        fs.unlink(filePath, () => {});
        
        if (retryCount < this.maxRetries) {
          console.log(`Download timeout. Retrying... (attempt ${retryCount + 1})`);
          setTimeout(() => {
            this.downloadFile(url, filename, retryCount + 1)
              .then(resolve)
              .catch(reject);
          }, this.retryDelay);
        } else {
          reject(new Error(`Download timeout after ${this.maxRetries} retries`));
        }
      });
    });
  }

  /**
   * Export database and download SQL backup
   */
  async exportDatabase(databaseId, options = {}) {
    const startTime = Date.now();
    
    try {
      // Validate database ID format
      if (!databaseId || typeof databaseId !== 'string') {
        throw new Error('Valid database ID is required');
      }

      // Start export
      let exportResult = await this.startExport(databaseId, options.dumpOptions);
      console.log(`Export status: ${exportResult.status}`);

      // Poll until complete with timeout protection
      const maxPollTime = options.maxPollTime || 30 * 60 * 1000; // 30 minutes default
      const pollStartTime = Date.now();

      while (exportResult.status === 'in-progress' || exportResult.status === 'active') {
        // Check for timeout
        if (Date.now() - pollStartTime > maxPollTime) {
          throw new Error(`Export polling timeout after ${maxPollTime / 1000} seconds`);
        }

        console.log(`Polling export... Bookmark: ${exportResult.at_bookmark}`);
        await this.sleep(5000); // Wait 5 seconds
        
        exportResult = await this.pollExport(databaseId, exportResult.at_bookmark);
        console.log(`Export status: ${exportResult.status}`);
      }

      if (exportResult.status === 'complete' && exportResult.result?.signed_url) {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-').split('T')[0];
        const filename = exportResult.result.filename || `${databaseId}_backup_${timestamp}.sql`;
        const filePath = await this.downloadFile(exportResult.result.signed_url, filename);
        
        const totalTime = ((Date.now() - startTime) / 1000).toFixed(2);
        console.log(`Export completed in ${totalTime} seconds`);
        
        return {
          success: true,
          filePath,
          filename,
          databaseId,
          exportTime: totalTime,
          fileSize: fs.statSync(filePath).size
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

  /**
   * Export multiple databases with progress tracking
   */
  async exportMultipleDatabases(databaseIds, options = {}) {
    const results = [];
    const startTime = Date.now();
    
    console.log(`Starting batch export of ${databaseIds.length} databases...`);
    
    for (let i = 0; i < databaseIds.length; i++) {
      const databaseId = databaseIds[i];
      const progress = `[${i + 1}/${databaseIds.length}]`;
      
      try {
        console.log(`\n${progress} --- Exporting database: ${databaseId} ---`);
        const result = await this.exportDatabase(databaseId, options);
        results.push(result);
        console.log(`✅ ${progress} Successfully exported: ${result.filename} (${(result.fileSize / 1024 / 1024).toFixed(2)} MB)`);
      } catch (error) {
        console.error(`❌ ${progress} Failed to export ${databaseId}: ${error.message}`);
        results.push({
          success: false,
          error: error.message,
          databaseId
        });
      }
      
      // Add delay between exports to be respectful to API
      if (i < databaseIds.length - 1) {
        await this.sleep(2000); // 2 second delay between exports
      }
    }

    const totalTime = ((Date.now() - startTime) / 1000).toFixed(2);
    const successCount = results.filter(r => r.success).length;
    const failCount = results.filter(r => !r.success).length;
    
    console.log(`\n📊 Batch Export Summary:`);
    console.log(`Total time: ${totalTime} seconds`);
    console.log(`Successful: ${successCount}`);
    console.log(`Failed: ${failCount}`);

    return results;
  }

  /**
   * List all D1 databases (bonus feature)
   */
  async listDatabases() {
    const endpoint = `/client/v4/accounts/${this.accountId}/d1/database`;
    
    try {
      const response = await this.makeRequest('GET', endpoint);
      
      if (!response.success) {
        throw new Error(`Failed to list databases: ${response.errors?.[0]?.message || 'Unknown error'}`);
      }

      return response.result;
    } catch (error) {
      throw new Error(`Failed to list databases: ${error.message}`);
    }
  }
}

module.exports = D1BackupExporter;
