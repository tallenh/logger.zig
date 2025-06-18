# Zig Logger

A flexible and feature-rich logging library for Zig projects.

## Features

- Multiple log levels (debug, info, warn, error)
- Optional log level display (disabled by default for cleaner output)
- Customizable colors for log output
- File logging support
- Timestamp support (per-logger and global)
- Advanced tag-based filtering with wildcards, exclusions, and level filters
- Block logging for grouping related logs
- Hexdump functionality
- Thread-safe logging
- Compile-time optimizations for release builds

## Installation

Add this to your `build.zig.zon`:

```zig
.{
    .name = "your-project",
    .version = "0.1.0",
    .dependencies = .{
        .logger = .{
            .url = "https://github.com/tallenh/logger/archive/refs/tags/0.4.1.tar.gz",
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
log.dbg("Debug message", .{});

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
logger.setLogFile(file);          // Set global log file for all loggers

// Block logging
const block = custom_log.block("MyBlock");
block.info("Inside block", .{});
block.close("Block completed");

// Hexdump
const data = "Hello, World!";
custom_log.hexdump(data, .{
    .decimal_offset = false,
    .length = null,  // dump entire buffer
    .start = 0,
});
```

## Logger Configuration and Inheritance

The logger provides two methods for creating new loggers from existing ones:

### `new()` - Override Configuration

The `new()` method creates a logger with a completely new configuration, where any provided options override the defaults:

```zig
// Create a base logger
const base_log = logger.new(.{
    .tag = "app",
    .color = .blue,
    .show_timestamp = true,
    .show_level = false,
});

// Create a new logger with different options
const db_log = base_log.new(.{
    .tag = "database",  // Replaces "app" completely
    .color = .green,    // Override color
    .show_level = true, // Override level display
    // show_timestamp inherits from base_log
});

// Create another logger with minimal overrides
const api_log = base_log.new(.{
    .tag = "api",       // New tag replaces parent tag
    // All other settings inherit from base_log
});
```

### `chain()` - Hierarchical Tag Composition

The `chain()` method creates a logger that appends to the existing tag with a dot separator, perfect for creating hierarchical loggers:

```zig
// Create a base logger
const app_log = logger.new(.{ .tag = "app" });

// Chain creates hierarchical tags
const db_log = app_log.chain(.{ .tag = "database" });  // tag becomes "app.database"
const user_log = db_log.chain(.{ .tag = "users" });    // tag becomes "app.database.users"

// Chain with other config changes
const debug_user_log = user_log.chain(.{
    .tag = "debug",
    .color = .red,
    .show_level = true,
});  // tag becomes "app.database.users.debug"

// Usage
app_log.info("Application started", .{});              // [app]: Application started
db_log.info("Database connected", .{});               // [app.database]: Database connected
user_log.info("User created", .{});                   // [app.database.users]: User created
debug_user_log.dbg("Debug user operation", .{});      // [app.database.users.debug] DEBUG: Debug user operation
```

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
// Output: [1234567890] [full] WARN : Warning message
```

## Environment Variables

You can filter logs using the `ZIGLOG` environment variable with support for tag patterns, level filtering, and exclusions:

### Basic Tag Filtering

```bash
# Exact matches
ZIGLOG=database,network ./your-program

# Wildcard patterns
ZIGLOG=db*          # Match tags starting with "db"
ZIGLOG=*test        # Match tags ending with "test"
ZIGLOG=*net*        # Match tags containing "net"
ZIGLOG=api*,*test   # Multiple patterns
ZIGLOG=*            # Match all tags

# Exclusion patterns
ZIGLOG=!debug       # Exclude logs with tag "debug"
ZIGLOG=!*test*      # Exclude any tags containing "test"
ZIGLOG=api*,!api_debug  # Include api* but exclude api_debug
```

### Level Filtering

Add level specifications to control which log levels are shown:

```bash
# Show only specific levels
ZIGLOG=app:info         # Show only info level for "app" tag
ZIGLOG=db:warn          # Show only warn level for "db" tag
ZIGLOG=*:err            # Show only error level for all tags

# Level ranges
ZIGLOG=app:info+        # Show info level and above (info, warn, err)
ZIGLOG=debug:warn-      # Show warn level and below (debug, info, warn)

# Exclude levels
ZIGLOG=app:!debug       # Show all levels except debug
ZIGLOG=*:!debug+        # Exclude debug and above (only show nothing, since debug is lowest)
ZIGLOG=*:!err-          # Exclude err and below (show nothing, since err is highest)

# Complex combinations
ZIGLOG=api*:info+,db*:warn+,!*test*:debug
# - api* tags: show info and above
# - db* tags: show warn and above
# - exclude any *test* tags at debug level
```

### Level Filter Examples

```zig
// In your code
const app_log = logger.new(.{ .tag = "app" });
const db_log = logger.new(.{ .tag = "database" });
const test_log = logger.new(.{ .tag = "test_runner" });

app_log.dbg("Debug message", .{});     // Filtered by ZIGLOG=app:info+
app_log.info("Info message", .{});     // Shown by ZIGLOG=app:info+
app_log.warn("Warning", .{});          // Shown by ZIGLOG=app:info+
app_log.err("Error", .{});             // Shown by ZIGLOG=app:info+

db_log.info("DB connected", .{});      // Filtered by ZIGLOG=db*:warn+
db_log.warn("DB slow query", .{});     // Shown by ZIGLOG=db*:warn+

test_log.info("Test started", .{});    // Filtered by ZIGLOG=!*test*
```

### Available Log Levels

- `debug` or `dbg` - Lowest priority
- `info` - Informational messages
- `warn` - Warnings
- `err` or `error` - Highest priority

### Level Filter Modes

- `:level` - Exact level match
- `:level+` - Level and above (higher priority)
- `:level-` - Level and below (lower priority)
- `:!level` - Exclude exact level
- `:!level+` - Exclude level and above
- `:!level-` - Exclude level and below

## Compile-time Optimizations

The logger automatically optimizes for release builds:

- In `Debug` mode: All logging and filtering is active
- In `ReleaseSafe`/`ReleaseFast` mode: Only error logs are compiled in, all other logs are removed at compile time for zero runtime cost

## Reloading Filters

You can reload the `ZIGLOG` environment variable at runtime:

```zig
// Reload the filter from the current ZIGLOG environment variable
logger.reloadLogFilter();
```

## License

MIT
