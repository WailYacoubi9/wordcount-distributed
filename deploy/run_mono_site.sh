#!/bin/bash
set -e  # Exit on error

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   MONO-SITE DISTRIBUTED WORD COUNT                      ║"
echo "║   All nodes on the same Grid5000 site                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check if running in Grid5000 environment
if [ -z "$OAR_NODEFILE" ]; then
    echo "❌ Error: OAR_NODEFILE not found"
    echo ""
    echo "Reserve nodes on a SINGLE site first:"
    echo "  oarsub -I -l nodes=5,walltime=1:00:00"
    echo ""
    echo "Or non-interactive:"
    echo "  oarsub -l nodes=5,walltime=1:00:00 \"bash deploy/run_mono_site.sh\""
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
SITE=$(hostname | cut -d'.' -f2)

echo "📍 Site: $SITE"
echo "🖥️  Master node: $MASTER_NODE"
echo ""
echo "👷 Worker nodes:"
WORKER_COUNT=0
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        echo "  - $hostname"
        WORKER_COUNT=$((WORKER_COUNT + 1))
    fi
done
echo ""
echo "Total workers: $WORKER_COUNT"
echo ""

# Verify all nodes are on the same site
echo "🔍 Verifying mono-site deployment..."
for hostname in $HOSTNAMES; do
    NODE_SITE=$(echo $hostname | cut -d'.' -f2)
    if [ "$NODE_SITE" != "$SITE" ]; then
        echo "❌ Error: Node $hostname is on site $NODE_SITE, but master is on $SITE"
        echo "This script is for MONO-SITE deployment only!"
        echo "Use run_multi_site.sh for multi-site deployment."
        exit 1
    fi
done
echo "✅ All nodes confirmed on site: $SITE"
echo ""

# Copy files to all worker nodes
echo "📦 Copying files to worker nodes..."
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        echo "  - Copying to $hostname..."
        if ! scp -q -r bin wordcount $hostname:~ ; then
            echo "❌ Failed to copy files to $hostname"
            exit 1
        fi
    fi
done
echo "✅ Files copied successfully"
echo ""

# Start workers
echo "🚀 Starting worker nodes..."
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        echo "  - Starting worker on $hostname..."
        ssh $hostname "cd ~ && nohup java -cp bin network.worker.WorkerNode $hostname > worker.log 2>&1 &" &
        sleep 1
    fi
done

# Wait for workers to initialize
echo "⏳ Waiting for workers to initialize..."
sleep 5
echo ""

# Build worker list for scheduler
WORKER_LIST=$(echo "$HOSTNAMES" | grep -v "$MASTER_NODE" | awk '{printf "\"%s\",", $0}' | sed 's/,$//')

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   STARTING DISTRIBUTED EXECUTION                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo "Worker list: [$WORKER_LIST]"
echo ""

# Run the static Makefile-based system
if java -cp bin scheduler.Main "[$WORKER_LIST]"; then
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "✅ Execution completed successfully!"
    echo "═══════════════════════════════════════════════════════════"

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
else
    echo ""
    echo "❌ Execution failed!"
fi

# Cleanup: stop all workers
echo ""
echo "🛑 Stopping worker nodes..."
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        ssh $hostname "pkill -f 'java.*WorkerNode'" 2>/dev/null || true
    fi
done

echo "✅ All workers stopped"
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   MONO-SITE TEST COMPLETED                              ║"
echo "╚══════════════════════════════════════════════════════════╝"
