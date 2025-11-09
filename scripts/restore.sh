#!/bin/bash

# SFTPGo Restore Script for GKE with PostgreSQL
# This script restores both PostgreSQL database and SFTPGo data from GCS

set -e

# Check if backup file is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <backup-file-or-gcs-path> [--db-only] [--data-only]"
    echo ""
    echo "Examples:"
    echo "  $0 gs://sftpgo-backups/backups/2024-01-15/sftpgo-backup-20240115_120000.tar.gz"
    echo "  $0 /path/to/sftpgo-backup-20240115_120000.tar.gz"
    echo "  $0 gs://sftpgo-backups/backups/2024-01-15/sftpgo-backup-20240115_120000.tar.gz --db-only"
    echo ""
    exit 1
fi

BACKUP_SOURCE="$1"
RESTORE_DB=true
RESTORE_DATA=true

# Parse arguments
shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --db-only)
            RESTORE_DATA=false
            shift
            ;;
        --data-only)
            RESTORE_DB=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Configuration
NAMESPACE="${NAMESPACE:-sftpgo}"
RESTORE_DIR="/tmp/sftpgo-restore-$(date +%Y%m%d_%H%M%S)"

# PostgreSQL configuration from environment or secrets
POSTGRES_HOST="${POSTGRES_HOST}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-sftpgo}"
POSTGRES_USER="${POSTGRES_USER}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

echo "================================================"
echo "SFTPGo Restore Process Started"
echo "================================================"
echo "Backup Source: ${BACKUP_SOURCE}"
echo "Namespace: ${NAMESPACE}"
echo "Restore Database: ${RESTORE_DB}"
echo "Restore Data: ${RESTORE_DATA}"
echo "================================================"

# Create restore directory
mkdir -p "${RESTORE_DIR}"

# Download backup from GCS if it's a GCS path
if [[ "${BACKUP_SOURCE}" == gs://* ]]; then
    echo ""
    echo "[1/4] Downloading backup from GCS..."
    BACKUP_FILE="${RESTORE_DIR}/$(basename ${BACKUP_SOURCE})"
    gsutil cp "${BACKUP_SOURCE}" "${BACKUP_FILE}"
    echo "✓ Backup downloaded"
else
    BACKUP_FILE="${BACKUP_SOURCE}"
    if [ ! -f "${BACKUP_FILE}" ]; then
        echo "✗ Backup file not found: ${BACKUP_FILE}"
        exit 1
    fi
fi

# Extract backup
echo ""
echo "[2/4] Extracting backup archive..."
tar xzf "${BACKUP_FILE}" -C "${RESTORE_DIR}"

# Find the extracted directory
BACKUP_DIR=$(find "${RESTORE_DIR}" -maxdepth 1 -type d -name "sftpgo-backup-*" | head -n 1)

if [ -z "${BACKUP_DIR}" ]; then
    echo "✗ Could not find backup directory in archive"
    exit 1
fi

echo "✓ Backup extracted to: ${BACKUP_DIR}"

# Read metadata
if [ -f "${BACKUP_DIR}/metadata.json" ]; then
    echo ""
    echo "Backup Information:"
    cat "${BACKUP_DIR}/metadata.json"
    echo ""
fi

# Restore PostgreSQL Database
if [ "${RESTORE_DB}" = true ]; then
    echo ""
    echo "[3/4] Restoring PostgreSQL database..."

    # Find the database dump file
    DB_DUMP=$(find "${BACKUP_DIR}/db" -name "*.dump" | head -n 1)

    if [ -z "${DB_DUMP}" ]; then
        echo "✗ Database dump file not found!"
        exit 1
    fi

    echo "Found database dump: $(basename ${DB_DUMP})"
    echo "⚠ WARNING: This will replace the existing database!"
    echo "Database: ${POSTGRES_DB} on ${POSTGRES_HOST}:${POSTGRES_PORT}"

    read -p "Continue with database restore? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Database restore cancelled."
        RESTORE_DB=false
    else
        export PGPASSWORD="${POSTGRES_PASSWORD}"

        # Drop existing connections
        echo "Terminating existing connections..."
        psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres -c \
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${POSTGRES_DB}' AND pid <> pg_backend_pid();"

        # Drop and recreate database
        echo "Recreating database..."
        psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};"
        psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d postgres -c "CREATE DATABASE ${POSTGRES_DB};"

        # Restore database
        echo "Restoring database..."
        pg_restore -h "${POSTGRES_HOST}" \
                   -p "${POSTGRES_PORT}" \
                   -U "${POSTGRES_USER}" \
                   -d "${POSTGRES_DB}" \
                   -v \
                   "${DB_DUMP}"

        if [ $? -eq 0 ]; then
            echo "✓ Database restored successfully"
        else
            echo "✗ Database restore failed!"
            exit 1
        fi
    fi
fi

# Restore SFTPGo Data
if [ "${RESTORE_DATA}" = true ]; then
    echo ""
    echo "[4/4] Restoring SFTPGo data..."

    # Get the first pod
    POD_NAME=$(kubectl get pods -n "${NAMESPACE}" -l app=sftpgo -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$POD_NAME" ]; then
        echo "✗ No SFTPGo pod found!"
        exit 1
    fi

    echo "Using pod: ${POD_NAME}"
    echo "⚠ WARNING: This will replace existing SFTPGo data!"

    read -p "Continue with data restore? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Data restore cancelled."
    else
        # Restore SFTPGo data directory
        DATA_ARCHIVE=$(find "${BACKUP_DIR}/data" -name "sftpgo-data-*.tar.gz" | head -n 1)
        if [ -n "${DATA_ARCHIVE}" ]; then
            echo "Restoring SFTPGo data directory..."
            kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -- rm -rf /srv/sftpgo/*
            cat "${DATA_ARCHIVE}" | kubectl exec -i -n "${NAMESPACE}" "${POD_NAME}" -- tar xzf - -C /
            echo "✓ SFTPGo data restored"
        fi

        # Restore SFTPGo home directory
        HOME_ARCHIVE=$(find "${BACKUP_DIR}/data" -name "sftpgo-home-*.tar.gz" | head -n 1)
        if [ -n "${HOME_ARCHIVE}" ]; then
            echo "Restoring SFTPGo home directory..."
            kubectl exec -n "${NAMESPACE}" "${POD_NAME}" -- rm -rf /var/lib/sftpgo/*
            cat "${HOME_ARCHIVE}" | kubectl exec -i -n "${NAMESPACE}" "${POD_NAME}" -- tar xzf - -C /
            echo "✓ SFTPGo home directory restored"
        fi

        # Restart SFTPGo pods to apply changes
        echo ""
        echo "Restarting SFTPGo pods..."
        kubectl rollout restart deployment/sftpgo -n "${NAMESPACE}"
        kubectl rollout status deployment/sftpgo -n "${NAMESPACE}" --timeout=5m
        echo "✓ SFTPGo pods restarted"
    fi
fi

# Cleanup
echo ""
echo "Cleaning up temporary files..."
rm -rf "${RESTORE_DIR}"

echo ""
echo "================================================"
echo "Restore process completed!"
echo "================================================"
