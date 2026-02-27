//! Progress indicators for long-running operations
//!
//! Provides progress bars, spinners, and multi-progress displays.
//! All output is written to user-provided Writer.
//!
//! Features:
//! - Progress bar: percentage, current/total, ETA, customizable width
//! - Spinner: Braille, dots, line, arc animations
//! - Multi-progress: multiple indicators with thread-safe updates
//! - Writer-based: no stdout/stderr direct usage

const std = @import("std");
const builtin = @import("builtin");
const term = @import("term.zig");
const color = @import("color.zig");
const Allocator = std.mem.Allocator;

pub const Error = error{} || Allocator.Error;

/// Spinner style
pub const SpinnerStyle = enum {
    braille,  // ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏
    dots,     // ⠋⠙⠚⠞⠖⠦⠴⠲⠳⠓
    line,     // -\|/
    arc,      // ◜◠◝◞◡◟

    pub fn frames(self: SpinnerStyle) []const []const u8 {
        return switch (self) {
            .braille => &.{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"},
            .dots => &.{"⠋", "⠙", "⠚", "⠞", "⠖", "⠦", "⠴", "⠲", "⠳", "⠓"},
            .line => &.{"-", "\\", "|", "/"},
            .arc => &.{"◜", "◠", "◝", "◞", "◡", "◟"},
        };
    }
};

/// Progress bar configuration
pub const BarConfig = struct {
    /// Width of progress bar (default: 40)
    width: usize = 40,

    /// Show percentage (default: true)
    show_percent: bool = true,

    /// Show count (current/total) (default: true)
    show_count: bool = true,

    /// Show ETA (default: false)
    show_eta: bool = false,

    /// Use color (default: auto-detect)
    use_color: ?bool = null,

    /// Filled character (default: "█")
    filled: []const u8 = "█",

    /// Empty character (default: "░")
    empty: []const u8 = "░",
};

/// Progress bar state
pub const Bar = struct {
    config: BarConfig,
    total: u64,
    current: u64,
    start_time: i64,
    use_color: bool,

    const Self = @This();

    /// Create a new progress bar
    pub fn init(total: u64, config: BarConfig) Self {
        return Self{
            .config = config,
            .total = total,
            .current = 0,
            .start_time = std.time.milliTimestamp(),
            .use_color = config.use_color orelse (color.ColorLevel.detect() != .none),
        };
    }

    /// Update progress
    pub fn update(self: *Self, current: u64) void {
        self.current = @min(current, self.total);
    }

    /// Increment progress by 1
    pub fn inc(self: *Self) void {
        self.update(self.current + 1);
    }

    /// Render to writer
    /// Writer can be std.io.AnyWriter or any writer type
    pub fn render(self: Self, writer: anytype) !void {
        // Calculate percentage
        const percent = if (self.total > 0)
            @as(f64, @floatFromInt(self.current)) / @as(f64, @floatFromInt(self.total)) * 100.0
        else
            0.0;

        // Calculate filled width
        const filled_width = if (self.total > 0)
            @as(usize, @intFromFloat(@as(f64, @floatFromInt(self.config.width)) *
                                      @as(f64, @floatFromInt(self.current)) /
                                      @as(f64, @floatFromInt(self.total))))
        else
            0;

        // Bar
        try writer.writeAll("[");

        if (self.use_color) {
            const s = color.Style{ .fg = .{ .basic = .green }, .attrs = .{ .bold = true } };
            try s.write(writer);
        }

        var i: usize = 0;
        while (i < filled_width) : (i += 1) {
            try writer.writeAll(self.config.filled);
        }

        if (self.use_color) {
            try color.Style.reset(writer);
        }

        while (i < self.config.width) : (i += 1) {
            try writer.writeAll(self.config.empty);
        }

        try writer.writeAll("]");

        // Percentage
        if (self.config.show_percent) {
            try writer.print(" {d:>5.1}%", .{percent});
        }

        // Count
        if (self.config.show_count) {
            try writer.print(" ({d}/{d})", .{self.current, self.total});
        }

        // ETA
        if (self.config.show_eta and self.current > 0 and self.current < self.total) {
            const elapsed = std.time.milliTimestamp() - self.start_time;
            const rate = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(self.current));
            const remaining = @as(i64, @intFromFloat(rate * @as(f64, @floatFromInt(self.total - self.current))));
            const eta_sec = @divFloor(remaining, 1000);

            if (eta_sec < 60) {
                try writer.print(" ETA {d}s", .{eta_sec});
            } else if (eta_sec < 3600) {
                try writer.print(" ETA {d}m{d}s", .{@divFloor(eta_sec, 60), @mod(eta_sec, 60)});
            } else {
                try writer.print(" ETA {d}h{d}m", .{@divFloor(eta_sec, 3600), @divFloor(@mod(eta_sec, 3600), 60)});
            }
        }
    }

    /// Render with ANSI clear line (for terminal updates)
    pub fn renderLine(self: Self, writer: anytype) !void {
        try writer.writeAll("\r\x1b[K");
        try self.render(writer);
    }
};

/// Spinner state
pub const Spinner = struct {
    style: SpinnerStyle,
    frame_index: usize,
    message: []const u8,
    use_color: bool,

    const Self = @This();

    /// Create a new spinner
    pub fn init(message: []const u8, style: SpinnerStyle, use_color: ?bool) Self {
        return Self{
            .style = style,
            .frame_index = 0,
            .message = message,
            .use_color = use_color orelse (color.ColorLevel.detect() != .none),
        };
    }

    /// Advance to next frame
    pub fn tick(self: *Self) void {
        const frames_list = self.style.frames();
        self.frame_index = (self.frame_index + 1) % frames_list.len;
    }

    /// Render to writer
    pub fn render(self: Self, writer: anytype) !void {
        const frames_list = self.style.frames();
        const frame = frames_list[self.frame_index];

        if (self.use_color) {
            const s = color.Style{ .fg = .{ .basic = .cyan }, .attrs = .{ .bold = true } };
            try s.write(writer);
        }

        try writer.print("{s} ", .{frame});

        if (self.use_color) {
            try color.Style.reset(writer);
        }

        try writer.writeAll(self.message);
    }

    /// Render with ANSI clear line (for terminal updates)
    pub fn renderLine(self: Self, writer: anytype) !void {
        try writer.writeAll("\r\x1b[K");
        try self.render(writer);
    }
};

/// Multi-progress manager (thread-safe)
pub const Multi = struct {
    allocator: Allocator,
    mutex: std.Thread.Mutex,
    bars: std.ArrayListUnmanaged(Bar),
    spinners: std.ArrayListUnmanaged(Spinner),

    const Self = @This();

    /// Initialize multi-progress manager
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .mutex = .{},
            .bars = .{},
            .spinners = .{},
        };
    }

    /// Cleanup resources
    pub fn deinit(self: *Self) void {
        self.bars.deinit(self.allocator);
        self.spinners.deinit(self.allocator);
    }

    /// Add a progress bar
    pub fn addBar(self: *Self, total: u64, config: BarConfig) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const bar = Bar.init(total, config);
        try self.bars.append(self.allocator, bar);
        return self.bars.items.len - 1;
    }

    /// Add a spinner
    pub fn addSpinner(self: *Self, message: []const u8, style: SpinnerStyle, use_color: ?bool) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const spinner = Spinner.init(message, style, use_color);
        try self.spinners.append(self.allocator, spinner);
        return self.spinners.items.len - 1;
    }

    /// Update bar progress (thread-safe)
    pub fn updateBar(self: *Self, index: usize, current: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (index < self.bars.items.len) {
            self.bars.items[index].update(current);
        }
    }

    /// Tick spinner (thread-safe)
    pub fn tickSpinner(self: *Self, index: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (index < self.spinners.items.len) {
            self.spinners.items[index].tick();
        }
    }

    /// Render all indicators to writer (thread-safe)
    pub fn render(self: *Self, writer: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Move cursor up to start of progress display
        const total_lines = self.bars.items.len + self.spinners.items.len;
        if (total_lines > 0) {
            try writer.print("\x1b[{d}A", .{total_lines});
        }

        // Render all bars
        for (self.bars.items) |bar| {
            try writer.writeAll("\r\x1b[K");
            try bar.render(writer);
            try writer.writeAll("\n");
        }

        // Render all spinners
        for (self.spinners.items) |spinner| {
            try writer.writeAll("\r\x1b[K");
            try spinner.render(writer);
            try writer.writeAll("\n");
        }
    }
};

// Tests

test "Bar basic" {
    var buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer buf.deinit();

    var bar = Bar.init(100, .{ .use_color = false });
    bar.update(50);

    try bar.render(buf.writer());

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "50.0%") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "(50/100)") != null);
}

test "Bar inc" {
    var bar = Bar.init(10, .{});
    try std.testing.expectEqual(@as(u64, 0), bar.current);

    bar.inc();
    try std.testing.expectEqual(@as(u64, 1), bar.current);

    bar.inc();
    try std.testing.expectEqual(@as(u64, 2), bar.current);
}

test "Bar clamps at total" {
    var bar = Bar.init(10, .{});
    bar.update(20);
    try std.testing.expectEqual(@as(u64, 10), bar.current);
}

test "Spinner frames" {
    const frames_braille = SpinnerStyle.braille.frames();
    try std.testing.expectEqual(@as(usize, 10), frames_braille.len);

    const frames_line = SpinnerStyle.line.frames();
    try std.testing.expectEqual(@as(usize, 4), frames_line.len);
}

test "Spinner tick" {
    var spinner = Spinner.init("Loading", .line, false);
    try std.testing.expectEqual(@as(usize, 0), spinner.frame_index);

    spinner.tick();
    try std.testing.expectEqual(@as(usize, 1), spinner.frame_index);

    spinner.tick();
    spinner.tick();
    spinner.tick();
    try std.testing.expectEqual(@as(usize, 0), spinner.frame_index); // Wraps around
}

test "Spinner render" {
    var buf = std.array_list.Managed(u8).init(std.testing.allocator);
    defer buf.deinit();

    const spinner = Spinner.init("Loading", .line, false);
    try spinner.render(buf.writer());

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "Loading") != null);
}

test "Multi basic" {
    const allocator = std.testing.allocator;

    var multi = Multi.init(allocator);
    defer multi.deinit();

    const bar_idx = try multi.addBar(100, .{ .use_color = false });
    try std.testing.expectEqual(@as(usize, 0), bar_idx);

    multi.updateBar(bar_idx, 50);

    const spinner_idx = try multi.addSpinner("Loading", .line, false);
    try std.testing.expectEqual(@as(usize, 0), spinner_idx);

    multi.tickSpinner(spinner_idx);
}
