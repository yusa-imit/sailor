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

    pub fn icon(self: Level) u21 {
        return switch (self) {
            .info => 'ℹ',
            .success => '✓',
            .warning => '⚠',
            .error_ => '✗',
        };
    }

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
            buf.setChar(x, y, self.level.icon(), notif_style);
            x += 1;

            // Space after icon
            if (x < inner_area.x + inner_area.width) {
                buf.setChar(x, y, ' ', notif_style);
                x += 1;
            }
        }

        // Draw message
        for (self.message) |ch| {
            if (x >= inner_area.x + inner_area.width) break;
            buf.setChar(x, y, ch, notif_style);
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
    var buf = try Buffer.init(allocator, area);
    defer buf.deinit();

    try notif.render(&buf, area);

    // Should render without errors
    var non_empty: usize = 0;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getCell(@intCast(col), @intCast(row));
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
    var buf = try Buffer.init(allocator, area);
    defer buf.deinit();

    try notif.render(&buf, area);

    // Should render title and message
    var found_text = false;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getCell(@intCast(col), @intCast(row));
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
    var buf = try Buffer.init(allocator, area);
    defer buf.deinit();

    try notif.render(&buf, area);

    // Should still render message
    var found_message = false;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getCell(@intCast(col), @intCast(row));
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
        var buf = try Buffer.init(allocator, area);
        defer buf.deinit();

        // Should render at all positions without error
        try notif.render(&buf, area);
    }
}

test "Notification.render empty area" {
    const allocator = std.testing.allocator;
    const notif = Notification.err("Error");

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    var buf = try Buffer.init(allocator, Rect{ .x = 0, .y = 0, .width = 10, .height = 10 });
    defer buf.deinit();

    // Should not crash
    try notif.render(&buf, area);
}
