const std = @import("std");
const types = @import("types.zig");

const Commit = types.Commit;
const DailyReport = types.DailyReport;
const MonthlyReport = types.MonthlyReport;

pub fn getDayStart(timestamp: i64) i64 {
    // Get the start of the day (midnight) for a given timestamp
    const seconds_per_day: i64 = 24 * 60 * 60;
    return @divFloor(timestamp, seconds_per_day) * seconds_per_day;
}

pub fn getMonthStart(timestamp: i64) i64 {
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

pub fn generateDailyReports(allocator: std.mem.Allocator, commits: []const Commit) ![]DailyReport {
    if (commits.len == 0) return try allocator.alloc(DailyReport, 0);

    // Sort commits by timestamp
    const sorted_commits = try allocator.dupe(Commit, commits);
    defer allocator.free(sorted_commits);
    std.mem.sort(Commit, sorted_commits, {}, struct {
        fn lessThan(_: void, a: Commit, b: Commit) bool {
            return a.timestamp < b.timestamp;
        }
    }.lessThan);

    // Find the date range
    const now = std.time.timestamp();
    const oldest_commit = sorted_commits[0].timestamp;
    const newest_commit = sorted_commits[sorted_commits.len - 1].timestamp;
    const start_day = getDayStart(@min(oldest_commit, newest_commit));
    const end_day = getDayStart(@max(now, newest_commit));

    // Create a map to aggregate by day
    var day_map = std.AutoHashMap(i64, DailyReport).init(allocator);
    defer day_map.deinit();

    // Initialize all days in the range with empty reports
    var current_day = start_day;
    const seconds_per_day: i64 = 24 * 60 * 60;
    while (current_day <= end_day) : (current_day += seconds_per_day) {
        const empty_day = DailyReport{
            .day_timestamp = current_day,
            .commits = 0,
            .lines_added = 0,
            .lines_deleted = 0,
            .avg_commit_size = 0,
            .refactoring_ratio = 0,
            .language_stats = null,
        };
        try day_map.put(current_day, empty_day);
    }

    // Now aggregate the actual commits
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
                .language_stats = null,
            };
            try day_map.put(day_start, updated);
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

pub fn generateMonthlyReports(allocator: std.mem.Allocator, commits: []const Commit) ![]MonthlyReport {
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