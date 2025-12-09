#!/bin/bash
set -e  # Exit on error

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   MULTI-SITE DISTRIBUTED WORD COUNT                     ║"
echo "║   Nodes distributed across multiple Grid5000 sites      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check if running in Grid5000 environment
if [ -z "$OAR_NODEFILE" ]; then
    echo "❌ Error: OAR_NODEFILE not found"
    echo ""
    echo "For multi-site deployment on Grid5000:"
    echo ""
    echo "1. Reserve nodes on multiple sites using oargridsub:"
    echo "   oargridsub -w 1:00:00 nancy:rdef=\"/nodes=2\",lyon:rdef=\"/nodes=2\""
    echo ""
    echo "2. Or manually reserve on each site and combine nodefiles:"
    echo "   # On site 1:"
    echo "   oarsub -I -l nodes=2"
    echo "   # On site 2:"
    echo "   oarsub -I -l nodes=2"
    echo "   # Then combine OAR_NODEFILE from both"
    exit 1
fi

# ==================== COMPILE JAVA CODE ====================

echo "🔨 Compiling Java code..."
javac -d bin src/config/*.java src/cluster/*.java src/utils/*.java \
      src/parser/*.java src/network/worker/*.java \
      src/network/master/*.java src/scheduler/*.java

if [ $? -eq 0 ]; then
    echo "✅ Java compilation successful"
else
    echo "❌ Java compilation failed"
    exit 1
fi
echo ""

# Compile wordcount binary
if [ ! -f "wordcount" ] || [ "test/wordcount.c" -nt "wordcount" ]; then
    echo "🔨 Compiling wordcount binary..."
    gcc -o wordcount test/wordcount.c
    echo "✅ Wordcount compiled"
fi
echo ""

# Get node information
HOSTNAMES=$(uniq $OAR_NODEFILE)
MASTER_NODE=$(hostname)
MASTER_SITE=$(hostname | cut -d'.' -f2)

echo "📍 Master site: $MASTER_SITE"
echo "🖥️  Master node: $MASTER_NODE"
echo ""

# Analyze site distribution
echo "🗺️  Analyzing site distribution..."
declare -A SITES
for hostname in $HOSTNAMES; do
    SITE=$(echo $hostname | cut -d'.' -f2)
    if [ -z "${SITES[$SITE]}" ]; then
        SITES[$SITE]=1
    else
        SITES[$SITE]=$((${SITES[$SITE]} + 1))
    fi
done

echo ""
echo "Sites involved:"
for site in "${!SITES[@]}"; do
    count=${SITES[$site]}
    if [ "$site" == "$MASTER_SITE" ]; then
        echo "  ✓ $site: $count node(s) [MASTER SITE]"
    else
        echo "  → $site: $count node(s)"
    fi
done

# Verify multi-site deployment
SITE_COUNT=${#SITES[@]}
if [ $SITE_COUNT -lt 2 ]; then
    echo ""
    echo "⚠️  Warning: Only 1 site detected"
    echo "This appears to be a mono-site deployment."
    echo "Consider using run_mono_site.sh instead."
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo ""
    echo "✅ Multi-site deployment confirmed ($SITE_COUNT sites)"
fi

echo ""
echo "👷 Worker nodes by site:"
TOTAL_WORKERS=0
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        SITE=$(echo $hostname | cut -d'.' -f2)
        echo "  [$SITE] $hostname"
        TOTAL_WORKERS=$((TOTAL_WORKERS + 1))
    fi
done
echo ""
echo "Total workers: $TOTAL_WORKERS across $SITE_COUNT sites"
echo ""

# Important: Multi-site network considerations
echo "📡 Multi-site network information:"
echo "  - Nodes use fully qualified domain names (FQDN)"
echo "  - RMI communication may require specific network configuration"
echo "  - Latency between sites: typically 1-10ms depending on sites"
echo ""

# ==================== COMPRESSION & TRANSFER ====================

echo "📦 Preparing files for multi-site transfer with compression..."

# Create temporary archive with all necessary files
ARCHIVE_NAME="wordcount_deployment.tar.gz"
echo "  🗜️  Compressing files (bin/, wordcount, test/, Makefile)..."

# Get sizes before compression
BIN_SIZE=$(du -sb bin 2>/dev/null | awk '{print $1}')
TOTAL_SIZE_BEFORE=$BIN_SIZE

tar -czf $ARCHIVE_NAME bin wordcount test part*.txt Makefile 2>/dev/null || \
    tar -czf $ARCHIVE_NAME bin wordcount test Makefile 2>/dev/null

ARCHIVE_SIZE=$(stat -f%z "$ARCHIVE_NAME" 2>/dev/null || stat -c%s "$ARCHIVE_NAME" 2>/dev/null)
COMPRESSION_RATIO=$(awk "BEGIN {printf \"%.1f\", ($TOTAL_SIZE_BEFORE / $ARCHIVE_SIZE)}")

echo "  📊 Compression stats:"
echo "      Original: $(numfmt --to=iec $TOTAL_SIZE_BEFORE 2>/dev/null || echo "$TOTAL_SIZE_BEFORE bytes")"
echo "      Compressed: $(numfmt --to=iec $ARCHIVE_SIZE 2>/dev/null || echo "$ARCHIVE_SIZE bytes")"
echo "      Ratio: ${COMPRESSION_RATIO}x"
echo ""

# Transfer compressed archive to all worker nodes
echo "🚀 Transferring compressed archive to worker nodes..."
TRANSFER_START=$(date +%s)

for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        SITE=$(echo $hostname | cut -d'.' -f2)
        echo "  - [$SITE] Transferring to $hostname..."

        if ! scp -q -C $ARCHIVE_NAME $hostname:~ ; then
            echo "❌ Failed to transfer to $hostname"
            echo "   Check network connectivity and SSH access"
            rm -f $ARCHIVE_NAME
            exit 1
        fi

        # Extract on remote node
        echo "  - [$SITE] Extracting on $hostname..."
        ssh $hostname "tar -xzf ~/$ARCHIVE_NAME -C ~ && rm ~/$ARCHIVE_NAME" &
    fi
done

# Wait for all extractions to complete
wait

TRANSFER_END=$(date +%s)
TRANSFER_DURATION=$((TRANSFER_END - TRANSFER_START))

echo "✅ Files transferred and extracted on all sites in ${TRANSFER_DURATION}s"
echo "   (Compression saved ~$(awk "BEGIN {printf \"%.0f\", ($TOTAL_SIZE_BEFORE - $ARCHIVE_SIZE) * $(echo $HOSTNAMES | wc -w)}") bytes total)"

# Cleanup local archive
rm -f $ARCHIVE_NAME
echo ""

# Start workers
echo "🚀 Starting worker nodes across all sites..."
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        SITE=$(echo $hostname | cut -d'.' -f2)
        echo "  - [$SITE] Starting worker on $hostname..."
        ssh $hostname "cd ~ && nohup java -cp bin network.worker.WorkerNode $hostname > worker.log 2>&1 &" &
        sleep 1
    fi
done

# Wait for workers to initialize (longer for multi-site)
echo "⏳ Waiting for workers to initialize across all sites..."
sleep 8
echo ""

# Build worker list for scheduler
WORKER_LIST=$(echo "$HOSTNAMES" | grep -v "$MASTER_NODE" | awk '{printf "\"%s\",", $0}' | sed 's/,$//')

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   STARTING MULTI-SITE DISTRIBUTED EXECUTION             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo "Worker list: [$WORKER_LIST]"
echo ""
echo "⚠️  Note: Inter-site communication may show increased latency"
echo ""

# Run the static Makefile-based system
START_TIME=$(date +%s)

if java -cp bin scheduler.Main "[$WORKER_LIST]"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "✅ Multi-site execution completed successfully!"
    echo "═══════════════════════════════════════════════════════════"
    echo "Total execution time: ${DURATION}s"

    # Display results
    if [ -f total.txt ]; then
        TOTAL=$(cat total.txt)
        echo ""
        echo "📊 RESULTS:"
        echo "  Total word count: $TOTAL"
        echo ""
        echo "  Individual counts:"
        for i in {1..5}; do
            if [ -f count$i.txt ]; then
                COUNT=$(cat count$i.txt)
                echo "    - part$i.txt: $COUNT words"
            fi
        done
    fi

    echo ""
    echo "🌐 Multi-site performance:"
    echo "  Sites involved: $SITE_COUNT"
    echo "  Workers: $TOTAL_WORKERS"
    echo "  Execution time: ${DURATION}s"
else
    echo ""
    echo "❌ Execution failed!"
    echo "Check worker.log files on each node for details"
fi

# Cleanup: stop all workers across all sites
echo ""
echo "🛑 Stopping worker nodes across all sites..."
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        SITE=$(echo $hostname | cut -d'.' -f2)
        echo "  - [$SITE] Stopping $hostname..."
        ssh $hostname "pkill -f 'java.*WorkerNode'" 2>/dev/null || true
    fi
done

echo "✅ All workers stopped"
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   MULTI-SITE TEST COMPLETED                             ║"
echo "╚══════════════════════════════════════════════════════════╝"
