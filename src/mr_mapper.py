#!/usr/bin/env python3
"""
mr_mapper.py  –  Hadoop Streaming mapper
=========================================
Reads CLF log lines from stdin, emits: <url>\t1
Used by 09_mapreduce_compare.sh for the MapReduce vs Spark benchmark.
"""
import sys
import re

LOG_PATTERN = re.compile(
    r'^\S+\s+\S+\s+\S+\s+\[[^\]]+\]\s+"(\S+)\s+(\S+)\s*\S*"\s+(\d{3})\s+\S+'
)

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    m = LOG_PATTERN.match(line)
    if m:
        # method = m.group(1)
        url    = m.group(2)
        status = m.group(3)
        # Emit url and status as key, count 1
        print(f"{url}\t{status}\t1")
