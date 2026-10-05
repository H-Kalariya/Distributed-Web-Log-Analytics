#!/usr/bin/env bash
# =============================================================================
# 01_setup_node.sh  –  Run on EVERY node (master, worker1, worker2)
#
# What it does:
#   1. Installs Java 11, SSH server, wget, git
#   2. Writes /etc/hosts so nodes resolve each other by name
#   3. Downloads and extracts Hadoop 3.3.6 to /opt/hadoop
#   4. Sets JAVA_HOME, HADOOP_HOME, PATH in ~/.bashrc
#   5. Creates the HDFS data directories
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── 1. System packages ───────────────────────────────────────────────────────
info "Installing Java ${JAVA_VERSION}, SSH, wget, git ..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    openjdk-${JAVA_VERSION}-jdk \
    openssh-server openssh-client \
    wget curl git net-tools \
    python3 python3-pip python3-venv

# ── 2. /etc/hosts ─────────────────────────────────────────────────────────────
info "Updating /etc/hosts ..."
sudo tee -a /etc/hosts > /dev/null <<EOF

# Hadoop cluster nodes
${MASTER_IP}   ${MASTER_HOST}
${WORKER1_IP}  ${WORKER1_HOST}
${WORKER2_IP}  ${WORKER2_HOST}
EOF

# ── 3. Download Hadoop ────────────────────────────────────────────────────────
HADOOP_TGZ="hadoop-${HADOOP_VERSION}.tar.gz"
HADOOP_URL="https://downloads.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/${HADOOP_TGZ}"
MIRROR_URL="https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/${HADOOP_TGZ}"

if [ ! -d "${HADOOP_HOME}" ]; then
    info "Downloading Hadoop ${HADOOP_VERSION} ..."
    cd /tmp
    wget -q --show-progress "${HADOOP_URL}" || wget -q --show-progress "${MIRROR_URL}"
    sudo tar -xzf "${HADOOP_TGZ}" -C /opt/
    sudo mv /opt/hadoop-${HADOOP_VERSION} ${HADOOP_HOME}
    sudo chown -R ${HADOOP_USER}:${HADOOP_USER} ${HADOOP_HOME}
    rm -f "${HADOOP_TGZ}"
    info "Hadoop extracted to ${HADOOP_HOME}"
else
    warn "Hadoop already at ${HADOOP_HOME}, skipping download."
fi

# ── 4. Environment variables ──────────────────────────────────────────────────
JAVA_HOME_PATH=$(dirname $(dirname $(readlink -f $(which java))))

info "Writing environment variables to ~/.bashrc ..."
cat >> ~/.bashrc <<EOF

# ── Hadoop environment ──────────────────────────────────────────
export JAVA_HOME=${JAVA_HOME_PATH}
export HADOOP_HOME=${HADOOP_HOME}
export HADOOP_CONF_DIR=\${HADOOP_HOME}/etc/hadoop
export PATH=\${PATH}:\${HADOOP_HOME}/bin:\${HADOOP_HOME}/sbin
export HADOOP_MAPRED_HOME=\${HADOOP_HOME}
export YARN_HOME=\${HADOOP_HOME}
export HDFS_NAMENODE_USER=${HADOOP_USER}
export HDFS_DATANODE_USER=${HADOOP_USER}
export HDFS_SECONDARYNAMENODE_USER=${HADOOP_USER}
export YARN_RESOURCEMANAGER_USER=${HADOOP_USER}
export YARN_NODEMANAGER_USER=${HADOOP_USER}
EOF

# Write JAVA_HOME into Hadoop's own env script so daemons pick it up
echo "export JAVA_HOME=${JAVA_HOME_PATH}" | sudo tee -a ${HADOOP_HOME}/etc/hadoop/hadoop-env.sh > /dev/null

# ── 5. Data directories ───────────────────────────────────────────────────────
info "Creating HDFS data directories ..."
sudo mkdir -p ${HADOOP_DATA}/{namenode,datanode,tmp}
sudo chown -R ${HADOOP_USER}:${HADOOP_USER} ${HADOOP_DATA}
sudo chmod -R 755 ${HADOOP_DATA}

# ── 6. SSH daemon ─────────────────────────────────────────────────────────────
info "Ensuring SSH server is enabled and running ..."
sudo systemctl enable ssh --quiet
sudo systemctl start ssh

# ── Done ──────────────────────────────────────────────────────────────────────
info "✅  Node setup complete. Run: source ~/.bashrc && hadoop version"
info "Then proceed to 02_ssh_and_config.sh on MASTER only."
