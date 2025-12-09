package scheduler;

import benchmark.BenchmarkManager;
import config.Configuration;
import config.FileTransferMethod;
import parser.MakefileParser;
import parser.Task;
import parser.TaskStatus;
import cluster.ClusterManager;

import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Main entry point for the distributed word count system.
 * Refactored with proper dependency injection and error handling.
 * Supports benchmarking and comparison of file transfer methods.
 */
public class Main {
    public static void main(String[] args) {
        System.out.println("╔══════════════════════════════════════════════════════════╗");
        System.out.println("║   DISTRIBUTED WORD COUNT - Mono-Site Architecture       ║");
        System.out.println("╚══════════════════════════════════════════════════════════╝\n");

        if (args.length < 1) {
            System.err.println("Usage: java scheduler.Main \"[worker1,worker2,...]\" [--method=SCP|NFS] [--benchmark] [--output-dir=<dir>]");
            System.err.println("Example: java scheduler.Main \"[nancy-2.grid5000.fr,nancy-3.grid5000.fr]\" --method=NFS --benchmark");
            System.err.println("Local test: java scheduler.Main \"[localhost]\" --method=SCP");
            System.err.println("Benchmark: java scheduler.Main \"[localhost]\" --method=SCP --benchmark --output-dir=benchmarks/scp");
            System.exit(1);
        }

        // Parse command line arguments
        String workersArg = args[0];
        FileTransferMethod method = FileTransferMethod.SCP; // default
        boolean enableBenchmark = false;
        String outputDir = "benchmarks";

        for (int i = 1; i < args.length; i++) {
            String arg = args[i];
            if (arg.startsWith("--method=")) {
                String methodStr = arg.substring("--method=".length());
                method = FileTransferMethod.fromString(methodStr);
            } else if (arg.equals("--benchmark")) {
                enableBenchmark = true;
            } else if (arg.startsWith("--output-dir=")) {
                outputDir = arg.substring("--output-dir=".length());
            }
        }

        // Configure system
        Configuration.setFileTransferMethod(method);
        Configuration.setBenchmarkingEnabled(enableBenchmark);
        Configuration.setBenchmarkOutputDir(outputDir);

        // Initialize benchmarking if enabled
        if (enableBenchmark) {
            BenchmarkManager.initialize(method, outputDir);
            System.out.println("[MAIN] Benchmarking enabled, output to: " + outputDir);
        }

        try {
            // Initialize cluster
            System.out.println("[MAIN] Initializing cluster...");
            ClusterManager clusterManager = new ClusterManager(args[0]);

            // Parse Makefile
            System.out.println("[MAIN] Parsing Makefile...");
            MakefileParser parser = new MakefileParser();
            Map<Task, List<Task>> graph = parser.processFile("Makefile");

            if (graph.isEmpty()) {
                System.err.println("[MAIN] ❌ No tasks found in Makefile. Exiting.");
                System.exit(1);
            }

            parser.printGraph();

            // Inject cluster manager into all tasks and mark file-only tasks as finished
            System.out.println("[MAIN] Configuring tasks with cluster manager...");

            // First, collect all tasks (including those only in dependency lists)
            Set<Task> allTasks = new HashSet<>(graph.keySet());
            for (List<Task> deps : graph.values()) {
                allTasks.addAll(deps);
            }

            // Configure all tasks
            for (Task task : allTasks) {
                task.setClusterManager(clusterManager);
                // Tasks with no commands represent files that already exist
                if (task.getCommands().isEmpty()) {
                    task.setStatus(TaskStatus.FINISHED);
                    System.out.println("[MAIN] File dependency " + task.getTaskName() + " marked as FINISHED");
                }
            }

            // Create and configure scheduler
            System.out.println("[MAIN] Creating task scheduler...");
            TaskScheduler scheduler = new TaskScheduler();

            for (Map.Entry<Task, List<Task>> entry : graph.entrySet()) {
                scheduler.addTask(entry.getKey(), entry.getValue());
            }

            System.out.println("[MAIN] Scheduler configured with " + scheduler.getTaskCount() + " tasks");
            System.out.println("[MAIN] Starting distributed execution...\n");

            scheduler.executeTasks();

            System.out.println("\n[MAIN] ✅ Distributed execution completed successfully!");

            // Export benchmark results if enabled
            if (enableBenchmark) {
                System.out.println("\n[MAIN] Exporting benchmark results...");
                BenchmarkManager.getInstance().printSummary();
                BenchmarkManager.getInstance().exportMetrics();
            }

        } catch (IllegalArgumentException e) {
            System.err.println("\n[MAIN] ❌ Configuration error: " + e.getMessage());
            System.exit(1);
        } catch (java.io.FileNotFoundException e) {
            System.err.println("\n[MAIN] ❌ Makefile not found: " + e.getMessage());
            System.err.println("[MAIN] Please ensure Makefile exists in the current directory");
            System.exit(1);
        } catch (java.io.IOException e) {
            System.err.println("\n[MAIN] ❌ IO error: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            System.err.println("\n[MAIN] ❌ Execution interrupted: " + e.getMessage());
            System.exit(1);
        } catch (Exception e) {
            System.err.println("\n[MAIN] ❌ Unexpected error: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
}
