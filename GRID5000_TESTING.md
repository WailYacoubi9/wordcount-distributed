# Grid5000 Testing Guide

## Overview

This guide covers testing the distributed word count system on Grid5000 in both **mono-site** and **multi-site** configurations.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Mono-Site Testing](#mono-site-testing)
3. [Multi-Site Testing](#multi-site-testing)
4. [Dynamic System Testing](#dynamic-system-testing)
5. [Troubleshooting](#troubleshooting)
6. [Performance Analysis](#performance-analysis)

---

## Prerequisites

### 1. Setup the Project

```bash
# Clone and setup
cd ~/wordcount-distributed
bash deploy/setup.sh
```

This compiles all Java classes and generates test data.

### 2. Grid5000 Access

Ensure you have:
- Valid Grid5000 account
- SSH access configured
- Access to at least one site (two for multi-site testing)

---

## Mono-Site Testing

### Scenario 1: All nodes on the same site

This tests the system with master and all workers on a single Grid5000 site (e.g., all on Nancy).

### Step 1: Reserve Nodes

```bash
# Interactive reservation (recommended for testing)
oarsub -I -l nodes=5,walltime=1:00:00

# Non-interactive
oarsub -l nodes=5,walltime=1:00:00 "cd ~/wordcount-distributed && bash deploy/run_mono_site.sh"
```

**Verification:**
```bash
# Check your reservation
echo $OAR_NODEFILE
cat $OAR_NODEFILE

# Should show 5 nodes from the same site, e.g.:
# nancy-1.nancy.grid5000.fr
# nancy-2.nancy.grid5000.fr
# nancy-3.nancy.grid5000.fr
# nancy-4.nancy.grid5000.fr
# nancy-5.nancy.grid5000.fr
```

### Step 2: Run the Test

```bash
cd ~/wordcount-distributed
bash deploy/run_mono_site.sh
```

**What it does:**
1. ✅ Verifies all nodes are on the same site
2. 📦 Distributes files to all workers
3. 🚀 Starts worker processes
4. 📊 Executes the word count with static Makefile
5. 📈 Reports results and performance
6. 🛑 Cleans up worker processes

**Expected output:**
```
╔══════════════════════════════════════════════════════════╗
║   MONO-SITE DISTRIBUTED WORD COUNT                      ║
╚══════════════════════════════════════════════════════════╝

📍 Site: nancy
🖥️  Master node: nancy-1.nancy.grid5000.fr
...
✅ Execution completed successfully!

📊 RESULTS:
  Total word count: 75000
```

### Step 3: Analyze Results

The script provides:
- **Site verification** - Confirms mono-site deployment
- **File distribution** - Shows files copied to each worker
- **Execution logs** - Real-time task distribution
- **Performance metrics** - Total execution time

---

## Multi-Site Testing

### Scenario 2: Nodes distributed across multiple sites

This tests inter-site communication and handles network latency between Grid5000 sites.

### Step 1: Reserve Nodes on Multiple Sites

#### Option A: Using oargridsub (recommended)

```bash
# Reserve 2 nodes on Nancy and 2 on Lyon
oargridsub -w 1:00:00 \
  nancy:rdef="/nodes=2" \
  lyon:rdef="/nodes=2"
```

#### Option B: Manual reservation on each site

```bash
# Terminal 1 - Nancy site
ssh nancy.grid5000.fr
oarsub -I -l nodes=2,walltime=1:00:00

# Terminal 2 - Lyon site
ssh lyon.grid5000.fr
oarsub -I -l nodes=2,walltime=1:00:00

# Combine nodefiles manually (advanced)
```

**Verification:**
```bash
cat $OAR_NODEFILE

# Should show nodes from different sites:
# nancy-1.nancy.grid5000.fr
# nancy-2.nancy.grid5000.fr
# lyon-1.lyon.grid5000.fr
# lyon-2.lyon.grid5000.fr
```

### Step 2: Run Multi-Site Test

```bash
cd ~/wordcount-distributed
bash deploy/run_multi_site.sh
```

**What it does:**
1. 🗺️  Analyzes site distribution
2. ✅ Verifies multi-site deployment (warns if only 1 site)
3. 📦 Distributes files across sites (may take longer)
4. 📡 Starts workers on all sites
5. ⏱️  Executes with inter-site communication tracking
6. 📊 Reports performance including latency impact

**Expected output:**
```
╔══════════════════════════════════════════════════════════╗
║   MULTI-SITE DISTRIBUTED WORD COUNT                     ║
╚══════════════════════════════════════════════════════════╝

🗺️  Analyzing site distribution...

Sites involved:
  ✓ nancy: 2 node(s) [MASTER SITE]
  → lyon: 2 node(s)

✅ Multi-site deployment confirmed (2 sites)
...
Total execution time: 15s

🌐 Multi-site performance:
  Sites involved: 2
  Workers: 3
  Execution time: 15s
```

### Step 3: Performance Analysis

Multi-site deployments show:
- **Increased latency** - Inter-site communication adds 1-10ms per RMI call
- **File transfer time** - Initial scp takes longer across sites
- **Network topology** - Grid5000 backbone between sites

**Typical latencies:**
- Same site (mono): ~0.1ms
- Nancy ↔ Lyon: ~5ms
- Nancy ↔ Toulouse: ~8ms
- Lyon ↔ Sophia: ~10ms

---

## Dynamic System Testing

### Using DynamicMain with automatic file splitting

The dynamic system accepts **any input file** and automatically divides it equitably among workers.

### Mono-Site Dynamic Test

```bash
# Reserve nodes
oarsub -I -l nodes=5,walltime=1:00:00

# Run with your own file
cd ~/wordcount-distributed
bash deploy/run_dynamic.sh my-large-corpus.txt mono
```

### Multi-Site Dynamic Test

```bash
# Reserve multi-site nodes
oargridsub -w 1:00:00 nancy:rdef="/nodes=2" lyon:rdef="/nodes=2"

# Run with automatic file splitting
cd ~/wordcount-distributed
bash deploy/run_dynamic.sh my-data.txt multi
```

**Advantages:**
- ✅ Works with ANY text file
- ✅ Automatic equitable load balancing
- ✅ Adapts to N workers automatically
- ✅ No pre-processing needed

**Output example:**
```
📄 Input file: corpus.txt
   Size: 10485760 bytes
   Lines: 50000

📊 Expected load distribution:
   Lines per worker: ~12500
   (System will auto-balance with max ±1 line difference)

✅ Dynamic execution completed successfully!

⏱️  Performance metrics:
   Input: 50000 lines, 10485760 bytes
   Workers: 4 across 2 site(s)
   Execution time: 23s
   Throughput: 2173 lines/sec
```

---

## Troubleshooting

### Problem: "OAR_NODEFILE not found"

**Solution:** You need an active OAR reservation:
```bash
oarsub -I -l nodes=5,walltime=1:00:00
```

### Problem: "Failed to copy files to node"

**Possible causes:**
1. SSH keys not configured
2. Network connectivity issue
3. Node unreachable

**Solution:**
```bash
# Test SSH access
ssh <node-name>

# Check network
ping <node-name>

# Verify Grid5000 status
g5k-checks
```

### Problem: Workers not starting

**Check worker logs:**
```bash
# On each worker node
ssh <worker-node>
cat ~/worker.log
```

**Common issues:**
- Port already in use (kill existing Java processes)
- Java not in PATH
- RMI registry creation failed

### Problem: Multi-site communication failing

**Verify:**
1. Nodes can reach each other:
   ```bash
   ssh nancy-node
   ping lyon-node.lyon.grid5000.fr
   ```

2. RMI port 3000 is open:
   ```bash
   telnet <remote-node> 3000
   ```

3. Grid5000 firewall rules allow RMI

### Problem: "Only 1 site detected" in multi-site script

This means all your nodes are on the same site. Either:
- Use `run_mono_site.sh` instead
- Reserve nodes on multiple sites with `oargridsub`

---

## Performance Analysis

### Metrics to Compare

#### 1. Mono-Site vs Multi-Site

| Metric | Mono-Site | Multi-Site |
|--------|-----------|------------|
| Network latency | ~0.1ms | 1-10ms |
| File transfer | Fast (local) | Slower (inter-site) |
| RMI calls | Very fast | Moderate |
| Total overhead | Minimal | +20-50% |

#### 2. Static vs Dynamic

| System | Pros | Cons |
|--------|------|------|
| Static (Makefile) | Complex dependencies, fixed workflow | Requires pre-split files |
| Dynamic (DynamicMain) | Any file, auto-balancing | No dependency management |

### Benchmarking Commands

```bash
# Mono-site benchmark
time bash deploy/run_mono_site.sh

# Multi-site benchmark
time bash deploy/run_multi_site.sh

# Dynamic with large file
time bash deploy/run_dynamic.sh huge-corpus.txt
```

### Expected Performance

**Test data (75000 words, 5 parts):**
- **Mono-site:** ~5-10s
- **Multi-site (2 sites):** ~10-15s
- **Multi-site (3+ sites):** ~15-25s

**Large corpus (1GB, 10M words):**
- **Mono-site, 10 workers:** ~30-60s
- **Multi-site, 10 workers (2 sites):** ~45-90s

---

## Best Practices

### 1. Site Selection

- **Same datacenter sites** (Nancy-Luxembourg): Lower latency
- **Distant sites** (Nancy-Sophia): Higher latency but tests resilience

### 2. Node Count

- **Minimum:** 3 nodes (1 master + 2 workers)
- **Recommended:** 5+ nodes for load balancing tests
- **Maximum:** Limited by OAR quota

### 3. Walltime

- **Short tests:** 30 minutes sufficient
- **Large corpus:** Allow 1-2 hours
- **Benchmarking:** 2+ hours for comprehensive tests

### 4. Cleanup

Always cleanup after testing:
```bash
# Kill any remaining processes
oardel <job-id>

# Or manually
for node in $(cat $OAR_NODEFILE); do
  ssh $node "pkill -f java"
done
```

---

## Summary

You now have **4 deployment scripts**:

1. **`run_distributed.sh`** - Original static system (basic)
2. **`run_mono_site.sh`** - Mono-site with verification ✨
3. **`run_multi_site.sh`** - Multi-site with latency tracking ✨
4. **`run_dynamic.sh`** - Dynamic with any input file ✨

**Recommended testing sequence:**
1. Start with mono-site (simpler, faster)
2. Verify correct results
3. Move to multi-site (test network resilience)
4. Test dynamic system with custom files

Good luck with your Grid5000 experiments! 🚀
