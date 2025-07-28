const std = @import("std");
const process = std.process;
const print = std.debug.print;

// Import modules
const types = @import("types.zig");
const git = @import("git.zig");
const reports = @import("reports.zig");
const display = @import("display.zig");
const language = @import("language.zig");

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
    var show_languages: bool = false;
    
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
        } else if (std.mem.eql(u8, args[i], "--by-language")) {
            show_languages = true;
        } else if (std.mem.startsWith(u8, args[i], "--max-commit-size=")) {
            max_commit_size = std.fmt.parseInt(u64, args[i][18..], 10) catch {
                std.debug.print("Error: Invalid max-commit-size value\n", .{});
                return;
            };
        } else if (std.mem.eql(u8, args[i], "-h") or std.mem.eql(u8, args[i], "--help")) {
            display.printHelp();
            return;
        }
    }

    // Execute git command and parse output
    const commits = try git.executeGitLog(allocator, since_arg);
    defer allocator.free(commits);

    if (commits.len == 0) {
        print("No commits found in the specified time range.\n", .{});
        return;
    }

    // Apply filtering if requested
    const filtered_commits = if (filter_large) 
        try git.filterLargeCommits(allocator, commits, max_commit_size)
    else
        commits;

    // Show language breakdown if requested
    if (show_languages) {
        try language.showLanguageBreakdown(allocator, since_arg, use_colors);
        return;
    }
    
    if (history_mode) {
        // Generate monthly reports for history view
        const monthly_reports = try reports.generateMonthlyReports(allocator, filtered_commits);
        defer allocator.free(monthly_reports);
        display.printMonthlyReport(since_arg, monthly_reports, use_colors);
    } else {
        // Generate daily reports for default view
        const daily_reports = try reports.generateDailyReports(allocator, filtered_commits);
        defer allocator.free(daily_reports);
        display.printDailyReport(since_arg, daily_reports, use_colors);
    }

    // Free filtered commits if we allocated them
    if (filter_large) {
        allocator.free(filtered_commits);
    }
}