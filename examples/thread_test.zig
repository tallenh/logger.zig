const std = @import("std");
const logger = @import("logger");

fn workerThread(thread_id: u32) void {
    const log = logger.new(.{ .tag = "thread" });

    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        log.info("Thread {d} message {d}", .{ thread_id, i });
        log.warn("Thread {d} warning {d}", .{ thread_id, i });

        // Small delay to increase chance of race conditions
        std.time.sleep(1000); // 1μs
    }
}

pub fn main() !void {
    std.debug.print("=== Thread Safety Test ===\n", .{});

    const num_threads = 4;
    var threads: [num_threads]std.Thread = undefined;

    std.debug.print("Spawning {} threads...\n", .{num_threads});

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, workerThread, .{@as(u32, @intCast(i))}) catch |err| {
            std.debug.print("Failed to spawn thread {}: {}\n", .{ i, err });
            return;
        };
    }

    std.debug.print("Waiting for threads to complete...\n", .{});

    for (threads) |thread| {
        thread.join();
    }

    std.debug.print("✅ Thread safety test completed successfully!\n", .{});
}
