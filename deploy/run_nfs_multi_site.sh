#!/bin/bash

# NFS-based Multi-Site Deployment Script
# Sets up NFS share across multiple Grid5000 sites

set -e  # Exit on any error

# Configuration
NFS_SHARED_DIR="/tmp/nfs_shared"
EXPORT_FILE="/etc/exports"
PROJECT_DIR="$HOME/wordcount-distributed"
PORT=3000

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "╔══════════════════════════════════════════════════════════╗"
echo "║     DISTRIBUTED WORD COUNT - NFS Multi-Site Setup      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check arguments
if [ -z "$1" ]; then
    echo -e "${RED}❌ Error: Combined nodefile not provided${NC}"
    echo ""
    echo "Usage: $0 <combined_nodefile> [input_file]"
    echo ""
    echo "Steps to prepare:"
    echo "1. Reserve nodes on site 1 (e.g., Grenoble):"
    echo "   oarsub -I -l nodes=2,walltime=1:00:00"
    echo "   cat \$OAR_NODEFILE > ~/combined_nodefile"
    echo ""
    echo "2. Reserve nodes on site 2 (e.g., Lyon):"
    echo "   oarsub -I -l nodes=2,walltime=1:00:00"
    echo "   cat \$OAR_NODEFILE >> ~/combined_nodefile_lyon"
    echo "   scp combined_nodefile_lyon site1-master:~/combined_nodefile"
    echo ""
    echo "3. Back on site 1 master:"
    echo "   cat ~/combined_nodefile_lyon >> ~/combined_nodefile"
    echo "   ./deploy/run_nfs_multi_site.sh ~/combined_nodefile myinput.txt"
    exit 1
fi

COMBINED_NODEFILE="$1"
INPUT_FILE_ARG="$2"

if [ ! -f "$COMBINED_NODEFILE" ]; then
    echo -e "${RED}❌ Error: Combined nodefile not found: $COMBINED_NODEFILE${NC}"
    exit 1
fi

# Get nodes
MASTER=$(head -n 1 $COMBINED_NODEFILE)
ALL_WORKERS=$(tail -n +2 $COMBINED_NODEFILE | uniq)
WORKER_COUNT=$(echo "$ALL_WORKERS" | wc -l)

echo -e "${BLUE}🖥️  Master node: $MASTER${NC}"
echo -e "${BLUE}👷 Workers ($WORKER_COUNT):${NC}"
echo "$ALL_WORKERS" | nl
echo ""

# Detect sites
echo -e "${BLUE}🌍 Detecting sites...${NC}"
SITES=$(echo "$ALL_WORKERS" | awk -F. '{print $2}' | sort -u)
SITE_COUNT=$(echo "$SITES" | wc -l)
echo -e "${GREEN}Sites detected ($SITE_COUNT): $SITES${NC}"
echo ""

# Build worker list for Java
WORKER_LIST="["
FIRST=true
for worker in $ALL_WORKERS; do
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

echo -e "${BLUE}📁 Setting up NFS on master ($MASTER)...${NC}"

# Create NFS directory on master
mkdir -p $NFS_SHARED_DIR
chmod 777 $NFS_SHARED_DIR

# Copy necessary files to NFS directory
cp -r $PROJECT_DIR/test $NFS_SHARED_DIR/
cp -r $PROJECT_DIR/bin $NFS_SHARED_DIR/
echo -e "${GREEN}✅ NFS directory created: $NFS_SHARED_DIR${NC}"

# Setup NFS export on master
echo -e "${BLUE}📤 Configuring NFS export on master...${NC}"
echo "$NFS_SHARED_DIR *(rw,sync,no_subtree_check,no_root_squash,insecure)" | sudo tee -a $EXPORT_FILE > /dev/null || true
sudo exportfs -ra 2>/dev/null || echo "⚠️  Warning: Could not export NFS"
sudo systemctl restart nfs-server 2>/dev/null || \
    sudo service nfs-kernel-server restart 2>/dev/null || \
    echo "⚠️  Warning: Could not restart NFS server"

echo -e "${GREEN}✅ NFS exported from master${NC}"
echo ""

# ==================== MOUNT NFS ON ALL WORKERS ====================

echo -e "${BLUE}🔗 Mounting NFS on all workers...${NC}"
MOUNT_FAILURES=0

for worker in $ALL_WORKERS; do
    echo "  Mounting on $worker..."

    # Create directory and mount
    ssh $worker "mkdir -p $NFS_SHARED_DIR" 2>/dev/null || true

    if ssh $worker "sudo mount -t nfs -o vers=3 ${MASTER}:${NFS_SHARED_DIR} ${NFS_SHARED_DIR}" 2>/dev/null; then
        echo -e "    ${GREEN}✅ Mounted${NC}"
    else
        echo -e "    ${YELLOW}⚠️  Warning: Could not mount NFS (may need kadeploy environment)${NC}"
        MOUNT_FAILURES=$((MOUNT_FAILURES + 1))
    fi
done

if [ $MOUNT_FAILURES -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Warning: $MOUNT_FAILURES workers could not mount NFS${NC}"
    echo -e "${YELLOW}   For multi-site NFS, you may need a Grid5000 environment with NFS support${NC}"
    echo -e "${YELLOW}   Alternative: Use kadeploy to deploy an environment with NFS enabled${NC}"
    echo ""
fi

echo -e "${GREEN}✅ NFS setup complete${NC}"
echo ""

# ==================== DEPLOY WORKERS ====================

echo -e "${BLUE}📦 Deploying and starting workers...${NC}"

for worker in $ALL_WORKERS; do
    echo "  Deploying on $worker..."

    # Copy bin if NFS mount failed
    if ! ssh $worker "test -d $NFS_SHARED_DIR/bin" 2>/dev/null; then
        scp -q -r $PROJECT_DIR/bin $worker:~/
        BIN_PATH="~/bin"
    else
        BIN_PATH="$NFS_SHARED_DIR/bin"
    fi

    # Start worker
    ssh $worker "nohup java -cp $BIN_PATH network.worker.WorkerNode $worker $PORT > worker_nfs.log 2>&1 &" &
done

echo -e "${BLUE}⏳ Waiting for workers to initialize...${NC}"
sleep 7
echo -e "${GREEN}✅ All workers started${NC}"
echo ""

# ==================== PREPARE INPUT ====================

echo -e "${BLUE}📝 Preparing input file...${NC}"

if [ -z "$INPUT_FILE_ARG" ]; then
    echo "No input file provided, creating multi-site test file..."
    cat > $NFS_SHARED_DIR/multisite_test.txt << 'EOF'
This is a multi-site test of the NFS-based distributed word count system.
Workers are distributed across multiple Grid5000 sites.
All sites access files from the shared NFS directory on the master node.
NFS provides a unified filesystem view across geographical boundaries.
This eliminates the need for SCP file transfers.
Making the system architecture simpler and more elegant.
Testing distributed computing with Grenoble Lyon and Nancy.
Verifying correct word counting across all sites.
EOF
    INPUT_FILE="multisite_test.txt"
else
    INPUT_FILE=$(basename "$INPUT_FILE_ARG")
    cp "$INPUT_FILE_ARG" $NFS_SHARED_DIR/$INPUT_FILE
    echo -e "${GREEN}✅ Input file copied to NFS: $INPUT_FILE${NC}"
fi

# Compile wordcount
echo -e "${BLUE}🔨 Compiling wordcount in NFS directory...${NC}"
gcc -o $NFS_SHARED_DIR/wordcount $NFS_SHARED_DIR/test/wordcount.c
echo -e "${GREEN}✅ Wordcount compiled${NC}"
echo ""

# ==================== RUN DISTRIBUTED EXECUTION ====================

echo -e "${BLUE}🚀 Starting multi-site distributed execution (NFS mode)...${NC}"
echo ""

cd $PROJECT_DIR
java -cp bin scheduler.MainNFS "$NFS_SHARED_DIR/$INPUT_FILE" "$WORKER_LIST" "$NFS_SHARED_DIR"

# ==================== DISPLAY RESULTS ====================

echo ""
echo -e "${GREEN}✅ Multi-site execution completed!${NC}"
echo ""

if [ -f "$NFS_SHARED_DIR/total.txt" ]; then
    RESULT=$(cat $NFS_SHARED_DIR/total.txt)
    echo "╔═══════════════════════════════════════╗"
    echo "║  Total word count: $RESULT              ║"
    echo "║  Sites: $SITE_COUNT                             ║"
    echo "║  Workers: $WORKER_COUNT                          ║"
    echo "╚═══════════════════════════════════════╝"
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
for worker in $ALL_WORKERS; do
    ssh $worker "pkill -f 'java.*WorkerNode'" 2>/dev/null || true
done
echo -e "${GREEN}✅ Workers stopped${NC}"

# Unmount NFS
for worker in $ALL_WORKERS; do
    ssh $worker "sudo umount $NFS_SHARED_DIR" 2>/dev/null || true
done
echo -e "${GREEN}✅ NFS unmounted from workers${NC}"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  NFS Multi-Site Test Complete! 🎉   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
