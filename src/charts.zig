const std = @import("std");
const types = @import("types.zig");
const format = @import("format.zig");

const DailyReport = types.DailyReport;
const MonthlyReport = types.MonthlyReport;
const Color = types.Color;
const print = std.debug.print;

pub fn drawCombinedChart(reports: []const DailyReport, enable_color: bool, max_width: usize) void {
    if (reports.len == 0) return;
    
    // Find max values for scaling
    var max_lines: u64 = 0;
    var max_commits: u64 = 0;
    for (reports) |report| {
        const added = report.lines_added;
        const deleted = report.lines_deleted;
        if (added > max_lines) max_lines = added;
        if (deleted > max_lines) max_lines = deleted;
        if (report.commits > max_commits) max_commits = report.commits;
    }
    
    if (max_lines == 0 and max_commits == 0) return;
    
    const chart_height: usize = 8; // Half for additions, half for deletions
    const bar_width: usize = 5; // Width per bar including spacing  
    const max_bars = @min(reports.len, max_width / bar_width);
    const actual_bars = @min(max_bars, 14); // Limit to 14 bars (2 weeks) for readability
    
    // Start from the end to show most recent data if we have too many days
    const start_idx = if (reports.len > actual_bars) reports.len - actual_bars else 0;
    
    // Draw the upper half (additions)
    var row: i32 = @intCast(chart_height);
    while (row > 0) : (row -= 1) {
        // Y-axis label
        if (row == chart_height) {
            if (enable_color) print("\x1b[32m", .{}); // Green
            print("+{d:>5} |", .{max_lines});
            if (enable_color) print("\x1b[0m", .{});
        } else if (row == chart_height / 2) {
            if (enable_color) print("\x1b[32m", .{}); // Green
            print("+{d:>5} |", .{max_lines / 2});
            if (enable_color) print("\x1b[0m", .{});
        } else {
            print("       |", .{});
        }
        
        // Draw bars and line for each day
        var idx: usize = start_idx;
        while (idx < reports.len and idx < start_idx + actual_bars) : (idx += 1) {
            const report = reports[idx];
            const add_height = if (max_lines > 0) (report.lines_added * chart_height) / max_lines else 0;
            const commit_height = if (max_commits > 0) (report.commits * chart_height * 2) / max_commits else 0;
            
            // Draw the bar/line combo
            if (add_height >= @as(u64, @intCast(row))) {
                if (enable_color) print("\x1b[32m", .{}); // Green for additions
                print(" ██ ", .{});
                if (enable_color) print("\x1b[0m", .{});
            } else if (commit_height >= @as(u64, @intCast(row)) and commit_height < @as(u64, @intCast(row + 1))) {
                // Draw commit line
                if (enable_color) print("\x1b[33m", .{}); // Yellow for commits
                print(" ── ", .{});
                if (enable_color) print("\x1b[0m", .{});
            } else {
                print("    ", .{});
            }
        }
        print("\n", .{});
    }
    
    // Draw zero line
    print("     0 +", .{});
    var i: usize = 0;
    while (i < actual_bars * bar_width) : (i += 1) {
        print("═", .{});
    }
    print(" Commits: ", .{});
    if (enable_color) print("\x1b[33m", .{}); // Yellow
    print("──", .{});
    if (enable_color) print("\x1b[0m", .{});
    print(" (max: {d})", .{max_commits});
    print("\n", .{});
    
    // Draw the lower half (deletions)
    row = -1;
    while (row >= -@as(i32, @intCast(chart_height))) : (row -= 1) {
        // Y-axis label
        if (row == -@as(i32, @intCast(chart_height))) {
            if (enable_color) print("\x1b[31m", .{}); // Red
            print("-{d:>5} |", .{max_lines});
            if (enable_color) print("\x1b[0m", .{});
        } else if (row == -@as(i32, @intCast(chart_height / 2))) {
            if (enable_color) print("\x1b[31m", .{}); // Red
            print("-{d:>5} |", .{max_lines / 2});
            if (enable_color) print("\x1b[0m", .{});
        } else {
            print("       |", .{});
        }
        
        // Draw bars for each day
        var idx: usize = start_idx;
        while (idx < reports.len and idx < start_idx + actual_bars) : (idx += 1) {
            const report = reports[idx];
            const del_height = if (max_lines > 0) (report.lines_deleted * chart_height) / max_lines else 0;
            
            if (del_height >= @as(u64, @intCast(-row))) {
                if (enable_color) print("\x1b[31m", .{}); // Red for deletions
                print(" ██ ", .{});
                if (enable_color) print("\x1b[0m", .{});
            } else {
                print("    ", .{});
            }
        }
        print("\n", .{});
    }
    
    // Draw date labels
    print("        ", .{});
    var idx: usize = start_idx;
    while (idx < reports.len and idx < start_idx + actual_bars) : (idx += 1) {
        const report = reports[idx];
        const date_str = format.formatDailyDate(report.day_timestamp);
        // Extract day number
        const day_start = 4; // "Jul " is 4 chars
        const day = date_str[day_start..day_start+2];
        print("{s}   ", .{day});
    }
    print("\n", .{});
    
    // Month label if all dates are in the same month
    if (reports.len > 0) {
        print("        ", .{});
        const first_date = format.formatDailyDate(reports[start_idx].day_timestamp);
        const month = first_date[0..3];
        print("{s}\n", .{month});
    }
}

pub fn drawVerticalMonthlyChart(reports: []const MonthlyReport, enable_color: bool, max_width: usize) void {
    if (reports.len == 0) return;
    
    // Find max changes for scaling
    var max_changes: u64 = 0;
    for (reports) |report| {
        const total = report.lines_added + report.lines_deleted;
        if (total > max_changes) {
            max_changes = total;
        }
    }
    
    if (max_changes == 0) return;
    
    const chart_height: usize = 10;
    const bar_width: usize = 5; // Width per bar including spacing
    const max_bars = @min(reports.len, max_width / bar_width);
    
    // Start from the end to show most recent data if we have too many months
    const start_idx = if (reports.len > max_bars) reports.len - max_bars else 0;
    
    // Draw the chart from top to bottom
    var row: usize = chart_height;
    while (row > 0) : (row -= 1) {
        // Y-axis label
        if (row == chart_height) {
            print("{d:>6} |", .{max_changes});
        } else if (row == chart_height / 2) {
            print("{d:>6} |", .{max_changes / 2});
        } else if (row == 1) {
            print("     0 |", .{});
        } else {
            print("       |", .{});
        }
        
        // Draw bars for each month
        var idx: usize = start_idx;
        while (idx < reports.len and idx < start_idx + max_bars) : (idx += 1) {
            const report = reports[idx];
            const total_changes = report.lines_added + report.lines_deleted;
            const bar_height = (total_changes * chart_height) / max_changes;
            
            if (bar_height >= row) {
                if (enable_color) {
                    print("\x1b[35m", .{}); // Magenta for monthly
                }
                print(" ██ ", .{});
                if (enable_color) {
                    print("\x1b[0m", .{}); // Reset
                }
            } else {
                print("    ", .{});
            }
        }
        print("\n", .{});
    }
    
    // Draw x-axis
    print("       +", .{});
    var i: usize = 0;
    while (i < max_bars * bar_width - 1) : (i += 1) {
        print("-", .{});
    }
    print("\n", .{});
    
    // Draw month labels
    print("        ", .{});
    var idx: usize = start_idx;
    while (idx < reports.len and idx < start_idx + max_bars) : (idx += 1) {
        const report = reports[idx];
        const month_str = format.formatMonthly(report.sample_timestamp);
        print("{s:<4}", .{month_str[0..3]});
    }
    print("\n", .{});
}

pub fn drawSparkline(values: []const u64, enable_color: bool) void {
    if (values.len == 0) return;
    
    const sparkline_chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
    
    // Find min and max
    var min: u64 = values[0];
    var max: u64 = values[0];
    for (values) |v| {
        if (v < min) min = v;
        if (v > max) max = v;
    }
    
    if (enable_color) {
        print("\x1b[36m", .{}); // Cyan
    }
    
    for (values) |v| {
        const range = if (max > min) max - min else 1;
        const normalized = ((v - min) * 7) / range;
        const idx = @min(7, normalized);
        print("{s}", .{sparkline_chars[idx]});
    }
    
    if (enable_color) {
        print("\x1b[0m", .{}); // Reset
    }
}