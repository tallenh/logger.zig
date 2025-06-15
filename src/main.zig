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

pub const LogOptions = struct {
    tag: []const u8 = "default",
    color: ?LogColor = null,
    file: ?std.fs.File = null,
    show_timestamp: bool = false,
};

// Centralized logging backend - handles all I/O and synchronization
const LogBackend = struct {
    mutex: std.Thread.Mutex = .{},
    file: ?std.fs.File = null,
    show_global_timestamp: bool = false,
    filter: ?std.BoundedArray([]const u8, 16) = null,

    fn ensureFilterLoaded(self: *LogBackend) void {
        if (self.filter != null) return;

        const env = std.process.getEnvVarOwned(std.heap.page_allocator, "ZIGLOG") catch {
            self.filter = std.BoundedArray([]const u8, 16){};
            return;
        };
        defer std.heap.page_allocator.free(env);

        var list = std.BoundedArray([]const u8, 16){};
        var it = std.mem.splitSequence(u8, env, ",");
        while (it.next()) |entry| {
            const entry_copy = std.heap.page_allocator.dupe(u8, entry) catch continue;
            list.append(entry_copy) catch {};
        }
        self.filter = list;
    }

    fn shouldLog(self: *LogBackend, level: LogLevel, tag: []const u8) bool {
        // Build mode check
        if (builtin.mode != .Debug and level != .err) return false;

        // Tag filtering
        self.ensureFilterLoaded();
        if (self.filter) |f| {
            if (f.len == 0) return true;
            for (f.slice()) |allowed| {
                if (std.mem.eql(u8, allowed, tag)) return true;
            }
            return false;
        }
        return true;
    }

    fn writeLog(self: *LogBackend, level: LogLevel, tag: []const u8, color: ?LogColor, show_timestamp: bool, message: []const u8) void {
        if (!self.shouldLog(level, tag)) return;

        self.mutex.lock();
        defer self.mutex.unlock();

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

        out.print("{s}{s}[{s}] {s}: {s}{s}\n", .{ ts_prefix, actual_color, tag, label, message, reset }) catch {};

        if (self.file) |file| {
            file.writer().print("{s}[{s}] {s}: {s}\n", .{ ts_prefix, tag, label, message }) catch {};
        }
    }

    fn writeHexdump(self: *LogBackend, tag: []const u8, color: ?LogColor, buf: []const u8, opts: HexdumpOptions) void {
        // Hexdump only works in debug mode
        if (builtin.mode != .Debug) return;
        if (!self.shouldLog(.debug, tag)) return;

        self.mutex.lock();
        defer self.mutex.unlock();

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

pub fn new(config: LogOptions) Logger {
    return Logger{ .config = config };
}

pub const Logger = struct {
    config: LogOptions,

    pub fn info(self: Logger, comptime fmt: []const u8, args: anytype) void {
        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.info, self.config.tag, self.config.color, self.config.show_timestamp, message);
    }

    pub fn warn(self: Logger, comptime fmt: []const u8, args: anytype) void {
        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.warn, self.config.tag, self.config.color, self.config.show_timestamp, message);
    }

    pub fn err(self: Logger, comptime fmt: []const u8, args: anytype) void {
        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.err, self.config.tag, self.config.color, self.config.show_timestamp, message);
    }

    pub fn dbg(self: Logger, comptime fmt: []const u8, args: anytype) void {
        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.debug, self.config.tag, self.config.color, self.config.show_timestamp, message);
    }

    pub fn fatal(self: Logger, comptime fmt: []const u8, args: anytype) noreturn {
        var buf: [1024]u8 = undefined;
        const message = std.fmt.bufPrint(&buf, fmt, args) catch "FORMAT_ERROR";
        backend.writeLog(.err, self.config.tag, self.config.color, self.config.show_timestamp, message);
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
