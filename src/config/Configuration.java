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

    private Configuration() {
        // Prevent instantiation
        throw new UnsupportedOperationException("Configuration is a utility class");
    }

    /**
     * Builds the RMI URL for a given hostname.
     * @param hostname The hostname of the worker
     * @return The complete RMI URL
     */
    public static String buildRmiUrl(String hostname) {
        if (hostname == null || hostname.trim().isEmpty()) {
            throw new IllegalArgumentException("Hostname cannot be null or empty");
        }
        return String.format("rmi://%s:%d/%s", hostname, RMI_REGISTRY_PORT, RMI_SERVICE_NAME);
    }
}
