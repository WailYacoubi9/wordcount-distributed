package cluster;

import config.Configuration;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Manages the cluster of compute nodes.
 * Refactored to remove static mutable state and improve thread safety.
 */
public class ClusterManager {
    private final List<ComputeNode> nodes;
    private final ComputeNode masterNode;

    /**
     * Initializes the cluster with the given node list.
     * @param nodesList Comma-separated list of hostnames (can include brackets/quotes)
     * @throws IllegalArgumentException if nodesList is invalid
     */
    public ClusterManager(String nodesList) {
        if (nodesList == null || nodesList.trim().isEmpty()) {
            throw new IllegalArgumentException("Nodes list cannot be null or empty");
        }

        String cleaned = nodesList.replaceAll("[\\[\\]'\"]", "").trim();
        String[] hostnames = cleaned.split(",");

        List<ComputeNode> tempNodes = new ArrayList<>();
        System.out.println("[CLUSTER] Initializing cluster with " + hostnames.length + " nodes:");

        for (String hostname : hostnames) {
            hostname = hostname.trim();
            if (!hostname.isEmpty()) {
                validateHostname(hostname);
                ComputeNode node = new ComputeNode(hostname);
                tempNodes.add(node);
                System.out.println("[CLUSTER]   - " + hostname);
            }
        }

        if (tempNodes.isEmpty()) {
            throw new IllegalArgumentException("No valid nodes found in the list");
        }

        if (tempNodes.size() < Configuration.MIN_WORKER_NODES) {
            throw new IllegalArgumentException(
                String.format("At least %d worker node(s) required", Configuration.MIN_WORKER_NODES)
            );
        }

        if (tempNodes.size() > Configuration.MAX_WORKER_NODES) {
            throw new IllegalArgumentException(
                String.format("Maximum %d worker nodes allowed", Configuration.MAX_WORKER_NODES)
            );
        }

        this.nodes = Collections.synchronizedList(tempNodes);
        this.masterNode = tempNodes.get(0);
        System.out.println("[CLUSTER] Master node: " + masterNode.hostname);
        System.out.println("[CLUSTER] ✅ Cluster initialized with " + tempNodes.size() + " worker(s)\n");
    }

    /**
     * Gets a thread-safe view of the cluster nodes.
     * @return Synchronized list of nodes
     */
    public List<ComputeNode> getNodes() {
        return nodes;
    }

    /**
     * Gets the master node.
     * @return The master node
     */
    public ComputeNode getMasterNode() {
        return masterNode;
    }

    /**
     * Finds an available worker node and marks it as occupied.
     * This method is thread-safe.
     * @return An available ComputeNode, or null if none are available
     */
    public synchronized ComputeNode acquireAvailableNode() {
        for (ComputeNode node : nodes) {
            if (node.getStatus() == NodeStatus.FREE) {
                node.setStatus(NodeStatus.OCCUPIED);
                return node;
            }
        }
        return null;
    }

    /**
     * Releases a node back to the free pool.
     * This method is thread-safe.
     * @param node The node to release
     */
    public synchronized void releaseNode(ComputeNode node) {
        if (node != null) {
            node.setStatus(NodeStatus.FREE);
        }
    }

    /**
     * Prints the current status of all nodes in the cluster.
     */
    public void printClusterStatus() {
        System.out.println("\n[CLUSTER] Current Status:");
        System.out.println("========================");
        for (ComputeNode node : nodes) {
            String statusSymbol = node.getStatus() == NodeStatus.FREE ? "✅" : "⏳";
            System.out.println(statusSymbol + " " + node.hostname + " - " + node.getStatus());
        }
        System.out.println("========================\n");
    }

    /**
     * Validates a hostname format.
     * @param hostname The hostname to validate
     * @throws IllegalArgumentException if hostname is invalid
     */
    private void validateHostname(String hostname) {
        if (hostname == null || hostname.isEmpty()) {
            throw new IllegalArgumentException("Hostname cannot be null or empty");
        }
        // Basic validation - could be enhanced with regex for proper hostname format
        if (hostname.length() > 255) {
            throw new IllegalArgumentException("Hostname too long: " + hostname);
        }
    }
}
