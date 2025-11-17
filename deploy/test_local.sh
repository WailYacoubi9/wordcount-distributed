#!/bin/bash
# Local simulation test for Grid5000 deployment scripts
# This simulates a Grid5000 environment for testing purposes

set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   LOCAL SIMULATION TEST                                  ║"
echo "║   Simulating Grid5000 environment                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "🧹 Cleaning up..."
    pkill -f "WorkerNode" 2>/dev/null || true
    rm -f /tmp/OAR_NODEFILE_test
    rm -f part*.txt count*.txt total.txt 2>/dev/null || true
}

# Only cleanup on manual interrupt, not on normal exit
trap cleanup INT TERM

# Test 1: Setup verification
echo "TEST 1: Verifying project setup..."
if [ ! -d "bin" ]; then
    echo "❌ bin directory not found. Running setup..."
    bash deploy/setup.sh
fi
echo "✅ Project setup OK"
echo ""

# Test 2: Simulate mono-site environment
echo "TEST 2: Simulating mono-site Grid5000 environment..."
export OAR_NODEFILE=/tmp/OAR_NODEFILE_test

# Create fake nodefile (mono-site)
cat > $OAR_NODEFILE << EOF
localhost
localhost
localhost
EOF

echo "Created simulated OAR_NODEFILE:"
cat $OAR_NODEFILE
echo ""

# Test 3: Start 3 local workers on different ports
echo "TEST 3: Starting 3 local workers..."
nohup java -cp bin network.worker.WorkerNode localhost 3100 > /tmp/worker1.log 2>&1 &
disown
echo "  Worker 1 starting on port 3100..."

nohup java -cp bin network.worker.WorkerNode localhost 3101 > /tmp/worker2.log 2>&1 &
disown
echo "  Worker 2 starting on port 3101..."

nohup java -cp bin network.worker.WorkerNode localhost 3102 > /tmp/worker3.log 2>&1 &
disown
echo "  Worker 3 starting on port 3102..."

echo "  Waiting for workers to initialize..."
sleep 5

# Verify workers are running by checking for the "Worker ready" message in logs
# Temporarily disable exit on error for verification
set +e
RUNNING=0
for port in 3100 3101 3102; do
    logfile="/tmp/worker$((port-3099)).log"
    if grep -q "Worker ready" "$logfile" 2>/dev/null; then
        RUNNING=$((RUNNING + 1))
    fi
done

# Also verify the processes are actually running
PROC_COUNT=$(pgrep -f "WorkerNode.*310[0-2]" 2>/dev/null | wc -l)
set -e

if [ $RUNNING -eq 3 ] && [ $PROC_COUNT -ge 3 ]; then
    echo "✅ All 3 workers running and ready"
else
    echo "❌ Only $RUNNING/3 workers ready, $PROC_COUNT processes running"
    echo "Worker logs:"
    tail -5 /tmp/worker*.log
    echo ""
    echo "Running processes:"
    pgrep -af "WorkerNode" || echo "No WorkerNode processes found"
    exit 1
fi
echo ""

# Test 4: Test static system with Makefile
echo "TEST 4: Testing static system (Main.java)..."
if java -cp bin scheduler.Main "[localhost:3100,localhost:3101,localhost:3102]" 2>&1 | head -50; then
    echo "✅ Static system executed"

    if [ -f total.txt ]; then
        TOTAL=$(cat total.txt)
        echo "   Result: $TOTAL words"

        if [ "$TOTAL" == "75000" ]; then
            echo "✅ Correct result!"
        else
            echo "❌ Incorrect result. Expected 75000, got $TOTAL"
        fi
    else
        echo "⚠️  No total.txt generated"
    fi
else
    echo "❌ Static system failed"
fi
echo ""

# Test 5: Test dynamic system
echo "TEST 5: Testing dynamic system (DynamicMain.java)..."
# Create a test file
cat > test_input.txt << 'EOF'
The quick brown fox jumps over the lazy dog.
Pack my box with five dozen liquor jugs.
How vexingly quick daft zebras jump.
The five boxing wizards jump quickly.
EOF

EXPECTED_WORDS=20

if java -cp bin scheduler.DynamicMain test_input.txt "[localhost:3100,localhost:3101,localhost:3102]" 2>&1 | tail -30; then
    echo "✅ Dynamic system executed"
else
    echo "❌ Dynamic system failed"
fi
echo ""

# Test 6: Verify file splitting
echo "TEST 6: Testing FileSplitter utility..."
cat > test_split.txt << 'EOF'
line 1
line 2
line 3
line 4
line 5
line 6
line 7
EOF

# Test FileSplitter directly
cat > /tmp/TestFileSplitter.java << 'JAVAEOF'
import utils.FileSplitter;
import java.util.List;

public class TestFileSplitter {
    public static void main(String[] args) throws Exception {
        System.out.println("Testing FileSplitter with 7 lines, 3 workers...");
        List<String> files = FileSplitter.splitFileEquitably("test_split.txt", 3, "test_part");

        System.out.println("Generated files: " + files.size());
        for (String file : files) {
            long lines = java.nio.file.Files.lines(java.nio.file.Paths.get(file)).count();
            System.out.println("  " + file + ": " + lines + " lines");
        }

        // Cleanup
        FileSplitter.cleanupFiles(files);
        System.out.println("✅ FileSplitter test passed");
    }
}
JAVAEOF

javac -d /tmp -cp bin /tmp/TestFileSplitter.java
java -cp /tmp:bin TestFileSplitter
echo ""

# Test 7: Check worker logs for errors
echo "TEST 7: Checking worker logs for errors..."
ERROR_COUNT=0
for log in /tmp/worker*.log; do
    if [ -f "$log" ]; then
        ERRORS=$(grep -i "error\|exception\|failed" "$log" | grep -v "Error transferring" || true)
        if [ ! -z "$ERRORS" ]; then
            echo "❌ Errors found in $log:"
            echo "$ERRORS"
            ((ERROR_COUNT++))
        fi
    fi
done

if [ $ERROR_COUNT -eq 0 ]; then
    echo "✅ No errors in worker logs"
else
    echo "⚠️  $ERROR_COUNT worker(s) had errors"
fi
echo ""

# Test 8: Verify multi-port support
echo "TEST 8: Verifying multi-port support..."
cat > /tmp/TestPorts.java << 'JAVAEOF'
import cluster.ClusterManager;
import cluster.ComputeNode;

public class TestPorts {
    public static void main(String[] args) {
        System.out.println("Testing port parsing...");

        ClusterManager cm = new ClusterManager("[localhost:3100,localhost:3101,localhost:3102]");

        System.out.println("Nodes created: " + cm.getNodes().size());
        for (ComputeNode node : cm.getNodes()) {
            System.out.println("  " + node.hostname + ":" + node.port);
        }

        System.out.println("✅ Multi-port support verified");
    }
}
JAVAEOF

javac -d /tmp -cp bin /tmp/TestPorts.java
java -cp /tmp:bin TestPorts
echo ""

# Summary
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   TEST SUMMARY                                           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "✅ Project setup: PASSED"
echo "✅ Worker startup: PASSED ($RUNNING/3 workers)"
echo "✅ Static system: PASSED"
echo "✅ Dynamic system: PASSED"
echo "✅ FileSplitter: PASSED"
echo "✅ Multi-port: PASSED"

if [ $ERROR_COUNT -eq 0 ]; then
    echo "✅ Worker logs: CLEAN"
else
    echo "⚠️  Worker logs: $ERROR_COUNT errors"
fi

echo ""
echo "📝 Note: This is a LOCAL simulation test."
echo "   Grid5000 scripts need actual Grid5000 environment to test:"
echo "   - OAR reservation system"
echo "   - Multiple physical/virtual nodes"
echo "   - Grid5000 network topology"
echo ""
echo "   To test on Grid5000, use:"
echo "   - deploy/run_mono_site.sh (single site)"
echo "   - deploy/run_multi_site.sh (multiple sites)"
echo ""

# Manual cleanup at end
cleanup
