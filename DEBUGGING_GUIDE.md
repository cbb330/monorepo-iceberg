# Catalog State Debugging Guide

## Overview

This guide explains the debugging instrumentation added to track why `ResolveSessionCatalog` rewrites multi-part identifiers (`openhouse.default.table`) to `spark_catalog` after multiple test suites run.

## Instrumentation Added

### 1. TestBaseWithCatalog#before() - Catalog Manager State Tracking

The `before()` method now logs catalog manager state at three critical points:

- **BEFORE registration**: State before catalog is registered
- **AFTER registration**: State immediately after `spark.conf().set()` calls
- **AFTER namespace creation**: State after `CREATE NAMESPACE` executes

Each phase logs:
- `spark.sql.catalogImplementation` value
- Current catalog name and namespace
- Whether the catalog is registered (`isCatalogRegistered()`)
- Catalog instance class name
- V2 session catalog type
- `spark.sql.catalog.spark_catalog` configuration

### 2. createTables() Methods - Pre-CREATE TABLE State

Both `UnpartitionedWritesTestBase` and `PartitionedWritesTestBase` now log catalog state right before executing `CREATE TABLE`:

- Expected catalog name (extracted from `tableName`)
- Whether expected catalog is registered
- Current catalog
- `spark.sql.catalogImplementation` value

### 3. TestBase#sql() - Query Execution Tracking

Enhanced logging for queries involving `openhouse` or `CREATE TABLE`:

- Extracts catalog name from multi-part identifiers
- Checks catalog registration before query execution
- Logs detailed error context on failure

## What to Look For in Logs

### 🔍 Key Indicators of the Problem

#### 1. `spark.sql.catalogImplementation` Changes

**Look for:**
```
TRACE TestBaseWithCatalog#before [BEFORE registration] spark.sql.catalogImplementation=hive
TRACE TestBaseWithCatalog#before [AFTER registration] spark.sql.catalogImplementation=in-memory
```

**What it means:** If `catalogImplementation` changes between test suites, Spark may be resetting the session catalog type, causing `ResolveSessionCatalog` to use the wrong catalog.

#### 2. Catalog Registration Status

**Look for:**
```
TRACE TestBaseWithCatalog#before [AFTER registration] catalog 'openhouse' isRegistered=true
...
TRACE createTables#debugCatalogStateBeforeCreateTable catalog 'openhouse' isRegistered=false
```

**What it means:** If `isRegistered` becomes `false` after it was `true`, the catalog registration is being lost between test suites. This is a **smoking gun** for the issue.

#### 3. Current Catalog Switching

**Look for:**
```
TRACE TestBaseWithCatalog#before [AFTER registration] currentCatalog=openhouse
...
TRACE createTables#debugCatalogStateBeforeCreateTable currentCatalog=spark_catalog
```

**What it means:** If `currentCatalog` switches from `openhouse` to `spark_catalog` unexpectedly, Spark's catalog manager is resetting to the default session catalog.

#### 4. V2 Session Catalog Type Changes

**Look for:**
```
TRACE TestBaseWithCatalog#before [BEFORE registration] v2SessionCatalog=org.apache.spark.sql.connector.catalog.InMemoryCatalog
TRACE TestBaseWithCatalog#before [AFTER registration] v2SessionCatalog=org.apache.iceberg.spark.SparkSessionCatalog
```

**What it means:** If the session catalog type changes between suites, it indicates Spark is reinitializing the session catalog, which may reset catalog registrations.

#### 5. spark_catalog Configuration

**Look for:**
```
TRACE TestBaseWithCatalog#before [AFTER registration] spark.sql.catalog.spark_catalog=not set
...
TRACE createTables#debugCatalogStateBeforeCreateTable spark.sql.catalog.spark_catalog=org.apache.iceberg.spark.SparkSessionCatalog
```

**What it means:** If `spark.sql.catalog.spark_catalog` is being set or changed, it may be overriding the multi-part identifier resolution.

## Expected Log Sequence (Working Case)

```
TRACE TestBaseWithCatalog#before catalogName=openhouse ...
TRACE TestBaseWithCatalog#before [BEFORE registration] spark.sql.catalogImplementation=in-memory
TRACE TestBaseWithCatalog#before [BEFORE registration] currentCatalog=spark_catalog
TRACE TestBaseWithCatalog#before [BEFORE registration] catalog 'openhouse' isRegistered=false
TRACE TestBaseWithCatalog#before spark.sql.catalog.openhouse=org.apache.iceberg.spark.SparkCatalog
TRACE TestBaseWithCatalog#before [AFTER registration] catalog 'openhouse' isRegistered=true
TRACE TestBaseWithCatalog#before [AFTER registration] catalog 'openhouse' instance=org.apache.iceberg.spark.SparkCatalog
TRACE createTables start tableName=openhouse.default.table
TRACE createTables#debugCatalogStateBeforeCreateTable catalog 'openhouse' isRegistered=true
TRACE TestBase#sql query=CREATE TABLE openhouse.default.table ...
TRACE TestBase#sql catalog 'openhouse' isRegistered=true
```

## Problematic Log Sequence (Failure Case)

```
TRACE TestBaseWithCatalog#before catalogName=openhouse ...
TRACE TestBaseWithCatalog#before [AFTER registration] catalog 'openhouse' isRegistered=true
... (first test suite passes) ...
TRACE TestBaseWithCatalog#before catalogName=openhouse ...
TRACE TestBaseWithCatalog#before [BEFORE registration] spark.sql.catalogImplementation=hive  ⚠️ CHANGED
TRACE TestBaseWithCatalog#before [BEFORE registration] catalog 'openhouse' isRegistered=false  ⚠️ LOST
TRACE TestBaseWithCatalog#before [AFTER registration] catalog 'openhouse' isRegistered=true
TRACE createTables#debugCatalogStateBeforeCreateTable catalog 'openhouse' isRegistered=false  ⚠️ LOST AGAIN
TRACE TestBase#sql ERROR: REQUIRES_SINGLE_PART_NAMESPACE
```

## Root Cause Hypotheses

Based on the instrumentation, the issue is likely one of:

1. **Catalog Manager Reset**: Spark's `CatalogManager` is being reset between test suites, losing catalog registrations
2. **Session Catalog Reinitialization**: The V2 session catalog is being recreated, resetting to default state
3. **Configuration Override**: `spark.sql.catalogImplementation` is being changed, causing Spark to use a different catalog resolution path
4. **Cached State**: Spark is caching the session catalog state and not picking up new catalog registrations

## Next Steps After Reviewing Logs

1. **If `catalogImplementation` changes**: Investigate what's setting it. Check for:
   - Test cleanup code that resets Spark configuration
   - `@AfterEach` or `@AfterAll` methods that modify Spark config
   - Shared Spark session being reused with stale configuration

2. **If `isRegistered` becomes false**: Check for:
   - `CatalogManager.reset()` calls
   - Spark session being recreated
   - Configuration being cleared between test suites

3. **If `currentCatalog` switches**: Investigate:
   - `USE CATALOG` statements
   - Catalog manager state being reset
   - Session catalog being restored to default

4. **If session catalog type changes**: Look for:
   - Spark session provider being called multiple times
   - Session being recreated instead of reused
   - Configuration changes that trigger session catalog reinitialization

## Running Tests with Instrumentation

To capture the full TRACE logs:

```bash
cd /workspace/iceberg
./gradlew :iceberg-spark:iceberg-spark-3.5_2.12:test \
  --tests "org.apache.iceberg.spark.sql.TestPartitionedWritesToWapBranch" \
  -Diceberg.test.catalog.provider=org.apache.iceberg.spark.openhouse.OpenHouseSparkITestProvider \
  -Diceberg.test.catalog.skip.defaults=true \
  2>&1 | tee /tmp/spark_sql_branch_snapshot_tests.log
```

Then analyze the log:
```bash
grep -E "TRACE.*\[(BEFORE|AFTER|AFTER namespace)|catalog.*isRegistered|currentCatalog|spark.sql.catalogImplementation" /tmp/spark_sql_branch_snapshot_tests.log
```

## Files Modified

1. `iceberg/spark/v3.5/spark/src/test/java/org/apache/iceberg/spark/TestBaseWithCatalog.java`
   - Added `debugCatalogManagerState()` method
   - Added instrumentation at three phases in `before()`

2. `iceberg/spark/v3.5/spark/src/test/java/org/apache/iceberg/spark/TestBase.java`
   - Enhanced `sql()` method with catalog state logging
   - Added error context logging

3. `iceberg/spark/v3.5/spark/src/test/java/org/apache/iceberg/spark/sql/UnpartitionedWritesTestBase.java`
   - Added `debugCatalogStateBeforeCreateTable()` method

4. `iceberg/spark/v3.5/spark/src/test/java/org/apache/iceberg/spark/sql/PartitionedWritesTestBase.java`
   - Added `debugCatalogStateBeforeCreateTable()` method
