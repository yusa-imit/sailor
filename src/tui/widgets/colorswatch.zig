//! ColorSwatch Widget — a grid of color swatches with selection navigation
//!
//! ColorSwatch displays a grid of color values with optional labels below each swatch.
//! It supports selection navigation (up/down/left/right), optional block borders,
//! and configurable swatch dimensions.
//!
//! ## Features
//! - Grid layout of color swatches
//! - Selection marker (●, U+25CF) on selected color
//! - Optional text labels below swatches
//! - Block border support
//! - Four-directional and linear navigation
//!
//! ## Usage
//! ```zig
//! const colors = [_]Color{ .red, .green, .blue, .yellow };
//! const cs = ColorSwatch.init(&colors)
//!     .withColumns(4)
//!     .withSwatchWidth(5)
//!     .withSwatchHeight(2)
//!     .withShowLabels(true);
//! cs.render(&buf, area);
//! ```

const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Cell = @import("../buffer.zig").Cell;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;

/// Color swatch grid widget
pub const ColorSwatch = struct {
    colors: []const Color = &.{},
    labels: []const []const u8 = &.{},
    selected: usize = 0,
    columns: u16 = 4,
    swatch_width: u16 = 3,
    swatch_height: u16 = 1,
    show_labels: bool = false,
    style: Style = .{},
    selected_style: Style = .{ .fg = .white, .bold = true },
    label_style: Style = .{ .fg = .white },
    block: ?Block = null,

    /// Initialize with a slice of colors
    pub fn init(colors: []const Color) ColorSwatch {
        return ColorSwatch{ .colors = colors };
    }

    /// Get the currently selected color, or null if empty
    pub fn selectedColor(self: ColorSwatch) ?Color {
        if (self.colors.len == 0) return null;
        if (self.selected >= self.colors.len) return null;
        return self.colors[self.selected];
    }

    /// Move selection to next color (wrapping at end)
    pub fn selectNext(self: *ColorSwatch) void {
        if (self.colors.len == 0) return;
        self.selected = (self.selected + 1) % self.colors.len;
    }

    /// Move selection to previous color (wrapping at start)
    pub fn selectPrev(self: *ColorSwatch) void {
        if (self.colors.len == 0) return;
        self.selected = if (self.selected == 0) self.colors.len - 1 else self.selected - 1;
    }

    /// Move selection right within grid (same as selectNext)
    pub fn selectRight(self: *ColorSwatch) void {
        if (self.colors.len == 0) return;
        self.selected = (self.selected + 1) % self.colors.len;
    }

    /// Move selection left within grid (same as selectPrev)
    pub fn selectLeft(self: *ColorSwatch) void {
        if (self.colors.len == 0) return;
        self.selected = if (self.selected == 0) self.colors.len - 1 else self.selected - 1;
    }

    /// Move selection down by columns
    pub fn selectDown(self: *ColorSwatch) void {
        if (self.colors.len == 0) return;
        const cols = @as(usize, self.columns);
        const new = self.selected + cols;
        self.selected = if (new >= self.colors.len) self.colors.len - 1 else new;
    }

    /// Move selection up by columns
    pub fn selectUp(self: *ColorSwatch) void {
        if (self.colors.len == 0) return;
        const cols = @as(usize, self.columns);
        self.selected = if (self.selected < cols) 0 else self.selected - cols;
    }

    /// Builder: set colors
    pub fn withColors(self: ColorSwatch, c: []const Color) ColorSwatch {
        var r = self;
        r.colors = c;
        return r;
    }

    /// Builder: set labels
    pub fn withLabels(self: ColorSwatch, l: []const []const u8) ColorSwatch {
        var r = self;
        r.labels = l;
        return r;
    }

    /// Builder: set selected index (clamped to valid range)
    pub fn withSelected(self: ColorSwatch, idx: usize) ColorSwatch {
        var r = self;
        if (self.colors.len > 0) {
            r.selected = if (idx >= self.colors.len) self.colors.len - 1 else idx;
        } else {
            r.selected = 0;
        }
        return r;
    }

    /// Builder: set number of columns
    pub fn withColumns(self: ColorSwatch, n: u16) ColorSwatch {
        var r = self;
        r.columns = n;
        return r;
    }

    /// Builder: set swatch width
    pub fn withSwatchWidth(self: ColorSwatch, w: u16) ColorSwatch {
        var r = self;
        r.swatch_width = w;
        return r;
    }

    /// Builder: set swatch height
    pub fn withSwatchHeight(self: ColorSwatch, h: u16) ColorSwatch {
        var r = self;
        r.swatch_height = h;
        return r;
    }

    /// Builder: set show_labels
    pub fn withShowLabels(self: ColorSwatch, v: bool) ColorSwatch {
        var r = self;
        r.show_labels = v;
        return r;
    }

    /// Builder: set base style
    pub fn withStyle(self: ColorSwatch, s: Style) ColorSwatch {
        var r = self;
        r.style = s;
        return r;
    }

    /// Builder: set selected style
    pub fn withSelectedStyle(self: ColorSwatch, s: Style) ColorSwatch {
        var r = self;
        r.selected_style = s;
        return r;
    }

    /// Builder: set label style
    pub fn withLabelStyle(self: ColorSwatch, s: Style) ColorSwatch {
        var r = self;
        r.label_style = s;
        return r;
    }

    /// Builder: set block border
    pub fn withBlock(self: ColorSwatch, b: Block) ColorSwatch {
        var r = self;
        r.block = b;
        return r;
    }

    /// Render the color swatch grid
    pub fn render(self: ColorSwatch, buf: *Buffer, area: Rect) void {
        // Early exit for invalid areas
        if (area.width == 0 or area.height == 0) return;
        if (self.colors.len == 0) return;

        // Render block if present and compute inner area
        var inner = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner = blk.inner(area);
        }

        if (inner.width == 0 or inner.height == 0) return;

        // Compute cell height (swatch + optional label row)
        const cell_h: u16 = self.swatch_height + if (self.show_labels) @as(u16, 1) else 0;

        // Determine which row the selected item is in
        const cols = @as(usize, self.columns);
        const selected_row_idx = self.selected / cols;

        // Compute scroll offset to keep selected row visible
        const visible_rows = inner.height / cell_h;
        const scroll_start: usize = blk: {
            if (visible_rows == 0) break :blk selected_row_idx;
            if (selected_row_idx < visible_rows) break :blk 0;
            break :blk selected_row_idx - (visible_rows - 1);
        };

        // Render visible grid rows
        const total_rows = (self.colors.len + cols - 1) / cols;
        var row_idx: usize = scroll_start;
        var screen_row: u16 = 0;

        while (row_idx < total_rows and screen_row + cell_h <= inner.height) {
            defer {
                row_idx += 1;
                screen_row += cell_h;
            }

            var col_idx: usize = 0;
            while (col_idx < cols) {
                defer col_idx += 1;

                const item_idx = row_idx * cols + col_idx;
                if (item_idx >= self.colors.len) break;

                const cell_x = inner.x + @as(u16, @intCast(col_idx)) * self.swatch_width;
                const cell_y = inner.y + screen_row;

                // Check horizontal bounds
                if (cell_x >= inner.x + inner.width) break;

                const color = self.colors[item_idx];
                const cell_style = Style{ .bg = color };

                // Fill swatch area with color background
                var sy: u16 = 0;
                while (sy < self.swatch_height) {
                    defer sy += 1;

                    if (cell_y + sy >= inner.y + inner.height) break;

                    var sx: u16 = 0;
                    while (sx < self.swatch_width) {
                        defer sx += 1;

                        const px = cell_x + sx;
                        if (px >= inner.x + inner.width) break;

                        if (buf.get(px, cell_y + sy)) |cell| {
                            cell.char = ' ';
                            cell.style = cell_style;
                        }
                    }
                }

                // Selection marker: place '●' (0x25CF) at center of swatch
                if (item_idx == self.selected) {
                    const marker_x = cell_x + self.swatch_width / 2;
                    const marker_y = cell_y + self.swatch_height / 2;

                    if (marker_x < inner.x + inner.width and marker_y < inner.y + inner.height) {
                        if (buf.get(marker_x, marker_y)) |cell| {
                            cell.char = 0x25CF; // '●'
                            cell.style = Style{
                                .fg = self.selected_style.fg,
                                .bg = color,
                                .bold = self.selected_style.bold,
                            };
                        }
                    }
                }

                // Labels row (if show_labels and cell_h > swatch_height)
                if (self.show_labels and cell_h > self.swatch_height) {
                    const label_y = cell_y + self.swatch_height;
                    if (label_y < inner.y + inner.height) {
                        // Get label text
                        const label_text: []const u8 = if (item_idx < self.labels.len)
                            self.labels[item_idx]
                        else
                            "";

                        // Render label text (truncated to swatch_width)
                        var lx: u16 = 0;
                        for (label_text) |byte| {
                            if (lx >= self.swatch_width) break;

                            const px = cell_x + lx;
                            if (px >= inner.x + inner.width) break;

                            if (buf.get(px, label_y)) |cell| {
                                cell.char = @as(u21, byte);
                                cell.style = self.label_style;
                            }

                            lx += 1;
                        }
                    }
                }
            }
        }
    }
};
