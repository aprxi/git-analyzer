const std = @import("std");
const process = std.process;
const print = std.debug.print;

// ANSI color codes
const Color = struct {
    const RESET = "\x1b[0m";
    const GREEN = "\x1b[32m";
    const RED = "\x1b[31m";
    const BOLD = "\x1b[1m";
    const DIM = "\x1b[2m";
};

const Commit = struct {
    timestamp: i64,
    lines_added: u64,
    lines_deleted: u64,
};

const DailyReport = struct {
    day_timestamp: i64,
    commits: u64,
    lines_added: u64,
    lines_deleted: u64,
    avg_commit_size: f32,
    refactoring_ratio: f32,
};

const MonthlyReport = struct {
    month_timestamp: i64,
    commits: u64,
    lines_added: u64,
    lines_deleted: u64,
    avg_commit_size: f32,
    refactoring_ratio: f32,
    // Store a representative actual timestamp for proper date formatting
    sample_timestamp: i64,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    var since_arg: []const u8 = "30 days ago";
    var use_colors: bool = true;
    var history_mode: bool = false;
    var filter_large: bool = false;
    var max_commit_size: u64 = 10000; // Default threshold: 10k lines changed
    
    // Simple argument parsing
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.startsWith(u8, args[i], "--since=")) {
            since_arg = args[i][8..];
        } else if (std.mem.eql(u8, args[i], "--no-color")) {
            use_colors = false;
        } else if (std.mem.eql(u8, args[i], "--history")) {
            history_mode = true;
            if (std.mem.eql(u8, since_arg, "30 days ago")) {
                since_arg = "1 year ago"; // Default for history mode
            }
        } else if (std.mem.eql(u8, args[i], "--filter-large")) {
            filter_large = true;
        } else if (std.mem.startsWith(u8, args[i], "--max-commit-size=")) {
            max_commit_size = std.fmt.parseInt(u64, args[i][18..], 10) catch {
                std.debug.print("Error: Invalid max-commit-size value\n", .{});
                return;
            };
            filter_large = true; // Enable filtering when size is specified
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            printHelp();
            return;
        }
    }

    // Execute git command and parse output
    const commits = try executeGitLog(allocator, since_arg);
    defer allocator.free(commits);

    if (commits.len == 0) {
        print("No commits found in the specified time range.\n", .{});
        return;
    }

    // Apply filtering if requested
    const filtered_commits = if (filter_large) 
        try filterLargeCommits(allocator, commits, max_commit_size)
    else
        commits;

    if (history_mode) {
        // Generate monthly reports for history view
        const monthly_reports = try generateMonthlyReports(allocator, filtered_commits);
        defer allocator.free(monthly_reports);
        printMonthlyReport(since_arg, monthly_reports, use_colors);
    } else {
        // Generate daily reports for default view
        const daily_reports = try generateDailyReports(allocator, filtered_commits);
        defer allocator.free(daily_reports);
        printDailyReport(since_arg, daily_reports, use_colors);
    }
    
    // Clean up filtered commits if different from original
    if (filter_large and filtered_commits.ptr != commits.ptr) {
        allocator.free(filtered_commits);
    }
}

fn printHelp() void {
    print("git-insight - Git repository statistics analyzer\n\n", .{});
    print("Usage: git-insight [OPTIONS]\n\n", .{});
    print("Options:\n", .{});
    print("  --since=\"<date>\"          Analyze commits since the given date (default: \"30 days ago\")\n", .{});
    print("  --history                 Show monthly aggregation instead of daily view\n", .{});
    print("  --filter-large            Filter out commits with >10k lines changed\n", .{});
    print("  --max-commit-size=N       Set custom threshold for large commit filtering\n", .{});
    print("  --no-color                Disable colored output\n", .{});
    print("  -h, --help                Show this help message\n\n", .{});
    print("Examples:\n", .{});
    print("  git-insight                                    # Last 30 days, daily view\n", .{});
    print("  git-insight --filter-large                     # Filter out bulk operations\n", .{});
    print("  git-insight --max-commit-size=5000              # Custom 5k line threshold\n", .{});
    print("  git-insight --history --filter-large           # Monthly view, filtered\n", .{});
    print("  git-insight --since=\"60 days ago\" --filter-large # 60 days, filtered\n", .{});
}

fn executeGitLog(allocator: std.mem.Allocator, since: []const u8) ![]Commit {
    // Build the git command
    const argv = [_][]const u8{
        "git",
        "log",
        try std.fmt.allocPrint(allocator, "--since={s}", .{since}),
        "--numstat",
        "--pretty=format:---COMMIT---%n%at",
    };
    defer allocator.free(argv[2]);

    // Execute git command with streaming
    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    
    try child.spawn();
    
    // Read output in chunks to handle large repositories
    var stdout_data = std.ArrayList(u8).init(allocator);
    defer stdout_data.deinit();
    
    var stderr_data = std.ArrayList(u8).init(allocator);
    defer stderr_data.deinit();
    
    const stdout_reader = child.stdout.?.reader();
    const stderr_reader = child.stderr.?.reader();
    
    // Read stdout in chunks
    var buffer: [8192]u8 = undefined;
    while (true) {
        const bytes_read = stdout_reader.read(buffer[0..]) catch |err| switch (err) {
            else => return err,
        };
        if (bytes_read == 0) break;
        try stdout_data.appendSlice(buffer[0..bytes_read]);
    }
    
    // Read stderr
    while (true) {
        const bytes_read = stderr_reader.read(buffer[0..]) catch |err| switch (err) {
            else => return err,
        };
        if (bytes_read == 0) break;
        try stderr_data.appendSlice(buffer[0..bytes_read]);
    }
    
    const term = try child.wait();
    
    if (term != .Exited or term.Exited != 0) {
        std.debug.print("Error: Failed to execute git command. Make sure you're in a git repository.\n", .{});
        std.debug.print("stderr: {s}\n", .{stderr_data.items});
        return error.GitCommandFailed;
    }

    // Parse the output
    return try parseGitOutputStreaming(allocator, stdout_data.items);
}

fn parseGitOutputStreaming(allocator: std.mem.Allocator, output: []const u8) ![]Commit {
    // For very large repositories, we could process line by line to save memory
    // For now, use the existing logic but with better memory management
    return parseGitOutput(allocator, output);
}

fn filterLargeCommits(allocator: std.mem.Allocator, commits: []const Commit, max_commit_size: u64) ![]Commit {
    var filtered = std.ArrayList(Commit).init(allocator);
    defer filtered.deinit();
    
    var filtered_count: u64 = 0;
    var total_filtered_lines: u64 = 0;
    
    for (commits) |commit| {
        const total_changes = commit.lines_added + commit.lines_deleted;
        if (total_changes <= max_commit_size) {
            try filtered.append(commit);
        } else {
            filtered_count += 1;
            total_filtered_lines += total_changes;
        }
    }
    
    // Report filtering results
    if (filtered_count > 0) {
        std.debug.print("Filtered out {d} large commits (>{d} lines changed) with {d} total lines changed.\n", 
            .{filtered_count, max_commit_size, total_filtered_lines});
    }
    
    return try filtered.toOwnedSlice();
}

fn parseGitOutput(allocator: std.mem.Allocator, output: []const u8) ![]Commit {
    var commits = std.ArrayList(Commit).init(allocator);
    defer commits.deinit();

    // Process output line by line for better memory efficiency
    var line_iterator = std.mem.split(u8, output, "\n");
    var current_commit: ?Commit = null;
    var processed_commits: u64 = 0;

    while (line_iterator.next()) |line| {
        // Skip empty lines
        if (line.len == 0) continue;
        
        if (std.mem.eql(u8, line, "---COMMIT---")) {
            // Save previous commit if exists
            if (current_commit) |commit| {
                try commits.append(commit);
                processed_commits += 1;
                
                // Print progress for large repos
                if (processed_commits % 1000 == 0) {
                    std.debug.print("\rProcessed {d} commits...", .{processed_commits});
                }
            }
            
            // Start new commit
            if (line_iterator.next()) |timestamp_line| {
                if (timestamp_line.len > 0) {
                    const timestamp = std.fmt.parseInt(i64, timestamp_line, 10) catch continue;
                    current_commit = Commit{
                        .timestamp = timestamp,
                        .lines_added = 0,
                        .lines_deleted = 0,
                    };
                }
            }
        } else if (current_commit != null) {
            // Parse numstat line (added\tdeleted\tfilename)
            var tab_iterator = std.mem.split(u8, line, "\t");
            
            if (tab_iterator.next()) |added_str| {
                if (tab_iterator.next()) |deleted_str| {
                    // Skip binary files (shown as "-") and malformed lines
                    if (added_str.len > 0 and deleted_str.len > 0 and
                        !std.mem.eql(u8, added_str, "-") and !std.mem.eql(u8, deleted_str, "-")) {
                        const added = std.fmt.parseInt(u64, added_str, 10) catch continue;
                        const deleted = std.fmt.parseInt(u64, deleted_str, 10) catch continue;
                        current_commit.?.lines_added += added;
                        current_commit.?.lines_deleted += deleted;
                    }
                }
            }
        }
    }

    // Don't forget the last commit
    if (current_commit) |commit| {
        try commits.append(commit);
        processed_commits += 1;
    }
    
    // Clear progress line if we printed any
    if (processed_commits >= 1000) {
        std.debug.print("\rProcessed {d} commits total.\n", .{processed_commits});
    } else if (processed_commits > 0) {
        std.debug.print("Processed {d} commits total.\n", .{processed_commits});
    }

    return try commits.toOwnedSlice();
}

fn generateDailyReports(allocator: std.mem.Allocator, commits: []const Commit) ![]DailyReport {
    if (commits.len == 0) return try allocator.alloc(DailyReport, 0);

    // Sort commits by timestamp
    const sorted_commits = try allocator.dupe(Commit, commits);
    defer allocator.free(sorted_commits);
    std.mem.sort(Commit, sorted_commits, {}, struct {
        fn lessThan(_: void, a: Commit, b: Commit) bool {
            return a.timestamp < b.timestamp;
        }
    }.lessThan);

    // Create a map to aggregate by day
    var day_map = std.AutoHashMap(i64, DailyReport).init(allocator);
    defer day_map.deinit();

    for (sorted_commits) |commit| {
        const day_start = getDayStart(commit.timestamp);
        
        if (day_map.get(day_start)) |existing| {
            // Update existing day
            const updated = DailyReport{
                .day_timestamp = day_start,
                .commits = existing.commits + 1,
                .lines_added = existing.lines_added + commit.lines_added,
                .lines_deleted = existing.lines_deleted + commit.lines_deleted,
                .avg_commit_size = 0, // Will calculate later
                .refactoring_ratio = 0, // Will calculate later
            };
            try day_map.put(day_start, updated);
        } else {
            // New day
            const new_day = DailyReport{
                .day_timestamp = day_start,
                .commits = 1,
                .lines_added = commit.lines_added,
                .lines_deleted = commit.lines_deleted,
                .avg_commit_size = 0,
                .refactoring_ratio = 0,
            };
            try day_map.put(day_start, new_day);
        }
    }

    // Convert to sorted array and calculate ratios
    var reports = std.ArrayList(DailyReport).init(allocator);
    defer reports.deinit();

    var iterator = day_map.iterator();
    while (iterator.next()) |entry| {
        var report = entry.value_ptr.*;
        const total_changes = report.lines_added + report.lines_deleted;
        report.avg_commit_size = if (report.commits > 0)
            @as(f32, @floatFromInt(total_changes)) / @as(f32, @floatFromInt(report.commits))
            else 0;
        report.refactoring_ratio = if (report.lines_added > 0)
            @as(f32, @floatFromInt(report.lines_deleted)) / @as(f32, @floatFromInt(report.lines_added))
            else 0;
        try reports.append(report);
    }

    // Sort by timestamp
    std.mem.sort(DailyReport, reports.items, {}, struct {
        fn lessThan(_: void, a: DailyReport, b: DailyReport) bool {
            return a.day_timestamp < b.day_timestamp;
        }
    }.lessThan);

    return try reports.toOwnedSlice();
}

fn generateMonthlyReports(allocator: std.mem.Allocator, commits: []const Commit) ![]MonthlyReport {
    if (commits.len == 0) return try allocator.alloc(MonthlyReport, 0);

    // Sort commits by timestamp
    const sorted_commits = try allocator.dupe(Commit, commits);
    defer allocator.free(sorted_commits);
    std.mem.sort(Commit, sorted_commits, {}, struct {
        fn lessThan(_: void, a: Commit, b: Commit) bool {
            return a.timestamp < b.timestamp;
        }
    }.lessThan);

    // Create a map to aggregate by month
    var month_map = std.AutoHashMap(i64, MonthlyReport).init(allocator);
    defer month_map.deinit();

    for (sorted_commits) |commit| {
        const month_start = getMonthStart(commit.timestamp);
        
        if (month_map.get(month_start)) |existing| {
            // Update existing month
            const updated = MonthlyReport{
                .month_timestamp = month_start,
                .commits = existing.commits + 1,
                .lines_added = existing.lines_added + commit.lines_added,
                .lines_deleted = existing.lines_deleted + commit.lines_deleted,
                .avg_commit_size = 0, // Will calculate later
                .refactoring_ratio = 0, // Will calculate later
                .sample_timestamp = existing.sample_timestamp, // Keep first commit's timestamp
            };
            try month_map.put(month_start, updated);
        } else {
            // New month
            const new_month = MonthlyReport{
                .month_timestamp = month_start,
                .commits = 1,
                .lines_added = commit.lines_added,
                .lines_deleted = commit.lines_deleted,
                .avg_commit_size = 0,
                .refactoring_ratio = 0,
                .sample_timestamp = commit.timestamp, // Store actual commit timestamp
            };
            try month_map.put(month_start, new_month);
        }
    }

    // Convert to sorted array and calculate ratios
    var reports = std.ArrayList(MonthlyReport).init(allocator);
    defer reports.deinit();

    var iterator = month_map.iterator();
    while (iterator.next()) |entry| {
        var report = entry.value_ptr.*;
        const total_changes = report.lines_added + report.lines_deleted;
        report.avg_commit_size = if (report.commits > 0)
            @as(f32, @floatFromInt(total_changes)) / @as(f32, @floatFromInt(report.commits))
            else 0;
        report.refactoring_ratio = if (report.lines_added > 0)
            @as(f32, @floatFromInt(report.lines_deleted)) / @as(f32, @floatFromInt(report.lines_added))
            else 0;
        try reports.append(report);
    }

    // Sort by timestamp
    std.mem.sort(MonthlyReport, reports.items, {}, struct {
        fn lessThan(_: void, a: MonthlyReport, b: MonthlyReport) bool {
            return a.month_timestamp < b.month_timestamp;
        }
    }.lessThan);

    return try reports.toOwnedSlice();
}

fn getDayStart(timestamp: i64) i64 {
    // Get the start of the day (midnight) for a given timestamp
    const seconds_per_day: i64 = 24 * 60 * 60;
    return @divFloor(timestamp, seconds_per_day) * seconds_per_day;
}

fn getMonthStart(timestamp: i64) i64 {
    // Simple month aggregation - group by year+month
    // We don't need exact dates, just consistent grouping
    const seconds_per_day: i64 = 24 * 60 * 60;
    const days_since_epoch = @divFloor(timestamp, seconds_per_day);
    
    // Very rough calculation for year and month
    const approx_years = @divFloor(days_since_epoch, 365);
    const year_start_day = approx_years * 365;
    const days_in_year = days_since_epoch - year_start_day;
    
    // Approximate month (good enough for grouping)
    const approx_month = @divFloor(days_in_year, 30); // ~30 days per month
    
    // Create a unique identifier for this year+month combination
    // This will group all commits in the same approximate month together
    return (approx_years * 12 + approx_month) * (30 * seconds_per_day);
}

fn printDailyReport(since: []const u8, reports: []const DailyReport, use_colors: bool) void {
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
        const date_str = formatDailyDate(report.day_timestamp);
        const added_str = formatLinesAdded(report.lines_added, use_colors);
        const deleted_str = formatLinesDeleted(report.lines_deleted, use_colors);
        
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
    const total_added_str = formatLinesAdded(total_added, use_colors);
    const total_deleted_str = formatLinesDeleted(total_deleted, use_colors);
    
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
    
    print("\n", .{});
}

fn printMonthlyReport(since: []const u8, reports: []const MonthlyReport, use_colors: bool) void {
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
        const month_str = formatMonthly(report.sample_timestamp);
        const added_str = formatLinesAdded(report.lines_added, use_colors);
        const deleted_str = formatLinesDeleted(report.lines_deleted, use_colors);
        
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
    const total_added_str = formatLinesAdded(total_added, use_colors);
    const total_deleted_str = formatLinesDeleted(total_deleted, use_colors);
    
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
    
    print("\n", .{});
}

fn formatDailyDate(timestamp: i64) [12]u8 {
    const seconds_per_day: i64 = 24 * 60 * 60;
    const days_since_epoch = @divFloor(timestamp, seconds_per_day);
    
    // Simple date calculation (approximate)
    const years_since_1970 = @divFloor(days_since_epoch, 365);
    const year: i64 = 1970 + years_since_1970;
    
    var remaining_days = days_since_epoch - (years_since_1970 * 365);
    // Rough leap year adjustment
    remaining_days -= @divFloor(years_since_1970, 4);
    
    if (remaining_days < 0) remaining_days = 0;
    
    const months = [_]u8{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    const month_names = [_][3]u8{
        .{'J','a','n'}, .{'F','e','b'}, .{'M','a','r'}, .{'A','p','r'},
        .{'M','a','y'}, .{'J','u','n'}, .{'J','u','l'}, .{'A','u','g'},
        .{'S','e','p'}, .{'O','c','t'}, .{'N','o','v'}, .{'D','e','c'}
    };
    var month: u8 = 0;
    var day: i64 = 1;
    
    for (months, 0..) |days_in_month, i| {
        if (remaining_days < days_in_month) {
            month = @intCast(i);
            day = remaining_days + 1;
            break;
        }
        remaining_days -= days_in_month;
    }
    
    var result: [12]u8 = .{' '} ** 12;
    const formatted = std.fmt.bufPrint(&result, "{c}{c}{c} {d:0>2}, {d}", .{
        month_names[month][0], month_names[month][1], month_names[month][2],
        @as(u8, @intCast(day)), 
        @as(u32, @intCast(year))
    }) catch "Jan 01, 2025";
    // Ensure proper padding
    var final: [12]u8 = .{' '} ** 12;
    const copy_len = @min(formatted.len, 12);
    @memcpy(final[0..copy_len], formatted[0..copy_len]);
    return final;
}

fn formatMonthly(timestamp: i64) [12]u8 {
    // Use a more accurate date calculation
    // Based on the fact that your repo started in March 2025
    const seconds_per_day: i64 = 24 * 60 * 60;
    const days_since_epoch = @divFloor(timestamp, seconds_per_day);
    
    // More accurate calculation
    // Unix epoch: Jan 1, 1970 was day 0
    // March 1, 2025 would be approximately day 20,149 
    
    // Start from a known date: Jan 1, 2020 = 18,262 days since epoch
    const days_since_2020 = days_since_epoch - 18262;
    const years_since_2020 = @divFloor(days_since_2020, 365);
    const year = 2020 + years_since_2020;
    
    // Account for leap years more accurately
    const leap_days = @divFloor(years_since_2020, 4);
    var remaining_days = days_since_2020 - (years_since_2020 * 365) - leap_days;
    
    if (remaining_days < 0) {
        remaining_days += 365;
    }
    
    const months = [_]u16{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    const month_names = [_][3]u8{
        .{'J','a','n'}, .{'F','e','b'}, .{'M','a','r'}, .{'A','p','r'},
        .{'M','a','y'}, .{'J','u','n'}, .{'J','u','l'}, .{'A','u','g'},
        .{'S','e','p'}, .{'O','c','t'}, .{'N','o','v'}, .{'D','e','c'}
    };
    var month: u8 = 0;
    
    for (months, 0..) |days_in_month, i| {
        if (remaining_days < days_in_month) {
            month = @intCast(i);
            break;
        }
        remaining_days -= days_in_month;
    }
    
    var result: [12]u8 = .{' '} ** 12;
    const formatted = std.fmt.bufPrint(&result, "{c}{c}{c} {d}", .{
        month_names[month][0], month_names[month][1], month_names[month][2],
        @as(u32, @intCast(year))
    }) catch "Mar 2025    ";
    // Ensure proper padding
    var final: [12]u8 = .{' '} ** 12;
    const copy_len = @min(formatted.len, 12);
    @memcpy(final[0..copy_len], formatted[0..copy_len]);
    return final;
}

// formatShortDate removed - using formatDailyDate and formatMonthly instead

fn formatLinesAdded(lines: u64, use_colors: bool) [25]u8 {
    var buf: [25]u8 = undefined;
    const formatted = if (use_colors)
        std.fmt.bufPrint(&buf, "{s}+{d}{s}", .{Color.GREEN, lines, Color.RESET}) catch "+0"
    else
        std.fmt.bufPrint(&buf, "+{d}", .{lines}) catch "+0";
    
    // Pad with spaces to fit column width
    var result: [25]u8 = .{' '} ** 25;
    const copy_len = @min(formatted.len, 25);
    @memcpy(result[0..copy_len], formatted[0..copy_len]);
    return result;
}

fn formatLinesDeleted(lines: u64, use_colors: bool) [25]u8 {
    var buf: [25]u8 = undefined;
    const formatted = if (use_colors)
        std.fmt.bufPrint(&buf, "{s}-{d}{s}", .{Color.RED, lines, Color.RESET}) catch "-0"
    else
        std.fmt.bufPrint(&buf, "-{d}", .{lines}) catch "-0";
    
    // Pad with spaces to fit column width
    var result: [25]u8 = .{' '} ** 25;
    const copy_len = @min(formatted.len, 25);
    @memcpy(result[0..copy_len], formatted[0..copy_len]);
    return result;
}

// Old functions removed - now using daily/monthly reports directly