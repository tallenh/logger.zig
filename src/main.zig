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

pub var log_file: ?std.fs.File = null;
pub var show_global_timestamp: bool = false;

var filter: ?std.BoundedArray([]const u8, 16) = null;

pub const HexdumpOptions = struct {
    tag: []const u8,
    color: ?LogColor,
    file: ?std.fs.File,
    decimal_offset: bool = false,
    length: ?usize = null,
    start: usize = 0,
};

pub fn setLogFile(file: std.fs.File) void {
    log_file = file;
}

pub fn new(config: LogOptions) Logger {
    return Logger{ .config = config };
}

pub const Logger = struct {
    config: LogOptions,

    pub fn info(self: Logger, comptime fmt: []const u8, args: anytype) void {
        logWithOptions(.info, self.config, fmt, args);
    }

    pub fn warn(self: Logger, comptime fmt: []const u8, args: anytype) void {
        logWithOptions(.warn, self.config, fmt, args);
    }

    pub fn err(self: Logger, comptime fmt: []const u8, args: anytype) void {
        logWithOptions(.err, self.config, fmt, args);
    }

    pub fn dbg(self: Logger, comptime fmt: []const u8, args: anytype) void {
        logWithOptions(.debug, self.config, fmt, args);
    }

    pub fn fatal(self: Logger, comptime fmt: []const u8, args: anytype) noreturn {
        logWithOptions(.err, self.config, fmt, args);
        std.process.exit(1);
    }

    pub fn hexdump(self: Logger, buf: []const u8, opts: struct {
        decimal_offset: bool = false,
        length: ?usize = null,
        start: usize = 0,
    }) void {
        const combined = HexdumpOptions{
            .tag = self.config.tag,
            .color = self.config.color,
            .file = self.config.file,
            .decimal_offset = opts.decimal_offset,
            .length = opts.length,
            .start = opts.start,
        };
        hexdump_impl(buf, combined);
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

fn ensureFilterLoaded() void {
    if (filter != null) return;

    const env = std.process.getEnvVarOwned(std.heap.page_allocator, "ZIGLOG") catch {
        filter = std.BoundedArray([]const u8, 16){};
        return;
    };
    defer std.heap.page_allocator.free(env);

    var list = std.BoundedArray([]const u8, 16){};
    var it = std.mem.splitSequence(u8, env, ",");
    while (it.next()) |entry| {
        // Create a copy of the entry since env will be freed
        const entry_copy = std.heap.page_allocator.dupe(u8, entry) catch continue;
        list.append(entry_copy) catch {};
    }
    filter = list;
}

fn tagMatches(tag: []const u8) bool {
    ensureFilterLoaded();
    if (filter == null) return true;
    // If filter is empty (no ZIGLOG set), allow all tags
    if (filter.?.len == 0) return true;
    for (filter.?.slice()) |allowed| {
        if (std.mem.eql(u8, allowed, tag)) return true;
    }
    return false;
}

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

fn logWithOptions(
    level: LogLevel,
    options: LogOptions,
    comptime fmt: []const u8,
    args: anytype,
) void {
    if (!tagMatches(options.tag)) return;

    const color = if (options.color) |c| colorCode(c) else levelToColor(level);
    const label = levelToLabel(level);
    const reset = "\x1b[0m";

    var out = switch (level) {
        .err => std.io.getStdErr().writer(),
        else => std.io.getStdOut().writer(),
    };

    const show_ts = options.show_timestamp or show_global_timestamp;
    const ts_prefix: []u8 = if (show_ts) blk: {
        var buf: [32]u8 = undefined;
        const now = std.time.timestamp();
        const slice = std.fmt.bufPrintZ(&buf, "[{d}] ", .{now}) catch break :blk ""[0..0];
        break :blk slice[0 .. slice.len - 1]; // remove null terminator
    } else ""[0..0];

    // Create a new tuple with the prefix, color, tag, label, user args, and reset
    const full_args = .{ ts_prefix, color, options.tag, label } ++ args ++ .{reset};

    out.print("{s}{s}[{s}] {s}: " ++ fmt ++ "{s}\n", full_args) catch {};

    const target_file = options.file orelse log_file;
    if (target_file) |file| {
        const file_args = .{ ts_prefix, options.tag, label } ++ args;
        file.writer().print("{s}[{s}] {s}: " ++ fmt ++ "\n", file_args) catch {};
    }
}

pub fn hexdump_impl(buf: []const u8, opts: HexdumpOptions) void {
    if (!tagMatches(opts.tag)) return;

    const color = if (opts.color) |c| colorCode(c) else levelToColor(.debug);
    const reset = "\x1b[0m";
    const label = "DEBUG";

    var out = std.io.getStdOut().writer();

    const start = opts.start;
    if (start >= buf.len) return;
    const bytes_available = buf.len - start;
    const bytes_to_dump = if (opts.length) |len| @min(bytes_available, len) else bytes_available;

    out.print("{s}[{s}] {s}: hexdump buffer length = {}{s}\n", .{
        color, opts.tag, label, bytes_to_dump, reset,
    }) catch {};

    const target_file = opts.file orelse log_file;
    if (target_file) |file| {
        file.writer().print("[{s}] {s}: hexdump buffer length = {}\n", .{
            opts.tag, label, bytes_to_dump,
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

        out.print("{s}{s} |{s}|{s}\n", .{ color, hex_line[0..hex_i], ascii_line[0..ascii_i], reset }) catch {};

        if (target_file) |file| {
            file.writer().print("{s} |{s}|\n", .{ hex_line[0..hex_i], ascii_line[0..ascii_i] }) catch {};
        }
    }
}
