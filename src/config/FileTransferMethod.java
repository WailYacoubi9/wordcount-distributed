package config;

/**
 * Enumeration of file transfer methods for benchmarking.
 * Supports comparison between NFS and SCP approaches.
 */
public enum FileTransferMethod {
    /**
     * Network File System - shared filesystem approach.
     * Files are accessible via shared mount points.
     */
    NFS,

    /**
     * Secure Copy Protocol - explicit file transfer approach.
     * Files are copied between hosts using scp command.
     */
    SCP;

    /**
     * Parses a string to a FileTransferMethod enum.
     * @param method String representation (case-insensitive)
     * @return The corresponding FileTransferMethod
     * @throws IllegalArgumentException if method is invalid
     */
    public static FileTransferMethod fromString(String method) {
        if (method == null || method.trim().isEmpty()) {
            throw new IllegalArgumentException("File transfer method cannot be null or empty");
        }

        String normalized = method.trim().toUpperCase();
        switch (normalized) {
            case "NFS":
                return NFS;
            case "SCP":
                return SCP;
            default:
                throw new IllegalArgumentException("Invalid file transfer method: " + method + ". Valid options: NFS, SCP");
        }
    }
}
