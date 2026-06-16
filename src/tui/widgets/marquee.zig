//! Marquee Widget — horizontally scrolling text ticker.
//!
//! Marquee displays a single line of text that scrolls horizontally, either
//! left or right. The text repeats with a separator between cycles.
//!
//! ## Features
//! - Horizontal text scrolling (left or right direction)
//! - Configurable scroll speed
//! - Custom separator between text cycles
//! - Wrapping/cycling behavior
//! - Style and block support
//!
//! ## Usage
//! ```zig
//! var marquee = Marquee.init("Hello World")
//!     .withSpeed(2)
//!     .withDirection(.left)
//!     .withStyle(Style{ .fg = Color.green });
//!
//! marquee.render(&buf, area);
//! marquee = marquee.tick();  // advance animation
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Marquee widget — horizontally scrolling text
pub const Marquee = struct {
    /// Scroll direction enum
    pub const ScrollDirection = enum {
        left, // offset increments on tick (text appears to scroll left)
        right, // offset decrements on tick (text appears to scroll right)
    };

    /// Text to scroll
    text: []const u8,

    /// Current scroll offset
    offset: usize = 0,

    /// Pixels/chars to advance per tick
    speed: u8 = 1,

    /// Separator between text cycles
    separator: []const u8 = " | ",

    /// Scroll direction
    direction: ScrollDirection = .left,

    /// Style for text
    style: Style = .{},

    /// Optional block for borders
    block: ?Block = null,

    /// Initialize Marquee with text
    pub fn init(text: []const u8) Marquee {
        return .{
            .text = text,
        };
    }

    /// Calculate total length of text + separator
    pub fn textLen(self: Marquee) usize {
        const total = self.text.len + self.separator.len;
        // Avoid division by zero in currentOffset
        return if (total == 0) 1 else total;
    }

    /// Get current offset wrapped to textLen
    pub fn currentOffset(self: Marquee) usize {
        const len = self.text.len + self.separator.len;
        if (len == 0) return 0;
        return self.offset % len;
    }

    /// Advance animation to next frame
    pub fn tick(self: Marquee) Marquee {
        var result = self;

        const len = self.text.len + self.separator.len;
        if (len == 0) {
            return result;
        }

        switch (self.direction) {
            .left => {
                // Left: offset increases
                result.offset = (self.offset + @as(usize, self.speed)) % len;
            },
            .right => {
                // Right: offset decreases with wrapping
                if (self.offset < @as(usize, self.speed)) {
                    // Would go negative, wrap around
                    result.offset = (len + self.offset - @as(usize, self.speed)) % len;
                } else {
                    result.offset = self.offset - @as(usize, self.speed);
                }
            },
        }

        return result;
    }

    /// Reset offset to 0
    pub fn reset(self: Marquee) Marquee {
        var result = self;
        result.offset = 0;
        return result;
    }

    /// Builder: set text
    pub fn withText(self: Marquee, text: []const u8) Marquee {
        var result = self;
        result.text = text;
        return result;
    }

    /// Builder: set offset
    pub fn withOffset(self: Marquee, offset: usize) Marquee {
        var result = self;
        result.offset = offset;
        return result;
    }

    /// Builder: set speed
    pub fn withSpeed(self: Marquee, speed: u8) Marquee {
        var result = self;
        result.speed = speed;
        return result;
    }

    /// Builder: set separator
    pub fn withSeparator(self: Marquee, sep: []const u8) Marquee {
        var result = self;
        result.separator = sep;
        return result;
    }

    /// Builder: set direction
    pub fn withDirection(self: Marquee, dir: ScrollDirection) Marquee {
        var result = self;
        result.direction = dir;
        return result;
    }

    /// Builder: set style
    pub fn withStyle(self: Marquee, new_style: Style) Marquee {
        var result = self;
        result.style = new_style;
        return result;
    }

    /// Builder: set block
    pub fn withBlock(self: Marquee, new_block: Block) Marquee {
        var result = self;
        result.block = new_block;
        return result;
    }

    /// Render the Marquee widget
    pub fn render(self: Marquee, buf: *Buffer, area: Rect) void {
        // Handle block if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        // Early exit if area too small
        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Get total text length
        const total_len = self.text.len + self.separator.len;
        if (total_len == 0) return;

        // Get starting position in the repeating text
        const start = self.currentOffset();

        // Render each column in the available width
        var col: u16 = 0;
        while (col < inner_area.width) : (col += 1) {
            const pos = (start + @as(usize, col)) % total_len;

            // Determine which character to render
            const ch: u21 = if (pos < self.text.len)
                @as(u21, self.text[pos])
            else
                @as(u21, self.separator[pos - self.text.len]);

            // Write the character
            buf.set(
                inner_area.x + col,
                inner_area.y,
                .{
                    .char = ch,
                    .style = self.style,
                },
            );
        }
    }
};
