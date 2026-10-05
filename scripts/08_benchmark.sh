#!/usr/bin/env bash
# =============================================================================
# 08_benchmark.sh  –  Run on MASTER only
#
# Runs the analytics job 3 times with 1, 2, and 4 executors and records
# wall-clock time for each.  Results go to results/benchmark.csv.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster.env"
source ~/.bashrc 2>/dev/null || true

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC}  $*"; }

RESULTS_DIR="${SCRIPT_DIR}/../results"
BENCH_CSV="${RESULTS_DIR}/benchmark.csv"
mkdir -p "${RESULTS_DIR}"

echo "executors,time_seconds,speedup" > "${BENCH_CSV}"

BASELINE=0
for N in 1 2 4; do
    info "── Run with ${N} executor(s) ────────────────────────────────"

    # Clean output so the job doesn't fail on existing dirs
    ${HADOOP_HOME}/bin/hdfs dfs -rm -r -f hdfs:///logs/output 2>/dev/null || true

    START=$(date +%s)

    spark-submit \
        --master yarn \
        --deploy-mode client \
        --num-executors "${N}" \
        --executor-memory "1g" \
        --executor-cores "1" \
        --driver-memory "1g" \
        --conf spark.sql.legacy.timeParserPolicy=LEGACY \
        --conf spark.sql.shuffle.partitions=4 \
        --conf spark.yarn.jars="hdfs:///spark-jars/*" \
        --name "Benchmark-ex${N}" \
        "${SCRIPT_DIR}/../src/log_analytics.py" \
        --input "hdfs:///logs/raw" \
        --output "hdfs:///logs/output" \
        --parquet "hdfs:///logs/parquet" \
        2>&1 | tail -5

    END=$(date +%s)
    T=$((END - START))

    if [ "${N}" -eq 1 ]; then
        BASELINE=${T}
        SPEEDUP="1.00"
    else
        SPEEDUP=$(python3 -c "print(f'{${BASELINE}/${T}:.2f}')")
    fi

    echo "${N},${T},${SPEEDUP}" >> "${BENCH_CSV}"
    info "  executors=${N}  time=${T}s  speedup=${SPEEDUP}x"
done

echo ""
info "── Benchmark results ───────────────────────────────────────"
cat "${BENCH_CSV}"

# Generate speedup chart
python3 - <<'PYEOF'
import csv, os
import matplotlib.pyplot as plt
import matplotlib
matplotlib.use('Agg')

results_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'results')
bench_csv   = os.path.join(results_dir, 'benchmark.csv')

rows = []
with open(bench_csv) as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)

executors = [int(r['executors'])   for r in rows]
times     = [float(r['time_seconds']) for r in rows]
speedups  = [float(r['speedup'])   for r in rows]

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))

ax1.bar([str(e) for e in executors], times, color=['#2196F3','#4CAF50','#FF9800'])
ax1.set_xlabel('Number of Executors')
ax1.set_ylabel('Time (seconds)')
ax1.set_title('Execution Time vs Executors')
for i, t in enumerate(times):
    ax1.text(i, t + 1, f'{t:.0f}s', ha='center', fontweight='bold')

ax2.plot([str(e) for e in executors], speedups, 'o-', color='#E91E63', linewidth=2, markersize=8)
ax2.axhline(y=1, color='gray', linestyle='--', alpha=0.5, label='Baseline')
ax2.set_xlabel('Number of Executors')
ax2.set_ylabel('Speedup (T1 / Tn)')
ax2.set_title('Speedup vs Executors')
ax2.legend()
for i, s in enumerate(speedups):
    ax2.annotate(f'{s:.2f}x', (str(executors[i]), s), textcoords="offset points", xytext=(0, 10))

plt.suptitle('Spark Scalability Benchmark – 3-Node Hadoop Cluster', fontsize=13, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(results_dir, 'benchmark_speedup.png'), dpi=150, bbox_inches='tight')
print("Saved: benchmark_speedup.png")
PYEOF

info "✅  Benchmark done. Chart: results/benchmark_speedup.png"
info "Then proceed to 09_mapreduce_compare.sh"
