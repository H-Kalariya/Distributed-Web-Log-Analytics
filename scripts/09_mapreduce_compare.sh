#!/usr/bin/env bash
# =============================================================================
# 09_mapreduce_compare.sh  –  Run on MASTER only
#
# Runs the MapReduce word-count style URL counter and compares its runtime
# against the Spark job.  Writes results/mr_vs_spark.csv.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster.env"
source ~/.bashrc 2>/dev/null || true

GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC}  $*"; }

RESULTS_DIR="${SCRIPT_DIR}/../results"
mkdir -p "${RESULTS_DIR}"

MR_OUTPUT="hdfs:///logs/mr_output"
${HADOOP_HOME}/bin/hdfs dfs -rm -r -f "${MR_OUTPUT}" 2>/dev/null || true

# ── Run MapReduce job ─────────────────────────────────────────────────────────
info "Running MapReduce URL counter ..."
START_MR=$(date +%s)

${HADOOP_HOME}/bin/hadoop jar \
    "${HADOOP_HOME}/share/hadoop/tools/lib/hadoop-streaming-${HADOOP_VERSION}.jar" \
    -mapper  "python3 ${SCRIPT_DIR}/../src/mr_mapper.py" \
    -reducer "python3 ${SCRIPT_DIR}/../src/mr_reducer.py" \
    -input   "hdfs:///logs/raw" \
    -output  "${MR_OUTPUT}" \
    -file    "${SCRIPT_DIR}/../src/mr_mapper.py" \
    -file    "${SCRIPT_DIR}/../src/mr_reducer.py"

END_MR=$(date +%s)
MR_TIME=$((END_MR - START_MR))
info "MapReduce time: ${MR_TIME}s"

# ── Read Spark time from benchmark ────────────────────────────────────────────
SPARK_TIME=$(grep "^2," "${RESULTS_DIR}/benchmark.csv" 2>/dev/null | cut -d',' -f2 || echo "N/A")

# ── Write comparison CSV ──────────────────────────────────────────────────────
cat > "${RESULTS_DIR}/mr_vs_spark.csv" <<EOF
engine,time_seconds,notes
MapReduce,${MR_TIME},Hadoop Streaming Python mapper+reducer
Spark,${SPARK_TIME},PySpark DataFrame with 2 executors
EOF

info "── MapReduce vs Spark ───────────────────────────────────────"
cat "${RESULTS_DIR}/mr_vs_spark.csv"

# ── Bar chart ─────────────────────────────────────────────────────────────────
python3 - <<PYEOF
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

mr_time    = ${MR_TIME}
spark_time = ${SPARK_TIME} if "${SPARK_TIME}" != "N/A" else None

engines = ['MapReduce']
times   = [mr_time]
colors  = ['#FF5722']

if spark_time:
    engines.append('Spark (2 exec)')
    times.append(spark_time)
    colors.append('#2196F3')

fig, ax = plt.subplots(figsize=(7, 5))
bars = ax.bar(engines, times, color=colors, width=0.5)
ax.set_ylabel('Time (seconds)')
ax.set_title('MapReduce vs Spark – URL Count Job\n3-Node Hadoop Cluster', fontweight='bold')
for bar, t in zip(bars, times):
    ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 1,
            f'{t:.0f}s', ha='center', fontweight='bold', fontsize=12)
ax.set_ylim(0, max(times) * 1.25)
plt.tight_layout()
plt.savefig('${RESULTS_DIR}/mr_vs_spark.png', dpi=150, bbox_inches='tight')
print("Saved: mr_vs_spark.png")
PYEOF

info "✅  Comparison done. Chart: results/mr_vs_spark.png"
info "Then proceed to 10_fault_tolerance_demo.sh"
