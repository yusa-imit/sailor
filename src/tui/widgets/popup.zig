//! Popup widget for overlay content such as help text, detail views, and tooltips.
const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Cell = @import("../buffer.zig").Cell;
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
/// tooltip.borders = Borders.none;
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

    /// Create centered popup with text content (50% x, 50% y, auto-size).
    pub fn init(content: []const u8) Popup {
        return Popup{
            .content = content,
            .x_percent = 50, // Center by default
            .y_percent = 50,
            .width = 0, // Auto-size
            .height = 0,
            .title = null,
            .borders = Borders.all,
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
            } else if (self.height <= 100)
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
            .border_style = self.style,
            .title = self.title orelse "",
        };
        block.render(buf, area);

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
            buf.set(x, y, Cell.init(ch, self.style));
            col += 1;
        }
    }
};

// Tests

const testing = std.testing;

fn rect(x: u16, y: u16, width: u16, height: u16) Rect {
    return Rect{ .x = x, .y = y, .width = width, .height = height };
}

/// Assert that the cells of row `y` starting at `x` spell exactly `text` (ASCII only).
fn expectRow(buf: Buffer, x: u16, y: u16, text: []const u8) !void {
    for (text, 0..) |ch, i| {
        try testing.expectEqual(@as(u21, ch), buf.getChar(x + @as(u16, @intCast(i)), y));
    }
}

/// Assert that every cell of the buffer is the default blank cell.
fn expectBlank(buf: Buffer) !void {
    for (buf.cells) |cell| {
        try testing.expect(cell.eql(Cell{}));
    }
}

test "Popup.init defaults to centered auto-sized bordered popup" {
    const popup = Popup.init("Hello, World!");

    try testing.expectEqualStrings("Hello, World!", popup.content);
    try testing.expectEqual(@as(u8, 50), popup.x_percent);
    try testing.expectEqual(@as(u8, 50), popup.y_percent);
    try testing.expectEqual(@as(u16, 0), popup.width);
    try testing.expectEqual(@as(u16, 0), popup.height);
    try testing.expectEqual(@as(?[]const u8, null), popup.title);
    try testing.expect(popup.borders.top and popup.borders.right);
    try testing.expect(popup.borders.bottom and popup.borders.left);
}

test "Popup.setPosition stores percentages and clamps above 100" {
    var popup = Popup.init("Test");

    popup.setPosition(25, 75);
    try testing.expectEqual(@as(u8, 25), popup.x_percent);
    try testing.expectEqual(@as(u8, 75), popup.y_percent);

    popup.setPosition(150, 200);
    try testing.expectEqual(@as(u8, 100), popup.x_percent);
    try testing.expectEqual(@as(u8, 100), popup.y_percent);

    popup.setPosition(100, 0);
    try testing.expectEqual(@as(u8, 100), popup.x_percent);
    try testing.expectEqual(@as(u8, 0), popup.y_percent);
}

test "Popup.setSize stores values verbatim including absolute sizes above 100" {
    var popup = Popup.init("Test");

    popup.setSize(40, 20);
    try testing.expectEqual(@as(u16, 40), popup.width);
    try testing.expectEqual(@as(u16, 20), popup.height);

    popup.setSize(200, 101);
    try testing.expectEqual(@as(u16, 200), popup.width);
    try testing.expectEqual(@as(u16, 101), popup.height);
}

test "Popup.calculateArea centers a percentage-sized popup" {
    var popup = Popup.init("Content");
    popup.setSize(20, 10); // 20% of 100 = 20 wide, 10% of 50 = 5 high

    const area = popup.calculateArea(rect(0, 0, 100, 50));

    // x = 50 - 20/2, y = 25 - 5/2
    try testing.expectEqual(rect(40, 23, 20, 5), area);
}

test "Popup.calculateArea top-left anchors at the parent origin" {
    var popup = Popup.init("Content");
    popup.setPosition(0, 0);
    popup.setSize(30, 15);

    const area = popup.calculateArea(rect(0, 0, 100, 50));

    try testing.expectEqual(rect(0, 0, 30, 7), area); // 15% of 50 = 7 (floor)
}

test "Popup.calculateArea bottom-right anchor is clamped inside the parent" {
    var popup = Popup.init("Content");
    popup.setPosition(100, 100);
    popup.setSize(20, 10);

    const area = popup.calculateArea(rect(0, 0, 100, 50));

    try testing.expectEqual(rect(80, 45, 20, 5), area);
    try testing.expectEqual(@as(u32, 100), @as(u32, area.x) + area.width);
    try testing.expectEqual(@as(u32, 50), @as(u32, area.y) + area.height);
}

test "Popup.calculateArea honours the parent origin" {
    var popup = Popup.init("Content");
    popup.setSize(20, 10);

    const area = popup.calculateArea(rect(10, 5, 100, 50));

    // Center of parent is (60, 30); popup is 20x5 so top-left is (50, 28).
    try testing.expectEqual(rect(50, 28, 20, 5), area);
}

test "Popup.calculateArea percentage size uses floor division of the parent" {
    var popup = Popup.init("Test");
    popup.setSize(50, 40);

    const area = popup.calculateArea(rect(0, 0, 101, 51));

    try testing.expectEqual(@as(u16, 50), area.width); // 101 * 50 / 100
    try testing.expectEqual(@as(u16, 20), area.height); // 51 * 40 / 100
}

test "Popup.calculateArea auto-size fits content plus padding" {
    var popup = Popup.init("This is a test message"); // 22 bytes
    popup.setSize(0, 0);

    const area = popup.calculateArea(rect(0, 0, 80, 40));

    // width = 22 + 4, height = 1 line + 3, centered: x = 40 - 13, y = 20 - 2
    try testing.expectEqual(rect(27, 18, 26, 4), area);
}

test "Popup.calculateArea auto-size is capped at 80 percent of the parent" {
    const long = "x" ** 200;
    var popup = Popup.init(long);
    popup.setSize(0, 0);

    const area = popup.calculateArea(rect(0, 0, 50, 20));

    try testing.expectEqual(@as(u16, 40), area.width); // 50 * 80%
    // 200 bytes at content width 40 - 4 = 36 => 6 lines, + 3 for borders.
    try testing.expectEqual(@as(u16, 9), area.height);
}

test "Popup.calculateArea absolute size above 100 is clamped to the parent" {
    var popup = Popup.init("Content");
    popup.setSize(150, 101);

    const small = popup.calculateArea(rect(0, 0, 40, 20));
    try testing.expectEqual(rect(0, 0, 40, 20), small);

    popup.setSize(120, 110);
    const large = popup.calculateArea(rect(0, 0, 200, 150));
    try testing.expectEqual(@as(u16, 120), large.width);
    try testing.expectEqual(@as(u16, 110), large.height);
}

test "Popup.calculateArea absolute position above 100 offsets from the parent origin" {
    var popup = Popup.init("Content");
    popup.setSize(20, 10); // 20x5 in a 100x50 parent
    popup.x_percent = 110; // setPosition clamps, so write the field directly
    popup.y_percent = 120;

    const area = popup.calculateArea(rect(0, 0, 100, 50));
    try testing.expectEqual(rect(10, 20, 20, 5), area);

    popup.x_percent = 250; // beyond the parent: clamped so the popup stays inside
    popup.y_percent = 250;
    const clamped = popup.calculateArea(rect(0, 0, 100, 50));
    try testing.expectEqual(rect(80, 45, 20, 5), clamped);
}

test "Popup.render draws a bordered box and content at the computed area" {
    var popup = Popup.init("Hello!");
    popup.setSize(50, 50);

    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    const parent = rect(0, 0, 60, 20);
    try popup.render(&buf, parent);
    buf.check_invariants();

    // Area is (15, 5, 30, 10): corners at (15,5) .. (44,14).
    try testing.expectEqual(rect(15, 5, 30, 10), popup.calculateArea(parent));
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(15, 5));
    try testing.expectEqual(@as(u21, '┐'), buf.getChar(44, 5));
    try testing.expectEqual(@as(u21, '└'), buf.getChar(15, 14));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(44, 14));
    try testing.expectEqual(@as(u21, '─'), buf.getChar(16, 5));
    try testing.expectEqual(@as(u21, '─'), buf.getChar(30, 14));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(15, 9));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(44, 9));

    // Content starts in the inner area's top-left cell (16, 6).
    try expectRow(buf, 16, 6, "Hello!");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(22, 6));

    // Nothing is drawn outside the popup.
    try testing.expectEqual(@as(u21, ' '), buf.getChar(14, 5));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(45, 14));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(15, 4));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(15, 15));
}

test "Popup.render draws the title in the top border" {
    var popup = Popup.init("Popup content here");
    popup.title = "Info";
    popup.setSize(50, 50);

    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    try popup.render(&buf, rect(0, 0, 60, 20));

    // Popup area is (15, 5, 30, 10); title sits one cell right of the top-left corner.
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(15, 5));
    try testing.expectEqual(@as(u21, '─'), buf.getChar(16, 5));
    try expectRow(buf, 17, 5, "Info");
    try testing.expectEqual(@as(u21, '─'), buf.getChar(21, 5));
    try expectRow(buf, 16, 6, "Popup content here");
}

test "Popup.render splits content on newlines" {
    var popup = Popup.init("Line 1\nLine 2\nLine 3");
    popup.setSize(50, 50);

    var buf = try Buffer.init(testing.allocator, 60, 20);
    defer buf.deinit();
    try popup.render(&buf, rect(0, 0, 60, 20));

    try expectRow(buf, 16, 6, "Line 1");
    try expectRow(buf, 16, 7, "Line 2");
    try expectRow(buf, 16, 8, "Line 3");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(22, 6)); // the newline is not drawn
    try testing.expectEqual(@as(u21, ' '), buf.getChar(16, 9));
}

test "Popup.render wraps long lines at the inner width and drops overflow" {
    // Parent 20x10, 50% x 50% => popup (5, 3, 10, 5); inner (6, 4, 8, 3).
    var popup = Popup.init("ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    popup.setSize(50, 50);

    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    try popup.render(&buf, rect(0, 0, 20, 10));

    try expectRow(buf, 6, 4, "ABCDEFGH");
    try expectRow(buf, 6, 5, "IJKLMNOP");
    try expectRow(buf, 6, 6, "QRSTUVWX"); // "YZ" does not fit: only 3 inner rows
    // Borders around the inner area are untouched by the overflow.
    try testing.expectEqual(@as(u21, '│'), buf.getChar(5, 5));
    try testing.expectEqual(@as(u21, '│'), buf.getChar(14, 5));
    try testing.expectEqual(@as(u21, '└'), buf.getChar(5, 7));
    try testing.expectEqual(@as(u21, '─'), buf.getChar(6, 7));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(14, 7));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(15, 6));
}

test "Popup.render drops lines beyond the inner height" {
    var popup = Popup.init("a\nb\nc\nd\ne");
    popup.setSize(50, 50);

    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    try popup.render(&buf, rect(0, 0, 20, 10)); // inner is (6, 4, 8, 3)

    try expectRow(buf, 6, 4, "a");
    try expectRow(buf, 6, 5, "b");
    try expectRow(buf, 6, 6, "c");
    try testing.expectEqual(@as(u21, '└'), buf.getChar(5, 7));
    try testing.expectEqual(@as(u21, '─'), buf.getChar(6, 7));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(6, 8));
}

test "Popup.render without borders puts content at the popup origin" {
    var popup = Popup.init("Press Enter");
    popup.borders = Borders.none;
    popup.setSize(50, 50);

    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    try popup.render(&buf, rect(0, 0, 20, 10)); // popup area (5, 3, 10, 5)

    try expectRow(buf, 5, 3, "Press Ente"); // wrapped at width 10
    try expectRow(buf, 5, 4, "r");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(4, 3));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(6, 4));
}

test "Popup.render applies the style to border and content cells" {
    const style = Style{ .bold = true, .fg = .{ .indexed = 11 } };
    var popup = Popup.init("Hi");
    popup.style = style;
    popup.setSize(50, 50);

    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();
    try popup.render(&buf, rect(0, 0, 20, 10));

    try testing.expect(std.meta.eql(style, buf.getStyle(5, 3))); // corner
    try testing.expect(std.meta.eql(style, buf.getStyle(6, 4))); // 'H'
    try testing.expect(std.meta.eql(style, buf.getStyle(7, 4))); // 'i'
    try testing.expect(!buf.getStyle(8, 4).bold); // untouched blank interior
}

test "Popup.render with an empty parent leaves the buffer untouched" {
    const popup = Popup.init("Test");

    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    try popup.render(&buf, rect(0, 0, 0, 0));
    try expectBlank(buf);

    try popup.render(&buf, rect(0, 0, 0, 10));
    try popup.render(&buf, rect(0, 0, 10, 0));
    try expectBlank(buf);
}

test "Popup.render rounding to a zero-sized popup draws nothing" {
    var popup = Popup.init("Test");
    popup.setSize(1, 1); // 1% of 10 floors to 0

    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    try popup.render(&buf, rect(0, 0, 10, 10));

    try expectBlank(buf);
}

test "Popup.render too small for content draws borders only" {
    var popup = Popup.init("X");
    popup.setSize(20, 20); // 2x2 popup: borders leave no inner area

    var buf = try Buffer.init(testing.allocator, 10, 10);
    defer buf.deinit();
    try popup.render(&buf, rect(0, 0, 10, 10));

    try testing.expectEqual(@as(u21, '┌'), buf.getChar(4, 4));
    try testing.expectEqual(@as(u21, '┐'), buf.getChar(5, 4));
    try testing.expectEqual(@as(u21, '└'), buf.getChar(4, 5));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(5, 5));
    for (buf.cells) |cell| try testing.expect(cell.char != 'X');
}

test "Popup.render larger than parent is clamped to the parent bounds" {
    var popup = Popup.init("Very long content that should be constrained");
    popup.setSize(200, 100);

    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    const parent = rect(0, 0, 40, 20);
    try popup.render(&buf, parent);

    try testing.expectEqual(parent, popup.calculateArea(parent));
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '┐'), buf.getChar(39, 0));
    try testing.expectEqual(@as(u21, '└'), buf.getChar(0, 19));
    try testing.expectEqual(@as(u21, '┘'), buf.getChar(39, 19));
    // Inner width is 38, so the 44-byte content wraps after 38 bytes.
    try expectRow(buf, 1, 1, "Very long content that should be const");
    try expectRow(buf, 1, 2, "rained");
}

test "Popup.render into an offset parent leaves cells outside the parent blank" {
    var popup = Popup.init("ok");
    popup.setSize(50, 50);

    var buf = try Buffer.init(testing.allocator, 40, 20);
    defer buf.deinit();
    // Parent (10, 5, 20, 10): popup 10x5 at x = 10+10-5 = 15, y = 5+5-2 = 8.
    try popup.render(&buf, rect(10, 5, 20, 10));

    try testing.expectEqual(@as(u21, '┌'), buf.getChar(15, 8));
    try expectRow(buf, 16, 9, "ok");
    try testing.expectEqual(@as(u21, ' '), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(14, 8));
}

test "Popup.render clips silently when the buffer is smaller than the parent" {
    var popup = Popup.init("clip");
    popup.setSize(100, 100);

    var buf = try Buffer.init(testing.allocator, 6, 4);
    defer buf.deinit();
    try popup.render(&buf, rect(0, 0, 20, 10));
    buf.check_invariants();

    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '─'), buf.getChar(5, 0));
    try expectRow(buf, 1, 1, "clip");
}
