const std = @import("std");
const Allocator = std.mem.Allocator;
const Rect = @import("../layout.zig").Rect;
const Buffer = @import("../buffer.zig").Buffer;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;

/// Log level for filtering and coloring
pub const LogLevel = enum {
    trace,
    debug,
    info,
    warn,
    err,
    fatal,

    /// Get default color for log level
    pub fn defaultColor(self: LogLevel) Color {
        return switch (self) {
            .trace => .gray,
            .debug => .cyan,
            .info => .green,
            .warn => .yellow,
            .err => .red,
            .fatal => .magenta,
        };
    }

    /// Parse log level from string (case-insensitive)
    pub fn parse(str: []const u8) ?LogLevel {
        if (std.ascii.eqlIgnoreCase(str, "trace")) return .trace;
        if (std.ascii.eqlIgnoreCase(str, "debug")) return .debug;
        if (std.ascii.eqlIgnoreCase(str, "info")) return .info;
        if (std.ascii.eqlIgnoreCase(str, "warn")) return .warn;
        if (std.ascii.eqlIgnoreCase(str, "err")) return .err;
        if (std.ascii.eqlIgnoreCase(str, "error")) return .err;
        if (std.ascii.eqlIgnoreCase(str, "fatal")) return .fatal;
        return null;
    }
};

/// Log entry with timestamp, level, and message
pub const LogEntry = struct {
    /// Unix timestamp in milliseconds
    timestamp_ms: u64,
    /// Log level
    level: LogLevel,
    /// Log message (owned by caller)
    message: []const u8,
    /// Optional source/tag (e.g., "HTTP", "DB")
    source: ?[]const u8,

    /// Format timestamp as ISO8601 string
    pub fn formatTimestamp(self: LogEntry, buf: []u8) ![]const u8 {
        const seconds = self.timestamp_ms / 1000;
        const ms = self.timestamp_ms % 1000;
        return std.fmt.bufPrint(buf, "{d}.{d:0>3}s", .{ seconds, ms });
    }
};

/// Log viewer widget (tail -f style with filtering and search)
pub const LogViewer = struct {
    /// Log entries (circular buffer)
    entries: std.ArrayListUnmanaged(LogEntry),
    /// Maximum number of entries to keep (oldest trimmed)
    max_entries: usize,
    /// Current scroll offset from bottom (0 = auto-scroll enabled)
    scroll_offset: usize,
    /// Minimum log level to display
    min_level: LogLevel,
    /// Search filter (null = no filter)
    search_filter: ?[]const u8,
    /// Source filter (null = show all sources)
    source_filter: ?[]const u8,
    /// Block widget for border and title
    block: ?Block,
    /// Show timestamps
    show_timestamps: bool,
    /// Show log levels
    show_levels: bool,
    /// Show sources
    show_sources: bool,
    /// Auto-scroll to bottom when new entries arrive
    auto_scroll: bool,
    /// Highlight search matches
    highlight_search: bool,
    /// Color scheme override (null = use defaults)
    level_colors: ?[6]Color,
    /// Word wrap long lines
    wrap_lines: bool,

    /// Create a new log viewer widget
    pub fn init(allocator: Allocator, max_entries: usize) !LogViewer {
        return .{
            .entries = try std.ArrayListUnmanaged(LogEntry).initCapacity(allocator, @min(max_entries, 100)),
            .max_entries = max_entries,
            .scroll_offset = 0,
            .min_level = .trace,
            .search_filter = null,
            .source_filter = null,
            .block = null,
            .show_timestamps = true,
            .show_levels = true,
            .show_sources = true,
            .auto_scroll = true,
            .highlight_search = true,
            .level_colors = null,
            .wrap_lines = false,
        };
    }

    /// Clean up log viewer
    pub fn deinit(self: *LogViewer, allocator: Allocator) void {
        self.entries.deinit(allocator);
    }

    /// Set block border/title
    pub fn setBlock(self: *LogViewer, block: Block) void {
        self.block = block;
    }

    /// Add a log entry
    pub fn addEntry(
        self: *LogViewer,
        allocator: Allocator,
        timestamp_ms: u64,
        level: LogLevel,
        message: []const u8,
        source: ?[]const u8,
    ) !void {
        // Trim oldest entries if at capacity
        if (self.entries.items.len >= self.max_entries) {
            _ = self.entries.orderedRemove(0);
        }

        try self.entries.append(allocator, .{
            .timestamp_ms = timestamp_ms,
            .level = level,
            .message = message,
            .source = source,
        });

        // Reset scroll offset if auto-scroll enabled
        if (self.auto_scroll) {
            self.scroll_offset = 0;
        }
    }

    /// Clear all log entries
    pub fn clear(self: *LogViewer) void {
        self.entries.clearRetainingCapacity();
        self.scroll_offset = 0;
    }

    /// Scroll up by N lines
    pub fn scrollUp(self: *LogViewer, lines: usize) void {
        self.scroll_offset +|= lines;
        self.auto_scroll = false;
    }

    /// Scroll down by N lines
    pub fn scrollDown(self: *LogViewer, lines: usize) void {
        if (self.scroll_offset >= lines) {
            self.scroll_offset -= lines;
        } else {
            self.scroll_offset = 0;
            self.auto_scroll = true;
        }
    }

    /// Jump to bottom (enable auto-scroll)
    pub fn scrollToBottom(self: *LogViewer) void {
        self.scroll_offset = 0;
        self.auto_scroll = true;
    }

    /// Jump to top
    pub fn scrollToTop(self: *LogViewer) void {
        if (self.entries.items.len > 0) {
            self.scroll_offset = self.entries.items.len - 1;
            self.auto_scroll = false;
        }
    }

    /// Set minimum log level filter
    pub fn setMinLevel(self: *LogViewer, level: LogLevel) void {
        self.min_level = level;
    }

    /// Set search filter (case-insensitive substring match)
    pub fn setSearchFilter(self: *LogViewer, filter: ?[]const u8) void {
        self.search_filter = filter;
    }

    /// Set source filter
    pub fn setSourceFilter(self: *LogViewer, filter: ?[]const u8) void {
        self.source_filter = filter;
    }

    /// Check if entry passes current filters
    fn passesFilters(self: LogViewer, entry: LogEntry) bool {
        // Level filter
        const level_value: u8 = @intFromEnum(entry.level);
        const min_level_value: u8 = @intFromEnum(self.min_level);
        if (level_value < min_level_value) return false;

        // Source filter
        if (self.source_filter) |filter| {
            if (entry.source == null) return false;
            if (std.mem.indexOf(u8, entry.source.?, filter) == null) return false;
        }

        // Search filter
        if (self.search_filter) |filter| {
            // Case-insensitive search in message
            var buf: [512]u8 = undefined;
            const lower_msg = std.ascii.lowerString(&buf, entry.message);
            var filter_buf: [256]u8 = undefined;
            const lower_filter = std.ascii.lowerString(&filter_buf, filter);
            if (std.mem.indexOf(u8, lower_msg, lower_filter) == null) return false;
        }

        return true;
    }

    /// Get color for log level
    fn getLevelColor(self: LogViewer, level: LogLevel) Color {
        if (self.level_colors) |colors| {
            return colors[@intFromEnum(level)];
        }
        return level.defaultColor();
    }

    /// Check if substring matches search filter (case-insensitive)
    fn matchesSearch(self: LogViewer, text: []const u8) bool {
        if (self.search_filter == null) return false;
        const filter = self.search_filter.?;

        var buf: [512]u8 = undefined;
        const lower_text = std.ascii.lowerString(&buf, text);
        var filter_buf: [256]u8 = undefined;
        const lower_filter = std.ascii.lowerString(&filter_buf, filter);

        return std.mem.indexOf(u8, lower_text, lower_filter) != null;
    }

    /// Render the widget
    pub fn render(self: LogViewer, buf: *Buffer, area: Rect) void {
        var render_area = area;

        // Draw block border if present
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        if (render_area.height == 0 or render_area.width == 0) return;

        // Filter entries
        var filtered = std.ArrayList(LogEntry).init(std.heap.page_allocator);
        defer filtered.deinit();

        for (self.entries.items) |entry| {
            if (self.passesFilters(entry)) {
                filtered.append(entry) catch break;
            }
        }

        if (filtered.items.len == 0) return;

        // Calculate visible range
        const visible_height = render_area.height;
        const total_entries = filtered.items.len;

        var start_idx: usize = 0;
        if (total_entries > visible_height) {
            // Calculate start index based on scroll offset
            if (self.scroll_offset >= total_entries) {
                start_idx = 0;
            } else {
                const bottom_idx = total_entries -| self.scroll_offset;
                if (bottom_idx >= visible_height) {
                    start_idx = bottom_idx - visible_height;
                } else {
                    start_idx = 0;
                }
            }
        }

        var y = render_area.y;
        const max_y = render_area.y + render_area.height;

        for (filtered.items[start_idx..]) |entry| {
            if (y >= max_y) break;

            var line_buf: [1024]u8 = undefined;
            var line_pos: usize = 0;

            // Timestamp
            if (self.show_timestamps) {
                const ts_str = entry.formatTimestamp(line_buf[line_pos..]) catch "";
                line_pos += ts_str.len;
                if (line_pos < line_buf.len) {
                    line_buf[line_pos] = ' ';
                    line_pos += 1;
                }
            }

            // Level
            const level_start = line_pos;
            if (self.show_levels) {
                const level_str = @tagName(entry.level);
                for (level_str) |c| {
                    if (line_pos >= line_buf.len) break;
                    line_buf[line_pos] = std.ascii.toUpper(c);
                    line_pos += 1;
                }
                if (line_pos < line_buf.len) {
                    line_buf[line_pos] = ' ';
                    line_pos += 1;
                }
            }
            const level_end = line_pos;

            // Source
            const source_start = line_pos;
            if (self.show_sources and entry.source != null) {
                line_buf[line_pos] = '[';
                line_pos += 1;
                for (entry.source.?) |c| {
                    if (line_pos >= line_buf.len) break;
                    line_buf[line_pos] = c;
                    line_pos += 1;
                }
                if (line_pos < line_buf.len) {
                    line_buf[line_pos] = ']';
                    line_pos += 1;
                }
                if (line_pos < line_buf.len) {
                    line_buf[line_pos] = ' ';
                    line_pos += 1;
                }
            }
            const source_end = line_pos;

            // Message
            const msg_start = line_pos;
            for (entry.message) |c| {
                if (line_pos >= line_buf.len) break;
                line_buf[line_pos] = c;
                line_pos += 1;
            }

            // Render line
            const line = line_buf[0..line_pos];
            var x: usize = 0;
            for (line, 0..) |c, idx| {
                if (x >= render_area.width) break;

                var style = Style.init();

                // Color level text
                if (idx >= level_start and idx < level_end) {
                    style = style.setFg(self.getLevelColor(entry.level));
                }

                // Gray source text
                if (idx >= source_start and idx < source_end) {
                    style = style.setFg(.gray);
                }

                // Highlight search matches in message
                if (self.highlight_search and idx >= msg_start) {
                    const substr_start = idx - msg_start;
                    const substr_end = @min(entry.message.len, substr_start + 20);
                    if (substr_end > substr_start) {
                        const substr = entry.message[substr_start..substr_end];
                        if (self.matchesSearch(substr)) {
                            style = style.setBg(.yellow).setFg(.black);
                        }
                    }
                }

                buf.setCell(render_area.x + @as(u16, @intCast(x)), y, c, style);
                x += 1;
            }

            y += 1;
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "LogViewer init and deinit" {
    var viewer = try LogViewer.init(std.testing.allocator, 100);
    defer viewer.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), viewer.entries.items.len);
    try std.testing.expectEqual(@as(usize, 100), viewer.max_entries);
    try std.testing.expect(viewer.auto_scroll);
}

test "LogViewer add entry" {
    var viewer = try LogViewer.init(std.testing.allocator, 100);
    defer viewer.deinit(std.testing.allocator);

    try viewer.addEntry(std.testing.allocator, 1000, .info, "Test message", null);

    try std.testing.expectEqual(@as(usize, 1), viewer.entries.items.len);
    try std.testing.expectEqualStrings("Test message", viewer.entries.items[0].message);
    try std.testing.expectEqual(LogLevel.info, viewer.entries.items[0].level);
}

test "LogViewer trim old entries" {
    var viewer = try LogViewer.init(std.testing.allocator, 3);
    defer viewer.deinit(std.testing.allocator);

    try viewer.addEntry(std.testing.allocator, 1000, .info, "Message 1", null);
    try viewer.addEntry(std.testing.allocator, 2000, .info, "Message 2", null);
    try viewer.addEntry(std.testing.allocator, 3000, .info, "Message 3", null);
    try viewer.addEntry(std.testing.allocator, 4000, .info, "Message 4", null);

    try std.testing.expectEqual(@as(usize, 3), viewer.entries.items.len);
    try std.testing.expectEqualStrings("Message 2", viewer.entries.items[0].message);
    try std.testing.expectEqualStrings("Message 4", viewer.entries.items[2].message);
}

test "LogViewer clear" {
    var viewer = try LogViewer.init(std.testing.allocator, 100);
    defer viewer.deinit(std.testing.allocator);

    try viewer.addEntry(std.testing.allocator, 1000, .info, "Message 1", null);
    try viewer.addEntry(std.testing.allocator, 2000, .info, "Message 2", null);

    viewer.clear();

    try std.testing.expectEqual(@as(usize, 0), viewer.entries.items.len);
    try std.testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
}

test "LogViewer scroll navigation" {
    var viewer = try LogViewer.init(std.testing.allocator, 100);
    defer viewer.deinit(std.testing.allocator);

    try viewer.addEntry(std.testing.allocator, 1000, .info, "Message 1", null);

    try std.testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
    try std.testing.expect(viewer.auto_scroll);

    viewer.scrollUp(5);
    try std.testing.expectEqual(@as(usize, 5), viewer.scroll_offset);
    try std.testing.expect(!viewer.auto_scroll);

    viewer.scrollDown(2);
    try std.testing.expectEqual(@as(usize, 3), viewer.scroll_offset);

    viewer.scrollToBottom();
    try std.testing.expectEqual(@as(usize, 0), viewer.scroll_offset);
    try std.testing.expect(viewer.auto_scroll);

    viewer.scrollToTop();
    try std.testing.expect(viewer.scroll_offset > 0);
    try std.testing.expect(!viewer.auto_scroll);
}

test "LogLevel parse" {
    try std.testing.expectEqual(LogLevel.trace, LogLevel.parse("trace"));
    try std.testing.expectEqual(LogLevel.debug, LogLevel.parse("DEBUG"));
    try std.testing.expectEqual(LogLevel.info, LogLevel.parse("Info"));
    try std.testing.expectEqual(LogLevel.warn, LogLevel.parse("WARN"));
    try std.testing.expectEqual(LogLevel.err, LogLevel.parse("err"));
    try std.testing.expectEqual(LogLevel.err, LogLevel.parse("error"));
    try std.testing.expectEqual(LogLevel.fatal, LogLevel.parse("FATAL"));
    try std.testing.expectEqual(@as(?LogLevel, null), LogLevel.parse("invalid"));
}

test "LogLevel default colors" {
    try std.testing.expectEqual(Color.gray, LogLevel.trace.defaultColor());
    try std.testing.expectEqual(Color.cyan, LogLevel.debug.defaultColor());
    try std.testing.expectEqual(Color.green, LogLevel.info.defaultColor());
    try std.testing.expectEqual(Color.yellow, LogLevel.warn.defaultColor());
    try std.testing.expectEqual(Color.red, LogLevel.err.defaultColor());
    try std.testing.expectEqual(Color.magenta, LogLevel.fatal.defaultColor());
}

test "LogEntry format timestamp" {
    const entry = LogEntry{
        .timestamp_ms = 5250,
        .level = .info,
        .message = "test",
        .source = null,
    };

    var buf: [64]u8 = undefined;
    const result = try entry.formatTimestamp(&buf);
    try std.testing.expectEqualStrings("5.250s", result);
}

test "LogViewer level filter" {
    var viewer = try LogViewer.init(std.testing.allocator, 100);
    defer viewer.deinit(std.testing.allocator);

    try viewer.addEntry(std.testing.allocator, 1000, .trace, "Trace", null);
    try viewer.addEntry(std.testing.allocator, 2000, .debug, "Debug", null);
    try viewer.addEntry(std.testing.allocator, 3000, .info, "Info", null);
    try viewer.addEntry(std.testing.allocator, 4000, .warn, "Warn", null);

    viewer.setMinLevel(.warn);

    const trace_entry = viewer.entries.items[0];
    const warn_entry = viewer.entries.items[3];

    try std.testing.expect(!viewer.passesFilters(trace_entry));
    try std.testing.expect(viewer.passesFilters(warn_entry));
}

test "LogViewer search filter" {
    var viewer = try LogViewer.init(std.testing.allocator, 100);
    defer viewer.deinit(std.testing.allocator);

    try viewer.addEntry(std.testing.allocator, 1000, .info, "Hello world", null);
    try viewer.addEntry(std.testing.allocator, 2000, .info, "Goodbye", null);

    viewer.setSearchFilter("WORLD"); // Case-insensitive

    const entry1 = viewer.entries.items[0];
    const entry2 = viewer.entries.items[1];

    try std.testing.expect(viewer.passesFilters(entry1));
    try std.testing.expect(!viewer.passesFilters(entry2));
}

test "LogViewer source filter" {
    var viewer = try LogViewer.init(std.testing.allocator, 100);
    defer viewer.deinit(std.testing.allocator);

    try viewer.addEntry(std.testing.allocator, 1000, .info, "Message 1", "HTTP");
    try viewer.addEntry(std.testing.allocator, 2000, .info, "Message 2", "DB");

    viewer.setSourceFilter("HTTP");

    const entry1 = viewer.entries.items[0];
    const entry2 = viewer.entries.items[1];

    try std.testing.expect(viewer.passesFilters(entry1));
    try std.testing.expect(!viewer.passesFilters(entry2));
}

test "LogViewer render empty" {
    var viewer = try LogViewer.init(std.testing.allocator, 100);
    defer viewer.deinit(std.testing.allocator);

    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    viewer.render(&buffer, area);

    // Should not crash with empty entries
    try std.testing.expectEqual(@as(usize, 0), viewer.entries.items.len);
}

test "LogViewer render with entries" {
    var viewer = try LogViewer.init(std.testing.allocator, 100);
    defer viewer.deinit(std.testing.allocator);

    try viewer.addEntry(std.testing.allocator, 1000, .info, "Test message", null);

    var buffer = try Buffer.init(std.testing.allocator, 60, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };
    viewer.render(&buffer, area);

    // Check that something was rendered
    const cell = buffer.getCell(0, 0);
    try std.testing.expect(cell.char != ' ');
}

test "LogViewer render with block border" {
    var viewer = try LogViewer.init(std.testing.allocator, 100);
    defer viewer.deinit(std.testing.allocator);

    var block = (Block{});
    block.setBorder(true);
    block.setTitle("Logs");
    viewer.setBlock(block);

    try viewer.addEntry(std.testing.allocator, 1000, .info, "Test", null);

    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    viewer.render(&buffer, area);

    // Check border was rendered
    const top_left = buffer.getCell(0, 0);
    try std.testing.expect(top_left.char != ' ');
}

test "LogViewer render with source tags" {
    var viewer = try LogViewer.init(std.testing.allocator, 100);
    defer viewer.deinit(std.testing.allocator);

    try viewer.addEntry(std.testing.allocator, 1000, .info, "Request processed", "HTTP");

    var buffer = try Buffer.init(std.testing.allocator, 60, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };
    viewer.render(&buffer, area);

    // Check rendering occurred
    const cell = buffer.getCell(0, 0);
    try std.testing.expect(cell.char != ' ');
}

test "LogViewer render zero-size area" {
    var viewer = try LogViewer.init(std.testing.allocator, 100);
    defer viewer.deinit(std.testing.allocator);

    try viewer.addEntry(std.testing.allocator, 1000, .info, "Test", null);

    var buffer = try Buffer.init(std.testing.allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    viewer.render(&buffer, area);

    // Should not crash
    try std.testing.expectEqual(@as(usize, 1), viewer.entries.items.len);
}

test "LogViewer multiple levels and filtering" {
    var viewer = try LogViewer.init(std.testing.allocator, 100);
    defer viewer.deinit(std.testing.allocator);

    try viewer.addEntry(std.testing.allocator, 1000, .trace, "Trace msg", "SYS");
    try viewer.addEntry(std.testing.allocator, 2000, .debug, "Debug msg", "SYS");
    try viewer.addEntry(std.testing.allocator, 3000, .info, "Info msg", "APP");
    try viewer.addEntry(std.testing.allocator, 4000, .warn, "Warning msg", "APP");
    try viewer.addEntry(std.testing.allocator, 5000, .err, "Error msg", "DB");

    viewer.setMinLevel(.info);
    viewer.setSourceFilter("APP");

    const info_entry = viewer.entries.items[2];
    const warn_entry = viewer.entries.items[3];
    const err_entry = viewer.entries.items[4];

    try std.testing.expect(viewer.passesFilters(info_entry));
    try std.testing.expect(viewer.passesFilters(warn_entry));
    try std.testing.expect(!viewer.passesFilters(err_entry)); // Wrong source
}
