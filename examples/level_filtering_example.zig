const std = @import("std");
const logger = @import("logger");

pub fn main() !void {
    // Test basic level filtering
    std.debug.print("=== Level Filtering Example ===\n\n", .{});

    // Create different loggers for testing
    const app_logger = logger.new(.{ .tag = "app" });
    const db_logger = logger.new(.{ .tag = "database" });
    const auth_logger = logger.new(.{ .tag = "auth" });
    const network_logger = logger.new(.{ .tag = "network" });

    std.debug.print("Test 1: No filter (should show all in debug mode)\n", .{});
    app_logger.dbg("Debug message from app", .{});
    app_logger.info("Info message from app", .{});
    app_logger.warn("Warning from app", .{});
    app_logger.err("Error from app", .{});
    std.debug.print("\n", .{});

    // Set different filter patterns and test
    std.debug.print("Test 2: Set ZIGLOG=*:warn+ (global warn and above)\n", .{});
    std.debug.print("Expected: Only warn and err messages\n", .{});

    // Simulate setting environment variable by reloading filter
    // Note: In real usage, you'd set ZIGLOG=*:warn+ before running
    std.debug.print("(Simulated - you would set ZIGLOG=*:warn+ in environment)\n", .{});
    app_logger.dbg("This debug should be hidden", .{});
    app_logger.info("This info should be hidden", .{});
    app_logger.warn("This warning should show", .{});
    app_logger.err("This error should show", .{});
    std.debug.print("\n", .{});

    std.debug.print("Test 3: Mixed patterns: *:warn+,database:debug,auth:!debug\n", .{});
    std.debug.print("Expected: Global warn+, database shows debug, auth excludes debug\n", .{});
    std.debug.print("(Simulated - you would set ZIGLOG=*:warn+,database:debug,auth:!debug)\n", .{});

    app_logger.dbg("App debug - should be hidden (global warn+)", .{});
    app_logger.warn("App warning - should show", .{});

    db_logger.dbg("Database debug - should show (override to debug)", .{});
    db_logger.info("Database info - should show", .{});

    auth_logger.dbg("Auth debug - should be hidden (!debug)", .{});
    auth_logger.info("Auth info - should show", .{});
    auth_logger.warn("Auth warning - should show", .{});
    std.debug.print("\n", .{});

    std.debug.print("Test 4: Tag exclusion: !network,*:info+\n", .{});
    std.debug.print("Expected: Network completely excluded, others show info+\n", .{});
    std.debug.print("(Simulated - you would set ZIGLOG=!network,*:info+)\n", .{});

    app_logger.dbg("App debug - should be hidden (info+ filter)", .{});
    app_logger.info("App info - should show", .{});

    network_logger.dbg("Network debug - should be hidden (tag excluded)", .{});
    network_logger.err("Network error - should be hidden (tag excluded)", .{});
    std.debug.print("\n", .{});

    std.debug.print("=== Syntax Examples ===\n", .{});
    std.debug.print("ZIGLOG=*:warn                    - Global warn level only\n", .{});
    std.debug.print("ZIGLOG=*:warn+                   - Global warn and above\n", .{});
    std.debug.print("ZIGLOG=*:debug-                  - Global debug and below\n", .{});
    std.debug.print("ZIGLOG=*:!debug                  - Global exclude debug\n", .{});
    std.debug.print("ZIGLOG=*:!debug+                 - Global exclude debug and above\n", .{});
    std.debug.print("ZIGLOG=*:warn+,database:debug    - Global warn+, database debug exact\n", .{});
    std.debug.print("ZIGLOG=app:info+,network:!warn   - App info+, network exclude warn\n", .{});
    std.debug.print("ZIGLOG=!auth,*:debug+            - Exclude auth entirely, others debug+\n", .{});
    std.debug.print("ZIGLOG=!auth:debug               - Exclude auth (level ignored)\n", .{});
}
