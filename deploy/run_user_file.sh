#!/bin/bash
set -e  # Exit on error

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   DISTRIBUTED WORD COUNT - User File Mode              ║"
echo "║   Auto-adapts to number of workers                     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check for input file argument
if [ $# -lt 1 ]; then
    echo "Usage: $0 <input-file>"
    echo ""
    echo "Arguments:"
    echo "  input-file : Text file to count words in"
    echo ""
    echo "Example:"
    echo "  $0 mydata.txt"
    exit 1
fi

INPUT_FILE="$1"

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
    echo "Please reserve nodes first with: oarsub -I -l nodes=N,walltime=1:00:00"
    exit 1
fi

# Check if necessary files exist
if [ ! -d "bin" ]; then
    echo "❌ Error: bin directory not found. Please compile first:"
    echo "  javac -d bin -sourcepath src \$(find src -name '*.java')"
    exit 1
fi

if [ ! -f "wordcount" ]; then
    echo "⚠️  Warning: wordcount binary not found. Compiling..."
    gcc -o wordcount test/wordcount.c
fi

# Get node information
HOSTNAMES=$(uniq $OAR_NODEFILE)
MASTER_NODE=$(hostname)

echo "🖥️  Master node: $MASTER_NODE"
echo ""

# Build worker list (exclude master)
WORKERS=""
WORKER_COUNT=0
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        if [ -z "$WORKERS" ]; then
            WORKERS="$hostname"
        else
            WORKERS="$WORKERS,$hostname"
        fi
        WORKER_COUNT=$((WORKER_COUNT + 1))
    fi
done

if [ $WORKER_COUNT -eq 0 ]; then
    echo "❌ Error: No worker nodes available"
    echo "Reserve at least 2 nodes (1 master + 1 worker)"
    exit 1
fi

echo "👷 Workers: $WORKER_COUNT"
for hostname in $(echo $WORKERS | tr ',' '\n'); do
    echo "  - $hostname"
done
echo ""

# Calculate expected load per worker
LINES_PER_WORKER=$((LINE_COUNT / WORKER_COUNT))
echo "📊 Load distribution:"
echo "   Input lines: $LINE_COUNT"
echo "   Workers: $WORKER_COUNT"
echo "   Lines per worker: ~$LINES_PER_WORKER"
echo ""

# Copy files to all worker nodes
echo "📦 Distributing files to workers..."
for hostname in $(echo $WORKERS | tr ',' '\n'); do
    echo "  - $hostname"
    if ! scp -q -r bin wordcount test "$INPUT_FILE" $hostname:~ ; then
        echo "❌ Failed to copy files to $hostname"
        exit 1
    fi
done
echo "✅ Files distributed"
echo ""

# Start workers
echo "🚀 Starting workers..."
for hostname in $(echo $WORKERS | tr ',' '\n'); do
    ssh $hostname "cd ~ && nohup java -cp bin network.worker.WorkerNode $hostname > worker.log 2>&1 &" &
    sleep 1
done

echo "⏳ Waiting for workers to initialize..."
sleep 5
echo ""

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   STARTING DYNAMIC DISTRIBUTED EXECUTION                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Mode: Dynamic (auto-generating Makefile with $WORKER_COUNT parts)"
echo "Workers: [$WORKERS]"
echo ""

# Run the dynamic system
INPUT_BASENAME=$(basename "$INPUT_FILE")
START_TIME=$(date +%s)

if java -cp bin scheduler.Main "$INPUT_BASENAME" "[$WORKERS]"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "✅ Execution completed successfully!"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # Show results
    if [ -f "total.txt" ]; then
        TOTAL=$(cat total.txt)
        echo "📊 RESULTS:"
        echo "  Total word count: $TOTAL"
        echo ""
        echo "  Individual counts:"
        for i in $(seq 1 $WORKER_COUNT); do
            if [ -f "count$i.txt" ]; then
                COUNT=$(cat count$i.txt)
                echo "    - part$i.txt: $COUNT words"
            fi
        done
    fi

    echo ""
    echo "⏱️  Performance:"
    echo "   Workers: $WORKER_COUNT"
    echo "   Execution time: ${DURATION}s"
    if [ $DURATION -gt 0 ]; then
        echo "   Throughput: $((LINE_COUNT / DURATION)) lines/sec"
    fi
else
    echo ""
    echo "❌ Execution failed!"
fi

# Cleanup
echo ""
echo "🛑 Stopping workers..."
for hostname in $(echo $WORKERS | tr ',' '\n'); do
    ssh $hostname "pkill -f 'java.*WorkerNode'" 2>/dev/null || true
done

echo "✅ All workers stopped"
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   USER FILE TEST COMPLETED                              ║"
echo "╚══════════════════════════════════════════════════════════╝"
