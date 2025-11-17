#!/bin/bash
set -e  # Exit on error

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   DYNAMIC DISTRIBUTED WORD COUNT                        ║"
echo "║   Automatic file splitting and load balancing           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check for input file argument
if [ $# -lt 1 ]; then
    echo "Usage: $0 <input-file> [mono|multi]"
    echo ""
    echo "Arguments:"
    echo "  input-file : Text file to count words in"
    echo "  mono|multi : Deployment mode (default: auto-detect)"
    echo ""
    echo "Examples:"
    echo "  $0 large-corpus.txt mono"
    echo "  $0 mydata.txt multi"
    echo "  $0 input.txt  # auto-detect"
    exit 1
fi

INPUT_FILE="$1"
DEPLOYMENT_MODE="${2:-auto}"

# Verify input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "❌ Error: Input file not found: $INPUT_FILE"
    exit 1
fi

FILE_SIZE=$(stat -f%z "$INPUT_FILE" 2>/dev/null || stat -c%s "$INPUT_FILE" 2>/dev/null)
LINE_COUNT=$(wc -l < "$INPUT_FILE")

echo "📄 Input file: $INPUT_FILE"
echo "   Size: $FILE_SIZE bytes"
echo "   Lines: $LINE_COUNT"
echo ""

# Check if running in Grid5000 environment
if [ -z "$OAR_NODEFILE" ]; then
    echo "❌ Error: OAR_NODEFILE not found"
    echo "Please reserve nodes first"
    exit 1
fi

# Check if necessary files exist
if [ ! -d "bin" ]; then
    echo "❌ Error: bin directory not found. Please run deploy/setup.sh first"
    exit 1
fi

if [ ! -f "wordcount" ]; then
    echo "⚠️  Warning: wordcount binary not found. Compiling..."
    gcc -o wordcount test/wordcount.c
fi

# Get node information
HOSTNAMES=$(uniq $OAR_NODEFILE)
MASTER_NODE=$(hostname)
MASTER_SITE=$(hostname | cut -d'.' -f2)

echo "🖥️  Master node: $MASTER_NODE"
echo "📍 Master site: $MASTER_SITE"
echo ""

# Analyze deployment type
echo "🔍 Analyzing deployment configuration..."
declare -A SITES
WORKER_COUNT=0
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        SITE=$(echo $hostname | cut -d'.' -f2)
        if [ -z "${SITES[$SITE]}" ]; then
            SITES[$SITE]=1
        else
            SITES[$SITE]=$((${SITES[$SITE]} + 1))
        fi
        WORKER_COUNT=$((WORKER_COUNT + 1))
    fi
done

SITE_COUNT=${#SITES[@]}

if [ "$DEPLOYMENT_MODE" == "auto" ]; then
    if [ $SITE_COUNT -gt 1 ]; then
        DEPLOYMENT_MODE="multi"
    else
        DEPLOYMENT_MODE="mono"
    fi
fi

echo "Deployment mode: $DEPLOYMENT_MODE-site"
echo "Sites: $SITE_COUNT"
echo "Workers: $WORKER_COUNT"
echo ""

# Display site distribution
echo "👷 Worker distribution:"
for site in "${!SITES[@]}"; do
    count=${SITES[$site]}
    echo "  [$site]: $count worker(s)"
done
echo ""

# Calculate expected load per worker
LINES_PER_WORKER=$((LINE_COUNT / WORKER_COUNT))
echo "📊 Expected load distribution:"
echo "   Lines per worker: ~$LINES_PER_WORKER"
echo "   (System will auto-balance with max ±1 line difference)"
echo ""

# Copy files to all worker nodes
echo "📦 Distributing files to workers..."
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        SITE=$(echo $hostname | cut -d'.' -f2)
        echo "  - [$SITE] $hostname"
        if ! scp -q -r bin wordcount "$INPUT_FILE" $hostname:~ ; then
            echo "❌ Failed to copy files to $hostname"
            exit 1
        fi
    fi
done
echo "✅ Files distributed"
echo ""

# Start workers
echo "🚀 Starting workers..."
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        ssh $hostname "cd ~ && nohup java -cp bin network.worker.WorkerNode $hostname > worker.log 2>&1 &" &
        sleep 1
    fi
done

# Wait for initialization (longer for multi-site)
if [ "$DEPLOYMENT_MODE" == "multi" ]; then
    echo "⏳ Waiting for multi-site workers to initialize..."
    sleep 8
else
    echo "⏳ Waiting for workers to initialize..."
    sleep 5
fi
echo ""

# Build worker list
WORKER_LIST=$(echo "$HOSTNAMES" | grep -v "$MASTER_NODE" | awk '{printf "\"%s\",", $0}' | sed 's/,$//')

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   STARTING DYNAMIC DISTRIBUTED EXECUTION                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Run the dynamic system
INPUT_BASENAME=$(basename "$INPUT_FILE")
START_TIME=$(date +%s)

if java -cp bin scheduler.DynamicMain "$INPUT_BASENAME" "[$WORKER_LIST]"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "✅ Dynamic execution completed successfully!"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "⏱️  Performance metrics:"
    echo "   Input: $LINE_COUNT lines, $FILE_SIZE bytes"
    echo "   Workers: $WORKER_COUNT across $SITE_COUNT site(s)"
    echo "   Mode: $DEPLOYMENT_MODE-site"
    echo "   Execution time: ${DURATION}s"
    echo "   Throughput: $((LINE_COUNT / DURATION)) lines/sec"
else
    echo ""
    echo "❌ Execution failed!"
fi

# Cleanup
echo ""
echo "🛑 Stopping workers..."
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        ssh $hostname "pkill -f 'java.*WorkerNode'" 2>/dev/null || true
    fi
done

echo "✅ All workers stopped"
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   DYNAMIC DISTRIBUTED WORD COUNT COMPLETED              ║"
echo "╚══════════════════════════════════════════════════════════╝"
