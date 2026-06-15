//! KeyValueViewer Widget — two-column key-value pair viewer.
//!
//! Displays key-value pair data in a two-column layout with optional
//! block border, row selection, and keyboard navigation.
//!
//! ## Usage
//! ```zig
//! const entries = [_]KeyValueViewer.Entry{
//!     .{ .key = "host", .value = "localhost" },
//!     .{ .key = "port", .value = "6379" },
//! };
//! var viewer = KeyValueViewer.init(&entries);
//! viewer.render(&buf, area);
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

/// KeyValueViewer widget — displays key-value pairs in two columns
pub const KeyValueViewer = struct {
    pub const Entry = struct {
        key: []const u8,
        value: []const u8,
    };

    pub const KeyWidth = union(enum) {
        auto: void,
        fixed: u16,
    };

    entries: []const Entry,
    selected: ?usize = null,
    offset: usize = 0,
    key_width: KeyWidth = .auto,
    separator: []const u8 = ": ",
    key_style: Style = .{},
    value_style: Style = .{},
    selected_key_style: Style = .{},
    selected_value_style: Style = .{},
    block: ?Block = null,

    /// Create a new KeyValueViewer with entries
    pub fn init(entries: []const Entry) KeyValueViewer {
        return .{ .entries = entries };
    }

    /// Get number of entries
    pub fn count(self: KeyValueViewer) usize {
        return self.entries.len;
    }

    /// Compute the key column width based on key_width mode
    pub fn computeKeyWidth(self: KeyValueViewer) usize {
        switch (self.key_width) {
            .fixed => |w| return w,
            .auto => {
                var max: usize = 0;
                for (self.entries) |entry| {
                    if (entry.key.len > max) max = entry.key.len;
                }
                return max;
            },
        }
    }

    /// Get currently selected entry, or null
    pub fn selectedEntry(self: KeyValueViewer) ?Entry {
        if (self.selected) |sel| {
            if (sel < self.entries.len) {
                return self.entries[sel];
            }
        }
        return null;
    }

    /// Move to next entry, clamp at last
    pub fn selectNext(self: *KeyValueViewer) void {
        if (self.entries.len == 0) return;

        if (self.selected) |sel| {
            if (sel < self.entries.len - 1) {
                self.selected = sel + 1;
            }
            // else: stay at last
        } else {
            self.selected = 0;
        }

        // Auto-scroll (estimate 10 visible rows)
        self.scrollToSelected(10);
    }

    /// Move to previous entry, clamp at 0
    pub fn selectPrev(self: *KeyValueViewer) void {
        if (self.entries.len == 0) return;

        if (self.selected) |sel| {
            if (sel > 0) {
                self.selected = sel - 1;
            }
            // else: stay at 0
        }
        // else: null stays null

        // Auto-scroll
        self.scrollToSelected(10);
    }

    /// Auto-scroll offset so selected entry is visible in viewport
    pub fn scrollToSelected(self: *KeyValueViewer, visible_rows: usize) void {
        const sel = self.selected orelse return;
        if (visible_rows == 0) return;

        // If sel is above the viewport, scroll up
        if (sel < self.offset) {
            self.offset = sel;
        }
        // If sel is below the viewport, scroll down
        if (sel >= self.offset + visible_rows) {
            self.offset = sel - visible_rows + 1;
        }
    }

    // ========== Builder API ==========

    /// Set selected entry index (returns new value)
    pub fn withSelected(self: KeyValueViewer, selected: ?usize) KeyValueViewer {
        var result = self;
        result.selected = selected;
        return result;
    }

    /// Set offset (returns new value)
    pub fn withOffset(self: KeyValueViewer, offset: usize) KeyValueViewer {
        var result = self;
        result.offset = offset;
        return result;
    }

    /// Set key_width (returns new value)
    pub fn withKeyWidth(self: KeyValueViewer, key_width: KeyWidth) KeyValueViewer {
        var result = self;
        result.key_width = key_width;
        return result;
    }

    /// Set separator (returns new value)
    pub fn withSeparator(self: KeyValueViewer, separator: []const u8) KeyValueViewer {
        var result = self;
        result.separator = separator;
        return result;
    }

    /// Set key_style (returns new value)
    pub fn withKeyStyle(self: KeyValueViewer, style: Style) KeyValueViewer {
        var result = self;
        result.key_style = style;
        return result;
    }

    /// Set value_style (returns new value)
    pub fn withValueStyle(self: KeyValueViewer, style: Style) KeyValueViewer {
        var result = self;
        result.value_style = style;
        return result;
    }

    /// Set selected_key_style (returns new value)
    pub fn withSelectedKeyStyle(self: KeyValueViewer, style: Style) KeyValueViewer {
        var result = self;
        result.selected_key_style = style;
        return result;
    }

    /// Set selected_value_style (returns new value)
    pub fn withSelectedValueStyle(self: KeyValueViewer, style: Style) KeyValueViewer {
        var result = self;
        result.selected_value_style = style;
        return result;
    }

    /// Set block (returns new value)
    pub fn withBlock(self: KeyValueViewer, block: Block) KeyValueViewer {
        var result = self;
        result.block = block;
        return result;
    }

    /// Render the KeyValueViewer to a buffer in the given area
    pub fn render(self: KeyValueViewer, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        // If we have a block, render it and get the inner area
        const inner = if (self.block) |blk| blk: {
            blk.render(buf, area);
            break :blk blk.inner(area);
        } else area;

        if (inner.width == 0 or inner.height == 0) return;

        const key_col_width = self.computeKeyWidth();
        const sep_len = self.separator.len;

        const visible_rows = inner.height;
        const start = self.offset;
        const end = @min(self.entries.len, start + visible_rows);

        var i = start;
        while (i < end) : (i += 1) {
            const entry = self.entries[i];
            const y = inner.y + @as(u16, @intCast(i - start));
            const is_selected = if (self.selected) |sel| sel == i else false;
            const k_style = if (is_selected) self.selected_key_style else self.key_style;
            const v_style = if (is_selected) self.selected_value_style else self.value_style;

            var x = inner.x;

            // Render key column (padded to key_col_width)
            var ki: usize = 0;
            while (ki < key_col_width and x < inner.x + inner.width) : ({
                ki += 1;
                x += 1;
            }) {
                const ch: u21 = if (ki < entry.key.len) @intCast(entry.key[ki]) else ' ';
                buf.set(x, y, Cell.init(ch, k_style));
            }

            // Render separator
            var si: usize = 0;
            while (si < sep_len and x < inner.x + inner.width) : ({
                si += 1;
                x += 1;
            }) {
                buf.set(x, y, Cell.init(@intCast(self.separator[si]), k_style));
            }

            // Render value (truncated to remaining width)
            var vi: usize = 0;
            while (vi < entry.value.len and x < inner.x + inner.width) : ({
                vi += 1;
                x += 1;
            }) {
                buf.set(x, y, Cell.init(@intCast(entry.value[vi]), v_style));
            }
        }
    }
};
