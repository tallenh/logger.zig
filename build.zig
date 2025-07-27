const std = @import("std");

/// Helper function for consuming projects to easily add Zig Logger with Objective-C support
pub fn addZigLoggerObjC(exe: *std.Build.Step.Compile, logger_dep: *std.Build.Dependency) void {
    // Add the Zig module
    exe.root_module.addImport("logger", logger_dep.module("logger"));
    
    // Link both libraries
    exe.linkLibrary(logger_dep.artifact("zig-logger"));
    exe.linkLibrary(logger_dep.artifact("zig-logger-objc"));
    
    // Add include path for headers
    exe.addIncludePath(logger_dep.path("objc_bridge"));
    
    // Add system frameworks
    exe.linkFramework("Foundation");
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the logger module
    const logger_module = b.addModule("logger", .{
        .root_source_file = b.path("src/main.zig"),
    });

    // Create a static library for C/Objective-C interop
    const lib = b.addStaticLibrary(.{
        .name = "zig-logger",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Install the library and headers for dependency use
    b.installArtifact(lib);
    
    // Install C header for Objective-C interop
    const install_header = b.addInstallFile(
        b.path("objc_bridge/zig_logger.h"),
        "include/zig_logger.h"
    );
    b.getInstallStep().dependOn(&install_header.step);
    
    // Install Objective-C wrapper files
    const install_objc_header = b.addInstallFile(
        b.path("objc_bridge/ZigLogger.h"),
        "include/ZigLogger.h"
    );
    const install_objc_impl = b.addInstallFile(
        b.path("objc_bridge/ZigLogger.m"),
        "src/ZigLogger.m"
    );
    b.getInstallStep().dependOn(&install_objc_header.step);
    b.getInstallStep().dependOn(&install_objc_impl.step);
    
    // Create an Objective-C static library that includes the wrapper
    const objc_lib = b.addStaticLibrary(.{
        .name = "zig-logger-objc",
        .target = target,
        .optimize = optimize,
    });
    
    // Add the Objective-C wrapper source to the library
    objc_lib.addCSourceFile(.{
        .file = b.path("objc_bridge/ZigLogger.m"),
        .flags = &.{
            "-fobjc-arc",
            "-I", "objc_bridge",
        },
    });
    
    // Link with the main Zig library
    objc_lib.linkLibrary(lib);
    
    // Add system frameworks
    objc_lib.linkFramework("Foundation");
    
    // Install the Objective-C library
    b.installArtifact(objc_lib);

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

    // Derive example (demonstrates Logger.new and Logger.chain)
    const derive_example = b.addExecutable(.{
        .name = "derive_example",
        .root_source_file = b.path("examples/derive_example.zig"),
        .target = target,
        .optimize = optimize,
    });
    derive_example.root_module.addImport("logger", logger_module);

    const run_derive = b.addRunArtifact(derive_example);
    if (b.args) |args| {
        run_derive.addArgs(args);
    }

    const derive_step = b.step("derive", "Run derive example");
    derive_step.dependOn(&run_derive.step);
}
