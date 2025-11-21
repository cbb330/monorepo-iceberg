# Catalog State Debugging - Analysis Results

## Current Situation

The test execution is blocked by a Java version compatibility issue (Gradle 8.1.1 doesn't support Java 21). However, the debugging instrumentation has been successfully added to the codebase.

## Instrumentation Status

✅ **All debugging instrumentation has been added:**

1. `TestBaseWithCatalog#before()` - Logs catalog state at 3 phases
2. `UnpartitionedWritesTestBase#createTables()` - Logs state before CREATE TABLE
3. `PartitionedWritesTestBase#createTables()` - Logs state before CREATE TABLE  
4. `TestBase#sql()` - Enhanced query execution logging

## Expected Log Output Format

When tests run successfully, you should see logs like this:

### Phase 1: Before Catalog Registration
```
TRACE TestBaseWithCatalog#before catalogName=openhouse implementation=org.apache.iceberg.spark.SparkCatalog config={catalog-impl=com.linkedin.openhouse.spark.OpenHouseCatalog, uri=..., cluster=local-cluster}
TRACE TestBaseWithCatalog#before [BEFORE registration] spark.sql.catalogImplementation=in-memory
TRACE TestBaseWithCatalog#before [BEFORE registration] currentCatalog=spark_catalog currentNamespace=[default]
TRACE TestBaseWithCatalog#before [BEFORE registration] catalog 'openhouse' isRegistered=false
TRACE TestBaseWithCatalog#before [BEFORE registration] spark.sql.catalog.spark_catalog=not set
```

### Phase 2: After Catalog Registration
```
TRACE TestBaseWithCatalog#before spark.sql.catalog.openhouse=org.apache.iceberg.spark.SparkCatalog
TRACE TestBaseWithCatalog#before spark.sql.catalog.openhouse.catalog-impl=com.linkedin.openhouse.spark.OpenHouseCatalog
TRACE TestBaseWithCatalog#before [AFTER registration] spark.sql.catalogImplementation=in-memory
TRACE TestBaseWithCatalog#before [AFTER registration] currentCatalog=spark_catalog currentNamespace=[default]
TRACE TestBaseWithCatalog#before [AFTER registration] catalog 'openhouse' isRegistered=true
TRACE TestBaseWithCatalog#before [AFTER registration] catalog 'openhouse' instance=org.apache.iceberg.spark.SparkCatalog
TRACE TestBaseWithCatalog#before [AFTER registration] v2SessionCatalog=org.apache.spark.sql.connector.catalog.InMemoryCatalog
TRACE TestBaseWithCatalog#before [AFTER registration] spark.sql.catalog.spark_catalog=not set
```

### Phase 3: Before CREATE TABLE
```
TRACE createTables start tableName=openhouse.default.table
TRACE createTables#debugCatalogStateBeforeCreateTable tableName=openhouse.default.table
TRACE createTables#debugCatalogStateBeforeCreateTable expectedCatalog=openhouse
TRACE createTables#debugCatalogStateBeforeCreateTable catalog 'openhouse' isRegistered=true
TRACE createTables#debugCatalogStateBeforeCreateTable currentCatalog=spark_catalog
TRACE createTables#debugCatalogStateBeforeCreateTable spark.sql.catalogImplementation=in-memory
```

### Phase 4: Query Execution
```
TRACE TestBase#sql query=CREATE TABLE openhouse.default.table (id bigint, data string) USING iceberg PARTITIONED BY (truncate(id, 3))
TRACE TestBase#sql extracted catalog from query: openhouse
TRACE TestBase#sql catalog 'openhouse' isRegistered=true
TRACE TestBase#sql currentCatalog=spark_catalog
TRACE TestBase#sql spark.sql.catalogImplementation=in-memory
TRACE TestBase#sql spark.sql.catalog.spark_catalog=not set
```

## Problem Indicators to Look For

### 🔴 Critical Issue: Catalog Registration Lost

**Pattern:**
```
TRACE TestBaseWithCatalog#before [AFTER registration] catalog 'openhouse' isRegistered=true
... (test suite 1 passes) ...
TRACE TestBaseWithCatalog#before [BEFORE registration] catalog 'openhouse' isRegistered=false  ⚠️
TRACE TestBaseWithCatalog#before [AFTER registration] catalog 'openhouse' isRegistered=true
TRACE createTables#debugCatalogStateBeforeCreateTable catalog 'openhouse' isRegistered=false  ⚠️
```

**What this means:** The catalog registration is being lost between test suites or between registration and CREATE TABLE execution.

**Root cause likely:** CatalogManager is being reset or Spark session is being recreated.

### 🔴 Critical Issue: catalogImplementation Changed

**Pattern:**
```
TRACE TestBaseWithCatalog#before [AFTER registration] spark.sql.catalogImplementation=in-memory
... (test suite 1 passes) ...
TRACE TestBaseWithCatalog#before [BEFORE registration] spark.sql.catalogImplementation=hive  ⚠️
```

**What this means:** Spark's catalog implementation is being reset, causing ResolveSessionCatalog to use a different resolution path.

**Root cause likely:** Configuration is being reset between test suites.

### 🔴 Critical Issue: currentCatalog Switched

**Pattern:**
```
TRACE TestBaseWithCatalog#before [AFTER registration] currentCatalog=openhouse
TRACE createTables#debugCatalogStateBeforeCreateTable currentCatalog=spark_catalog  ⚠️
```

**What this means:** The current catalog switched from openhouse to spark_catalog, causing multi-part identifiers to be resolved against spark_catalog instead.

**Root cause likely:** USE CATALOG statement or catalog manager reset.

### 🟡 Warning: V2 Session Catalog Type Changed

**Pattern:**
```
TRACE TestBaseWithCatalog#before [AFTER registration] v2SessionCatalog=org.apache.spark.sql.connector.catalog.InMemoryCatalog
... (test suite 1 passes) ...
TRACE TestBaseWithCatalog#before [BEFORE registration] v2SessionCatalog=org.apache.iceberg.spark.SparkSessionCatalog  ⚠️
```

**What this means:** The session catalog type changed, which may reset catalog registrations.

## Analysis Script Usage

Once you have logs from a successful test run, use:

```bash
./analyze_catalog_logs.sh /path/to/spark_sql_branch_snapshot_tests.log
```

The script will:
1. Show catalogImplementation changes
2. Show catalog registration status
3. Show currentCatalog changes
4. Show v2SessionCatalog type changes
5. Show spark_catalog configuration
6. Show REQUIRES_SINGLE_PART_NAMESPACE errors with context
7. Show timeline of catalog state changes
8. Provide a summary of potential issues

## Next Steps

1. **Resolve Java Version Issue:**
   - Option A: Install Java 17 or Java 11
   - Option B: Upgrade Gradle to 8.5+ which supports Java 21
   - Option C: Use a different build environment

2. **Run Tests with Instrumentation:**
   ```bash
   cd /workspace/iceberg
   ./gradlew :iceberg-spark:iceberg-spark-3.5_2.12:test \
     --tests "org.apache.iceberg.spark.sql.TestPartitionedWritesToWapBranch" \
     -Diceberg.test.catalog.provider=org.apache.iceberg.spark.openhouse.OpenHouseSparkITestProvider \
     -Diceberg.test.catalog.skip.defaults=true \
     2>&1 | tee /tmp/spark_sql_branch_snapshot_tests.log
   ```

3. **Analyze the Logs:**
   ```bash
   ./analyze_catalog_logs.sh /tmp/spark_sql_branch_snapshot_tests.log
   ```

4. **Review Key Sections:**
   - Look for `isRegistered=false` after it was `true`
   - Look for `catalogImplementation` changes
   - Look for `currentCatalog` switching to `spark_catalog`
   - Look for the exact state when `REQUIRES_SINGLE_PART_NAMESPACE` occurs

## Code Locations

All instrumentation is in place and ready:

- `iceberg/spark/v3.5/spark/src/test/java/org/apache/iceberg/spark/TestBaseWithCatalog.java`
- `iceberg/spark/v3.5/spark/src/test/java/org/apache/iceberg/spark/TestBase.java`
- `iceberg/spark/v3.5/spark/src/test/java/org/apache/iceberg/spark/sql/UnpartitionedWritesTestBase.java`
- `iceberg/spark/v3.5/spark/src/test/java/org/apache/iceberg/spark/sql/PartitionedWritesTestBase.java`

## Expected Findings

Based on the user's description, we expect to find:

1. **Catalog registration is intact** - `isRegistered=true` after registration
2. **But registration is lost** - `isRegistered=false` when CREATE TABLE executes
3. **ResolveSessionCatalog rewrites** - Multi-part identifier gets rewritten to spark_catalog
4. **Error occurs** - `REQUIRES_SINGLE_PART_NAMESPACE` because spark_catalog requires single-part namespace

The instrumentation will show **exactly when and why** the registration is lost, which will point to the root cause.
