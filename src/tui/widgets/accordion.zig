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
// Tests — to be implemented by test-writer in TDD cycle
// ============================================================================

test {
    std.testing.refAllDecls(@This());
}
