#!/bin/bash

# SFTPGo Backup Script for GKE with PostgreSQL
# This script backs up both PostgreSQL database and SFTPGo data to GCS

set -e

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

pg_dump -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        -F c \
        -f "${BACKUP_DIR}/db/sftpgo-db-${TIMESTAMP}.dump"

if [ $? -eq 0 ]; then
    echo "✓ Database backup completed: sftpgo-db-${TIMESTAMP}.dump"
else
    echo "✗ Database backup failed!"
    exit 1
fi

# 2. Backup SFTPGo configuration and data
echo ""
echo "[2/5] Backing up SFTPGo data from Kubernetes..."

# Get the first pod
POD_NAME=$(kubectl get pods -n "${NAMESPACE}" -l app=sftpgo -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD_NAME" ]; then
    echo "✗ No SFTPGo pod found!"
    exit 1
fi

echo "Using pod: ${POD_NAME}"

# Backup SFTPGo data directory
kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -- tar czf - /srv/sftpgo > "${BACKUP_DIR}/data/sftpgo-data-${TIMESTAMP}.tar.gz"
echo "✓ SFTPGo data backed up"

# Backup SFTPGo home directory
kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -- tar czf - /var/lib/sftpgo > "${BACKUP_DIR}/data/sftpgo-home-${TIMESTAMP}.tar.gz"
echo "✓ SFTPGo home directory backed up"

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
  }
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
gsutil cp "sftpgo-backup-${TIMESTAMP}.tar.gz" "${GCS_BUCKET}/backups/${BACKUP_DATE}/sftpgo-backup-${TIMESTAMP}.tar.gz"

if [ $? -eq 0 ]; then
    echo "✓ Backup uploaded successfully"
    echo "  Location: ${GCS_BUCKET}/backups/${BACKUP_DATE}/sftpgo-backup-${TIMESTAMP}.tar.gz"
else
    echo "✗ Upload to GCS failed!"
    exit 1
fi

# 5. Cleanup old backups
echo ""
echo "[5/5] Cleaning up old backups (older than ${RETENTION_DAYS} days)..."

CUTOFF_DATE=$(date -d "${RETENTION_DAYS} days ago" +%Y-%m-%d)
echo "Deleting backups older than: ${CUTOFF_DATE}"

# List and delete old backups
gsutil ls "${GCS_BUCKET}/backups/" | while read -r backup_path; do
    backup_date=$(basename "${backup_path}" | cut -d'/' -f1)
    if [[ "${backup_date}" < "${CUTOFF_DATE}" ]]; then
        echo "Deleting old backup: ${backup_path}"
        gsutil -m rm -r "${backup_path}"
    fi
done

echo "✓ Old backups cleaned up"

# Cleanup local temporary files
rm -rf "${BACKUP_DIR}"
rm -f "/tmp/sftpgo-backup-${TIMESTAMP}.tar.gz"

echo ""
echo "================================================"
echo "Backup completed successfully!"
echo "================================================"
echo "Backup file: sftpgo-backup-${TIMESTAMP}.tar.gz"
echo "Location: ${GCS_BUCKET}/backups/${BACKUP_DATE}/"
echo "================================================"
