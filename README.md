# Distributed Web Log Analytics on a 3-Node Hadoop Cluster

A Big Data Systems project that processes NASA HTTP access logs (200 MB+) using
**HDFS** for distributed storage and **Apache Spark on YARN** for parallel analytics,
deployed across a 3-node Ubuntu cluster.

---

## Cluster Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         master (192.168.x.100)                  │
│   NameNode · SecondaryNameNode · ResourceManager · Spark Driver │
└───────────────────┬─────────────────────┬───────────────────────┘
                    │ SSH + HDFS RPC       │
       ┌────────────▼──────┐   ┌──────────▼────────────┐
       │  worker1           │   │  worker2               │
       │  DataNode          │   │  DataNode              │
       │  NodeManager       │   │  NodeManager           │
       │  Spark Executor    │   │  Spark Executor        │
       └────────────────────┘   └────────────────────────┘
```

HDFS replication = 2 (each block stored on both workers).

---

## Data Flow

```
Raw logs → HDFS /logs/raw
         → Spark parse+clean
         → Parquet (partitioned by date)  /logs/parquet
         → Spark SQL analytics
         → CSV results                    /logs/output
         → Python charts                  results/*.png
```

---

## Manual Setup (before running any script)

| Step | What to do |
|------|-----------|
| 1 | Create **3 Ubuntu 22.04 VMs** (4 GB RAM, 2 vCPUs each) in VirtualBox/VMware |
| 2 | Set hostnames: `sudo hostnamectl set-hostname master` (and worker1, worker2) |
| 3 | Create user: `sudo adduser hadoop && sudo usermod -aG sudo hadoop` |
| 4 | Note the IP of each VM with `ip a` |
| 5 | Clone this repo on all 3 VMs: `git clone <repo-url> web-log-analytics-hadoop` |
| 6 | **Edit `config/cluster.env`** with your 3 IPs |
| 7 | Run the numbered scripts in order (see below) |

---

## Step-by-Step Execution

### Step 1 – Setup every node
Run on **master, worker1, worker2** (run independently on each):
```bash
./scripts/01_setup_node.sh
source ~/.bashrc
hadoop version    # verify
```
Installs Java 11, SSH, downloads Hadoop 3.3.6, sets env vars, creates data dirs.

---

### Step 2 – SSH + config push  *(master only)*
```bash
./scripts/02_ssh_and_config.sh
ssh worker1 hostname   # must print 'worker1' – no password prompt
```
Generates SSH key pair, distributes to all nodes, pushes 5 Hadoop config files.

---

### Step 3 – Start HDFS + YARN  *(master only)*
```bash
./scripts/03_start_cluster.sh
```
Formats NameNode (first run), starts all daemons, creates HDFS directories.

📸 **Screenshot:** `http://master:9870` (2 live DataNodes) and `http://master:8088`

---

### Step 4 – Install Spark  *(master only)*
```bash
./scripts/04_install_spark.sh
source ~/.bashrc
spark-submit --version
```
Downloads Spark 3.5.1, uploads JARs to HDFS, installs Python deps.

---

### Step 5 – Load data into HDFS  *(master only)*
```bash
./scripts/05_load_data.sh nasa              # real NASA logs (~200 MB)
# OR
./scripts/05_load_data.sh synthetic 500    # 500 MB synthetic logs
```
📸 **Screenshot:** `hdfs fsck /logs/raw -blocks -locations` (should show 2 replicas)

---

### Step 6 – Run Spark analytics  *(master only)*
```bash
./scripts/06_run_analytics.sh 2    # 2 executors
```
Parses, cleans, writes Parquet, runs 7 SQL queries, writes CSVs to HDFS.

📸 **Screenshot:** YARN app page showing executors on both workers.

---

### Step 7 – Fetch results and charts  *(master only)*
```bash
./scripts/07_fetch_results.sh
```
Downloads CSVs from HDFS, generates 7 PNG charts in `results/`.

Copy to your laptop:
```bash
scp hadoop@master:~/web-log-analytics-hadoop/results/*.png .
```

---

### Step 8 – Performance benchmark  *(master only)*
```bash
./scripts/08_benchmark.sh          # runs with 1, 2, 4 executors
./scripts/09_mapreduce_compare.sh  # MapReduce vs Spark
```
Produces `results/benchmark_speedup.png` and `results/mr_vs_spark.png`.

---

### Step 9 – Fault tolerance demo  *(master only)*
```bash
./scripts/10_fault_tolerance_demo.sh
```
Kills worker2's DataNode, proves data is still readable, then restores it.

---

### Step 10 – Shut down
```bash
stop-yarn.sh && stop-dfs.sh
```

---

## Output Files

| File | Description |
|------|-------------|
| `results/top_urls.png` | Top 15 most requested pages |
| `results/status_pie.png` | HTTP status code split |
| `results/traffic_hourly.png` | Requests per hour (peak traffic) |
| `results/top_ips.png` | Top 10 IPs by request count |
| `results/top_404.png` | Most common 404 pages |
| `results/bandwidth.png` | URLs consuming most bandwidth |
| `results/summary_table.png` | Key metrics overview |
| `results/benchmark_speedup.png` | Scalability: 1/2/4 executors |
| `results/mr_vs_spark.png` | MapReduce vs Spark runtime |

---

## Config Reference

| File | Key Setting | Meaning |
|------|-------------|---------|
| `core-site.xml` | `fs.defaultFS=hdfs://master:9000` | HDFS entrypoint |
| `hdfs-site.xml` | `dfs.replication=2` | 2 block copies |
| `hdfs-site.xml` | `dfs.blocksize=64MB` | Block size |
| `yarn-site.xml` | `nodemanager.resource.memory=3072MB` | YARN budget per node |
| `mapred-site.xml` | `framework.name=yarn` | MR runs on YARN |
| `workers` | `worker1, worker2` | Which nodes run DataNode+NM |

---

## Common Fixes

| Problem | Fix |
|---------|-----|
| SSH asks for password | `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`, redo Step 2 |
| DataNode dies after re-format | `rm -rf /opt/hadoop/data/datanode/*` on that worker |
| Only 1 live DataNode | Check `/etc/hosts`, run `sudo ufw disable`, verify configs match |
| Container killed (OOM) | Lower `--executor-memory` in `06_run_analytics.sh` |
| Timestamps are NULL | Add `--conf spark.sql.legacy.timeParserPolicy=LEGACY` |
| NameNode in safe mode | `hdfs dfsadmin -safemode leave` |

---

## Tech Stack

- **Hadoop 3.3.6** – HDFS + YARN
- **Apache Spark 3.5.1** – PySpark DataFrame API
- **Python 3** – pandas, matplotlib, numpy
- **Ubuntu 22.04** – OS on all 3 VMs
- **Parquet** – columnar output format
- **Hadoop Streaming** – MapReduce comparison job
