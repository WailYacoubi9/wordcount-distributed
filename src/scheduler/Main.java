package scheduler;

import parser.MakefileParser;
import parser.Task;
import cluster.ClusterManager;

import java.util.List;
import java.util.Map;

/**
 * Main entry point for the distributed word count system.
 * Refactored with proper dependency injection and error handling.
 */
public class Main {
    public static void main(String[] args) {
        System.out.println("╔══════════════════════════════════════════════════════════╗");
        System.out.println("║   DISTRIBUTED WORD COUNT - Mono-Site Architecture       ║");
        System.out.println("╚══════════════════════════════════════════════════════════╝\n");

        if (args.length < 1) {
            System.err.println("Usage: java scheduler.Main \"[worker1,worker2,...]\"");
            System.err.println("Example: java scheduler.Main \"[nancy-2.grid5000.fr,nancy-3.grid5000.fr]\"");
            System.err.println("Local test: java scheduler.Main \"[localhost]\"");
            System.exit(1);
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

            // Inject cluster manager into all tasks
            System.out.println("[MAIN] Configuring tasks with cluster manager...");
            for (Task task : graph.keySet()) {
                task.setClusterManager(clusterManager);
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
