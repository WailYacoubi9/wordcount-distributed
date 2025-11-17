package network.worker;

import config.Configuration;

import java.rmi.Naming;
import java.rmi.registry.LocateRegistry;

/**
 * Worker node that registers with RMI and waits for tasks.
 * Uses proper thread blocking instead of Long.MAX_VALUE sleep.
 */
public class WorkerNode {
    private static volatile boolean running = true;
    private static final Object lock = new Object();

    public static void main(String[] args) {
        if (args.length < 1) {
            System.err.println("Usage: java network.worker.WorkerNode <hostname>");
            System.exit(1);
        }

        String hostname = args[0];
        if (hostname == null || hostname.trim().isEmpty()) {
            System.err.println("[WORKER] ❌ Hostname cannot be empty");
            System.exit(1);
        }

        System.out.println("╔══════════════════════════════════════════════════════════╗");
        System.out.println("║   WORKER NODE STARTING                                   ║");
        System.out.println("╚══════════════════════════════════════════════════════════╝");
        System.out.println("[WORKER] Node: " + hostname);

        // Add shutdown hook for graceful termination
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.out.println("\n[WORKER] Shutting down gracefully...");
            running = false;
            synchronized (lock) {
                lock.notifyAll();
            }
        }));

        try {
            System.out.println("[WORKER] Creating RMI registry on port " + Configuration.RMI_REGISTRY_PORT + "...");
            LocateRegistry.createRegistry(Configuration.RMI_REGISTRY_PORT);

            System.out.println("[WORKER] Creating worker implementation...");
            WorkerImpl worker = new WorkerImpl();

            String url = Configuration.buildRmiUrl(hostname);
            Naming.rebind(url, worker);

            System.out.println("[WORKER] ✅ Worker ready and waiting for tasks!");
            System.out.println("[WORKER] RMI URL: " + url);
            System.out.println("[WORKER] Press Ctrl+C to stop");

            // Proper blocking mechanism
            synchronized (lock) {
                while (running) {
                    lock.wait();
                }
            }

            System.out.println("[WORKER] Worker stopped.");

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            System.err.println("[WORKER] Worker interrupted");
        } catch (Exception e) {
            System.err.println("[WORKER] ❌ Failed to start: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
}
