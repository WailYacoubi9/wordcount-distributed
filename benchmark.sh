#!/bin/bash

# Performance Benchmarking Script
# Tests different modes with various file sizes and multiple runs

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "╔══════════════════════════════════════════════════════════╗"
echo "║     PERFORMANCE BENCHMARKING TOOL                       ║"
echo "║     Tests: NFS vs SCP | Mono-site vs Multi-site         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Configuration
PROJECT_DIR="$HOME/wordcount-distributed"
RESULTS_DIR="$PROJECT_DIR/benchmark_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="$RESULTS_DIR/benchmark_${TIMESTAMP}.csv"

# Test parameters
FILE_SIZES=(1000 5000 10000 50000 100000)  # Lines in input file
NUM_RUNS=3  # Number of runs per test

# Create results directory
mkdir -p "$RESULTS_DIR"

echo "📋 Benchmark Configuration:"
echo "   File sizes (lines): ${FILE_SIZES[@]}"
echo "   Runs per test: $NUM_RUNS"
echo "   Results file: $RESULTS_FILE"
echo ""

# Check if in OAR job
if [ -z "$OAR_NODEFILE" ]; then
    echo "❌ Error: Not in an OAR job"
    echo "Reserve nodes first: oarsub -I -l nodes=5,walltime=1:00:00"
    exit 1
fi

# Count workers
TOTAL_NODES=$(cat $OAR_NODEFILE | uniq | wc -l)
NUM_WORKERS=$((TOTAL_NODES - 1))

echo "🖥️  Cluster info:"
echo "   Total nodes: $TOTAL_NODES"
echo "   Workers: $NUM_WORKERS"
echo ""

# Initialize CSV
echo "Mode,FileSize,Run,TimeTotal,TimeSplitting,TimeExecution,TimeAggregation,WordCount" > "$RESULTS_FILE"

# Function to generate test file
generate_test_file() {
    local size=$1
    local filename=$2

    echo -e "${BLUE}📝 Generating test file: $size lines${NC}"

    > "$filename"
    for i in $(seq 1 $size); do
        echo "This is line number $i with some test words for distributed counting system" >> "$filename"
    done
}

# Function to extract timing from logs
extract_time() {
    local log_file=$1
    local pattern=$2

    grep "$pattern" "$log_file" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1 || echo "0"
}

# Function to test NFS mode
test_nfs_mode() {
    local size=$1
    local run=$2
    local test_file=$3

    echo -e "${GREEN}🧪 Testing NFS mode - Size: $size lines - Run: $run${NC}"

    # Clean previous results
    rm -rf ~/nfs_wordcount/*

    # Run test
    local start_time=$(date +%s.%N)
    timeout 300 bash "$PROJECT_DIR/deploy/run_nfs_home.sh" "$test_file" > /tmp/bench_nfs_${size}_${run}.log 2>&1 || true
    local end_time=$(date +%s.%N)

    local total_time=$(awk "BEGIN {printf \"%.3f\", $end_time - $start_time}")

    # Extract result
    local word_count=$(cat ~/nfs_wordcount/total.txt 2>/dev/null || echo "0")

    # Write to CSV
    echo "NFS,$size,$run,$total_time,0,0,0,$word_count" >> "$RESULTS_FILE"

    echo "   ⏱️  Time: ${total_time}s | Words: $word_count"
}

# Function to test SCP mode
test_scp_mode() {
    local size=$1
    local run=$2
    local test_file=$3

    echo -e "${GREEN}🧪 Testing SCP mode - Size: $size lines - Run: $run${NC}"

    # Clean previous results
    rm -f ~/part*.txt ~/count*.txt ~/total.txt

    # Run test
    local start_time=$(date +%s.%N)
    timeout 300 bash "$PROJECT_DIR/deploy/run_mono_site.sh" "$test_file" > /tmp/bench_scp_${size}_${run}.log 2>&1 || true
    local end_time=$(date +%s.%N)

    local total_time=$(awk "BEGIN {printf \"%.3f\", $end_time - $start_time}")

    # Extract result
    local word_count=$(cat ~/total.txt 2>/dev/null || echo "0")

    # Write to CSV
    echo "SCP,$size,$run,$total_time,0,0,0,$word_count" >> "$RESULTS_FILE"

    echo "   ⏱️  Time: ${total_time}s | Words: $word_count"
}

# Main benchmarking loop
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     STARTING BENCHMARK TESTS                            ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

for size in "${FILE_SIZES[@]}"; do
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  Testing with file size: $size lines"
    echo "═══════════════════════════════════════════════════════════"

    # Generate test file
    TEST_FILE="/tmp/test_input_${size}.txt"
    generate_test_file "$size" "$TEST_FILE"

    # Run multiple tests
    for run in $(seq 1 $NUM_RUNS); do
        echo ""
        echo "--- Run $run/$NUM_RUNS ---"

        # Test NFS mode
        test_nfs_mode "$size" "$run" "$TEST_FILE"
        sleep 2

        # Test SCP mode
        test_scp_mode "$size" "$run" "$TEST_FILE"
        sleep 2
    done

    # Clean up test file
    rm -f "$TEST_FILE"
done

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     BENCHMARK COMPLETED                                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

echo "📊 Results saved to: $RESULTS_FILE"
echo ""

# Calculate averages
echo "📈 Computing averages..."
python3 - <<EOF
import csv
import sys
from collections import defaultdict

results = defaultdict(lambda: defaultdict(list))

with open('$RESULTS_FILE', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        mode = row['Mode']
        size = row['FileSize']
        time = float(row['TimeTotal'])
        results[mode][size].append(time)

print("\n📊 Average Times (seconds):")
print("=" * 60)
print(f"{'Mode':<10} {'Size (lines)':<15} {'Avg Time':<12} {'Std Dev':<10}")
print("=" * 60)

for mode in sorted(results.keys()):
    for size in sorted(results[mode].keys(), key=int):
        times = results[mode][size]
        avg = sum(times) / len(times)
        std = (sum((x - avg) ** 2 for x in times) / len(times)) ** 0.5
        print(f"{mode:<10} {size:<15} {avg:<12.3f} {std:<10.3f}")

print("=" * 60)
EOF

echo ""
echo "🎨 Generate graphs with:"
echo "   python3 $PROJECT_DIR/benchmark_plot.py $RESULTS_FILE"
echo ""
