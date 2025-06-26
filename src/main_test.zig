const std = @import("std");
const testing = std.testing;
const logger = @import("main.zig");
const builtin = @import("builtin");

test "basic logging" {
    std.debug.print("Testing basic logging...\n", .{});
    const log = logger.new(.{});
    log.info("test info message", .{});
    log.warn("test warning message", .{});
    log.err("test error message", .{});
    log.dbg("test debug message", .{});
    std.debug.print("Basic logging test completed\n", .{});
}

test "custom tag and color" {
    std.debug.print("Testing custom tag and color...\n", .{});
    const log = logger.new(.{
        .tag = "test",
        .color = .blue,
    });
    log.info("test message with custom tag and color", .{});
    std.debug.print("Custom tag and color test completed\n", .{});
}

test "timestamp logging" {
    std.debug.print("Testing timestamp logging...\n", .{});
    const log = logger.new(.{
        .show_timestamp = true,
    });
    log.info("test message with timestamp", .{});
    std.debug.print("Timestamp logging test completed\n", .{});
}

test "block logging" {
    std.debug.print("Testing block logging...\n", .{});
    const log = logger.new(.{});
    const block = log.block("test_block");
    block.info("inside block", .{});
    block.close("block completed");
    std.debug.print("Block logging test completed\n", .{});
}

test "hexdump" {
    std.debug.print("Testing hexdump...\n", .{});
    const log = logger.new(.{});
    const data = "Hello, World!";
    log.hexdump(data, .{});
    std.debug.print("Hexdump test completed\n", .{});
}

// test "tag filtering" {
//     // Test with no filter
//     const log1 = logger.new(.{ .tag = "test1" });
//     log1.info("should be visible", .{});
//
//     // Test with matching filter
//     std.posix.setenv("ZIGLOG", "test2", true) catch {};
//     const log2 = logger.new(.{ .tag = "test2" });
//     log2.info("should be visible", .{});
//
//     // Test with non-matching filter
//     const log3 = logger.new(.{ .tag = "test3" });
//     log3.info("should not be visible", .{});
//
//     // Clean up
//     std.posix.unsetenv("ZIGLOG") catch {};
// }

test "file logging" {
    std.debug.print("Testing file logging...\n", .{});
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file = tmp_dir.dir.createFile("test.log", .{}) catch |err| {
        std.debug.print("Failed to create test log file: {}\n", .{err});
        return;
    };
    defer file.close();

    const log = logger.new(.{
        .file = file,
        .tag = "file_test",
    });

    log.info("test message to file", .{});
    std.debug.print("File logging test completed\n", .{});
}

// test "fatal logging" {
//     const log = logger.new(.{});
//     // Note: We can't actually test the exit behavior, but we can verify it compiles
//     _ = log.fatal;
// }

test "multiple loggers" {
    std.debug.print("Testing multiple loggers...\n", .{});
    const log1 = logger.new(.{ .tag = "logger1" });
    const log2 = logger.new(.{ .tag = "logger2" });

    log1.info("from logger 1", .{});
    log2.info("from logger 2", .{});
    std.debug.print("Multiple loggers test completed\n", .{});
}

test "hexdump options" {
    std.debug.print("Testing hexdump options...\n", .{});
    const log = logger.new(.{});
    const data = "Hello, World!";

    log.hexdump(data, .{
        .decimal_offset = true,
        .length = 5,
        .start = 2,
    });
    std.debug.print("Hexdump options test completed\n", .{});
}

fn workerThread(thread_id: u32) void {
    const tmp_tag = std.fmt.allocPrint(std.heap.page_allocator, "T{d}", .{thread_id}) catch "THREAD";
    const log = logger.new(.{ .tag = tmp_tag });
    if (!std.mem.eql(u8, tmp_tag, "THREAD")) {
        std.heap.page_allocator.free(tmp_tag);
    }

    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        log.info("Message {d} from thread {d}", .{ i, thread_id });
        if (i == 1) {
            const data = std.fmt.allocPrint(std.heap.page_allocator, "T{d}", .{thread_id}) catch "T";
            defer if (!std.mem.eql(u8, data, "T")) std.heap.page_allocator.free(data);
            log.hexdump(data, .{});
        }
        std.time.sleep(500000); // 0.5ms
    }
}

test "thread safety" {
    std.debug.print("Testing thread-safe logging...\n", .{});

    const num_threads = 2;
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, workerThread, .{@as(u32, @intCast(i))}) catch |err| {
            std.debug.print("Failed to spawn thread {}: {}\n", .{ i, err });
            return;
        };
    }

    for (threads) |thread| {
        thread.join();
    }

    std.debug.print("Thread safety test completed\n", .{});
}

test "wildcard tag filtering" {
    std.debug.print("Testing wildcard tag filtering...\n", .{});

    // Test different wildcard patterns
    const test_cases = [_]struct {
        pattern: []const u8,
        tag: []const u8,
        should_match: bool,
    }{
        // Exact matches
        .{ .pattern = "test", .tag = "test", .should_match = true },
        .{ .pattern = "test", .tag = "other", .should_match = false },

        // Prefix wildcards (tag*)
        .{ .pattern = "test*", .tag = "test", .should_match = true },
        .{ .pattern = "test*", .tag = "testing", .should_match = true },
        .{ .pattern = "test*", .tag = "test123", .should_match = true },
        .{ .pattern = "test*", .tag = "other", .should_match = false },

        // Suffix wildcards (*tag)
        .{ .pattern = "*test", .tag = "test", .should_match = true },
        .{ .pattern = "*test", .tag = "mytest", .should_match = true },
        .{ .pattern = "*test", .tag = "testing", .should_match = false },

        // Contains wildcards (*tag*)
        .{ .pattern = "*test*", .tag = "test", .should_match = true },
        .{ .pattern = "*test*", .tag = "testing", .should_match = true },
        .{ .pattern = "*test*", .tag = "mytest", .should_match = true },
        .{ .pattern = "*test*", .tag = "mytesting", .should_match = true },
        .{ .pattern = "*test*", .tag = "other", .should_match = false },

        // Edge cases
        .{ .pattern = "*", .tag = "anything", .should_match = true },
    };

    var backend = logger.LogBackend{};

    for (test_cases) |case| {
        const result = backend.tagMatches(case.tag, case.pattern);
        if (result != case.should_match) {
            std.debug.print("FAIL: pattern '{s}' with tag '{s}' expected {}, got {}\n", .{ case.pattern, case.tag, case.should_match, result });
            return error.TestFailed;
        }
    }

    std.debug.print("Wildcard tag filtering test completed\n", .{});
}

test "NOT operator filtering" {
    std.debug.print("Testing NOT operator filtering...\n", .{});

    const test_cases = [_]struct {
        patterns: []const []const u8,
        tag: []const u8,
        level: logger.LogLevel,
        should_match: bool,
        description: []const u8,
    }{
        // Simple NOT patterns
        .{ .patterns = &[_][]const u8{"!debug"}, .tag = "debug", .level = .info, .should_match = false, .description = "!debug excludes debug" },
        .{ .patterns = &[_][]const u8{"!debug"}, .tag = "info", .level = .info, .should_match = true, .description = "!debug allows info" },

        // NOT with wildcards
        .{ .patterns = &[_][]const u8{"!test*"}, .tag = "testing", .level = .info, .should_match = false, .description = "!test* excludes testing" },
        .{ .patterns = &[_][]const u8{"!test*"}, .tag = "production", .level = .info, .should_match = true, .description = "!test* allows production" },
        .{ .patterns = &[_][]const u8{"!*debug*"}, .tag = "api_debug", .level = .info, .should_match = false, .description = "!*debug* excludes api_debug" },
        .{ .patterns = &[_][]const u8{"!*debug*"}, .tag = "api_info", .level = .info, .should_match = true, .description = "!*debug* allows api_info" },

        // Include + exclude combinations
        .{ .patterns = &[_][]const u8{ "api*", "!api_debug" }, .tag = "api_server", .level = .info, .should_match = true, .description = "api*,!api_debug allows api_server" },
        .{ .patterns = &[_][]const u8{ "api*", "!api_debug" }, .tag = "api_debug", .level = .info, .should_match = false, .description = "api*,!api_debug excludes api_debug" },
        .{ .patterns = &[_][]const u8{ "api*", "!api_debug" }, .tag = "database", .level = .info, .should_match = false, .description = "api*,!api_debug excludes database" },

        // Multiple excludes
        .{ .patterns = &[_][]const u8{ "*", "!test*", "!*debug" }, .tag = "production", .level = .info, .should_match = true, .description = "*,!test*,!*debug allows production" },
        .{ .patterns = &[_][]const u8{ "*", "!test*", "!*debug" }, .tag = "testing", .level = .info, .should_match = false, .description = "*,!test*,!*debug excludes testing" },
        .{ .patterns = &[_][]const u8{ "*", "!test*", "!*debug" }, .tag = "api_debug", .level = .info, .should_match = false, .description = "*,!test*,!*debug excludes api_debug" },

        // Complex scenarios
        .{ .patterns = &[_][]const u8{ "web*", "db*", "!*test", "!*debug" }, .tag = "web_server", .level = .info, .should_match = true, .description = "complex: allows web_server" },
        .{ .patterns = &[_][]const u8{ "web*", "db*", "!*test", "!*debug" }, .tag = "db_connection", .level = .info, .should_match = true, .description = "complex: allows db_connection" },
        .{ .patterns = &[_][]const u8{ "web*", "db*", "!*test", "!*debug" }, .tag = "web_test", .level = .info, .should_match = false, .description = "complex: excludes web_test" },
        .{ .patterns = &[_][]const u8{ "web*", "db*", "!*test", "!*debug" }, .tag = "api_server", .level = .info, .should_match = false, .description = "complex: excludes api_server" },
    };

    for (test_cases) |case| {
        // Create a backend and manually set up the filter
        var backend = logger.LogBackend{};
        var filter_list = std.BoundedArray(logger.FilterEntry, 16){};

        for (case.patterns) |pattern| {
            // Create FilterEntry manually based on pattern
            var exclude_tag = false;
            var working_str = pattern;
            if (std.mem.startsWith(u8, pattern, "!")) {
                exclude_tag = true;
                working_str = pattern[1..];
            }

            const tag_pattern = std.heap.page_allocator.dupe(u8, working_str) catch continue;

            const filter_entry = logger.FilterEntry{
                .tag_pattern = tag_pattern,
                .exclude_tag = exclude_tag,
            };

            filter_list.append(filter_entry) catch continue;
        }
        backend.filter = filter_list;
        backend.filter_loaded = true; // Mark filter as loaded for the test

        const result = backend.shouldLogUnsafe(case.level, case.tag);

        if (result != case.should_match) {
            std.debug.print("FAIL: {s} - expected {}, got {}\n", .{ case.description, case.should_match, result });

            // Clean up allocated patterns
            for (filter_list.slice()) |entry| {
                std.heap.page_allocator.free(entry.tag_pattern);
            }
            return error.TestFailed;
        } else {
            std.debug.print("PASS: {s}\n", .{case.description});
        }

        // Clean up allocated patterns
        for (filter_list.slice()) |entry| {
            std.heap.page_allocator.free(entry.tag_pattern);
        }
    }

    std.debug.print("NOT operator filtering test completed\n", .{});
}

test "show level functionality" {
    std.debug.print("Testing show level functionality...\n", .{});

    // Test individual logger show_level setting
    const default_log = logger.new(.{ .tag = "test_default" });
    const level_log = logger.new(.{ .tag = "test_level", .show_level = true });

    // These should work without throwing errors
    default_log.info("message without level", .{});
    level_log.info("message with level", .{});

    // Test global level setting
    logger.setGlobalLevel(true);
    default_log.info("message with global level", .{});

    logger.setGlobalLevel(false);
    default_log.info("message without global level", .{});
    level_log.info("message with individual level", .{});

    std.debug.print("Show level functionality test completed\n", .{});
}

test "level filtering - basic level specs" {
    std.debug.print("Testing basic level filtering specs...\n", .{});

    const TestCase = struct {
        pattern: []const u8,
        tag: []const u8,
        level: logger.LogLevel,
        should_show: bool,
        description: []const u8,
    };

    const test_cases = [_]TestCase{
        // Exact level matching
        .{ .pattern = "*:debug", .tag = "app", .level = .debug, .should_show = true, .description = "*:debug allows debug" },
        .{ .pattern = "*:debug", .tag = "app", .level = .info, .should_show = false, .description = "*:debug excludes info" },
        .{ .pattern = "*:info", .tag = "app", .level = .info, .should_show = true, .description = "*:info allows info" },
        .{ .pattern = "*:warn", .tag = "app", .level = .warn, .should_show = true, .description = "*:warn allows warn" },
        .{ .pattern = "*:err", .tag = "app", .level = .err, .should_show = true, .description = "*:err allows err" },

        // Plus mode (level and above)
        .{ .pattern = "*:debug+", .tag = "app", .level = .debug, .should_show = true, .description = "*:debug+ allows debug" },
        .{ .pattern = "*:debug+", .tag = "app", .level = .info, .should_show = true, .description = "*:debug+ allows info" },
        .{ .pattern = "*:debug+", .tag = "app", .level = .warn, .should_show = true, .description = "*:debug+ allows warn" },
        .{ .pattern = "*:debug+", .tag = "app", .level = .err, .should_show = true, .description = "*:debug+ allows err" },

        .{ .pattern = "*:warn+", .tag = "app", .level = .debug, .should_show = false, .description = "*:warn+ excludes debug" },
        .{ .pattern = "*:warn+", .tag = "app", .level = .info, .should_show = false, .description = "*:warn+ excludes info" },
        .{ .pattern = "*:warn+", .tag = "app", .level = .warn, .should_show = true, .description = "*:warn+ allows warn" },
        .{ .pattern = "*:warn+", .tag = "app", .level = .err, .should_show = true, .description = "*:warn+ allows err" },

        // Minus mode (level and below)
        .{ .pattern = "*:warn-", .tag = "app", .level = .debug, .should_show = true, .description = "*:warn- allows debug" },
        .{ .pattern = "*:warn-", .tag = "app", .level = .info, .should_show = true, .description = "*:warn- allows info" },
        .{ .pattern = "*:warn-", .tag = "app", .level = .warn, .should_show = true, .description = "*:warn- allows warn" },
        .{ .pattern = "*:warn-", .tag = "app", .level = .err, .should_show = false, .description = "*:warn- excludes err" },

        // NOT mode (exclude exact level)
        .{ .pattern = "*:!debug", .tag = "app", .level = .debug, .should_show = false, .description = "*:!debug excludes debug" },
        .{ .pattern = "*:!debug", .tag = "app", .level = .info, .should_show = true, .description = "*:!debug allows info" },
        .{ .pattern = "*:!debug", .tag = "app", .level = .warn, .should_show = true, .description = "*:!debug allows warn" },
        .{ .pattern = "*:!debug", .tag = "app", .level = .err, .should_show = true, .description = "*:!debug allows err" },

        // NOT plus mode (exclude level and above)
        .{ .pattern = "*:!warn+", .tag = "app", .level = .debug, .should_show = true, .description = "*:!warn+ allows debug" },
        .{ .pattern = "*:!warn+", .tag = "app", .level = .info, .should_show = true, .description = "*:!warn+ allows info" },
        .{ .pattern = "*:!warn+", .tag = "app", .level = .warn, .should_show = false, .description = "*:!warn+ excludes warn" },
        .{ .pattern = "*:!warn+", .tag = "app", .level = .err, .should_show = false, .description = "*:!warn+ excludes err" },

        // NOT minus mode (exclude level and below)
        .{ .pattern = "*:!warn-", .tag = "app", .level = .debug, .should_show = false, .description = "*:!warn- excludes debug" },
        .{ .pattern = "*:!warn-", .tag = "app", .level = .info, .should_show = false, .description = "*:!warn- excludes info" },
        .{ .pattern = "*:!warn-", .tag = "app", .level = .warn, .should_show = false, .description = "*:!warn- excludes warn" },
        .{ .pattern = "*:!warn-", .tag = "app", .level = .err, .should_show = true, .description = "*:!warn- allows err" },
    };

    for (test_cases) |case| {
        var backend = logger.LogBackend{};
        if (parsePattern(&backend, case.pattern)) {
            const result = backend.shouldLogUnsafe(case.level, case.tag);
            if (result != case.should_show) {
                std.debug.print("FAIL: {s} - expected {}, got {}\n", .{ case.description, case.should_show, result });
                cleanupBackend(&backend);
                return error.TestFailed;
            } else {
                std.debug.print("PASS: {s}\n", .{case.description});
            }
        }
        cleanupBackend(&backend);
    }

    std.debug.print("Level filtering basic specs test completed\n", .{});
}

test "level filtering - tag specific overrides" {
    std.debug.print("Testing tag-specific level filtering overrides...\n", .{});

    const TestCase = struct {
        pattern: []const u8,
        tag: []const u8,
        level: logger.LogLevel,
        should_show: bool,
        description: []const u8,
    };

    const test_cases = [_]TestCase{
        // Global warn+ with database debug override
        .{ .pattern = "*:warn+,database:debug", .tag = "app", .level = .debug, .should_show = false, .description = "global warn+ excludes app debug" },
        .{ .pattern = "*:warn+,database:debug", .tag = "app", .level = .warn, .should_show = true, .description = "global warn+ allows app warn" },
        .{ .pattern = "*:warn+,database:debug", .tag = "database", .level = .debug, .should_show = true, .description = "database override allows debug" },
        .{ .pattern = "*:warn+,database:debug", .tag = "database", .level = .info, .should_show = false, .description = "database exact debug only" },

        // Multiple tag-specific patterns
        .{ .pattern = "*:err,app:info+,db:debug+", .tag = "app", .level = .info, .should_show = true, .description = "app gets info+" },
        .{ .pattern = "*:err,app:info+,db:debug+", .tag = "app", .level = .debug, .should_show = false, .description = "app excludes debug" },
        .{ .pattern = "*:err,app:info+,db:debug+", .tag = "db", .level = .debug, .should_show = true, .description = "db gets debug+" },
        .{ .pattern = "*:err,app:info+,db:debug+", .tag = "other", .level = .err, .should_show = true, .description = "other gets global err" },
        .{ .pattern = "*:err,app:info+,db:debug+", .tag = "other", .level = .warn, .should_show = false, .description = "other excludes warn" },

        // Tag wildcards with level specs
        .{ .pattern = "api*:debug+,web*:warn+", .tag = "api_server", .level = .debug, .should_show = true, .description = "api* gets debug+" },
        .{ .pattern = "api*:debug+,web*:warn+", .tag = "web_server", .level = .info, .should_show = false, .description = "web* excludes info" },
        .{ .pattern = "api*:debug+,web*:warn+", .tag = "web_server", .level = .warn, .should_show = true, .description = "web* allows warn" },
        .{ .pattern = "api*:debug+,web*:warn+", .tag = "db_server", .level = .debug, .should_show = false, .description = "unmatched tag gets nothing" },
    };

    for (test_cases) |case| {
        var backend = logger.LogBackend{};
        if (parsePattern(&backend, case.pattern)) {
            const result = backend.shouldLogUnsafe(case.level, case.tag);
            if (result != case.should_show) {
                std.debug.print("FAIL: {s} - expected {}, got {}\n", .{ case.description, case.should_show, result });
                cleanupBackend(&backend);
                return error.TestFailed;
            } else {
                std.debug.print("PASS: {s}\n", .{case.description});
            }
        }
        cleanupBackend(&backend);
    }

    std.debug.print("Tag-specific level filtering test completed\n", .{});
}

test "level filtering - complex patterns" {
    std.debug.print("Testing complex level filtering patterns...\n", .{});

    const TestCase = struct {
        pattern: []const u8,
        tag: []const u8,
        level: logger.LogLevel,
        should_show: bool,
        description: []const u8,
    };

    const test_cases = [_]TestCase{
        // Tag exclusion with level filtering
        .{ .pattern = "!network,*:info+", .tag = "app", .level = .debug, .should_show = false, .description = "global info+ excludes app debug" },
        .{ .pattern = "!network,*:info+", .tag = "app", .level = .info, .should_show = true, .description = "global info+ allows app info" },
        .{ .pattern = "!network,*:info+", .tag = "network", .level = .err, .should_show = false, .description = "network completely excluded" },

        // Multiple exclusions with overrides
        .{ .pattern = "!network,!test*,*:debug+,db:warn+", .tag = "app", .level = .debug, .should_show = true, .description = "app gets global debug+" },
        .{ .pattern = "!network,!test*,*:debug+,db:warn+", .tag = "db", .level = .info, .should_show = false, .description = "db override to warn+" },
        .{ .pattern = "!network,!test*,*:debug+,db:warn+", .tag = "db", .level = .warn, .should_show = true, .description = "db allows warn" },
        .{ .pattern = "!network,!test*,*:debug+,db:warn+", .tag = "testing", .should_show = false, .level = .err, .description = "test* excluded" },
        .{ .pattern = "!network,!test*,*:debug+,db:warn+", .tag = "network", .level = .err, .should_show = false, .description = "network excluded" },

        // Level exclusions with tag patterns
        .{ .pattern = "api*:!debug,web*:!warn+", .tag = "api_server", .level = .debug, .should_show = false, .description = "api* excludes debug" },
        .{ .pattern = "api*:!debug,web*:!warn+", .tag = "api_server", .level = .info, .should_show = true, .description = "api* allows info" },
        .{ .pattern = "api*:!debug,web*:!warn+", .tag = "web_server", .level = .info, .should_show = true, .description = "web* allows info" },
        .{ .pattern = "api*:!debug,web*:!warn+", .tag = "web_server", .level = .warn, .should_show = false, .description = "web* excludes warn+" },
        .{ .pattern = "api*:!debug,web*:!warn+", .tag = "web_server", .level = .err, .should_show = false, .description = "web* excludes err (warn+)" },

        // Pattern precedence (later patterns override earlier ones)
        .{ .pattern = "*:err,app:warn+,app:debug+", .tag = "app", .level = .debug, .should_show = true, .description = "last pattern wins (debug+)" },
        .{ .pattern = "*:debug+,app:err", .tag = "app", .level = .info, .should_show = false, .description = "app override to err only" },
        .{ .pattern = "*:debug+,app:err", .tag = "app", .level = .err, .should_show = true, .description = "app allows err" },
    };

    for (test_cases) |case| {
        var backend = logger.LogBackend{};
        if (parsePattern(&backend, case.pattern)) {
            const result = backend.shouldLogUnsafe(case.level, case.tag);
            if (result != case.should_show) {
                std.debug.print("FAIL: {s} - expected {}, got {}\n", .{ case.description, case.should_show, result });
                cleanupBackend(&backend);
                return error.TestFailed;
            } else {
                std.debug.print("PASS: {s}\n", .{case.description});
            }
        }
        cleanupBackend(&backend);
    }

    std.debug.print("Complex level filtering patterns test completed\n", .{});
}

test "level filtering - edge cases" {
    std.debug.print("Testing level filtering edge cases...\n", .{});

    const TestCase = struct {
        pattern: []const u8,
        tag: []const u8,
        level: logger.LogLevel,
        should_show: bool,
        description: []const u8,
    };

    const test_cases = [_]TestCase{
        // Empty and wildcard patterns
        .{ .pattern = "", .tag = "app", .level = .debug, .should_show = true, .description = "empty pattern allows all" },
        .{ .pattern = "*", .tag = "app", .level = .debug, .should_show = true, .description = "* wildcard allows all" },

        // Alternative level names (dbg vs debug, err vs error)
        .{ .pattern = "*:dbg", .tag = "app", .level = .debug, .should_show = true, .description = "dbg alias for debug" },
        .{ .pattern = "*:error", .tag = "app", .level = .err, .should_show = true, .description = "error alias for err" },

        // Mixed alias and standard names
        .{ .pattern = "*:dbg+", .tag = "app", .level = .info, .should_show = true, .description = "dbg+ includes info" },
        .{ .pattern = "*:!error", .tag = "app", .level = .err, .should_show = false, .description = "!error excludes err" },

        // No include patterns (everything allowed by default)
        .{ .pattern = "!test", .tag = "app", .level = .debug, .should_show = true, .description = "no includes = allow all except excluded" },
        .{ .pattern = "!test", .tag = "test", .level = .debug, .should_show = false, .description = "excluded tag blocked" },

        // Multiple exclusions
        .{ .pattern = "!test,!debug*,!*tmp", .tag = "app", .level = .debug, .should_show = true, .description = "multiple exclusions allow non-matching" },
        .{ .pattern = "!test,!debug*,!*tmp", .tag = "test", .level = .debug, .should_show = false, .description = "first exclusion works" },
        .{ .pattern = "!test,!debug*,!*tmp", .tag = "debug_server", .level = .debug, .should_show = false, .description = "second exclusion works" },
        .{ .pattern = "!test,!debug*,!*tmp", .tag = "app_tmp", .level = .debug, .should_show = false, .description = "third exclusion works" },
    };

    for (test_cases) |case| {
        var backend = logger.LogBackend{};
        if (parsePattern(&backend, case.pattern)) {
            const result = backend.shouldLogUnsafe(case.level, case.tag);
            if (result != case.should_show) {
                std.debug.print("FAIL: {s} - expected {}, got {}\n", .{ case.description, case.should_show, result });
                cleanupBackend(&backend);
                return error.TestFailed;
            } else {
                std.debug.print("PASS: {s}\n", .{case.description});
            }
        }
        cleanupBackend(&backend);
    }

    std.debug.print("Level filtering edge cases test completed\n", .{});
}

// Helper functions for level filtering tests
fn parsePattern(backend: *logger.LogBackend, pattern: []const u8) bool {
    if (pattern.len == 0) {
        backend.filter = std.BoundedArray(logger.FilterEntry, 16){};
        backend.filter_loaded = true;
        return true;
    }

    var list = std.BoundedArray(logger.FilterEntry, 16){};
    var it = std.mem.splitSequence(u8, pattern, ",");

    while (it.next()) |entry_str| {
        const trimmed = std.mem.trim(u8, entry_str, " \t");
        if (trimmed.len == 0) continue;

        if (parseFilterEntry(trimmed)) |filter_entry| {
            list.append(filter_entry) catch return false;
        }
    }

    backend.filter = list;
    backend.filter_loaded = true;
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

fn cleanupBackend(backend: *logger.LogBackend) void {
    if (backend.filter) |f| {
        for (f.slice()) |entry| {
            std.heap.page_allocator.free(entry.tag_pattern);
        }
    }
}

// Verify that the tag matching helper handles wildcard edge-cases correctly
// (prefix, suffix, contains, and degenerate patterns).
test "tag matching wildcard edge cases" {
    var backend = logger.LogBackend{};

    const cases = [_]struct {
        pattern: []const u8,
        tag: []const u8,
        expected: bool,
    }{
        .{ .pattern = "*sub*", .tag = "my_sub_tag", .expected = true }, // contains
        .{ .pattern = "*sub*", .tag = "mytag", .expected = false },
        .{ .pattern = "*suffix", .tag = "abc_suffix", .expected = true }, // ends with
        .{ .pattern = "*suffix", .tag = "suffix_abc", .expected = false },
        .{ .pattern = "prefix*", .tag = "prefix_abc", .expected = true }, // starts with
        .{ .pattern = "prefix*", .tag = "abc_prefix", .expected = false },
        .{ .pattern = "*", .tag = "anything", .expected = true }, // single star matches all
        .{ .pattern = "**", .tag = "anything", .expected = true }, // double star behaves the same
    };

    for (cases) |c| {
        const result = backend.tagMatches(c.tag, c.pattern);
        try std.testing.expectEqual(@as(bool, c.expected), result);
    }
}

// Ensure that attempts to push more than FILTER_CAP patterns into the
// internal BoundedArray do not crash and cap the length to FILTER_CAP.
test "filter capacity overflow" {
    var list = std.BoundedArray(logger.FilterEntry, logger.FILTER_CAP){};
    var i: usize = 0;
    while (i < logger.FILTER_CAP + 5) : (i += 1) {
        const entry = logger.FilterEntry{
            .tag_pattern = "tag", // slice literal – no allocation needed
            .exclude_tag = false,
        };
        // append may fail when capacity is exceeded – ignore error
        _ = list.append(entry) catch {};
    }
    try std.testing.expectEqual(logger.FILTER_CAP, list.len);
}

// Invalid level strings in the filter should be ignored, while valid ones
// continue to work.
test "invalid pattern parts are skipped" {
    var backend = logger.LogBackend{};

    // Construct env string with one bogus and one valid entry.
    const env_str = "*:bogus,*:info";

    // Manually parse using production helper to stay close to real path.
    var it = std.mem.splitSequence(u8, env_str, ",");
    var list = std.BoundedArray(logger.FilterEntry, logger.FILTER_CAP){};
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t");
        if (trimmed.len == 0) continue;
        if (parseFilterEntry(trimmed)) |fe| {
            list.append(fe) catch {};
        }
    }
    backend.filter = list;
    backend.filter_loaded = true;

    try std.testing.expectEqual(false, backend.shouldLogUnsafe(.debug, "app")); // debug blocked (no rule)
    try std.testing.expectEqual(true, backend.shouldLogUnsafe(.info, "app")); // info allowed by second rule
}

// Hexdump with non-default options should run without crashing and report the
// expected byte count (returned via stdout length can be approximated by
// capturing start/end indices but here we simply ensure call compiles).
test "hexdump option matrix" {
    if (builtin.mode != .Debug) return; // hexdump only active in debug builds
    const log = logger.new(.{ .tag = "hex_test" });
    const buf = "0123456789abcdefghijklmnopqrstuvwxyz";
    log.hexdump(buf, .{ .decimal_offset = true, .start = 8, .length = 24 });
}

test "logger instance new functionality" {
    std.debug.print("Testing logger instance new functionality...\n", .{});

    // Create a base logger
    const base_log = logger.new(.{
        .tag = "base",
        .color = .blue,
        .show_timestamp = true,
        .show_level = false,
    });

    // Test partial override - only change tag
    const log1 = base_log.new(.{
        .tag = "modified",
    });
    try std.testing.expectEqualStrings("modified", log1.tag());
    try std.testing.expectEqual(@as(?logger.LogColor, .blue), log1.config.color);
    try std.testing.expectEqual(true, log1.config.show_timestamp);
    try std.testing.expectEqual(false, log1.config.show_level);

    // Test multiple field override
    const log2 = base_log.new(.{
        .color = .red,
        .show_level = true,
    });
    try std.testing.expectEqualStrings("base", log2.tag());
    try std.testing.expectEqual(@as(?logger.LogColor, .red), log2.config.color);
    try std.testing.expectEqual(true, log2.config.show_timestamp);
    try std.testing.expectEqual(true, log2.config.show_level);

    // Test overriding boolean to false
    const log3 = base_log.new(.{
        .show_timestamp = false,
    });
    try std.testing.expectEqualStrings("base", log3.tag());
    try std.testing.expectEqual(@as(?logger.LogColor, .blue), log3.config.color);
    try std.testing.expectEqual(false, log3.config.show_timestamp);
    try std.testing.expectEqual(false, log3.config.show_level);

    // Test chaining withConfig calls
    const log4 = base_log.new(.{ .tag = "chain1" }).new(.{ .color = .green });
    try std.testing.expectEqualStrings("chain1", log4.tag());
    try std.testing.expectEqual(@as(?logger.LogColor, .green), log4.config.color);
    try std.testing.expectEqual(true, log4.config.show_timestamp);
    try std.testing.expectEqual(false, log4.config.show_level);

    // Test that the original logger is unchanged
    try std.testing.expectEqualStrings("base", base_log.tag());
    try std.testing.expectEqual(@as(?logger.LogColor, .blue), base_log.config.color);
    try std.testing.expectEqual(true, base_log.config.show_timestamp);
    try std.testing.expectEqual(false, base_log.config.show_level);

    std.debug.print("logger instance new functionality test completed\n", .{});
}

// Verify that `chain` concatenates tags while inheriting other fields.
test "chain functionality" {
    const base = logger.new(.{ .tag = "parent", .color = .yellow });
    const chained = base.chain(.{ .tag = "child" });

    try std.testing.expectEqualStrings("parent.child", chained.tag());
    try std.testing.expectEqual(@as(?logger.LogColor, .yellow), chained.config.color);
}

test "dump functionality" {
    std.debug.print("Testing dump functionality...\n", .{});
    
    const test_data = "Hello, World! This is test data for the dump function.";
    const filename = "test_dump.bin";
    
    // Create logger and dump data to file
    const log = logger.new(.{ .tag = "dump_test" });
    log.dump(filename, test_data);
    
    // Verify file exists and has correct size
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        std.debug.print("Failed to open dump file: {}\n", .{err});
        return err;
    };
    defer file.close();
    
    const file_size = file.getEndPos() catch |err| {
        std.debug.print("Failed to get file size: {}\n", .{err});
        return err;
    };
    
    try std.testing.expectEqual(@as(u64, test_data.len), file_size);
    
    // Read file contents and verify they match
    var buffer: [256]u8 = undefined;
    const bytes_read = file.readAll(buffer[0..]) catch |err| {
        std.debug.print("Failed to read file contents: {}\n", .{err});
        return err;
    };
    
    try std.testing.expectEqual(test_data.len, bytes_read);
    try std.testing.expectEqualStrings(test_data, buffer[0..bytes_read]);
    
    // Clean up - delete the test file
    std.fs.cwd().deleteFile(filename) catch |err| {
        std.debug.print("Failed to delete test file: {}\n", .{err});
        return err;
    };
    
    std.debug.print("Dump functionality test completed\n", .{});
}

test "block logger dump functionality" {
    std.debug.print("Testing block logger dump functionality...\n", .{});
    
    const test_data = "Block logger test data";
    const filename = "test_block_dump.bin";
    
    // Create logger with block and dump data to file
    const log = logger.new(.{ .tag = "block_test" });
    const block = log.block("test_block");
    block.dump(filename, test_data);
    
    // Verify file exists and has correct contents
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        std.debug.print("Failed to open block dump file: {}\n", .{err});
        return err;
    };
    defer file.close();
    
    var buffer: [64]u8 = undefined;
    const bytes_read = file.readAll(buffer[0..]) catch |err| {
        std.debug.print("Failed to read block dump file: {}\n", .{err});
        return err;
    };
    
    try std.testing.expectEqual(test_data.len, bytes_read);
    try std.testing.expectEqualStrings(test_data, buffer[0..bytes_read]);
    
    // Clean up
    std.fs.cwd().deleteFile(filename) catch |err| {
        std.debug.print("Failed to delete block test file: {}\n", .{err});
        return err;
    };
    
    std.debug.print("Block logger dump functionality test completed\n", .{});
}
