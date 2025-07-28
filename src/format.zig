const std = @import("std");
const types = @import("types.zig");

const Color = types.Color;

pub fn formatDailyDate(timestamp: i64) [12]u8 {
    const seconds_per_day: i64 = 24 * 60 * 60;
    const days_since_epoch = @divFloor(timestamp, seconds_per_day);
    
    // Simple date calculation (approximate)
    const years_since_1970 = @divFloor(days_since_epoch, 365);
    const year = 1970 + years_since_1970;
    
    // Calculate day within year (approximate)
    const year_start_day = years_since_1970 * 365;
    const day_in_year = days_since_epoch - year_start_day;
    
    // Approximate month and day
    const months = [_]struct { name: []const u8, days: u32 }{
        .{ .name = "Jan", .days = 31 },
        .{ .name = "Feb", .days = 28 }, // Ignoring leap years for simplicity
        .{ .name = "Mar", .days = 31 },
        .{ .name = "Apr", .days = 30 },
        .{ .name = "May", .days = 31 },
        .{ .name = "Jun", .days = 30 },
        .{ .name = "Jul", .days = 31 },
        .{ .name = "Aug", .days = 31 },
        .{ .name = "Sep", .days = 30 },
        .{ .name = "Oct", .days = 31 },
        .{ .name = "Nov", .days = 30 },
        .{ .name = "Dec", .days = 31 },
    };
    
    var accumulated_days: u32 = 0;
    var month_name: []const u8 = "Jan";
    var day_of_month: u32 = 1;
    
    for (months) |month| {
        if (day_in_year >= accumulated_days and day_in_year < accumulated_days + month.days) {
            month_name = month.name;
            day_of_month = @as(u32, @intCast(day_in_year - accumulated_days + 1));
            break;
        }
        accumulated_days += month.days;
    }
    
    var result: [12]u8 = undefined;
    _ = std.fmt.bufPrint(&result, "{s} {d:>2}, {d}", .{ month_name, day_of_month, year }) catch {
        return "Invalid Date".*;
    };
    return result;
}

pub fn formatMonthly(timestamp: i64) [12]u8 {
    const seconds_per_day: i64 = 24 * 60 * 60;
    const days_since_epoch = @divFloor(timestamp, seconds_per_day);
    
    // Simple date calculation (approximate)
    const years_since_1970 = @divFloor(days_since_epoch, 365);
    const year = 1970 + years_since_1970;
    
    // Calculate day within year
    const year_start_day = years_since_1970 * 365;
    const day_in_year = days_since_epoch - year_start_day;
    
    // Approximate month
    const months = [_][]const u8{
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    };
    
    // Very simple month calculation (30 days per month average)
    const month_index = @min(11, @as(usize, @intCast(@divFloor(day_in_year, 30))));
    const month_name = months[month_index];
    
    var result: [12]u8 = undefined;
    _ = std.fmt.bufPrint(&result, "{s} {d}", .{ month_name, year }) catch {
        return "Invalid Date".*;
    };
    return result;
}

pub fn formatLinesAdded(lines: u64, use_colors: bool) [25]u8 {
    var result = [_]u8{' '} ** 25;
    const str = std.fmt.bufPrint(&result, "+{d}", .{lines}) catch {
        std.mem.copyForwards(u8, &result, "+???");
        return result;
    };
    
    if (use_colors and lines > 0) {
        var colored = [_]u8{' '} ** 25;
        _ = std.fmt.bufPrint(&colored, "{s}{s}{s}", .{ Color.GREEN, str, Color.RESET }) catch return result;
        return colored;
    }
    
    // Ensure result is null-terminated or padded
    for (str.len..result.len) |i| {
        result[i] = ' ';
    }
    return result;
}

pub fn formatLinesDeleted(lines: u64, use_colors: bool) [25]u8 {
    var result = [_]u8{' '} ** 25;
    const str = std.fmt.bufPrint(&result, "-{d}", .{lines}) catch {
        std.mem.copyForwards(u8, &result, "-???");
        return result;
    };
    
    if (use_colors and lines > 0) {
        var colored = [_]u8{' '} ** 25;
        _ = std.fmt.bufPrint(&colored, "{s}{s}{s}", .{ Color.RED, str, Color.RESET }) catch return result;
        return colored;
    }
    
    // Ensure result is null-terminated or padded
    for (str.len..result.len) |i| {
        result[i] = ' ';
    }
    return result;
}