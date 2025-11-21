#!/bin/bash
# Script to run tests with Java 17 (if available)

cd /workspace/iceberg

# Try to find Java 17
JAVA17_HOME=$(find /usr/lib/jvm -name "*java-17*" -type d 2>/dev/null | head -1)

if [ -z "$JAVA17_HOME" ]; then
    echo "Java 17 not found. Please install Java 17 or use Java 11."
    echo "On Ubuntu: sudo apt-get install openjdk-17-jdk"
    exit 1
fi

export JAVA_HOME="$JAVA17_HOME"
export PATH="$JAVA_HOME/bin:$PATH"

echo "Using Java: $JAVA_HOME"
java -version

echo ""
echo "Running tests with instrumentation..."
echo ""

./gradlew :iceberg-spark:iceberg-spark-3.5_2.12:test \
  --tests "org.apache.iceberg.spark.sql.TestPartitionedWritesToWapBranch" \
  -Diceberg.test.catalog.provider=org.apache.iceberg.spark.openhouse.OpenHouseSparkITestProvider \
  -Diceberg.test.catalog.skip.defaults=true \
  2>&1 | tee /tmp/spark_sql_branch_snapshot_tests.log

echo ""
echo "Test execution complete. Analyzing logs..."
echo ""

cd /workspace
./analyze_catalog_logs.sh /tmp/spark_sql_branch_snapshot_tests.log
