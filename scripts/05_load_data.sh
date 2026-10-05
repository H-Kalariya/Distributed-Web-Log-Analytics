#!/usr/bin/env bash
# =============================================================================
# 05_load_data.sh  –  Run on MASTER only
#
# Usage:
#   ./05_load_data.sh nasa              # Download real NASA HTTP logs (~200 MB)
#   ./05_load_data.sh synthetic 500     # Generate 500 MB of synthetic logs
#   ./05_load_data.sh local <filepath>  # Load a local log file you already have
#
# After loading, the script prints hdfs fsck to confirm block distribution.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/cluster.env"
source ~/.bashrc 2>/dev/null || true

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

MODE="${1:-nasa}"
DATA_DIR="${SCRIPT_DIR}/../data"
mkdir -p "${DATA_DIR}"

HDFS_RAW="/logs/raw"
HDFS_PARQUET="/logs/parquet"
HDFS_OUTPUT="/logs/output"

# ── Ensure HDFS dirs exist ────────────────────────────────────────────────────
${HADOOP_HOME}/bin/hdfs dfs -mkdir -p ${HDFS_RAW} ${HDFS_PARQUET} ${HDFS_OUTPUT}

# ─────────────────────────────────────────────────────────────────────────────
# MODE: nasa
# ─────────────────────────────────────────────────────────────────────────────
if [ "${MODE}" = "nasa" ]; then
    NASA_FILE="${DATA_DIR}/NASA_access_log_Jul95"
    NASA_URL_1="ftp://ita.ee.lbl.gov/traces/NASA_access_log_Jul95.gz"
    NASA_URL_2="https://raw.githubusercontent.com/logpai/loghub/master/Apache/Apache_2k.log"

    if [ ! -f "${NASA_FILE}" ]; then
        info "Attempting NASA log download ..."
        # Try FTP first, fall back to a smaller Apache log for testing
        if wget -q --timeout=30 -O "${NASA_FILE}.gz" "${NASA_URL_1}" 2>/dev/null; then
            info "Downloaded NASA log via FTP, decompressing ..."
            gunzip "${NASA_FILE}.gz"
        else
            warn "FTP blocked. Using sample Apache log for structure validation."
            warn "For full data, download from Kaggle: 'NASA HTTP logs Jul 1995'"
            warn "Place the file at: ${NASA_FILE}"
            wget -q -O "${NASA_FILE}" "${NASA_URL_2}" \
                && info "Sample log downloaded." \
                || error "Could not download any log file. Place your file at ${NASA_FILE} and re-run."
        fi
    else
        info "NASA log already at ${NASA_FILE}"
    fi

    info "Uploading to HDFS ..."
    ${HADOOP_HOME}/bin/hdfs dfs -put -f "${NASA_FILE}" "${HDFS_RAW}/"
    info "Uploaded: ${NASA_FILE} → ${HDFS_RAW}/"

# ─────────────────────────────────────────────────────────────────────────────
# MODE: synthetic <size_mb>
# ─────────────────────────────────────────────────────────────────────────────
elif [ "${MODE}" = "synthetic" ]; then
    SIZE_MB="${2:-200}"
    SYNTH_FILE="${DATA_DIR}/synthetic_access_log.txt"

    info "Generating ${SIZE_MB} MB of synthetic web logs ..."
    python3 - <<PYEOF
import random, datetime, gzip, os, sys

size_mb   = int("${SIZE_MB}")
out_file  = "${SYNTH_FILE}"
target    = size_mb * 1024 * 1024

ips = [f"{random.randint(1,254)}.{random.randint(0,254)}.{random.randint(0,254)}.{random.randint(1,254)}" for _ in range(500)]
urls = [
    "/index.html", "/history/apollo/", "/shuttle/missions/",
    "/images/NASA-logosmall.gif", "/htbin/cdt_main.pl",
    "/shuttle/countdown/", "/cgi-bin/imagemap/countdown",
    "/history/apollo/apollo-13.html", "/software/winvn/",
    "/facts/about_NASA.html", "/nonexistent.html", "/missing_page.php"
]
methods  = ["GET"] * 95 + ["POST"] * 4 + ["HEAD"] * 1
statuses = [200]*70 + [304]*10 + [404]*12 + [500]*4 + [301]*4
months   = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

start = datetime.datetime(1995, 7, 1)
written = 0
lines   = 0

with open(out_file, "w") as f:
    while written < target:
        ip      = random.choice(ips)
        ts_off  = datetime.timedelta(seconds=random.randint(0, 86400*31))
        ts      = start + ts_off
        mo      = months[ts.month - 1]
        ts_str  = f"{ts.day:02d}/{mo}/{ts.year}:{ts.hour:02d}:{ts.minute:02d}:{ts.second:02d} -0400"
        method  = random.choice(methods)
        url     = random.choice(urls)
        status  = random.choice(statuses)
        size    = random.randint(200, 50000) if status not in (304, 404) else 0
        line    = f'{ip} - - [{ts_str}] "{method} {url} HTTP/1.0" {status} {size}\n'
        f.write(line)
        written += len(line)
        lines   += 1

print(f"Generated {lines:,} lines ({written/1024/1024:.1f} MB) → {out_file}")
PYEOF

    info "Uploading synthetic log to HDFS ..."
    ${HADOOP_HOME}/bin/hdfs dfs -put -f "${SYNTH_FILE}" "${HDFS_RAW}/"
    info "Uploaded: ${SYNTH_FILE} → ${HDFS_RAW}/"

# ─────────────────────────────────────────────────────────────────────────────
# MODE: local <filepath>
# ─────────────────────────────────────────────────────────────────────────────
elif [ "${MODE}" = "local" ]; then
    LOCAL_FILE="${2:-}"
    [ -z "${LOCAL_FILE}" ] && error "Usage: $0 local <filepath>"
    [ -f "${LOCAL_FILE}" ] || error "File not found: ${LOCAL_FILE}"
    info "Uploading ${LOCAL_FILE} to HDFS ..."
    ${HADOOP_HOME}/bin/hdfs dfs -put -f "${LOCAL_FILE}" "${HDFS_RAW}/"
    info "Done."

else
    error "Unknown mode '${MODE}'. Usage: $0 [nasa|synthetic <mb>|local <file>]"
fi

# ── Show block distribution ────────────────────────────────────────────────────
echo ""
info "── HDFS block distribution report ─────────────────────────"
${HADOOP_HOME}/bin/hdfs fsck "${HDFS_RAW}" -blocks -locations -files 2>/dev/null | head -60

echo ""
info "── Disk usage ──────────────────────────────────────────────"
${HADOOP_HOME}/bin/hdfs dfs -du -h "${HDFS_RAW}"

echo ""
info "✅  Data loaded into HDFS at ${HDFS_RAW}"
info "📸 Screenshot the fsck output above (shows 2 replicas on worker1+worker2)"
info "Then proceed to 06_run_analytics.sh on MASTER."
