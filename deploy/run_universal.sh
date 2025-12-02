#!/bin/bash
set -e  # Exit on error

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   DISTRIBUTED WORD COUNT - Universal Script             ║"
echo "║   Auto-detects mono-site or multi-site deployment      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check if running in Grid5000 environment
if [ -z "$OAR_NODEFILE" ]; then
    echo "❌ Error: OAR_NODEFILE not found"
    echo ""
    echo "Reserve nodes first:"
    echo "  Mono-site:  oarsub -I -l nodes=5,walltime=1:00:00"
    echo "  Multi-site: Reserve on multiple sites and combine nodefiles"
    exit 1
fi

# Check if necessary files exist
if [ ! -d "bin" ]; then
    echo "❌ Error: bin directory not found. Please compile first"
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

# ============================================================
# AUTO-DETECTION: Mono-site ou Multi-site?
# ============================================================

echo "🔍 Analyzing deployment topology..."

# Compte les sites uniques
declare -A SITES
for hostname in $HOSTNAMES; do
    SITE=$(echo $hostname | cut -d'.' -f2)
    if [ -z "${SITES[$SITE]}" ]; then
        SITES[$SITE]=1
    else
        SITES[$SITE]=$((${SITES[$SITE]} + 1))
    fi
done

SITE_COUNT=${#SITES[@]}

# ============================================================
# DÉCISION: Quel mode?
# ============================================================

if [ $SITE_COUNT -eq 1 ]; then
    MODE="MONO-SITE"
    SLEEP_TIME=5
    echo "✓ Detection: MONO-SITE deployment"
    echo "  All nodes on site: $MASTER_SITE"
else
    MODE="MULTI-SITE"
    SLEEP_TIME=8
    echo "✓ Detection: MULTI-SITE deployment"
    echo "  Sites involved: $SITE_COUNT"
    echo ""
    for site in "${!SITES[@]}"; do
        count=${SITES[$site]}
        if [ "$site" == "$MASTER_SITE" ]; then
            echo "    ✓ $site: $count node(s) [MASTER]"
        else
            echo "    → $site: $count node(s)"
        fi
    done
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Mode: $MODE"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Display workers
if [ "$MODE" == "MONO-SITE" ]; then
    echo "👷 Worker nodes:"
    WORKER_COUNT=0
    for hostname in $HOSTNAMES; do
        if [ "$hostname" != "$MASTER_NODE" ]; then
            echo "  - $hostname"
            WORKER_COUNT=$((WORKER_COUNT + 1))
        fi
    done
else
    echo "👷 Worker nodes by site:"
    WORKER_COUNT=0
    for hostname in $HOSTNAMES; do
        if [ "$hostname" != "$MASTER_NODE" ]; then
            SITE=$(echo $hostname | cut -d'.' -f2)
            echo "  [$SITE] $hostname"
            WORKER_COUNT=$((WORKER_COUNT + 1))
        fi
    done
fi

echo ""
echo "Total workers: $WORKER_COUNT"
echo ""

# Multi-site specific warnings
if [ "$MODE" == "MULTI-SITE" ]; then
    echo "📡 Multi-site considerations:"
    echo "  - Inter-site latency: 1-10ms"
    echo "  - Using fully qualified domain names (FQDN)"
    echo "  - File transfers may take longer"
    echo ""
fi

# Copy files to all worker nodes
echo "📦 Copying files to worker nodes..."
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        if [ "$MODE" == "MULTI-SITE" ]; then
            SITE=$(echo $hostname | cut -d'.' -f2)
            echo "  - [$SITE] Copying to $hostname..."
        else
            echo "  - Copying to $hostname..."
        fi

        if ! scp -q -r bin wordcount test part*.txt Makefile $hostname:~ ; then
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
        if [ "$MODE" == "MULTI-SITE" ]; then
            SITE=$(echo $hostname | cut -d'.' -f2)
            echo "  - [$SITE] Starting worker on $hostname..."
        else
            echo "  - Starting worker on $hostname..."
        fi
        ssh $hostname "cd ~ && nohup java -cp bin network.worker.WorkerNode $hostname > worker.log 2>&1 &" &
        sleep 1
    fi
done

# Wait for workers (adaptive delay based on mode)
echo "⏳ Waiting for workers to initialize ($SLEEP_TIME seconds)..."
sleep $SLEEP_TIME
echo ""

# Build worker list for scheduler
WORKER_LIST=$(echo "$HOSTNAMES" | grep -v "$MASTER_NODE" | awk '{printf "\"%s\",", $0}' | sed 's/,$//')

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   STARTING DISTRIBUTED EXECUTION                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo "Mode: $MODE"
echo "Worker list: [$WORKER_LIST]"
echo ""

# Run execution (measure time for multi-site)
if [ "$MODE" == "MULTI-SITE" ]; then
    START_TIME=$(date +%s)
fi

if java -cp bin scheduler.Main "[$WORKER_LIST]"; then

    if [ "$MODE" == "MULTI-SITE" ]; then
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "✅ Execution completed successfully!"
    echo "═══════════════════════════════════════════════════════════"

    if [ "$MODE" == "MULTI-SITE" ]; then
        echo "Execution time: ${DURATION}s"
    fi

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

    if [ "$MODE" == "MULTI-SITE" ]; then
        echo ""
        echo "🌐 Multi-site performance:"
        echo "  Sites: $SITE_COUNT"
        echo "  Workers: $WORKER_COUNT"
        echo "  Time: ${DURATION}s"
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
echo "║   $MODE TEST COMPLETED                                  "
echo "╚══════════════════════════════════════════════════════════╝"
