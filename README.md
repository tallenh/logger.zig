# Zig Logger

A flexible and feature-rich logging library for Zig projects.

## Features

- Multiple log levels (debug, info, warn, error)
- Optional log level display (disabled by default for cleaner output)
- Customizable colors for log output
- File logging support
- Timestamp support (per-logger and global)
- Tag-based filtering with wildcards and exclusions
- Block logging for grouping related logs
- Hexdump functionality
- Thread-safe logging

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
    .show_level = true,  // Show log levels (INFO, WARN, ERROR, DEBUG)
});

// Global settings
logger.setGlobalTimestamp(true);  // Enable timestamps for all loggers
logger.setGlobalLevel(true);      // Enable log levels for all loggers

// Block logging
const block = custom_log.block("MyBlock");
block.info("Inside block", .{});
block.close("Block completed");

// Hexdump
const data = "Hello, World!";
custom_log.hexdump(data, .{});
```

## Logger Configuration Merging

The `withConfig` method allows you to create a new logger by merging configurations. This is useful for creating specialized loggers that inherit most settings from a base logger while overriding specific fields:

```zig
// Create a base logger
const base_log = logger.new(.{
    .tag = "app",
    .color = .blue,
    .show_timestamp = true,
    .show_level = false,
});

// Create specialized loggers by merging configs
const db_log = base_log.withConfig(.{
    .tag = "database",  // Override tag
    .color = .green,    // Override color
    // show_timestamp and show_level inherit from base_log
});

const api_log = base_log.withConfig(.{
    .tag = "api",
    .show_level = true,  // Override to show levels
    // Other fields inherit from base_log
});

// Chain multiple withConfig calls
const debug_log = base_log
    .withConfig(.{ .tag = "debug" })
    .withConfig(.{ .color = .red })
    .withConfig(.{ .show_timestamp = false });

// Original logger remains unchanged
base_log.info("Base logger unchanged", .{});      // [1234567890] [app]: Base logger unchanged
db_log.info("Database operation", .{});          // [1234567890] [database]: Database operation
api_log.info("API request", .{});               // [1234567890] [api] INFO : API request
debug_log.info("Debug info", .{});              // [debug]: Debug info
```

The `withConfig` method uses a `LogOptionsPartial` struct where all fields are optional. Only the fields you specify will override the original configuration - unspecified fields keep their original values.

## Log Level Display

By default, log levels (INFO, WARN, ERROR, DEBUG) are **not** displayed in the output for cleaner logs. You can enable them per logger or globally:

```zig
// Default behavior - no levels shown
const log = logger.new(.{ .tag = "app" });
log.info("Starting application", .{});
// Output: [app]: Starting application

// Enable levels for individual logger
const debug_log = logger.new(.{ .tag = "debug", .show_level = true });
debug_log.info("Debug information", .{});
// Output: [debug] INFO : Debug information

// Enable levels globally for all loggers
logger.setGlobalLevel(true);
log.info("Now showing levels", .{});
// Output: [app] INFO : Now showing levels

// Combine with timestamps
const full_log = logger.new(.{
    .tag = "full",
    .show_timestamp = true,
    .show_level = true
});
full_log.warn("Warning message", .{});
// Output: [1234567890][full] WARN : Warning message
```

## Environment Variables

You can filter logs by tag using the `ZIGLOG` environment variable with support for wildcards and exclusions:

```bash
# Exact matches
ZIGLOG=database,network ./your-program

# Wildcard patterns
ZIGLOG=db*          # Match tags starting with "db" (db_connection, db_pool, etc.)
ZIGLOG=*test        # Match tags ending with "test" (unit_test, integration_test, etc.)
ZIGLOG=*net*        # Match tags containing "net" (network, ethernet, etc.)
ZIGLOG=api*,*test   # Multiple patterns (api_server, api_client, unit_test, etc.)
ZIGLOG=*            # Match all tags (show everything)

# Exclusion patterns (NOT operator)
ZIGLOG=!debug       # Exclude logs with tag "debug"
ZIGLOG=!*test*      # Exclude any tags containing "test"
ZIGLOG=!test*       # Exclude tags starting with "test"

# Combined include/exclude patterns
ZIGLOG=api*,!api_debug      # Include api* but exclude api_debug
ZIGLOG=*,!test*,!*debug     # Include everything except test* and *debug
ZIGLOG=web*,db*,!*test      # Include web* and db* but exclude anything with test
```

**Wildcard Examples:**

- `web*` → matches `web_server`, `web_client`, `web`
- `*db` → matches `mysql_db`, `redis_db`, `db`
- `*cache*` → matches `redis_cache`, `memory_cache`, `cache_manager`

**NOT Operator Examples:**

- `!debug` → excludes exactly `debug`
- `!*test*` → excludes `unit_test`, `api_test`, `test_helper`, etc.
- `api*,!api_debug` → includes `api_server`, `api_client` but excludes `api_debug`
- `*,!production` → includes everything except `production`

## License

MIT
