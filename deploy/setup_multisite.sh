#!/bin/bash

# Helper script to setup multi-site deployment on Grid5000
# This script guides you through reserving nodes on multiple sites

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   MULTI-SITE SETUP HELPER                               ║"
echo "║   Guide for reserving nodes on multiple Grid5000 sites  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

cat << 'EOF'
STEP 1: Reserve nodes on SITE 1 (e.g., Grenoble)
=================================================

In a FIRST terminal:

  ssh access.grid5000.fr
  ssh grenoble
  oarsub -I -l nodes=2,walltime=1:00:00

Once connected to the job:

  cat $OAR_NODEFILE | uniq > ~/nodes_grenoble.txt
  cat ~/nodes_grenoble.txt

Keep this terminal open!

---

STEP 2: Reserve nodes on SITE 2 (e.g., Lyon)
==============================================

In a SECOND terminal:

  ssh access.grid5000.fr
  ssh lyon
  oarsub -I -l nodes=2,walltime=1:00:00

Once connected to the job:

  cat $OAR_NODEFILE | uniq > ~/nodes_lyon.txt

  # Copy to Grenoble master
  GRENOBLE_MASTER=$(ssh grenoble "cat ~/nodes_grenoble.txt | head -n 1")
  scp ~/nodes_lyon.txt ${GRENOBLE_MASTER}:~/

Keep this terminal open too!

---

STEP 3: Combine nodefiles on Grenoble (FIRST terminal)
========================================================

Back in the Grenoble terminal:

  # Wait for Lyon nodes file
  while [ ! -f ~/nodes_lyon.txt ]; do sleep 1; done

  # Combine both nodefiles
  cat ~/nodes_grenoble.txt ~/nodes_lyon.txt > ~/combined_nodes.txt

  echo ""
  echo "Combined nodes:"
  cat ~/combined_nodes.txt
  echo ""

---

STEP 4: Launch multi-site execution
=====================================

  cd ~/wordcount-distributed
  export OAR_NODEFILE=~/combined_nodes.txt
  bash deploy/run_multi_site.sh

---

ALTERNATIVE: Automatic helper script
======================================

Run this script with the site names:

  bash deploy/setup_multisite.sh grenoble lyon

EOF

# Check if sites provided as arguments
if [ $# -ge 2 ]; then
    SITE1=$1
    SITE2=$2

    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║   AUTOMATED MULTI-SITE SETUP                            ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Sites: $SITE1 and $SITE2"
    echo ""
    echo "⚠️  This requires you to have active reservations on both sites!"
    echo ""

    read -p "Do you have active OAR reservations on $SITE1 and $SITE2? (y/N) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Fetching nodes from $SITE1..."
        ssh $SITE1 "cat \$OAR_NODEFILE | uniq" > ~/nodes_${SITE1}.txt 2>/dev/null

        if [ $? -eq 0 ]; then
            echo "✅ Fetched $(wc -l < ~/nodes_${SITE1}.txt) nodes from $SITE1"
        else
            echo "❌ Failed to fetch nodes from $SITE1"
            echo "   Make sure you have an active reservation there"
            exit 1
        fi

        echo ""
        echo "Fetching nodes from $SITE2..."
        ssh $SITE2 "cat \$OAR_NODEFILE | uniq" > ~/nodes_${SITE2}.txt 2>/dev/null

        if [ $? -eq 0 ]; then
            echo "✅ Fetched $(wc -l < ~/nodes_${SITE2}.txt) nodes from $SITE2"
        else
            echo "❌ Failed to fetch nodes from $SITE2"
            echo "   Make sure you have an active reservation there"
            exit 1
        fi

        echo ""
        echo "Creating combined nodefile..."
        cat ~/nodes_${SITE1}.txt ~/nodes_${SITE2}.txt > ~/combined_nodes.txt

        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║   NODES COMBINED                                         ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        cat ~/combined_nodes.txt | awk -F. '{print "  - " $0 " [" $2 "]"}'
        echo ""

        echo "To run multi-site execution:"
        echo ""
        echo "  export OAR_NODEFILE=~/combined_nodes.txt"
        echo "  cd ~/wordcount-distributed"
        echo "  bash deploy/run_multi_site.sh"
        echo ""
    fi
fi
