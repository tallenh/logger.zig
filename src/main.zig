const std = @import("std");
const builtin = @import("builtin");

pub const LogLevel = enum { debug, info, warn, err };

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

    pub fn deinit(self: FilterEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.tag_pattern);
    }
};

pub const LogOptions = struct {
    tag: []const u8 = "default",
    color: ?LogColor = null,
    file: ?std.fs.File = null,
    show_timestamp: bool = false,
    show_level: bool = false,
};

// Centralized logging backend - handles all I/O and synchronization
pub const LogBackend = struct {
    mutex: std.Thread.Mutex = .{},
    file: ?std.fs.File = null,
    show_global_timestamp: bool = false,
    show_global_level: bool = false,
    filter: ?std.BoundedArray(FilterEntry, 16) = null,

    fn ensureFilterLoaded(self: *LogBackend) void {
        // First check without lock for performance
        if (self.filter != null) return;

        // Double-checked locking pattern for thread safety
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check again after acquiring lock
        if (self.filter != null) return;

        self.reloadFilterUnsafe();
    }

    pub fn reloadFilter(self: *LogBackend) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.reloadFilterUnsafe();
    }

    fn reloadFilterUnsafe(self: *LogBackend) void {
        // Clean up existing filter
        if (self.filter) |f| {
            for (f.slice()) |entry| {
                entry.deinit(std.heap.page_allocator);
            }
        }
        self.filter = null;

        const env = std.process.getEnvVarOwned(std.heap.page_allocator, "ZIGLOG") catch {
            self.filter = std.BoundedArray(FilterEntry, 16){};
            return;
        };
        defer std.heap.page_allocator.free(env);

        var list = std.BoundedArray(FilterEntry, 16){};
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
            if (exclude_tag) {
                tag_pattern = std.heap.page_allocator.dupe(u8, tag_part) catch return null;
            } else {
                tag_pattern = std.heap.page_allocator.dupe(u8, tag_part) catch return null;
                level_spec = parseLevelSpec(level_part);
            }
        } else {
            // No colon, just tag pattern
            tag_pattern = std.heap.page_allocator.dupe(u8, working_str) catch return null;
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
        // Build mode check
        if (builtin.mode != .Debug and level != .err) return false;

        // Tag and level filtering
        self.ensureFilterLoaded();
        if (self.filter) |f| {
            if (f.len == 0) return true;

            var has_includes = false;
            var included = false;
            var level_allowed = true;
            var active_level_spec: ?LevelSpec = null;

            // First pass: check includes (entries without exclude_tag)
            // Process patterns in order - later patterns override earlier ones
            for (f.slice()) |entry| {
                if (!entry.exclude_tag) {
                    has_includes = true;
                    if (self.tagMatches(tag, entry.tag_pattern)) {
                        included = true;
                        // Later patterns override earlier ones (most recent wins)
                        if (entry.level_spec) |spec| {
                            active_level_spec = spec;
                        } else {
                            // If no level spec, reset to default (allow all levels)
                            active_level_spec = null;
                        }
                    }
                }
            }

            // If no includes specified, default to included
            if (!has_includes) {
                included = true;
            }

            // Check level against the active level specification
            if (active_level_spec) |spec| {
                level_allowed = self.levelMatches(level, spec);
            }

            // Second pass: check excludes (entries with exclude_tag)
            if (included) {
                for (f.slice()) |entry| {
                    if (entry.exclude_tag) {
                        if (self.tagMatches(tag, entry.tag_pattern)) {
                            return false; // Excluded entirely
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

        const level_order = [_]LogLevel{ .debug, .info, .warn, .err };
        const current_idx = for (level_order, 0..) |l, i| {
            if (l == level) break i;
        } else return false;

        const spec_idx = for (level_order, 0..) |l, i| {
            if (l == spec.level) break i;
        } else return false;

        return switch (spec.mode) {
            .exact => level == spec.level,
            .plus => current_idx >= spec_idx,
            .minus => current_idx <= spec_idx,
            .not_exact => level != spec.level,
            .not_plus => current_idx < spec_idx,
            .not_minus => current_idx > spec_idx,
        };
    }

    pub fn tagMatches(self: *LogBackend, tag: []const u8, pattern: []const u8) bool {
        _ = self; // Mark as used

        // Exact match (no wildcards)
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
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check if we should log inside the mutex to avoid double acquisition
        if (!self.shouldLogUnsafe(level, tag)) return;

        const actual_color = if (color) |c| colorCode(c) else levelToColor(level);
        const label = levelToLabel(level);
        const reset = "\x1b[0m";

        var out = switch (level) {
            .err => if (builtin.mode == .Debug) std.io.getStdOut().writer() else std.io.getStdErr().writer(),
            else => std.io.getStdOut().writer(),
        };

        const show_ts = show_timestamp or self.show_global_timestamp;
        const ts_prefix: []u8 = if (show_ts) blk: {
            var buf: [32]u8 = undefined;
            const now = std.time.timestamp();
            const slice = std.fmt.bufPrintZ(&buf, "[{d}] ", .{now}) catch break :blk ""[0..0];
            break :blk slice[0 .. slice.len - 1]; // remove null terminator
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

    // Add a new function that doesn't use the mutex (for internal use when mutex is already held)
    pub fn shouldLogUnsafe(self: *LogBackend, level: LogLevel, tag: []const u8) bool {
        // Build mode check
        if (builtin.mode != .Debug and level != .err) return false;

        // Tag and level filtering
        self.ensureFilterLoadedUnsafe();
        if (self.filter) |f| {
            if (f.len == 0) return true;

            var has_includes = false;
            var included = false;
            var level_allowed = true;
            var active_level_spec: ?LevelSpec = null;

            // First pass: check includes (entries without exclude_tag)
            // Process patterns in order - later patterns override earlier ones
            for (f.slice()) |entry| {
                if (!entry.exclude_tag) {
                    has_includes = true;
                    if (self.tagMatches(tag, entry.tag_pattern)) {
                        included = true;
                        // Later patterns override earlier ones (most recent wins)
                        if (entry.level_spec) |spec| {
                            active_level_spec = spec;
                        } else {
                            // If no level spec, reset to default (allow all levels)
                            active_level_spec = null;
                        }
                    }
                }
            }

            // If no includes specified, default to included
            if (!has_includes) {
                included = true;
            }

            // Check level against the active level specification
            if (active_level_spec) |spec| {
                level_allowed = self.levelMatches(level, spec);
            }

            // Second pass: check excludes (entries with exclude_tag)
            if (included) {
                for (f.slice()) |entry| {
                    if (entry.exclude_tag) {
                        if (self.tagMatches(tag, entry.tag_pattern)) {
                            return false; // Excluded entirely
                        }
                    }
                }
            }

            return included and level_allowed;
        }
        return true;
    }

    // Add unsafe version that doesn't acquire mutex
    fn ensureFilterLoadedUnsafe(self: *LogBackend) void {
        if (self.filter != null) return;
        self.reloadFilterUnsafe();
    }

    fn writeHexdump(self: *LogBackend, tag: []const u8, color: ?LogColor, buf: []const u8, opts: HexdumpOptions) void {
        // Hexdump only works in debug mode
        if (builtin.mode != .Debug) return;

        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.shouldLogUnsafe(.debug, tag)) return;

        const actual_color = if (color) |c| colorCode(c) else levelToColor(.debug);
        const reset = "\x1b[0m";
        const label = "DEBUG";

        var out = std.io.getStdOut().writer();

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
    return Logger{ .config = config };
}

pub const Logger = struct {
    config: LogOptions,

    pub fn info(self: Logger, comptime fmt: []const u8, args: anytype) void {
        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.info, self.config.tag, self.config.color, self.config.show_timestamp, self.config.show_level, message);
    }

    pub fn warn(self: Logger, comptime fmt: []const u8, args: anytype) void {
        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.warn, self.config.tag, self.config.color, self.config.show_timestamp, self.config.show_level, message);
    }

    pub fn err(self: Logger, comptime fmt: []const u8, args: anytype) void {
        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.err, self.config.tag, self.config.color, self.config.show_timestamp, self.config.show_level, message);
    }

    pub fn dbg(self: Logger, comptime fmt: []const u8, args: anytype) void {
        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.debug, self.config.tag, self.config.color, self.config.show_timestamp, self.config.show_level, message);
    }

    pub fn fatal(self: Logger, comptime fmt: []const u8, args: anytype) noreturn {
        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.err, self.config.tag, self.config.color, self.config.show_timestamp, self.config.show_level, message);
        std.process.exit(1);
    }

    pub fn hexdump(self: Logger, buf: []const u8, opts: HexdumpOptions) void {
        backend.writeHexdump(self.config.tag, self.config.color, buf, opts);
    }

    pub fn block(self: Logger, label: []const u8) BlockLogger {
        const open_line = std.fmt.allocPrint(std.heap.page_allocator, "============={s}=============\n", .{label}) catch return BlockLogger{
            .logger = self,
            .label = label,
        };
        defer std.heap.page_allocator.free(open_line);
        self.info("{s}", .{open_line});
        return BlockLogger{
            .logger = self,
            .label = label,
        };
    }
};

pub const BlockLogger = struct {
    logger: Logger,
    label: []const u8,

    pub fn info(self: BlockLogger, comptime fmt: []const u8, args: anytype) void {
        self.logger.info(fmt, args);
    }

    pub fn warn(self: BlockLogger, comptime fmt: []const u8, args: anytype) void {
        self.logger.warn(fmt, args);
    }

    pub fn err(self: BlockLogger, comptime fmt: []const u8, args: anytype) void {
        self.logger.err(fmt, args);
    }

    pub fn dbg(self: BlockLogger, comptime fmt: []const u8, args: anytype) void {
        self.logger.dbg(fmt, args);
    }

    pub fn hexdump(self: BlockLogger, buf: []const u8) void {
        self.logger.hexdump(buf, .{});
    }

    pub fn close(self: BlockLogger, msg: []const u8) void {
        self.logger.info("{s}\n", .{msg});
        const close_line = std.fmt.allocPrint(std.heap.page_allocator, "===========end {s}=============\n", .{self.label}) catch return;
        defer std.heap.page_allocator.free(close_line);
        self.logger.info("{s}", .{close_line});
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
