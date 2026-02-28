const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const Borders = @import("block.zig").Borders;

/// Popup widget for overlay content (help text, detail views, tooltips)
/// Renders floating content over the main interface at a specified position
///
/// Example: Help popup in top-right
/// ```zig
/// const help_text =
///     \\Keyboard Shortcuts:
///     \\  q - Quit
///     \\  ? - Toggle help
///     \\  ↑↓ - Navigate
/// ;
/// var popup = Popup.init(help_text);
/// popup.title = "Help";
/// popup.setPosition(100, 0); // Top-right corner
/// popup.setSize(30, 8);
///
/// try popup.render(&buf, area);
/// ```
///
/// Example: Centered tooltip
/// ```zig
/// var tooltip = Popup.init("Press Enter to confirm");
/// tooltip.setPosition(50, 50); // Center (50% x, 50% y)
/// tooltip.setSize(0, 0);       // Auto-size from content
/// tooltip.borders = Borders.none();
/// tooltip.style = Style{ .fg = .{ .indexed = 11 } }; // Yellow
///
/// try tooltip.render(&buf, area);
/// ```
///
/// Example: Detail view as percentage of screen
/// ```zig
/// const details = "Full item details...";
/// var popup = Popup.init(details);
/// popup.title = "Details";
/// popup.setSize(80, 60); // 80% width, 60% height
/// popup.setPosition(50, 50);
///
/// try popup.render(&buf, area);
/// ```
pub const Popup = struct {
    /// Content to display in the popup
    content: []const u8,
    /// X position (0-100 as percentage of parent width, or absolute if > 100)
    x_percent: u8,
    /// Y position (0-100 as percentage of parent height, or absolute if > 100)
    y_percent: u8,
    /// Width (0 = auto-size, 1-100 = percentage, >100 = absolute cells)
    width: u16,
    /// Height (0 = auto-size, 1-100 = percentage, >100 = absolute cells)
    height: u16,
    /// Optional title for the popup
    title: ?[]const u8,
    /// Border style
    borders: Borders,
    /// Style for the popup
    style: Style,

    pub fn init(content: []const u8) Popup {
        return Popup{
            .content = content,
            .x_percent = 50, // Center by default
            .y_percent = 50,
            .width = 0, // Auto-size
            .height = 0,
            .title = null,
            .borders = Borders.all(),
            .style = Style{},
        };
    }

    /// Set position as percentage (0-100)
    pub fn setPosition(self: *Popup, x_percent: u8, y_percent: u8) void {
        self.x_percent = @min(x_percent, 100);
        self.y_percent = @min(y_percent, 100);
    }

    /// Set size (0 = auto, 1-100 = percentage, >100 = absolute)
    pub fn setSize(self: *Popup, width: u16, height: u16) void {
        self.width = width;
        self.height = height;
    }

    /// Calculate popup area based on parent area and settings
    fn calculateArea(self: Popup, parent: Rect) Rect {
        // Calculate width
        const popup_width = if (self.width == 0)
            // Auto-size: content length + padding, capped at 80% of parent
            @min(@as(u16, @intCast(@min(self.content.len + 4, 1000))), parent.width * 80 / 100)
        else if (self.width <= 100)
            // Percentage
            parent.width * self.width / 100
        else
            // Absolute
            @min(self.width, parent.width);

        const popup_height = if (self.height == 0)
            // Auto-size: estimate lines + borders
            blk: {
                const content_width = if (popup_width > 4) popup_width -| 4 else 1;
                const lines = @as(u16, @intCast((self.content.len + content_width - 1) / content_width));
                break :blk @min(lines + 3, parent.height * 80 / 100);
            }
        else if (self.height <= 100)
            // Percentage
            parent.height * self.height / 100
        else
            // Absolute
            @min(self.height, parent.height);

        // Calculate position
        const x = if (self.x_percent <= 100)
            parent.x + (parent.width * self.x_percent / 100) -| (popup_width / 2)
        else
            parent.x + @min(@as(u16, self.x_percent) -| 100, parent.width -| popup_width);

        const y = if (self.y_percent <= 100)
            parent.y + (parent.height * self.y_percent / 100) -| (popup_height / 2)
        else
            parent.y + @min(@as(u16, self.y_percent) -| 100, parent.height -| popup_height);

        return Rect{
            .x = @min(x, parent.x + parent.width -| popup_width),
            .y = @min(y, parent.y + parent.height -| popup_height),
            .width = @min(popup_width, parent.width),
            .height = @min(popup_height, parent.height),
        };
    }

    /// Render the popup
    pub fn render(self: Popup, buf: *Buffer, parent_area: Rect) !void {
        if (parent_area.width == 0 or parent_area.height == 0) return;

        const area = self.calculateArea(parent_area);
        if (area.width == 0 or area.height == 0) return;

        // Draw border
        var block = Block{
            .borders = self.borders,
            .style = self.style,
            .title = self.title orelse "",
        };
        try block.render(buf, area);

        // Draw content
        const inner = block.inner(area);
        if (inner.width == 0 or inner.height == 0) return;

        // Simple line wrapping
        var line: usize = 0;
        var col: usize = 0;
        for (self.content) |ch| {
            if (line >= inner.height) break;

            if (ch == '\n') {
                line += 1;
                col = 0;
                continue;
            }

            if (col >= inner.width) {
                line += 1;
                col = 0;
                if (line >= inner.height) break;
            }

            const x = inner.x + @as(u16, @intCast(col));
            const y = inner.y + @as(u16, @intCast(line));
            try buf.setCell(x, y, ch, self.style);
            col += 1;
        }
    }
};

// Tests
test "Popup.init" {
    const popup = Popup.init("Hello, World!");

    try std.testing.expectEqualStrings("Hello, World!", popup.content);
    try std.testing.expectEqual(50, popup.x_percent);
    try std.testing.expectEqual(50, popup.y_percent);
    try std.testing.expectEqual(0, popup.width);
    try std.testing.expectEqual(0, popup.height);
}

test "Popup.setPosition" {
    var popup = Popup.init("Test");

    popup.setPosition(25, 75);
    try std.testing.expectEqual(25, popup.x_percent);
    try std.testing.expectEqual(75, popup.y_percent);

    // Should cap at 100
    popup.setPosition(150, 200);
    try std.testing.expectEqual(100, popup.x_percent);
    try std.testing.expectEqual(100, popup.y_percent);
}

test "Popup.setSize" {
    var popup = Popup.init("Test");

    popup.setSize(40, 20);
    try std.testing.expectEqual(40, popup.width);
    try std.testing.expectEqual(20, popup.height);

    popup.setSize(200, 100);
    try std.testing.expectEqual(200, popup.width);
    try std.testing.expectEqual(100, popup.height);
}

test "Popup.calculateArea centered" {
    var popup = Popup.init("Content");
    popup.setSize(20, 10);

    const parent = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const area = popup.calculateArea(parent);

    // Should be centered (50% x, 50% y)
    // Width 20, so x = 50 - 10 = 40
    // Height 10, so y = 25 - 5 = 20
    try std.testing.expectEqual(40, area.x);
    try std.testing.expectEqual(20, area.y);
    try std.testing.expectEqual(20, area.width);
    try std.testing.expectEqual(10, area.height);
}

test "Popup.calculateArea top-left" {
    var popup = Popup.init("Content");
    popup.setPosition(0, 0);
    popup.setSize(30, 15);

    const parent = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const area = popup.calculateArea(parent);

    // Should be at top-left corner (accounting for centering offset)
    try std.testing.expectEqual(0, area.x);
    try std.testing.expectEqual(0, area.y);
    try std.testing.expectEqual(30, area.width);
    try std.testing.expectEqual(15, area.height);
}

test "Popup.calculateArea percentage size" {
    var popup = Popup.init("Test");
    popup.setSize(50, 40); // 50% width, 40% height

    const parent = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const area = popup.calculateArea(parent);

    try std.testing.expectEqual(50, area.width); // 100 * 50%
    try std.testing.expectEqual(20, area.height); // 50 * 40%
}

test "Popup.calculateArea auto-size" {
    var popup = Popup.init("This is a test message");
    popup.setSize(0, 0); // Auto-size

    const parent = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    const area = popup.calculateArea(parent);

    // Width should be content + padding, capped
    try std.testing.expect(area.width > 0);
    try std.testing.expect(area.width <= parent.width);

    // Height should be reasonable
    try std.testing.expect(area.height >= 3); // At least borders + 1 line
    try std.testing.expect(area.height <= parent.height);
}

test "Popup.render simple" {
    const allocator = std.testing.allocator;
    var popup = Popup.init("Hello!");
    popup.setSize(20, 8);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 30 };
    var buf = try Buffer.init(allocator, area);
    defer buf.deinit();

    try popup.render(&buf, area);

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

test "Popup.render with title" {
    const allocator = std.testing.allocator;
    var popup = Popup.init("Popup content here");
    popup.title = "Info";
    popup.setSize(30, 10);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 40 };
    var buf = try Buffer.init(allocator, area);
    defer buf.deinit();

    try popup.render(&buf, area);

    // Should render title and content
    var found_content = false;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getCell(@intCast(col), @intCast(row));
            if (cell.char == 'P' or cell.char == 'o' or cell.char == 'p') {
                found_content = true;
            }
        }
    }

    try std.testing.expect(found_content);
}

test "Popup.render multiline" {
    const allocator = std.testing.allocator;
    const content = "Line 1\nLine 2\nLine 3";
    var popup = Popup.init(content);
    popup.setSize(25, 12);

    const area = Rect{ .x = 0, .y = 0, .width = 70, .height = 35 };
    var buf = try Buffer.init(allocator, area);
    defer buf.deinit();

    try popup.render(&buf, area);

    // Should handle newlines
    var found_lines = false;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getCell(@intCast(col), @intCast(row));
            if (cell.char == 'L' or cell.char == 'i' or cell.char == 'n' or cell.char == 'e') {
                found_lines = true;
            }
        }
    }

    try std.testing.expect(found_lines);
}

test "Popup.render empty area" {
    const allocator = std.testing.allocator;
    const popup = Popup.init("Test");

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    var buf = try Buffer.init(allocator, Rect{ .x = 0, .y = 0, .width = 10, .height = 10 });
    defer buf.deinit();

    // Should not crash
    try popup.render(&buf, area);
}

test "Popup.render constrained parent" {
    const allocator = std.testing.allocator;
    var popup = Popup.init("Very long content that should be constrained");
    popup.setSize(200, 100); // Request larger than parent

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 };
    var buf = try Buffer.init(allocator, area);
    defer buf.deinit();

    try popup.render(&buf, area);

    // Should be clamped to parent size
    const calc_area = popup.calculateArea(area);
    try std.testing.expect(calc_area.width <= area.width);
    try std.testing.expect(calc_area.height <= area.height);
}
