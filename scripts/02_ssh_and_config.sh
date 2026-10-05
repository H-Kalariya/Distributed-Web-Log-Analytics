#!/usr/bin/env bash
# =============================================================================
# 02_ssh_and_config.sh  –  Run on MASTER only
#
# What it does:
#   1. Generates an SSH key pair for the hadoop user on master
#   2. Copies the public key to master itself, worker1, worker2
#   3. Copies the 5 Hadoop config files to all 3 nodes
#   4. Verifies passwordless SSH works
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster.env"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

NODES=("${MASTER_HOST}" "${WORKER1_HOST}" "${WORKER2_HOST}")
CONFIG_DIR="${SCRIPT_DIR}/../config"

# ── 1. Generate SSH key pair ─────────────────────────────────────────────────
info "Setting up SSH key pair ..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh

if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa -q
    info "SSH key pair generated."
else
    warn "SSH key already exists, skipping keygen."
fi

# ── 2. Distribute public key to all nodes ────────────────────────────────────
for node in "${NODES[@]}"; do
    info "Copying SSH key to ${node} ..."
    # ssh-copy-id will prompt for password the first time
    ssh-copy-id -o StrictHostKeyChecking=no ${HADOOP_USER}@${node} \
        && info "  ✓ ${node} done" \
        || warn "  ✗ ${node} failed – run manually: ssh-copy-id hadoop@${node}"
done

# ── 3. Push Hadoop XML configs to all nodes ──────────────────────────────────
HADOOP_ETC="${HADOOP_HOME}/etc/hadoop"
CONFIG_FILES=(
    "core-site.xml"
    "hdfs-site.xml"
    "yarn-site.xml"
    "mapred-site.xml"
    "workers"
)

info "Pushing config files to all nodes ..."
for node in "${NODES[@]}"; do
    for cfg in "${CONFIG_FILES[@]}"; do
        scp -q "${CONFIG_DIR}/${cfg}" ${HADOOP_USER}@${node}:${HADOOP_ETC}/${cfg}
    done
    info "  ✓ Configs pushed to ${node}"
done

# ── 4. Verify passwordless SSH ───────────────────────────────────────────────
info "Verifying passwordless SSH ..."
for node in "${NODES[@]}"; do
    result=$(ssh -o BatchMode=yes -o ConnectTimeout=5 ${node} hostname 2>&1)
    if [ "${result}" = "${node}" ]; then
        info "  ✓ ${node} → hostname: ${result}"
    else
        warn "  ✗ ${node} SSH check failed. Output: ${result}"
    fi
done

info "✅  SSH setup complete."
info "Run: ssh worker1 hostname   (should print 'worker1' with no password)"
info "Then proceed to 03_start_cluster.sh on MASTER."
