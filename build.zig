const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the logger module
    const logger_module = b.addModule("logger", .{
        .root_source_file = b.path("src/main.zig"),
    });
    _ = logger_module; // Mark as used

    // Create a test step
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/main_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    // Configure the test runner to show output
    if (b.args) |args| {
        run_main_tests.addArgs(args);
    }

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
