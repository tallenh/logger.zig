const std = @import("std");
const logger = @import("logger");

pub fn main() !void {
    // Create loggers with different tags
    const api_log = logger.new(.{ .tag = "api_server" });
    const api_debug_log = logger.new(.{ .tag = "api_debug" });
    const db_log = logger.new(.{ .tag = "db_connection" });
    const test_log = logger.new(.{ .tag = "test_runner" });
    const prod_log = logger.new(.{ .tag = "production" });

    std.debug.print("=== NOT Operator Examples ===\n\n");

    std.debug.print("Try running this example with different ZIGLOG settings:\n\n");

    std.debug.print("ZIGLOG=!*debug*     # Exclude anything with 'debug'\n");
    std.debug.print("ZIGLOG=api*,!api_debug  # Include api* but exclude api_debug\n");
    std.debug.print("ZIGLOG=*,!test*,!production  # Include all except test* and production\n");
    std.debug.print("ZIGLOG=!production  # Exclude only production\n\n");

    // Generate some log messages
    api_log.info("API server starting up", .{});
    api_debug_log.debug("API debug information", .{});
    db_log.info("Database connection established", .{});
    test_log.info("Running unit tests", .{});
    prod_log.warn("Production environment detected", .{});

    std.debug.print("\nExample complete!\n");
}
