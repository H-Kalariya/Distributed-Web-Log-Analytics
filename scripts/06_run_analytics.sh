#!/usr/bin/env bash
# =============================================================================
# 06_run_analytics.sh  –  Run on MASTER only
#
# Usage:  ./06_run_analytics.sh [num_executors]
#   num_executors  number of Spark executors  (default: 2)
#
# Submits the PySpark job to YARN in client mode.
# While running, open http://master:8088 to watch executors on both workers.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster.env"
source ~/.bashrc 2>/dev/null || true

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }

NUM_EXECUTORS="${1:-2}"
EXECUTOR_MEMORY="1g"
EXECUTOR_CORES="1"
DRIVER_MEMORY="1g"

APP_SCRIPT="${SCRIPT_DIR}/../src/log_analytics.py"
INPUT_PATH="hdfs:///logs/raw"
OUTPUT_PATH="hdfs:///logs/output"
PARQUET_PATH="hdfs:///logs/parquet"

info "Submitting Spark job with ${NUM_EXECUTORS} executor(s) ..."
info "  Input:   ${INPUT_PATH}"
info "  Output:  ${OUTPUT_PATH}"
info "  Parquet: ${PARQUET_PATH}"
echo ""
info "📺 Watch progress at: http://${MASTER_IP}:8088"
echo ""

START_TIME=$(date +%s)

spark-submit \
    --master yarn \
    --deploy-mode client \
    --num-executors "${NUM_EXECUTORS}" \
    --executor-memory "${EXECUTOR_MEMORY}" \
    --executor-cores "${EXECUTOR_CORES}" \
    --driver-memory "${DRIVER_MEMORY}" \
    --conf spark.sql.legacy.timeParserPolicy=LEGACY \
    --conf spark.sql.shuffle.partitions=4 \
    --conf spark.yarn.jars="hdfs:///spark-jars/*" \
    --name "WebLogAnalytics-ex${NUM_EXECUTORS}" \
    "${APP_SCRIPT}" \
    --input "${INPUT_PATH}" \
    --output "${OUTPUT_PATH}" \
    --parquet "${PARQUET_PATH}"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
info "✅  Spark job completed in ${ELAPSED} seconds."
info "   Executors used: ${NUM_EXECUTORS}"

# Save timing for benchmarks
TIMING_FILE="${SCRIPT_DIR}/../results/timing_ex${NUM_EXECUTORS}.txt"
mkdir -p "${SCRIPT_DIR}/../results"
echo "${NUM_EXECUTORS},${ELAPSED}" >> "${TIMING_FILE}"
echo "${ELAPSED}" > "${SCRIPT_DIR}/../results/last_run_time.txt"

info "── Output directories in HDFS ──────────────────────────────"
${HADOOP_HOME}/bin/hdfs dfs -ls "${OUTPUT_PATH}" 2>/dev/null

echo ""
info "📸 Screenshot the YARN app page (http://${MASTER_IP}:8088) showing both workers."
info "Then proceed to 07_fetch_results.sh on MASTER."
