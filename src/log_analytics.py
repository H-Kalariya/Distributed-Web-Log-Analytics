"""
log_analytics.py  –  PySpark web-log analytics job
====================================================
Stages
  1. Read raw log files from HDFS
  2. Parse each line with a regex into structured columns
  3. Clean: drop malformed, fix null bytes, parse timestamp
  4. Write Parquet (columnar, compressed, partitioned by date)
  5. Run Spark SQL analytics:
       top_urls, status_counts, hourly_traffic, top_ips,
       top_404s, bandwidth, summary
  6. Write each result as a CSV to HDFS

Usage (via 06_run_analytics.sh, but can also run directly):
  spark-submit log_analytics.py \
      --input  hdfs:///logs/raw \
      --output hdfs:///logs/output \
      --parquet hdfs:///logs/parquet
"""

import argparse
import re
import sys
from datetime import datetime

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (
    StructType, StructField,
    StringType, IntegerType, LongType, TimestampType
)

# ── CLI arguments ─────────────────────────────────────────────────────────────
parser = argparse.ArgumentParser(description="Web Log Analytics with PySpark")
parser.add_argument("--input",   default="hdfs:///logs/raw",     help="HDFS input directory")
parser.add_argument("--output",  default="hdfs:///logs/output",  help="HDFS CSV output directory")
parser.add_argument("--parquet", default="hdfs:///logs/parquet", help="HDFS Parquet output directory")
args = parser.parse_args()

# ── Spark session ─────────────────────────────────────────────────────────────
spark = (
    SparkSession.builder
    .appName("WebLogAnalytics")
    .config("spark.sql.legacy.timeParserPolicy", "LEGACY")
    # Coalesce output to avoid thousands of tiny part files
    .config("spark.sql.shuffle.partitions", "4")
    .getOrCreate()
)
spark.sparkContext.setLogLevel("WARN")

print(f"\n{'='*60}")
print(f"  Web Log Analytics  –  Input: {args.input}")
print(f"{'='*60}\n")

# ── Stage 1: Read raw text lines ─────────────────────────────────────────────
print("[Stage 1] Reading raw log files from HDFS ...")
raw = spark.read.text(args.input)
total_lines = raw.count()
print(f"  Total lines read: {total_lines:,}")

# ── Stage 2: Parse with regex ─────────────────────────────────────────────────
# CLF format: ip - - [timestamp] "method url protocol" status bytes
LOG_PATTERN = (
    r'^(\S+)'                            # 1  ip
    r'\s+\S+\s+\S+'                      #    ident, authuser (ignored)
    r'\s+\[([^\]]+)\]'                   # 2  timestamp
    r'\s+"(\S+)\s+(\S+)\s*(\S*)\"'      # 3  method  4 url  5 protocol
    r'\s+(\d{3})'                        # 6  status
    r'\s+(\S+)'                          # 7  bytes (may be '-')
)

print("[Stage 2] Parsing log lines with regex ...")

parsed = raw.select(
    F.regexp_extract("value", LOG_PATTERN, 1).alias("ip"),
    F.regexp_extract("value", LOG_PATTERN, 2).alias("timestamp_str"),
    F.regexp_extract("value", LOG_PATTERN, 3).alias("method"),
    F.regexp_extract("value", LOG_PATTERN, 4).alias("url"),
    F.regexp_extract("value", LOG_PATTERN, 5).alias("protocol"),
    F.regexp_extract("value", LOG_PATTERN, 6).alias("status_str"),
    F.regexp_extract("value", LOG_PATTERN, 7).alias("bytes_str"),
)

# ── Stage 3: Clean ────────────────────────────────────────────────────────────
print("[Stage 3] Cleaning and casting columns ...")

# Drop rows where regex matched nothing (malformed lines)
clean = (
    parsed
    .filter(F.col("ip") != "")
    .filter(F.col("status_str") != "")
    # Cast types
    .withColumn("status", F.col("status_str").cast(IntegerType()))
    .withColumn(
        "bytes",
        F.when(F.col("bytes_str") == "-", F.lit(0))
         .otherwise(F.col("bytes_str").cast(LongType()))
         .cast(LongType())
    )
    # Parse timestamp:  01/Jul/1995:00:00:01 -0400
    .withColumn(
        "timestamp",
        F.to_timestamp("timestamp_str", "dd/MMM/yyyy:HH:mm:ss Z")
    )
    .withColumn("date",  F.to_date("timestamp"))
    .withColumn("hour",  F.hour("timestamp"))
    .drop("status_str", "bytes_str")
)

# Cache because we run many queries against this
clean.cache()

clean_count    = clean.count()
malformed      = total_lines - clean_count
malformed_pct  = malformed / total_lines * 100 if total_lines > 0 else 0

print(f"  Clean lines:    {clean_count:,}")
print(f"  Malformed/skipped: {malformed:,}  ({malformed_pct:.2f}%)")

# ── Stage 4: Write Parquet ────────────────────────────────────────────────────
print(f"[Stage 4] Writing Parquet to {args.parquet} ...")
(
    clean
    .write
    .mode("overwrite")
    .partitionBy("date")
    .parquet(args.parquet)
)
print("  Parquet written.")

# ── Stage 5 & 6: Analytics → CSV ─────────────────────────────────────────────
def save_csv(df, name, n=None):
    """Coalesce to 1 partition and write as CSV with header."""
    out = df.coalesce(1) if n is None else df.limit(n).coalesce(1)
    path = f"{args.output}/{name}"
    out.write.mode("overwrite").option("header", "true").csv(path)
    print(f"  Saved: {path}")

clean.createOrReplaceTempView("logs")

print("\n[Stage 5] Running Spark SQL analytics ...")

# 5a. Top 20 URLs by hit count
print("  → top_urls")
top_urls = spark.sql("""
    SELECT url,
           COUNT(*) AS hits
    FROM logs
    WHERE url IS NOT NULL AND url != ''
    GROUP BY url
    ORDER BY hits DESC
    LIMIT 20
""")
save_csv(top_urls, "top_urls")

# 5b. HTTP status code distribution
print("  → status_counts")
status_counts = spark.sql("""
    SELECT status,
           COUNT(*) AS count,
           ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM logs), 2) AS percentage
    FROM logs
    GROUP BY status
    ORDER BY count DESC
""")
save_csv(status_counts, "status_counts")

# 5c. Hourly traffic pattern
print("  → hourly_traffic")
hourly = spark.sql("""
    SELECT hour,
           COUNT(*) AS requests,
           SUM(bytes) AS total_bytes
    FROM logs
    GROUP BY hour
    ORDER BY hour
""")
save_csv(hourly, "hourly_traffic")

# 5d. Top 10 IPs by request count
print("  → top_ips")
top_ips = spark.sql("""
    SELECT ip,
           COUNT(*) AS requests,
           SUM(bytes) AS total_bytes
    FROM logs
    GROUP BY ip
    ORDER BY requests DESC
    LIMIT 10
""")
save_csv(top_ips, "top_ips")

# 5e. Top 20 URLs that returned 404
print("  → top_404s")
top_404 = spark.sql("""
    SELECT url,
           COUNT(*) AS count
    FROM logs
    WHERE status = 404
    GROUP BY url
    ORDER BY count DESC
    LIMIT 20
""")
save_csv(top_404, "top_404s")

# 5f. Bandwidth by URL (top 10 data consumers)
print("  → bandwidth")
bandwidth = spark.sql("""
    SELECT url,
           SUM(bytes) AS total_bytes,
           COUNT(*) AS hits,
           ROUND(AVG(bytes), 0) AS avg_bytes_per_hit
    FROM logs
    WHERE bytes > 0
    GROUP BY url
    ORDER BY total_bytes DESC
    LIMIT 10
""")
save_csv(bandwidth, "bandwidth")

# 5g. Summary statistics
print("  → summary")
unique_ips  = clean.select("ip").distinct().count()
error_count = clean.filter(F.col("status") >= 400).count()
error_pct   = error_count / clean_count * 100 if clean_count > 0 else 0
total_bytes = clean.agg(F.sum("bytes")).collect()[0][0] or 0

summary_data = [(
    total_lines,
    clean_count,
    malformed,
    round(malformed_pct, 2),
    unique_ips,
    error_count,
    round(error_pct, 2),
    total_bytes,
)]
summary_schema = StructType([
    StructField("total_lines",       LongType(),   False),
    StructField("clean_lines",       LongType(),   False),
    StructField("malformed_lines",   LongType(),   False),
    StructField("malformed_pct",     StringType(), False),
    StructField("unique_ips",        LongType(),   False),
    StructField("error_requests",    LongType(),   False),
    StructField("error_pct",         StringType(), False),
    StructField("total_bytes",       LongType(),   False),
])
summary_df = spark.createDataFrame(summary_data, schema=summary_schema)
save_csv(summary_df, "summary")

# ── Done ──────────────────────────────────────────────────────────────────────
print(f"\n{'='*60}")
print("  Analytics complete!")
print(f"  Total lines   : {total_lines:,}")
print(f"  Clean lines   : {clean_count:,}")
print(f"  Unique IPs    : {unique_ips:,}")
print(f"  Error %       : {error_pct:.2f}%")
print(f"  Total bytes   : {total_bytes:,}")
print(f"  Output        : {args.output}")
print(f"{'='*60}\n")

spark.stop()
