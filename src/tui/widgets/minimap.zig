//! MiniMap widget — scaled-down content overview with viewport indicator.
//!
//! MiniMap displays a compressed view of a large content area, showing which portion
//! is currently visible in the main viewport. Each rendered row represents multiple
//! content lines (determined by scaling factor).
//!
//! ## Features
//! - Compressed line-by-line overview of content
//! - Viewport highlight showing visible portion
//! - Customizable highlight and empty characters
//! - Configurable viewport styling
//! - Optional block wrapper for borders
//!
//! ## Usage
//! ```zig
//! var widget = MiniMap.init()
//!     .withLines(content_lines)
//!     .withViewportTop(10)
//!     .withViewportHeight(20)
//!     .withViewportStyle(Style{ .fg = .blue });
//! widget.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// MiniMap widget - shows compressed overview with viewport indicator
pub const MiniMap = struct {
    /// Content lines to display
    lines: []const []const u8 = &.{},
    /// First visible line in main viewport
    viewport_top: usize = 0,
    /// Height of main viewport
    viewport_height: usize = 10,
    /// Style for non-viewport rows
    style: Style = .{},
    /// Style for viewport region rows
    viewport_style: Style = .{},
    /// Character for rows with content
    highlight_char: u21 = '▌',
    /// Character for empty rows
    empty_char: u21 = ' ',
    /// Optional border block
    block: ?Block = null,

    /// Initialize with default values
    pub fn init() MiniMap {
        return .{};
    }

    /// Builder: set content lines
    pub fn withLines(self: MiniMap, lines: []const []const u8) MiniMap {
        var copy = self;
        copy.lines = lines;
        return copy;
    }

    /// Builder: set viewport top position
    pub fn withViewportTop(self: MiniMap, top: usize) MiniMap {
        var copy = self;
        copy.viewport_top = top;
        return copy;
    }

    /// Builder: set viewport height
    pub fn withViewportHeight(self: MiniMap, height: usize) MiniMap {
        var copy = self;
        copy.viewport_height = height;
        return copy;
    }

    /// Builder: set base style
    pub fn withStyle(self: MiniMap, s: Style) MiniMap {
        var copy = self;
        copy.style = s;
        return copy;
    }

    /// Builder: set viewport style
    pub fn withViewportStyle(self: MiniMap, s: Style) MiniMap {
        var copy = self;
        copy.viewport_style = s;
        return copy;
    }

    /// Builder: set highlight character
    pub fn withHighlightChar(self: MiniMap, char: u21) MiniMap {
        var copy = self;
        copy.highlight_char = char;
        return copy;
    }

    /// Builder: set empty character
    pub fn withEmptyChar(self: MiniMap, char: u21) MiniMap {
        var copy = self;
        copy.empty_char = char;
        return copy;
    }

    /// Builder: set block wrapper
    pub fn withBlock(self: MiniMap, b: Block) MiniMap {
        var copy = self;
        copy.block = b;
        return copy;
    }

    /// Render the widget to a buffer at the given area
    pub fn render(self: MiniMap, buf: *Buffer, area: Rect) void {
        // Guard: zero area
        if (area.width == 0 or area.height == 0) return;

        // Determine inner area (either inside block or same as area)
        var inner = area;
        if (self.block) |b| {
            b.render(buf, area);
            inner = b.inner(area);
        }

        // Guard: zero inner area
        if (inner.width == 0 or inner.height == 0) return;

        const total_lines = self.lines.len;

        // Calculate scaling factor: how many content lines per rendered row
        // scale = max(1, (total_lines + inner.height - 1) / inner.height)
        const scale: usize = if (total_lines == 0)
            1
        else
            @max(1, (total_lines + inner.height - 1) / inner.height);

        // Render each row of the minimap
        var r: usize = 0;
        while (r < inner.height) : (r += 1) {
            // Calculate which content lines this row represents
            const content_start = r * scale;
            const content_end = @min(total_lines, content_start + scale);

            // Determine if this row has content
            var has_content = false;
            if (total_lines > 0 and content_start < content_end) {
                for (content_start..content_end) |line_idx| {
                    if (self.lines[line_idx].len > 0) {
                        has_content = true;
                        break;
                    }
                }
            }

            // Determine if this row is in viewport
            const in_viewport = total_lines > 0 and
                content_start < self.viewport_top + self.viewport_height and
                content_end > self.viewport_top;

            // Choose character and style
            const the_char = if (has_content) self.highlight_char else self.empty_char;
            const the_style = if (in_viewport) self.viewport_style else self.style;

            // Fill entire row with the character and style
            var col: usize = 0;
            while (col < inner.width) : (col += 1) {
                const x = inner.x + @as(u16, @intCast(col));
                const y = inner.y + @as(u16, @intCast(r));
                const cell = Cell{ .char = the_char, .style = the_style };
                buf.set(x, y, cell);
            }
        }
    }
};
