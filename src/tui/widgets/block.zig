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

    /// Set title text and position (builder pattern)
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
            result.x +|= 1;
            result.width -|= 1;
        }
        if (self.borders.right) {
            result.width -|= 1;
        }
        if (self.borders.top) {
            result.y +|= 1;
            result.height -|= 1;
        }
        if (self.borders.bottom) {
            result.height -|= 1;
        }

        // Account for padding
        result.x +|= self.padding_left;
        result.width -|= self.padding_left +| self.padding_right;
        result.y +|= self.padding_top;
        result.height -|= self.padding_top +| self.padding_bottom;

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
                buf.set(area.x, y, .{ .char = decodeUtf8(symbols.top_left), .style = self.border_style });
            }
            var x: u16 = area.x +| @intFromBool(self.borders.left);
            const end_x = (area.x +| area.width) -| @intFromBool(self.borders.right);
            const h_char = decodeUtf8(symbols.horizontal);
            while (x < end_x) : (x += 1) {
                buf.set(x, y, .{ .char = h_char, .style = self.border_style });
            }
            if (self.borders.right and area.width > 0) {
                buf.set((area.x +| area.width) -| 1, y, .{ .char = decodeUtf8(symbols.top_right), .style = self.border_style });
            }
        }

        // Bottom border
        if (self.borders.bottom and area.height > 0) {
            const y = (area.y +| area.height) -| 1;
            if (self.borders.left) {
                buf.set(area.x, y, .{ .char = decodeUtf8(symbols.bottom_left), .style = self.border_style });
            }
            var x: u16 = area.x +| @intFromBool(self.borders.left);
            const end_x = (area.x +| area.width) -| @intFromBool(self.borders.right);
            const h_char = decodeUtf8(symbols.horizontal);
            while (x < end_x) : (x += 1) {
                buf.set(x, y, .{ .char = h_char, .style = self.border_style });
            }
            if (self.borders.right and area.width > 0) {
                buf.set((area.x +| area.width) -| 1, y, .{ .char = decodeUtf8(symbols.bottom_right), .style = self.border_style });
            }
        }

        // Left border
        if (self.borders.left) {
            const v_char = decodeUtf8(symbols.vertical);
            var y: u16 = area.y +| @intFromBool(self.borders.top);
            const end_y = (area.y +| area.height) -| @intFromBool(self.borders.bottom);
            while (y < end_y) : (y += 1) {
                buf.set(area.x, y, .{ .char = v_char, .style = self.border_style });
            }
        }

        // Right border
        if (self.borders.right and area.width > 0) {
            const x = (area.x +| area.width) -| 1;
            const v_char = decodeUtf8(symbols.vertical);
            var y: u16 = area.y +| @intFromBool(self.borders.top);
            const end_y = (area.y +| area.height) -| @intFromBool(self.borders.bottom);
            while (y < end_y) : (y += 1) {
                buf.set(x, y, .{ .char = v_char, .style = self.border_style });
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
                break :blk (area.y +| area.height) -| 1;
            },
        };

        // Calculate available width for title
        const border_offset: u16 = @as(u16, @intFromBool(self.borders.left)) + @as(u16, @intFromBool(self.borders.right));
        if (area.width < border_offset + 2) return; // Need space for borders + title

        const available_width = area.width -| border_offset -| 2; // -2 for padding around title
        const title_len = @min(title_text.len, available_width);
        if (title_len == 0) return;

        const title_x = switch (self.title_position) {
            .top_left, .bottom_left => area.x +| @intFromBool(self.borders.left) +| 1,
            .top_center, .bottom_center => blk: {
                const total_width = area.width -| border_offset;
                if (title_len >= total_width) {
                    break :blk area.x +| @intFromBool(self.borders.left) +| 1;
                }
                const offset = (total_width -| title_len) / 2;
                break :blk area.x +| @intFromBool(self.borders.left) +| offset;
            },
            .top_right, .bottom_right => blk: {
                const safe_width = area.width -| border_offset;
                if (title_len + 1 > safe_width) {
                    break :blk area.x +| @intFromBool(self.borders.left) +| 1;
                }
                break :blk (area.x +| area.width) -| @intFromBool(self.borders.right) -| title_len -| 1;
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

// Regression tests for u16 overflow bugs in Block.inner()
// These tests ensure that inner() handles extreme Rect coordinates without panicking
// when computing x+1, y+1, x+padding, y+padding, or padding sums that would overflow u16's max (65535).

test "Block.inner with borders.left and x near max completes without panic on result.x += 1" {
    const block = (Block{}).withBorders(Borders{ .left = true });
    // x + 1 = 65535 + 1 = 65536 (overflows u16 max of 65535)
    // This triggers the `result.x += 1` computation at line 145
    const area = Rect{ .x = 65535, .y = 0, .width = 10, .height = 10 };
    const inner_area = block.inner(area); // Should not panic with u16 overflow
    // After fix: x saturates to 65535, width reduces by 1 (border), no early return since both dimensions remain > 0
    try std.testing.expectEqual(@as(u16, 65535), inner_area.x);
    try std.testing.expectEqual(@as(u16, 0), inner_area.y);
    try std.testing.expectEqual(@as(u16, 9), inner_area.width);
    try std.testing.expectEqual(@as(u16, 10), inner_area.height);
}

test "Block.inner with borders.top and y near max completes without panic on result.y += 1" {
    const block = (Block{}).withBorders(Borders{ .top = true });
    // y + 1 = 65535 + 1 = 65536 (overflows u16 max of 65535)
    // This triggers the `result.y += 1` computation at line 152
    const area = Rect{ .x = 0, .y = 65535, .width = 10, .height = 10 };
    const inner_area = block.inner(area); // Should not panic with u16 overflow
    // After fix: y saturates to 65535, height reduces by 1 (border), no early return since both dimensions remain > 0
    try std.testing.expectEqual(@as(u16, 0), inner_area.x);
    try std.testing.expectEqual(@as(u16, 65535), inner_area.y);
    try std.testing.expectEqual(@as(u16, 10), inner_area.width);
    try std.testing.expectEqual(@as(u16, 9), inner_area.height);
}

test "Block.inner with large padding_left and x near max completes without panic on result.x += self.padding_left" {
    const block = (Block{}).withPaddingCustom(0, 0, 0, 40000).withBorders(Borders.none);
    // x + padding_left = 30000 + 40000 = 70000 (overflows u16 max of 65535)
    // This triggers the `result.x += self.padding_left` computation at line 160
    const area = Rect{ .x = 30000, .y = 0, .width = 20, .height = 10 };
    const inner_area = block.inner(area); // Should not panic with u16 overflow
    // After fix: x saturates to 65535, width underflows to 0, triggering early return
    // Early return sets both width and height to 0 when either becomes 0
    try std.testing.expectEqual(@as(u16, 65535), inner_area.x);
    try std.testing.expectEqual(@as(u16, 0), inner_area.y);
    try std.testing.expectEqual(@as(u16, 0), inner_area.width);
    try std.testing.expectEqual(@as(u16, 0), inner_area.height);
}

test "Block.inner with large padding_top and y near max completes without panic on result.y += self.padding_top" {
    const block = (Block{}).withPaddingCustom(40000, 0, 0, 0).withBorders(Borders.none);
    // y + padding_top = 30000 + 40000 = 70000 (overflows u16 max of 65535)
    // This triggers the `result.y += self.padding_top` computation at line 162
    const area = Rect{ .x = 0, .y = 30000, .width = 10, .height = 20 };
    const inner_area = block.inner(area); // Should not panic with u16 overflow
    // After fix: y saturates to 65535, height underflows to 0, triggering early return
    // Early return sets both width and height to 0 when either becomes 0
    try std.testing.expectEqual(@as(u16, 0), inner_area.x);
    try std.testing.expectEqual(@as(u16, 65535), inner_area.y);
    try std.testing.expectEqual(@as(u16, 0), inner_area.width);
    try std.testing.expectEqual(@as(u16, 0), inner_area.height);
}

test "Block.inner with large padding_left and padding_right sum overflow completes without panic" {
    const block = (Block{}).withPaddingCustom(0, 40000, 0, 40000).withBorders(Borders.none);
    // padding_left + padding_right = 40000 + 40000 = 80000 (overflows u16 max of 65535)
    // This triggers the sum in the width subtraction at line 161:
    // `result.width -|= self.padding_left +| self.padding_right` (saturated sum = 65535)
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 10 };
    const inner_area = block.inner(area); // Should not panic with u16 overflow in padding sum
    // After fix: x = 40000 (0 + padding_left), width underflows to 0 (100 - 65535), triggering early return
    // Early return sets both width and height to 0
    try std.testing.expectEqual(@as(u16, 40000), inner_area.x);
    try std.testing.expectEqual(@as(u16, 0), inner_area.y);
    try std.testing.expectEqual(@as(u16, 0), inner_area.width);
    try std.testing.expectEqual(@as(u16, 0), inner_area.height);
}

test "Block.inner with large padding_top and padding_bottom sum overflow completes without panic" {
    const block = (Block{}).withPaddingCustom(40000, 0, 40000, 0).withBorders(Borders.none);
    // padding_top + padding_bottom = 40000 + 40000 = 80000 (overflows u16 max of 65535)
    // This triggers the sum in the height subtraction at line 163:
    // `result.height -|= self.padding_top +| self.padding_bottom` (saturated sum = 65535)
    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 100 };
    const inner_area = block.inner(area); // Should not panic with u16 overflow in padding sum
    // After fix: y = 40000 (0 + padding_top), height underflows to 0 (100 - 65535), triggering early return
    // Early return sets both width and height to 0
    try std.testing.expectEqual(@as(u16, 0), inner_area.x);
    try std.testing.expectEqual(@as(u16, 40000), inner_area.y);
    try std.testing.expectEqual(@as(u16, 0), inner_area.width);
    try std.testing.expectEqual(@as(u16, 0), inner_area.height);
}

test "Block.inner with all borders and x at max returns sensible result post-fix" {
    const block = (Block{});
    // x + 1 (left border) would overflow, test that post-fix it returns sane dimensions
    const area = Rect{ .x = 65535, .y = 0, .width = 10, .height = 10 };
    const inner_area = block.inner(area);
    // Post-fix with saturating arithmetic: x saturates to 65535, but width/height both reduce by 1 per border
    // No early-return (both dimensions > 0), so normal return applies
    try std.testing.expectEqual(@as(u16, 65535), inner_area.x);
    try std.testing.expectEqual(@as(u16, 1), inner_area.y);
    try std.testing.expectEqual(@as(u16, 8), inner_area.width);
    try std.testing.expectEqual(@as(u16, 8), inner_area.height);
}

test "Block.inner with all borders and y at max returns sensible result post-fix" {
    const block = (Block{});
    // y + 1 (top border) would overflow, test that post-fix it returns sane dimensions
    const area = Rect{ .x = 0, .y = 65535, .width = 10, .height = 10 };
    const inner_area = block.inner(area);
    // Post-fix with saturating arithmetic: y saturates to 65535, but width/height both reduce by 1 per border
    // No early-return (both dimensions > 0), so normal return applies
    try std.testing.expectEqual(@as(u16, 1), inner_area.x);
    try std.testing.expectEqual(@as(u16, 65535), inner_area.y);
    try std.testing.expectEqual(@as(u16, 8), inner_area.width);
    try std.testing.expectEqual(@as(u16, 8), inner_area.height);
}

// Regression tests for u16 overflow bugs in Block.render() path (renderBorders/renderTitle)
// These tests reproduce panics when calling render() with extreme Rect coordinates
// and verify that post-fix the render does not panic and borders/titles render correctly

test "Block.render with borders.left and x near max does not panic at line 207" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 100, 10);
    defer buf.deinit();

    const block = (Block{}).withBorders(Borders{ .left = true });
    // This will trigger: var x: u16 = area.x + @intFromBool(self.borders.left)
    // at line 207 in renderBorders: area.x=65535, +1 overflows u16 max
    const area = Rect{ .x = 65535, .y = 0, .width = 10, .height = 10 };
    block.render(&buf, area); // Should not panic with u16 overflow

    // Post-fix: left border should be rendered at saturated x=65535
    // The buffer is 100 wide, but the Rect is at x=65535, so the border writes out of bounds
    // and are silently dropped (no panic, just bounds checking in buf.set)
}

test "Block.render with borders.right and x+width near max does not panic at line 208" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 100, 10);
    defer buf.deinit();

    const block = (Block{}).withBorders(Borders{ .right = true });
    // This will trigger: const end_x = area.x + area.width -| @intFromBool(self.borders.right)
    // The + happens BEFORE the -|, so area.x + area.width can overflow
    // area.x=65530, area.width=10 → 65530 + 10 = 65540 overflows u16
    const area = Rect{ .x = 65530, .y = 0, .width = 10, .height = 10 };
    block.render(&buf, area); // Should not panic with u16 overflow
}

test "Block.render with borders.top and y near max does not panic at line 238" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 100);
    defer buf.deinit();

    const block = (Block{}).withBorders(Borders{ .top = true });
    // This will trigger: var y: u16 = area.y + @intFromBool(self.borders.top)
    // at line 238 in renderBorders (left border vertical loop): area.y=65535, +1 overflows
    const area = Rect{ .x = 0, .y = 65535, .width = 10, .height = 10 };
    block.render(&buf, area); // Should not panic with u16 overflow
}

test "Block.render with borders.bottom and y+height near max does not panic at line 220" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 100);
    defer buf.deinit();

    const block = (Block{}).withBorders(Borders{ .bottom = true });
    // This will trigger: const y = area.y + area.height - 1
    // at line 220 in renderBorders (bottom border row): area.y=65530, area.height=10 → 65540 overflows u16
    const area = Rect{ .x = 0, .y = 65530, .width = 10, .height = 10 };
    block.render(&buf, area); // Should not panic with u16 overflow
}

test "Block.render with all borders and area.x+width at max does not panic at line 214" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 100, 10);
    defer buf.deinit();

    const block = (Block{});
    // This will trigger: buf.set(area.x + area.width - 1, y, ...)
    // at line 214 (top-right corner): area.x=65530, area.width=10 → 65540 overflows u16
    const area = Rect{ .x = 65530, .y = 0, .width = 10, .height = 10 };
    block.render(&buf, area); // Should not panic with u16 overflow
}

test "Block.render with all borders and area.y+height at max does not panic at line 231" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 100);
    defer buf.deinit();

    const block = (Block{});
    // This will trigger: buf.set(area.x + area.width - 1, y, ...)
    // at line 231 (bottom-right corner): area.y=65530, area.height=10 → 65540 overflows u16
    const area = Rect{ .x = 0, .y = 65530, .width = 10, .height = 10 };
    block.render(&buf, area); // Should not panic with u16 overflow
}

test "Block.render title at top_left with area.x near max does not panic at line 277" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 100, 10);
    defer buf.deinit();

    const block = (Block{})
        .withBorders(Borders{ .top = true, .left = true })
        .withTitle("Test", .top_left);
    // This will trigger: area.x + @intFromBool(self.borders.left) + 1
    // at line 277 in renderTitle: area.x=65535, +1 +1 overflows u16
    const area = Rect{ .x = 65535, .y = 0, .width = 20, .height = 10 };
    block.render(&buf, area); // Should not panic with u16 overflow
}

test "Block.render title at bottom_left with area.y+height at max does not panic at line 264" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 100, 100);
    defer buf.deinit();

    const block = (Block{})
        .withBorders(Borders{ .bottom = true, .left = true })
        .withTitle("Test", .bottom_left);
    // This will trigger: area.y + area.height - 1
    // at line 264 in renderTitle (bottom position): area.y=65530, area.height=10 → 65540 overflows u16
    const area = Rect{ .x = 0, .y = 65530, .width = 20, .height = 10 };
    block.render(&buf, area); // Should not panic with u16 overflow
}

test "Block.render title at top_center with area.x near max does not panic at line 284" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 100, 10);
    defer buf.deinit();

    const block = (Block{})
        .withBorders(Borders{ .top = true, .left = true })
        .withTitle("Hi", .top_center);
    // This will trigger: area.x + @intFromBool(self.borders.left) + offset
    // at line 284 in renderTitle: area.x=65535 can overflow when adding border+offset
    const area = Rect{ .x = 65535, .y = 0, .width = 20, .height = 10 };
    block.render(&buf, area); // Should not panic with u16 overflow
}

test "Block.render title at top_right with area.x+width at max does not panic at line 291" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 100, 10);
    defer buf.deinit();

    const block = (Block{})
        .withBorders(Borders{ .top = true, .right = true })
        .withTitle("End", .top_right);
    // This will trigger: area.x + area.width -| @intFromBool(self.borders.right) -| title_len -| 1
    // at line 291: the area.x + area.width part happens BEFORE the -|, so it overflows
    // area.x=65530, area.width=10 → 65540 overflows u16
    const area = Rect{ .x = 65530, .y = 0, .width = 10, .height = 10 };
    block.render(&buf, area); // Should not panic with u16 overflow
}

test "Block.render with all borders and title correctly renders after fix with extreme x" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 100, 10);
    defer buf.deinit();

    const block = (Block{})
        .withBorders(Borders.all)
        .withTitle("Title", .top_left);
    // After fix: extreme coordinates saturate but don't overflow or panic
    // Writes out of buffer bounds are silently dropped (buf.set has bounds checking)
    const area = Rect{ .x = 65535, .y = 0, .width = 10, .height = 10 };
    block.render(&buf, area); // Should not panic, render calls complete without crash
}

test "Block.render with all borders and title correctly renders after fix with extreme y" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 100, 100);
    defer buf.deinit();

    const block = (Block{})
        .withBorders(Borders.all)
        .withTitle("Title", .bottom_center);
    // After fix: extreme y coordinates saturate but don't overflow or panic
    const area = Rect{ .x = 0, .y = 65535, .width = 10, .height = 10 };
    block.render(&buf, area); // Should not panic, render calls complete without crash
}
