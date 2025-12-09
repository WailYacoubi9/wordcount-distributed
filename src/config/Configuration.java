package config;

/**
 * Central configuration for the distributed word count system.
 * Eliminates magic numbers and provides a single source of truth for settings.
 */
public class Configuration {
    // RMI Configuration
    public static final int RMI_REGISTRY_PORT = 3000;
    public static final String RMI_SERVICE_NAME = "WorkerService";

    // Scheduler Configuration
    public static final int SCHEDULER_POLL_INTERVAL_MS = 500;
    public static final int SCHEDULER_TIMEOUT_HOURS = 1;

    // Task Configuration
    public static final int TASK_RETRY_BASE_WAIT_MS = 100;
    public static final int TASK_RETRY_RANDOM_RANGE_MS = 100;

    // Validation
    public static final int MIN_WORKER_NODES = 1;
    public static final int MAX_WORKER_NODES = 1000;

    // File Transfer Configuration
    private static FileTransferMethod fileTransferMethod = FileTransferMethod.SCP;
    private static String nfsSharedPath = "/tmp/wordcount_shared";
    private static boolean benchmarkingEnabled = false;
    private static String benchmarkOutputDir = "benchmarks";

    private Configuration() {
        // Prevent instantiation
        throw new UnsupportedOperationException("Configuration is a utility class");
    }

    /**
     * Gets the current file transfer method.
     * @return The configured file transfer method
     */
    public static FileTransferMethod getFileTransferMethod() {
        return fileTransferMethod;
    }

    /**
     * Sets the file transfer method.
     * @param method The file transfer method to use
     */
    public static void setFileTransferMethod(FileTransferMethod method) {
        if (method == null) {
            throw new IllegalArgumentException("File transfer method cannot be null");
        }
        fileTransferMethod = method;
        System.out.println("[CONFIG] File transfer method set to: " + method);
    }

    /**
     * Gets the NFS shared path.
     * @return The NFS shared path
     */
    public static String getNfsSharedPath() {
        return nfsSharedPath;
    }

    /**
     * Sets the NFS shared path.
     * @param path The NFS shared path
     */
    public static void setNfsSharedPath(String path) {
        if (path == null || path.trim().isEmpty()) {
            throw new IllegalArgumentException("NFS shared path cannot be null or empty");
        }
        nfsSharedPath = path;
    }

    /**
     * Checks if benchmarking is enabled.
     * @return true if benchmarking is enabled
     */
    public static boolean isBenchmarkingEnabled() {
        return benchmarkingEnabled;
    }

    /**
     * Enables or disables benchmarking.
     * @param enabled true to enable benchmarking
     */
    public static void setBenchmarkingEnabled(boolean enabled) {
        benchmarkingEnabled = enabled;
        System.out.println("[CONFIG] Benchmarking " + (enabled ? "enabled" : "disabled"));
    }

    /**
     * Gets the benchmark output directory.
     * @return The benchmark output directory
     */
    public static String getBenchmarkOutputDir() {
        return benchmarkOutputDir;
    }

    /**
     * Sets the benchmark output directory.
     * @param dir The benchmark output directory
     */
    public static void setBenchmarkOutputDir(String dir) {
        if (dir == null || dir.trim().isEmpty()) {
            throw new IllegalArgumentException("Benchmark output directory cannot be null or empty");
        }
        benchmarkOutputDir = dir;
    }

    /**
     * Builds the RMI URL for a given hostname using the default port.
     * @param hostname The hostname of the worker
     * @return The complete RMI URL
     */
    public static String buildRmiUrl(String hostname) {
        return buildRmiUrl(hostname, RMI_REGISTRY_PORT);
    }

    /**
     * Builds the RMI URL for a given hostname and port.
     * @param hostname The hostname of the worker
     * @param port The RMI registry port
     * @return The complete RMI URL
     */
    public static String buildRmiUrl(String hostname, int port) {
        if (hostname == null || hostname.trim().isEmpty()) {
            throw new IllegalArgumentException("Hostname cannot be null or empty");
        }
        if (port < 1024 || port > 65535) {
            throw new IllegalArgumentException("Port must be between 1024 and 65535");
        }
        return String.format("rmi://%s:%d/%s", hostname, port, RMI_SERVICE_NAME);
    }
}
