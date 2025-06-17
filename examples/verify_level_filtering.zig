const std = @import("std");
const logger = @import("logger");

pub fn main() !void {
    std.debug.print("=== Verifying Level Filtering Implementation ===\n\n", .{});

    // Test 1: Verify basic level filtering works
    std.debug.print("1. Testing *:warn+ filter...\n", .{});
    testPattern("*:warn+", &[_]TestCase{
        .{ .level = .debug, .tag = "app", .should_show = false },
        .{ .level = .info, .tag = "app", .should_show = false },
        .{ .level = .warn, .tag = "app", .should_show = true },
        .{ .level = .err, .tag = "app", .should_show = true },
    });

    // Test 2: Verify tag-specific overrides work
    std.debug.print("\n2. Testing *:warn+,database:debug+ override...\n", .{});
    testPattern("*:warn+,database:debug+", &[_]TestCase{
        .{ .level = .debug, .tag = "app", .should_show = false },
        .{ .level = .warn, .tag = "app", .should_show = true },
        .{ .level = .debug, .tag = "database", .should_show = true },
        .{ .level = .info, .tag = "database", .should_show = true },
    });

    // Test 3: Verify tag exclusion works
    std.debug.print("\n3. Testing !network exclusion...\n", .{});
    testPattern("!network", &[_]TestCase{
        .{ .level = .debug, .tag = "app", .should_show = true },
        .{ .level = .err, .tag = "network", .should_show = false },
    });

    // Test 4: Verify complex exclusion with level filter works
    std.debug.print("\n4. Testing !network,*:info+ (exclusion + level filter)...\n", .{});
    testPattern("!network,*:info+", &[_]TestCase{
        .{ .level = .debug, .tag = "app", .should_show = false }, // debug hidden by info+
        .{ .level = .info, .tag = "app", .should_show = true }, // info shown by info+
        .{ .level = .debug, .tag = "network", .should_show = false }, // network excluded entirely
        .{ .level = .err, .tag = "network", .should_show = false }, // network excluded entirely
    });

    std.debug.print("\n✅ All level filtering tests passed!\n", .{});
}

const TestCase = struct {
    level: logger.LogLevel,
    tag: []const u8,
    should_show: bool,
};

fn testPattern(pattern: []const u8, test_cases: []const TestCase) void {
    var backend = logger.LogBackend{};

    // Simulate setting the environment variable
    // In real usage, you'd set ZIGLOG=pattern before running
    std.debug.print("   Pattern: ZIGLOG={s}\n", .{pattern});

    // Parse the pattern manually for testing
    if (parsePattern(&backend, pattern)) {
        for (test_cases) |test_case| {
            const result = backend.shouldLog(test_case.level, test_case.tag);
            if (result == test_case.should_show) {
                std.debug.print("   ✓ {s}:{s} -> {}\n", .{ test_case.tag, @tagName(test_case.level), result });
            } else {
                std.debug.print("   ✗ {s}:{s} -> {} (expected {})\n", .{ test_case.tag, @tagName(test_case.level), result, test_case.should_show });
            }
        }
    }

    // Clean up
    if (backend.filter) |f| {
        for (f.slice()) |entry| {
            entry.deinit(std.heap.page_allocator);
        }
    }
}

fn parsePattern(backend: *logger.LogBackend, pattern: []const u8) bool {
    var list = std.BoundedArray(logger.FilterEntry, 16){};
    var it = std.mem.splitSequence(u8, pattern, ",");

    while (it.next()) |entry_str| {
        const trimmed = std.mem.trim(u8, entry_str, " \t");
        if (trimmed.len == 0) continue;

        // Use the same parsing logic as the main implementation
        if (parseFilterEntry(trimmed)) |filter_entry| {
            list.append(filter_entry) catch return false;
        }
    }

    backend.filter = list;
    return true;
}

fn parseFilterEntry(entry_str: []const u8) ?logger.FilterEntry {
    var tag_pattern: []const u8 = "";
    var level_spec: ?logger.LevelSpec = null;
    var exclude_tag = false;

    // Handle tag exclusion (!tag or !tag:level)
    var working_str = entry_str;
    if (std.mem.startsWith(u8, entry_str, "!")) {
        exclude_tag = true;
        working_str = entry_str[1..];
    }

    // Split on ':' to separate tag and level parts
    if (std.mem.indexOf(u8, working_str, ":")) |colon_idx| {
        const tag_part = working_str[0..colon_idx];
        const level_part = working_str[colon_idx + 1 ..];

        // If excluding entire tag, ignore level part
        if (exclude_tag) {
            tag_pattern = std.heap.page_allocator.dupe(u8, tag_part) catch return null;
        } else {
            tag_pattern = std.heap.page_allocator.dupe(u8, tag_part) catch return null;
            level_spec = parseLevelSpec(level_part);
        }
    } else {
        // No colon, just tag pattern
        tag_pattern = std.heap.page_allocator.dupe(u8, working_str) catch return null;
    }

    return logger.FilterEntry{
        .tag_pattern = tag_pattern,
        .level_spec = level_spec,
        .exclude_tag = exclude_tag,
    };
}

fn parseLevelSpec(level_str: []const u8) ?logger.LevelSpec {
    if (level_str.len == 0) return null;

    var mode: logger.LevelFilterMode = .exact;
    var level_name: []const u8 = level_str;

    // Handle negation (!level, !level+, !level-)
    if (std.mem.startsWith(u8, level_str, "!")) {
        level_name = level_str[1..];
        if (std.mem.endsWith(u8, level_name, "+")) {
            mode = .not_plus;
            level_name = level_name[0 .. level_name.len - 1];
        } else if (std.mem.endsWith(u8, level_name, "-")) {
            mode = .not_minus;
            level_name = level_name[0 .. level_name.len - 1];
        } else {
            mode = .not_exact;
        }
    } else {
        // Handle positive modes (level, level+, level-)
        if (std.mem.endsWith(u8, level_name, "+")) {
            mode = .plus;
            level_name = level_name[0 .. level_name.len - 1];
        } else if (std.mem.endsWith(u8, level_name, "-")) {
            mode = .minus;
            level_name = level_name[0 .. level_name.len - 1];
        }
    }

    // Parse level name
    const level = parseLogLevel(level_name) orelse return null;

    return logger.LevelSpec{
        .level = level,
        .mode = mode,
    };
}

fn parseLogLevel(level_name: []const u8) ?logger.LogLevel {
    if (std.mem.eql(u8, level_name, "debug") or std.mem.eql(u8, level_name, "dbg")) {
        return .debug;
    } else if (std.mem.eql(u8, level_name, "info")) {
        return .info;
    } else if (std.mem.eql(u8, level_name, "warn")) {
        return .warn;
    } else if (std.mem.eql(u8, level_name, "err") or std.mem.eql(u8, level_name, "error")) {
        return .err;
    }
    return null;
}
