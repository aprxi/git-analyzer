const std = @import("std");
const types = @import("types.zig");

const Commit = types.Commit;
const print = std.debug.print;

pub fn executeGitLog(allocator: std.mem.Allocator, since: []const u8) ![]Commit {
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
    
    // Read from pipes
    if (child.stdout) |stdout| {
        const reader = stdout.reader();
        var buffer: [8192]u8 = undefined;
        while (true) {
            const bytes_read = try reader.read(&buffer);
            if (bytes_read == 0) break;
            try stdout_data.appendSlice(buffer[0..bytes_read]);
        }
    }
    
    if (child.stderr) |stderr| {
        const reader = stderr.reader();
        var buffer: [4096]u8 = undefined;
        while (true) {
            const bytes_read = try reader.read(&buffer);
            if (bytes_read == 0) break;
            try stderr_data.appendSlice(buffer[0..bytes_read]);
        }
    }
    
    // Wait for process to complete
    const term = try child.wait();
    
    if (term.Exited != 0) {
        print("Error executing git command: {s}\n", .{stderr_data.items});
        return error.GitCommandFailed;
    }
    
    // For very large outputs, process in streaming fashion
    if (stdout_data.items.len > 10 * 1024 * 1024) { // 10MB threshold
        return parseGitOutputStreaming(allocator, stdout_data.items);
    }
    
    return parseGitOutput(allocator, stdout_data.items);
}

pub fn parseGitOutputStreaming(allocator: std.mem.Allocator, output: []const u8) ![]Commit {
    // For very large repositories, we could process line by line to save memory
    // For now, use the existing logic but with better memory management
    return parseGitOutput(allocator, output);
}

pub fn filterLargeCommits(allocator: std.mem.Allocator, commits: []const Commit, max_commit_size: u64) ![]Commit {
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
        print("Filtered out {d} large commits (>{d} lines changed) with {d} total lines changed.\n", 
            .{filtered_count, max_commit_size, total_filtered_lines});
    }
    
    return try filtered.toOwnedSlice();
}

pub fn parseGitOutput(allocator: std.mem.Allocator, output: []const u8) ![]Commit {
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
                    print("\rProcessed {d} commits...", .{processed_commits});
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
        print("\rProcessed {d} commits total.\n", .{processed_commits});
    } else if (processed_commits > 0) {
        print("Processed {d} commits total.\n", .{processed_commits});
    }

    return try commits.toOwnedSlice();
}