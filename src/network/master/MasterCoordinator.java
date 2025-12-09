package network.master;

import benchmark.BenchmarkManager;
import config.Configuration;
import config.FileTransferMethod;
import network.worker.WorkerInterface;

import java.io.File;
import java.rmi.Naming;

/**
 * Coordinates task execution on worker nodes via RMI.
 * Refactored to remove circular dependencies.
 * Supports both NFS and SCP file transfer methods with benchmarking.
 */
public class MasterCoordinator {

    /**
     * Executes a command on a worker node.
     * Simplified version - assumes all input files are pre-deployed to workers.
     * @param command The command to execute
     * @param workerHost The worker hostname
     * @param workerPort The worker RMI port
     * @param masterHostname The master hostname
     * @param taskName The name of the task (used for result retrieval)
     * @return Exit code from the command
     */
    public static int executeOnWorker(String command, String workerHost, int workerPort, String masterHostname, String taskName) {
        if (command == null || command.trim().isEmpty()) {
            System.err.println("[MASTER] Invalid command");
            return -1;
        }

        if (workerHost == null || workerHost.trim().isEmpty()) {
            System.err.println("[MASTER] Invalid worker host");
            return -1;
        }

        long taskStartTime = System.currentTimeMillis();

        try {
            System.out.println("[MASTER] Connecting to worker: " + workerHost + ":" + workerPort);
            String workerUrl = Configuration.buildRmiUrl(workerHost, workerPort);
            WorkerInterface worker = (WorkerInterface) Naming.lookup(workerUrl);

            System.out.println("[MASTER] Executing on " + workerHost + ":" + workerPort + ": " + command);
            long cmdStartTime = System.currentTimeMillis();
            int exitCode = worker.executeCommand(command);
            long cmdDuration = System.currentTimeMillis() - cmdStartTime;

            // Record command execution time
            if (Configuration.isBenchmarkingEnabled()) {
                try {
                    BenchmarkManager.getInstance().recordCommandExecution(taskName, cmdDuration);
                } catch (IllegalStateException e) {
                    // BenchmarkManager not initialized, skip recording
                }
            }

            if (exitCode == 0 && taskName != null) {
                retrieveResults(taskName, workerHost, masterHostname);
            }

            // Record total task time
            if (Configuration.isBenchmarkingEnabled()) {
                try {
                    long totalDuration = System.currentTimeMillis() - taskStartTime;
                    BenchmarkManager.getInstance().recordTotalTask(taskName, totalDuration);
                } catch (IllegalStateException e) {
                    // BenchmarkManager not initialized, skip recording
                }
            }

            return exitCode;

        } catch (Exception e) {
            System.err.println("[MASTER] Error executing on worker " + workerHost + ": " + e.getMessage());
            e.printStackTrace();
            return -1;
        }
    }

    /**
     * Retrieves result files from the worker back to master.
     */
    private static void retrieveResults(String taskName, String workerHost, String masterHost) {
        try {
            if (taskName != null && taskName.contains(".")) {
                System.out.println("[MASTER] Retrieving result: " + taskName);
                transferFile(workerHost, masterHost, taskName);
            }
        } catch (Exception e) {
            System.err.println("[MASTER] Error retrieving results: " + e.getMessage());
        }
    }

    /**
     * Transfers a file between hosts using configured method (NFS or SCP).
     * Skips transfer if source and destination are both localhost.
     */
    private static void transferFile(String sourceHost, String destHost, String filename) {
        if (filename == null || filename.trim().isEmpty()) {
            System.err.println("[MASTER] Invalid filename for transfer");
            return;
        }

        // Skip transfer if both hosts are localhost (file is already accessible)
        boolean sourceIsLocal = isLocalhost(sourceHost);
        boolean destIsLocal = isLocalhost(destHost);

        if (sourceIsLocal && destIsLocal) {
            System.out.println("[MASTER] ✅ File available locally: " + filename);
            return;
        }

        long startTime = System.currentTimeMillis();
        long fileSize = getFileSize(filename);
        FileTransferMethod method = Configuration.getFileTransferMethod();

        try {
            boolean success = false;

            switch (method) {
                case NFS:
                    success = transferFileNFS(sourceHost, destHost, filename);
                    break;
                case SCP:
                    success = transferFileSCP(sourceHost, destHost, filename);
                    break;
            }

            long duration = System.currentTimeMillis() - startTime;

            // Record file transfer time
            if (Configuration.isBenchmarkingEnabled()) {
                try {
                    BenchmarkManager.getInstance().recordFileTransfer(filename, duration, filename, fileSize);
                } catch (IllegalStateException e) {
                    // BenchmarkManager not initialized, skip recording
                }
            }

            if (success) {
                System.out.println("[MASTER] ✅ File transferred (" + method + "): " + filename + " in " + duration + " ms");
            } else {
                System.err.println("[MASTER] ❌ File transfer failed (" + method + "): " + filename);
            }

        } catch (Exception e) {
            System.err.println("[MASTER] Error transferring file " + filename + ": " + e.getMessage());
        }
    }

    /**
     * Transfers a file using SCP.
     * Note: Requires passwordless SSH authentication (SSH keys must be configured).
     */
    private static boolean transferFileSCP(String sourceHost, String destHost, String filename) {
        try {
            // Use SSH options to avoid interactive prompts
            String command = "scp -o BatchMode=yes -o StrictHostKeyChecking=no " +
                           sourceHost + ":" + filename + " " + destHost + ":~";

            Process process = Runtime.getRuntime().exec(command);
            int exitCode = process.waitFor();

            if (exitCode != 0) {
                // Read error output for debugging
                java.io.BufferedReader errorReader = new java.io.BufferedReader(
                    new java.io.InputStreamReader(process.getErrorStream()));
                String errorLine;
                StringBuilder errorMsg = new StringBuilder();
                while ((errorLine = errorReader.readLine()) != null) {
                    errorMsg.append(errorLine).append("\n");
                }

                if (errorMsg.toString().contains("Permission denied") ||
                    errorMsg.toString().contains("password")) {
                    System.err.println("[MASTER] ⚠️  SCP authentication failed!");
                    System.err.println("[MASTER] 💡 Solution: Configure SSH keys for passwordless authentication:");
                    System.err.println("[MASTER]     1. ssh-keygen -t rsa -N \"\" -f ~/.ssh/id_rsa");
                    System.err.println("[MASTER]     2. ssh-copy-id " + sourceHost);
                    System.err.println("[MASTER]     3. Test: ssh " + sourceHost + " 'echo OK'");
                } else {
                    System.err.println("[MASTER] SCP error output: " + errorMsg);
                }
            }

            return exitCode == 0;
        } catch (Exception e) {
            System.err.println("[MASTER] SCP error: " + e.getMessage());
            return false;
        }
    }

    /**
     * Transfers a file using NFS (assumes shared filesystem).
     * In NFS mode, files are accessed directly via shared mount point.
     */
    private static boolean transferFileNFS(String sourceHost, String destHost, String filename) {
        try {
            String sharedPath = Configuration.getNfsSharedPath();
            File sourceFile = new File(sharedPath, filename);

            // In NFS, we just verify the file exists in the shared location
            if (sourceFile.exists()) {
                // File is already accessible via NFS
                return true;
            } else {
                // Need to copy to shared location
                String command = "cp " + filename + " " + sharedPath + "/";
                Process process = Runtime.getRuntime().exec(command);
                int exitCode = process.waitFor();
                return exitCode == 0;
            }
        } catch (Exception e) {
            System.err.println("[MASTER] NFS error: " + e.getMessage());
            return false;
        }
    }

    /**
     * Gets the size of a file in bytes.
     */
    private static long getFileSize(String filename) {
        try {
            File file = new File(filename);
            if (file.exists()) {
                return file.length();
            }
        } catch (Exception e) {
            // Ignore errors, return 0
        }
        return 0;
    }

    /**
     * Checks if a hostname refers to localhost.
     */
    private static boolean isLocalhost(String hostname) {
        if (hostname == null) return false;
        String normalized = hostname.trim().toLowerCase();
        return normalized.equals("localhost") ||
               normalized.equals("127.0.0.1") ||
               normalized.equals("::1") ||
               normalized.equals("0.0.0.0");
    }
}
