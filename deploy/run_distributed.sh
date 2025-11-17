#!/bin/bash
set -e  # Exit on error

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   DISTRIBUTED WORD COUNT - Deployment Script            ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check if running in Grid5000 environment
if [ -z "$OAR_NODEFILE" ]; then
    echo "❌ Error: OAR_NODEFILE not found"
    echo "Please reserve nodes first: oarsub -I -l nodes=5"
    exit 1
fi

# Check if necessary files exist
if [ ! -d "bin" ] || [ ! -f "wordcount" ] || [ ! -f "Makefile" ]; then
    echo "❌ Error: Required files not found. Please run deploy/setup.sh first"
    exit 1
fi

# Check if test data exists
if [ ! -f "part1.txt" ]; then
    echo "❌ Error: Test data not found. Please run deploy/setup.sh first"
    exit 1
fi

HOSTNAMES=$(uniq $OAR_NODEFILE)
MASTER_NODE=$(hostname)

echo "Master node: $MASTER_NODE"
echo ""
echo "Worker nodes:"
echo "$HOSTNAMES" | grep -v "$MASTER_NODE"
echo ""

echo "Copying files to all nodes..."
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        echo "  - Copying to $hostname..."
        # Copy all necessary files, excluding wordcount.c (not needed on workers)
        if ! scp -r bin wordcount part*.txt Makefile $hostname:~ ; then
            echo "❌ Failed to copy files to $hostname"
            exit 1
        fi
    fi
done

echo ""
echo "Starting workers..."

for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        echo "  - Starting worker on $hostname..."
        if ! ssh $hostname "cd ~ && java -cp bin network.worker.WorkerNode $hostname > worker.log 2>&1" & then
            echo "⚠️  Warning: Failed to start worker on $hostname"
        fi
        sleep 2
    fi
done

echo ""
echo "✅ All workers started!"
echo ""

WORKER_LIST=$(echo "$HOSTNAMES" | grep -v "$MASTER_NODE" | awk '{printf "\"%s\",", $0}' | sed 's/,$//')

echo "Starting master coordinator..."
echo "Worker list: [$WORKER_LIST]"
echo ""

# Run from project root directory (current directory should be project root)
if ! java -cp bin scheduler.Main "[$WORKER_LIST]"; then
    echo "❌ Failed to run master coordinator"
    # Cleanup workers before exit
    for hostname in $HOSTNAMES; do
        if [ "$hostname" != "$MASTER_NODE" ]; then
            ssh $hostname "pkill -f WorkerNode" 2>/dev/null || true
        fi
    done
    exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "Execution completed!"
echo "═══════════════════════════════════════════════════════════"
echo ""

if [ -f total.txt ]; then
    TOTAL=$(cat total.txt)
    echo "📊 Total word count: $TOTAL"
    echo ""
    echo "Individual counts:"
    for i in {1..5}; do
        if [ -f count$i.txt ]; then
            COUNT=$(cat count$i.txt)
            echo "  - part$i.txt: $COUNT words"
        fi
    done
fi

echo ""
echo "Stopping workers..."
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        ssh $hostname "pkill -f WorkerNode" 2>/dev/null
    fi
done

echo "✅ All done!"
