#!/bin/bash
set -e  # Exit on error

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   MONO-SITE DISTRIBUTED WORD COUNT (SCP Mode)          ║"
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
    echo "  oarsub -l nodes=5,walltime=1:00:00 \"bash deploy/run_mono_site.sh [input_file]\""
    exit 1
fi

# Check if necessary files exist
if [ ! -d "bin" ]; then
    echo "❌ Error: bin directory not found. Compiling Java code..."
    javac -d bin src/config/*.java src/cluster/*.java src/utils/*.java \
          src/parser/*.java src/network/worker/*.java \
          src/network/master/*.java src/scheduler/*.java
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

# ==================== PREPARE INPUT FILE ====================

echo "📝 Preparing input file..."

# Check if user provided input file
if [ -z "$1" ]; then
    echo "No input file provided, creating test file..."
    cat > test_input.txt << 'EOF'
Test SCP mono-site avec division dynamique du fichier.
Système distribué de comptage de mots sur Grid5000.
Java RMI pour communication entre les nœuds.
Makefile parsing et gestion des dépendances.
Architecture distribuée avec workers multiples.
Grenoble Lyon Nancy infrastructure de recherche.
EOF
    INPUT_FILE="test_input.txt"
else
    INPUT_FILE="$1"
    if [ ! -f "$INPUT_FILE" ]; then
        echo "❌ Error: Input file not found: $INPUT_FILE"
        exit 1
    fi
fi

echo "✅ Using input file: $INPUT_FILE"
echo ""

# ==================== GENERATE MAKEFILE AND SPLIT FILE ====================

echo "🔧 Generating Makefile and splitting input file..."
echo "   This will create part*.txt files and Makefile.generated"

# Build ALL_NODES list (including master for Java processing)
ALL_NODES_LIST=$(echo "$HOSTNAMES" | awk '{printf "\"%s\",", $0}' | sed 's/,$//')

# Run Main.java in dynamic mode to generate Makefile and split files
# This runs on master and creates part*.txt and Makefile.generated locally
if java -cp bin scheduler.Main "$INPUT_FILE" "[$ALL_NODES_LIST]"; then
    echo "✅ Makefile generated and files split"

    # Check that Makefile.generated was created
    if [ ! -f "Makefile.generated" ]; then
        echo "❌ Error: Makefile.generated was not created"
        exit 1
    fi

    # Check that split files were created
    SPLIT_COUNT=$(ls -1 part*.txt 2>/dev/null | wc -l)
    if [ $SPLIT_COUNT -eq 0 ]; then
        echo "❌ Error: No part*.txt files were created"
        exit 1
    fi

    echo "   - Generated $SPLIT_COUNT split files"
    echo "   - Generated Makefile.generated"
else
    echo "❌ Error: Failed to generate Makefile and split files"
    exit 1
fi

echo ""

# Copy files to all worker nodes
echo "📦 Copying files to worker nodes..."
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        echo "  - Copying to $hostname..."
        # Copy: bin/, wordcount, test/, split files, and generated Makefile
        if ! scp -q -r bin wordcount test part*.txt Makefile.generated $hostname:~ ; then
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

# Build ALL_NODES list for scheduler (master + workers, as required by ClusterManager)
ALL_NODES_LIST=$(echo "$HOSTNAMES" | awk '{printf "\"%s\",", $0}' | sed 's/,$//')

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   STARTING DISTRIBUTED EXECUTION (SCP MODE)             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo "Node list: [$ALL_NODES_LIST]"
echo ""

# Copy Makefile.generated to Makefile for execution
cp Makefile.generated Makefile

# Run the static Makefile-based system with generated Makefile
if java -cp bin scheduler.Main "[$ALL_NODES_LIST]"; then
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
        # Display results for all generated count files
        for count_file in count*.txt; do
            if [ -f "$count_file" ]; then
                COUNT=$(cat "$count_file")
                # Extract number from count file name
                PART_NUM=$(echo "$count_file" | sed 's/count\([0-9]*\).txt/\1/')
                echo "    - part${PART_NUM}.txt: $COUNT words"
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
