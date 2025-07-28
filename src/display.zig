const std = @import("std");
const types = @import("types.zig");
const format = @import("format.zig");
const charts = @import("charts.zig");

const DailyReport = types.DailyReport;
const MonthlyReport = types.MonthlyReport;
const Color = types.Color;
const print = std.debug.print;

pub fn printDailyReport(since: []const u8, reports: []const DailyReport, use_colors: bool) void {
    if (use_colors) {
        print("\n{s}Git Insight Daily Report{s} for the last {s}{s}{s}\n\n", .{Color.BOLD, Color.RESET, Color.BOLD, since, Color.RESET});
    } else {
        print("\nGit Insight Daily Report for the last {s}\n\n", .{since});
    }
    
    // Print header
    print("| {s:<12} | {s:>7} | {s:>11} | {s:>13} | {s:>16} | {s:>17} |\n", .{
        "Date",
        "Commits",
        "Lines Added",
        "Lines Deleted",
        "Avg. Commit Size",
        "Refactoring Ratio",
    });
    print("|{s:-<14}|{s:-<9}|{s:-<13}|{s:-<15}|{s:-<18}|{s:-<19}|\n", .{
        "-" ** 14,
        "-" ** 9,
        "-" ** 13,
        "-" ** 15,
        "-" ** 18,
        "-" ** 19,
    });

    // Calculate totals
    var total_commits: u64 = 0;
    var total_added: u64 = 0;
    var total_deleted: u64 = 0;
    var total_changes: u64 = 0;
    
    for (reports) |report| {
        total_commits += report.commits;
        total_added += report.lines_added;
        total_deleted += report.lines_deleted;
        total_changes += report.lines_added + report.lines_deleted;
    }
    
    const overall_avg_size = if (total_commits > 0)
        @as(f32, @floatFromInt(total_changes)) / @as(f32, @floatFromInt(total_commits))
        else 0;
    const overall_refactor_ratio = if (total_added > 0)
        @as(f32, @floatFromInt(total_deleted)) / @as(f32, @floatFromInt(total_added))
        else 0;

    // Print each day's data
    for (reports) |report| {
        const date_str = format.formatDailyDate(report.day_timestamp);
        const added_str = format.formatLinesAdded(report.lines_added, use_colors);
        const deleted_str = format.formatLinesDeleted(report.lines_deleted, use_colors);
        
        print("| {s:<12} | {d:>7} | {s:>11} | {s:>13} | {d:>16.0} | {d:>17.2} |\n", .{
            date_str,
            report.commits,
            added_str,
            deleted_str,
            report.avg_commit_size,
            report.refactoring_ratio,
        });
    }
    
    // Print separator
    print("|{s:-<14}|{s:-<9}|{s:-<13}|{s:-<15}|{s:-<18}|{s:-<19}|\n", .{
        "-" ** 14,
        "-" ** 9,
        "-" ** 13,
        "-" ** 15,
        "-" ** 18,
        "-" ** 19,
    });
    
    // Print totals
    const total_added_str = format.formatLinesAdded(total_added, use_colors);
    const total_deleted_str = format.formatLinesDeleted(total_deleted, use_colors);
    
    if (use_colors) {
        print("| {s}TOTAL{s}        | {s}{d:>7}{s} | {s:>11} | {s:>13} | {s}{d:>16.0}{s} | {s}{d:>17.2}{s} |\n", .{
            Color.BOLD, Color.RESET,
            Color.BOLD, total_commits, Color.RESET,
            total_added_str,
            total_deleted_str,
            Color.BOLD, overall_avg_size, Color.RESET,
            Color.BOLD, overall_refactor_ratio, Color.RESET,
        });
    } else {
        print("| TOTAL        | {d:>7} | {s:>11} | {s:>13} | {d:>16.0} | {d:>17.2} |\n", .{
            total_commits,
            total_added_str,
            total_deleted_str,
            overall_avg_size,
            overall_refactor_ratio,
        });
    }
    
    // Add visual commit activity chart
    if (reports.len > 0) {
        print("\n", .{});
        
        // Commit Activity Chart
        if (use_colors) {
            print("{s}Commit Activity:{s}\n", .{Color.BOLD, Color.RESET});
        } else {
            print("Commit Activity:\n", .{});
        }
        
        // Draw combined chart with additions, deletions, and commits
        charts.drawCombinedChart(reports, use_colors, 70);
        
        // Activity sparkline
        if (reports.len > 1) {
            print("\n", .{});
            if (use_colors) {
                print("{s}Trend:{s} ", .{Color.BOLD, Color.RESET});
            } else {
                print("Trend: ", .{});
            }
            
            // Create array of commit counts
            var commit_counts = std.ArrayList(u64).init(std.heap.page_allocator);
            defer commit_counts.deinit();
            
            for (reports) |report| {
                commit_counts.append(report.commits) catch {};
            }
            
            charts.drawSparkline(commit_counts.items, use_colors);
            print("\n", .{});
        }
    }
    
    print("\n", .{});
}

pub fn printMonthlyReport(since: []const u8, reports: []const MonthlyReport, use_colors: bool) void {
    if (use_colors) {
        print("\n{s}Git Insight Monthly History{s} for the last {s}{s}{s}\n\n", .{Color.BOLD, Color.RESET, Color.BOLD, since, Color.RESET});
    } else {
        print("\nGit Insight Monthly History for the last {s}\n\n", .{since});
    }
    
    // Print header
    print("| {s:<12} | {s:>7} | {s:>11} | {s:>13} | {s:>16} | {s:>17} |\n", .{
        "Month",
        "Commits",
        "Lines Added",
        "Lines Deleted",
        "Avg. Commit Size",
        "Refactoring Ratio",
    });
    print("|{s:-<14}|{s:-<9}|{s:-<13}|{s:-<15}|{s:-<18}|{s:-<19}|\n", .{
        "-" ** 14,
        "-" ** 9,
        "-" ** 13,
        "-" ** 15,
        "-" ** 18,
        "-" ** 19,
    });

    // Calculate totals
    var total_commits: u64 = 0;
    var total_added: u64 = 0;
    var total_deleted: u64 = 0;
    var total_changes: u64 = 0;
    
    for (reports) |report| {
        total_commits += report.commits;
        total_added += report.lines_added;
        total_deleted += report.lines_deleted;
        total_changes += report.lines_added + report.lines_deleted;
    }
    
    const overall_avg_size = if (total_commits > 0)
        @as(f32, @floatFromInt(total_changes)) / @as(f32, @floatFromInt(total_commits))
        else 0;
    const overall_refactor_ratio = if (total_added > 0)
        @as(f32, @floatFromInt(total_deleted)) / @as(f32, @floatFromInt(total_added))
        else 0;

    // Print each month's data
    for (reports) |report| {
        const month_str = format.formatMonthly(report.sample_timestamp);
        const added_str = format.formatLinesAdded(report.lines_added, use_colors);
        const deleted_str = format.formatLinesDeleted(report.lines_deleted, use_colors);
        
        print("| {s:<12} | {d:>7} | {s:>11} | {s:>13} | {d:>16.0} | {d:>17.2} |\n", .{
            month_str,
            report.commits,
            added_str,
            deleted_str,
            report.avg_commit_size,
            report.refactoring_ratio,
        });
    }
    
    // Print separator
    print("|{s:-<14}|{s:-<9}|{s:-<13}|{s:-<15}|{s:-<18}|{s:-<19}|\n", .{
        "-" ** 14,
        "-" ** 9,
        "-" ** 13,
        "-" ** 15,
        "-" ** 18,
        "-" ** 19,
    });
    
    // Print totals
    const total_added_str = format.formatLinesAdded(total_added, use_colors);
    const total_deleted_str = format.formatLinesDeleted(total_deleted, use_colors);
    
    if (use_colors) {
        print("| {s}TOTAL{s}        | {s}{d:>7}{s} | {s:>11} | {s:>13} | {s}{d:>16.0}{s} | {s}{d:>17.2}{s} |\n", .{
            Color.BOLD, Color.RESET,
            Color.BOLD, total_commits, Color.RESET,
            total_added_str,
            total_deleted_str,
            Color.BOLD, overall_avg_size, Color.RESET,
            Color.BOLD, overall_refactor_ratio, Color.RESET,
        });
    } else {
        print("| TOTAL        | {d:>7} | {s:>11} | {s:>13} | {d:>16.0} | {d:>17.2} |\n", .{
            total_commits,
            total_added_str,
            total_deleted_str,
            overall_avg_size,
            overall_refactor_ratio,
        });
    }
    
    // Add visual commit activity chart for monthly view
    if (reports.len > 0) {
        print("\n", .{});
        
        // Monthly Activity Chart
        if (use_colors) {
            print("{s}Monthly Activity:{s}\n", .{Color.BOLD, Color.RESET});
        } else {
            print("Monthly Activity:\n", .{});
        }
        
        // Draw vertical bar chart for monthly activity
        charts.drawVerticalMonthlyChart(reports, use_colors, 70);
    }
    
    print("\n", .{});
}

pub fn printHelp() void {
    print("git-insight - Git repository statistics analyzer\n\n", .{});
    print("Usage: git-insight [OPTIONS]\n\n", .{});
    print("Options:\n", .{});
    print("  --since=\"<date>\"          Analyze commits since the given date (default: \"30 days ago\")\n", .{});
    print("  --history                 Show monthly aggregation instead of daily view\n", .{});
    print("  --filter-large            Filter out commits with >10k lines changed\n", .{});
    print("  --max-commit-size=N       Set custom threshold for large commit filtering\n", .{});
    print("  --by-language             Show breakdown of changes by programming language\n", .{});
    print("  --no-color                Disable colored output\n", .{});
    print("  -h, --help                Show this help message\n\n", .{});
    print("Examples:\n", .{});
    print("  git-insight                                    # Last 30 days, daily view\n", .{});
    print("  git-insight --filter-large                     # Filter out bulk operations\n", .{});
    print("  git-insight --max-commit-size=5000              # Custom 5k line threshold\n", .{});
    print("  git-insight --history --filter-large           # Monthly view, filtered\n", .{});
    print("  git-insight --since=\"60 days ago\" --filter-large # 60 days, filtered\n", .{});
    print("  git-insight --by-language                      # Show language breakdown\n", .{});
}