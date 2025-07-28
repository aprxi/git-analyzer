const std = @import("std");
const types = @import("types.zig");

const LanguageInfo = types.LanguageInfo;
const LanguageStats = types.LanguageStats;
const Color = types.Color;
const print = std.debug.print;

pub fn getLanguageFromFile(filename: []const u8) LanguageInfo {
    const ext_start = std.mem.lastIndexOf(u8, filename, ".") orelse return .{ .name = "Other", .color = "\x1b[37m" };
    const ext = filename[ext_start..];
    
    // Popular language mappings with ANSI colors
    if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".jsx")) return .{ .name = "JavaScript", .color = "\x1b[33m" }; // Yellow
    if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".tsx")) return .{ .name = "TypeScript", .color = "\x1b[34m" }; // Blue
    if (std.mem.eql(u8, ext, ".py")) return .{ .name = "Python", .color = "\x1b[32m" }; // Green
    if (std.mem.eql(u8, ext, ".rs")) return .{ .name = "Rust", .color = "\x1b[31m" }; // Red
    if (std.mem.eql(u8, ext, ".go")) return .{ .name = "Go", .color = "\x1b[36m" }; // Cyan
    if (std.mem.eql(u8, ext, ".java")) return .{ .name = "Java", .color = "\x1b[35m" }; // Magenta
    if (std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h")) return .{ .name = "C", .color = "\x1b[94m" }; // Light Blue
    if (std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".cc") or std.mem.eql(u8, ext, ".hpp")) return .{ .name = "C++", .color = "\x1b[95m" }; // Light Magenta
    if (std.mem.eql(u8, ext, ".zig")) return .{ .name = "Zig", .color = "\x1b[93m" }; // Light Yellow
    if (std.mem.eql(u8, ext, ".rb")) return .{ .name = "Ruby", .color = "\x1b[91m" }; // Light Red
    if (std.mem.eql(u8, ext, ".php")) return .{ .name = "PHP", .color = "\x1b[96m" }; // Light Cyan
    if (std.mem.eql(u8, ext, ".cs")) return .{ .name = "C#", .color = "\x1b[92m" }; // Light Green
    if (std.mem.eql(u8, ext, ".swift")) return .{ .name = "Swift", .color = "\x1b[33m" }; // Yellow
    if (std.mem.eql(u8, ext, ".kt")) return .{ .name = "Kotlin", .color = "\x1b[35m" }; // Magenta
    if (std.mem.eql(u8, ext, ".scala")) return .{ .name = "Scala", .color = "\x1b[31m" }; // Red
    if (std.mem.eql(u8, ext, ".sh") or std.mem.eql(u8, ext, ".bash")) return .{ .name = "Shell", .color = "\x1b[32m" }; // Green
    if (std.mem.eql(u8, ext, ".sql")) return .{ .name = "SQL", .color = "\x1b[37m" }; // White
    if (std.mem.eql(u8, ext, ".html") or std.mem.eql(u8, ext, ".htm")) return .{ .name = "HTML", .color = "\x1b[33m" }; // Yellow
    if (std.mem.eql(u8, ext, ".css") or std.mem.eql(u8, ext, ".scss") or std.mem.eql(u8, ext, ".sass")) return .{ .name = "CSS", .color = "\x1b[35m" }; // Magenta
    if (std.mem.eql(u8, ext, ".md") or std.mem.eql(u8, ext, ".markdown")) return .{ .name = "Markdown", .color = "\x1b[37m" }; // White
    if (std.mem.eql(u8, ext, ".json")) return .{ .name = "JSON", .color = "\x1b[37m" }; // White
    if (std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml")) return .{ .name = "YAML", .color = "\x1b[37m" }; // White
    if (std.mem.eql(u8, ext, ".xml")) return .{ .name = "XML", .color = "\x1b[37m" }; // White
    
    return .{ .name = "Other", .color = "\x1b[37m" }; // White
}

pub fn showLanguageBreakdown(allocator: std.mem.Allocator, since: []const u8, use_colors: bool) !void {
    // Execute git log with file details
    const argv = [_][]const u8{
        "git", "log", "--since", since, "--numstat", "--pretty=format:---COMMIT---%n%at",
    };
    
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &argv,
        .max_output_bytes = 512 * 1024 * 1024, // 512MB max
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    if (result.term.Exited != 0) {
        std.debug.print("Error executing git command: {s}\n", .{result.stderr});
        return;
    }
    
    // Parse language statistics
    var language_map = std.StringHashMap(LanguageStats).init(allocator);
    defer {
        var it = language_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        language_map.deinit();
    }
    
    var line_iterator = std.mem.split(u8, result.stdout, "\n");
    while (line_iterator.next()) |line| {
        if (line.len == 0 or std.mem.eql(u8, line, "---COMMIT---")) continue;
        
        // Parse numstat line (added\tdeleted\tfilename)
        var tab_iterator = std.mem.split(u8, line, "\t");
        
        if (tab_iterator.next()) |added_str| {
            if (tab_iterator.next()) |deleted_str| {
                if (tab_iterator.next()) |filename| {
                    // Skip binary files and timestamps
                    if (std.mem.eql(u8, added_str, "-") or 
                        std.mem.eql(u8, deleted_str, "-") or
                        std.fmt.parseInt(i64, line, 10) catch null != null) continue;
                    
                    const added = std.fmt.parseInt(u64, added_str, 10) catch continue;
                    const deleted = std.fmt.parseInt(u64, deleted_str, 10) catch continue;
                    
                    const lang_info = getLanguageFromFile(filename);
                    
                    if (language_map.get(lang_info.name)) |existing| {
                        try language_map.put(lang_info.name, .{
                            .added = existing.added + added,
                            .deleted = existing.deleted + deleted,
                        });
                    } else {
                        const key = try allocator.dupe(u8, lang_info.name);
                        try language_map.put(key, .{
                            .added = added,
                            .deleted = deleted,
                        });
                    }
                }
            }
        }
    }
    
    // Convert to sorted array
    var entries = std.ArrayList(struct { lang: []const u8, stats: LanguageStats, color: []const u8 }).init(allocator);
    defer entries.deinit();
    
    var it = language_map.iterator();
    while (it.next()) |entry| {
        // Find color for this language by checking common extensions
        var color = "\x1b[37m"; // Default white
        if (std.mem.eql(u8, entry.key_ptr.*, "JavaScript")) {
            color = "\x1b[33m";
        } else if (std.mem.eql(u8, entry.key_ptr.*, "TypeScript")) {
            color = "\x1b[34m";
        } else if (std.mem.eql(u8, entry.key_ptr.*, "Python")) {
            color = "\x1b[32m";
        } else if (std.mem.eql(u8, entry.key_ptr.*, "Rust")) {
            color = "\x1b[31m";
        } else if (std.mem.eql(u8, entry.key_ptr.*, "Go")) {
            color = "\x1b[36m";
        } else if (std.mem.eql(u8, entry.key_ptr.*, "Java")) {
            color = "\x1b[35m";
        } else if (std.mem.eql(u8, entry.key_ptr.*, "C")) {
            color = "\x1b[94m";
        } else if (std.mem.eql(u8, entry.key_ptr.*, "C++")) {
            color = "\x1b[95m";
        } else if (std.mem.eql(u8, entry.key_ptr.*, "Zig")) {
            color = "\x1b[93m";
        }
        try entries.append(.{
            .lang = entry.key_ptr.*,
            .stats = entry.value_ptr.*,
            .color = color,
        });
    }
    
    // Sort by total changes (descending)
    std.mem.sort(@TypeOf(entries.items[0]), entries.items, {}, struct {
        fn lessThan(_: void, a: @TypeOf(entries.items[0]), b: @TypeOf(entries.items[0])) bool {
            const a_total = a.stats.added + a.stats.deleted;
            const b_total = b.stats.added + b.stats.deleted;
            return a_total > b_total;
        }
    }.lessThan);
    
    // Print header
    if (use_colors) {
        print("\n{s}Language Breakdown{s} for the last {s}{s}{s}\n\n", .{
            Color.BOLD, Color.RESET, Color.BOLD, since, Color.RESET
        });
    } else {
        print("\nLanguage Breakdown for the last {s}\n\n", .{since});
    }
    
    // Print table header
    print("| {s:<15} | {s:>12} | {s:>12} | {s:>12} | {s:>10} |\n", .{
        "Language", "Lines Added", "Lines Deleted", "Total Changes", "Percentage"
    });
    print("|{s:-<17}|{s:-<14}|{s:-<14}|{s:-<14}|{s:-<12}|\n", .{
        "-" ** 17, "-" ** 14, "-" ** 14, "-" ** 14, "-" ** 12
    });
    
    // Calculate totals
    var total_added: u64 = 0;
    var total_deleted: u64 = 0;
    for (entries.items) |entry| {
        total_added += entry.stats.added;
        total_deleted += entry.stats.deleted;
    }
    const grand_total = total_added + total_deleted;
    
    // Import format module for line formatting
    const format = @import("format.zig");
    
    // Print each language
    for (entries.items) |entry| {
        const total = entry.stats.added + entry.stats.deleted;
        const percentage = if (grand_total > 0) 
            @as(f32, @floatFromInt(total)) * 100.0 / @as(f32, @floatFromInt(grand_total))
            else 0;
        
        if (use_colors) {
            print("| {s}{s:<15}{s} | ", .{entry.color, entry.lang, Color.RESET});
        } else {
            print("| {s:<15} | ", .{entry.lang});
        }
        
        const added_str = format.formatLinesAdded(entry.stats.added, use_colors);
        const deleted_str = format.formatLinesDeleted(entry.stats.deleted, use_colors);
        
        print("{s:>12} | {s:>12} | {d:>12} | {d:>9.1}% |\n", .{
            added_str, deleted_str, total, percentage
        });
    }
    
    // Print totals
    print("|{s:-<17}|{s:-<14}|{s:-<14}|{s:-<14}|{s:-<12}|\n", .{
        "-" ** 17, "-" ** 14, "-" ** 14, "-" ** 14, "-" ** 12
    });
    
    const total_added_str = format.formatLinesAdded(total_added, use_colors);
    const total_deleted_str = format.formatLinesDeleted(total_deleted, use_colors);
    
    if (use_colors) {
        print("| {s}TOTAL{s}           | {s:>12} | {s:>12} | {s}{d:>12}{s} | {s}100.0%{s}     |\n", .{
            Color.BOLD, Color.RESET,
            total_added_str, total_deleted_str,
            Color.BOLD, grand_total, Color.RESET,
            Color.BOLD, Color.RESET
        });
    } else {
        print("| TOTAL           | {s:>12} | {s:>12} | {d:>12} | 100.0%     |\n", .{
            total_added_str, total_deleted_str, grand_total
        });
    }
    
    print("\n", .{});
}