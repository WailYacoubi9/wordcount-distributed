package scheduler;

import cluster.ClusterManager;
import cluster.ComputeNode;
import parser.Task;
import parser.TaskStatus;
import utils.FileSplitter;

import java.io.File;
import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

/**
 * Dynamic distributed word count with automatic file splitting.
 * Accepts any input file and divides it equitably among workers.
 */
public class DynamicMain {

    public static void main(String[] args) {
        System.out.println("╔══════════════════════════════════════════════════════════╗");
        System.out.println("║   DYNAMIC DISTRIBUTED WORD COUNT                        ║");
        System.out.println("║   Automatic Load Balancing                              ║");
        System.out.println("╚══════════════════════════════════════════════════════════╝\n");

        if (args.length < 2) {
            System.err.println("Usage: java scheduler.DynamicMain <input-file> \"[worker1,worker2,...]\"");
            System.err.println("");
            System.err.println("Examples:");
            System.err.println("  Local test with 1 worker:");
            System.err.println("    java scheduler.DynamicMain myfile.txt \"[localhost]\"");
            System.err.println("");
            System.err.println("  Local test with 3 workers:");
            System.err.println("    java scheduler.DynamicMain myfile.txt \"[localhost:3000,localhost:3001,localhost:3002]\"");
            System.err.println("");
            System.err.println("  Grid5000:");
            System.err.println("    java scheduler.DynamicMain input.txt \"[node1.grid5000.fr,node2.grid5000.fr]\"");
            System.exit(1);
        }

        String inputFile = args[0];
        String workerList = args[1];

        // Validate input file
        File file = new File(inputFile);
        if (!file.exists() || !file.isFile()) {
            System.err.println("[MAIN] ❌ Input file not found: " + inputFile);
            System.exit(1);
        }

        System.out.println("[MAIN] Input file: " + inputFile);
        System.out.println("[MAIN] File size: " + file.length() + " bytes");

        List<String> splitFiles = new ArrayList<>();

        try {
            // Initialize cluster
            System.out.println("\n[MAIN] Initializing cluster...");
            ClusterManager clusterManager = new ClusterManager(workerList);
            int numWorkers = clusterManager.getNodes().size();

            System.out.println("[MAIN] Number of workers: " + numWorkers);

            // Split input file equitably
            System.out.println("\n[MAIN] Splitting input file into " + numWorkers + " parts...");
            splitFiles = FileSplitter.splitFileEquitably(inputFile, numWorkers, "part");

            // Ensure wordcount binary exists
            System.out.println("\n[MAIN] Checking wordcount binary...");
            File wordcountBinary = new File("wordcount");
            if (!wordcountBinary.exists()) {
                System.out.println("[MAIN] Compiling wordcount...");
                compileWordcount(clusterManager);
            }

            // Create and execute tasks
            System.out.println("\n[MAIN] Creating tasks for " + splitFiles.size() + " parts...");
            List<Task> tasks = createTasks(splitFiles, clusterManager);

            System.out.println("[MAIN] Executing tasks in parallel...\n");
            Map<Task, Integer> results = executeTasks(tasks);

            // Aggregate results
            System.out.println("\n[MAIN] Aggregating results...");
            int totalWords = 0;
            for (Map.Entry<Task, Integer> entry : results.entrySet()) {
                int count = entry.getValue();
                totalWords += count;
                System.out.println("  " + entry.getKey().getTaskName() + ": " + count + " words");
            }

            System.out.println("\n╔══════════════════════════════════════════════════════════╗");
            System.out.println("║   TOTAL WORD COUNT: " + String.format("%-32d", totalWords) + "║");
            System.out.println("╚══════════════════════════════════════════════════════════╝");

            System.out.println("\n[MAIN] ✅ Distributed word count completed successfully!");

            // Cleanup
            System.out.println("\n[MAIN] Cleaning up temporary files...");
            FileSplitter.cleanupFiles(splitFiles);

        } catch (Exception e) {
            System.err.println("\n[MAIN] ❌ Error: " + e.getMessage());
            e.printStackTrace();

            // Cleanup on error
            FileSplitter.cleanupFiles(splitFiles);
            System.exit(1);
        }
    }

    /**
     * Compiles the wordcount binary on the master node.
     */
    private static void compileWordcount(ClusterManager clusterManager) throws Exception {
        ComputeNode masterNode = clusterManager.getMasterNode();
        Task compileTask = new Task("compile-wordcount", clusterManager);
        compileTask.addCommand("gcc -o wordcount test/wordcount.c");
        compileTask.execute();

        if (compileTask.getStatus() != TaskStatus.FINISHED) {
            throw new RuntimeException("Failed to compile wordcount");
        }
    }

    /**
     * Creates tasks for each split file.
     */
    private static List<Task> createTasks(List<String> splitFiles, ClusterManager clusterManager) {
        List<Task> tasks = new ArrayList<>();

        for (int i = 0; i < splitFiles.size(); i++) {
            String splitFile = splitFiles.get(i);
            String outputFile = "count" + (i + 1) + ".txt";
            String taskName = "count-" + splitFile;

            Task task = new Task(taskName, clusterManager);
            // Redirect output to file so we can read it back
            task.addCommand("./wordcount " + splitFile + " > " + outputFile);
            tasks.add(task);
        }

        return tasks;
    }

    /**
     * Executes tasks in parallel and returns results.
     */
    private static Map<Task, Integer> executeTasks(List<Task> tasks) throws Exception {
        ExecutorService executor = Executors.newCachedThreadPool();
        Map<Task, Future<Void>> futures = new HashMap<>();

        // Submit all tasks
        for (Task task : tasks) {
            Future<Void> future = executor.submit(() -> {
                task.execute();
                if (task.getStatus() != TaskStatus.FINISHED) {
                    throw new RuntimeException("Task " + task.getTaskName() + " failed");
                }
                return null;
            });
            futures.put(task, future);
        }

        // Wait for all tasks to complete
        for (Map.Entry<Task, Future<Void>> entry : futures.entrySet()) {
            try {
                entry.getValue().get();
            } catch (Exception e) {
                System.err.println("[MAIN] Error executing " + entry.getKey().getTaskName());
                throw e;
            }
        }

        executor.shutdown();

        // Read results from count files
        Map<Task, Integer> results = new HashMap<>();
        for (int i = 0; i < tasks.size(); i++) {
            Task task = tasks.get(i);
            String countFile = "count" + (i + 1) + ".txt";
            int count = readWordCountFromFile(countFile);
            results.put(task, count);
        }

        return results;
    }

    /**
     * Reads word count from a count file.
     */
    private static int readWordCountFromFile(String countFile) {
        try {
            java.io.BufferedReader reader = new java.io.BufferedReader(
                new java.io.FileReader(countFile)
            );
            String line = reader.readLine();
            reader.close();

            if (line != null && !line.trim().isEmpty()) {
                return Integer.parseInt(line.trim());
            }
        } catch (Exception e) {
            System.err.println("[MAIN] Error reading " + countFile + ": " + e.getMessage());
        }
        return 0;
    }
}
