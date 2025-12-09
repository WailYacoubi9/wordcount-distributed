#!/usr/bin/env python3
"""
Benchmark Visualization Script for NFS vs SCP Comparison

This script generates comparative graphs from benchmark CSV files
produced by the distributed word count system.

Usage:
    python3 generate_benchmark_graphs.py <benchmarks_directory>

Example:
    python3 generate_benchmark_graphs.py benchmarks/
"""

import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import glob
import sys
import os
from pathlib import Path

# Set style for better-looking graphs
sns.set_style("whitegrid")
plt.rcParams['figure.figsize'] = (12, 8)

def load_benchmark_files(directory):
    """Load all benchmark CSV files from directory."""
    files = glob.glob(f"{directory}/**/benchmark_*.csv", recursive=True)

    if not files:
        print(f"❌ No benchmark files found in {directory}")
        return None

    print(f"📁 Found {len(files)} benchmark file(s):")
    for f in files:
        print(f"   - {f}")

    # Combine all CSV files
    dfs = []
    for file in files:
        try:
            df = pd.read_csv(file)
            dfs.append(df)
        except Exception as e:
            print(f"⚠️  Error reading {file}: {e}")

    if not dfs:
        return None

    combined = pd.concat(dfs, ignore_index=True)
    print(f"✅ Loaded {len(combined)} benchmark entries\n")
    return combined

def load_summary_files(directory):
    """Load all summary CSV files from directory."""
    files = glob.glob(f"{directory}/**/summary_*.csv", recursive=True)

    if not files:
        return None

    dfs = []
    for file in files:
        try:
            df = pd.read_csv(file)
            dfs.append(df)
        except Exception as e:
            print(f"⚠️  Error reading {file}: {e}")

    if not dfs:
        return None

    return pd.concat(dfs, ignore_index=True)

def plot_comparison_by_operation(df, output_dir):
    """Create bar chart comparing NFS vs SCP by operation type."""
    fig, ax = plt.subplots(figsize=(14, 8))

    # Group by transfer method and operation
    grouped = df.groupby(['transfer_method', 'operation'])['duration_ms'].agg(['mean', 'std']).reset_index()

    # Create grouped bar chart
    operations = grouped['operation'].unique()
    x = range(len(operations))
    width = 0.35

    nfs_data = grouped[grouped['transfer_method'] == 'NFS']
    scp_data = grouped[grouped['transfer_method'] == 'SCP']

    # Plot bars
    if not nfs_data.empty:
        ax.bar([i - width/2 for i in x], nfs_data['mean'], width,
               label='NFS', color='#2ecc71', alpha=0.8,
               yerr=nfs_data['std'], capsize=5)

    if not scp_data.empty:
        ax.bar([i + width/2 for i in x], scp_data['mean'], width,
               label='SCP', color='#3498db', alpha=0.8,
               yerr=scp_data['std'], capsize=5)

    ax.set_xlabel('Operation Type', fontsize=12, fontweight='bold')
    ax.set_ylabel('Average Duration (ms)', fontsize=12, fontweight='bold')
    ax.set_title('NFS vs SCP Performance Comparison by Operation', fontsize=14, fontweight='bold')
    ax.set_xticks(x)
    ax.set_xticklabels(operations, rotation=45, ha='right')
    ax.legend(fontsize=11)
    ax.grid(axis='y', alpha=0.3)

    plt.tight_layout()
    output_file = f"{output_dir}/comparison_by_operation.png"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"✅ Generated: {output_file}")
    plt.close()

def plot_file_transfer_comparison(df, output_dir):
    """Create detailed comparison of file transfer times."""
    transfer_data = df[df['operation'] == 'file_transfer']

    if transfer_data.empty:
        print("⚠️  No file transfer data found")
        return

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))

    # Box plot
    sns.boxplot(data=transfer_data, x='transfer_method', y='duration_ms', ax=ax1, palette='Set2')
    ax1.set_title('File Transfer Time Distribution', fontsize=12, fontweight='bold')
    ax1.set_xlabel('Transfer Method', fontsize=11)
    ax1.set_ylabel('Duration (ms)', fontsize=11)

    # Violin plot
    sns.violinplot(data=transfer_data, x='transfer_method', y='duration_ms', ax=ax2, palette='Set2')
    ax2.set_title('File Transfer Time Distribution (Violin)', fontsize=12, fontweight='bold')
    ax2.set_xlabel('Transfer Method', fontsize=11)
    ax2.set_ylabel('Duration (ms)', fontsize=11)

    plt.tight_layout()
    output_file = f"{output_dir}/file_transfer_comparison.png"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"✅ Generated: {output_file}")
    plt.close()

def plot_timeline(df, output_dir):
    """Create timeline showing execution over time."""
    fig, ax = plt.subplots(figsize=(14, 8))

    # Convert timestamp to relative time
    df['relative_time'] = (df['timestamp'] - df['timestamp'].min()) / 1000  # Convert to seconds

    for method in df['transfer_method'].unique():
        method_data = df[df['transfer_method'] == method]

        for operation in method_data['operation'].unique():
            op_data = method_data[method_data['operation'] == operation]
            ax.scatter(op_data['relative_time'], op_data['duration_ms'],
                      label=f"{method} - {operation}", alpha=0.6, s=100)

    ax.set_xlabel('Time (seconds)', fontsize=12, fontweight='bold')
    ax.set_ylabel('Duration (ms)', fontsize=12, fontweight='bold')
    ax.set_title('Execution Timeline', fontsize=14, fontweight='bold')
    ax.legend(bbox_to_anchor=(1.05, 1), loc='upper left', fontsize=9)
    ax.grid(alpha=0.3)

    plt.tight_layout()
    output_file = f"{output_dir}/execution_timeline.png"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"✅ Generated: {output_file}")
    plt.close()

def plot_total_execution_time(summary_df, output_dir):
    """Create bar chart of total execution time by method."""
    if summary_df is None or summary_df.empty:
        print("⚠️  No summary data available")
        return

    fig, ax = plt.subplots(figsize=(10, 6))

    # Calculate total time per method
    total_by_method = summary_df.groupby('transfer_method')['total_ms'].sum().reset_index()

    colors = {'NFS': '#2ecc71', 'SCP': '#3498db'}
    bars = ax.bar(total_by_method['transfer_method'],
                  total_by_method['total_ms'],
                  color=[colors.get(m, 'gray') for m in total_by_method['transfer_method']],
                  alpha=0.8)

    # Add value labels on bars
    for bar in bars:
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2., height,
                f'{int(height)} ms',
                ha='center', va='bottom', fontsize=11, fontweight='bold')

    ax.set_xlabel('Transfer Method', fontsize=12, fontweight='bold')
    ax.set_ylabel('Total Execution Time (ms)', fontsize=12, fontweight='bold')
    ax.set_title('Total Execution Time Comparison', fontsize=14, fontweight='bold')
    ax.grid(axis='y', alpha=0.3)

    plt.tight_layout()
    output_file = f"{output_dir}/total_execution_time.png"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"✅ Generated: {output_file}")
    plt.close()

def plot_summary_table(summary_df, output_dir):
    """Create a summary statistics table."""
    if summary_df is None or summary_df.empty:
        return

    fig, ax = plt.subplots(figsize=(12, 6))
    ax.axis('tight')
    ax.axis('off')

    # Prepare data for table
    table_data = summary_df[['transfer_method', 'operation', 'count', 'avg_ms', 'min_ms', 'max_ms']].copy()
    table_data.columns = ['Method', 'Operation', 'Count', 'Avg (ms)', 'Min (ms)', 'Max (ms)']

    # Round numeric values
    for col in ['Avg (ms)', 'Min (ms)', 'Max (ms)']:
        table_data[col] = table_data[col].round(2)

    table = ax.table(cellText=table_data.values, colLabels=table_data.columns,
                     cellLoc='center', loc='center', bbox=[0, 0, 1, 1])

    table.auto_set_font_size(False)
    table.set_fontsize(10)
    table.scale(1, 2)

    # Style header
    for i in range(len(table_data.columns)):
        table[(0, i)].set_facecolor('#3498db')
        table[(0, i)].set_text_props(weight='bold', color='white')

    # Alternate row colors
    for i in range(1, len(table_data) + 1):
        for j in range(len(table_data.columns)):
            if i % 2 == 0:
                table[(i, j)].set_facecolor('#ecf0f1')

    plt.title('Benchmark Summary Statistics', fontsize=14, fontweight='bold', pad=20)

    output_file = f"{output_dir}/summary_table.png"
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"✅ Generated: {output_file}")
    plt.close()

def generate_report(df, summary_df, output_dir):
    """Generate a text report with key findings."""
    report_file = f"{output_dir}/benchmark_report.txt"

    with open(report_file, 'w') as f:
        f.write("=" * 70 + "\n")
        f.write("BENCHMARK COMPARISON REPORT: NFS vs SCP\n")
        f.write("=" * 70 + "\n\n")

        # Overall statistics
        f.write("OVERALL STATISTICS\n")
        f.write("-" * 70 + "\n")
        for method in df['transfer_method'].unique():
            method_data = df[df['transfer_method'] == method]
            f.write(f"\n{method}:\n")
            f.write(f"  Total operations: {len(method_data)}\n")
            f.write(f"  Average duration: {method_data['duration_ms'].mean():.2f} ms\n")
            f.write(f"  Min duration: {method_data['duration_ms'].min():.2f} ms\n")
            f.write(f"  Max duration: {method_data['duration_ms'].max():.2f} ms\n")
            f.write(f"  Std deviation: {method_data['duration_ms'].std():.2f} ms\n")

        # File transfer comparison
        f.write("\n" + "-" * 70 + "\n")
        f.write("FILE TRANSFER COMPARISON\n")
        f.write("-" * 70 + "\n")
        transfer_data = df[df['operation'] == 'file_transfer']

        if not transfer_data.empty:
            for method in transfer_data['transfer_method'].unique():
                method_transfers = transfer_data[transfer_data['transfer_method'] == method]
                f.write(f"\n{method}:\n")
                f.write(f"  File transfers: {len(method_transfers)}\n")
                f.write(f"  Average time: {method_transfers['duration_ms'].mean():.2f} ms\n")
                f.write(f"  Total data transferred: {method_transfers['file_size'].sum() / (1024*1024):.2f} MB\n")

        # Winner determination
        f.write("\n" + "=" * 70 + "\n")
        f.write("CONCLUSION\n")
        f.write("=" * 70 + "\n\n")

        if summary_df is not None and not summary_df.empty:
            total_by_method = summary_df.groupby('transfer_method')['total_ms'].sum()
            winner = total_by_method.idxmin()
            speedup = total_by_method.max() / total_by_method.min()

            f.write(f"Winner: {winner}\n")
            f.write(f"Speedup: {speedup:.2f}x faster than the alternative\n\n")

            for method in total_by_method.index:
                f.write(f"{method} total time: {total_by_method[method]:.2f} ms\n")

    print(f"✅ Generated: {report_file}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 generate_benchmark_graphs.py <benchmarks_directory>")
        print("Example: python3 generate_benchmark_graphs.py benchmarks/")
        sys.exit(1)

    benchmark_dir = sys.argv[1]

    if not os.path.exists(benchmark_dir):
        print(f"❌ Directory not found: {benchmark_dir}")
        sys.exit(1)

    print("╔══════════════════════════════════════════════════════════╗")
    print("║        BENCHMARK GRAPH GENERATOR - NFS vs SCP           ║")
    print("╚══════════════════════════════════════════════════════════╝\n")

    # Load data
    df = load_benchmark_files(benchmark_dir)
    summary_df = load_summary_files(benchmark_dir)

    if df is None:
        print("❌ No data to process")
        sys.exit(1)

    # Create output directory for graphs
    output_dir = f"{benchmark_dir}/graphs"
    os.makedirs(output_dir, exist_ok=True)
    print(f"📊 Generating graphs in: {output_dir}\n")

    # Generate all graphs
    plot_comparison_by_operation(df, output_dir)
    plot_file_transfer_comparison(df, output_dir)
    plot_timeline(df, output_dir)
    plot_total_execution_time(summary_df, output_dir)
    plot_summary_table(summary_df, output_dir)

    # Generate report
    generate_report(df, summary_df, output_dir)

    print("\n✅ All graphs generated successfully!")
    print(f"📂 Output directory: {output_dir}")

if __name__ == "__main__":
    main()
