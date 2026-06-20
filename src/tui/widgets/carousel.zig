//! Carousel widget — horizontal slide navigation with indicators and arrow hints.
//!
//! The Carousel widget manages navigation state for a collection of items,
//! providing visual indicators (dots), arrow hints, and optional block borders.
//! Callers render content into the contentArea().
//!
//! ## Features
//! - Navigation tracking (next/prev with loop or clamp modes)
//! - Indicator row with active/inactive markers
//! - Arrow visibility based on navigation state
//! - Optional block borders
//! - Configurable characters and styles
//! - Builder API for fluent configuration
//!
//! ## Usage
//! ```zig
//! var carousel = Carousel.init(5);
//! carousel.loop = true;
//! carousel.next();
//! const content = carousel.contentArea(area);
//! // Render carousel.render(&buf, area)
//! // Render app content into content area
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

/// Carousel navigation widget
pub const Carousel = struct {
    items_count: usize,
    current: usize = 0,
    loop: bool = true,
    show_indicators: bool = true,
    show_arrows: bool = true,
    indicator_active_char: u21 = '●',
    indicator_inactive_char: u21 = '○',
    left_arrow: []const u8 = "◄",
    right_arrow: []const u8 = "►",
    indicator_style: Style = .{},
    active_indicator_style: Style = .{},
    arrow_style: Style = .{},
    block: ?Block = null,

    /// Initialize carousel with item count
    pub fn init(items_count: usize) Carousel {
        return .{
            .items_count = items_count,
        };
    }

    /// Advance to next item
    /// If loop=true: wraps from last to first
    /// If loop=false: clamps to last item
    /// No-op if items_count==0
    pub fn next(self: *Carousel) void {
        if (self.items_count == 0) return;
        if (self.loop) {
            self.current = (self.current + 1) % self.items_count;
        } else {
            if (self.current < self.items_count - 1) {
                self.current += 1;
            }
        }
    }

    /// Move to previous item
    /// If loop=true: wraps from first to last
    /// If loop=false: clamps to first item
    /// No-op if items_count==0
    pub fn prev(self: *Carousel) void {
        if (self.items_count == 0) return;
        if (self.loop) {
            self.current = (self.items_count + self.current - 1) % self.items_count;
        } else {
            if (self.current > 0) {
                self.current -= 1;
            }
        }
    }

    /// Go to specific item by index
    /// No-op if i >= items_count
    pub fn goTo(self: *Carousel, i: usize) void {
        if (i < self.items_count) {
            self.current = i;
        }
    }

    /// Check if at first item
    /// Returns true if items_count==0 or current==0
    pub fn isFirst(self: Carousel) bool {
        return self.items_count == 0 or self.current == 0;
    }

    /// Check if at last item
    /// Returns true if items_count==0 or current==items_count-1
    pub fn isLast(self: Carousel) bool {
        return self.items_count == 0 or self.current == self.items_count - 1;
    }

    /// Get total item count
    pub fn count(self: Carousel) usize {
        return self.items_count;
    }

    /// Get indicator row height (1 if show_indicators else 0)
    pub fn indicatorHeight(self: Carousel) u16 {
        return if (self.show_indicators) 1 else 0;
    }

    /// Get content area (area minus block insets and indicator height)
    pub fn contentArea(self: Carousel, area: Rect) Rect {
        var result = area;

        // Apply block insets
        if (self.block) |block| {
            result = block.inner(area);
        }

        // Reduce height by indicator row
        if (self.show_indicators and result.height > 0) {
            result.height -= 1;
        }

        return result;
    }

    /// Create copy with different current index
    pub fn withCurrent(self: Carousel, current: usize) Carousel {
        var result = self;
        result.current = current;
        return result;
    }

    /// Create copy with different loop mode
    pub fn withLoop(self: Carousel, loop: bool) Carousel {
        var result = self;
        result.loop = loop;
        return result;
    }

    /// Create copy with different show_indicators setting
    pub fn withShowIndicators(self: Carousel, show: bool) Carousel {
        var result = self;
        result.show_indicators = show;
        return result;
    }

    /// Create copy with different show_arrows setting
    pub fn withShowArrows(self: Carousel, show: bool) Carousel {
        var result = self;
        result.show_arrows = show;
        return result;
    }

    /// Create copy with different active indicator character
    pub fn withIndicatorActiveChar(self: Carousel, ch: u21) Carousel {
        var result = self;
        result.indicator_active_char = ch;
        return result;
    }

    /// Create copy with different inactive indicator character
    pub fn withIndicatorInactiveChar(self: Carousel, ch: u21) Carousel {
        var result = self;
        result.indicator_inactive_char = ch;
        return result;
    }

    /// Create copy with different left arrow string
    pub fn withLeftArrow(self: Carousel, arrow: []const u8) Carousel {
        var result = self;
        result.left_arrow = arrow;
        return result;
    }

    /// Create copy with different right arrow string
    pub fn withRightArrow(self: Carousel, arrow: []const u8) Carousel {
        var result = self;
        result.right_arrow = arrow;
        return result;
    }

    /// Create copy with different indicator style
    pub fn withIndicatorStyle(self: Carousel, style: Style) Carousel {
        var result = self;
        result.indicator_style = style;
        return result;
    }

    /// Create copy with different active indicator style
    pub fn withActiveIndicatorStyle(self: Carousel, style: Style) Carousel {
        var result = self;
        result.active_indicator_style = style;
        return result;
    }

    /// Create copy with different arrow style
    pub fn withArrowStyle(self: Carousel, style: Style) Carousel {
        var result = self;
        result.arrow_style = style;
        return result;
    }

    /// Create copy with block
    pub fn withBlock(self: Carousel, block: Block) Carousel {
        var result = self;
        result.block = block;
        return result;
    }

    /// Render carousel indicators and block (if present)
    pub fn render(self: Carousel, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        var inner = area;

        // Render block if present
        if (self.block) |block| {
            block.render(buf, area);
            inner = block.inner(area);
        }

        if (inner.width == 0 or inner.height == 0) return;

        // Render indicator row if enabled
        if (self.show_indicators and inner.height > 0) {
            self.renderIndicatorRow(buf, inner);
        }
    }

    /// Render the indicator row at the bottom of the inner area
    fn renderIndicatorRow(self: Carousel, buf: *Buffer, inner: Rect) void {
        const indicator_row_y = inner.y + inner.height - 1;
        var col = inner.x;
        const max_col = inner.x + inner.width;

        // Left arrow
        if (self.show_arrows and (self.loop or !self.isFirst())) {
            const arrow_char = firstCodepoint(self.left_arrow);
            if (col < max_col) {
                buf.set(col, indicator_row_y, .{
                    .char = arrow_char,
                    .style = self.arrow_style,
                });
                col += 1;
            }

            // Space after left arrow
            if (col < max_col) {
                buf.set(col, indicator_row_y, .{
                    .char = ' ',
                    .style = self.indicator_style,
                });
                col += 1;
            }
        }

        // Indicator dots
        var i: usize = 0;
        while (i < self.items_count and col < max_col) : (i += 1) {
            const is_active = i == self.current;
            const char = if (is_active)
                self.indicator_active_char
            else
                self.indicator_inactive_char;
            const style = if (is_active)
                self.active_indicator_style
            else
                self.indicator_style;

            buf.set(col, indicator_row_y, .{
                .char = char,
                .style = style,
            });
            col += 1;

            // Space between dots
            if (i < self.items_count - 1 and col < max_col) {
                buf.set(col, indicator_row_y, .{
                    .char = ' ',
                    .style = self.indicator_style,
                });
                col += 1;
            }
        }

        // Space before right arrow
        if (self.show_arrows and (self.loop or !self.isLast()) and col < max_col) {
            // Look ahead to see if we'll render right arrow
            if (col + 1 < max_col) {
                buf.set(col, indicator_row_y, .{
                    .char = ' ',
                    .style = self.indicator_style,
                });
                col += 1;
            }
        }

        // Right arrow
        if (self.show_arrows and (self.loop or !self.isLast()) and col < max_col) {
            const arrow_char = firstCodepoint(self.right_arrow);
            buf.set(col, indicator_row_y, .{
                .char = arrow_char,
                .style = self.arrow_style,
            });
        }
    }
};

/// Decode first UTF-8 codepoint from a string
fn firstCodepoint(s: []const u8) u21 {
    if (s.len == 0) return '?';
    const seq_len = std.unicode.utf8ByteSequenceLength(s[0]) catch return '?';
    if (seq_len > s.len) return '?';
    return std.unicode.utf8Decode(s[0..seq_len]) catch '?';
}
