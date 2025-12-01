package scheduler;

import parser.MakefileParser;
import parser.Task;
import parser.TaskStatus;
import cluster.ClusterManager;
import cluster.ComputeNode;
import utils.FileSplitter;

import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Main entry point for the distributed word count system.
 * Supports both static Makefile and dynamic input file with automatic Makefile generation.
 */
public class Main {
    public static void main(String[] args) {
        System.out.println("╔══════════════════════════════════════════════════════════╗");
        System.out.println("║   DISTRIBUTED WORD COUNT - Makefile-based System       ║");
        System.out.println("╚══════════════════════════════════════════════════════════╝\n");

        if (args.length < 1) {
            System.err.println("Usage:");
            System.err.println("  Static mode:  java scheduler.Main \"[worker1,worker2,...]\"");
            System.err.println("  Dynamic mode: java scheduler.Main <input-file> \"[worker1,worker2,...]\"");
            System.err.println("");
            System.err.println("Examples:");
            System.err.println("  Static:  java scheduler.Main \"[nancy-2.grid5000.fr,nancy-3.grid5000.fr]\"");
            System.err.println("  Dynamic: java scheduler.Main data.txt \"[nancy-2.grid5000.fr,nancy-3.grid5000.fr]\"");
            System.err.println("  Local:   java scheduler.Main input.txt \"[localhost]\"");
            System.exit(1);
        }

        try {
            // Determine mode and parse arguments
            boolean dynamicMode = args.length >= 2;
            String inputFile = null;
            String workerList = null;
            String makefilePath = "Makefile";
            List<String> splitFiles = null;

            if (dynamicMode) {
                inputFile = args[0];
                workerList = args[1];
                System.out.println("[MAIN] 🔄 Dynamic mode: Auto-generating Makefile from input file");
                System.out.println("[MAIN] Input file: " + inputFile);
            } else {
                workerList = args[0];
                System.out.println("[MAIN] 📄 Static mode: Using existing Makefile");
            }

            // Initialize cluster
            System.out.println("[MAIN] Initializing cluster...");
            ClusterManager clusterManager = new ClusterManager(workerList);
            int numWorkers = clusterManager.getNodes().size();

            // Dynamic mode: generate Makefile from input file
            if (dynamicMode) {
                File file = new File(inputFile);
                if (!file.exists() || !file.isFile()) {
                    System.err.println("[MAIN] ❌ Input file not found: " + inputFile);
                    System.exit(1);
                }

                System.out.println("[MAIN] File size: " + file.length() + " bytes");
                System.out.println("[MAIN] Splitting file into " + numWorkers + " parts...");

                // Split the input file
                splitFiles = FileSplitter.splitFileEquitably(inputFile, numWorkers, "part");

                // Distribute split files to all workers
                System.out.println("[MAIN] Distributing split files to workers...");
                distributeSplitFiles(splitFiles, clusterManager);

                // Generate Makefile
                makefilePath = "Makefile.generated";
                System.out.println("[MAIN] Generating Makefile: " + makefilePath);
                generateMakefile(makefilePath, splitFiles);
            }

            // Parse Makefile (either existing or generated)
            System.out.println("[MAIN] Parsing Makefile...");
            MakefileParser parser = new MakefileParser();
            Map<Task, List<Task>> graph = parser.processFile(makefilePath);

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

            // Cleanup in dynamic mode
            if (dynamicMode && splitFiles != null) {
                System.out.println("\n[MAIN] Cleaning up temporary files...");
                FileSplitter.cleanupFiles(splitFiles);
                new File(makefilePath).delete();
                System.out.println("[MAIN] ✅ Cleanup complete");
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

    /**
     * Distributes split files to all worker nodes using scp.
     */
    private static void distributeSplitFiles(List<String> splitFiles, ClusterManager clusterManager) {
        List<ComputeNode> nodes = clusterManager.getNodes();

        for (String splitFile : splitFiles) {
            for (ComputeNode node : nodes) {
                try {
                    String hostname = node.hostname;
                    String[] command = {"scp", "-q", splitFile, hostname + ":~/"};
                    Process process = Runtime.getRuntime().exec(command);
                    int exitCode = process.waitFor();

                    if (exitCode != 0) {
                        System.err.println("[MAIN] ⚠️  Failed to copy " + splitFile + " to " + hostname);
                    }
                } catch (Exception e) {
                    System.err.println("[MAIN] Error distributing " + splitFile + ": " + e.getMessage());
                }
            }
        }
        System.out.println("[MAIN] ✅ Split files distributed to all workers");
    }

    /**
     * Generates a Makefile from the split files.
     * Creates a dependency graph: total.txt depends on count*.txt, which depend on part*.txt and wordcount.
     */
    private static void generateMakefile(String makefilePath, List<String> splitFiles) throws Exception {
        PrintWriter writer = new PrintWriter(new FileWriter(makefilePath));

        // Generate wordcount binary target
        writer.println("wordcount: test/wordcount.c");
        writer.println("\tgcc -o wordcount test/wordcount.c");
        writer.println();

        // Generate count targets for each split file
        for (int i = 0; i < splitFiles.size(); i++) {
            String splitFile = splitFiles.get(i);
            String countFile = "count" + (i + 1) + ".txt";

            writer.println(countFile + ": " + splitFile + " wordcount");
            writer.println("\t./wordcount " + splitFile + " > " + countFile);
            writer.println();
        }

        // Generate total.txt target (aggregation)
        writer.print("total.txt:");
        for (int i = 0; i < splitFiles.size(); i++) {
            writer.print(" count" + (i + 1) + ".txt");
        }
        writer.println();
        writer.print("\tcat");
        for (int i = 0; i < splitFiles.size(); i++) {
            writer.print(" count" + (i + 1) + ".txt");
        }
        writer.println(" | awk '{sum += $1} END {print sum}' > total.txt");

        writer.close();
        System.out.println("[MAIN] ✅ Makefile generated with " + splitFiles.size() + " parts");
    }
}
