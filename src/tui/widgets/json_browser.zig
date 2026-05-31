//! JsonBrowser — collapsible JSON tree viewer widget (v2.16.0)
//!
//! Renders a flat list of pre-parsed JSON nodes as an interactive tree.
//! Supports collapse/expand of objects and arrays.
//! No allocation in render() — caller provides the node slice.

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Kind of a node in the flat JSON representation.
pub const NodeKind = enum {
    object_open,  // opening '{'
    object_close, // closing '}'
    array_open,   // opening '['
    array_close,  // closing ']'
    string,       // JSON string value
    number,       // JSON number value
    boolean,      // true or false
    null_val,     // null
};

/// A single node in the flat JSON tree.
///
/// Nodes are stored in a flat slice with `depth` encoding the nesting level.
/// Container nodes (`object_open`, `array_open`) may be collapsed by setting
/// `collapsed = true`; the widget's render and navigation logic respect this.
pub const Node = struct {
    kind: NodeKind,
    /// Object field key. Empty string for array elements without a key.
    key: []const u8 = "",
    /// String representation of the value (for leaf nodes).
    /// For container open/close nodes this is "" (the bracket is implied by kind).
    value: []const u8 = "",
    /// Nesting depth (0 = root level).
    depth: u16 = 0,
    /// When true, the subtree of a container node is hidden during render.
    collapsed: bool = false,
};

/// JsonBrowser widget — displays a JSON node tree with collapse/expand support.
///
/// The caller is responsible for building the `nodes` slice.
/// The widget does not own the slice; the caller manages its lifetime.
///
/// Example:
/// ```zig
/// var nodes = [_]Node{
///     .{ .kind = .object_open, .depth = 0 },
///     .{ .kind = .string, .key = "name", .value = "\"Alice\"", .depth = 1 },
///     .{ .kind = .object_close, .depth = 0 },
/// };
/// var browser = JsonBrowser{ .nodes = &nodes };
/// browser.render(buf, area);
/// ```
pub const JsonBrowser = struct {
    /// Flat node list. Mutable — `toggleCollapse` mutates `nodes[i].collapsed`.
    nodes: []Node,
    /// Index into `nodes` for the currently selected (visible) node.
    cursor: usize = 0,
    /// Vertical scroll offset (in visible display lines).
    scroll: u16 = 0,
    /// Optional border block.
    block: ?Block = null,

    // Styles — all customisable.
    key_style: Style = .{ .fg = .blue },
    string_style: Style = .{ .fg = .green },
    number_style: Style = .{ .fg = .cyan },
    bool_style: Style = .{ .fg = .yellow },
    null_style: Style = .{ .fg = .bright_black },
    bracket_style: Style = .{ .bold = true },
    cursor_style: Style = .{ .bold = true, .fg = .white },
    /// Indent string per depth level (default: two spaces).
    indent_str: []const u8 = "  ",

    /// Toggle collapse/expand of the container node at `cursor`.
    /// No-op if the cursor is on a non-container node or a close bracket.
    pub fn toggleCollapse(self: *JsonBrowser) void {
        if (self.cursor >= self.nodes.len) return;
        const node = &self.nodes[self.cursor];
        if (node.kind == .object_open or node.kind == .array_open) {
            node.collapsed = !node.collapsed;
        }
    }

    /// Move cursor to the next visible node (down arrow).
    pub fn moveDown(self: *JsonBrowser) void {
        const next = self.nextVisible(self.cursor + 1) orelse return;
        self.cursor = next;
    }

    /// Move cursor to the previous visible node (up arrow).
    pub fn moveUp(self: *JsonBrowser) void {
        if (self.cursor == 0) return;
        const prev = self.prevVisible(self.cursor -| 1) orelse return;
        self.cursor = prev;
    }

    /// Find the first visible node index at or after `start`.
    fn nextVisible(self: JsonBrowser, start: usize) ?usize {
        // Replay collapse state from the beginning up to `start`.
        var cd: ?u16 = null;
        var cn: u16 = 0;

        for (self.nodes[0..start]) |node| {
            if (cd) |d| {
                if (node.depth > d) {
                    adjustNesting(&cn, node.kind);
                    continue;
                } else if (node.depth == d and isClose(node.kind) and cn == 0) {
                    cd = null;
                    continue;
                } else {
                    cd = null;
                }
            }
            if (isOpen(node.kind) and node.collapsed) {
                cd = node.depth;
                cn = 0;
            }
        }

        // Scan forward for first visible.
        var i = start;
        while (i < self.nodes.len) : (i += 1) {
            const node = self.nodes[i];
            if (cd) |d| {
                if (node.depth > d) {
                    adjustNesting(&cn, node.kind);
                    continue;
                } else if (node.depth == d and isClose(node.kind) and cn == 0) {
                    cd = null;
                    continue; // skip matching close of collapsed container
                } else {
                    cd = null;
                    // This node is now visible.
                    if (isOpen(node.kind) and node.collapsed) {
                        cd = node.depth;
                        cn = 0;
                    }
                    return i;
                }
            }
            // Node is visible.
            if (isOpen(node.kind) and node.collapsed) {
                cd = node.depth;
                cn = 0;
            }
            return i;
        }
        return null;
    }

    /// Find the last visible node index at or before `end`.
    fn prevVisible(self: JsonBrowser, end: usize) ?usize {
        var last: ?usize = null;
        var cd: ?u16 = null;
        var cn: u16 = 0;

        for (self.nodes[0 .. end + 1], 0..) |node, i| {
            if (cd) |d| {
                if (node.depth > d) {
                    adjustNesting(&cn, node.kind);
                    continue;
                } else if (node.depth == d and isClose(node.kind) and cn == 0) {
                    cd = null;
                    continue;
                } else {
                    cd = null;
                }
            }
            last = i;
            if (isOpen(node.kind) and node.collapsed) {
                cd = node.depth;
                cn = 0;
            }
        }
        return last;
    }

    /// Render the JSON tree into the buffer, clipped to area.
    pub fn render(self: JsonBrowser, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        var inner = area;
        if (self.block) |b| {
            b.render(buf, area);
            inner = b.inner(area);
        }

        if (inner.width == 0 or inner.height == 0) return;

        var display_line: u16 = 0;
        var row: u16 = 0;
        var cd: ?u16 = null;
        var cn: u16 = 0;

        for (self.nodes, 0..) |node, i| {
            // Collapse skip logic
            if (cd) |d| {
                if (node.depth > d) {
                    adjustNesting(&cn, node.kind);
                    continue;
                } else if (node.depth == d and isClose(node.kind) and cn == 0) {
                    cd = null;
                    continue; // skip matching close (shown as "{ ... }")
                } else {
                    cd = null;
                    // fall through — visible
                }
            }

            // Scroll check
            if (display_line < self.scroll) {
                display_line += 1;
                if (isOpen(node.kind) and node.collapsed) {
                    cd = node.depth;
                    cn = 0;
                }
                continue;
            }

            if (row >= inner.height) break;

            self.renderNode(buf, inner, row, node, i == self.cursor);
            row += 1;
            display_line += 1;

            if (isOpen(node.kind) and node.collapsed) {
                cd = node.depth;
                cn = 0;
            }
        }
    }

    fn renderNode(self: JsonBrowser, buf: *Buffer, area: Rect, row: u16, node: Node, is_cursor: bool) void {
        var col: u16 = area.x;
        const y = area.y + row;
        const max_x = area.x + area.width;

        // Indent
        const indent_w: u16 = @intCast(self.indent_str.len);
        var ic: u16 = 0;
        while (ic < node.depth * indent_w and col < max_x) : (ic += 1) {
            buf.set(col, y, .{ .char = ' ', .style = .{} });
            col += 1;
        }

        // Key (for object fields)
        if (node.key.len > 0) {
            const ks = if (is_cursor) self.cursor_style else self.key_style;
            col += writeStr(buf, col, y, max_x, node.key, ks);
            if (col < max_x) { buf.set(col, y, .{ .char = ':', .style = .{} }); col += 1; }
            if (col < max_x) { buf.set(col, y, .{ .char = ' ', .style = .{} }); col += 1; }
        }

        // Value / bracket
        const bs = if (is_cursor) self.cursor_style else self.bracket_style;
        switch (node.kind) {
            .object_open => {
                if (node.collapsed) {
                    _ = writeStr(buf, col, y, max_x, "{ ... }", bs);
                } else {
                    if (col < max_x) buf.set(col, y, .{ .char = '{', .style = bs });
                }
            },
            .object_close => {
                if (col < max_x) buf.set(col, y, .{ .char = '}', .style = bs });
            },
            .array_open => {
                if (node.collapsed) {
                    _ = writeStr(buf, col, y, max_x, "[ ... ]", bs);
                } else {
                    if (col < max_x) buf.set(col, y, .{ .char = '[', .style = bs });
                }
            },
            .array_close => {
                if (col < max_x) buf.set(col, y, .{ .char = ']', .style = bs });
            },
            .string => {
                const vs = if (is_cursor) self.cursor_style else self.string_style;
                _ = writeStr(buf, col, y, max_x, node.value, vs);
            },
            .number => {
                const vs = if (is_cursor) self.cursor_style else self.number_style;
                _ = writeStr(buf, col, y, max_x, node.value, vs);
            },
            .boolean => {
                const vs = if (is_cursor) self.cursor_style else self.bool_style;
                _ = writeStr(buf, col, y, max_x, node.value, vs);
            },
            .null_val => {
                const vs = if (is_cursor) self.cursor_style else self.null_style;
                _ = writeStr(buf, col, y, max_x, "null", vs);
            },
        }
    }
};

// ── Helpers ────────────────────────────────────────────────────────────────

fn isOpen(k: NodeKind) bool {
    return k == .object_open or k == .array_open;
}

fn isClose(k: NodeKind) bool {
    return k == .object_close or k == .array_close;
}

fn adjustNesting(cn: *u16, k: NodeKind) void {
    if (isOpen(k)) {
        cn.* += 1;
    } else if (isClose(k) and cn.* > 0) {
        cn.* -= 1;
    }
}

/// Write a UTF-8 string into the buffer from (x, y) up to max_x columns.
/// Returns the number of terminal columns consumed.
fn writeStr(buf: *Buffer, x: u16, y: u16, max_x: u16, s: []const u8, style: Style) u16 {
    var col = x;
    var idx: usize = 0;
    while (idx < s.len and col < max_x) {
        const cp_len = std.unicode.utf8ByteSequenceLength(s[idx]) catch 1;
        if (idx + cp_len > s.len) break;
        const cp = std.unicode.utf8Decode(s[idx..][0..cp_len]) catch '?';
        buf.set(col, y, .{ .char = cp, .style = style });
        col += 1;
        idx += cp_len;
    }
    return col - x;
}
