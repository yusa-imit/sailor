//! Inspector Widget — Collapsible Key-Value Property Inspector
//!
//! A widget that displays structured key-value pairs with support for:
//! - Hierarchical nesting via depth field
//! - Text filtering on keys (case-insensitive substring match)
//! - Scroll navigation and clamping
//! - Type annotations for each field
//! - Customizable styling for keys, values, and types
//! - Optional block border

const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Block = @import("block.zig").Block;

/// A single field in the inspector
pub const InspectorField = struct {
    key: []const u8,
    value: []const u8,
    field_type: []const u8 = "",
    depth: u8 = 0,
};

/// Inspector widget — displays key-value properties with filtering and navigation
pub const Inspector = struct {
    fields: []const InspectorField,
    scroll_offset: usize = 0,
    filter_query: []const u8 = "",
    show_types: bool = false,
    show_filter: bool = false,
    block: ?Block = null,
    key_style: Style = .{},
    value_style: Style = .{},
    type_style: Style = .{ .fg = .bright_black },
    filter_style: Style = .{ .bold = true },

    /// Initialize a new inspector with fields
    pub fn init(fields: []const InspectorField) Inspector {
        return Inspector{
            .fields = fields,
            .scroll_offset = 0,
            .filter_query = "",
            .show_types = false,
            .show_filter = false,
            .block = null,
            .key_style = .{},
            .value_style = .{},
            .type_style = .{ .fg = .bright_black },
            .filter_style = .{ .bold = true },
        };
    }

    /// Scroll down one field (clamps to last visible field)
    pub fn scrollDown(self: *Inspector) void {
        const visible = self.visibleCount();
        if (visible == 0) return;
        if (self.scroll_offset < visible - 1) {
            self.scroll_offset += 1;
        }
    }

    /// Scroll up one field (clamps to 0)
    pub fn scrollUp(self: *Inspector) void {
        if (self.scroll_offset > 0) {
            self.scroll_offset -= 1;
        }
    }

    /// Go to first visible field
    pub fn goToTop(self: *Inspector) void {
        self.scroll_offset = 0;
    }

    /// Go to last visible field
    pub fn goToBottom(self: *Inspector) void {
        const visible = self.visibleCount();
        if (visible > 0) {
            self.scroll_offset = visible - 1;
        } else {
            self.scroll_offset = 0;
        }
    }

    /// Filter fields by key (case-insensitive substring match)
    /// Clamps scroll_offset if visible count changes
    pub fn filterBy(self: *Inspector, query: []const u8) void {
        self.filter_query = query;
        // Clamp scroll_offset to valid range
        const visible = self.visibleCount();
        if (visible == 0) {
            self.scroll_offset = 0;
        } else if (self.scroll_offset >= visible) {
            self.scroll_offset = visible - 1;
        }
    }

    /// Clear filter (show all fields)
    pub fn clearFilter(self: *Inspector) void {
        self.filter_query = "";
    }

    /// Builder: set block border
    pub fn withBlock(self: Inspector, block: Block) Inspector {
        var result = self;
        result.block = block;
        return result;
    }

    /// Builder: set key style
    pub fn withKeyStyle(self: Inspector, style: Style) Inspector {
        var result = self;
        result.key_style = style;
        return result;
    }

    /// Builder: set value style
    pub fn withValueStyle(self: Inspector, style: Style) Inspector {
        var result = self;
        result.value_style = style;
        return result;
    }

    /// Builder: set type annotation style
    pub fn withTypeStyle(self: Inspector, style: Style) Inspector {
        var result = self;
        result.type_style = style;
        return result;
    }

    /// Builder: set filter display style
    pub fn withFilterStyle(self: Inspector, style: Style) Inspector {
        var result = self;
        result.filter_style = style;
        return result;
    }

    /// Builder: enable/disable type display
    pub fn withShowTypes(self: Inspector, show: bool) Inspector {
        var result = self;
        result.show_types = show;
        return result;
    }

    /// Builder: enable/disable filter row display
    pub fn withShowFilter(self: Inspector, show: bool) Inspector {
        var result = self;
        result.show_filter = show;
        return result;
    }

    /// Render inspector to buffer
    pub fn render(self: *Inspector, buf: *Buffer, area: Rect) void {
        // Early return for zero-area
        if (area.width == 0 or area.height == 0) return;

        var content_area = area;

        // Render block border if present
        if (self.block) |block| {
            block.render(buf, area);
            // Shrink content area by 1 each side
            if (content_area.x + 1 >= content_area.x + content_area.width or
                content_area.y + 1 >= content_area.y + content_area.height)
            {
                return; // Content area too small
            }
            content_area.x += 1;
            content_area.y += 1;
            if (content_area.width >= 2) content_area.width -= 2;
            if (content_area.height >= 2) content_area.height -= 2;
            if (content_area.width == 0 or content_area.height == 0) return;
        }

        var row = content_area.y;
        const max_row = content_area.y + content_area.height;

        // Render filter row if enabled
        if (self.show_filter and row < max_row) {
            self.renderFilterRow(buf, content_area.x, row, content_area.width);
            row += 1;
        }

        // Render visible fields
        var visible_idx: usize = 0;
        for (self.fields) |field| {
            if (!self.isVisible(field)) continue;

            // Skip fields before scroll_offset
            if (visible_idx < self.scroll_offset) {
                visible_idx += 1;
                continue;
            }

            // Stop if we've filled the available height
            if (row >= max_row) break;

            self.renderField(buf, field, content_area.x, row, content_area.width);
            row += 1;
            visible_idx += 1;
        }
    }

    // ========== Private Helpers ==========

    /// Count visible fields (respecting filter)
    fn visibleCount(self: Inspector) usize {
        var count: usize = 0;
        for (self.fields) |field| {
            if (self.isVisible(field)) {
                count += 1;
            }
        }
        return count;
    }

    /// Check if field is visible (filter match or no filter)
    fn isVisible(self: Inspector, field: InspectorField) bool {
        if (self.filter_query.len == 0) return true;
        return containsInsensitive(field.key, self.filter_query);
    }

    /// Case-insensitive substring search
    fn containsInsensitive(haystack: []const u8, needle: []const u8) bool {
        if (needle.len == 0) return true;
        if (needle.len > haystack.len) return false;

        for (0..haystack.len - needle.len + 1) |i| {
            if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) {
                return true;
            }
        }
        return false;
    }

    /// Render the filter row showing "Filter: <query>"
    fn renderFilterRow(self: Inspector, buf: *Buffer, x: u16, y: u16, width: u16) void {
        if (width == 0) return;
        buf.setString(x, y, "Filter: ", self.filter_style);
        const prefix_len = 8;
        if (x + prefix_len < x + width) {
            buf.setString(x + @as(u16, @intCast(prefix_len)), y, self.filter_query, self.filter_style);
        }
    }

    /// Render a single field row
    fn renderField(self: Inspector, buf: *Buffer, field: InspectorField, x: u16, y: u16, width: u16) void {
        if (width == 0) return;

        var col = x;
        const max_col = x + width;

        // Render indentation (depth * 2 spaces)
        const indent_width = field.depth * 2;
        var indent_idx: u16 = 0;
        while (indent_idx < indent_width and col < max_col) : (indent_idx += 1) {
            buf.setString(col, y, " ", self.key_style);
            col += 1;
        }

        // Render key
        if (col < max_col) {
            buf.setString(col, y, field.key, self.key_style);
            col += @as(u16, @intCast(field.key.len));
        }

        // Render separator ": "
        if (col < max_col) {
            buf.setString(col, y, ": ", self.key_style);
            col += 2;
        }

        // Render value
        if (col < max_col) {
            buf.setString(col, y, field.value, self.value_style);
            col += @as(u16, @intCast(field.value.len));
        }

        // Render type annotation if enabled
        if (self.show_types and field.field_type.len > 0 and col < max_col) {
            buf.setString(col, y, " [", self.type_style);
            col += 2;
            if (col < max_col) {
                buf.setString(col, y, field.field_type, self.type_style);
                col += @as(u16, @intCast(field.field_type.len));
            }
            if (col < max_col) {
                buf.setString(col, y, "]", self.type_style);
            }
        }
    }
};
