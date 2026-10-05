#!/usr/bin/env bash
# =============================================================================
# 07_fetch_results.sh  –  Run on MASTER only
#
# Downloads all CSVs from HDFS, merges part files, generates charts.
# Results land in: results/
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster.env"
source ~/.bashrc 2>/dev/null || true

GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC}  $*"; }

RESULTS_DIR="${SCRIPT_DIR}/../results"
HDFS_OUTPUT="hdfs:///logs/output"
mkdir -p "${RESULTS_DIR}"

DATASETS=(
    "top_urls"
    "status_counts"
    "hourly_traffic"
    "top_ips"
    "top_404s"
    "bandwidth"
    "summary"
)

# ── Pull each dataset from HDFS ───────────────────────────────────────────────
for ds in "${DATASETS[@]}"; do
    info "Fetching ${ds} ..."
    LOCAL_DIR="${RESULTS_DIR}/${ds}"
    mkdir -p "${LOCAL_DIR}"
    ${HADOOP_HOME}/bin/hdfs dfs -getmerge \
        "${HDFS_OUTPUT}/${ds}" \
        "${LOCAL_DIR}/${ds}.csv" 2>/dev/null \
        || { info "  (skipping ${ds} – not found in HDFS)"; continue; }

    # Add header if the merged file is headerless (Spark writes header per part)
    info "  ✓ ${ds}.csv saved"
done

# ── Generate charts ───────────────────────────────────────────────────────────
info "Generating charts ..."
python3 "${SCRIPT_DIR}/../src/visualize.py" \
    --results "${RESULTS_DIR}" \
    && info "Charts saved to ${RESULTS_DIR}/" \
    || info "Chart generation failed – check visualize.py"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
info "── Results directory ───────────────────────────────────────"
ls -lh "${RESULTS_DIR}" 2>/dev/null

echo ""
info "✅  All results in: ${RESULTS_DIR}"
info "Copy to laptop:  scp hadoop@${MASTER_IP}:~/web-log-analytics-hadoop/results/*.png ."
