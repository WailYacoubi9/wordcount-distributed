# Dynamic Distributed Word Count

## Overview

The **DynamicMain** system automatically divides any input file equitably among workers and performs distributed word counting with automatic load balancing.

## Key Features

✅ **Accepts any text file as input**
✅ **Automatic equitable file splitting** based on number of workers
✅ **Fair load distribution** (maximum 1 line difference between workers)
✅ **Parallel execution** across all workers
✅ **Automatic result aggregation**
✅ **Cleanup of temporary files**

## Usage

### Basic Syntax

```bash
java -cp bin scheduler.DynamicMain <input-file> "[worker1,worker2,...]"
```

### Examples

#### Local test with 1 worker:
```bash
# Start worker
java -cp bin network.worker.WorkerNode localhost &

# Run word count
java -cp bin scheduler.DynamicMain myfile.txt "[localhost]"
```

#### Local test with 3 workers (different ports):
```bash
# Start workers
java -cp bin network.worker.WorkerNode localhost 3000 &
java -cp bin network.worker.WorkerNode localhost 3001 &
java -cp bin network.worker.WorkerNode localhost 3002 &

# Run word count
java -cp bin scheduler.DynamicMain myfile.txt "[localhost:3000,localhost:3001,localhost:3002]"
```

#### Grid5000 deployment:
```bash
# Assuming nodes are reserved via OAR
java -cp bin scheduler.DynamicMain large-corpus.txt "[node1.grid5000.fr,node2.grid5000.fr,node3.grid5000.fr]"
```

## How It Works

### 1. File Splitting Algorithm

The system divides the input file by **line count** to ensure equitable distribution:

```
Total lines: N
Workers: W

Base lines per worker: N / W
Remainder: N % W

Distribution:
- First (N % W) workers get: (N / W) + 1 lines
- Remaining workers get: (N / W) lines
```

**Example:** 20 lines, 3 workers
- Worker 1: 7 lines (6 + 1)
- Worker 2: 7 lines (6 + 1)
- Worker 3: 6 lines

**Load balance:** Maximum 1 line difference = **perfectly equitable**

### 2. Execution Flow

```
Input File (myfile.txt)
        ↓
    [SPLIT]
        ↓
  ┌─────┴─────┬─────┐
  ↓           ↓     ↓
part1.txt  part2.txt part3.txt
  ↓           ↓     ↓
Worker 1    Worker 2 Worker 3
  ↓           ↓     ↓
  77 words   88 words 79 words
  └─────┬─────┴─────┘
        ↓
  [AGGREGATE]
        ↓
   244 words (TOTAL)
```

### 3. Automatic Cleanup

The system automatically:
- Deletes temporary split files (part*.txt)
- Keeps the count results (count*.txt) for verification
- Displays final aggregated result

## Advantages over Static Makefile

| Feature | Static (Makefile) | Dynamic (DynamicMain) |
|---------|-------------------|----------------------|
| Input flexibility | ❌ Hardcoded files only | ✅ Any text file |
| Load balancing | ❌ Manual pre-splitting | ✅ Automatic equitable split |
| Worker count | ❌ Fixed (5 parts) | ✅ Adapts to N workers |
| File cleanup | ❌ Manual | ✅ Automatic |
| Use case | Fixed datasets | ✅ Ad-hoc analysis |

## Performance Testing

Test case: `myinput.txt` (20 lines, 244 words, 1234 bytes)

**With 3 workers:**
- Splitting time: <100ms
- Parallel execution: All workers started simultaneously
- Distribution: 7, 7, 6 lines (perfectly balanced)
- Result: 244 words (verified ✅)

## When to Use Each System

### Use `Main.java` (Static Makefile) when:
- You have a fixed workflow with known dependencies
- Files are pre-split and optimized
- You need complex dependency graphs (like compilation)
- Working with the provided test data (part1-5.txt)

### Use `DynamicMain.java` (This system) when:
- Processing arbitrary text files
- Number of workers varies
- Need automatic load balancing
- Ad-hoc analysis and experimentation
- Simpler use case (just word counting)

## Technical Details

**Classes:**
- `scheduler.DynamicMain`: Entry point with file splitting and aggregation
- `utils.FileSplitter`: Equitable file splitting utility

**Distribution algorithm:** Line-based splitting with remainder distribution
**Concurrency:** Java ExecutorService with cached thread pool
**Aggregation:** Sum of partial counts from each worker

## See Also

- [README.md](README.md) - Original static system documentation
- [deploy/run_distributed.sh](deploy/run_distributed.sh) - Grid5000 deployment script
