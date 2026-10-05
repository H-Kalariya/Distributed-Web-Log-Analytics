"""
visualize.py  –  Generate charts from the CSV results
======================================================
Usage:
    python3 visualize.py --results results/

Produces:
    top_urls.png
    status_pie.png
    traffic_hourly.png
    top_ips.png
    top_404.png
    bandwidth.png
    summary_table.png
"""

import argparse
import os
import csv

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

# ── CLI ───────────────────────────────────────────────────────────────────────
parser = argparse.ArgumentParser()
parser.add_argument("--results", default="results", help="Path to results directory")
args = parser.parse_args()

RESULTS = args.results
os.makedirs(RESULTS, exist_ok=True)

PALETTE = ['#2196F3','#4CAF50','#FF9800','#E91E63','#9C27B0',
           '#00BCD4','#FF5722','#8BC34A','#FFC107','#3F51B5']

def load_csv(name):
    """Load a merged CSV from results/<name>/<name>.csv"""
    path = os.path.join(RESULTS, name, f"{name}.csv")
    if not os.path.exists(path):
        print(f"  [SKIP] {path} not found")
        return None
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
    return rows

def savefig(name):
    path = os.path.join(RESULTS, name)
    plt.savefig(path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Saved: {name}")

# ── 1. Top URLs bar chart ─────────────────────────────────────────────────────
rows = load_csv("top_urls")
if rows:
    urls  = [r["url"][:50] for r in rows[:15]]
    hits  = [int(r["hits"]) for r in rows[:15]]
    fig, ax = plt.subplots(figsize=(12, 6))
    bars = ax.barh(urls[::-1], hits[::-1], color=PALETTE[0], alpha=0.85)
    ax.set_xlabel("Number of Requests")
    ax.set_title("Top 15 Most Requested URLs", fontsize=14, fontweight='bold')
    for bar, h in zip(bars, hits[::-1]):
        ax.text(bar.get_width() + max(hits)*0.005, bar.get_y() + bar.get_height()/2,
                f'{h:,}', va='center', fontsize=8)
    plt.tight_layout()
    savefig("top_urls.png")

# ── 2. Status code pie chart ──────────────────────────────────────────────────
rows = load_csv("status_counts")
if rows:
    labels  = [f"HTTP {r['status']}" for r in rows]
    counts  = [int(r["count"]) for r in rows]
    explode = [0.05] * len(counts)
    fig, ax = plt.subplots(figsize=(8, 8))
    wedges, texts, autotexts = ax.pie(
        counts, labels=labels, autopct='%1.1f%%',
        colors=PALETTE[:len(counts)], explode=explode,
        startangle=140, pctdistance=0.8
    )
    for t in autotexts:
        t.set_fontsize(9)
    ax.set_title("HTTP Status Code Distribution", fontsize=14, fontweight='bold')
    plt.tight_layout()
    savefig("status_pie.png")

# ── 3. Hourly traffic line chart ──────────────────────────────────────────────
rows = load_csv("hourly_traffic")
if rows:
    hours    = [int(r["hour"])     for r in rows]
    requests = [int(r["requests"]) for r in rows]
    fig, ax1 = plt.subplots(figsize=(12, 5))
    ax1.plot(hours, requests, 'o-', color=PALETTE[0], linewidth=2, markersize=6)
    ax1.fill_between(hours, requests, alpha=0.15, color=PALETTE[0])
    ax1.set_xlabel("Hour of Day (0–23)")
    ax1.set_ylabel("Number of Requests", color=PALETTE[0])
    ax1.set_title("Hourly Traffic Pattern", fontsize=14, fontweight='bold')
    ax1.set_xticks(range(0, 24))
    ax1.grid(axis='y', alpha=0.3)
    # Peak annotation
    peak_hour = hours[requests.index(max(requests))]
    ax1.axvline(peak_hour, color='red', linestyle='--', alpha=0.5,
                label=f"Peak: {peak_hour:02d}:00")
    ax1.legend()
    plt.tight_layout()
    savefig("traffic_hourly.png")

# ── 4. Top IPs bar chart ──────────────────────────────────────────────────────
rows = load_csv("top_ips")
if rows:
    ips  = [r["ip"] for r in rows[:10]]
    reqs = [int(r["requests"]) for r in rows[:10]]
    fig, ax = plt.subplots(figsize=(10, 5))
    ax.bar(range(len(ips)), reqs, color=PALETTE[3], alpha=0.85)
    ax.set_xticks(range(len(ips)))
    ax.set_xticklabels(ips, rotation=30, ha='right', fontsize=9)
    ax.set_ylabel("Number of Requests")
    ax.set_title("Top 10 IPs by Request Count", fontsize=14, fontweight='bold')
    for i, r in enumerate(reqs):
        ax.text(i, r + max(reqs)*0.01, f'{r:,}', ha='center', fontsize=8)
    plt.tight_layout()
    savefig("top_ips.png")

# ── 5. Top 404 URLs ───────────────────────────────────────────────────────────
rows = load_csv("top_404s")
if rows:
    urls   = [r["url"][:50] for r in rows[:12]]
    counts = [int(r["count"]) for r in rows[:12]]
    fig, ax = plt.subplots(figsize=(12, 5))
    ax.barh(urls[::-1], counts[::-1], color=PALETTE[6], alpha=0.85)
    ax.set_xlabel("Number of 404 Errors")
    ax.set_title("Top 404 Not Found URLs", fontsize=14, fontweight='bold')
    plt.tight_layout()
    savefig("top_404.png")

# ── 6. Bandwidth by URL ───────────────────────────────────────────────────────
rows = load_csv("bandwidth")
if rows:
    urls  = [r["url"][:40] for r in rows[:10]]
    bytes_ = [int(r["total_bytes"]) / 1024 / 1024 for r in rows[:10]]  # MB
    fig, ax = plt.subplots(figsize=(12, 5))
    ax.barh(urls[::-1], bytes_[::-1], color=PALETTE[4], alpha=0.85)
    ax.set_xlabel("Total Bandwidth (MB)")
    ax.set_title("Top 10 URLs by Bandwidth Consumed", fontsize=14, fontweight='bold')
    plt.tight_layout()
    savefig("bandwidth.png")

# ── 7. Summary table ──────────────────────────────────────────────────────────
rows = load_csv("summary")
if rows and rows:
    r = rows[0]
    fig, ax = plt.subplots(figsize=(8, 4))
    ax.axis('off')
    table_data = [
        ["Metric", "Value"],
        ["Total Log Lines",     f"{int(r.get('total_lines',0)):,}"],
        ["Clean Lines",         f"{int(r.get('clean_lines',0)):,}"],
        ["Malformed Lines",     f"{int(r.get('malformed_lines',0)):,}  ({r.get('malformed_pct','?')}%)"],
        ["Unique IPs",          f"{int(r.get('unique_ips',0)):,}"],
        ["Error Requests (4xx/5xx)", f"{int(r.get('error_requests',0)):,}  ({r.get('error_pct','?')}%)"],
        ["Total Data Transferred", f"{int(r.get('total_bytes',0))/1024/1024:.1f} MB"],
    ]
    tbl = ax.table(cellText=table_data[1:], colLabels=table_data[0],
                   cellLoc='left', loc='center', colWidths=[0.55, 0.45])
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(11)
    tbl.scale(1, 1.8)
    for (row, col), cell in tbl.get_celld().items():
        if row == 0:
            cell.set_facecolor('#2196F3')
            cell.set_text_props(color='white', fontweight='bold')
        elif row % 2 == 0:
            cell.set_facecolor('#f5f5f5')
    ax.set_title("Web Log Analytics – Summary", fontsize=14, fontweight='bold', pad=20)
    plt.tight_layout()
    savefig("summary_table.png")

print("\n✅  All charts generated in:", RESULTS)
