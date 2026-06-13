//! KeyMap Widget — Keyboard shortcut reference panel
//!
//! A scrollable widget for displaying keyboard shortcuts organized by sections.
//! Supports:
//! - Section-based organization (title + bindings)
//! - Scrolling (scrollDown, scrollUp, pageDown, pageUp, goToTop, goToBottom)
//! - 1-column and 2-column layouts
//! - Builder API for style customization
//! - Block borders (optional)

const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Block = @import("block.zig").Block;

/// A single key binding (key + description)
pub const KeyBinding = struct {
    key: []const u8,
    description: []const u8,
};

/// A section containing a title and multiple bindings
pub const KeySection = struct {
    title: []const u8,
    bindings: []const KeyBinding,
};

/// KeyMap widget for displaying keyboard shortcuts
pub const KeyMap = struct {
    sections: []const KeySection,
    scroll_offset: usize = 0,
    columns: u8 = 1,
    key_width: u8 = 10,
    block: ?Block = null,
    key_style: Style = .{},
    desc_style: Style = .{},
    section_style: Style = .{},

    /// Initialize KeyMap with sections
    pub fn init(sections: []const KeySection) KeyMap {
        return KeyMap{
            .sections = sections,
            .scroll_offset = 0,
            .columns = 1,
            .key_width = 10,
            .block = null,
            .key_style = .{},
            .desc_style = .{},
            .section_style = .{},
        };
    }

    /// Calculate total number of rows needed to display all content
    /// - Each section title takes 1 row
    /// - Bindings are laid out based on columns setting:
    ///   - columns=1: each binding takes 1 row
    ///   - columns=N: ceil(bindings.len / N) rows per section
    pub fn totalRows(self: KeyMap) usize {
        var total: usize = 0;

        for (self.sections) |section| {
            // Title row
            total += 1;

            // Binding rows
            if (self.columns == 1) {
                // Single column: one binding per row
                total += section.bindings.len;
            } else {
                // Multi-column: ceil(bindings.len / columns)
                const binding_count: u16 = @intCast(section.bindings.len);
                const col_count: u16 = self.columns;
                const rows_for_section = (binding_count + col_count - 1) / col_count;
                total += rows_for_section;
            }
        }

        return total;
    }

    /// Scroll down by 1 row (clamped to totalRows)
    pub fn scrollDown(self: *KeyMap) void {
        const max = self.totalRows();
        if (max == 0) return;
        if (self.scroll_offset < max) {
            self.scroll_offset += 1;
        }
    }

    /// Scroll up by 1 row (clamped to 0)
    pub fn scrollUp(self: *KeyMap) void {
        if (self.scroll_offset > 0) {
            self.scroll_offset -= 1;
        }
    }

    /// Page down by height rows (clamped to totalRows)
    pub fn pageDown(self: *KeyMap, height: u16) void {
        if (height == 0) return;
        const max = self.totalRows();
        if (max == 0) return;
        const step: usize = @intCast(height);
        const new_offset = self.scroll_offset + step;
        self.scroll_offset = @min(new_offset, max);
    }

    /// Page up by height rows (clamped to 0)
    pub fn pageUp(self: *KeyMap, height: u16) void {
        if (height == 0) return;
        const step: usize = @intCast(height);
        if (self.scroll_offset >= step) {
            self.scroll_offset -= step;
        } else {
            self.scroll_offset = 0;
        }
    }

    /// Go to top of content
    pub fn goToTop(self: *KeyMap) void {
        self.scroll_offset = 0;
    }

    /// Go to bottom of content
    pub fn goToBottom(self: *KeyMap) void {
        const max = self.totalRows();
        if (max == 0) return;
        self.scroll_offset = max;
    }

    /// Builder: set block
    pub fn withBlock(self: KeyMap, block: Block) KeyMap {
        var result = self;
        result.block = block;
        return result;
    }

    /// Builder: set key style
    pub fn withKeyStyle(self: KeyMap, style: Style) KeyMap {
        var result = self;
        result.key_style = style;
        return result;
    }

    /// Builder: set description style
    pub fn withDescStyle(self: KeyMap, style: Style) KeyMap {
        var result = self;
        result.desc_style = style;
        return result;
    }

    /// Builder: set section title style
    pub fn withSectionStyle(self: KeyMap, style: Style) KeyMap {
        var result = self;
        result.section_style = style;
        return result;
    }

    /// Builder: set number of columns
    pub fn withColumns(self: KeyMap, n: u8) KeyMap {
        var result = self;
        result.columns = @max(1, n); // Ensure at least 1 column
        return result;
    }

    /// Builder: set key column width
    pub fn withKeyWidth(self: KeyMap, w: u8) KeyMap {
        var result = self;
        result.key_width = w;
        return result;
    }

    /// Render KeyMap to buffer
    pub fn render(self: KeyMap, buf: *Buffer, area: Rect) void {
        // Early exit for zero-area
        if (area.width == 0 or area.height == 0) return;

        // Determine render area (apply block border if set)
        var inner_area = area;
        if (self.block) |block| {
            block.render(buf, area);
            // Get inner area by applying border width
            if (area.x + 1 < area.x + area.width and area.y + 1 < area.y + area.height) {
                inner_area = Rect{
                    .x = area.x + 1,
                    .y = area.y + 1,
                    .width = if (area.width > 2) area.width - 2 else 0,
                    .height = if (area.height > 2) area.height - 2 else 0,
                };
            } else {
                return;
            }
        }

        if (inner_area.width == 0 or inner_area.height == 0) return;

        // Build virtual row list and render visible rows
        self.renderContent(buf, inner_area);
    }

    /// Internal: render content rows
    fn renderContent(self: KeyMap, buf: *Buffer, area: Rect) void {
        var virtual_row: usize = 0;

        // Iterate through sections
        for (self.sections) |section| {
            // Render section title row
            if (virtual_row >= self.scroll_offset) {
                const screen_offset = virtual_row - self.scroll_offset;
                if (screen_offset < area.height) {
                    const screen_y: u16 = @intCast(area.y + screen_offset);
                    buf.setString(area.x, screen_y, section.title, self.section_style);
                }
            }
            virtual_row += 1;

            // Render bindings
            if (self.columns == 1) {
                // Single-column layout
                for (section.bindings) |binding| {
                    if (virtual_row >= self.scroll_offset) {
                        const screen_offset = virtual_row - self.scroll_offset;
                        if (screen_offset < area.height) {
                            const screen_y: u16 = @intCast(area.y + screen_offset);
                            self.renderBindingRow(buf, area, screen_y, &[_]KeyBinding{binding}, 1);
                        }
                    }
                    virtual_row += 1;
                }
            } else {
                // Multi-column layout: group bindings into rows
                var binding_idx: usize = 0;
                while (binding_idx < section.bindings.len) {
                    if (virtual_row >= self.scroll_offset) {
                        const screen_offset = virtual_row - self.scroll_offset;
                        if (screen_offset < area.height) {
                            const screen_y: u16 = @intCast(area.y + screen_offset);
                            const bindings_in_row = @min(self.columns, @as(u8, @intCast(section.bindings.len - binding_idx)));

                            // Create temporary array of bindings for this row
                            var row_bindings: [256]KeyBinding = undefined;
                            for (0..bindings_in_row) |i| {
                                row_bindings[i] = section.bindings[binding_idx + i];
                            }

                            self.renderBindingRow(buf, area, screen_y, &row_bindings, bindings_in_row);
                        }
                    }

                    const col_count: usize = self.columns;
                    binding_idx += col_count;
                    virtual_row += 1;
                }
            }
        }
    }

    /// Internal: render a single binding row (1 or more bindings depending on columns)
    fn renderBindingRow(self: KeyMap, buf: *Buffer, area: Rect, y: u16, bindings: []const KeyBinding, count: u8) void {
        if (count == 0) return;

        const padding_array = " " ** 256;
        const col_count: u16 = self.columns;
        const col_width: u16 = area.width / col_count;

        for (0..count) |col_idx| {
            const binding = bindings[col_idx];
            const col_start_x: u16 = area.x + @as(u16, @intCast(col_idx)) * col_width;

            // Render key (padded to key_width)
            const key_len: usize = @min(binding.key.len, self.key_width);
            if (col_start_x < area.x + area.width) {
                buf.setString(col_start_x, y, binding.key[0..key_len], self.key_style);

                // Add padding after key
                if (key_len < self.key_width) {
                    const padding_len = self.key_width - @as(u8, @intCast(key_len));
                    const pad_to_write: usize = @min(padding_len, padding_array.len);
                    if (col_start_x + key_len < area.x + area.width) {
                        buf.setString(col_start_x + @as(u16, @intCast(key_len)), y, padding_array[0..pad_to_write], self.desc_style);
                    }
                }
            }

            // Render description after key column
            const desc_start_x: u16 = col_start_x + self.key_width;
            if (desc_start_x < area.x + area.width) {
                const available_width = (area.x + area.width) - desc_start_x;
                const desc_len: usize = @min(binding.description.len, available_width);
                if (desc_len > 0) {
                    buf.setString(desc_start_x, y, binding.description[0..desc_len], self.desc_style);
                }
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "KeyMap exports check" {
    _ = KeyMap;
    _ = KeyBinding;
    _ = KeySection;
}
