const std = @import("std");
const builtin = @import("builtin");

/// Maximum number of filter patterns that can be parsed from the `ZIGLOG`
/// environment variable.  Modify this value at compile-time to increase the
/// capacity without touching the core implementation.
pub const FILTER_CAP: usize = 16;

/// Maximum length (in bytes) of a logger tag that can be stored directly in a
/// `Logger` instance without any heap allocation.  Longer tags will cause a
/// runtime assertion failure when constructing the logger.
pub const MAX_TAG_LEN: usize = 128;

pub const LogLevel = enum(u8) {
    debug = 0,
    info = 1,
    warn = 2,
    err = 3,

    // Compile-time level comparison optimization
    pub fn cmp(self: LogLevel, other: LogLevel) std.math.Order {
        return std.math.order(@intFromEnum(self), @intFromEnum(other));
    }
};

pub const LogColor = enum {
    red,
    blue,
    green,
    orange,
    yellow,
    purple,
    pink,
    cyan,
    magenta,
};

// New types for the enhanced filtering system
pub const LevelFilterMode = enum {
    exact, // :level
    plus, // :level+
    minus, // :level-
    not_exact, // :!level
    not_plus, // :!level+
    not_minus, // :!level-
};

pub const LevelSpec = struct {
    level: LogLevel,
    mode: LevelFilterMode,
};

pub const FilterEntry = struct {
    tag_pattern: []const u8,
    level_spec: ?LevelSpec = null,
    exclude_tag: bool = false, // true for !tag patterns
};

pub const LogOptions = struct {
    tag: []const u8 = "default",
    color: ?LogColor = null,
    file: ?std.fs.File = null,
    show_timestamp: bool = false,
    show_level: bool = false,
};

pub const LogOptionsPartial = struct {
    tag: ?[]const u8 = null,
    color: ?LogColor = null,
    file: ?std.fs.File = null,
    show_timestamp: ?bool = null,
    show_level: ?bool = null,
};

// Compile-time optimization: in release mode, skip all filtering except err level
inline fn shouldCompileLog(comptime level: LogLevel) bool {
    return switch (builtin.mode) {
        .Debug => true,
        else => level == .err,
    };
}

// Centralized logging backend - handles all I/O and synchronization
pub const LogBackend = struct {
    mutex: std.Thread.Mutex = .{},
    file: ?std.fs.File = null,
    show_global_timestamp: bool = false,
    show_global_level: bool = false,
    filter: ?std.BoundedArray(FilterEntry, FILTER_CAP) = null,
    env_buf: ?[]u8 = null, // holds the raw ZIGLOG string for pattern slices
    filter_loaded: bool = false,

    fn ensureFilterLoaded(self: *LogBackend) void {
        // Fast path: check if already loaded without lock
        if (self.filter_loaded) return;

        // Slow path: double-checked locking pattern for thread safety
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check again after acquiring lock
        if (self.filter_loaded) return;

        self.reloadFilterUnsafe();
        self.filter_loaded = true;
    }

    pub fn reloadFilter(self: *LogBackend) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.reloadFilterUnsafe();
        self.filter_loaded = true;
    }

    fn reloadFilterUnsafe(self: *LogBackend) void {
        // Free previous environment buffer (also releases tag_pattern slices)
        if (self.env_buf) |buf| {
            std.heap.page_allocator.free(buf);
            self.env_buf = null;
        }
        // Reset filter
        self.filter = null;

        // In release mode, skip environment parsing for non-err levels
        if (builtin.mode != .Debug) {
            self.filter = std.BoundedArray(FilterEntry, FILTER_CAP){};
            return;
        }

        const env = std.process.getEnvVarOwned(std.heap.page_allocator, "ZIGLOG") catch {
            self.filter = std.BoundedArray(FilterEntry, FILTER_CAP){};
            return;
        };
        // Keep env alive for the lifetime of the filter
        self.env_buf = env;

        var list = std.BoundedArray(FilterEntry, FILTER_CAP){};
        var it = std.mem.splitSequence(u8, env, ",");
        while (it.next()) |entry_str| {
            const trimmed = std.mem.trim(u8, entry_str, " \t");
            if (trimmed.len == 0) continue;

            if (parseFilterEntry(trimmed)) |filter_entry| {
                list.append(filter_entry) catch {};
            }
        }
        self.filter = list;
    }

    fn parseFilterEntry(entry_str: []const u8) ?FilterEntry {
        var tag_pattern: []const u8 = "";
        var level_spec: ?LevelSpec = null;
        var exclude_tag = false;

        // Handle tag exclusion (!tag or !tag:level)
        var working_str = entry_str;
        if (std.mem.startsWith(u8, entry_str, "!")) {
            exclude_tag = true;
            working_str = entry_str[1..];
        }

        // Split on ':' to separate tag and level parts
        if (std.mem.indexOf(u8, working_str, ":")) |colon_idx| {
            const tag_part = working_str[0..colon_idx];
            const level_part = working_str[colon_idx + 1 ..];

            // If excluding entire tag, ignore level part
            tag_pattern = tag_part;
            if (!exclude_tag) {
                level_spec = parseLevelSpec(level_part);
            }
        } else {
            // No colon, just tag pattern
            tag_pattern = working_str;
        }

        return FilterEntry{
            .tag_pattern = tag_pattern,
            .level_spec = level_spec,
            .exclude_tag = exclude_tag,
        };
    }

    fn parseLevelSpec(level_str: []const u8) ?LevelSpec {
        if (level_str.len == 0) return null;

        var mode: LevelFilterMode = .exact;
        var level_name: []const u8 = level_str;

        // Handle negation (!level, !level+, !level-)
        if (std.mem.startsWith(u8, level_str, "!")) {
            level_name = level_str[1..];
            if (std.mem.endsWith(u8, level_name, "+")) {
                mode = .not_plus;
                level_name = level_name[0 .. level_name.len - 1];
            } else if (std.mem.endsWith(u8, level_name, "-")) {
                mode = .not_minus;
                level_name = level_name[0 .. level_name.len - 1];
            } else {
                mode = .not_exact;
            }
        } else {
            // Handle positive modes (level, level+, level-)
            if (std.mem.endsWith(u8, level_name, "+")) {
                mode = .plus;
                level_name = level_name[0 .. level_name.len - 1];
            } else if (std.mem.endsWith(u8, level_name, "-")) {
                mode = .minus;
                level_name = level_name[0 .. level_name.len - 1];
            }
        }

        // Parse level name
        const level = parseLogLevel(level_name) orelse return null;

        return LevelSpec{
            .level = level,
            .mode = mode,
        };
    }

    fn parseLogLevel(level_name: []const u8) ?LogLevel {
        if (std.mem.eql(u8, level_name, "debug") or std.mem.eql(u8, level_name, "dbg")) {
            return .debug;
        } else if (std.mem.eql(u8, level_name, "info")) {
            return .info;
        } else if (std.mem.eql(u8, level_name, "warn")) {
            return .warn;
        } else if (std.mem.eql(u8, level_name, "err") or std.mem.eql(u8, level_name, "error")) {
            return .err;
        }
        return null;
    }

    pub fn shouldLog(self: *LogBackend, level: LogLevel, tag: []const u8) bool {
        // Fast compile-time filter: skip everything except err in Release/Safe modes.
        if (builtin.mode != .Debug and level != .err) return false;

        // Make sure the filter is ready (lazily initialised).
        self.ensureFilterLoaded();

        return self.shouldLogInternal(level, tag);
    }

    // Internal helper that contains the actual filtering algorithm. The caller must
    // guarantee that `ensureFilterLoaded()` has already been executed.  It makes no
    // attempt to acquire the mutex and is therefore safe to use from both locked
    // and lock-free contexts.
    fn shouldLogInternal(self: *LogBackend, level: LogLevel, tag: []const u8) bool {
        // If there is no filter configured, everything is allowed (respecting
        // compile-time optimisation already checked by the caller).
        if (self.filter) |f| {
            if (f.len == 0) return true;

            var has_includes = false;
            var included = false;
            var level_allowed = true;
            var active_level_spec: ?LevelSpec = null;

            // Pass 1: includes (entries without the exclude flag). Later rules win.
            for (f.slice()) |entry| {
                if (!entry.exclude_tag) {
                    has_includes = true;
                    if (self.tagMatches(tag, entry.tag_pattern)) {
                        included = true;
                        if (entry.level_spec) |spec| {
                            active_level_spec = spec;
                        } else {
                            active_level_spec = null;
                        }
                    }
                }
            }

            if (!has_includes) {
                included = true;
            }

            if (active_level_spec) |spec| {
                level_allowed = self.levelMatches(level, spec);
            }

            // Pass 2: explicit excludes.
            if (included) {
                for (f.slice()) |entry| {
                    if (entry.exclude_tag) {
                        if (self.tagMatches(tag, entry.tag_pattern)) {
                            return false;
                        }
                    }
                }
            }

            return included and level_allowed;
        }

        return true;
    }

    fn levelMatches(self: *LogBackend, level: LogLevel, spec: LevelSpec) bool {
        _ = self; // Mark as used

        // Optimized level comparison using enum ordering
        return switch (spec.mode) {
            .exact => level == spec.level,
            .plus => level.cmp(spec.level) != .lt,
            .minus => level.cmp(spec.level) != .gt,
            .not_exact => level != spec.level,
            .not_plus => level.cmp(spec.level) == .lt,
            .not_minus => level.cmp(spec.level) == .gt,
        };
    }

    pub fn tagMatches(self: *LogBackend, tag: []const u8, pattern: []const u8) bool {
        _ = self; // Mark as used

        // Exact match (no wildcards) - most common case
        if (std.mem.indexOf(u8, pattern, "*") == null) {
            return std.mem.eql(u8, pattern, tag);
        }

        // Handle wildcard patterns
        if (std.mem.startsWith(u8, pattern, "*") and std.mem.endsWith(u8, pattern, "*")) {
            // *substring* - contains match
            if (pattern.len <= 2) return true; // Just "*" or "**" matches everything
            const substring = pattern[1 .. pattern.len - 1];
            return std.mem.indexOf(u8, tag, substring) != null;
        } else if (std.mem.startsWith(u8, pattern, "*")) {
            // *suffix - ends with match
            const suffix = pattern[1..];
            return std.mem.endsWith(u8, tag, suffix);
        } else if (std.mem.endsWith(u8, pattern, "*")) {
            // prefix* - starts with match
            const prefix = pattern[0 .. pattern.len - 1];
            return std.mem.startsWith(u8, tag, prefix);
        }

        // Fallback to exact match if pattern is malformed
        return std.mem.eql(u8, pattern, tag);
    }

    fn writeLog(self: *LogBackend, level: LogLevel, tag: []const u8, color: ?LogColor, show_timestamp: bool, show_level: bool, message: []const u8) void {
        // First, perform the inexpensive filtering without taking the mutex.
        if (!self.shouldLog(level, tag)) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        // Re-check now that the lock is held to protect against race conditions
        // (e.g., another thread could have reloaded the filter in between).
        if (!self.shouldLogInternal(level, tag)) return;

        const actual_color = if (color) |c| colorCode(c) else levelToColor(level);
        const label = levelToLabel(level);
        const reset = "\x1b[0m";

        var out = if (builtin.is_test) blk: {
            break :blk std.io.getStdErr().writer();
        } else switch (level) {
            .err => if (builtin.mode == .Debug) std.io.getStdOut().writer() else std.io.getStdErr().writer(),
            else => std.io.getStdOut().writer(),
        };

        const show_ts = show_timestamp or self.show_global_timestamp;
        const ts_prefix: []u8 = if (show_ts) blk: {
            var buf: [32]u8 = undefined;
            const now = std.time.timestamp();
            const slice = std.fmt.bufPrint(buf[0..], "[{d}] ", .{now}) catch break :blk ""[0..0];
            break :blk slice;
        } else ""[0..0];

        const show_lvl = show_level or self.show_global_level;
        if (show_lvl) {
            out.print("{s}{s}[{s}] {s}: {s}{s}\n", .{ ts_prefix, actual_color, tag, label, message, reset }) catch {};
            if (self.file) |file| {
                file.writer().print("{s}[{s}] {s}: {s}\n", .{ ts_prefix, tag, label, message }) catch {};
            }
        } else {
            out.print("{s}{s}[{s}]: {s}{s}\n", .{ ts_prefix, actual_color, tag, message, reset }) catch {};
            if (self.file) |file| {
                file.writer().print("{s}[{s}]: {s}\n", .{ ts_prefix, tag, message }) catch {};
            }
        }
    }

    fn writeHexdump(self: *LogBackend, tag: []const u8, color: ?LogColor, buf: []const u8, opts: HexdumpOptions) void {
        // Hexdump only meaningful in debug builds; in Release/Safe we exit quickly.
        if (builtin.mode != .Debug) return;

        // Fast filter check without locking.
        if (!self.shouldLog(.debug, tag)) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        // Re-check now that the lock is held to protect against race conditions
        // (e.g., another thread could have reloaded the filter in between).
        if (!self.shouldLogInternal(.debug, tag)) return;

        const actual_color = if (color) |c| colorCode(c) else levelToColor(.debug);
        const reset = "\x1b[0m";
        const label = "DEBUG";

        var out = if (builtin.is_test) blk: {
            break :blk std.io.getStdErr().writer();
        } else std.io.getStdOut().writer();

        const start = opts.start;
        if (start >= buf.len) return;
        const bytes_available = buf.len - start;
        const bytes_to_dump = if (opts.length) |len| @min(bytes_available, len) else bytes_available;

        out.print("{s}[{s}] {s}: hexdump buffer length = {}{s}\n", .{
            actual_color, tag, label, bytes_to_dump, reset,
        }) catch {};

        if (self.file) |file| {
            file.writer().print("[{s}] {s}: hexdump buffer length = {}\n", .{
                tag, label, bytes_to_dump,
            }) catch {};
        }

        var offset: usize = 0;
        while (offset < bytes_to_dump) : (offset += 16) {
            const abs_offset = start + offset;
            var hex_line: [80]u8 = undefined;
            var ascii_line: [17]u8 = undefined;
            var hex_i: usize = 0;
            var ascii_i: usize = 0;

            if (opts.decimal_offset) {
                const slice = std.fmt.bufPrint(hex_line[hex_i..], "{d:0>8}  ", .{abs_offset}) catch continue;
                hex_i += slice.len;
            } else {
                const slice = std.fmt.bufPrint(hex_line[hex_i..], "{x:0>8}  ", .{abs_offset}) catch continue;
                hex_i += slice.len;
            }

            var i: usize = 0;
            while (i < 16) : (i += 1) {
                if (offset + i < bytes_to_dump) {
                    const slice = std.fmt.bufPrint(hex_line[hex_i..], "{x:0>2} ", .{buf[start + offset + i]}) catch continue;
                    hex_i += slice.len;
                    const c = buf[start + offset + i];
                    ascii_line[ascii_i] = if (c >= 0x20 and c <= 0x7e) c else '.';
                } else {
                    const slice = std.fmt.bufPrint(hex_line[hex_i..], "   ", .{}) catch continue;
                    hex_i += slice.len;
                    ascii_line[ascii_i] = ' ';
                }
                ascii_i += 1;
                if (i == 7) {
                    const slice = std.fmt.bufPrint(hex_line[hex_i..], " ", .{}) catch continue;
                    hex_i += slice.len;
                }
            }
            ascii_line[ascii_i] = 0;

            out.print("{s}{s} |{s}|{s}\n", .{ actual_color, hex_line[0..hex_i], ascii_line[0..ascii_i], reset }) catch {};

            if (self.file) |file| {
                file.writer().print("{s} |{s}|\n", .{ hex_line[0..hex_i], ascii_line[0..ascii_i] }) catch {};
            }
        }
    }

    /// Compatibility shim used by unit-tests. It performs the same logic as
    /// `shouldLog` but **does not** take the backend mutex.  The caller must
    /// guarantee no concurrent reload or write is in progress.
    pub fn shouldLogUnsafe(self: *LogBackend, level: LogLevel, tag: []const u8) bool {
        if (builtin.mode != .Debug and level != .err) return false;

        // The filter may still need to be initialised; we reuse the regular
        // loader which itself is thread-safe.  This will momentarily acquire
        // the mutex only on first use.
        self.ensureFilterLoaded();

        return self.shouldLogInternal(level, tag);
    }
};

// Global backend instance
var backend: LogBackend = .{};

/// Force reload the ZIGLOG environment variable filter
pub fn reloadLogFilter() void {
    backend.reloadFilter();
}

pub const HexdumpOptions = struct {
    decimal_offset: bool = false,
    length: ?usize = null,
    start: usize = 0,
};

pub fn setLogFile(file: std.fs.File) void {
    backend.file = file;
}

pub fn setGlobalTimestamp(enabled: bool) void {
    backend.show_global_timestamp = enabled;
}

pub fn setGlobalLevel(enabled: bool) void {
    backend.show_global_level = enabled;
}

pub fn new(config: LogOptions) Logger {
    return Logger.init(config);
}

pub const Logger = struct {
    // Fixed-size storage for the tag slice – avoids any heap allocation and
    // keeps the whole logger as a stack value.
    tag_buf: [MAX_TAG_LEN]u8 = undefined,
    tag_len: usize = 0,

    config: LogOptions,

    /// Internal helper that creates a logger, copying the provided tag into
    /// the embedded buffer.  Panics if the tag is longer than MAX_TAG_LEN.
    pub fn init(base_cfg: LogOptions) Logger {
        std.debug.assert(base_cfg.tag.len <= MAX_TAG_LEN);

        var logger = Logger{ .config = undefined };

        // Copy tag into internal buffer in a way that works in both
        // compile-time and run-time contexts.
        logger.tag_len = base_cfg.tag.len;
        for (base_cfg.tag, 0..) |ch, idx| {
            logger.tag_buf[idx] = ch;
        }

        // Materialise the final config pointing at the slice inside tag_buf.
        logger.config = LogOptions{
            .tag = base_cfg.tag,
            .color = base_cfg.color,
            .file = base_cfg.file,
            .show_timestamp = base_cfg.show_timestamp,
            .show_level = base_cfg.show_level,
        };

        return logger;
    }

    pub fn info(self: Logger, comptime fmt: []const u8, args: anytype) void {
        // Compile-time optimization: compile out non-err logs in release mode
        if (!shouldCompileLog(.info)) return;

        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.info, self.tag(), self.config.color, self.config.show_timestamp, self.config.show_level, message);
    }

    pub fn warn(self: Logger, comptime fmt: []const u8, args: anytype) void {
        // Compile-time optimization: compile out non-err logs in release mode
        if (!shouldCompileLog(.warn)) return;

        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.warn, self.tag(), self.config.color, self.config.show_timestamp, self.config.show_level, message);
    }

    pub fn err(self: Logger, comptime fmt: []const u8, args: anytype) void {
        // Error logs are always compiled in
        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.err, self.tag(), self.config.color, self.config.show_timestamp, self.config.show_level, message);
    }

    pub fn dbg(self: Logger, comptime fmt: []const u8, args: anytype) void {
        // Compile-time optimization: compile out non-err logs in release mode
        if (!shouldCompileLog(.debug)) return;

        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.debug, self.tag(), self.config.color, self.config.show_timestamp, self.config.show_level, message);
    }

    pub fn fatal(self: Logger, comptime fmt: []const u8, args: anytype) noreturn {
        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.err, self.tag(), self.config.color, self.config.show_timestamp, self.config.show_level, message);
        std.process.exit(1);
    }

    pub fn hexdump(self: Logger, buf: []const u8, opts: HexdumpOptions) void {
        // Compile-time optimization: compile out hexdump in release mode
        if (!shouldCompileLog(.debug)) return;

        backend.writeHexdump(self.tag(), self.config.color, buf, opts);
    }

    pub fn dump(self: Logger, filename: []const u8, buf: []const u8) void {
        // Compile-time optimization: compile out dump in release mode
        if (!shouldCompileLog(.debug)) return;

        const file = std.fs.cwd().createFile(filename, .{}) catch |create_err| {
            self.err("Failed to create dump file '{s}': {}", .{ filename, create_err });
            return;
        };
        defer file.close();

        file.writeAll(buf) catch |write_err| {
            self.err("Failed to write to dump file '{s}': {}", .{ filename, write_err });
            return;
        };

        self.dbg("Dumped {} bytes to file '{s}'", .{ buf.len, filename });
    }

    pub fn block(self: Logger, label: []const u8) BlockLogger {
        return BlockLogger{
            .logger = self,
            .label = label,
        };
    }

    /// Create a *new* logger derived from the current one, overriding only
    /// the fields explicitly set in `override_config`.  The `tag` provided
    /// here *replaces* the parent tag.  Use `chain()` instead if you want to
    /// append to the existing tag.
    pub fn new(self: Logger, override: LogOptionsPartial) Logger {
        return Logger.init(LogOptions{
            .tag = override.tag orelse self.tag(),
            .color = override.color orelse self.config.color,
            .file = override.file orelse self.config.file,
            .show_timestamp = override.show_timestamp orelse self.config.show_timestamp,
            .show_level = override.show_level orelse self.config.show_level,
        });
    }

    /// Create a new logger that "chains" its configuration onto the current
    /// one.  Non-null fields in `override_config` still override the existing
    /// values *except* for `tag`: when a new tag is supplied it is **joined**
    /// onto the existing tag using a dot separator (e.g. "parent.child").
    ///
    /// The function is meant to be used with *compile-time* `override_config`
    /// so that any tag concatenation happens at compile time and no heap
    /// allocation is required, preserving the "stack-only" nature of
    /// `Logger`.
    pub fn chain(self: Logger, override_config: LogOptionsPartial) Logger {
        const parent_tag = self.tag();
        const child_tag = override_config.tag.?;
        const needed_len = parent_tag.len + 1 + child_tag.len;
        std.debug.assert(needed_len <= MAX_TAG_LEN);

        var result = Logger.init(LogOptions{
            .tag = "", // temporary, will be fixed below
            .color = override_config.color orelse self.config.color,
            .file = override_config.file orelse self.config.file,
            .show_timestamp = override_config.show_timestamp orelse self.config.show_timestamp,
            .show_level = override_config.show_level orelse self.config.show_level,
        });

        // Copy parent.child into the new logger's own buffer.
        std.mem.copyForwards(u8, result.tag_buf[0..parent_tag.len], parent_tag);
        result.tag_buf[parent_tag.len] = '.';
        std.mem.copyForwards(u8, result.tag_buf[parent_tag.len + 1 .. needed_len], child_tag);

        result.tag_len = needed_len;

        return result;
    }

    /// Return the current tag slice backed by this logger's internal buffer.
    pub fn tag(self: *const Logger) []const u8 {
        return self.tag_buf[0..self.tag_len];
    }
};

pub const BlockLogger = struct {
    logger: Logger,
    label: []const u8,

    pub fn info(self: BlockLogger, comptime fmt: []const u8, args: anytype) void {
        if (!shouldCompileLog(.info)) return;
        self.logger.info(fmt, args);
    }

    pub fn warn(self: BlockLogger, comptime fmt: []const u8, args: anytype) void {
        if (!shouldCompileLog(.warn)) return;
        self.logger.warn(fmt, args);
    }

    pub fn err(self: BlockLogger, comptime fmt: []const u8, args: anytype) void {
        self.logger.err(fmt, args);
    }

    pub fn dbg(self: BlockLogger, comptime fmt: []const u8, args: anytype) void {
        if (!shouldCompileLog(.debug)) return;
        self.logger.dbg(fmt, args);
    }

    pub fn hexdump(self: BlockLogger, buf: []const u8) void {
        if (!shouldCompileLog(.debug)) return;
        self.logger.hexdump(buf, .{});
    }

    pub fn dump(self: BlockLogger, filename: []const u8, buf: []const u8) void {
        if (!shouldCompileLog(.debug)) return;
        self.logger.dump(filename, buf);
    }

    pub fn close(self: BlockLogger, msg: []const u8) void {
        if (!shouldCompileLog(.info)) return;
        self.logger.info("{s}", .{msg});
    }
};

fn colorCode(color: LogColor) []const u8 {
    return switch (color) {
        .red => "\x1b[31m",
        .blue => "\x1b[34m",
        .green => "\x1b[32m",
        .orange => "\x1b[38;5;208m",
        .yellow => "\x1b[33m",
        .purple => "\x1b[35m",
        .pink => "\x1b[38;5;200m",
        .cyan => "\x1b[36m",
        .magenta => "\x1b[95m",
    };
}

fn levelToColor(level: LogLevel) []const u8 {
    return switch (level) {
        .debug => "\x1b[36m",
        .info => "\x1b[32m",
        .warn => "\x1b[33m",
        .err => "\x1b[1;31m",
    };
}

fn levelToLabel(level: LogLevel) []const u8 {
    return switch (level) {
        .debug => "DEBUG",
        .info => "INFO ",
        .warn => "WARN ",
        .err => "ERROR",
    };
}
