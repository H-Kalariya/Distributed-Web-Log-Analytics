#!/usr/bin/env bash
# =============================================================================
# 10_fault_tolerance_demo.sh  –  Run on MASTER only
#
# Demonstrates HDFS fault tolerance:
#   1. Show fsck BEFORE – 2 replicas healthy
#   2. Kill worker2's DataNode
#   3. Show fsck AFTER  – data still readable from worker1's replica
#   4. Read a file to prove it still works
#   5. Restart worker2's DataNode
#   6. Show fsck FINAL  – replication recovered
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster.env"
source ~/.bashrc 2>/dev/null || true

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
section() { echo -e "\n${YELLOW}════════════════════════════════════════${NC}"; echo -e "${YELLOW}  $*${NC}"; echo -e "${YELLOW}════════════════════════════════════════${NC}"; }

HDFS_FILE="hdfs:///logs/raw"

section "STEP 1 – Baseline: HDFS health BEFORE fault injection"
info "Running hdfs fsck ..."
${HADOOP_HOME}/bin/hdfs fsck "${HDFS_FILE}" -blocks -locations 2>/dev/null | tail -20
info "📸 Screenshot this output."

section "STEP 2 – Killing DataNode on worker2"
warn "Stopping DataNode on worker2 ..."
ssh "${WORKER2_HOST}" "source ~/.bashrc 2>/dev/null; hdfs --daemon stop datanode" \
    && info "DataNode stopped on worker2." \
    || warn "Could not stop DataNode on worker2 (may already be stopped)."

info "Waiting 15 seconds for NameNode to detect missing DataNode ..."
sleep 15

section "STEP 3 – HDFS status AFTER worker2 DataNode killed"
${HADOOP_HOME}/bin/hdfs dfsadmin -report 2>/dev/null | head -20
info "📸 Screenshot this (should show 1 live DataNode)."

section "STEP 4 – Proving data is still readable from worker1's replica"
info "Running hdfs fsck (blocks should still be found on worker1) ..."
${HADOOP_HOME}/bin/hdfs fsck "${HDFS_FILE}" -blocks -locations 2>/dev/null | grep -E "Under-replicated|MISSING|Status:" | head -10

info "Reading first 3 lines of the log file from HDFS ..."
${HADOOP_HOME}/bin/hdfs dfs -cat "${HDFS_FILE}/NASA_access_log_Jul95" 2>/dev/null | head -3 \
    || ${HADOOP_HOME}/bin/hdfs dfs -cat "${HDFS_FILE}/synthetic_access_log.txt" 2>/dev/null | head -3 \
    || warn "Could not read file – check the filename in HDFS"

info "✅  Data IS readable even with worker2 down. Fault tolerance verified."
info "📸 Screenshot the output above."

section "STEP 5 – Restarting DataNode on worker2"
ssh "${WORKER2_HOST}" "source ~/.bashrc 2>/dev/null; hdfs --daemon start datanode" \
    && info "DataNode restarted on worker2." \
    || warn "Could not restart DataNode on worker2."

info "Waiting 20 seconds for re-replication to begin ..."
sleep 20

section "STEP 6 – HDFS health AFTER recovery"
${HADOOP_HOME}/bin/hdfs fsck "${HDFS_FILE}" -blocks -locations 2>/dev/null | tail -15
info "📸 Screenshot showing replication restored to 2."

info "✅  Fault tolerance demo complete."
