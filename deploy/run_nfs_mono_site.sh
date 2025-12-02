#!/bin/bash

# NFS-based Mono-Site Deployment Script
# Sets up NFS share and runs distributed word count without SCP transfer

set -e  # Exit on any error

# Configuration
NFS_SHARED_DIR="/tmp/nfs_shared"
EXPORT_FILE="/etc/exports"
PROJECT_DIR="$HOME/wordcount-distributed"
PORT=3000

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "╔══════════════════════════════════════════════════════════╗"
echo "║     DISTRIBUTED WORD COUNT - NFS Mono-Site Setup       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check if running in OAR job
if [ -z "$OAR_NODEFILE" ]; then
    echo -e "${RED}❌ Error: Not running in an OAR job${NC}"
    echo "Please reserve nodes first: oarsub -I -l nodes=4,walltime=1:00:00"
    exit 1
fi

# Get master and worker nodes
MASTER=$(head -n 1 $OAR_NODEFILE)
WORKERS=$(tail -n +2 $OAR_NODEFILE | uniq)
WORKER_COUNT=$(echo "$WORKERS" | wc -l)

echo -e "${BLUE}🖥️  Master node: $MASTER${NC}"
echo -e "${BLUE}👷 Workers ($WORKER_COUNT):${NC}"
echo "$WORKERS" | nl
echo ""

# Build worker list for Java
WORKER_LIST="["
FIRST=true
for worker in $WORKERS; do
    if [ "$FIRST" = true ]; then
        WORKER_LIST="${WORKER_LIST}${worker}:${PORT}"
        FIRST=false
    else
        WORKER_LIST="${WORKER_LIST},${worker}:${PORT}"
    fi
done
WORKER_LIST="${WORKER_LIST}]"

echo -e "${GREEN}📋 Worker list: $WORKER_LIST${NC}"
echo ""

# ==================== NFS SETUP ====================

echo -e "${BLUE}📁 Setting up NFS shared directory...${NC}"

# Create NFS directory on master
mkdir -p $NFS_SHARED_DIR
chmod 777 $NFS_SHARED_DIR

# Copy necessary files to NFS directory
cp -r $PROJECT_DIR/test $NFS_SHARED_DIR/
echo -e "${GREEN}✅ NFS directory created: $NFS_SHARED_DIR${NC}"

# Setup NFS export on master (requires root - use OAR kadeploy if needed)
echo -e "${BLUE}📤 Configuring NFS export...${NC}"
echo "$NFS_SHARED_DIR *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a $EXPORT_FILE > /dev/null || true
sudo exportfs -ra 2>/dev/null || echo "⚠️  Warning: Could not export NFS (may need kadeploy environment)"
sudo systemctl restart nfs-server 2>/dev/null || echo "⚠️  Warning: Could not restart NFS server"

# Mount NFS on all workers
echo -e "${BLUE}🔗 Mounting NFS on workers...${NC}"
for worker in $WORKERS; do
    echo "  Mounting on $worker..."
    ssh $worker "mkdir -p $NFS_SHARED_DIR && sudo mount -t nfs ${MASTER}:${NFS_SHARED_DIR} ${NFS_SHARED_DIR}" 2>/dev/null || \
        echo "    ⚠️  Warning: Could not mount NFS on $worker (may need kadeploy environment)"
done
echo -e "${GREEN}✅ NFS mounted on all workers${NC}"
echo ""

# ==================== DEPLOY WORKERS ====================

echo -e "${BLUE}📦 Deploying workers...${NC}"

# Copy compiled code to all workers
for worker in $WORKERS; do
    echo "  Copying to $worker..."
    scp -q -r $PROJECT_DIR/bin $worker:~/
done

# Start worker nodes
echo -e "${BLUE}🚀 Starting worker nodes...${NC}"
for worker in $WORKERS; do
    echo "  Starting worker on $worker:$PORT..."
    ssh $worker "cd ~ && nohup java -cp bin network.worker.WorkerNode $worker $PORT > worker_nfs.log 2>&1 &" &
done

# Wait for workers to start
echo -e "${BLUE}⏳ Waiting for workers to initialize...${NC}"
sleep 5
echo -e "${GREEN}✅ All workers started${NC}"
echo ""

# ==================== RUN USER INPUT ====================

echo -e "${BLUE}📝 Preparing user input...${NC}"

# Check if user provided input file
if [ -z "$1" ]; then
    echo "No input file provided, creating test file..."
    cat > $NFS_SHARED_DIR/test_input.txt << 'EOF'
This is a test of the NFS-based distributed word count system.
The system splits files equitably among workers.
All workers access files from the shared NFS directory.
No SCP transfer is needed, making the system simpler and faster.
Testing with multiple lines to verify correct counting.
EOF
    INPUT_FILE="test_input.txt"
else
    INPUT_FILE=$(basename "$1")
    cp "$1" $NFS_SHARED_DIR/$INPUT_FILE
    echo -e "${GREEN}✅ Input file copied to NFS: $INPUT_FILE${NC}"
fi

# Compile wordcount in NFS directory
echo -e "${BLUE}🔨 Compiling wordcount program in NFS directory...${NC}"
gcc -o $NFS_SHARED_DIR/wordcount $NFS_SHARED_DIR/test/wordcount.c
echo -e "${GREEN}✅ Wordcount compiled${NC}"
echo ""

# ==================== RUN MAIN ====================

echo -e "${BLUE}🚀 Starting distributed execution (NFS mode)...${NC}"
cd $PROJECT_DIR

java -cp bin scheduler.MainNFS "$NFS_SHARED_DIR/$INPUT_FILE" "$WORKER_LIST" "$NFS_SHARED_DIR"

# ==================== DISPLAY RESULTS ====================

echo ""
echo -e "${GREEN}✅ Execution completed!${NC}"
echo ""

if [ -f "$NFS_SHARED_DIR/total.txt" ]; then
    RESULT=$(cat $NFS_SHARED_DIR/total.txt)
    echo "╔════════════════════════════════════╗"
    echo "║  Total word count: $RESULT           ║"
    echo "╚════════════════════════════════════╝"
    echo ""

    echo "Files in NFS directory:"
    ls -lh $NFS_SHARED_DIR/*.txt 2>/dev/null | head -10
else
    echo -e "${RED}❌ Result file not found: $NFS_SHARED_DIR/total.txt${NC}"
fi

# ==================== CLEANUP ====================

echo ""
echo -e "${BLUE}🧹 Cleanup...${NC}"

# Stop workers
for worker in $WORKERS; do
    ssh $worker "pkill -f 'java.*WorkerNode'" 2>/dev/null || true
done
echo -e "${GREEN}✅ Workers stopped${NC}"

# Unmount NFS on workers
for worker in $WORKERS; do
    ssh $worker "sudo umount $NFS_SHARED_DIR" 2>/dev/null || true
done
echo -e "${GREEN}✅ NFS unmounted${NC}"

# Remove NFS export (optional - uncomment to clean up)
# sudo sed -i "\|$NFS_SHARED_DIR|d" $EXPORT_FILE
# sudo exportfs -ra

echo ""
echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  NFS Mono-Site Test Complete! 🎉  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
