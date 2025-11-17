package scheduler;

import config.Configuration;
import parser.Task;
import parser.TaskStatus;

import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/**
 * Schedules and executes tasks based on their dependencies.
 * Refactored to remove static state and improve testability.
 */
public class TaskScheduler {
    private final Map<Task, List<Task>> dependencyGraph;

    public TaskScheduler() {
        this.dependencyGraph = new HashMap<>();
    }

    /**
     * Adds a task with its dependencies to the scheduler.
     * @param task The task to add
     * @param dependencies List of tasks that must complete before this task
     * @throws IllegalArgumentException if task is null
     */
    public void addTask(Task task, List<Task> dependencies) {
        if (task == null) {
            throw new IllegalArgumentException("Task cannot be null");
        }
        if (dependencies == null) {
            dependencies = new ArrayList<>();
        }
        dependencyGraph.put(task, dependencies);
    }

    /**
     * Executes all tasks in the dependency graph, respecting dependencies.
     * @throws InterruptedException if execution is interrupted
     * @throws IllegalStateException if no tasks are scheduled
     */
    public void executeTasks() throws InterruptedException {
        if (dependencyGraph.isEmpty()) {
            throw new IllegalStateException("No tasks scheduled for execution");
        }

        System.out.println("\n[SCHEDULER] Starting task execution...");
        ExecutorService executor = Executors.newCachedThreadPool();

        int iteration = 0;
        while (!allTasksCompleted()) {
            iteration++;
            System.out.println("\n[SCHEDULER] Iteration " + iteration + " - Checking for ready tasks...");

            for (Map.Entry<Task, List<Task>> entry : dependencyGraph.entrySet()) {
                Task task = entry.getKey();

                if (canBeExecuted(task)) {
                    task.setStatus(TaskStatus.IN_PROGRESS);
                    System.out.println("[SCHEDULER] Launching task: " + task.getTaskName());
                    executor.submit(task::execute);
                }
            }

            Thread.sleep(Configuration.SCHEDULER_POLL_INTERVAL_MS);
        }

        System.out.println("\n[SCHEDULER] All tasks submitted, waiting for completion...");
        executor.shutdown();
        if (!executor.awaitTermination(Configuration.SCHEDULER_TIMEOUT_HOURS, TimeUnit.HOURS)) {
            System.err.println("[SCHEDULER] ⚠️  Timeout waiting for tasks to complete");
            executor.shutdownNow();
        }

        System.out.println("\n[SCHEDULER] ✅ All tasks completed!");
        printFinalStatus();
    }

    /**
     * Checks if a task can be executed based on its status and dependencies.
     * @param task The task to check
     * @return true if the task can be executed now
     */
    private boolean canBeExecuted(Task task) {
        if (task.getStatus() != TaskStatus.NOT_STARTED) {
            return false;
        }

        List<Task> dependencies = dependencyGraph.get(task);
        if (dependencies == null || dependencies.isEmpty()) {
            return true;
        }

        return dependencies.stream()
                .allMatch(dep -> dep.getStatus() == TaskStatus.FINISHED);
    }

    /**
     * Checks if all tasks have completed (either finished or failed).
     * @return true if all tasks are done
     */
    private boolean allTasksCompleted() {
        return dependencyGraph.keySet().stream()
                .allMatch(task -> task.getStatus() == TaskStatus.FINISHED ||
                                  task.getStatus() == TaskStatus.FAILED);
    }

    /**
     * Prints the final status of all tasks.
     */
    private void printFinalStatus() {
        System.out.println("\n[SCHEDULER] Final Status:");
        System.out.println("========================");
        for (Task task : dependencyGraph.keySet()) {
            String statusSymbol = task.getStatus() == TaskStatus.FINISHED ? "✅" : "❌";
            System.out.println(statusSymbol + " " + task.getTaskName() + " - " + task.getStatus());
        }
        System.out.println("========================\n");
    }

    /**
     * Gets the number of tasks in the scheduler.
     * @return The task count
     */
    public int getTaskCount() {
        return dependencyGraph.size();
    }
}
