#!/bin/bash
set -e  # Exit on error

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   MULTI-SITE DISTRIBUTED WORD COUNT (SCP Mode)          ║"
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
    echo ""
    echo "Usage: bash deploy/run_multi_site.sh [input_file]"
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

# ==================== PREPARE INPUT FILE ====================

echo "📝 Preparing input file..."

# Check if user provided input file
if [ -z "$1" ]; then
    echo "No input file provided, creating test file..."
    cat > test_input.txt << 'EOF'
Test SCP multi-site avec division dynamique du fichier.
Système distribué de comptage de mots sur Grid5000.
Java RMI pour communication entre les nœuds.
Makefile parsing et gestion des dépendances.
Architecture distribuée avec workers multiples sur plusieurs sites.
Grenoble Lyon Nancy Lille Rennes Sophia infrastructure de recherche.
Communication inter-sites pour calcul distribué à grande échelle.
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
echo "📦 Copying files to worker nodes (this may take longer for remote sites)..."
for hostname in $HOSTNAMES; do
    if [ "$hostname" != "$MASTER_NODE" ]; then
        SITE=$(echo $hostname | cut -d'.' -f2)
        echo "  - [$SITE] Copying to $hostname..."
        # Copy: bin/, wordcount, test/, split files, and generated Makefile
        if ! scp -q -r bin wordcount test part*.txt Makefile.generated $hostname:~ ; then
            echo "❌ Failed to copy files to $hostname"
            echo "   Check network connectivity and SSH access"
            exit 1
        fi
    fi
done
echo "✅ Files copied to all sites"
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

# Build ALL_NODES list for scheduler (master + workers, as required by ClusterManager)
ALL_NODES_LIST=$(echo "$HOSTNAMES" | awk '{printf "\"%s\",", $0}' | sed 's/,$//')

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   STARTING MULTI-SITE DISTRIBUTED EXECUTION (SCP MODE)  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo "Node list: [$ALL_NODES_LIST]"
echo ""
echo "⚠️  Note: Inter-site communication may show increased latency"
echo ""

# Copy Makefile.generated to Makefile for execution
cp Makefile.generated Makefile

# Run the static Makefile-based system with generated Makefile
START_TIME=$(date +%s)

if java -cp bin scheduler.Main "[$ALL_NODES_LIST]"; then
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
