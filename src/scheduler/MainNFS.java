package scheduler;

import parser.MakefileParser;
import parser.TaskNFS;
import parser.TaskStatus;
import cluster.ClusterManager;
import utils.FileSplitter;

import java.io.File;
import java.io.FileWriter;
import java.io.PrintWriter;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * NFS-based distributed word count system.
 * All workers access files through a shared NFS mount point.
 * No SCP transfer needed - files are directly accessible.
 */
public class MainNFS {
    private static final String DEFAULT_NFS_PATH = "/tmp/nfs_shared";

    public static void main(String[] args) {
        System.out.println("╔══════════════════════════════════════════════════════════╗");
        System.out.println("║   DISTRIBUTED WORD COUNT - NFS Version                 ║");
        System.out.println("╚══════════════════════════════════════════════════════════╝\n");

        if (args.length < 1) {
            System.err.println("Usage:");
            System.err.println("  Static mode:  java scheduler.MainNFS \"[worker1,worker2,...]\" [nfs-path]");
            System.err.println("  Dynamic mode: java scheduler.MainNFS <input-file> \"[worker1,worker2,...]\" [nfs-path]");
            System.err.println("");
            System.err.println("Examples:");
            System.err.println("  Static:  java scheduler.MainNFS \"[nancy-2.grid5000.fr,nancy-3.grid5000.fr]\" /tmp/nfs_shared");
            System.err.println("  Dynamic: java scheduler.MainNFS data.txt \"[nancy-2.grid5000.fr,nancy-3.grid5000.fr]\" /tmp/nfs_shared");
            System.err.println("  Local:   java scheduler.MainNFS input.txt \"[localhost]\"");
            System.err.println("");
            System.err.println("NFS Path: Directory shared across all nodes (default: /tmp/nfs_shared)");
            System.exit(1);
        }

        try {
            // Determine mode and parse arguments
            boolean dynamicMode = args.length >= 2 && !args[0].startsWith("[");
            String inputFile = null;
            String workerList = null;
            String nfsPath = DEFAULT_NFS_PATH;
            String makefilePath = "Makefile";
            List<String> splitFiles = null;

            if (dynamicMode) {
                inputFile = args[0];
                workerList = args[1];
                if (args.length >= 3) {
                    nfsPath = args[2];
                }
                System.out.println("[MAIN-NFS] 🔄 Dynamic mode: Auto-generating Makefile from input file");
                System.out.println("[MAIN-NFS] Input file: " + inputFile);
                System.out.println("[MAIN-NFS] NFS shared path: " + nfsPath);
            } else {
                workerList = args[0];
                if (args.length >= 2) {
                    nfsPath = args[1];
                }
                System.out.println("[MAIN-NFS] 📄 Static mode: Using existing Makefile");
                System.out.println("[MAIN-NFS] NFS shared path: " + nfsPath);
            }

            // Ensure NFS directory exists
            File nfsDir = new File(nfsPath);
            if (!nfsDir.exists()) {
                System.out.println("[MAIN-NFS] Creating NFS directory: " + nfsPath);
                if (!nfsDir.mkdirs()) {
                    System.err.println("[MAIN-NFS] ❌ Failed to create NFS directory");
                    System.exit(1);
                }
            }

            // Initialize cluster
            System.out.println("[MAIN-NFS] Initializing cluster...");
            ClusterManager clusterManager = new ClusterManager(workerList);
            int numWorkers = clusterManager.getNodes().size();

            // Dynamic mode: generate Makefile from input file
            if (dynamicMode) {
                File file = new File(inputFile);
                if (!file.exists() || !file.isFile()) {
                    System.err.println("[MAIN-NFS] ❌ Input file not found: " + inputFile);
                    System.exit(1);
                }

                System.out.println("[MAIN-NFS] File size: " + file.length() + " bytes");
                System.out.println("[MAIN-NFS] Splitting file into " + numWorkers + " parts in NFS directory...");

                // Split the input file directly into NFS directory
                String nfsPrefix = nfsPath + "/part";
                splitFiles = FileSplitter.splitFileEquitably(inputFile, numWorkers, nfsPrefix);

                // No distribution needed - files already in shared NFS!
                System.out.println("[MAIN-NFS] ✅ Files available in shared NFS directory (no transfer needed)");

                // Generate Makefile with NFS paths
                makefilePath = nfsPath + "/Makefile.generated";
                System.out.println("[MAIN-NFS] Generating Makefile: " + makefilePath);
                generateMakefileNFS(makefilePath, splitFiles, nfsPath);
            }

            // Parse Makefile (either existing or generated)
            System.out.println("[MAIN-NFS] Parsing Makefile...");
            MakefileParser parser = new MakefileParser();
            Map<TaskNFS, List<TaskNFS>> graph = parser.processFileNFS(makefilePath);

            if (graph.isEmpty()) {
                System.err.println("[MAIN-NFS] ❌ No tasks found in Makefile. Exiting.");
                System.exit(1);
            }

            parser.printGraphNFS();

            // Inject cluster manager and NFS path into all tasks
            System.out.println("[MAIN-NFS] Configuring tasks with cluster manager and NFS path...");

            // First, collect all tasks (including those only in dependency lists)
            Set<TaskNFS> allTasks = new HashSet<>(graph.keySet());
            for (List<TaskNFS> deps : graph.values()) {
                allTasks.addAll(deps);
            }

            // Configure all tasks
            for (TaskNFS task : allTasks) {
                task.setClusterManager(clusterManager);
                task.setNfsPath(nfsPath);
                // Tasks with no commands represent files that already exist
                if (task.getCommands().isEmpty()) {
                    task.setStatus(TaskStatus.FINISHED);
                    System.out.println("[MAIN-NFS] File dependency " + task.getTaskName() + " marked as FINISHED");
                }
            }

            // Create and configure scheduler
            System.out.println("[MAIN-NFS] Creating task scheduler...");
            TaskScheduler scheduler = new TaskScheduler();

            for (Map.Entry<TaskNFS, List<TaskNFS>> entry : graph.entrySet()) {
                scheduler.addTaskNFS(entry.getKey(), entry.getValue());
            }

            System.out.println("[MAIN-NFS] Scheduler configured with " + scheduler.getTaskCount() + " tasks");
            System.out.println("[MAIN-NFS] Starting distributed execution...\n");

            scheduler.executeTasks();

            System.out.println("\n[MAIN-NFS] ✅ Distributed execution completed successfully!");

            // Display result
            File resultFile = new File(nfsPath + "/total.txt");
            if (resultFile.exists()) {
                try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.FileReader(resultFile))) {
                    String result = reader.readLine();
                    System.out.println("\n╔════════════════════════════╗");
                    System.out.println("║  Total word count: " + result + "     ║");
                    System.out.println("╚════════════════════════════╝");
                }
            }

            // Optional cleanup in dynamic mode (commented out - keep files for verification)
            // if (dynamicMode && splitFiles != null) {
            //     System.out.println("\n[MAIN-NFS] Cleaning up temporary files...");
            //     FileSplitter.cleanupFiles(splitFiles);
            //     new File(makefilePath).delete();
            //     System.out.println("[MAIN-NFS] ✅ Cleanup complete");
            // }

        } catch (IllegalArgumentException e) {
            System.err.println("\n[MAIN-NFS] ❌ Configuration error: " + e.getMessage());
            System.exit(1);
        } catch (java.io.FileNotFoundException e) {
            System.err.println("\n[MAIN-NFS] ❌ Makefile not found: " + e.getMessage());
            System.err.println("[MAIN-NFS] Please ensure Makefile exists in the current directory");
            System.exit(1);
        } catch (java.io.IOException e) {
            System.err.println("\n[MAIN-NFS] ❌ IO error: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            System.err.println("\n[MAIN-NFS] ❌ Execution interrupted: " + e.getMessage());
            System.exit(1);
        } catch (Exception e) {
            System.err.println("\n[MAIN-NFS] ❌ Unexpected error: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }

    /**
     * Generates a Makefile from the split files with NFS paths.
     * All file paths use the shared NFS directory.
     */
    private static void generateMakefileNFS(String makefilePath, List<String> splitFiles, String nfsPath) throws Exception {
        PrintWriter writer = new PrintWriter(new FileWriter(makefilePath));

        // Generate wordcount binary target (in NFS directory)
        writer.println("wordcount: test/wordcount.c");
        writer.println("\tgcc -o " + nfsPath + "/wordcount test/wordcount.c");
        writer.println();

        // Generate count targets for each split file (all in NFS)
        for (int i = 0; i < splitFiles.size(); i++) {
            String splitFile = splitFiles.get(i);
            String countFile = nfsPath + "/count" + (i + 1) + ".txt";

            writer.println(countFile + ": " + splitFile + " wordcount");
            writer.println("\t" + nfsPath + "/wordcount " + splitFile + " > " + countFile);
            writer.println();
        }

        // Generate total.txt target (aggregation in NFS)
        writer.print(nfsPath + "/total.txt:");
        for (int i = 0; i < splitFiles.size(); i++) {
            writer.print(" " + nfsPath + "/count" + (i + 1) + ".txt");
        }
        writer.println();
        writer.print("\tcat");
        for (int i = 0; i < splitFiles.size(); i++) {
            writer.print(" " + nfsPath + "/count" + (i + 1) + ".txt");
        }
        writer.println(" | awk '{sum += $1} END {print sum}' > " + nfsPath + "/total.txt");

        writer.close();
        System.out.println("[MAIN-NFS] ✅ Makefile generated with " + splitFiles.size() + " parts (NFS paths)");
    }
}
