#!/usr/bin/env bash
# =============================================================================
# 04_install_spark.sh  –  Run on MASTER only
#
# What it does:
#   1. Downloads Spark 3.5.1 (pre-built for Hadoop 3)
#   2. Extracts to /opt/spark and sets env vars
#   3. Configures spark-defaults.conf to use YARN
#   4. Uploads Spark JARs to HDFS so workers don't re-download every job
#   5. Installs Python dependencies: pyspark, pandas, matplotlib, numpy
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster.env"
source ~/.bashrc 2>/dev/null || true

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }

SPARK_TGZ="spark-${SPARK_VERSION}-bin-hadoop3.tgz"
SPARK_URL="https://downloads.apache.org/spark/spark-${SPARK_VERSION}/${SPARK_TGZ}"
SPARK_MIRROR="https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/${SPARK_TGZ}"

# ── 1. Download and extract Spark ─────────────────────────────────────────────
if [ ! -d "${SPARK_HOME}" ]; then
    info "Downloading Spark ${SPARK_VERSION} ..."
    cd /tmp
    wget -q --show-progress "${SPARK_URL}" || wget -q --show-progress "${SPARK_MIRROR}"
    sudo tar -xzf "${SPARK_TGZ}" -C /opt/
    sudo mv /opt/spark-${SPARK_VERSION}-bin-hadoop3 ${SPARK_HOME}
    sudo chown -R ${HADOOP_USER}:${HADOOP_USER} ${SPARK_HOME}
    rm -f "${SPARK_TGZ}"
    info "Spark extracted to ${SPARK_HOME}"
else
    warn "Spark already at ${SPARK_HOME}, skipping download."
fi

# ── 2. Environment variables ──────────────────────────────────────────────────
info "Writing Spark env vars to ~/.bashrc ..."
cat >> ~/.bashrc <<'EOF'

# ── Spark environment ───────────────────────────────────────────
export SPARK_HOME=/opt/spark
export PATH=${PATH}:${SPARK_HOME}/bin:${SPARK_HOME}/sbin
export PYSPARK_PYTHON=python3
export PYSPARK_DRIVER_PYTHON=python3
EOF

export SPARK_HOME=/opt/spark
export PATH=${PATH}:${SPARK_HOME}/bin

# ── 3. spark-defaults.conf ────────────────────────────────────────────────────
info "Writing spark-defaults.conf ..."
cat > ${SPARK_HOME}/conf/spark-defaults.conf <<EOF
# Run on YARN
spark.master                     yarn
spark.submit.deployMode          client

# Spark JARs cached in HDFS for fast job submission
spark.yarn.jars                  hdfs:///spark-jars/*

# Executor resource defaults (override with --executor-memory on CLI)
spark.executor.memory            1g
spark.executor.cores             1
spark.driver.memory              1g

# History server log dir
spark.eventLog.enabled           true
spark.eventLog.dir               hdfs:///spark-logs

# Legacy timestamp parser (needed for NASA log date format)
spark.sql.legacy.timeParserPolicy  LEGACY

# Shuffle partitions: 4 is sensible for a 2-worker cluster
spark.sql.shuffle.partitions     4
EOF

# ── 4. spark-env.sh ───────────────────────────────────────────────────────────
cp ${SPARK_HOME}/conf/spark-env.sh.template ${SPARK_HOME}/conf/spark-env.sh 2>/dev/null || true
cat >> ${SPARK_HOME}/conf/spark-env.sh <<EOF
export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
export HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
export YARN_CONF_DIR=${HADOOP_HOME}/etc/hadoop
export SPARK_DIST_CLASSPATH=\$(${HADOOP_HOME}/bin/hadoop classpath)
EOF

# ── 5. Upload Spark JARs to HDFS ─────────────────────────────────────────────
info "Uploading Spark JARs to HDFS (hdfs:///spark-jars) ..."
source ~/.bashrc 2>/dev/null || true
${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /spark-jars
${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /spark-logs

${HADOOP_HOME}/bin/hdfs dfs -put -f \
    ${SPARK_HOME}/jars/*.jar \
    hdfs:///spark-jars/ \
    && info "Spark JARs uploaded." \
    || warn "JAR upload failed – check HDFS is running."

# ── 6. Python dependencies ────────────────────────────────────────────────────
info "Installing Python packages ..."
pip3 install --quiet pyspark==${SPARK_VERSION} pandas matplotlib numpy seaborn

info "✅  Spark ${SPARK_VERSION} installed and configured."
info "Run: source ~/.bashrc && spark-submit --version"
info "Then proceed to 05_load_data.sh on MASTER."
