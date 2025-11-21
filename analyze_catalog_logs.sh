#!/bin/bash
# Script to analyze TRACE logs for catalog state debugging

LOG_FILE="${1:-/tmp/spark_sql_branch_snapshot_tests.log}"

if [ ! -f "$LOG_FILE" ]; then
    echo "Error: Log file not found: $LOG_FILE"
    echo "Usage: $0 [log_file_path]"
    exit 1
fi

echo "=========================================="
echo "Catalog State Analysis"
echo "=========================================="
echo ""

echo "1. Checking for catalogImplementation changes:"
echo "-----------------------------------------------"
grep "spark.sql.catalogImplementation" "$LOG_FILE" | tail -20
echo ""

echo "2. Checking catalog registration status:"
echo "-----------------------------------------------"
grep "isRegistered" "$LOG_FILE" | tail -30
echo ""

echo "3. Checking currentCatalog changes:"
echo "-----------------------------------------------"
grep "currentCatalog=" "$LOG_FILE" | tail -20
echo ""

echo "4. Checking v2SessionCatalog type:"
echo "-----------------------------------------------"
grep "v2SessionCatalog=" "$LOG_FILE" | tail -20
echo ""

echo "5. Checking spark_catalog configuration:"
echo "-----------------------------------------------"
grep "spark.sql.catalog.spark_catalog=" "$LOG_FILE" | tail -20
echo ""

echo "6. Checking for REQUIRES_SINGLE_PART_NAMESPACE errors:"
echo "-----------------------------------------------"
grep -A 5 -B 5 "REQUIRES_SINGLE_PART_NAMESPACE" "$LOG_FILE" | head -40
echo ""

echo "7. Timeline of catalog state changes for 'openhouse':"
echo "-----------------------------------------------"
grep -E "(BEFORE registration|AFTER registration|AFTER namespace creation).*openhouse" "$LOG_FILE" | tail -30
echo ""

echo "8. Checking for catalog registration failures:"
echo "-----------------------------------------------"
grep -E "catalog.*isRegistered=false" "$LOG_FILE" | tail -20
echo ""

echo "=========================================="
echo "Summary of Potential Issues:"
echo "=========================================="

# Check for catalogImplementation changes
if grep -q "spark.sql.catalogImplementation" "$LOG_FILE"; then
    CATALOG_IMPL_COUNT=$(grep "spark.sql.catalogImplementation" "$LOG_FILE" | sort -u | wc -l)
    if [ "$CATALOG_IMPL_COUNT" -gt 1 ]; then
        echo "⚠️  WARNING: catalogImplementation has multiple values (may indicate reset)"
    fi
fi

# Check for registration losses
REGISTRATION_LOSSES=$(grep -E "catalog.*isRegistered=false" "$LOG_FILE" | grep -v "BEFORE registration" | wc -l)
if [ "$REGISTRATION_LOSSES" -gt 0 ]; then
    echo "⚠️  WARNING: Found $REGISTRATION_LOSSES instances where catalog registration was lost"
fi

# Check for currentCatalog switches
CURRENT_CATALOG_SWITCHES=$(grep "currentCatalog=" "$LOG_FILE" | grep -v "currentCatalog=openhouse" | grep -v "currentCatalog=null" | wc -l)
if [ "$CURRENT_CATALOG_SWITCHES" -gt 0 ]; then
    echo "⚠️  WARNING: Found $CURRENT_CATALOG_SWITCHES instances where currentCatalog switched away from openhouse"
fi

echo ""
echo "Analysis complete. Review the sections above for issues."
