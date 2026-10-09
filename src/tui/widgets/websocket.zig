//! WebSocket widget visualizing connection state for a WebSocket session.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Rect = @import("../layout.zig").Rect;
const Buffer = @import("../buffer.zig").Buffer;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const drawClipped = @import("text_clip.zig").drawClipped;

/// WebSocket connection state
pub const ConnectionState = enum {
    disconnected,
    connecting,
    connected,
    reconnecting,
    failed,
};

/// WebSocket message
pub const Message = struct {
    /// Message content
    content: []const u8,
    /// Timestamp (Unix milliseconds)
    timestamp_ms: u64,
    /// Message direction (true = received, false = sent)
    is_incoming: bool,
    /// Allocator used for content (for cleanup)
    allocator: Allocator,

    /// Create a new message
    pub fn init(allocator: Allocator, content: []const u8, timestamp_ms: u64, is_incoming: bool) !Message {
        const owned_content = try allocator.dupe(u8, content);
        return .{
            .content = owned_content,
            .timestamp_ms = timestamp_ms,
            .is_incoming = is_incoming,
            .allocator = allocator,
        };
    }

    /// Free message memory
    pub fn deinit(self: *Message) void {
        self.allocator.free(self.content);
    }
};

/// WebSocket widget with live data feed
pub const WebSocket = struct {
    /// WebSocket URL
    url: []const u8,
    /// Connection state
    state: ConnectionState,
    /// Message queue
    messages: std.ArrayList(Message),
    /// Allocator that owns the message list storage and render scratch strings
    allocator: Allocator,
    /// Current time in Unix milliseconds, used by the `.relative` timestamp format.
    /// The widget has no clock of its own (determinism): callers update it before render.
    now_ms: u64 = 0,
    /// Maximum messages to retain
    max_messages: usize,
    /// Auto-scroll enabled
    auto_scroll: bool,
    /// Current scroll position (0 = bottom/latest)
    scroll_offset: usize,
    /// Error message (only valid when state is failed)
    error_msg: ?[]const u8,
    /// Block widget for border and title
    block: ?Block,
    /// Show timestamps
    show_timestamps: bool,
    /// Show direction indicators
    show_direction: bool,
    /// Timestamp format
    timestamp_format: TimestampFormat,

    /// Timestamp display format
    pub const TimestampFormat = enum {
        /// HH:MM:SS
        time_only,
        /// YYYY-MM-DD HH:MM:SS
        datetime,
        /// Unix milliseconds
        unix_ms,
        /// Relative (e.g., "2s ago")
        relative,
    };

    /// Create a new WebSocket widget
    pub fn init(allocator: Allocator, url: []const u8) WebSocket {
        return .{
            .url = url,
            .state = .disconnected,
            .messages = .empty,
            .allocator = allocator,
            .max_messages = 100,
            .auto_scroll = true,
            .scroll_offset = 0,
            .error_msg = null,
            .block = null,
            .show_timestamps = true,
            .show_direction = true,
            .timestamp_format = .time_only,
        };
    }

    /// Free widget resources
    pub fn deinit(self: *WebSocket) void {
        for (self.messages.items) |*msg| {
            msg.deinit();
        }
        self.messages.deinit(self.allocator);
    }

    /// Set connection state
    pub fn setState(self: *WebSocket, state: ConnectionState) void {
        self.state = state;
    }

    /// Add a received message
    pub fn addMessage(self: *WebSocket, allocator: Allocator, content: []const u8, timestamp_ms: u64, is_incoming: bool) !void {
        const msg = try Message.init(allocator, content, timestamp_ms, is_incoming);
        errdefer {
            var failed = msg;
            failed.deinit();
        }
        try self.messages.append(self.allocator, msg);

        // Trim old messages if exceeded max
        while (self.messages.items.len > self.max_messages) {
            var old = self.messages.orderedRemove(0);
            old.deinit();
        }

        // Reset scroll if auto-scroll enabled
        if (self.auto_scroll) {
            self.scroll_offset = 0;
        }
    }

    /// Fail the connection
    pub fn fail(self: *WebSocket, error_msg: []const u8) void {
        self.state = .failed;
        self.error_msg = error_msg;
    }

    /// Scroll up (towards older messages)
    pub fn scrollUp(self: *WebSocket, lines: usize) void {
        self.scroll_offset +|= lines;
        if (self.scroll_offset >= self.messages.items.len) {
            self.scroll_offset = if (self.messages.items.len > 0) self.messages.items.len - 1 else 0;
        }
        self.auto_scroll = false; // Disable auto-scroll when manually scrolling
    }

    /// Scroll down (towards newer messages)
    pub fn scrollDown(self: *WebSocket, lines: usize) void {
        if (self.scroll_offset >= lines) {
            self.scroll_offset -= lines;
        } else {
            self.scroll_offset = 0;
            self.auto_scroll = true; // Re-enable auto-scroll at bottom
        }
    }

    /// Scroll to bottom
    pub fn scrollToBottom(self: *WebSocket) void {
        self.scroll_offset = 0;
        self.auto_scroll = true;
    }

    /// Toggle auto-scroll
    pub fn toggleAutoScroll(self: *WebSocket) void {
        self.auto_scroll = !self.auto_scroll;
        if (self.auto_scroll) {
            self.scroll_offset = 0;
        }
    }

    /// Format timestamp
    fn formatTimestamp(timestamp_ms: u64, now_ms: u64, format: TimestampFormat, buf: []u8) []const u8 {
        const seconds = timestamp_ms / 1000;
        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(seconds) };
        const epoch_day = epoch_seconds.getEpochDay();
        const day_seconds = epoch_seconds.getDaySeconds();
        const year_day = epoch_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return switch (format) {
            .time_only => std.fmt.bufPrint(
                buf,
                "{d:0>2}:{d:0>2}:{d:0>2}",
                .{ day_seconds.getHoursIntoDay(), day_seconds.getMinutesIntoHour(), day_seconds.getSecondsIntoMinute() },
            ) catch "[time error]",
            .datetime => std.fmt.bufPrint(
                buf,
                "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}",
                .{
                    year_day.year,
                    month_day.month.numeric(),
                    month_day.day_index + 1,
                    day_seconds.getHoursIntoDay(),
                    day_seconds.getMinutesIntoHour(),
                    day_seconds.getSecondsIntoMinute(),
                },
            ) catch "[datetime error]",
            .unix_ms => std.fmt.bufPrint(buf, "{d}ms", .{timestamp_ms}) catch "[unix error]",
            .relative => {
                const delta_ms = now_ms -| timestamp_ms;
                const delta_s = delta_ms / 1000;
                if (delta_s < 60) {
                    return std.fmt.bufPrint(buf, "{d}s ago", .{delta_s}) catch "[rel error]";
                } else if (delta_s < 3600) {
                    return std.fmt.bufPrint(buf, "{d}m ago", .{delta_s / 60}) catch "[rel error]";
                } else {
                    return std.fmt.bufPrint(buf, "{d}h ago", .{delta_s / 3600}) catch "[rel error]";
                }
            },
        };
    }

    /// Render the widget
    pub fn render(self: *const WebSocket, buf: *Buffer, area: Rect) void {
        // Apply block border if present
        const inner = if (self.block) |block| blk: {
            block.render(buf, area);
            break :blk block.inner(area);
        } else area;

        if (inner.width == 0 or inner.height == 0) return;

        // Render state header
        var y = inner.y;
        const state_text = switch (self.state) {
            .disconnected => "Disconnected",
            .connecting => "Connecting...",
            .connected => "Connected",
            .reconnecting => "Reconnecting...",
            .failed => "Failed",
        };
        const state_color: Color = switch (self.state) {
            .disconnected => .gray,
            .connecting => .yellow,
            .connected => .green,
            .reconnecting => .yellow,
            .failed => .red,
        };
        const state_style = Style{ .fg = state_color, .bold = true };

        // Render state line
        const state_line = std.fmt.allocPrint(
            self.allocator,
            "[{s}] {s}",
            .{ state_text, self.url },
        ) catch "[state error]";
        defer self.allocator.free(state_line);

        drawClipped(buf, inner.x, y, state_line, state_style, inner.width);
        y += 1;

        // Render error if failed
        if (self.state == .failed and self.error_msg != null) {
            if (y >= inner.y + inner.height) return;
            const error_style = Style{ .fg = .red, .bold = true };
            const error_text = std.fmt.allocPrint(
                self.allocator,
                "Error: {s}",
                .{self.error_msg.?},
            ) catch "Error: [format error]";
            defer self.allocator.free(error_text);
            drawClipped(buf, inner.x, y, error_text, error_style, inner.width);
            y += 1;
        }

        // Calculate visible message range
        const remaining_height = inner.height -| (y - inner.y);
        if (remaining_height == 0) return;

        const total_messages = self.messages.items.len;
        if (total_messages == 0) {
            // No messages
            if (y < inner.y + inner.height) {
                const no_msg = "(no messages)";
                drawClipped(buf, inner.x, y, no_msg, Style{ .fg = .gray }, inner.width);
            }
            return;
        }

        // Reverse order for display (newest at bottom)
        const start_index = self.scroll_offset;
        const end_index = @min(start_index + remaining_height, total_messages);

        // Render messages
        var line_idx: usize = 0;
        var msg_idx = total_messages - end_index;
        while (msg_idx < total_messages - start_index and line_idx < remaining_height) : ({
            msg_idx += 1;
            line_idx += 1;
        }) {
            const msg = self.messages.items[msg_idx];
            const render_y: u16 = y + @as(u16, @intCast(line_idx));

            // Build message line
            var line_buf: [512]u8 = undefined;
            var stream: std.Io.Writer = .fixed(&line_buf);

            // Direction indicator
            if (self.show_direction) {
                const indicator = if (msg.is_incoming) "<-" else "->";
                stream.writeAll(indicator) catch {};
                stream.writeAll(" ") catch {};
            }

            // Timestamp
            if (self.show_timestamps) {
                var ts_buf: [32]u8 = undefined;
                const ts = formatTimestamp(msg.timestamp_ms, self.now_ms, self.timestamp_format, &ts_buf);
                stream.writeAll("[") catch {};
                stream.writeAll(ts) catch {};
                stream.writeAll("] ") catch {};
            }

            // Message content
            stream.writeAll(msg.content) catch {};

            const line = stream.buffered();
            const msg_style = if (msg.is_incoming)
                Style{ .fg = .cyan }
            else
                Style{ .fg = .magenta };

            drawClipped(buf, inner.x, render_y, line, msg_style, inner.width);
        }

        // Render scroll indicator
        if (self.scroll_offset > 0) {
            const last_y = inner.y + inner.height - 1;
            const scroll_info = std.fmt.allocPrint(
                self.allocator,
                "[↑{d} more]",
                .{self.scroll_offset},
            ) catch "[scroll]";
            defer self.allocator.free(scroll_info);
            drawClipped(buf, inner.x, last_y, scroll_info, Style{ .fg = .yellow, .bold = true }, inner.width);
        }
    }
};

// Tests
const testing = std.testing;

test "WebSocket: init and state transitions" {
    const allocator = testing.allocator;
    var ws = WebSocket.init(allocator, "wss://example.com/ws");
    defer ws.deinit();

    try testing.expectEqual(.disconnected, ws.state);
    try testing.expectEqualStrings("wss://example.com/ws", ws.url);
    try testing.expectEqual(@as(usize, 0), ws.messages.items.len);

    ws.setState(.connecting);
    try testing.expectEqual(.connecting, ws.state);

    ws.setState(.connected);
    try testing.expectEqual(.connected, ws.state);

    ws.fail("Connection timeout");
    try testing.expectEqual(.failed, ws.state);
    try testing.expectEqualStrings("Connection timeout", ws.error_msg.?);
}

test "WebSocket: add message" {
    const allocator = testing.allocator;
    var ws = WebSocket.init(allocator, "wss://example.com/ws");
    defer ws.deinit();

    try ws.addMessage(allocator, "Hello", 1000, true);
    try testing.expectEqual(@as(usize, 1), ws.messages.items.len);
    try testing.expectEqualStrings("Hello", ws.messages.items[0].content);
    try testing.expectEqual(@as(u64, 1000), ws.messages.items[0].timestamp_ms);
    try testing.expect(ws.messages.items[0].is_incoming);

    try ws.addMessage(allocator, "World", 2000, false);
    try testing.expectEqual(@as(usize, 2), ws.messages.items.len);
    try testing.expectEqualStrings("World", ws.messages.items[1].content);
    try testing.expect(!ws.messages.items[1].is_incoming);
}

test "WebSocket: max messages limit" {
    const allocator = testing.allocator;
    var ws = WebSocket.init(allocator, "wss://example.com/ws");
    defer ws.deinit();
    ws.max_messages = 3;

    try ws.addMessage(allocator, "Msg1", 1000, true);
    try ws.addMessage(allocator, "Msg2", 2000, true);
    try ws.addMessage(allocator, "Msg3", 3000, true);
    try testing.expectEqual(@as(usize, 3), ws.messages.items.len);

    // Adding 4th message should remove oldest
    try ws.addMessage(allocator, "Msg4", 4000, true);
    try testing.expectEqual(@as(usize, 3), ws.messages.items.len);
    try testing.expectEqualStrings("Msg2", ws.messages.items[0].content);
    try testing.expectEqualStrings("Msg4", ws.messages.items[2].content);
}

test "WebSocket: auto-scroll" {
    const allocator = testing.allocator;
    var ws = WebSocket.init(allocator, "wss://example.com/ws");
    defer ws.deinit();

    try testing.expect(ws.auto_scroll);
    try testing.expectEqual(@as(usize, 0), ws.scroll_offset);

    ws.toggleAutoScroll();
    try testing.expect(!ws.auto_scroll);

    ws.toggleAutoScroll();
    try testing.expect(ws.auto_scroll);
}

test "WebSocket: scroll up/down" {
    const allocator = testing.allocator;
    var ws = WebSocket.init(allocator, "wss://example.com/ws");
    defer ws.deinit();

    // Add some messages
    try ws.addMessage(allocator, "Msg1", 1000, true);
    try ws.addMessage(allocator, "Msg2", 2000, true);
    try ws.addMessage(allocator, "Msg3", 3000, true);

    // Scroll up
    ws.scrollUp(1);
    try testing.expectEqual(@as(usize, 1), ws.scroll_offset);
    try testing.expect(!ws.auto_scroll);

    ws.scrollUp(1);
    try testing.expectEqual(@as(usize, 2), ws.scroll_offset);

    // Scroll down
    ws.scrollDown(1);
    try testing.expectEqual(@as(usize, 1), ws.scroll_offset);
    try testing.expect(!ws.auto_scroll);

    ws.scrollDown(2);
    try testing.expectEqual(@as(usize, 0), ws.scroll_offset);
    try testing.expect(ws.auto_scroll); // Re-enabled at bottom
}

test "WebSocket: scroll to bottom" {
    const allocator = testing.allocator;
    var ws = WebSocket.init(allocator, "wss://example.com/ws");
    defer ws.deinit();

    try ws.addMessage(allocator, "Msg1", 1000, true);
    try ws.addMessage(allocator, "Msg2", 2000, true);

    ws.scrollUp(5);
    try testing.expect(ws.scroll_offset > 0);

    ws.scrollToBottom();
    try testing.expectEqual(@as(usize, 0), ws.scroll_offset);
    try testing.expect(ws.auto_scroll);
}

test "WebSocket: format timestamp - time_only" {
    var buf: [64]u8 = undefined;
    // 2024-01-15 14:30:45 UTC
    const timestamp_ms = 1705329045000;
    const result = WebSocket.formatTimestamp(timestamp_ms, 0, .time_only, &buf);
    try testing.expectEqualStrings("14:30:45", result);
}

test "WebSocket: format timestamp - datetime" {
    var buf: [64]u8 = undefined;
    const timestamp_ms = 1705329045000;
    const result = WebSocket.formatTimestamp(timestamp_ms, 0, .datetime, &buf);
    try testing.expectEqualStrings("2024-01-15 14:30:45", result);
}

test "WebSocket: format timestamp - unix_ms" {
    var buf: [64]u8 = undefined;
    const timestamp_ms = 1705329045000;
    const result = WebSocket.formatTimestamp(timestamp_ms, 0, .unix_ms, &buf);
    try testing.expectEqualStrings("1705329045000ms", result);
}

test "WebSocket: format timestamp - relative uses injected clock" {
    var buf: [64]u8 = undefined;
    const sent_ms: u64 = 1_000_000;
    try testing.expectEqualStrings(
        "5s ago",
        WebSocket.formatTimestamp(sent_ms, sent_ms + 5_000, .relative, &buf),
    );
    try testing.expectEqualStrings(
        "3m ago",
        WebSocket.formatTimestamp(sent_ms, sent_ms + 180_000, .relative, &buf),
    );
    try testing.expectEqualStrings(
        "2h ago",
        WebSocket.formatTimestamp(sent_ms, sent_ms + 7_200_000, .relative, &buf),
    );
    // A timestamp in the future saturates to zero instead of underflowing.
    try testing.expectEqualStrings(
        "0s ago",
        WebSocket.formatTimestamp(sent_ms + 10, sent_ms, .relative, &buf),
    );
}

test "WebSocket: render with no messages" {
    const allocator = testing.allocator;
    var ws = WebSocket.init(allocator, "wss://example.com/ws");
    defer ws.deinit();
    ws.setState(.connected);

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    ws.render(&buffer, area);

    // Should show state and "no messages"
    const line0 = buffer.getLine(0, 0, 40);
    defer allocator.free(line0);
    try testing.expect(std.mem.find(u8, line0, "Connected") != null);
    try testing.expect(std.mem.find(u8, line0, "wss://example.com/ws") != null);

    const line1 = buffer.getLine(1, 0, 40);
    defer allocator.free(line1);
    try testing.expect(std.mem.find(u8, line1, "(no messages)") != null);
}

test "WebSocket: render with messages" {
    const allocator = testing.allocator;
    var ws = WebSocket.init(allocator, "wss://example.com/ws");
    defer ws.deinit();
    ws.setState(.connected);
    ws.show_timestamps = false; // Simpler test

    try ws.addMessage(allocator, "Hello server", 1000, false);
    try ws.addMessage(allocator, "Hello client", 2000, true);

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    ws.render(&buffer, area);

    // Line 0: state
    const line0 = buffer.getLine(0, 0, 40);
    defer allocator.free(line0);
    try testing.expect(std.mem.find(u8, line0, "Connected") != null);

    // Lines 1-2: messages
    const line1 = buffer.getLine(1, 0, 40);
    defer allocator.free(line1);
    try testing.expect(std.mem.find(u8, line1, "->") != null);
    try testing.expect(std.mem.find(u8, line1, "Hello server") != null);

    const line2 = buffer.getLine(2, 0, 40);
    defer allocator.free(line2);
    try testing.expect(std.mem.find(u8, line2, "<-") != null);
    try testing.expect(std.mem.find(u8, line2, "Hello client") != null);
}

test "WebSocket: render failed state" {
    const allocator = testing.allocator;
    var ws = WebSocket.init(allocator, "wss://example.com/ws");
    defer ws.deinit();
    ws.fail("Connection refused");

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    ws.render(&buffer, area);

    const line0 = buffer.getLine(0, 0, 40);
    defer allocator.free(line0);
    try testing.expect(std.mem.find(u8, line0, "Failed") != null);

    const line1 = buffer.getLine(1, 0, 40);
    defer allocator.free(line1);
    try testing.expect(std.mem.find(u8, line1, "Error: Connection refused") != null);
}

test "WebSocket: render with block border" {
    const allocator = testing.allocator;
    var ws = WebSocket.init(allocator, "wss://example.com/ws");
    defer ws.deinit();
    ws.setState(.connected);
    ws.block = (Block{}).withTitle("WebSocket", .top_left);

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    ws.render(&buffer, area);

    // Should have border characters
    const line0 = buffer.getLine(0, 0, 40);
    defer allocator.free(line0);
    try testing.expect(std.mem.find(u8, line0, "WebSocket") != null);
}

test "WebSocket: render with timestamps" {
    const allocator = testing.allocator;
    var ws = WebSocket.init(allocator, "wss://example.com/ws");
    defer ws.deinit();
    ws.setState(.connected);
    ws.show_timestamps = true;
    ws.timestamp_format = .unix_ms;

    try ws.addMessage(allocator, "Test", 1705329045000, true);

    var buffer = try Buffer.init(allocator, 60, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };
    ws.render(&buffer, area);

    const line1 = buffer.getLine(1, 0, 60);
    defer allocator.free(line1);
    try testing.expect(std.mem.find(u8, line1, "[1705329045000ms]") != null);
    try testing.expect(std.mem.find(u8, line1, "Test") != null);
}

test "WebSocket: render scroll indicator" {
    const allocator = testing.allocator;
    var ws = WebSocket.init(allocator, "wss://example.com/ws");
    defer ws.deinit();
    ws.setState(.connected);
    ws.show_timestamps = false;

    // Add many messages
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const msg = try std.fmt.allocPrint(allocator, "Message {d}", .{i});
        defer allocator.free(msg);
        try ws.addMessage(allocator, msg, 1000 + i * 1000, true);
    }

    ws.scrollUp(10);

    var buffer = try Buffer.init(allocator, 40, 5);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    ws.render(&buffer, area);

    // Last line should show scroll indicator
    const last_line = buffer.getLine(4, 0, 40);
    defer allocator.free(last_line);
    try testing.expect(std.mem.find(u8, last_line, "[↑10 more]") != null);
}
