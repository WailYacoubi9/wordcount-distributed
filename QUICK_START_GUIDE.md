# 🚀 Quick Start Guide - Complete Testing Walkthrough

This guide will walk you through testing the distributed word count system in **3 scenarios**:
1. Local testing (your laptop/workstation)
2. Grid5000 Mono-Site testing
3. Grid5000 Multi-Site testing

---

## Part 1: Local Testing (No Grid5000 Required)

### Step 1: Clone and Setup

```bash
# Clone the repository
git clone https://github.com/WailYacoubi9/wordcount-distributed.git
cd wordcount-distributed

# Verify you have the required tools
java -version   # Should show Java 8+
gcc --version   # Should show GCC compiler

# Compile everything
bash deploy/setup.sh
```

**Expected output:**
```
Compiling Java source files...
Compilation successful!
Compiling wordcount C program...
✅ Setup complete!
```

### Step 2: Run Automated Local Test

The easiest way to test locally:

```bash
# Run comprehensive automated test
bash deploy/test_local.sh
```

**What this tests:**
- ✅ Starts 3 workers on ports 3100, 3101, 3102
- ✅ Tests static Makefile-based system
- ✅ Tests dynamic file splitting system
- ✅ Verifies FileSplitter algorithm
- ✅ Checks multi-port RMI support

**Expected output:**
```
╔══════════════════════════════════════════════════════════╗
║   LOCAL SIMULATION TEST                                  ║
╚══════════════════════════════════════════════════════════╝

TEST 1: Verifying project setup...
✅ Project setup OK

TEST 2: Simulating mono-site Grid5000 environment...
✅ Environment created

TEST 3: Starting 3 local workers...
✅ All 3 workers running and ready

TEST 4: Testing static system (Main.java)...
✅ Static system executed
   Result: 75000 words
✅ Correct result!

...

✅ All tests PASSED!
```

### Step 3: Manual Local Testing (Alternative)

If you want to test manually:

**Terminal 1 - Worker 1:**
```bash
cd wordcount-distributed
java -cp bin network.worker.WorkerNode localhost 3000
```

**Terminal 2 - Worker 2:**
```bash
cd wordcount-distributed
java -cp bin network.worker.WorkerNode localhost 3001
```

**Terminal 3 - Worker 3:**
```bash
cd wordcount-distributed
java -cp bin network.worker.WorkerNode localhost 3002
```

**Terminal 4 - Run Static System:**
```bash
cd wordcount-distributed
java -cp bin scheduler.Main "[localhost:3000,localhost:3001,localhost:3002]"
```

**OR - Run Dynamic System with your own file:**
```bash
# Create a test file
echo "Hello world from distributed systems" > mytest.txt

# Run dynamic system
java -cp bin scheduler.DynamicMain mytest.txt "[localhost:3000,localhost:3001,localhost:3002]"
```

**To stop workers:** Press `Ctrl+C` in each worker terminal

---

## Part 2: Grid5000 Setup (One-Time Configuration)

### Prerequisites

1. **Grid5000 Account**: Apply at https://www.grid5000.fr/w/Grid5000:Get_an_account
2. **SSH Key Setup**

### SSH Key Configuration

#### Step 1: Generate SSH Key (if you don't have one)

```bash
# On your local machine
ssh-keygen -t rsa -b 4096 -C "your.email@example.com"

# Press Enter to accept default location (~/.ssh/id_rsa)
# Enter a passphrase (recommended) or leave empty
```

#### Step 2: Copy SSH Key to Grid5000

```bash
# Copy your public key to Grid5000 access machine
ssh-copy-id <your-username>@access.grid5000.fr

# Test the connection
ssh <your-username>@access.grid5000.fr
```

**If ssh-copy-id doesn't work:**
```bash
# Manually copy the key
cat ~/.ssh/id_rsa.pub | ssh <your-username>@access.grid5000.fr "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

#### Step 3: Configure SSH Config (Optional but Recommended)

Create/edit `~/.ssh/config`:

```
Host grid5000
    HostName access.grid5000.fr
    User <your-username>
    ForwardAgent yes

Host *.grid5000.fr
    User <your-username>
    ProxyJump grid5000
    ForwardAgent yes
```

Now you can connect with: `ssh grid5000`

### Step 4: Clone Project on Grid5000

```bash
# Connect to Grid5000
ssh <your-username>@access.grid5000.fr

# Choose a site (e.g., Nancy)
ssh nancy

# Clone the project
git clone https://github.com/WailYacoubi9/wordcount-distributed.git
cd wordcount-distributed

# Setup (compile everything)
bash deploy/setup.sh
```

---

## Part 3: Grid5000 Mono-Site Testing

**Scenario:** All nodes on the **same site** (e.g., all on Nancy)

### Step 1: Connect to a Grid5000 Site

```bash
# From your local machine
ssh <your-username>@access.grid5000.fr

# Connect to Nancy site (or any other site)
ssh nancy
```

### Step 2: Reserve Nodes

**Option A: Interactive Reservation (Recommended for testing)**

```bash
# Reserve 5 nodes for 1 hour
oarsub -I -l nodes=5,walltime=1:00:00
```

You'll get an interactive shell on the first node when reservation starts.

**Option B: Non-Interactive Reservation**

```bash
# Reserve and run script automatically
oarsub -l nodes=5,walltime=1:00:00 "cd ~/wordcount-distributed && bash deploy/run_mono_site.sh"
```

### Step 3: Verify Your Reservation

```bash
# Check your reservation
oarstat -u

# View assigned nodes
echo $OAR_NODEFILE
cat $OAR_NODEFILE

# Example output:
# graphene-1.nancy.grid5000.fr
# graphene-2.nancy.grid5000.fr
# graphene-3.nancy.grid5000.fr
# graphene-4.nancy.grid5000.fr
# graphene-5.nancy.grid5000.fr
```

**Important:** All nodes should be from the **same site** (nancy, lyon, etc.)

### Step 4: Run Mono-Site Test

```bash
# Navigate to project
cd ~/wordcount-distributed

# Run mono-site deployment
bash deploy/run_mono_site.sh
```

### Expected Output

```
╔══════════════════════════════════════════════════════════╗
║   MONO-SITE DISTRIBUTED WORD COUNT                      ║
╚══════════════════════════════════════════════════════════╝

📍 Site: nancy
🖥️  Master node: graphene-1.nancy.grid5000.fr

👷 Worker nodes:
  - graphene-2.nancy.grid5000.fr
  - graphene-3.nancy.grid5000.fr
  - graphene-4.nancy.grid5000.fr
  - graphene-5.nancy.grid5000.fr

Total workers: 4

🔍 Verifying mono-site deployment...
✅ All nodes confirmed on site: nancy

📦 Copying files to worker nodes...
  - Copying to graphene-2.nancy.grid5000.fr...
  - Copying to graphene-3.nancy.grid5000.fr...
  - Copying to graphene-4.nancy.grid5000.fr...
  - Copying to graphene-5.nancy.grid5000.fr...
✅ Files copied successfully

🚀 Starting worker nodes...
  - Starting worker on graphene-2.nancy.grid5000.fr...
  - Starting worker on graphene-3.nancy.grid5000.fr...
  - Starting worker on graphene-4.nancy.grid5000.fr...
  - Starting worker on graphene-5.nancy.grid5000.fr...

⏳ Waiting for workers to initialize...

╔══════════════════════════════════════════════════════════╗
║   STARTING DISTRIBUTED EXECUTION                        ║
╚══════════════════════════════════════════════════════════╝

[SCHEDULER] Starting task execution...
[SCHEDULER] Iteration 1 - Launching 6 tasks in parallel...
[TASK count1.txt] ✅ Completed on graphene-2.nancy.grid5000.fr
[TASK count2.txt] ✅ Completed on graphene-3.nancy.grid5000.fr
...

═══════════════════════════════════════════════════════════
✅ Execution completed successfully!
═══════════════════════════════════════════════════════════

📊 RESULTS:
  Total word count: 75000

  Individual counts:
    - part1.txt: 15000 words
    - part2.txt: 15000 words
    - part3.txt: 15000 words
    - part4.txt: 15000 words
    - part5.txt: 15000 words
```

### Step 5: Test Dynamic System (Optional)

```bash
# Create a custom test file
echo "This is a test of the dynamic word count system" > myfile.txt
echo "It automatically splits files equitably among workers" >> myfile.txt

# Run dynamic system
bash deploy/run_dynamic.sh myfile.txt mono
```

### Step 6: Cleanup

```bash
# The script automatically cleans up workers
# To release your reservation early:
oardel <job-id>

# Or just exit (reservation expires automatically)
exit
```

---

## Part 4: Grid5000 Multi-Site Testing

**Scenario:** Nodes distributed across **multiple sites** (e.g., Nancy + Lyon + Toulouse)

### Step 1: Reserve Nodes on Multiple Sites

**Option A: Using oargridsub (Recommended)**

```bash
# From Grid5000 frontend (access.grid5000.fr)
ssh <your-username>@access.grid5000.fr

# Reserve nodes on 2 sites (Nancy and Lyon)
oargridsub -w 1:00:00 \
  nancy:rdef="/nodes=2" \
  lyon:rdef="/nodes=2"
```

**Expected output:**
```
[OAR] Reservations created:
  - Nancy: Job 12345 (2 nodes)
  - Lyon: Job 67890 (2 nodes)
```

**Option B: Manual Reservation (Advanced)**

**Terminal 1 - Nancy:**
```bash
ssh nancy.grid5000.fr
oarsub -I -l nodes=2,walltime=1:00:00
# Note the job ID
```

**Terminal 2 - Lyon:**
```bash
ssh lyon.grid5000.fr
oarsub -I -l nodes=2,walltime=1:00:00
# Note the job ID
```

Then manually combine the OAR_NODEFILE from both sites.

### Step 2: Connect to Master Site

```bash
# Connect to the first site in your reservation (e.g., Nancy)
ssh nancy.grid5000.fr

# Find your Grid job and connect
oarsub -C <job-id>
```

### Step 3: Verify Multi-Site Reservation

```bash
# Check the nodefile
echo $OAR_NODEFILE
cat $OAR_NODEFILE

# Expected output (nodes from MULTIPLE sites):
# graphene-1.nancy.grid5000.fr
# graphene-2.nancy.grid5000.fr
# chiclet-1.lyon.grid5000.fr
# chiclet-2.lyon.grid5000.fr
```

**Important:** Nodes should be from **different sites** (nancy, lyon, etc.)

### Step 4: Run Multi-Site Test

```bash
cd ~/wordcount-distributed
bash deploy/run_multi_site.sh
```

### Expected Output

```
╔══════════════════════════════════════════════════════════╗
║   MULTI-SITE DISTRIBUTED WORD COUNT                     ║
╚══════════════════════════════════════════════════════════╝

📍 Master site: nancy
🖥️  Master node: graphene-1.nancy.grid5000.fr

🗺️  Analyzing site distribution...

Sites involved:
  ✓ nancy: 2 node(s) [MASTER SITE]
  → lyon: 2 node(s)

✅ Multi-site deployment confirmed (2 sites)

👷 Worker nodes by site:
  [nancy] graphene-2.nancy.grid5000.fr
  [lyon] chiclet-1.lyon.grid5000.fr
  [lyon] chiclet-2.lyon.grid5000.fr

Total workers: 3 across 2 sites

📡 Multi-site network information:
  - Nodes use fully qualified domain names (FQDN)
  - RMI communication may require specific network configuration
  - Latency between sites: typically 1-10ms depending on sites

📦 Copying files to worker nodes (this may take longer for remote sites)...
  - [nancy] Copying to graphene-2.nancy.grid5000.fr...
  - [lyon] Copying to chiclet-1.lyon.grid5000.fr...
  - [lyon] Copying to chiclet-2.lyon.grid5000.fr...
✅ Files copied to all sites

🚀 Starting worker nodes across all sites...
  - [nancy] Starting worker on graphene-2.nancy.grid5000.fr...
  - [lyon] Starting worker on chiclet-1.lyon.grid5000.fr...
  - [lyon] Starting worker on chiclet-2.lyon.grid5000.fr...

⏳ Waiting for workers to initialize across all sites...

╔══════════════════════════════════════════════════════════╗
║   STARTING MULTI-SITE DISTRIBUTED EXECUTION             ║
╚══════════════════════════════════════════════════════════╝

⚠️  Note: Inter-site communication may show increased latency

[SCHEDULER] Starting task execution...
[SCHEDULER] Iteration 1 - Launching 6 tasks in parallel...
[TASK count1.txt] ✅ Completed on graphene-2.nancy.grid5000.fr
[TASK count2.txt] ✅ Completed on chiclet-1.lyon.grid5000.fr
[TASK count3.txt] ✅ Completed on chiclet-2.lyon.grid5000.fr
...

═══════════════════════════════════════════════════════════
✅ Multi-site execution completed successfully!
═══════════════════════════════════════════════════════════
Total execution time: 12s

📊 RESULTS:
  Total word count: 75000

🌐 Multi-site performance:
  Sites involved: 2
  Workers: 3
  Execution time: 12s
```

**Note:** Multi-site execution is typically slower due to network latency between sites.

### Step 5: Compare Performance

Run both mono-site and multi-site and compare:

```bash
# Mono-site: ~5-10s
# Multi-site: ~10-15s

# The difference is due to:
# - Inter-site network latency (1-10ms vs 0.1ms)
# - File transfer time across sites
```

---

## Part 5: Troubleshooting

### Problem: "Permission denied (publickey)"

**Solution:**
```bash
# Verify SSH key is added
ssh-add -l

# Add your key if needed
ssh-add ~/.ssh/id_rsa

# Verify connection
ssh -v <your-username>@access.grid5000.fr
```

### Problem: "OAR_NODEFILE not found"

**Solution:** You need an active reservation
```bash
# Check your reservations
oarstat -u

# Create a new reservation
oarsub -I -l nodes=5,walltime=1:00:00
```

### Problem: "Failed to copy files to node"

**Solutions:**
1. **Check SSH access:**
   ```bash
   ssh <node-name>
   ```

2. **Check network:**
   ```bash
   ping <node-name>
   ```

3. **Verify Grid5000 status:**
   ```bash
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

**Solution:**
```bash
# Kill existing workers
for node in $(cat $OAR_NODEFILE); do
  ssh $node "pkill -f java"
done
```

### Problem: Windows Line Ending Errors (CRLF vs LF)

**Error symptoms:**
```
test_local.sh: line 4: $'\r': command not found
: invalid optionine 5: set: -
test_local.sh: line 14: syntax error near unexpected token `$'{\r''
```

**Cause:** Shell scripts have Windows line endings (CRLF) instead of Unix line endings (LF).

**Solution 1 - Automatic (Recommended):**

The repository now includes a `.gitattributes` file that automatically handles line endings. To fix your local copy:

```bash
# Remove all files from Git's index (doesn't delete them)
git rm --cached -r .

# Re-add all files (Git will normalize line endings)
git reset --hard

# If the above doesn't work, try:
git config core.autocrlf false
git rm --cached -r .
git reset --hard
```

**Solution 2 - Manual conversion with dos2unix:**

If you have Git Bash on Windows, use `dos2unix`:

```bash
# Install dos2unix (if not available)
# Download from: https://sourceforge.net/projects/dos2unix/

# Convert all shell scripts
find . -name "*.sh" -exec dos2unix {} \;
```

**Solution 3 - Manual conversion with sed:**

```bash
# For Git Bash on Windows
find . -name "*.sh" -exec sed -i 's/\r$//' {} \;
```

**Solution 4 - Use WSL (Windows Subsystem for Linux):**

The most reliable solution for Windows users is to use WSL:

```bash
# In PowerShell (run as Administrator)
wsl --install

# After WSL is installed, restart and open Ubuntu
# Clone the repository in WSL:
cd ~
git clone https://github.com/WailYacoubi9/wordcount-distributed.git
cd wordcount-distributed

# Run tests in WSL - scripts will work perfectly
bash deploy/test_local.sh
```

**Prevention:**

After fixing line endings, configure Git to prevent future issues:

```bash
# On Windows, use this setting
git config --global core.autocrlf true

# This converts CRLF to LF on commit, and LF to CRLF on checkout for text files
# But .gitattributes overrides this for .sh files to always use LF
```

### Problem: "Only 1 site detected" in multi-site script

**This means all nodes are on the same site.**

**Solutions:**
- Use `run_mono_site.sh` instead
- Reserve nodes on multiple sites with `oargridsub`

---

## Part 6: Tips and Best Practices

### Reservation Tips

1. **Walltime:** Start with 30 minutes for testing
   ```bash
   oarsub -I -l nodes=5,walltime=0:30:00
   ```

2. **Extend reservation:** If you need more time
   ```bash
   oarwalltime <job-id> +30
   ```

3. **Check site availability:**
   ```bash
   # See available resources
   oarstat -f
   ```

### Testing Tips

1. **Start small:** Test with 3-5 nodes first
2. **Use interactive mode:** `-I` flag for debugging
3. **Check logs:** Always check worker.log files
4. **Test locally first:** Use `test_local.sh` before Grid5000

### Performance Tips

1. **Node selection:** Prefer same cluster for mono-site
2. **Network bandwidth:** Multi-site has ~10x higher latency
3. **File size:** Larger files show better speedup
4. **Worker count:** Optimal is usually 4-10 workers

---

## Part 7: Quick Reference Commands

### Local Testing
```bash
# Automated test
bash deploy/test_local.sh

# Manual worker
java -cp bin network.worker.WorkerNode localhost 3000

# Run static system
java -cp bin scheduler.Main "[localhost:3000,localhost:3001]"

# Run dynamic system
java -cp bin scheduler.DynamicMain file.txt "[localhost:3000,localhost:3001]"
```

### Grid5000 - Mono-Site
```bash
# Reserve nodes
oarsub -I -l nodes=5,walltime=1:00:00

# Run test
cd ~/wordcount-distributed
bash deploy/run_mono_site.sh
```

### Grid5000 - Multi-Site
```bash
# Reserve multi-site
oargridsub -w 1:00:00 nancy:rdef="/nodes=2" lyon:rdef="/nodes=2"

# Connect to master site
ssh nancy.grid5000.fr
oarsub -C <job-id>

# Run test
cd ~/wordcount-distributed
bash deploy/run_multi_site.sh
```

### Cleanup
```bash
# Kill all workers
pkill -f "java.*WorkerNode"

# Release reservation
oardel <job-id>

# Or just exit
exit
```

---

## Part 8: Expected Results Summary

| Test Type | Workers | Expected Time | Expected Result |
|-----------|---------|---------------|-----------------|
| Local Simulation | 3 | ~10s | 75000 words ✅ |
| Mono-Site (Nancy) | 4 | ~5-10s | 75000 words ✅ |
| Multi-Site (2 sites) | 4 | ~10-15s | 75000 words ✅ |
| Multi-Site (3+ sites) | 4 | ~15-25s | 75000 words ✅ |
| Dynamic (custom file) | Any | Varies | Correct count ✅ |

---

## Need More Help?

- **Detailed Grid5000 guide:** See `GRID5000_TESTING.md`
- **Architecture details:** See `docs/ARCHITECTURE.md`
- **Grid5000 wiki:** https://www.grid5000.fr/w/Getting_Started
- **Grid5000 status:** https://www.grid5000.fr/w/Status

---

**You're now ready to test the distributed word count system! 🚀**

Start with local testing, then move to Grid5000 mono-site, and finally multi-site for complete validation.
