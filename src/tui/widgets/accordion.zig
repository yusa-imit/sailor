//! Accordion Widget — Expandable Sections with Navigation
//!
//! A collapsible accordion widget that displays multiple sections with expandable/collapsible
//! content areas. Supports single-expand mode (only one section open at a time), keyboard
//! navigation, custom icons, and styling.
//!
//! ## Features
//! - Expandable/collapsible sections
//! - Cursor-based navigation (up/down with wrapping)
//! - Single-expand mode (mutually exclusive sections)
//! - Custom expand/collapse icons
//! - Flexible styling (header, expanded content, cursor)
//! - Optional block border support
//! - Builder pattern API

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Block = @import("block.zig").Block;

/// A single section in an accordion
pub const AccordionSection = struct {
    title: []const u8,
    content_lines: []const []const u8,
    expanded: bool = false,
};

/// Accordion widget — displays collapsible sections
pub const Accordion = struct {
    sections: []AccordionSection,
    cursor: usize = 0,
    single_expand: bool = false,
    block: ?Block = null,
    header_style: Style = .{},
    expanded_style: Style = .{},
    cursor_style: Style = .{ .bold = true, .reverse = true },
    expand_icon: u21 = '▶',
    collapse_icon: u21 = '▼',

    /// Initialize a new accordion with sections
    pub fn init(sections: []AccordionSection) Accordion {
        return Accordion{
            .sections = sections,
            .cursor = 0,
            .single_expand = false,
            .block = null,
            .header_style = .{},
            .expanded_style = .{},
            .cursor_style = .{ .bold = true, .reverse = true },
            .expand_icon = '▶',
            .collapse_icon = '▼',
        };
    }

    /// Toggle expanded state of current section
    pub fn toggleCurrent(self: *Accordion) void {
        if (self.cursor < self.sections.len) {
            self.sections[self.cursor].expanded = !self.sections[self.cursor].expanded;
        }
    }

    /// Expand current section (collapse others if single_expand mode)
    pub fn expandCurrent(self: *Accordion) void {
        if (self.cursor >= self.sections.len) return;

        self.sections[self.cursor].expanded = true;

        if (self.single_expand) {
            for (0..self.sections.len) |i| {
                if (i != self.cursor) {
                    self.sections[i].expanded = false;
                }
            }
        }
    }

    /// Collapse current section
    pub fn collapseCurrent(self: *Accordion) void {
        if (self.cursor < self.sections.len) {
            self.sections[self.cursor].expanded = false;
        }
    }

    /// Expand all sections (ignores single_expand mode)
    pub fn expandAll(self: *Accordion) void {
        for (0..self.sections.len) |i| {
            self.sections[i].expanded = true;
        }
    }

    /// Collapse all sections
    pub fn collapseAll(self: *Accordion) void {
        for (0..self.sections.len) |i| {
            self.sections[i].expanded = false;
        }
    }

    /// Move cursor up (wraps to last section)
    pub fn moveCursorUp(self: *Accordion) void {
        if (self.sections.len == 0) return;
        if (self.cursor == 0) {
            self.cursor = self.sections.len - 1;
        } else {
            self.cursor -= 1;
        }
    }

    /// Move cursor down (wraps to first section)
    pub fn moveCursorDown(self: *Accordion) void {
        if (self.sections.len == 0) return;
        if (self.cursor >= self.sections.len - 1) {
            self.cursor = 0;
        } else {
            self.cursor += 1;
        }
    }

    /// Check if section is expanded
    pub fn isExpanded(self: Accordion, index: usize) bool {
        if (index >= self.sections.len) return false;
        return self.sections[index].expanded;
    }

    /// Builder: set block border
    pub fn withBlock(self: Accordion, block: Block) Accordion {
        var result = self;
        result.block = block;
        return result;
    }

    /// Builder: set header style
    pub fn withHeaderStyle(self: Accordion, style: Style) Accordion {
        var result = self;
        result.header_style = style;
        return result;
    }

    /// Builder: set expanded content style
    pub fn withExpandedStyle(self: Accordion, style: Style) Accordion {
        var result = self;
        result.expanded_style = style;
        return result;
    }

    /// Builder: set cursor style
    pub fn withCursorStyle(self: Accordion, style: Style) Accordion {
        var result = self;
        result.cursor_style = style;
        return result;
    }

    /// Builder: set expand icon
    pub fn withExpandIcon(self: Accordion, icon: u21) Accordion {
        var result = self;
        result.expand_icon = icon;
        return result;
    }

    /// Builder: set collapse icon
    pub fn withCollapseIcon(self: Accordion, icon: u21) Accordion {
        var result = self;
        result.collapse_icon = icon;
        return result;
    }

    /// Builder: set single-expand mode
    pub fn withSingleExpand(self: Accordion, enabled: bool) Accordion {
        var result = self;
        result.single_expand = enabled;
        return result;
    }

    /// Render accordion to buffer
    pub fn render(self: *Accordion, buf: *Buffer, area: Rect) void {
        // Early return if area is too small
        if (area.width == 0 or area.height == 0) return;

        // Early return if no sections
        if (self.sections.len == 0) return;

        // Calculate content area (accounting for block border)
        var content_area = area;
        if (self.block != null) {
            self.block.?.render(buf, area);
            // Adjust for border: shrink by 2 on each dimension, shift origin
            if (content_area.width > 2) {
                content_area.width -= 2;
            } else {
                return;
            }
            if (content_area.height > 2) {
                content_area.height -= 2;
            } else {
                return;
            }
            content_area.x += 1;
            content_area.y += 1;
        }

        var row: u16 = 0;

        // Iterate through sections and render
        for (self.sections, 0..) |section, idx| {
            // Render header row
            if (row >= content_area.height) break;

            const icon = if (section.expanded) self.collapse_icon else self.expand_icon;
            const style = if (idx == self.cursor) self.cursor_style else self.header_style;

            // Draw icon at column content_area.x
            buf.set(content_area.x, content_area.y + row, .{
                .char = icon,
                .style = style,
            });

            // Draw title starting at column content_area.x + 2
            buf.setString(content_area.x + 2, content_area.y + row, section.title, style);

            row += 1;

            // Render content rows (only if section is expanded)
            if (section.expanded) {
                for (section.content_lines) |line| {
                    if (row >= content_area.height) break;

                    // Draw line at content_area.x + 2 (indented) with expanded_style
                    buf.setString(content_area.x + 2, content_area.y + row, line, self.expanded_style);

                    row += 1;
                }
            }

            // Check if we've run out of vertical space
            if (row >= content_area.height) break;
        }
    }
};

// ============================================================================
// Tests — Accordion Widget Behavior
// ============================================================================

test "Accordion init with sections initializes cursor to 0" {
    const section1 = AccordionSection{ .title = "Section 1", .content_lines = &.{} };
    const section2 = AccordionSection{ .title = "Section 2", .content_lines = &.{} };
    var sections_array = [_]AccordionSection{ section1, section2 };

    const acc = Accordion.init(sections_array[0..]);
    try std.testing.expectEqual(@as(usize, 0), acc.cursor);
}

test "Accordion init sets single_expand to false by default" {
    const section = AccordionSection{ .title = "Test", .content_lines = &.{} };
    var sections_array = [_]AccordionSection{section};

    const acc = Accordion.init(sections_array[0..]);
    try std.testing.expect(!acc.single_expand);
}

test "Accordion init sets expand icon to ▶" {
    const section = AccordionSection{ .title = "Test", .content_lines = &.{} };
    var sections_array = [_]AccordionSection{section};

    const acc = Accordion.init(sections_array[0..]);
    try std.testing.expectEqual(@as(u21, '▶'), acc.expand_icon);
}

test "Accordion init sets collapse icon to ▼" {
    const section = AccordionSection{ .title = "Test", .content_lines = &.{} };
    var sections_array = [_]AccordionSection{section};

    const acc = Accordion.init(sections_array[0..]);
    try std.testing.expectEqual(@as(u21, '▼'), acc.collapse_icon);
}

test "Accordion toggleCurrent from collapsed opens section" {
    const section = AccordionSection{ .title = "Test", .content_lines = &.{}, .expanded = false };
    var sections = [_]AccordionSection{section};

    var acc = Accordion.init(sections[0..]);
    acc.toggleCurrent();
    try std.testing.expect(acc.sections[0].expanded);
}

test "Accordion toggleCurrent from expanded closes section" {
    const section = AccordionSection{ .title = "Test", .content_lines = &.{}, .expanded = true };
    var sections = [_]AccordionSection{section};

    var acc = Accordion.init(sections[0..]);
    acc.toggleCurrent();
    try std.testing.expect(!acc.sections[0].expanded);
}

test "Accordion toggleCurrent with out-of-bounds cursor doesn't crash" {
    const section = AccordionSection{ .title = "Test", .content_lines = &.{}, .expanded = false };
    var sections = [_]AccordionSection{section};

    var acc = Accordion.init(sections[0..]);
    acc.cursor = 10; // Out of bounds
    acc.toggleCurrent(); // Should be no-op
    try std.testing.expect(!acc.sections[0].expanded);
}

test "Accordion expandCurrent expands the current section" {
    const section = AccordionSection{ .title = "Test", .content_lines = &.{}, .expanded = false };
    var sections = [_]AccordionSection{section};

    var acc = Accordion.init(sections[0..]);
    acc.expandCurrent();
    try std.testing.expect(acc.sections[0].expanded);
}

test "Accordion expandCurrent in single_expand mode collapses other sections" {
    const s1 = AccordionSection{ .title = "S1", .content_lines = &.{}, .expanded = true };
    const s2 = AccordionSection{ .title = "S2", .content_lines = &.{}, .expanded = false };
    var sections = [_]AccordionSection{ s1, s2 };

    var acc = Accordion.init(sections[0..]);
    acc.single_expand = true;
    acc.cursor = 1;
    acc.expandCurrent();

    try std.testing.expect(!acc.sections[0].expanded);
    try std.testing.expect(acc.sections[1].expanded);
}

test "Accordion expandCurrent with out-of-bounds cursor is no-op" {
    const section = AccordionSection{ .title = "Test", .content_lines = &.{}, .expanded = false };
    var sections = [_]AccordionSection{section};

    var acc = Accordion.init(sections[0..]);
    acc.cursor = 10;
    acc.expandCurrent();
    try std.testing.expect(!acc.sections[0].expanded);
}

test "Accordion collapseCurrent collapses the current section" {
    const section = AccordionSection{ .title = "Test", .content_lines = &.{}, .expanded = true };
    var sections = [_]AccordionSection{section};

    var acc = Accordion.init(sections[0..]);
    acc.collapseCurrent();
    try std.testing.expect(!acc.sections[0].expanded);
}

test "Accordion collapseCurrent with out-of-bounds cursor is no-op" {
    const section = AccordionSection{ .title = "Test", .content_lines = &.{}, .expanded = true };
    var sections = [_]AccordionSection{section};

    var acc = Accordion.init(sections[0..]);
    acc.cursor = 10;
    acc.collapseCurrent();
    try std.testing.expect(acc.sections[0].expanded);
}

test "Accordion expandAll expands all sections regardless of single_expand" {
    const s1 = AccordionSection{ .title = "S1", .content_lines = &.{}, .expanded = false };
    const s2 = AccordionSection{ .title = "S2", .content_lines = &.{}, .expanded = false };
    const s3 = AccordionSection{ .title = "S3", .content_lines = &.{}, .expanded = false };
    var sections = [_]AccordionSection{ s1, s2, s3 };

    var acc = Accordion.init(sections[0..]);
    acc.single_expand = true;
    acc.expandAll();

    try std.testing.expect(acc.sections[0].expanded);
    try std.testing.expect(acc.sections[1].expanded);
    try std.testing.expect(acc.sections[2].expanded);
}

test "Accordion collapseAll collapses all sections" {
    const s1 = AccordionSection{ .title = "S1", .content_lines = &.{}, .expanded = true };
    const s2 = AccordionSection{ .title = "S2", .content_lines = &.{}, .expanded = true };
    var sections = [_]AccordionSection{ s1, s2 };

    var acc = Accordion.init(sections[0..]);
    acc.collapseAll();

    try std.testing.expect(!acc.sections[0].expanded);
    try std.testing.expect(!acc.sections[1].expanded);
}

test "Accordion moveCursorDown from middle section moves to next" {
    const s1 = AccordionSection{ .title = "S1", .content_lines = &.{} };
    const s2 = AccordionSection{ .title = "S2", .content_lines = &.{} };
    const s3 = AccordionSection{ .title = "S3", .content_lines = &.{} };
    var sections = [_]AccordionSection{ s1, s2, s3 };

    var acc = Accordion.init(sections[0..]);
    acc.cursor = 1;
    acc.moveCursorDown();
    try std.testing.expectEqual(@as(usize, 2), acc.cursor);
}

test "Accordion moveCursorDown from last section wraps to first" {
    const s1 = AccordionSection{ .title = "S1", .content_lines = &.{} };
    const s2 = AccordionSection{ .title = "S2", .content_lines = &.{} };
    var sections = [_]AccordionSection{ s1, s2 };

    var acc = Accordion.init(sections[0..]);
    acc.cursor = 1;
    acc.moveCursorDown();
    try std.testing.expectEqual(@as(usize, 0), acc.cursor);
}

test "Accordion moveCursorDown from single section stays at 0" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{} };
    var sections = [_]AccordionSection{section};

    var acc = Accordion.init(sections[0..]);
    acc.moveCursorDown();
    try std.testing.expectEqual(@as(usize, 0), acc.cursor);
}

test "Accordion moveCursorDown with empty sections is no-op" {
    const sections: [0]AccordionSection = undefined;
    var acc = Accordion.init(sections[0..]);
    acc.cursor = 5; // Should remain unchanged
    acc.moveCursorDown();
    try std.testing.expectEqual(@as(usize, 5), acc.cursor);
}

test "Accordion moveCursorUp from middle section moves to previous" {
    const s1 = AccordionSection{ .title = "S1", .content_lines = &.{} };
    const s2 = AccordionSection{ .title = "S2", .content_lines = &.{} };
    const s3 = AccordionSection{ .title = "S3", .content_lines = &.{} };
    var sections = [_]AccordionSection{ s1, s2, s3 };

    var acc = Accordion.init(sections[0..]);
    acc.cursor = 1;
    acc.moveCursorUp();
    try std.testing.expectEqual(@as(usize, 0), acc.cursor);
}

test "Accordion moveCursorUp from first section wraps to last" {
    const s1 = AccordionSection{ .title = "S1", .content_lines = &.{} };
    const s2 = AccordionSection{ .title = "S2", .content_lines = &.{} };
    var sections = [_]AccordionSection{ s1, s2 };

    var acc = Accordion.init(sections[0..]);
    acc.cursor = 0;
    acc.moveCursorUp();
    try std.testing.expectEqual(@as(usize, 1), acc.cursor);
}

test "Accordion moveCursorUp from single section stays at 0" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{} };
    var sections = [_]AccordionSection{section};

    var acc = Accordion.init(sections[0..]);
    acc.moveCursorUp();
    try std.testing.expectEqual(@as(usize, 0), acc.cursor);
}

test "Accordion isExpanded returns true for expanded section" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{}, .expanded = true };
    var sections = [_]AccordionSection{section};

    const acc = Accordion.init(sections[0..]);
    try std.testing.expect(acc.isExpanded(0));
}

test "Accordion isExpanded returns false for collapsed section" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{}, .expanded = false };
    var sections = [_]AccordionSection{section};

    const acc = Accordion.init(sections[0..]);
    try std.testing.expect(!acc.isExpanded(0));
}

test "Accordion isExpanded returns false for out-of-bounds index" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{}, .expanded = true };
    var sections = [_]AccordionSection{section};

    const acc = Accordion.init(sections[0..]);
    try std.testing.expect(!acc.isExpanded(10));
}

test "Accordion withBlock builder preserves other fields" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{} };
    var sections = [_]AccordionSection{section};

    const acc1 = Accordion.init(sections[0..]);
    const block = Block{ .title = "Accordion" };
    const acc2 = acc1.withBlock(block);

    try std.testing.expect(acc2.block != null);
    try std.testing.expectEqual(@as(usize, 0), acc2.cursor);
}

test "Accordion withBlock builder maintains immutability" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{} };
    var sections = [_]AccordionSection{section};

    const acc1 = Accordion.init(sections[0..]);
    const block = Block{ .title = "Accordion" };
    _ = acc1.withBlock(block);

    try std.testing.expect(acc1.block == null);
}

test "Accordion withHeaderStyle builder sets style" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{} };
    var sections = [_]AccordionSection{section};

    const acc1 = Accordion.init(sections[0..]);
    const style = Style{ .bold = true };
    const acc2 = acc1.withHeaderStyle(style);

    try std.testing.expect(acc2.header_style.bold);
}

test "Accordion withExpandedStyle builder sets style" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{} };
    var sections = [_]AccordionSection{section};

    const acc1 = Accordion.init(sections[0..]);
    const style = Style{ .italic = true };
    const acc2 = acc1.withExpandedStyle(style);

    try std.testing.expect(acc2.expanded_style.italic);
}

test "Accordion withCursorStyle builder sets style" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{} };
    var sections = [_]AccordionSection{section};

    const acc1 = Accordion.init(sections[0..]);
    const style = Style{ .dim = true };
    const acc2 = acc1.withCursorStyle(style);

    try std.testing.expect(acc2.cursor_style.dim);
}

test "Accordion withExpandIcon builder sets icon" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{} };
    var sections = [_]AccordionSection{section};

    const acc1 = Accordion.init(sections[0..]);
    const acc2 = acc1.withExpandIcon('+');

    try std.testing.expectEqual(@as(u21, '+'), acc2.expand_icon);
    try std.testing.expectEqual(@as(u21, '▶'), acc1.expand_icon);
}

test "Accordion withCollapseIcon builder sets icon" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{} };
    var sections = [_]AccordionSection{section};

    const acc1 = Accordion.init(sections[0..]);
    const acc2 = acc1.withCollapseIcon('-');

    try std.testing.expectEqual(@as(u21, '-'), acc2.collapse_icon);
    try std.testing.expectEqual(@as(u21, '▼'), acc1.collapse_icon);
}

test "Accordion withSingleExpand builder enables single-expand mode" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{} };
    var sections = [_]AccordionSection{section};

    const acc1 = Accordion.init(sections[0..]);
    const acc2 = acc1.withSingleExpand(true);

    try std.testing.expect(acc2.single_expand);
    try std.testing.expect(!acc1.single_expand);
}

test "Accordion builder methods can chain" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{} };
    var sections = [_]AccordionSection{section};

    const acc = Accordion.init(sections[0..])
        .withSingleExpand(true)
        .withExpandIcon('+')
        .withCollapseIcon('-');

    try std.testing.expect(acc.single_expand);
    try std.testing.expectEqual(@as(u21, '+'), acc.expand_icon);
    try std.testing.expectEqual(@as(u21, '-'), acc.collapse_icon);
}

test "Accordion render with zero width is no-op" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    // Fill with known pattern
    const pattern = buffer_mod.Cell{ .char = 'X', .style = .{} };
    buf.set(0, 0, pattern);

    const section = AccordionSection{ .title = "S1", .content_lines = &.{} };
    var sections = [_]AccordionSection{section};
    var acc = Accordion.init(sections[0..]);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    acc.render(&buf, area);

    // Buffer should remain unchanged
    try std.testing.expectEqual(@as(u21, 'X'), buf.getConst(0, 0).?.char);
}

test "Accordion render with zero height is no-op" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const pattern = buffer_mod.Cell{ .char = 'X', .style = .{} };
    buf.set(0, 0, pattern);

    const section = AccordionSection{ .title = "S1", .content_lines = &.{} };
    var sections = [_]AccordionSection{section};
    var acc = Accordion.init(sections[0..]);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 0 };
    acc.render(&buf, area);

    try std.testing.expectEqual(@as(u21, 'X'), buf.getConst(0, 0).?.char);
}

test "Accordion render with no sections is no-op" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 10, 10);
    defer buf.deinit();

    const pattern = buffer_mod.Cell{ .char = 'X', .style = .{} };
    buf.set(0, 0, pattern);

    const sections: [0]AccordionSection = undefined;
    var acc = Accordion.init(sections[0..]);

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    acc.render(&buf, area);

    try std.testing.expectEqual(@as(u21, 'X'), buf.getConst(0, 0).?.char);
}

test "Accordion render with single collapsed section renders header only" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const section = AccordionSection{ .title = "Test Section", .content_lines = &.{}, .expanded = false };
    var sections = [_]AccordionSection{section};
    var acc = Accordion.init(sections[0..]);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    acc.render(&buf, area);

    // Should render expand icon at (0, 0)
    try std.testing.expectEqual(@as(u21, '▶'), buf.getConst(0, 0).?.char);
}

test "Accordion render with expanded section includes content" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    var content = [_][]const u8{ "Line 1", "Line 2" };
    const section = AccordionSection{ .title = "Test", .content_lines = &content, .expanded = true };
    var sections = [_]AccordionSection{section};
    var acc = Accordion.init(sections[0..]);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    acc.render(&buf, area);

    // Should render collapse icon at (0, 0)
    try std.testing.expectEqual(@as(u21, '▼'), buf.getConst(0, 0).?.char);
}

test "Accordion render cursor changes style on focused section" {
    const allocator = std.testing.allocator;
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const s1 = AccordionSection{ .title = "S1", .content_lines = &.{} };
    const s2 = AccordionSection{ .title = "S2", .content_lines = &.{} };
    var sections = [_]AccordionSection{ s1, s2 };

    var acc = Accordion.init(sections[0..]);
    acc.cursor = 1; // Focus on second section

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    acc.render(&buf, area);

    // At row 1 (second header), style should be cursor_style (bold AND reverse, per default)
    const cell = buf.getConst(2, 1).?;
    try std.testing.expect(cell.style.bold);
    try std.testing.expect(cell.style.reverse);
}

test "Accordion sequential navigation up/down maintains valid cursor" {
    const s1 = AccordionSection{ .title = "S1", .content_lines = &.{} };
    const s2 = AccordionSection{ .title = "S2", .content_lines = &.{} };
    const s3 = AccordionSection{ .title = "S3", .content_lines = &.{} };
    var sections = [_]AccordionSection{ s1, s2, s3 };

    var acc = Accordion.init(sections[0..]);
    acc.moveCursorDown();
    acc.moveCursorDown();
    try std.testing.expectEqual(@as(usize, 2), acc.cursor);
    acc.moveCursorDown();
    try std.testing.expectEqual(@as(usize, 0), acc.cursor); // Wraps
}

test "Accordion toggle twice returns to original state" {
    const section = AccordionSection{ .title = "S1", .content_lines = &.{}, .expanded = false };
    var sections = [_]AccordionSection{section};

    var acc = Accordion.init(sections[0..]);
    const original = acc.sections[0].expanded;
    acc.toggleCurrent();
    acc.toggleCurrent();
    try std.testing.expectEqual(original, acc.sections[0].expanded);
}
