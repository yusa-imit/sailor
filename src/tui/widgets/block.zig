//! Block widget — the foundation for bordered, titled containers.
//!
//! Block provides borders, titles, and padding for other widgets. It's the most
//! commonly used widget for creating structured layouts with visual boundaries.
//!
//! ## Features
//! - Configurable borders (top, right, bottom, left, or any combination)
//! - Title positioning (top/bottom, left/center/right)
//! - Multiple border styles (single, double, rounded, thick)
//! - Padding control for inner content
//! - Fluent builder API for easy configuration
//!
//! ## Usage
//! ```zig
//! const block = Block{
//!     .borders = .all,
//!     .border_set = BoxSet.rounded,
//!     .title = "My Widget",
//!     .title_position = .top_center,
//! };
//! block.render(buf, area);
//! const inner = block.inner(area); // Get area for child content
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const symbols_mod = @import("../symbols.zig");
const BoxSet = symbols_mod.BoxSet;

/// Border configuration for a block
pub const Borders = packed struct {
    top: bool = false,
    right: bool = false,
    bottom: bool = false,
    left: bool = false,

    /// All borders enabled
    pub const all: Borders = .{ .top = true, .right = true, .bottom = true, .left = true };

    /// No borders
    pub const none: Borders = .{};

    /// Only top and bottom borders
    pub const horizontal: Borders = .{ .top = true, .bottom = true };

    /// Only left and right borders
    pub const vertical: Borders = .{ .left = true, .right = true };

    /// Check if any border is enabled
    pub fn any(self: Borders) bool {
        return self.top or self.right or self.bottom or self.left;
    }
};

/// Title position within a block
pub const TitlePosition = enum {
    top_left,
    top_center,
    top_right,
    bottom_left,
    bottom_center,
    bottom_right,
};

/// Block widget - provides borders, title, and padding
pub const Block = struct {
    borders: Borders = Borders.all,
    border_style: Style = .{},
    border_set: BoxSet = BoxSet.single,
    title: ?[]const u8 = null,
    title_position: TitlePosition = .top_left,
    title_style: Style = .{},
    padding_top: u16 = 0,
    padding_right: u16 = 0,
    padding_bottom: u16 = 0,
    padding_left: u16 = 0,

    /// Set which borders to display
    pub fn withBorders(self: Block, new_borders: Borders) Block {
        var result = self;
        result.borders = new_borders;
        return result;
    }

    /// Set border style
    pub fn withBorderStyle(self: Block, new_style: Style) Block {
        var result = self;
        result.border_style = new_style;
        return result;
    }

    /// Set border character set
    pub fn withBorderSet(self: Block, new_set: BoxSet) Block {
        var result = self;
        result.border_set = new_set;
        return result;
    }

    /// Set title text and position
    pub fn withTitle(self: Block, text: []const u8, position: TitlePosition) Block {
        var result = self;
        result.title = text;
        result.title_position = position;
        return result;
    }

    /// Set title style
    pub fn withTitleStyle(self: Block, new_style: Style) Block {
        var result = self;
        result.title_style = new_style;
        return result;
    }

    /// Set padding (all sides)
    pub fn withPadding(self: Block, padding: u16) Block {
        var result = self;
        result.padding_top = padding;
        result.padding_right = padding;
        result.padding_bottom = padding;
        result.padding_left = padding;
        return result;
    }

    /// Set padding for specific sides
    pub fn withPaddingCustom(self: Block, top: u16, right: u16, bottom: u16, left: u16) Block {
        var result = self;
        result.padding_top = top;
        result.padding_right = right;
        result.padding_bottom = bottom;
        result.padding_left = left;
        return result;
    }

    /// Calculate the inner area after accounting for borders and padding
    pub fn inner(self: Block, area: Rect) Rect {
        var result = area;

        // Account for borders
        if (self.borders.left) {
            result.x += 1;
            result.width -|= 1;
        }
        if (self.borders.right) {
            result.width -|= 1;
        }
        if (self.borders.top) {
            result.y += 1;
            result.height -|= 1;
        }
        if (self.borders.bottom) {
            result.height -|= 1;
        }

        // Account for padding
        result.x += self.padding_left;
        result.width -|= self.padding_left + self.padding_right;
        result.y += self.padding_top;
        result.height -|= self.padding_top + self.padding_bottom;

        // Ensure width and height don't underflow
        if (result.width == 0 or result.height == 0) {
            return Rect{ .x = result.x, .y = result.y, .width = 0, .height = 0 };
        }

        return result;
    }

    /// Render the block borders and title
    pub fn render(self: Block, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Render borders
        if (self.borders.any()) {
            self.renderBorders(buf, area);
        }

        // Render title if present
        if (self.title) |title_text| {
            self.renderTitle(buf, area, title_text);
        }
    }

    /// Render border lines
    fn renderBorders(self: Block, buf: *Buffer, area: Rect) void {
        const symbols = self.border_set;

        // Helper to decode first UTF-8 codepoint
        const decodeUtf8 = struct {
            fn decode(str: []const u8) u21 {
                if (str.len == 0) return ' ';
                const len = std.unicode.utf8ByteSequenceLength(str[0]) catch return str[0];
                return std.unicode.utf8Decode(str[0..len]) catch str[0];
            }
        }.decode;

        // Top border
        if (self.borders.top) {
            const y = area.y;
            if (self.borders.left) {
                buf.setChar(area.x, y, decodeUtf8(symbols.top_left), self.border_style);
            }
            var x: u16 = area.x + @intFromBool(self.borders.left);
            const end_x = area.x + area.width -| @intFromBool(self.borders.right);
            const h_char = decodeUtf8(symbols.horizontal);
            while (x < end_x) : (x += 1) {
                buf.setChar(x, y, h_char, self.border_style);
            }
            if (self.borders.right and area.width > 0) {
                buf.setChar(area.x + area.width - 1, y, decodeUtf8(symbols.top_right), self.border_style);
            }
        }

        // Bottom border
        if (self.borders.bottom and area.height > 0) {
            const y = area.y + area.height - 1;
            if (self.borders.left) {
                buf.setChar(area.x, y, decodeUtf8(symbols.bottom_left), self.border_style);
            }
            var x: u16 = area.x + @intFromBool(self.borders.left);
            const end_x = area.x + area.width -| @intFromBool(self.borders.right);
            const h_char = decodeUtf8(symbols.horizontal);
            while (x < end_x) : (x += 1) {
                buf.setChar(x, y, h_char, self.border_style);
            }
            if (self.borders.right and area.width > 0) {
                buf.setChar(area.x + area.width - 1, y, decodeUtf8(symbols.bottom_right), self.border_style);
            }
        }

        // Left border
        if (self.borders.left) {
            const v_char = decodeUtf8(symbols.vertical);
            var y: u16 = area.y + @intFromBool(self.borders.top);
            const end_y = area.y + area.height -| @intFromBool(self.borders.bottom);
            while (y < end_y) : (y += 1) {
                buf.setChar(area.x, y, v_char, self.border_style);
            }
        }

        // Right border
        if (self.borders.right and area.width > 0) {
            const x = area.x + area.width - 1;
            const v_char = decodeUtf8(symbols.vertical);
            var y: u16 = area.y + @intFromBool(self.borders.top);
            const end_y = area.y + area.height -| @intFromBool(self.borders.bottom);
            while (y < end_y) : (y += 1) {
                buf.setChar(x, y, v_char, self.border_style);
            }
        }
    }

    /// Render title text
    fn renderTitle(self: Block, buf: *Buffer, area: Rect, title_text: []const u8) void {
        // Calculate title position
        const title_y = switch (self.title_position) {
            .top_left, .top_center, .top_right => if (self.borders.top) area.y else return,
            .bottom_left, .bottom_center, .bottom_right => blk: {
                if (!self.borders.bottom or area.height == 0) return;
                break :blk area.y + area.height - 1;
            },
        };

        // Calculate available width for title
        const border_offset: u16 = @as(u16, @intFromBool(self.borders.left)) + @as(u16, @intFromBool(self.borders.right));
        if (area.width < border_offset + 2) return; // Need space for borders + title

        const available_width = area.width -| border_offset -| 2; // -2 for padding around title
        const title_len = @min(title_text.len, available_width);
        if (title_len == 0) return;

        const title_x = switch (self.title_position) {
            .top_left, .bottom_left => area.x + @intFromBool(self.borders.left) + 1,
            .top_center, .bottom_center => blk: {
                const total_width = area.width -| border_offset;
                if (title_len >= total_width) {
                    break :blk area.x + @intFromBool(self.borders.left) + 1;
                }
                const offset = (total_width -| title_len) / 2;
                break :blk area.x + @intFromBool(self.borders.left) + offset;
            },
            .top_right, .bottom_right => blk: {
                const safe_width = area.width -| border_offset;
                if (title_len + 1 > safe_width) {
                    break :blk area.x + @intFromBool(self.borders.left) + 1;
                }
                break :blk area.x + area.width -| @intFromBool(self.borders.right) -| title_len -| 1;
            },
        };

        // Render title
        buf.setString(title_x, title_y, title_text[0..title_len], self.title_style);
    }
};

// Tests
test "Block.init creates default block" {
    const block = (Block{});
    try std.testing.expect(block.borders.top);
    try std.testing.expect(block.borders.right);
    try std.testing.expect(block.borders.bottom);
    try std.testing.expect(block.borders.left);
}

test "Block.withBorders sets borders" {
    const block = (Block{}).withBorders(Borders.horizontal);
    try std.testing.expect(block.borders.top);
    try std.testing.expect(block.borders.bottom);
    try std.testing.expect(!block.borders.left);
    try std.testing.expect(!block.borders.right);
}

test "Block.inner calculates inner area with all borders" {
    const block = (Block{});
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const inner_area = block.inner(area);

    try std.testing.expectEqual(@as(u16, 1), inner_area.x);
    try std.testing.expectEqual(@as(u16, 1), inner_area.y);
    try std.testing.expectEqual(@as(u16, 8), inner_area.width);
    try std.testing.expectEqual(@as(u16, 8), inner_area.height);
}

test "Block.inner calculates inner area with padding" {
    const block = (Block{}).withPadding(1);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const inner_area = block.inner(area);

    try std.testing.expectEqual(@as(u16, 2), inner_area.x); // border + padding
    try std.testing.expectEqual(@as(u16, 2), inner_area.y);
    try std.testing.expectEqual(@as(u16, 6), inner_area.width); // width - (borders + padding) * 2
    try std.testing.expectEqual(@as(u16, 6), inner_area.height);
}

test "Block.inner handles no borders" {
    const block = (Block{}).withBorders(Borders.none);
    const area = Rect{ .x = 5, .y = 5, .width = 20, .height = 15 };
    const inner_area = block.inner(area);

    try std.testing.expectEqual(@as(u16, 5), inner_area.x);
    try std.testing.expectEqual(@as(u16, 5), inner_area.y);
    try std.testing.expectEqual(@as(u16, 20), inner_area.width);
    try std.testing.expectEqual(@as(u16, 15), inner_area.height);
}

test "Block.inner handles custom padding" {
    const block = (Block{})
        .withBorders(Borders.none)
        .withPaddingCustom(1, 2, 3, 4);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 20 };
    const inner_area = block.inner(area);

    try std.testing.expectEqual(@as(u16, 4), inner_area.x); // left padding
    try std.testing.expectEqual(@as(u16, 1), inner_area.y); // top padding
    try std.testing.expectEqual(@as(u16, 14), inner_area.width); // 20 - (4 left + 2 right)
    try std.testing.expectEqual(@as(u16, 16), inner_area.height); // 20 - (1 top + 3 bottom)
}

test "Block.render draws all borders" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const block = (Block{});
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    block.render(&buf, area);

    // Check corners
    const top_left = buf.get(0, 0).?;
    try std.testing.expectEqual(@as(u21, '┌'), top_left.char);

    const top_right = buf.get(9, 0).?;
    try std.testing.expectEqual(@as(u21, '┐'), top_right.char);

    const bottom_left = buf.get(0, 4).?;
    try std.testing.expectEqual(@as(u21, '└'), bottom_left.char);

    const bottom_right = buf.get(9, 4).?;
    try std.testing.expectEqual(@as(u21, '┘'), bottom_right.char);

    // Check horizontal border
    const top_border = buf.get(1, 0).?;
    try std.testing.expectEqual(@as(u21, '─'), top_border.char);

    // Check vertical border
    const left_border = buf.get(0, 1).?;
    try std.testing.expectEqual(@as(u21, '│'), left_border.char);
}

test "Block.render draws horizontal borders only" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const block = (Block{}).withBorders(Borders.horizontal);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    block.render(&buf, area);

    // Top border should exist
    const top = buf.get(0, 0).?;
    try std.testing.expectEqual(@as(u21, '─'), top.char);

    // Bottom border should exist
    const bottom = buf.get(0, 4).?;
    try std.testing.expectEqual(@as(u21, '─'), bottom.char);

    // Left side should be empty (space)
    const left = buf.get(0, 2).?;
    try std.testing.expectEqual(@as(u21, ' '), left.char);
}

test "Block.render with title at top left" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const block = (Block{}).withTitle("Test", .top_left);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    block.render(&buf, area);

    // Check title text
    try std.testing.expectEqual(@as(u21, 'T'), buf.get(2, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'e'), buf.get(3, 0).?.char);
    try std.testing.expectEqual(@as(u21, 's'), buf.get(4, 0).?.char);
    try std.testing.expectEqual(@as(u21, 't'), buf.get(5, 0).?.char);
}

test "Block.render with title at top center" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const block = (Block{}).withTitle("Hi", .top_center);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    block.render(&buf, area);

    // Title "Hi" (2 chars) in 18 available chars (20 - 2 borders) should be centered
    // Center position: (18 - 2) / 2 = 8, so start at 1 (border) + 8 = 9
    try std.testing.expectEqual(@as(u21, 'H'), buf.get(9, 0).?.char);
    try std.testing.expectEqual(@as(u21, 'i'), buf.get(10, 0).?.char);
}

test "Block.render with title at bottom right" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 20, 5);
    defer buf.deinit();

    const block = (Block{}).withTitle("End", .bottom_right);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 5 };
    block.render(&buf, area);

    // Title at bottom right: width=20, border=1, title_len=3, padding=1
    // Position: 20 - 1 (border) - 3 (title) - 1 (padding) = 15
    try std.testing.expectEqual(@as(u21, 'E'), buf.get(15, 4).?.char);
    try std.testing.expectEqual(@as(u21, 'n'), buf.get(16, 4).?.char);
    try std.testing.expectEqual(@as(u21, 'd'), buf.get(17, 4).?.char);
}

test "Block.render handles empty area" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const block = (Block{});
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    block.render(&buf, area); // Should not crash

    // All cells should remain as default
    try std.testing.expectEqual(@as(u21, ' '), buf.get(0, 0).?.char);
}

test "Block.render with different border sets" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 5);
    defer buf.deinit();

    const block = (Block{}).withBorderSet(BoxSet.double);
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 5 };
    block.render(&buf, area);

    // Check double-line corners
    try std.testing.expectEqual(@as(u21, '╔'), buf.get(0, 0).?.char);
    try std.testing.expectEqual(@as(u21, '╗'), buf.get(9, 0).?.char);
    try std.testing.expectEqual(@as(u21, '╚'), buf.get(0, 4).?.char);
    try std.testing.expectEqual(@as(u21, '╝'), buf.get(9, 4).?.char);
}

test "Borders.any returns true if any border enabled" {
    const all = Borders.all;
    try std.testing.expect(all.any());

    const none = Borders.none;
    try std.testing.expect(!none.any());

    const horizontal = Borders.horizontal;
    try std.testing.expect(horizontal.any());
}
