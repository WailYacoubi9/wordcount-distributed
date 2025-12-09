package utils;

import java.io.*;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

/**
 * Utility class for file compression/decompression using GZIP.
 * Optimized for text file transfers in distributed systems.
 */
public class FileCompressor {

    private static final int BUFFER_SIZE = 65536; // 64 KB for optimal I/O

    /**
     * Compresses a file using GZIP compression.
     * @param inputFile Path to the file to compress
     * @return Path to the compressed file (.gz extension added)
     * @throws IOException if compression fails
     */
    public static String compress(String inputFile) throws IOException {
        if (inputFile == null || inputFile.trim().isEmpty()) {
            throw new IllegalArgumentException("Input file cannot be null or empty");
        }

        File input = new File(inputFile);
        if (!input.exists()) {
            throw new FileNotFoundException("Input file not found: " + inputFile);
        }

        String outputFile = inputFile + ".gz";
        long startTime = System.currentTimeMillis();
        long originalSize = input.length();

        try (FileInputStream fis = new FileInputStream(inputFile);
             FileOutputStream fos = new FileOutputStream(outputFile);
             GZIPOutputStream gzos = new GZIPOutputStream(fos, BUFFER_SIZE)) {

            byte[] buffer = new byte[BUFFER_SIZE];
            int len;
            long bytesRead = 0;

            while ((len = fis.read(buffer)) != -1) {
                gzos.write(buffer, 0, len);
                bytesRead += len;
            }

            gzos.finish(); // Ensure all data is written
        }

        long duration = System.currentTimeMillis() - startTime;
        File output = new File(outputFile);
        long compressedSize = output.length();

        double ratio = 100.0 * (1 - (double)compressedSize / originalSize);

        System.out.printf("[COMPRESS] %s (%,d bytes) -> %s (%,d bytes) | %.1f%% reduction in %d ms%n",
                         input.getName(), originalSize, output.getName(), compressedSize, ratio, duration);

        return outputFile;
    }

    /**
     * Decompresses a GZIP file.
     * @param inputFile Path to the .gz file to decompress
     * @return Path to the decompressed file
     * @throws IOException if decompression fails
     */
    public static String decompress(String inputFile) throws IOException {
        if (inputFile == null || !inputFile.endsWith(".gz")) {
            throw new IllegalArgumentException("Input file must have .gz extension");
        }

        File input = new File(inputFile);
        if (!input.exists()) {
            throw new FileNotFoundException("Compressed file not found: " + inputFile);
        }

        String outputFile = inputFile.substring(0, inputFile.length() - 3);
        long startTime = System.currentTimeMillis();
        long compressedSize = input.length();

        try (FileInputStream fis = new FileInputStream(inputFile);
             GZIPInputStream gzis = new GZIPInputStream(fis, BUFFER_SIZE);
             FileOutputStream fos = new FileOutputStream(outputFile)) {

            byte[] buffer = new byte[BUFFER_SIZE];
            int len;
            long bytesWritten = 0;

            while ((len = gzis.read(buffer)) != -1) {
                fos.write(buffer, 0, len);
                bytesWritten += len;
            }
        }

        long duration = System.currentTimeMillis() - startTime;
        File output = new File(outputFile);

        System.out.printf("[DECOMPRESS] %s (%,d bytes) -> %s (%,d bytes) in %d ms%n",
                         input.getName(), compressedSize, output.getName(), output.length(), duration);

        return outputFile;
    }

    /**
     * Determines if compression would be beneficial for a file transfer.
     * Uses heuristics based on file size and network topology.
     *
     * @param filename Path to the file
     * @param isLocal True if transfer is to localhost
     * @param isMonoSite True if transfer is within same Grid5000 site
     * @return True if compression is recommended
     */
    public static boolean shouldCompress(String filename, boolean isLocal, boolean isMonoSite) {
        File file = new File(filename);
        if (!file.exists()) {
            return false;
        }

        long size = file.length();

        // Files < 100 KB: compression overhead > transfer time saved
        if (size < 100_000) {
            System.out.println("[COMPRESS] Skip compression: file too small (" + size + " bytes)");
            return false;
        }

        // Local transfers: no network bottleneck
        if (isLocal) {
            System.out.println("[COMPRESS] Skip compression: local transfer");
            return false;
        }

        // Mono-site with small files: marginal gain
        if (isMonoSite && size < 1_000_000) {
            System.out.println("[COMPRESS] Skip compression: mono-site and file < 1 MB");
            return false;
        }

        // Multi-site or large files: compress for significant bandwidth savings
        System.out.println("[COMPRESS] Compression recommended for " + file.getName() +
                          " (" + String.format("%,d", size) + " bytes)");
        return true;
    }

    /**
     * Gets the compression ratio (as percentage) for a file without actually compressing it.
     * Uses sampling for large files to estimate compression ratio quickly.
     *
     * @param filename File to analyze
     * @param sampleSize Number of bytes to sample (0 = full file)
     * @return Estimated compression ratio (0-100), or -1 if estimation fails
     */
    public static double estimateCompressionRatio(String filename, int sampleSize) {
        File file = new File(filename);
        if (!file.exists()) {
            return -1;
        }

        long fileSize = file.length();
        long bytesToRead = (sampleSize > 0 && sampleSize < fileSize) ? sampleSize : fileSize;

        try (FileInputStream fis = new FileInputStream(filename);
             ByteArrayOutputStream baos = new ByteArrayOutputStream();
             GZIPOutputStream gzos = new GZIPOutputStream(baos)) {

            byte[] buffer = new byte[8192];
            long bytesRead = 0;
            int len;

            while (bytesRead < bytesToRead && (len = fis.read(buffer)) != -1) {
                int toWrite = (int) Math.min(len, bytesToRead - bytesRead);
                gzos.write(buffer, 0, toWrite);
                bytesRead += toWrite;
            }

            gzos.finish();

            double ratio = 100.0 * (1 - (double)baos.size() / bytesRead);
            System.out.printf("[COMPRESS] Estimated ratio for %s: %.1f%% (sample: %,d bytes)%n",
                             file.getName(), ratio, bytesRead);
            return ratio;

        } catch (IOException e) {
            System.err.println("[COMPRESS] Failed to estimate compression ratio: " + e.getMessage());
            return -1;
        }
    }

    /**
     * Compresses a file only if it would result in significant space savings.
     *
     * @param inputFile File to potentially compress
     * @param minRatio Minimum compression ratio (%) to justify compression
     * @return Path to compressed file if compressed, or original file if not
     * @throws IOException if compression fails
     */
    public static String compressIfWorthwhile(String inputFile, double minRatio) throws IOException {
        // Estimate compression ratio by sampling first 100KB
        double estimatedRatio = estimateCompressionRatio(inputFile, 100_000);

        if (estimatedRatio < 0) {
            System.out.println("[COMPRESS] Could not estimate ratio, compressing anyway");
            return compress(inputFile);
        }

        if (estimatedRatio < minRatio) {
            System.out.printf("[COMPRESS] Skip compression: estimated ratio %.1f%% < threshold %.1f%%%n",
                             estimatedRatio, minRatio);
            return inputFile; // Return original file
        }

        System.out.printf("[COMPRESS] Estimated ratio %.1f%% >= threshold %.1f%%, compressing...%n",
                         estimatedRatio, minRatio);
        return compress(inputFile);
    }

    /**
     * Test method to demonstrate compression capabilities.
     */
    public static void main(String[] args) {
        if (args.length < 1) {
            System.out.println("Usage: java utils.FileCompressor <file> [decompress]");
            System.out.println("  Compress:   java utils.FileCompressor file.txt");
            System.out.println("  Decompress: java utils.FileCompressor file.txt.gz decompress");
            return;
        }

        try {
            String inputFile = args[0];

            if (args.length > 1 && args[1].equals("decompress")) {
                // Decompress mode
                String outputFile = decompress(inputFile);
                System.out.println("✅ Decompressed to: " + outputFile);
            } else {
                // Compress mode
                File file = new File(inputFile);
                System.out.println("Analyzing file: " + inputFile);
                System.out.println("Size: " + String.format("%,d", file.length()) + " bytes");

                // Estimate compression ratio
                double ratio = estimateCompressionRatio(inputFile, 0);
                System.out.printf("Estimated compression: %.1f%%%n", ratio);

                // Perform compression
                String compressed = compress(inputFile);
                System.out.println("✅ Compressed to: " + compressed);

                // Verify by decompressing
                System.out.println("\nVerifying compression...");
                String decompressed = decompress(compressed);
                System.out.println("✅ Verification successful: " + decompressed);
            }

        } catch (IOException e) {
            System.err.println("❌ Error: " + e.getMessage());
            e.printStackTrace();
        }
    }
}
