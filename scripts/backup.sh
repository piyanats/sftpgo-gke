#!/bin/bash

# SFTPGo Backup Script for GKE with PostgreSQL
# This script backs up both PostgreSQL database and SFTPGo data to GCS

set -e

# Cleanup function
cleanup() {
    if [ -n "${BACKUP_DIR}" ] && [ -d "${BACKUP_DIR}" ]; then
        echo "Cleaning up temporary files..."
        rm -rf "${BACKUP_DIR}" 2>/dev/null || true
        rm -f "/tmp/sftpgo-backup-${TIMESTAMP}.tar.gz" 2>/dev/null || true
    fi
}

# Set trap for cleanup on exit or error
trap cleanup EXIT ERR INT TERM

# Configuration
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DATE=$(date +%Y-%m-%d)
NAMESPACE="${NAMESPACE:-sftpgo}"
GCS_BUCKET="${GCS_BUCKET:-gs://sftpgo-backups}"
BACKUP_DIR="/tmp/sftpgo-backup-${TIMESTAMP}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# PostgreSQL configuration from secrets
POSTGRES_HOST="${POSTGRES_HOST}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-sftpgo}"
POSTGRES_USER="${POSTGRES_USER}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

# Validate required environment variables
echo "================================================"
echo "Validating environment..."
echo "================================================"

required_vars=(
    "POSTGRES_HOST:PostgreSQL host"
    "POSTGRES_USER:PostgreSQL user"
    "POSTGRES_PASSWORD:PostgreSQL password"
    "GCS_BUCKET:GCS bucket"
)

validation_failed=0
for var_info in "${required_vars[@]}"; do
    var_name="${var_info%%:*}"
    var_desc="${var_info##*:}"
    if [ -z "${!var_name}" ]; then
        echo "✗ Error: ${var_desc} (${var_name}) is not set"
        validation_failed=1
    else
        echo "✓ ${var_desc} is set"
    fi
done

if [ $validation_failed -eq 1 ]; then
    echo "✗ Validation failed. Please set all required environment variables."
    exit 1
fi

# Check for required commands
echo ""
echo "Checking required commands..."
required_commands=("kubectl" "pg_dump" "gsutil" "tar" "date")
for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "✗ Error: Required command '$cmd' not found"
        exit 1
    fi
    echo "✓ $cmd is available"
done

echo ""
echo "================================================"
echo "SFTPGo Backup Process Started"
echo "================================================"
echo "Timestamp: ${TIMESTAMP}"
echo "Namespace: ${NAMESPACE}"
echo "GCS Bucket: ${GCS_BUCKET}"
echo "Retention: ${RETENTION_DAYS} days"
echo "================================================"

# Create backup directory
mkdir -p "${BACKUP_DIR}/db"
mkdir -p "${BACKUP_DIR}/data"

# 1. Backup PostgreSQL Database
echo ""
echo "[1/5] Backing up PostgreSQL database..."
export PGPASSWORD="${POSTGRES_PASSWORD}"

if pg_dump -h "${POSTGRES_HOST}" \
           -p "${POSTGRES_PORT}" \
           -U "${POSTGRES_USER}" \
           -d "${POSTGRES_DB}" \
           -F c \
           -f "${BACKUP_DIR}/db/sftpgo-db-${TIMESTAMP}.dump"; then
    echo "✓ Database backup completed: sftpgo-db-${TIMESTAMP}.dump"
else
    echo "✗ Database backup failed!"
    exit 1
fi

# 2. Backup SFTPGo configuration and data
echo ""
echo "[2/5] Backing up SFTPGo data from Kubernetes..."

# Get the first pod
POD_NAME=$(kubectl get pods -n "${NAMESPACE}" -l app=sftpgo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    echo "✗ No SFTPGo pod found!"
    exit 1
fi

echo "Using pod: ${POD_NAME}"

# Backup SFTPGo data directory
if kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -- tar czf - /srv/sftpgo > "${BACKUP_DIR}/data/sftpgo-data-${TIMESTAMP}.tar.gz" 2>/dev/null; then
    echo "✓ SFTPGo data backed up"
else
    echo "✗ SFTPGo data backup failed!"
    exit 1
fi

# Backup SFTPGo home directory
if kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -- tar czf - /var/lib/sftpgo > "${BACKUP_DIR}/data/sftpgo-home-${TIMESTAMP}.tar.gz" 2>/dev/null; then
    echo "✓ SFTPGo home directory backed up"
else
    echo "✗ SFTPGo home backup failed!"
    exit 1
fi

# 3. Create metadata file
echo ""
echo "[3/5] Creating backup metadata..."
cat > "${BACKUP_DIR}/metadata.json" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "date": "${BACKUP_DATE}",
  "namespace": "${NAMESPACE}",
  "database": {
    "host": "${POSTGRES_HOST}",
    "port": "${POSTGRES_PORT}",
    "database": "${POSTGRES_DB}",
    "user": "${POSTGRES_USER}"
  },
  "files": {
    "database": "db/sftpgo-db-${TIMESTAMP}.dump",
    "data": "data/sftpgo-data-${TIMESTAMP}.tar.gz",
    "home": "data/sftpgo-home-${TIMESTAMP}.tar.gz"
  },
  "version": "1.0",
  "script_version": "2.0"
}
EOF
echo "✓ Metadata file created"

# 4. Upload to GCS
echo ""
echo "[4/5] Uploading backup to GCS..."

# Create tar archive of entire backup
cd /tmp
tar czf "sftpgo-backup-${TIMESTAMP}.tar.gz" "sftpgo-backup-${TIMESTAMP}"

# Upload to GCS
if gsutil cp "sftpgo-backup-${TIMESTAMP}.tar.gz" "${GCS_BUCKET}/backups/${BACKUP_DATE}/sftpgo-backup-${TIMESTAMP}.tar.gz"; then
    echo "✓ Backup uploaded successfully"
    echo "  Location: ${GCS_BUCKET}/backups/${BACKUP_DATE}/sftpgo-backup-${TIMESTAMP}.tar.gz"
else
    echo "✗ Upload to GCS failed!"
    exit 1
fi

# 5. Cleanup old backups
echo ""
echo "[5/5] Cleaning up old backups (older than ${RETENTION_DAYS} days)..."

# Calculate cutoff timestamp
CUTOFF_TIMESTAMP=$(date -d "${RETENTION_DAYS} days ago" +%s 2>/dev/null || date -v-${RETENTION_DAYS}d +%s 2>/dev/null)
CUTOFF_DATE=$(date -d "${RETENTION_DAYS} days ago" +%Y-%m-%d 2>/dev/null || date -v-${RETENTION_DAYS}d +%Y-%m-%d 2>/dev/null)
echo "Deleting backups older than: ${CUTOFF_DATE}"

# List and delete old backups
gsutil ls "${GCS_BUCKET}/backups/" 2>/dev/null | while read -r backup_path; do
    backup_date=$(basename "${backup_path}" | sed 's:/$::')

    # Convert backup date to timestamp for proper comparison
    backup_timestamp=$(date -d "$backup_date" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$backup_date" +%s 2>/dev/null || echo "0")

    if [ "$backup_timestamp" -ne 0 ] && [ "$backup_timestamp" -lt "$CUTOFF_TIMESTAMP" ]; then
        echo "Deleting old backup: ${backup_path}"
        gsutil -m rm -r "${backup_path}" 2>/dev/null || echo "  Warning: Failed to delete ${backup_path}"
    fi
done

echo "✓ Old backups cleaned up"

# Note: cleanup() will be called automatically via trap

echo ""
echo "================================================"
echo "Backup completed successfully!"
echo "================================================"
echo "Backup file: sftpgo-backup-${TIMESTAMP}.tar.gz"
echo "Location: ${GCS_BUCKET}/backups/${BACKUP_DATE}/"
echo "================================================"
