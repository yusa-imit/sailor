//! HexViewer Widget — Classic hex dump format viewer for binary data.
//!
//! HexViewer displays binary data in the traditional hex dump format:
//! - Address column (8 hex digits + spacing)
//! - Hex bytes grouped by group_size (default 8)
//! - ASCII panel showing printable characters or dots
//!
//! ## Features
//! - Virtual scrolling (offset-based)
//! - Byte-level selection with auto-scroll
//! - Configurable bytes per row and group size
//! - Optional address and ASCII panels
//! - Style customization for each column
//! - No allocations (borrowed data slice)
//!
//! ## Usage
//! ```zig
//! var hv = HexViewer.init(data)
//!     .withBytesPerRow(16)
//!     .withSelected(0);
//! hv.render(&buf, area);
//! hv.selectNext();
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

/// HexViewer widget — displays binary data in hex dump format
pub const HexViewer = struct {
    data: []const u8,
    offset: usize = 0,           // byte offset, always aligned to bytes_per_row
    selected: ?usize = null,     // selected byte index (or null)
    bytes_per_row: u8 = 16,      // bytes to display per row
    group_size: u8 = 8,          // bytes per group (extra space between groups)
    block: ?Block = null,        // optional border
    address_style: Style = .{},  // style for address column
    hex_style: Style = .{},      // style for hex bytes
    ascii_style: Style = .{},    // style for ASCII panel
    selected_style: Style = .{}, // style for selected byte
    show_ascii: bool = true,     // show ASCII panel
    show_address: bool = true,   // show address column

    /// Create a new HexViewer with data
    pub fn init(data: []const u8) HexViewer {
        return .{
            .data = data,
        };
    }

    /// Get number of bytes in data
    pub fn byteCount(self: HexViewer) usize {
        return self.data.len;
    }

    /// Get total number of rows (ceil division)
    pub fn totalRows(self: HexViewer) usize {
        if (self.data.len == 0) return 0;
        return (self.data.len + self.bytes_per_row - 1) / self.bytes_per_row;
    }

    /// Get currently selected byte, or null
    pub fn selectedByte(self: HexViewer) ?u8 {
        if (self.selected) |sel| {
            if (sel < self.data.len) {
                return self.data[sel];
            }
        }
        return null;
    }

    /// Move to next byte, clamp at last
    pub fn selectNext(self: *HexViewer) void {
        if (self.data.len == 0) return;

        if (self.selected) |sel| {
            if (sel < self.data.len - 1) {
                self.selected = sel + 1;
            }
            // else: stay at last byte
        } else {
            self.selected = 0;
        }

        // Auto-scroll to keep selected visible (estimate 1 row visible for now)
        self.scrollToSelected(1);
    }

    /// Move to previous byte, clamp at 0
    pub fn selectPrev(self: *HexViewer) void {
        if (self.data.len == 0) return;
        if (self.selected) |sel| {
            if (sel > 0) {
                self.selected = sel - 1;
            }
            // else: stay at 0
        }
        // else: null stays null

        // Auto-scroll
        self.scrollToSelected(1);
    }

    /// Move down by bytes_per_row
    pub fn selectNextRow(self: *HexViewer) void {
        if (self.data.len == 0) return;

        if (self.selected) |sel| {
            // If already at or past end, stay there
            if (sel >= self.data.len) {
                return;
            }

            const next = sel + self.bytes_per_row;
            if (next < self.data.len) {
                self.selected = next;
            } else if (next == self.data.len) {
                // Allow selecting exactly at data.len (one past end, on row boundary)
                self.selected = next;
            } else {
                // next > data.len: clamp to last valid byte
                self.selected = self.data.len - 1;
            }
        } else {
            self.selected = 0;
        }

        // Auto-scroll
        self.scrollToSelected(1);
    }

    /// Move up by bytes_per_row
    pub fn selectPrevRow(self: *HexViewer) void {
        if (self.data.len == 0) return;
        if (self.selected) |sel| {
            if (sel >= self.bytes_per_row) {
                self.selected = sel - self.bytes_per_row;
            } else {
                self.selected = 0;
            }
        }
        // else: null stays null

        // Auto-scroll
        self.scrollToSelected(1);
    }

    /// Advance offset by rows * bytes_per_row, clamp
    pub fn pageDown(self: *HexViewer, rows: usize) void {
        const bytes_to_advance = rows * self.bytes_per_row;
        const total_rows = self.totalRows();

        if (total_rows == 0) return;

        // max_offset = (total_rows - 1) * bytes_per_row, but only if data not empty
        const max_offset = if (self.data.len == 0) 0 else ((total_rows - 1) * self.bytes_per_row);

        const new_offset = self.offset + bytes_to_advance;
        self.offset = if (new_offset > max_offset) max_offset else new_offset;
    }

    /// Retreat offset by rows * bytes_per_row, clamp at 0
    pub fn pageUp(self: *HexViewer, rows: usize) void {
        const bytes_to_retreat = rows * self.bytes_per_row;

        if (bytes_to_retreat >= self.offset) {
            self.offset = 0;
        } else {
            self.offset -= bytes_to_retreat;
        }
    }

    /// Auto-scroll offset so selected byte is visible in viewport
    pub fn scrollToSelected(self: *HexViewer, visible_rows: usize) void {
        const sel = self.selected orelse return;
        if (visible_rows == 0) return;

        const sel_row = sel / self.bytes_per_row;
        const current_first = self.offset / self.bytes_per_row;
        const current_last = current_first + visible_rows - 1;

        if (sel_row < current_first) {
            self.offset = sel_row * self.bytes_per_row;
        } else if (sel_row > current_last) {
            self.offset = (sel_row - visible_rows + 1) * self.bytes_per_row;
        }
    }

    // ========== Builder API ==========

    /// Set data (returns new HexViewer)
    pub fn withData(self: HexViewer, data: []const u8) HexViewer {
        var result = self;
        result.data = data;
        return result;
    }

    /// Set offset (already aligned)
    pub fn withOffset(self: HexViewer, offset: usize) HexViewer {
        var result = self;
        result.offset = offset;
        return result;
    }

    /// Set selected byte index
    pub fn withSelected(self: HexViewer, selected: ?usize) HexViewer {
        var result = self;
        result.selected = selected;
        return result;
    }

    /// Set bytes per row
    pub fn withBytesPerRow(self: HexViewer, bpr: u8) HexViewer {
        var result = self;
        result.bytes_per_row = bpr;
        return result;
    }

    /// Set group size
    pub fn withGroupSize(self: HexViewer, gs: u8) HexViewer {
        var result = self;
        result.group_size = gs;
        return result;
    }

    /// Set block
    pub fn withBlock(self: HexViewer, block: Block) HexViewer {
        var result = self;
        result.block = block;
        return result;
    }

    /// Set address style
    pub fn withAddressStyle(self: HexViewer, style: Style) HexViewer {
        var result = self;
        result.address_style = style;
        return result;
    }

    /// Set hex style
    pub fn withHexStyle(self: HexViewer, style: Style) HexViewer {
        var result = self;
        result.hex_style = style;
        return result;
    }

    /// Set ASCII style
    pub fn withAsciiStyle(self: HexViewer, style: Style) HexViewer {
        var result = self;
        result.ascii_style = style;
        return result;
    }

    /// Set selected style
    pub fn withSelectedStyle(self: HexViewer, style: Style) HexViewer {
        var result = self;
        result.selected_style = style;
        return result;
    }

    /// Set show_ascii flag
    pub fn withShowAscii(self: HexViewer, show: bool) HexViewer {
        var result = self;
        result.show_ascii = show;
        return result;
    }

    /// Set show_address flag
    pub fn withShowAddress(self: HexViewer, show: bool) HexViewer {
        var result = self;
        result.show_address = show;
        return result;
    }

    // ========== Rendering ==========

    /// Render HexViewer to buffer at given area
    pub fn render(self: HexViewer, buf: *Buffer, area: Rect) void {
        // Apply block if present
        const inner_area = if (self.block) |block| block.inner(area) else area;

        // Render block border
        if (self.block) |block| {
            block.render(buf, area);
        }

        // Return early if no space
        if (inner_area.width == 0 or inner_area.height == 0) return;
        if (self.data.len == 0) return;

        // Render each visible row
        var row: u16 = 0;
        while (row < inner_area.height) : (row += 1) {
            const byte_start = self.offset + row * self.bytes_per_row;
            if (byte_start >= self.data.len) break;

            const byte_end = @min(
                byte_start + self.bytes_per_row,
                self.data.len,
            );
            const bytes_in_row = byte_end - byte_start;

            var col: u16 = 0;

            // Address column
            if (self.show_address) {
                var addr_buf: [10]u8 = undefined;
                const addr_str = std.fmt.bufPrint(
                    &addr_buf,
                    "{x}",
                    .{byte_start},
                ) catch "00000000";

                // Pad to 8 characters
                var padded_buf: [8]u8 = undefined;
                var pad_idx: usize = 0;
                const start_idx = 8 - addr_str.len;

                // Fill leading zeros
                while (pad_idx < start_idx) : (pad_idx += 1) {
                    padded_buf[pad_idx] = '0';
                }

                // Copy address
                while (pad_idx < 8 and (pad_idx - start_idx) < addr_str.len) : (pad_idx += 1) {
                    padded_buf[pad_idx] = addr_str[pad_idx - start_idx];
                }

                buf.setString(
                    inner_area.x + col,
                    inner_area.y + row,
                    padded_buf[0..8],
                    self.address_style,
                );
                col += 8;

                // Two spaces after address
                buf.set(
                    inner_area.x + col,
                    inner_area.y + row,
                    Cell.init(' ', self.address_style),
                );
                col += 1;
                buf.set(
                    inner_area.x + col,
                    inner_area.y + row,
                    Cell.init(' ', self.address_style),
                );
                col += 1;
            }

            // Hex bytes
            for (byte_start..byte_end) |byte_idx| {
                if (byte_idx > byte_start and (byte_idx - byte_start) % self.group_size == 0) {
                    // Extra space between groups
                    buf.set(
                        inner_area.x + col,
                        inner_area.y + row,
                        Cell.init(' ', .{}),
                    );
                    col += 1;
                }

                const byte_val = self.data[byte_idx];
                var hex_buf: [4]u8 = undefined;
                const hex_str = std.fmt.bufPrint(
                    &hex_buf,
                    "{x}",
                    .{byte_val},
                ) catch "";

                // Pad to 2 characters
                var hex_padded: [2]u8 = undefined;
                if (hex_str.len == 1) {
                    hex_padded[0] = '0';
                    hex_padded[1] = hex_str[0];
                } else if (hex_str.len >= 2) {
                    hex_padded[0] = hex_str[0];
                    hex_padded[1] = hex_str[1];
                } else {
                    hex_padded[0] = '0';
                    hex_padded[1] = '0';
                }

                const is_selected = self.selected == byte_idx;
                const style = if (is_selected) self.selected_style else self.hex_style;

                buf.setString(
                    inner_area.x + col,
                    inner_area.y + row,
                    hex_padded[0..2],
                    style,
                );
                col += 2;

                // Space after byte
                buf.set(
                    inner_area.x + col,
                    inner_area.y + row,
                    Cell.init(' ', .{}),
                );
                col += 1;
            }

            // Padding spaces for partial row (align ASCII panel)
            var padding_idx = bytes_in_row;
            while (padding_idx < self.bytes_per_row) : (padding_idx += 1) {
                if (padding_idx > 0 and padding_idx % self.group_size == 0) {
                    buf.set(
                        inner_area.x + col,
                        inner_area.y + row,
                        Cell.init(' ', .{}),
                    );
                    col += 1;
                }
                buf.set(
                    inner_area.x + col,
                    inner_area.y + row,
                    Cell.init(' ', .{}),
                );
                col += 1;
                buf.set(
                    inner_area.x + col,
                    inner_area.y + row,
                    Cell.init(' ', .{}),
                );
                col += 1;
                buf.set(
                    inner_area.x + col,
                    inner_area.y + row,
                    Cell.init(' ', .{}),
                );
                col += 1;
            }

            // ASCII panel
            if (self.show_ascii) {
                buf.set(
                    inner_area.x + col,
                    inner_area.y + row,
                    Cell.init('|', self.ascii_style),
                );
                col += 1;

                for (byte_start..byte_end) |byte_idx| {
                    const byte_val = self.data[byte_idx];
                    const is_selected = self.selected == byte_idx;
                    const style = if (is_selected) self.selected_style else self.ascii_style;

                    // Printable ASCII or '.'
                    const char: u21 = if (byte_val >= 32 and byte_val < 127)
                        @as(u21, byte_val)
                    else
                        '.';

                    buf.set(
                        inner_area.x + col,
                        inner_area.y + row,
                        Cell.init(char, style),
                    );
                    col += 1;
                }

                buf.set(
                    inner_area.x + col,
                    inner_area.y + row,
                    Cell.init('|', self.ascii_style),
                );
            }
        }
    }
};

// ============================================================================
// TESTS
// ============================================================================

const testing = std.testing;

test "HexViewer basic init" {
    const data = "Hello";
    const hv = HexViewer.init(data);
    try testing.expectEqual(data.len, hv.byteCount());
    try testing.expectEqual(@as(usize, 0), hv.offset);
    try testing.expectEqual(@as(?usize, null), hv.selected);
}

test "HexViewer totalRows calculation" {
    const data: [17]u8 = undefined;
    const hv = HexViewer.init(&data);
    try testing.expectEqual(@as(usize, 2), hv.totalRows());
}

test "HexViewer selectedByte" {
    const data = "Hello";
    var hv = HexViewer.init(data);
    hv = hv.withSelected(0);
    try testing.expectEqual(@as(?u8, 'H'), hv.selectedByte());
}

test "HexViewer selectNext" {
    const data = "Hello";
    var hv = HexViewer.init(data);
    hv.selectNext();
    try testing.expectEqual(@as(?usize, 0), hv.selected);
}

test "HexViewer selectPrev with null" {
    const data = "Hello";
    var hv = HexViewer.init(data);
    hv.selectPrev();
    try testing.expectEqual(@as(?usize, null), hv.selected);
}

test "HexViewer pageDown" {
    var data: [50]u8 = undefined;
    var hv = HexViewer.init(&data);
    hv.pageDown(1);
    try testing.expectEqual(@as(usize, 16), hv.offset);
}

test "HexViewer pageUp clamping" {
    var data: [100]u8 = undefined;
    var hv = HexViewer.init(&data);
    hv = hv.withOffset(0);
    hv.pageUp(1);
    try testing.expectEqual(@as(usize, 0), hv.offset);
}

test "HexViewer withData builder" {
    const data1 = "Hello";
    const data2 = "World";
    var hv = HexViewer.init(data1);
    hv = hv.withData(data2);
    try testing.expectEqual(data2.len, hv.byteCount());
}

test "HexViewer render basic" {
    const data = "A";
    var hv = HexViewer.init(data);
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    hv.render(&buf, area);
    // Basic smoke test - should not crash
    try testing.expect(buf.width > 0);
}
