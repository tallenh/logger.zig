# Zig Logger

A flexible and feature-rich logging library for Zig projects.

## Features

- Multiple log levels (debug, info, warn, error)
- Customizable colors for log output
- File logging support
- Timestamp support
- Tag-based filtering
- Block logging for grouping related logs
- Hexdump functionality

## Installation

Add this to your `build.zig.zon`:

```zig
.{
    .name = "your-project",
    .version = "0.1.0",
    .dependencies = .{
        .logger = .{
            .url = "https://github.com/tallenh/logger/archive/refs/tags/v0.1.0.tar.gz",
            .hash = "12345...", // You'll get this from zig fetch
        },
    },
}
```

Then in your `build.zig`:

```zig
const logger = b.dependency("logger", .{
    .target = target,
    .optimize = optimize,
});

// Add the module to your executable or library
exe.addModule("logger", logger.module("logger"));
```

## Usage

```zig
const logger = @import("logger");

// Create a new logger with default options
const log = logger.new(.{});

// Basic logging
log.info("Hello, world!", .{});
log.warn("This is a warning", .{});
log.err("This is an error", .{});

// Create a logger with custom options
const custom_log = logger.new(.{
    .tag = "custom",
    .color = .blue,
    .show_timestamp = true,
});

// Block logging
const block = custom_log.block("MyBlock");
block.info("Inside block", .{});
block.close("Block completed");

// Hexdump
const data = "Hello, World!";
custom_log.hexdump(data, .{});
```

## Environment Variables

You can filter logs by tag using the `ZIGLOG` environment variable:

```bash
ZIGLOG=tag1,tag2 ./your-program
```

## License

MIT
