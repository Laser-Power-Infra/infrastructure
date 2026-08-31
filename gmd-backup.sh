#!/bin/bash

set -u

# ===========================
# PostgreSQL Docker Backup
# ===========================

CONTAINER_NAME="${POSTGRES_CONTAINER:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-asmita}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

LOCAL_BACKUP_DIR="${LOCAL_BACKUP_DIR:-/backups/postgres}"
NETWORK_BACKUP_DIR="${NETWORK_BACKUP_DIR:-/network-backups}"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# ===========================
# Databases
# ===========================

DATABASES=(
    "laser-tender-dashboard-v2"
    "enquiry-quotation"
    "gmd-quotation"
    "quotation-backup"
    "testing"
)

# ===========================
# Prepare directories
# ===========================

mkdir -p "$LOCAL_BACKUP_DIR"
mkdir -p "$NETWORK_BACKUP_DIR"

echo "=========================================="
echo "PostgreSQL Backup Started"
echo "=========================================="
echo "Container : $CONTAINER_NAME"
echo "Timestamp : $TIMESTAMP"
echo ""

FAILED=0

# ===========================
# Backup databases
# ===========================

for DATABASE in "${DATABASES[@]}"; do

    BACKUP_FILE="backup_${DATABASE}_${TIMESTAMP}.sql"

    CONTAINER_BACKUP="/tmp/${BACKUP_FILE}"
    LOCAL_BACKUP="${LOCAL_BACKUP_DIR}/${BACKUP_FILE}"
    NETWORK_BACKUP="${NETWORK_BACKUP_DIR}/${BACKUP_FILE}"

    echo "------------------------------------------"
    echo "Database: $DATABASE"
    echo "------------------------------------------"

    echo "Running pg_dump..."

    docker exec \
        -e PGPASSWORD="$POSTGRES_PASSWORD" \
        "$CONTAINER_NAME" \
        pg_dump \
        -U "$POSTGRES_USER" \
        -d "$DATABASE" \
        -f "$CONTAINER_BACKUP"

    if [ $? -ne 0 ]; then
        echo "ERROR: pg_dump failed for $DATABASE"
        FAILED=1
        continue
    fi

    echo "pg_dump successful."

    # ---------------------------
    # Copy from PostgreSQL
    # ---------------------------

    echo "Copying backup from PostgreSQL container..."

    docker cp \
        "${CONTAINER_NAME}:${CONTAINER_BACKUP}" \
        "$LOCAL_BACKUP"

    if [ $? -ne 0 ]; then
        echo "ERROR: docker cp failed for $DATABASE"
        FAILED=1

        docker exec "$CONTAINER_NAME" rm -f "$CONTAINER_BACKUP"

        continue
    fi

    echo "Local backup:"
    echo "$LOCAL_BACKUP"

    # ---------------------------
    # Remove temporary container file
    # ---------------------------

    docker exec \
        "$CONTAINER_NAME" \
        rm -f "$CONTAINER_BACKUP"

    # ---------------------------
    # Copy to network storage
    # ---------------------------

    echo "Copying backup to network storage..."

    cp -f \
        "$LOCAL_BACKUP" \
        "$NETWORK_BACKUP"

    if [ $? -ne 0 ]; then
        echo "ERROR: Network copy failed for $DATABASE"
        echo "Local backup is available."
        FAILED=1
        continue
    fi

    echo "Network backup:"
    echo "$NETWORK_BACKUP"

    echo "SUCCESS: $DATABASE"
    echo ""

done

# ===========================
# Final result
# ===========================

echo "=========================================="

if [ $FAILED -eq 0 ]; then
    echo "ALL DATABASE BACKUPS COMPLETED"
    echo "=========================================="
    exit 0
else
    echo "SOME DATABASE BACKUPS FAILED"
    echo "=========================================="
    exit 1
fi