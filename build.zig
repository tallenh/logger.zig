const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the logger module
    const logger_module = b.addModule("logger", .{
        .root_source_file = b.path("src/main.zig"),
    });

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

    // Level filtering example
    const level_filtering_example = b.addExecutable(.{
        .name = "level_filtering_example",
        .root_source_file = b.path("examples/level_filtering_example.zig"),
        .target = target,
        .optimize = optimize,
    });
    level_filtering_example.root_module.addImport("logger", logger_module);

    const run_level_filtering = b.addRunArtifact(level_filtering_example);
    if (b.args) |args| {
        run_level_filtering.addArgs(args);
    }

    const level_filtering_step = b.step("level-filtering", "Run level filtering example");
    level_filtering_step.dependOn(&run_level_filtering.step);

    // Verification example
    const verify_level_filtering = b.addExecutable(.{
        .name = "verify_level_filtering",
        .root_source_file = b.path("examples/verify_level_filtering.zig"),
        .target = target,
        .optimize = optimize,
    });
    verify_level_filtering.root_module.addImport("logger", logger_module);

    const run_verify = b.addRunArtifact(verify_level_filtering);
    if (b.args) |args| {
        run_verify.addArgs(args);
    }

    const verify_step = b.step("verify", "Verify level filtering implementation");
    verify_step.dependOn(&run_verify.step);

    // Thread safety test
    const thread_test = b.addExecutable(.{
        .name = "thread_test",
        .root_source_file = b.path("examples/thread_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    thread_test.root_module.addImport("logger", logger_module);

    const run_thread_test = b.addRunArtifact(thread_test);
    if (b.args) |args| {
        run_thread_test.addArgs(args);
    }

    const thread_test_step = b.step("thread-test", "Test thread safety");
    thread_test_step.dependOn(&run_thread_test.step);
}
