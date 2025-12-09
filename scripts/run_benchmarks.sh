#!/bin/bash

# Benchmark Runner Script for NFS vs SCP Comparison
# This script automates the benchmarking process for comparing file transfer methods

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "╔══════════════════════════════════════════════════════════╗"
echo "║      BENCHMARK RUNNER - NFS vs SCP Comparison           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Default configuration
WORKERS="[localhost]"
RUNS=3
OUTPUT_BASE="benchmarks"
COMPILE=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --workers)
            WORKERS="$2"
            shift 2
            ;;
        --runs)
            RUNS="$2"
            shift 2
            ;;
        --output)
            OUTPUT_BASE="$2"
            shift 2
            ;;
        --no-compile)
            COMPILE=false
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --workers <list>     Worker list (default: [localhost])"
            echo "  --runs <number>      Number of runs per method (default: 3)"
            echo "  --output <dir>       Output directory (default: benchmarks)"
            echo "  --no-compile         Skip compilation step"
            echo "  --help               Show this help message"
            echo ""
            echo "Example:"
            echo "  $0 --workers \"[localhost]\" --runs 5 --output my_benchmarks"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Project paths
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$PROJECT_DIR/src"
BIN_DIR="$PROJECT_DIR/bin"
BENCHMARK_DIR="$PROJECT_DIR/$OUTPUT_BASE"

cd "$PROJECT_DIR"

# Compile project if needed
if [ "$COMPILE" = true ]; then
    echo -e "${BLUE}[1/5]${NC} Compiling project..."
    mkdir -p "$BIN_DIR"

    # Find all Java files
    find "$SRC_DIR" -name "*.java" > /tmp/sources.txt

    # Compile
    javac -d "$BIN_DIR" -sourcepath "$SRC_DIR" @/tmp/sources.txt

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Compilation successful${NC}"
    else
        echo -e "${RED}❌ Compilation failed${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠️  Skipping compilation${NC}"
fi

# Clean previous benchmark results
echo -e "\n${BLUE}[2/5]${NC} Cleaning previous results..."
rm -rf "$BENCHMARK_DIR"
mkdir -p "$BENCHMARK_DIR"

# Function to run benchmark
run_benchmark() {
    local method=$1
    local run_number=$2
    local output_dir="$BENCHMARK_DIR/${method,,}"

    echo -e "\n${YELLOW}▶${NC} Running $method benchmark (run $run_number/$RUNS)..."

    mkdir -p "$output_dir"

    # Run the benchmark
    java -cp "$BIN_DIR" scheduler.Main "$WORKERS" --method=$method --benchmark --output-dir="$output_dir" 2>&1 | tee "$output_dir/run_${run_number}.log"

    local exit_code=${PIPESTATUS[0]}

    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✅ $method run $run_number completed${NC}"
        return 0
    else
        echo -e "${RED}❌ $method run $run_number failed${NC}"
        return 1
    fi
}

# Run SCP benchmarks
echo -e "\n${BLUE}[3/5]${NC} Running SCP benchmarks..."
scp_success=0
for i in $(seq 1 $RUNS); do
    if run_benchmark "SCP" $i; then
        ((scp_success++))
    fi
    sleep 2  # Brief pause between runs
done

# Run NFS benchmarks
echo -e "\n${BLUE}[4/5]${NC} Running NFS benchmarks..."
nfs_success=0
for i in $(seq 1 $RUNS); do
    if run_benchmark "NFS" $i; then
        ((nfs_success++))
    fi
    sleep 2  # Brief pause between runs
done

# Summary
echo -e "\n${BLUE}[5/5]${NC} Benchmark Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "SCP: ${GREEN}$scp_success${NC}/$RUNS successful runs"
echo -e "NFS: ${GREEN}$nfs_success${NC}/$RUNS successful runs"
echo ""

# Check if we have results to analyze
if [ $scp_success -eq 0 ] && [ $nfs_success -eq 0 ]; then
    echo -e "${RED}❌ No successful benchmark runs. Cannot generate graphs.${NC}"
    exit 1
fi

# Generate graphs using Python script
echo -e "${BLUE}Generating comparison graphs...${NC}"
if command -v python3 &> /dev/null; then
    if [ -f "$PROJECT_DIR/scripts/generate_benchmark_graphs.py" ]; then
        python3 "$PROJECT_DIR/scripts/generate_benchmark_graphs.py" "$BENCHMARK_DIR"
        echo ""
        echo -e "${GREEN}✅ Graphs generated successfully!${NC}"
        echo -e "${BLUE}📂 Results location: $BENCHMARK_DIR/graphs/${NC}"
        echo ""
        echo "Generated files:"
        ls -lh "$BENCHMARK_DIR/graphs/" | grep -v "^total" | awk '{print "  📊 " $9 " (" $5 ")"}'
    else
        echo -e "${YELLOW}⚠️  Graph generation script not found${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Python3 not found. Install Python3 and required packages:${NC}"
    echo "     pip3 install pandas matplotlib seaborn"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Benchmark process completed!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
