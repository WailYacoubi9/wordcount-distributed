package benchmark;

import config.FileTransferMethod;

import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

/**
 * Manages benchmarking metrics for comparing file transfer methods.
 * Collects timing data and exports to CSV for visualization.
 */
public class BenchmarkManager {
    private static BenchmarkManager instance;
    private final ConcurrentMap<String, List<BenchmarkEntry>> metrics;
    private final FileTransferMethod transferMethod;
    private final long startTime;
    private final String outputDirectory;

    /**
     * Entry representing a single benchmark measurement.
     */
    public static class BenchmarkEntry {
        public final String taskName;
        public final String operation; // "file_transfer", "command_execution", "total_task"
        public final long durationMs;
        public final long timestamp;
        public final String filename;
        public final long fileSize;

        public BenchmarkEntry(String taskName, String operation, long durationMs, String filename, long fileSize) {
            this.taskName = taskName;
            this.operation = operation;
            this.durationMs = durationMs;
            this.timestamp = System.currentTimeMillis();
            this.filename = filename;
            this.fileSize = fileSize;
        }

        @Override
        public String toString() {
            return String.format("%s,%s,%d,%d,%s,%d",
                    taskName, operation, durationMs, timestamp, filename, fileSize);
        }
    }

    private BenchmarkManager(FileTransferMethod method, String outputDir) {
        this.transferMethod = method;
        this.metrics = new ConcurrentHashMap<>();
        this.startTime = System.currentTimeMillis();
        this.outputDirectory = outputDir != null ? outputDir : "benchmarks";
        System.out.println("[BENCHMARK] Initialized with method: " + method);
    }

    /**
     * Initializes the singleton instance.
     * @param method The file transfer method being benchmarked
     * @param outputDir Directory for benchmark results
     */
    public static synchronized void initialize(FileTransferMethod method, String outputDir) {
        if (instance == null) {
            instance = new BenchmarkManager(method, outputDir);
        }
    }

    /**
     * Gets the singleton instance.
     * @return The BenchmarkManager instance
     * @throws IllegalStateException if not initialized
     */
    public static BenchmarkManager getInstance() {
        if (instance == null) {
            throw new IllegalStateException("BenchmarkManager not initialized. Call initialize() first.");
        }
        return instance;
    }

    /**
     * Records a benchmark measurement.
     * @param taskName Name of the task
     * @param operation Type of operation
     * @param durationMs Duration in milliseconds
     * @param filename Name of file involved (can be null)
     * @param fileSize Size of file in bytes (0 if not applicable)
     */
    public void recordMetric(String taskName, String operation, long durationMs, String filename, long fileSize) {
        BenchmarkEntry entry = new BenchmarkEntry(taskName, operation, durationMs, filename, fileSize);
        metrics.computeIfAbsent(operation, k -> new ArrayList<>()).add(entry);

        System.out.println(String.format("[BENCHMARK] %s | %s | %d ms | %s",
                taskName, operation, durationMs, filename != null ? filename : "N/A"));
    }

    /**
     * Records a file transfer measurement.
     */
    public void recordFileTransfer(String taskName, long durationMs, String filename, long fileSize) {
        recordMetric(taskName, "file_transfer", durationMs, filename, fileSize);
    }

    /**
     * Records a command execution measurement.
     */
    public void recordCommandExecution(String taskName, long durationMs) {
        recordMetric(taskName, "command_execution", durationMs, null, 0);
    }

    /**
     * Records a total task measurement.
     */
    public void recordTotalTask(String taskName, long durationMs) {
        recordMetric(taskName, "total_task", durationMs, null, 0);
    }

    /**
     * Exports all metrics to CSV files.
     * Creates separate files for each operation type.
     */
    public void exportMetrics() {
        try {
            // Create output directory
            new java.io.File(outputDirectory).mkdirs();

            String timestamp = new SimpleDateFormat("yyyyMMdd_HHmmss").format(new Date());
            String methodName = transferMethod.name().toLowerCase();

            // Export all metrics to a single file
            String allMetricsFile = String.format("%s/benchmark_%s_%s.csv",
                    outputDirectory, methodName, timestamp);
            exportAllMetrics(allMetricsFile);

            // Export summary statistics
            String summaryFile = String.format("%s/summary_%s_%s.csv",
                    outputDirectory, methodName, timestamp);
            exportSummary(summaryFile);

            System.out.println("[BENCHMARK] Metrics exported to: " + outputDirectory);
            System.out.println("[BENCHMARK] - All metrics: " + allMetricsFile);
            System.out.println("[BENCHMARK] - Summary: " + summaryFile);

        } catch (IOException e) {
            System.err.println("[BENCHMARK] Error exporting metrics: " + e.getMessage());
            e.printStackTrace();
        }
    }

    /**
     * Exports all metrics to a single CSV file.
     */
    private void exportAllMetrics(String filename) throws IOException {
        try (PrintWriter writer = new PrintWriter(new FileWriter(filename))) {
            // Write header
            writer.println("transfer_method,task_name,operation,duration_ms,timestamp,filename,file_size");

            // Write all entries
            for (List<BenchmarkEntry> entries : metrics.values()) {
                for (BenchmarkEntry entry : entries) {
                    writer.printf("%s,%s%n", transferMethod.name(), entry.toString());
                }
            }
        }
    }

    /**
     * Exports summary statistics.
     */
    private void exportSummary(String filename) throws IOException {
        try (PrintWriter writer = new PrintWriter(new FileWriter(filename))) {
            writer.println("transfer_method,operation,count,total_ms,avg_ms,min_ms,max_ms");

            for (String operation : metrics.keySet()) {
                List<BenchmarkEntry> entries = metrics.get(operation);
                if (entries.isEmpty()) continue;

                long total = 0;
                long min = Long.MAX_VALUE;
                long max = Long.MIN_VALUE;

                for (BenchmarkEntry entry : entries) {
                    total += entry.durationMs;
                    min = Math.min(min, entry.durationMs);
                    max = Math.max(max, entry.durationMs);
                }

                double avg = (double) total / entries.size();

                writer.printf("%s,%s,%d,%d,%.2f,%d,%d%n",
                        transferMethod.name(), operation, entries.size(), total, avg, min, max);
            }
        }
    }

    /**
     * Prints a summary to console.
     */
    public void printSummary() {
        long totalDuration = System.currentTimeMillis() - startTime;

        System.out.println("\n╔══════════════════════════════════════════════════════════╗");
        System.out.println("║              BENCHMARK SUMMARY - " + transferMethod.name() + "                    ║");
        System.out.println("╚══════════════════════════════════════════════════════════╝");
        System.out.println("Total execution time: " + totalDuration + " ms");
        System.out.println();

        for (String operation : metrics.keySet()) {
            List<BenchmarkEntry> entries = metrics.get(operation);
            if (entries.isEmpty()) continue;

            long total = 0;
            for (BenchmarkEntry entry : entries) {
                total += entry.durationMs;
            }
            double avg = (double) total / entries.size();

            System.out.printf("%-20s: %3d operations, %6.2f ms avg, %7d ms total%n",
                    operation, entries.size(), avg, total);
        }
        System.out.println();
    }

    /**
     * Resets the singleton instance (for testing).
     */
    public static synchronized void reset() {
        instance = null;
    }
}
