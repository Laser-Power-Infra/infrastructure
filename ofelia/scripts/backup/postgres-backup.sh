#!/bin/bash

set -u

# ===========================
# PostgreSQL Docker Backup
# ===========================

POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

LOCAL_BACKUP_DIR="${LOCAL_BACKUP_DIR:-/backups/postgres}"
NETWORK_BACKUP_DIR="${NETWORK_BACKUP_DIR:-/network-backups}"

TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"

# ===========================
# Databases
# ===========================

DATABASES=(
    "laser-tender-dashboard-v2"
    "enquiry-quotation"
    "gmd-quotation"
    "DeliveryDB"
    "quotation-backup"
    "ceebuild-items"
    "tender-executive-dashboard-production"
    "gmd_gem_ids"
    # "test"
    # "osevents"
)

# ===========================
# Validate configuration
# ===========================

if [ -z "${POSTGRES_USER:-}" ]; then
    echo "ERROR: POSTGRES_USER is not set."
    exit 1
fi

if [ -z "${POSTGRES_PASSWORD:-}" ]; then
    echo "ERROR: POSTGRES_PASSWORD is not set."
    exit 1
fi

# ===========================
# Check directories
# ===========================

if [ ! -d "$LOCAL_BACKUP_DIR" ]; then
    echo "ERROR: Local backup directory does not exist:"
    echo "$LOCAL_BACKUP_DIR"
    exit 1
fi

if [ ! -d "$NETWORK_BACKUP_DIR" ]; then
    echo "ERROR: Network backup directory does not exist:"
    echo "$NETWORK_BACKUP_DIR"
    exit 1
fi

echo "=========================================="
echo "PostgreSQL Backup Started"
echo "=========================================="
echo "Host      : $POSTGRES_HOST"
echo "Port      : $POSTGRES_PORT"
echo "User      : $POSTGRES_USER"
echo "Timestamp : $TIMESTAMP"
echo ""

FAILED=0

# ===========================
# Backup databases
# ===========================

for DATABASE in "${DATABASES[@]}"; do

    BACKUP_FILE="backup_${DATABASE}_${TIMESTAMP}.sql"

    LOCAL_BACKUP="${LOCAL_BACKUP_DIR}/${BACKUP_FILE}"
    NETWORK_BACKUP="${NETWORK_BACKUP_DIR}/${BACKUP_FILE}"

    echo "------------------------------------------"
    echo "Database: $DATABASE"
    echo "------------------------------------------"

    # ---------------------------
    # Run pg_dump
    # ---------------------------

    echo "Running pg_dump..."

    if PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U "$POSTGRES_USER" \
        -d "$DATABASE" \
        -f "$LOCAL_BACKUP"; then

        echo "pg_dump successful."

    else

        echo "ERROR: pg_dump failed for $DATABASE"

        # Remove partial dump if one was created
        rm -f "$LOCAL_BACKUP"

        FAILED=1
        continue
    fi

    echo "Local backup created:"
    echo "$LOCAL_BACKUP"

    # ---------------------------
    # Copy to network storage
    # ---------------------------

    echo "Copying backup to network storage..."

    if cp -f "$LOCAL_BACKUP" "$NETWORK_BACKUP"; then

        echo "Network backup created:"
        echo "$NETWORK_BACKUP"

    else

        echo "ERROR: Network copy failed for $DATABASE"
        echo "Local backup is being retained:"
        echo "$LOCAL_BACKUP"

        FAILED=1
        continue
    fi

    # ---------------------------
    # Delete local backup
    # only after successful
    # network copy
    # ---------------------------

    # Disabled temporarily to inspect local backups
    # echo "Removing local backup..."
    #
    # if rm -f "$LOCAL_BACKUP"; then
    #
    #     echo "Local backup deleted."
    #
    # else
    #
    #     echo "WARNING: Network backup succeeded,"
    #     echo "but local backup could not be deleted."
    #     echo "Local backup:"
    #     echo "$LOCAL_BACKUP"
    #
    #     FAILED=1
    #     continue
    # fi

    echo "SUCCESS: $DATABASE"
    echo ""

done

# ===========================
# Final result
# ===========================

echo "=========================================="

if [ "$FAILED" -eq 0 ]; then

    echo "ALL DATABASE BACKUPS COMPLETED"
    echo "=========================================="
    exit 0

else

    echo "SOME DATABASE BACKUPS FAILED"
    echo "=========================================="
    exit 1

fi
