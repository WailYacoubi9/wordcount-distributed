#!/usr/bin/env python3
"""
Performance Benchmark Plotting Tool
Generates graphs comparing NFS vs SCP modes with multiple file sizes
"""

import sys
import csv
import matplotlib.pyplot as plt
import numpy as np
from collections import defaultdict

if len(sys.argv) != 2:
    print("Usage: python3 benchmark_plot.py <results_csv_file>")
    sys.exit(1)

results_file = sys.argv[1]

# Read results
results = defaultdict(lambda: defaultdict(list))

print(f"📊 Reading results from: {results_file}")

with open(results_file, 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        mode = row['Mode']
        size = int(row['FileSize'])
        time = float(row['TimeTotal'])
        results[mode][size].append(time)

# Calculate statistics
modes = sorted(results.keys())
sizes = sorted(set(size for mode in results.values() for size in mode.keys()))

print(f"📈 Modes found: {modes}")
print(f"📏 File sizes: {sizes}")
print()

# Prepare data for plotting
plot_data = {}
for mode in modes:
    plot_data[mode] = {
        'sizes': [],
        'means': [],
        'stds': [],
        'mins': [],
        'maxs': []
    }

    for size in sizes:
        if size in results[mode]:
            times = results[mode][size]
            plot_data[mode]['sizes'].append(size)
            plot_data[mode]['means'].append(np.mean(times))
            plot_data[mode]['stds'].append(np.std(times))
            plot_data[mode]['mins'].append(np.min(times))
            plot_data[mode]['maxs'].append(np.max(times))

# Create figure with subplots
fig, axes = plt.subplots(2, 2, figsize=(14, 10))
fig.suptitle('Distributed Word Count Performance Comparison\nNFS vs SCP', fontsize=16, fontweight='bold')

# Colors for modes
colors = {'NFS': '#2ecc71', 'SCP': '#3498db'}

# Plot 1: Line graph with error bars
ax1 = axes[0, 0]
for mode in modes:
    data = plot_data[mode]
    ax1.errorbar(data['sizes'], data['means'], yerr=data['stds'],
                 label=mode, marker='o', linewidth=2, markersize=8,
                 color=colors.get(mode, 'gray'), capsize=5, capthick=2)

ax1.set_xlabel('File Size (lines)', fontsize=12)
ax1.set_ylabel('Execution Time (seconds)', fontsize=12)
ax1.set_title('Average Execution Time by File Size', fontsize=13, fontweight='bold')
ax1.legend(fontsize=11)
ax1.grid(True, alpha=0.3)
ax1.set_xscale('log')

# Plot 2: Bar chart comparing modes
ax2 = axes[0, 1]
x = np.arange(len(sizes))
width = 0.35

for i, mode in enumerate(modes):
    data = plot_data[mode]
    offset = width * (i - len(modes)/2 + 0.5)
    bars = ax2.bar(x + offset, data['means'], width,
                   label=mode, color=colors.get(mode, 'gray'),
                   yerr=data['stds'], capsize=5)

ax2.set_xlabel('File Size (lines)', fontsize=12)
ax2.set_ylabel('Execution Time (seconds)', fontsize=12)
ax2.set_title('Mode Comparison by File Size', fontsize=13, fontweight='bold')
ax2.set_xticks(x)
ax2.set_xticklabels(sizes)
ax2.legend(fontsize=11)
ax2.grid(True, alpha=0.3, axis='y')

# Plot 3: Speedup comparison (if we have both modes)
ax3 = axes[1, 0]
if len(modes) == 2:
    mode1, mode2 = modes[0], modes[1]
    speedups = []
    speedup_sizes = []

    for size in sizes:
        if size in results[mode1] and size in results[mode2]:
            mean1 = np.mean(results[mode1][size])
            mean2 = np.mean(results[mode2][size])
            speedup = mean2 / mean1  # mode2 time / mode1 time
            speedups.append(speedup)
            speedup_sizes.append(size)

    ax3.plot(speedup_sizes, speedups, marker='o', linewidth=2,
             markersize=8, color='#e74c3c')
    ax3.axhline(y=1.0, color='gray', linestyle='--', linewidth=2,
                label='Equal performance')
    ax3.set_xlabel('File Size (lines)', fontsize=12)
    ax3.set_ylabel(f'Speedup ({mode2}/{mode1})', fontsize=12)
    ax3.set_title(f'{mode1} vs {mode2} Speedup', fontsize=13, fontweight='bold')
    ax3.legend(fontsize=11)
    ax3.grid(True, alpha=0.3)
    ax3.set_xscale('log')
else:
    ax3.text(0.5, 0.5, 'Need 2 modes for speedup comparison',
             ha='center', va='center', fontsize=12)
    ax3.axis('off')

# Plot 4: Box plot for variability
ax4 = axes[1, 1]
box_data = []
box_labels = []

for mode in modes:
    for size in sizes:
        if size in results[mode]:
            box_data.append(results[mode][size])
            box_labels.append(f'{mode}\n{size}')

bp = ax4.boxplot(box_data, labels=box_labels, patch_artist=True)

# Color boxes by mode
for i, patch in enumerate(bp['boxes']):
    mode = box_labels[i].split('\n')[0]
    patch.set_facecolor(colors.get(mode, 'gray'))
    patch.set_alpha(0.7)

ax4.set_xlabel('Mode / File Size', fontsize=12)
ax4.set_ylabel('Execution Time (seconds)', fontsize=12)
ax4.set_title('Execution Time Variability', fontsize=13, fontweight='bold')
ax4.grid(True, alpha=0.3, axis='y')
plt.setp(ax4.xaxis.get_majorticklabels(), rotation=45, ha='right', fontsize=8)

# Adjust layout
plt.tight_layout()

# Save figure
output_file = results_file.replace('.csv', '.png')
plt.savefig(output_file, dpi=300, bbox_inches='tight')
print(f"✅ Graph saved to: {output_file}")

# Print summary statistics
print("\n" + "="*60)
print("📊 PERFORMANCE SUMMARY")
print("="*60)

for mode in modes:
    print(f"\n{mode} Mode:")
    print("-" * 40)
    for size in sizes:
        if size in results[mode]:
            times = results[mode][size]
            print(f"  {size:>6} lines: {np.mean(times):6.3f}s ± {np.std(times):5.3f}s "
                  f"(min: {np.min(times):.3f}s, max: {np.max(times):.3f}s)")

# Speedup analysis
if len(modes) == 2:
    print(f"\n{'='*60}")
    print(f"⚡ SPEEDUP ANALYSIS ({modes[0]} vs {modes[1]})")
    print("="*60)

    for size in sizes:
        if size in results[modes[0]] and size in results[modes[1]]:
            mean1 = np.mean(results[modes[0]][size])
            mean2 = np.mean(results[modes[1]][size])
            speedup = mean2 / mean1

            if speedup > 1:
                faster_mode = modes[0]
                percentage = (speedup - 1) * 100
                symbol = "🚀"
            else:
                faster_mode = modes[1]
                percentage = (1/speedup - 1) * 100
                symbol = "🐌"
                speedup = 1/speedup

            print(f"  {size:>6} lines: {faster_mode} is {speedup:.2f}x faster "
                  f"({percentage:+.1f}%) {symbol}")

print("\n" + "="*60)
print("✅ Benchmark analysis completed!")
print("="*60)

# Display the plot
plt.show()
