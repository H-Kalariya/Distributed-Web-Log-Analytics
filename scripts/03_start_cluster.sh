#!/usr/bin/env bash
# =============================================================================
# 03_start_cluster.sh  –  Run on MASTER only
#
# What it does:
#   1. Formats the NameNode (first run only – skipped if already formatted)
#   2. Starts HDFS (NameNode + SecondaryNameNode on master, DataNodes on workers)
#   3. Starts YARN (ResourceManager on master, NodeManagers on workers)
#   4. Prints jps output from all 3 nodes
#   5. Shows hdfs dfsadmin -report
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster.env"
source ~/.bashrc 2>/dev/null || true

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── 1. Format NameNode ────────────────────────────────────────────────────────
NN_DIR="${HADOOP_DATA}/namenode"
if [ ! -d "${NN_DIR}/current" ]; then
    info "Formatting NameNode (first-time setup) ..."
    ${HADOOP_HOME}/bin/hdfs namenode -format -force -nonInteractive
    info "NameNode formatted."
else
    warn "NameNode already formatted (${NN_DIR}/current exists). Skipping format."
    warn "If you need a clean re-format: rm -rf ${NN_DIR}/* and re-run."
fi

# ── 2. Start HDFS ─────────────────────────────────────────────────────────────
info "Starting HDFS ..."
${HADOOP_HOME}/sbin/start-dfs.sh
sleep 5

# ── 3. Start YARN ─────────────────────────────────────────────────────────────
info "Starting YARN ..."
${HADOOP_HOME}/sbin/start-yarn.sh
sleep 5

# ── 4. jps on all nodes ───────────────────────────────────────────────────────
echo ""
info "── JPS output ──────────────────────────────────────────────"
for node in "${MASTER_HOST}" "${WORKER1_HOST}" "${WORKER2_HOST}"; do
    echo -e "\n${YELLOW}${node}:${NC}"
    ssh ${node} "source ~/.bashrc 2>/dev/null; jps" 2>/dev/null || warn "  Could not reach ${node}"
done

# ── 5. HDFS admin report ──────────────────────────────────────────────────────
echo ""
info "── HDFS dfsadmin report ────────────────────────────────────"
${HADOOP_HOME}/bin/hdfs dfsadmin -report 2>/dev/null | head -40

# ── 6. Create base HDFS directories ──────────────────────────────────────────
info "Creating HDFS directory structure ..."
${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /logs/raw
${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /logs/parquet
${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /logs/output
${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /user/${HADOOP_USER}
${HADOOP_HOME}/bin/hdfs dfs -chmod -R 775 /logs

echo ""
info "✅  Cluster is up!"
info "   HDFS UI  → http://${MASTER_IP}:9870"
info "   YARN UI  → http://${MASTER_IP}:8088"
info ""
info "📸 Screenshot both UIs and run: hdfs dfsadmin -report"
info "Then proceed to 04_install_spark.sh on MASTER."
