//! HexEditor Widget — binary data viewer with hex + ASCII columns
//!
//! The HexEditor widget displays binary data as hexadecimal bytes with optional
//! ASCII preview and offset columns. Supports cursor highlighting, custom grouping,
//! and block borders.
//!
//! ## Features
//! - Hex byte display with 0x00-0xFF notation
//! - ASCII column with printable characters and '.' for non-printable
//! - Offset column showing byte addresses
//! - Configurable bytes per row and byte grouping
//! - Cursor positioning and highlighting
//! - Block border support
//! - Multiple style attributes (base, cursor, modified)
//!
//! ## Usage
//! ```zig
//! const data = "Hello, World!";
//! var editor = HexEditor.init()
//!     .withData(data)
//!     .withCursor(0)
//!     .withShowOffset(true)
//!     .withShowAscii(true);
//! editor.render(&buf, area);
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

/// HexEditor widget for viewing binary data
pub const HexEditor = struct {
    /// Maximum bytes that can be displayed
    pub const MAX_BYTES: usize = 4096;

    /// Binary data to display
    data: []const u8 = &.{},
    /// Current cursor position in bytes
    cursor: usize = 0,
    /// Display offset in bytes (for scrolling)
    offset: usize = 0,
    /// Number of bytes to display per row
    bytes_per_row: u8 = 16,
    /// Group size for byte spacing (extra space every N bytes)
    group_size: u8 = 1,
    /// Show ASCII preview column
    show_ascii: bool = true,
    /// Show offset column
    show_offset: bool = true,
    /// Style for normal text
    style: Style = .{},
    /// Style for cursor position
    cursor_style: Style = .{},
    /// Style for modified bytes
    modified_style: Style = .{},
    /// Optional block border
    block: ?Block = null,

    /// Initialize a new HexEditor with defaults
    pub fn init() HexEditor {
        return .{};
    }

    /// Return the effective byte count (capped at MAX_BYTES)
    pub fn byteCount(self: HexEditor) usize {
        return @min(self.data.len, MAX_BYTES);
    }

    /// Return the number of rows needed to display data
    pub fn rowCount(self: HexEditor) usize {
        const count = self.byteCount();
        if (count == 0) return 0;
        return (count + self.bytes_per_row - 1) / self.bytes_per_row;
    }

    /// Create a copy with different data
    pub fn withData(self: HexEditor, data: []const u8) HexEditor {
        var result = self;
        result.data = data;
        return result;
    }

    /// Create a copy with different cursor position
    pub fn withCursor(self: HexEditor, cursor: usize) HexEditor {
        var result = self;
        result.cursor = cursor;
        return result;
    }

    /// Create a copy with different offset
    pub fn withOffset(self: HexEditor, offset: usize) HexEditor {
        var result = self;
        result.offset = offset;
        return result;
    }

    /// Create a copy with different bytes per row
    pub fn withBytesPerRow(self: HexEditor, bytes_per_row: u8) HexEditor {
        var result = self;
        result.bytes_per_row = bytes_per_row;
        return result;
    }

    /// Create a copy with different group size
    pub fn withGroupSize(self: HexEditor, group_size: u8) HexEditor {
        var result = self;
        result.group_size = group_size;
        return result;
    }

    /// Create a copy with show_ascii toggle
    pub fn withShowAscii(self: HexEditor, show_ascii: bool) HexEditor {
        var result = self;
        result.show_ascii = show_ascii;
        return result;
    }

    /// Create a copy with show_offset toggle
    pub fn withShowOffset(self: HexEditor, show_offset: bool) HexEditor {
        var result = self;
        result.show_offset = show_offset;
        return result;
    }

    /// Create a copy with different style
    pub fn withStyle(self: HexEditor, style: Style) HexEditor {
        var result = self;
        result.style = style;
        return result;
    }

    /// Create a copy with different cursor style
    pub fn withCursorStyle(self: HexEditor, cursor_style: Style) HexEditor {
        var result = self;
        result.cursor_style = cursor_style;
        return result;
    }

    /// Create a copy with different modified style
    pub fn withModifiedStyle(self: HexEditor, modified_style: Style) HexEditor {
        var result = self;
        result.modified_style = modified_style;
        return result;
    }

    /// Create a copy with a block border
    pub fn withBlock(self: HexEditor, block: ?Block) HexEditor {
        var result = self;
        result.block = block;
        return result;
    }

    /// Render the hex editor to the buffer
    pub fn render(self: HexEditor, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // Handle block border if present
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        const byte_count = self.byteCount();
        if (byte_count == 0) return;

        const hex_chars = "0123456789ABCDEF";
        const bpr = self.bytes_per_row;

        var row_idx: u16 = 0;
        while (row_idx < inner_area.height and row_idx < self.rowCount()) : (row_idx += 1) {
            const data_row_idx = row_idx;
            const y = inner_area.y + row_idx;

            var col: u16 = inner_area.x;

            // Offset column
            if (self.show_offset) {
                const byte_offset = self.offset + data_row_idx * bpr;
                var buf_hex: [8]u8 = undefined;
                _ = std.fmt.bufPrint(&buf_hex, "{X:0>8}", .{byte_offset}) catch return;
                for (buf_hex) |ch| {
                    if (col >= inner_area.x + inner_area.width) break;
                    buf.set(col, y, Cell.init(ch, self.style));
                    col += 1;
                }
                // Space after offset
                if (col < inner_area.x + inner_area.width) {
                    buf.set(col, y, Cell.init(' ', self.style));
                    col += 1;
                }
            }

            // Hex bytes
            var byte_in_row: u8 = 0;
            while (byte_in_row < bpr) : (byte_in_row += 1) {
                const data_idx = data_row_idx * bpr + byte_in_row;
                if (data_idx >= byte_count) break;
                if (col + 2 > inner_area.x + inner_area.width) break;

                const byte_val = self.data[data_idx];
                const byte_style = if (data_idx == self.cursor) self.cursor_style else self.style;

                // High nibble
                const hi = (byte_val >> 4) & 0xF;
                buf.set(col, y, Cell.init(hex_chars[hi], byte_style));
                col += 1;

                // Low nibble
                const lo = byte_val & 0xF;
                buf.set(col, y, Cell.init(hex_chars[lo], byte_style));
                col += 1;

                // Space after byte
                if (col < inner_area.x + inner_area.width) {
                    buf.set(col, y, Cell.init(' ', self.style));
                    col += 1;
                }

                // Extra space at group boundaries (but not after last byte)
                if (self.group_size > 0 and
                    @as(u32, byte_in_row + 1) % @as(u32, self.group_size) == 0 and
                    byte_in_row + 1 < bpr and
                    col < inner_area.x + inner_area.width)
                {
                    buf.set(col, y, Cell.init(' ', self.style));
                    col += 1;
                }
            }

            // ASCII column
            if (self.show_ascii) {
                // Space before ASCII
                if (col < inner_area.x + inner_area.width) {
                    buf.set(col, y, Cell.init(' ', self.style));
                    col += 1;
                }

                byte_in_row = 0;
                while (byte_in_row < bpr) : (byte_in_row += 1) {
                    const data_idx = data_row_idx * bpr + byte_in_row;
                    if (data_idx >= byte_count) break;
                    if (col >= inner_area.x + inner_area.width) break;

                    const byte_val = self.data[data_idx];
                    const ascii_char: u21 = if (byte_val >= 32 and byte_val < 127) byte_val else '.';
                    buf.set(col, y, Cell.init(ascii_char, self.style));
                    col += 1;
                }
            }
        }
    }
};

test "HexEditor imports" {
    const testing = std.testing;
    const he = HexEditor.init();
    try testing.expectEqual(@as(usize, 0), he.cursor);
}
