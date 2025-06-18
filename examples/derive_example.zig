const std = @import("std");
const logger = @import("logger");

/// Demonstrates how to derive new loggers from an existing one using
/// `Logger.new()` and how to build hierarchical tags with `Logger.chain()`.
pub fn main() !void {
    // Base logger
    const base = logger.new(.{
        .tag = "base",
        .color = .blue,
        .show_timestamp = true,
    });

    std.debug.print("=== Base Logger ===\n", .{});
    base.info("Base logger info", .{});

    // Override the tag (replace)
    const svc = base.new(.{ .tag = "service" });
    std.debug.print("\n=== Service Logger ===\n", .{});
    svc.warn("Service logger warning", .{});

    // Multiple overrides at once
    const api = base.new(.{ .tag = "api", .color = .green, .show_level = true });
    std.debug.print("\n=== API Logger ===\n", .{});
    api.err("API logger error", .{});

    // Build a chained tag: base.chained.depth
    const chained = base
        .chain(.{ .tag = "chained" })
        .chain(.{ .tag = "depth" });

    std.debug.print("\n=== Chained Logger ===\n", .{});
    chained.info("Chained logger info", .{});

    // Boolean override example
    const no_ts = base.new(.{ .show_timestamp = false });
    std.debug.print("\n=== No-timestamp Logger ===\n", .{});
    no_ts.info("No timestamp here", .{});
}
