package cluster;

/**
 * Represents a compute node in the cluster.
 * Refactored with proper encapsulation and thread-safe status management.
 */
public class ComputeNode {
    public final String hostname;
    private volatile NodeStatus status;

    public ComputeNode(String hostname) {
        if (hostname == null || hostname.trim().isEmpty()) {
            throw new IllegalArgumentException("Hostname cannot be null or empty");
        }
        this.hostname = hostname;
        this.status = NodeStatus.FREE;
    }

    /**
     * Gets the current status of this node.
     * Thread-safe using volatile.
     * @return The current node status
     */
    public NodeStatus getStatus() {
        return status;
    }

    /**
     * Sets the status of this node.
     * Thread-safe using volatile.
     * @param status The new status
     */
    public void setStatus(NodeStatus status) {
        if (status == null) {
            throw new IllegalArgumentException("Status cannot be null");
        }
        this.status = status;
    }

    @Override
    public String toString() {
        return "ComputeNode{" + hostname + ", " + status + "}";
    }
}
