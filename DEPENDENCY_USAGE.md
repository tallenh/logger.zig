# Using Zig Logger as a Dependency in Zig+Objective-C Projects

This guide explains how to use the Zig Logger library as a dependency in other Zig projects that also use Objective-C code.

## Quick Start

### 1. Add as Zig Dependency

In your project's `build.zig.zon`:

```zig
.{
    .name = "your-project",
    .version = "0.1.0",
    .dependencies = .{
        .logger = .{
            .url = "https://github.com/your-username/zig-logger/archive/main.tar.gz",
            .hash = "1234567890abcdef...", // Use `zig fetch` to get the hash
        },
    },
}
```

### 2. Configure Your build.zig (Easy Method)

```zig
const std = @import("std");
const logger = @import("logger"); // Import the logger build functions

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Import the logger dependency
    const logger_dep = b.dependency("logger", .{
        .target = target,
        .optimize = optimize,
    });

    // Your Zig executable/library
    const exe = b.addExecutable(.{
        .name = "your-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // ✨ ONE-LINE SETUP: Automatically adds Zig module + Objective-C bridge
    logger.addZigLoggerObjC(exe, logger_dep);
    
    // Add your own Objective-C files if needed
    exe.addCSourceFiles(.{
        .files = &.{
            "src/YourObjCFile.m",
        },
        .flags = &.{
            "-fobjc-arc",
        },
    });
    
    b.installArtifact(exe);
}
```

### 2b. Manual Configuration (Alternative)

If you prefer manual control:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Import the logger dependency
    const logger_dep = b.dependency("logger", .{
        .target = target,
        .optimize = optimize,
    });

    // Your Zig executable/library
    const exe = b.addExecutable(.{
        .name = "your-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add Zig module
    exe.root_module.addImport("logger", logger_dep.module("logger"));
    
    // Link both Zig and Objective-C libraries
    exe.linkLibrary(logger_dep.artifact("zig-logger"));
    exe.linkLibrary(logger_dep.artifact("zig-logger-objc"));
    
    // Add include path for headers
    exe.addIncludePath(logger_dep.path("objc_bridge"));
    
    // Add system frameworks
    exe.linkFramework("Foundation");
    
    // Add your own Objective-C files
    exe.addCSourceFiles(.{
        .files = &.{
            "src/YourObjCFile.m",
        },
        .flags = &.{
            "-fobjc-arc",
        },
    });
    
    b.installArtifact(exe);
}
```

### 3. That's It! 🎉

No manual file copying required! The Objective-C bridge is automatically available.

## Usage Examples

### In Zig Code

```zig
const std = @import("std");
const logger = @import("logger");

pub fn main() void {
    var log = logger.Logger.init(.{ .tag = "MyApp" });
    log.info("Hello from Zig!");
    log.warn("This is a warning");
}
```

### In Objective-C Code

```objc
#import "ZigLogger.h"

@implementation MyClass

- (void)doSomething {
    ZigLogger *log = [ZigLogger loggerWithTag:@"MyClass"];
    [log info:@"Hello from Objective-C!"];
    [log warn:@"This is a warning"];
}

@end
```

## Advanced Configuration

### Custom Build Options

You can pass build options to the logger dependency:

```zig
const logger_dep = b.dependency("logger", .{
    .target = target,
    .optimize = optimize,
    // Add any custom options here if the logger supports them
});
```

### Multiple Targets

For projects with multiple targets (iOS, macOS, etc.):

```zig
// Configure for each target
const targets = [_]std.Target.Query{
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .ios },
};

for (targets) |t| {
    const exe = b.addExecutable(.{
        .name = b.fmt("your-app-{s}-{s}", .{ @tagName(t.cpu_arch.?), @tagName(t.os_tag.?) }),
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(t),
        .optimize = optimize,
    });
    
    // Add logger dependency for each target
    const logger_dep = b.dependency("logger", .{
        .target = b.resolveTargetQuery(t),
        .optimize = optimize,
    });
    
    exe.root_module.addImport("logger", logger_dep.module("logger"));
    exe.linkLibrary(logger_dep.artifact("zig-logger"));
    
    b.installArtifact(exe);
}
```

## Troubleshooting

### Common Issues

1. **Missing Headers**: Ensure you've copied the header files to your include path
2. **Linking Errors**: Make sure you're linking the static library with `exe.linkLibrary(logger_lib)`
3. **ARC Issues**: Use `-fobjc-arc` flag when compiling Objective-C files
4. **Framework Dependencies**: Include `-framework Foundation` for Objective-C compilation

### Key Benefits

- **Zero Configuration**: Headers and libraries are automatically linked
- **No Manual Steps**: The Objective-C bridge is seamlessly integrated
- **Cross-Platform**: Works on macOS, iOS, and other Apple platforms
- **Performance**: Static linking with no runtime dependencies
- **Clean API**: Both Zig and Objective-C APIs feel natural
- **Thread-Safe**: Maintains all the original logger's safety guarantees

## Environment Variables

The logger respects the `ZIGLOG` environment variable for filtering:

```bash
# Show only error messages
export ZIGLOG="error"

# Show info and above for specific tags
export ZIGLOG="MyClass:info+"

# Multiple filters
export ZIGLOG="Network:debug+,Database:warn+"
```

This setup provides a clean, maintainable way to use the Zig Logger in mixed Zig+Objective-C projects while preserving all the logger's functionality and performance characteristics.
