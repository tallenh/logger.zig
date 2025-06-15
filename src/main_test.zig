const std = @import("std");
const testing = std.testing;
const logger = @import("main.zig");

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
    const log = logger.new(.{ .tag = std.fmt.allocPrint(std.heap.page_allocator, "T{d}", .{thread_id}) catch "THREAD" });
    defer if (!std.mem.eql(u8, log.config.tag, "THREAD")) std.heap.page_allocator.free(log.config.tag);

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
