const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const Borders = @import("block.zig").Borders;

/// Notification level determines styling and icon
pub const Level = enum {
    info,
    success,
    warning,
    error_,

    /// Returns the Unicode icon character for this notification level.
    ///
    /// Returns:
    ///   'ℹ' for info, '✓' for success, '⚠' for warning, '✗' for error
    pub fn icon(self: Level) u21 {
        return switch (self) {
            .info => 'ℹ',
            .success => '✓',
            .warning => '⚠',
            .error_ => '✗',
        };
    }

    /// Returns the default style for this notification level.
    ///
    /// Colors: Blue (info), Green (success), Yellow (warning), Red (error)
    ///
    /// Returns:
    ///   Style with appropriate foreground color
    pub fn style(self: Level) Style {
        return switch (self) {
            .info => Style{ .fg = .{ .indexed = 12 } }, // Blue
            .success => Style{ .fg = .{ .indexed = 10 } }, // Green
            .warning => Style{ .fg = .{ .indexed = 11 } }, // Yellow
            .error_ => Style{ .fg = .{ .indexed = 9 } }, // Red
        };
    }
};

/// Position where notification should appear
pub const Position = enum {
    top_right,
    top_left,
    bottom_right,
    bottom_left,
    top_center,
    bottom_center,
};

/// Notification widget for toast messages and alerts
/// Typically displayed at screen edges with auto-dismiss or manual close
///
/// Example: Success notification
/// ```zig
/// var notif = Notification.success("File saved successfully!");
/// notif.setPosition(.bottom_right);
///
/// try notif.render(&buf, area);
/// ```
///
/// Example: Error with custom positioning and title
/// ```zig
/// var notif = Notification.err("Connection failed");
/// notif.title = "Error";
/// notif.setPosition(.top_center);
/// notif.width = 40;
///
/// try notif.render(&buf, area);
/// ```
///
/// Example: Info notification without border
/// ```zig
/// var notif = Notification.info("Processing...");
/// notif.show_border = false;
/// notif.setPosition(.bottom_left);
///
/// try notif.render(&buf, area);
/// ```
///
/// Example: Warning with custom style
/// ```zig
/// var notif = Notification.warning("Low disk space");
/// notif.custom_style = Style{
///     .fg = .{ .indexed = 0 },
///     .bg = .{ .indexed = 11 },
///     .bold = true,
/// };
///
/// try notif.render(&buf, area);
/// ```
pub const Notification = struct {
    /// Notification message
    message: []const u8,
    /// Notification level (affects icon and color)
    level: Level,
    /// Position on screen
    position: Position,
    /// Optional title
    title: ?[]const u8,
    /// Width in cells (0 = auto-size from content)
    width: u16,
    /// Show border around notification
    show_border: bool,
    /// Custom style (overrides level default if set)
    custom_style: ?Style,
    /// Ticks until auto-dismiss (0 = persistent, never auto-dismissed)
    timeout_ticks: u32 = 0,
    /// Internal countdown, initialized to timeout_ticks; decremented by tick()
    ticks_remaining: u32 = 0,
    /// True once dismissed (manually via dismiss() or automatically via tick() timeout).
    /// render() is a no-op once dismissed.
    dismissed: bool = false,

    pub fn init(message: []const u8, level: Level) Notification {
        return Notification{
            .message = message,
            .level = level,
            .position = .top_right,
            .title = null,
            .width = 0,
            .show_border = true,
            .custom_style = null,
        };
    }

    /// Create an info notification
    pub fn info(message: []const u8) Notification {
        return init(message, .info);
    }

    /// Create a success notification
    pub fn success(message: []const u8) Notification {
        return init(message, .success);
    }

    /// Create a warning notification
    pub fn warning(message: []const u8) Notification {
        return init(message, .warning);
    }

    /// Create an error notification
    pub fn err(message: []const u8) Notification {
        return init(message, .error_);
    }

    /// Set position
    pub fn setPosition(self: *Notification, pos: Position) void {
        self.position = pos;
    }

    /// Set auto-dismiss timeout in ticks (0 = persistent). Sets ticks_remaining to match,
    /// since Notification has no separate show() call — it's live as soon as constructed.
    pub fn withTimeout(self: Notification, ticks: u32) Notification {
        var result = self;
        result.timeout_ticks = ticks;
        result.ticks_remaining = ticks;
        return result;
    }

    /// Manually dismiss the notification. render() becomes a no-op after this.
    pub fn dismiss(self: *Notification) void {
        self.dismissed = true;
    }

    /// Advance the auto-dismiss countdown by one tick. No-op if already dismissed
    /// or if timeout_ticks == 0 (persistent). Sets dismissed = true when ticks_remaining hits 0.
    pub fn tick(self: *Notification) void {
        if (self.dismissed) return;
        if (self.timeout_ticks == 0) return;
        self.ticks_remaining -= 1;
        if (self.ticks_remaining == 0) {
            self.dismissed = true;
        }
    }

    /// Calculate notification area based on parent and settings
    fn calculateArea(self: Notification, parent: Rect) Rect {
        const title_len = if (self.title) |t| t.len else 0;
        const icon_space: usize = 2; // Icon + space

        // Auto-size width: icon + message + padding, or explicit width
        const content_width = @max(self.message.len + icon_space, title_len);
        const notif_width = if (self.width > 0)
            @min(self.width, parent.width)
        else
            @min(@as(u16, @intCast(content_width + 4)), parent.width);

        // Height: 1 line for message + optional title + borders
        const has_title: u16 = if (self.title != null) 1 else 0;
        const border_space: u16 = if (self.show_border) 2 else 0;
        const notif_height = @min(1 + has_title + border_space, parent.height);

        // Calculate position based on placement
        const x = switch (self.position) {
            .top_right, .bottom_right => parent.x + parent.width -| notif_width,
            .top_left, .bottom_left => parent.x,
            .top_center, .bottom_center => parent.x + (parent.width -| notif_width) / 2,
        };

        const y = switch (self.position) {
            .top_right, .top_left, .top_center => parent.y,
            .bottom_right, .bottom_left, .bottom_center => parent.y + parent.height -| notif_height,
        };

        return Rect{
            .x = x,
            .y = y,
            .width = notif_width,
            .height = notif_height,
        };
    }

    /// Render the notification
    pub fn render(self: Notification, buf: *Buffer, parent_area: Rect) !void {
        if (self.dismissed) return;
        if (parent_area.width == 0 or parent_area.height == 0) return;

        const area = self.calculateArea(parent_area);
        if (area.width == 0 or area.height == 0) return;

        const notif_style = self.custom_style orelse self.level.style();

        // Draw border if enabled
        var inner_area = area;
        if (self.show_border) {
            var block = Block{
                .borders = Borders.all,
                .border_style = notif_style,
                .title = self.title orelse "",
            };
            block.render(buf, area);
            inner_area = block.inner(area);
            if (inner_area.width == 0 or inner_area.height == 0) return;
        }

        // Draw icon
        var x = inner_area.x;
        const y = inner_area.y;

        if (x < inner_area.x + inner_area.width) {
            buf.set(x, y, .{ .char = self.level.icon(), .style = notif_style });
            x += 1;

            // Space after icon
            if (x < inner_area.x + inner_area.width) {
                buf.set(x, y, .{ .char = ' ', .style = notif_style });
                x += 1;
            }
        }

        // Draw message
        for (self.message) |ch| {
            if (x >= inner_area.x + inner_area.width) break;
            buf.set(x, y, .{ .char = ch, .style = notif_style });
            x += 1;
        }
    }
};

// Tests
test "Notification.init" {
    const notif = Notification.init("Test message", .info);

    try std.testing.expectEqualStrings("Test message", notif.message);
    try std.testing.expectEqual(Level.info, notif.level);
    try std.testing.expectEqual(Position.top_right, notif.position);
    try std.testing.expectEqual(true, notif.show_border);
}

test "Notification.info" {
    const notif = Notification.info("Info message");

    try std.testing.expectEqualStrings("Info message", notif.message);
    try std.testing.expectEqual(Level.info, notif.level);
}

test "Notification.success" {
    const notif = Notification.success("Success!");

    try std.testing.expectEqualStrings("Success!", notif.message);
    try std.testing.expectEqual(Level.success, notif.level);
}

test "Notification.warning" {
    const notif = Notification.warning("Warning!");

    try std.testing.expectEqualStrings("Warning!", notif.message);
    try std.testing.expectEqual(Level.warning, notif.level);
}

test "Notification.err" {
    const notif = Notification.err("Error occurred");

    try std.testing.expectEqualStrings("Error occurred", notif.message);
    try std.testing.expectEqual(Level.error_, notif.level);
}

test "Level.icon" {
    try std.testing.expectEqual('ℹ', Level.info.icon());
    try std.testing.expectEqual('✓', Level.success.icon());
    try std.testing.expectEqual('⚠', Level.warning.icon());
    try std.testing.expectEqual('✗', Level.error_.icon());
}

test "Level.style" {
    const info_style = Level.info.style();
    const success_style = Level.success.style();

    // Styles should have different colors
    try std.testing.expect(info_style.fg != null);
    try std.testing.expect(success_style.fg != null);
}

test "Notification.setPosition" {
    var notif = Notification.info("Test");

    try std.testing.expectEqual(Position.top_right, notif.position);

    notif.setPosition(.bottom_left);
    try std.testing.expectEqual(Position.bottom_left, notif.position);

    notif.setPosition(.top_center);
    try std.testing.expectEqual(Position.top_center, notif.position);
}

test "Notification.calculateArea top_right" {
    var notif = Notification.info("Hello");
    notif.setPosition(.top_right);

    const parent = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    const area = notif.calculateArea(parent);

    // Should be at top-right
    try std.testing.expectEqual(0, area.y);
    try std.testing.expect(area.x > 0); // Not at left edge
    try std.testing.expect(area.x + area.width <= parent.width);
}

test "Notification.calculateArea bottom_left" {
    var notif = Notification.success("Done!");
    notif.setPosition(.bottom_left);

    const parent = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    const area = notif.calculateArea(parent);

    // Should be at bottom-left
    try std.testing.expectEqual(0, area.x);
    try std.testing.expect(area.y > 0); // Not at top edge
}

test "Notification.calculateArea top_center" {
    var notif = Notification.warning("Warning!");
    notif.setPosition(.top_center);

    const parent = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    const area = notif.calculateArea(parent);

    // Should be at top-center
    try std.testing.expectEqual(0, area.y);
    try std.testing.expect(area.x > 0); // Centered, not at left
    try std.testing.expect(area.x < parent.width / 2 + area.width / 2); // Roughly centered
}

test "Notification.calculateArea custom width" {
    var notif = Notification.err("Error");
    notif.width = 30;

    const parent = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    const area = notif.calculateArea(parent);

    try std.testing.expectEqual(30, area.width);
}

test "Notification.render simple" {
    const allocator = std.testing.allocator;
    var notif = Notification.info("Test notification");

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    var buf = try Buffer.init(allocator, area.width, area.height);
    defer buf.deinit();

    try notif.render(&buf, area);

    // Should render without errors
    var non_empty: usize = 0;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getConst(@intCast(col), @intCast(row)).?;
            if (cell.char != ' ') non_empty += 1;
        }
    }

    try std.testing.expect(non_empty > 0);
}

test "Notification.render with title" {
    const allocator = std.testing.allocator;
    var notif = Notification.success("Operation completed");
    notif.title = "Success";

    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 25 };
    var buf = try Buffer.init(allocator, area.width, area.height);
    defer buf.deinit();

    try notif.render(&buf, area);

    // Should render title and message
    var found_text = false;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getConst(@intCast(col), @intCast(row)).?;
            if (cell.char == 'O' or cell.char == 'p' or cell.char == 'e') {
                found_text = true;
            }
        }
    }

    try std.testing.expect(found_text);
}

test "Notification.render no border" {
    const allocator = std.testing.allocator;
    var notif = Notification.warning("Watch out!");
    notif.show_border = false;

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 15 };
    var buf = try Buffer.init(allocator, area.width, area.height);
    defer buf.deinit();

    try notif.render(&buf, area);

    // Should still render message
    var found_message = false;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getConst(@intCast(col), @intCast(row)).?;
            if (cell.char == 'W' or cell.char == 'a' or cell.char == 't') {
                found_message = true;
            }
        }
    }

    try std.testing.expect(found_message);
}

test "Notification.render all positions" {
    const allocator = std.testing.allocator;
    const positions = [_]Position{
        .top_right,
        .top_left,
        .bottom_right,
        .bottom_left,
        .top_center,
        .bottom_center,
    };

    for (positions) |pos| {
        var notif = Notification.info("Test");
        notif.setPosition(pos);

        const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
        var buf = try Buffer.init(allocator, area.width, area.height);
        defer buf.deinit();

        // Should render at all positions without error
        try notif.render(&buf, area);
    }
}

test "Notification.render empty area" {
    const allocator = std.testing.allocator;
    const notif = Notification.err("Error");

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    // Should not crash
    try notif.render(&buf, area);
}

// Auto-dismiss and manual-close tests (RED phase — these tests will fail until implementation)

test "Notification default timeout fields are zero and not dismissed" {
    const notif = Notification.init("Test", .info);
    try std.testing.expectEqual(@as(u32, 0), notif.timeout_ticks);
    try std.testing.expectEqual(@as(u32, 0), notif.ticks_remaining);
    try std.testing.expectEqual(false, notif.dismissed);
}

test "Notification.info default timeout fields are zero and not dismissed" {
    const notif = Notification.info("Info message");
    try std.testing.expectEqual(@as(u32, 0), notif.timeout_ticks);
    try std.testing.expectEqual(@as(u32, 0), notif.ticks_remaining);
    try std.testing.expectEqual(false, notif.dismissed);
}

test "Notification.withTimeout sets both timeout_ticks and ticks_remaining" {
    const notif = Notification.success("Test");
    const with_timeout = notif.withTimeout(5);

    try std.testing.expectEqual(@as(u32, 5), with_timeout.timeout_ticks);
    try std.testing.expectEqual(@as(u32, 5), with_timeout.ticks_remaining);
    try std.testing.expectEqual(false, with_timeout.dismissed);

    // Original should be unchanged (immutability check)
    try std.testing.expectEqual(@as(u32, 0), notif.timeout_ticks);
}

test "Notification.dismiss sets dismissed to true" {
    var notif = Notification.warning("Test");
    try std.testing.expectEqual(false, notif.dismissed);

    notif.dismiss();
    try std.testing.expectEqual(true, notif.dismissed);
}

test "Notification.tick persistent (timeout_ticks=0) never dismisses" {
    var notif = Notification.err("Test");
    try std.testing.expectEqual(@as(u32, 0), notif.timeout_ticks);

    // Call tick 5 times
    for (0..5) |_| {
        notif.tick();
    }

    try std.testing.expectEqual(false, notif.dismissed);
    try std.testing.expectEqual(@as(u32, 0), notif.ticks_remaining);
}

test "Notification.tick countdown with timeout_ticks=3" {
    var notif = Notification.info("Test").withTimeout(3);

    // First tick: ticks_remaining becomes 2, still not dismissed
    notif.tick();
    try std.testing.expectEqual(@as(u32, 2), notif.ticks_remaining);
    try std.testing.expectEqual(false, notif.dismissed);

    // Second tick: ticks_remaining becomes 1, still not dismissed
    notif.tick();
    try std.testing.expectEqual(@as(u32, 1), notif.ticks_remaining);
    try std.testing.expectEqual(false, notif.dismissed);

    // Third tick: ticks_remaining becomes 0, now dismissed
    notif.tick();
    try std.testing.expectEqual(@as(u32, 0), notif.ticks_remaining);
    try std.testing.expectEqual(true, notif.dismissed);
}

test "Notification.tick after already dismissed prevents underflow" {
    var notif = Notification.success("Test").withTimeout(1);

    notif.tick();
    try std.testing.expectEqual(true, notif.dismissed);
    try std.testing.expectEqual(@as(u32, 0), notif.ticks_remaining);

    // Call tick again on already-dismissed notification
    // Should not panic/underflow; should remain dismissed
    notif.tick();
    try std.testing.expectEqual(true, notif.dismissed);
    try std.testing.expectEqual(@as(u32, 0), notif.ticks_remaining);
}

test "Notification.render after manual dismiss produces no output" {
    const allocator = std.testing.allocator;
    var notif = Notification.info("Test notification");
    notif.dismiss();

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    var buf = try Buffer.init(allocator, area.width, area.height);
    defer buf.deinit();

    try notif.render(&buf, area);

    // Count non-space cells; dismissed render should produce zero
    var non_empty: usize = 0;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getConst(@intCast(col), @intCast(row)).?;
            if (cell.char != ' ') non_empty += 1;
        }
    }

    try std.testing.expectEqual(@as(usize, 0), non_empty);
}

test "Notification.render after auto-dismiss via tick produces no output" {
    const allocator = std.testing.allocator;
    var notif = Notification.success("Test notification").withTimeout(1);

    // Tick once to trigger auto-dismiss
    notif.tick();
    try std.testing.expectEqual(true, notif.dismissed);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    var buf = try Buffer.init(allocator, area.width, area.height);
    defer buf.deinit();

    try notif.render(&buf, area);

    // Count non-space cells; dismissed render should produce zero
    var non_empty: usize = 0;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getConst(@intCast(col), @intCast(row)).?;
            if (cell.char != ' ') non_empty += 1;
        }
    }

    try std.testing.expectEqual(@as(usize, 0), non_empty);
}

test "Notification.render with persistent timeout (default) still renders normally" {
    const allocator = std.testing.allocator;
    var notif = Notification.warning("Test notification");

    // Verify defaults: timeout_ticks=0, dismissed=false
    try std.testing.expectEqual(@as(u32, 0), notif.timeout_ticks);
    try std.testing.expectEqual(false, notif.dismissed);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 20 };
    var buf = try Buffer.init(allocator, area.width, area.height);
    defer buf.deinit();

    try notif.render(&buf, area);

    // Should render normally (content visible)
    var non_empty: usize = 0;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getConst(@intCast(col), @intCast(row)).?;
            if (cell.char != ' ') non_empty += 1;
        }
    }

    try std.testing.expect(non_empty > 0);
}
