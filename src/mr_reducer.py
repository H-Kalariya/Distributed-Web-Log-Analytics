#!/usr/bin/env python3
"""
mr_reducer.py  –  Hadoop Streaming reducer
===========================================
Reads sorted <url>\t<status>\t1 from stdin,
emits: <url>\t<status>\t<total_count>
"""
import sys
from itertools import groupby

def read_input(stdin):
    for line in stdin:
        line = line.strip()
        if line:
            parts = line.split('\t')
            if len(parts) == 3:
                yield parts[0], parts[1], int(parts[2])

def main():
    data = read_input(sys.stdin)
    # Group by (url, status) – works because Hadoop sorts keys before reducer
    for (url, status), group in groupby(data, lambda x: (x[0], x[1])):
        total = sum(count for _, _, count in group)
        print(f"{url}\t{status}\t{total}")

if __name__ == "__main__":
    main()
