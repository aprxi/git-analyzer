const std = @import("std");

pub const Color = struct {
    pub const RESET = "\x1b[0m";
    pub const RED = "\x1b[31m";
    pub const GREEN = "\x1b[32m";
    pub const YELLOW = "\x1b[33m";
    pub const BLUE = "\x1b[34m";
    pub const MAGENTA = "\x1b[35m";
    pub const CYAN = "\x1b[36m";
    pub const BOLD = "\x1b[1m";
    pub const DIM = "\x1b[2m";
};

pub const Commit = struct {
    timestamp: i64,
    lines_added: u64,
    lines_deleted: u64,
};

pub const LanguageStats = struct {
    added: u64,
    deleted: u64,
};

pub const DailyReport = struct {
    day_timestamp: i64,
    commits: u64,
    lines_added: u64,
    lines_deleted: u64,
    avg_commit_size: f32,
    refactoring_ratio: f32,
    language_stats: ?std.StringHashMap(LanguageStats),
};

pub const MonthlyReport = struct {
    month_timestamp: i64,
    commits: u64,
    lines_added: u64,
    lines_deleted: u64,
    avg_commit_size: f32,
    refactoring_ratio: f32,
    // Store a representative actual timestamp for proper date formatting
    sample_timestamp: i64,
};

pub const LanguageInfo = struct {
    name: []const u8,
    color: []const u8,
};