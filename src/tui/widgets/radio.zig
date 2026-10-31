//! Radio button group widget for mutually exclusive selection.
const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Cell = @import("../buffer.zig").Cell;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const symbols = @import("../symbols.zig");
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;

const help_text = "↑/↓: Navigate | Enter/Space: Select | Esc: Clear";

/// Draw `text` at (x, y), clipped to `max_cells` terminal cells (never splits a character).
fn putText(buf: *Buffer, x: u16, y: u16, max_cells: u16, text: []const u8, style: Style) void {
    const bytes = UnicodeWidth.truncate(text, max_cells);
    buf.setString(x, y, text[0..bytes], style);
}

/// Radio button group for mutually exclusive selection
pub const RadioGroup = struct {
    items: []const []const u8,
    selected: ?usize = null, // Index of selected item, null if none
    focused: usize = 0, // Currently focused item
    block: ?Block = null,
    style: Style = .{},
    selected_style: Style = .{ .fg = .green },
    focused_style: Style = .{ .bold = true, .reverse = true },
    show_help: bool = true,

    /// Creates a new radio group from a slice of item labels.
    /// No item is selected initially. Focus starts on the first item.
    pub fn init(items: []const []const u8) RadioGroup {
        return .{ .items = items };
    }

    /// Sets the initially selected item by index.
    /// If index is out of bounds, no selection is made.
    /// Returns a new group instance for method chaining.
    pub fn withSelected(self: RadioGroup, index: usize) RadioGroup {
        var result = self;
        if (index < result.items.len) {
            result.selected = index;
        }
        return result;
    }

    /// Sets an optional border block around the radio group.
    /// Returns a new group instance for method chaining.
    pub fn withBlock(self: RadioGroup, block: Block) RadioGroup {
        var result = self;
        result.block = block;
        return result;
    }

    /// Sets the default style for unselected, unfocused items.
    /// Returns a new group instance for method chaining.
    pub fn withStyle(self: RadioGroup, style: Style) RadioGroup {
        var result = self;
        result.style = style;
        return result;
    }

    /// Sets the style applied to the selected item.
    /// Default: green foreground. Returns a new group instance for method chaining.
    pub fn withSelectedStyle(self: RadioGroup, style: Style) RadioGroup {
        var result = self;
        result.selected_style = style;
        return result;
    }

    /// Sets the style applied to the focused item.
    /// Default: bold + reversed. Returns a new group instance for method chaining.
    pub fn withFocusedStyle(self: RadioGroup, style: Style) RadioGroup {
        var result = self;
        result.focused_style = style;
        return result;
    }

    /// Controls whether to display keyboard shortcut help text at the bottom.
    /// Help text: "↑/↓: Navigate | Enter/Space: Select | Esc: Clear"
    /// Returns a new group instance for method chaining.
    pub fn withHelp(self: RadioGroup, show: bool) RadioGroup {
        var result = self;
        result.show_help = show;
        return result;
    }

    /// Get currently focused item
    pub fn focusedItem(self: RadioGroup) ?[]const u8 {
        if (self.focused < self.items.len) {
            return self.items[self.focused];
        }
        return null;
    }

    /// Get currently selected item
    pub fn selectedItem(self: RadioGroup) ?[]const u8 {
        if (self.selected) |idx| {
            if (idx < self.items.len) {
                return self.items[idx];
            }
        }
        return null;
    }

    /// Get index of selected item
    pub fn selectedIndex(self: RadioGroup) ?usize {
        return self.selected;
    }

    /// Move focus to next item
    pub fn focusNext(self: *RadioGroup) void {
        if (self.items.len == 0) return;
        self.focused = (self.focused + 1) % self.items.len;
    }

    /// Move focus to previous item
    pub fn focusPrev(self: *RadioGroup) void {
        if (self.items.len == 0) return;
        if (self.focused == 0) {
            self.focused = self.items.len - 1;
        } else {
            self.focused -= 1;
        }
    }

    /// Select currently focused item
    pub fn selectFocused(self: *RadioGroup) void {
        if (self.focused < self.items.len) {
            self.selected = self.focused;
        }
    }

    /// Select item by index
    pub fn select(self: *RadioGroup, index: usize) void {
        if (index < self.items.len) {
            self.selected = index;
            self.focused = index;
        }
    }

    /// Clear selection
    pub fn clearSelection(self: *RadioGroup) void {
        self.selected = null;
    }

    /// Renders the radio group to the given buffer within the specified area.
    /// Displays all items vertically with radio indicators (● for selected, ○ for unselected).
    /// The focused item is visually highlighted. Optional border block and help text are rendered.
    pub fn render(self: RadioGroup, buf: *Buffer, area: Rect) void {
        // Clear area (clipped to the buffer)
        buf.fill(area, ' ', self.style);

        var render_area = area;

        // Render block if present
        if (self.block) |block| {
            block.render(buf, area);
            render_area = block.inner(area);
        }

        // Reserve space for help text
        const help_height: u16 = if (self.show_help) 1 else 0;
        const items_height = if (render_area.height > help_height)
            render_area.height - help_height
        else
            0;

        // Render items
        var y: u16 = 0;
        for (self.items, 0..) |item, i| {
            if (y >= items_height) break;

            const is_focused = (i == self.focused);
            const is_selected = if (self.selected) |sel| sel == i else false;

            // Determine style
            const item_style = if (is_focused)
                self.focused_style
            else if (is_selected)
                self.selected_style
            else
                self.style;

            const item_y = render_area.y + y;

            // Render radio button indicator, a space, then the label (all clipped to the area)
            const indicator = if (is_selected)
                symbols.radio.selected
            else
                symbols.radio.unselected;
            if (render_area.width >= 1) {
                buf.set(render_area.x, item_y, .{ .char = indicator, .style = item_style });
            }
            if (render_area.width >= 2) {
                buf.set(render_area.x + 1, item_y, .{ .char = ' ', .style = item_style });
            }
            const label_x = render_area.x +| 2;
            putText(buf, label_x, item_y, render_area.width -| 2, item, item_style);

            y += 1;
        }

        // Render help text
        if (self.show_help and render_area.height > 0) {
            const help_y = render_area.y + render_area.height - 1;
            putText(buf, render_area.x, help_y, render_area.width, help_text, .{ .fg = .gray });
        }
    }
};

// Tests

const testing = std.testing;

/// Assert `text` is drawn at (x, y) one codepoint per cell, every cell carrying `want`.
fn expectText(buf: Buffer, x: u16, y: u16, text: []const u8, want: Style) !void {
    var view = try std.unicode.Utf8View.init(text);
    var it = view.iterator();
    var col = x;
    while (it.nextCodepoint()) |cp| : (col += 1) {
        const cell = buf.getConst(col, y) orelse return error.TestUnexpectedResult;
        try testing.expectEqual(cp, cell.char);
        try testing.expectEqual(want, cell.style);
    }
}

/// Assert every cell of the buffer is still the default blank cell.
fn expectBlank(buf: Buffer) !void {
    for (buf.cells) |cell| try testing.expectEqual(Cell{}, cell);
}

const green: Style = .{ .fg = .green };
const focus: Style = .{ .bold = true, .reverse = true };
const gray: Style = .{ .fg = .gray };

test "radio: init has no selection, first item focused, documented defaults" {
    const items = [_][]const u8{ "Option A", "Option B", "Option C" };
    const group = RadioGroup.init(&items);

    try testing.expectEqual(@as(usize, 3), group.items.len);
    try testing.expectEqual(@as(?usize, null), group.selected);
    try testing.expectEqual(@as(usize, 0), group.focused);
    try testing.expect(group.show_help);
    try testing.expect(group.block == null);
    try testing.expectEqual(Style{}, group.style);
    try testing.expectEqual(green, group.selected_style);
    try testing.expectEqual(focus, group.focused_style);
}

test "radio: withSelected stores an in-range index and ignores an out-of-range one" {
    const items = [_][]const u8{ "First", "Second", "Third" };
    const base = RadioGroup.init(&items);

    try testing.expectEqual(@as(?usize, 1), base.withSelected(1).selected);
    try testing.expectEqual(@as(?usize, 2), base.withSelected(2).selected);
    try testing.expectEqual(@as(?usize, null), base.withSelected(3).selected);
    try testing.expectEqual(@as(?usize, null), base.withSelected(std.math.maxInt(usize)).selected);
    try testing.expectEqual(@as(usize, 0), base.withSelected(1).focused); // focus unchanged
}

test "radio: withSelected on an empty group selects nothing" {
    const items = [_][]const u8{};
    try testing.expectEqual(@as(?usize, null), RadioGroup.init(&items).withSelected(0).selected);
}

test "radio: each builder replaces only its own field" {
    const items = [_][]const u8{"a"};
    const base = RadioGroup.init(&items);
    const red: Style = .{ .fg = .red };

    const blk = base.withBlock(Block{});
    try testing.expect(blk.block != null);
    try testing.expect(blk.show_help);

    const st = base.withStyle(red);
    try testing.expectEqual(red, st.style);
    try testing.expectEqual(green, st.selected_style);

    const ss = base.withSelectedStyle(red);
    try testing.expectEqual(red, ss.selected_style);
    try testing.expectEqual(Style{}, ss.style);

    const fs = base.withFocusedStyle(red);
    try testing.expectEqual(red, fs.focused_style);
    try testing.expectEqual(green, fs.selected_style);

    const nh = base.withHelp(false);
    try testing.expect(!nh.show_help);
    try testing.expect(base.show_help);
}

test "radio: focus wraps forward and backward" {
    const items = [_][]const u8{ "A", "B", "C" };
    var group = RadioGroup.init(&items);

    group.focusPrev(); // wraps from first to last
    try testing.expectEqual(@as(usize, 2), group.focused);
    group.focusNext(); // wraps from last to first
    try testing.expectEqual(@as(usize, 0), group.focused);
    group.focusNext();
    group.focusNext();
    try testing.expectEqual(@as(usize, 2), group.focused);
    group.focusPrev();
    try testing.expectEqual(@as(usize, 1), group.focused);
    try testing.expectEqual(@as(?usize, null), group.selected); // moving focus never selects
}

test "radio: empty group ignores every mutation and has no items" {
    const items = [_][]const u8{};
    var group = RadioGroup.init(&items);

    group.focusNext();
    group.focusPrev();
    group.selectFocused();
    group.select(0);
    try testing.expectEqual(@as(usize, 0), group.focused);
    try testing.expectEqual(@as(?usize, null), group.selected);
    try testing.expect(group.focusedItem() == null);
    try testing.expect(group.selectedItem() == null);
}

test "radio: focusedItem follows focus and is null when focus is out of range" {
    const items = [_][]const u8{ "Apple", "Banana", "Cherry" };
    var group = RadioGroup.init(&items);

    try testing.expectEqualStrings("Apple", group.focusedItem().?);
    group.focusNext();
    try testing.expectEqualStrings("Banana", group.focusedItem().?);
    group.focused = 3;
    try testing.expect(group.focusedItem() == null);
}

test "radio: selectFocused selects the focused item and replaces the old selection" {
    const items = [_][]const u8{ "Red", "Green", "Blue" };
    var group = RadioGroup.init(&items);

    group.selectFocused();
    try testing.expectEqual(@as(?usize, 0), group.selected);

    group.focusNext();
    group.selectFocused();
    try testing.expectEqual(@as(?usize, 1), group.selected);

    group.focusNext();
    group.selectFocused();
    try testing.expectEqual(@as(?usize, 2), group.selected);
    try testing.expectEqual(@as(usize, 2), group.focused);
}

test "radio: selectFocused with out-of-range focus leaves the selection alone" {
    const items = [_][]const u8{ "X", "Y" };
    var group = RadioGroup.init(&items).withSelected(1);

    group.focused = 5;
    group.selectFocused();
    try testing.expectEqual(@as(?usize, 1), group.selected);
}

test "radio: selectedItem and selectedIndex agree" {
    const items = [_][]const u8{ "X", "Y", "Z" };
    var group = RadioGroup.init(&items);

    try testing.expect(group.selectedItem() == null);
    try testing.expectEqual(@as(?usize, null), group.selectedIndex());

    group.focused = 1;
    group.selectFocused();
    try testing.expectEqualStrings("Y", group.selectedItem().?);
    try testing.expectEqual(@as(?usize, 1), group.selectedIndex());
}

test "radio: selectedItem is null when the stored index is out of range" {
    const items = [_][]const u8{ "X", "Y" };
    var group = RadioGroup.init(&items);

    group.selected = 7; // fields are public; a stale index must not read out of bounds
    try testing.expect(group.selectedItem() == null);
    try testing.expectEqual(@as(?usize, 7), group.selectedIndex());
}

test "radio: select moves focus with it and rejects an out-of-range index" {
    const items = [_][]const u8{ "One", "Two", "Three" };
    var group = RadioGroup.init(&items);

    group.select(2);
    try testing.expectEqual(@as(?usize, 2), group.selected);
    try testing.expectEqual(@as(usize, 2), group.focused);

    group.select(3); // rejected: state unchanged
    try testing.expectEqual(@as(?usize, 2), group.selected);
    try testing.expectEqual(@as(usize, 2), group.focused);
}

test "radio: clearSelection removes the selection and keeps focus" {
    const items = [_][]const u8{ "A", "B" };
    var group = RadioGroup.init(&items);
    group.select(1);

    group.clearSelection();
    try testing.expectEqual(@as(?usize, null), group.selected);
    try testing.expectEqual(@as(usize, 1), group.focused);
    group.clearSelection(); // idempotent
    try testing.expectEqual(@as(?usize, null), group.selected);
}

test "radio: render draws indicators, labels, focus style, and help" {
    const items = [_][]const u8{ "Choice A", "Choice B" };
    const group = RadioGroup.init(&items);

    var buf = try Buffer.init(testing.allocator, 52, 5);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 52, .height = 5 });
    buf.check_invariants();

    try expectText(buf, 0, 0, "○ Choice A", focus); // focused row 0, unselected
    try expectText(buf, 10, 0, " " ** 42, .{});
    try expectText(buf, 0, 1, "○ Choice B", .{});
    try expectText(buf, 0, 2, " " ** 52, .{});
    try expectText(buf, 0, 3, " " ** 52, .{});
    try expectText(buf, 0, 4, "↑/↓: Navigate | Enter/Space: Select | Esc: Clear", gray);
    try expectText(buf, 49, 4, "   ", .{});
}

test "radio: render marks the selected item and styles it when unfocused" {
    const items = [_][]const u8{ "Unselected", "Selected", "Other" };
    const group = RadioGroup.init(&items).withSelected(1).withHelp(false);

    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 3 });

    try expectText(buf, 0, 0, "○ Unselected", focus);
    try expectText(buf, 0, 1, "● Selected", green);
    try expectText(buf, 0, 2, "○ Other", .{});
    try testing.expectEqual(@as(u21, symbols.radio.selected), buf.getChar(0, 1));
}

test "radio: focused and selected item shows the selected mark in focused style" {
    const items = [_][]const u8{ "A", "B" };
    var group = RadioGroup.init(&items).withHelp(false);
    group.select(1);

    var buf = try Buffer.init(testing.allocator, 6, 2);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 6, .height = 2 });

    try expectText(buf, 0, 0, "○ A", .{});
    try expectText(buf, 0, 1, "● B", focus);
}

test "radio: custom styles replace the defaults on render" {
    const items = [_][]const u8{ "A", "B", "C" };
    const sel: Style = .{ .fg = .red };
    const foc: Style = .{ .underline = true };
    const base: Style = .{ .fg = .blue };
    var group = RadioGroup.init(&items).withStyle(base).withSelectedStyle(sel)
        .withFocusedStyle(foc).withHelp(false);
    group.select(1);
    group.focused = 2;

    var buf = try Buffer.init(testing.allocator, 6, 4);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 6, .height = 4 });

    try expectText(buf, 0, 0, "○ A", base);
    try expectText(buf, 0, 1, "● B", sel);
    try expectText(buf, 0, 2, "○ C", foc);
    try expectText(buf, 0, 3, " " ** 6, base); // cleared with the group style
}

test "radio: labels are clipped at the area width" {
    const items = [_][]const u8{"Long label"};
    const group = RadioGroup.init(&items).withHelp(false);

    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 7, .height = 1 });

    try expectText(buf, 0, 0, "○ Long ", focus);
    try expectText(buf, 7, 0, " " ** 13, .{});
}

test "radio: multibyte labels are drawn as codepoints, not bytes" {
    const items = [_][]const u8{ "café", "日本" };
    const group = RadioGroup.init(&items).withHelp(false);

    var buf = try Buffer.init(testing.allocator, 12, 2);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 12, .height = 2 });

    try expectText(buf, 0, 0, "○ café", focus);
    try expectText(buf, 0, 1, "○ 日", .{});
    try testing.expectEqual(@as(u21, '本'), buf.getChar(4, 1));
}

test "radio: width one draws only the indicator, width zero draws nothing" {
    const items = [_][]const u8{"Item"};
    const group = RadioGroup.init(&items).withHelp(false);

    var buf = try Buffer.init(testing.allocator, 6, 2);
    defer buf.deinit();
    group.render(&buf, .{ .x = 2, .y = 0, .width = 1, .height = 1 });
    try testing.expectEqual(@as(u21, symbols.radio.unselected), buf.getChar(2, 0));
    try testing.expectEqual(focus, buf.getStyle(2, 0));
    try testing.expectEqual(Cell{}, buf.getConst(3, 0).?); // no spill past the area
    try testing.expectEqual(Cell{}, buf.getConst(1, 0).?);

    var empty = try Buffer.init(testing.allocator, 6, 2);
    defer empty.deinit();
    group.render(&empty, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
    try expectBlank(empty);
}

test "radio: help row takes the last row so one fewer item fits" {
    const items = [_][]const u8{ "A", "B", "C" };
    const group = RadioGroup.init(&items);

    var buf = try Buffer.init(testing.allocator, 24, 4);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 24, .height = 2 });

    try expectText(buf, 0, 0, "○ A", focus);
    try expectText(buf, 0, 1, "↑/↓: Navigate | Enter/Sp", gray);
    try expectText(buf, 0, 2, " " ** 24, .{});
}

test "radio: without help every row up to the height shows an item" {
    const items = [_][]const u8{ "A", "B", "C" };
    const group = RadioGroup.init(&items).withHelp(false);

    var buf = try Buffer.init(testing.allocator, 8, 4);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 2 });

    try expectText(buf, 0, 0, "○ A", focus);
    try expectText(buf, 0, 1, "○ B", .{});
    try expectText(buf, 0, 2, " " ** 8, .{});
}

test "radio: render honours the area origin and clears only inside it" {
    const items = [_][]const u8{"Q"};
    const group = RadioGroup.init(&items).withHelp(false).withStyle(gray);

    var buf = try Buffer.init(testing.allocator, 8, 3);
    defer buf.deinit();
    group.render(&buf, .{ .x = 2, .y = 1, .width = 4, .height = 2 });

    try expectText(buf, 0, 0, " " ** 8, .{});
    try expectText(buf, 0, 1, "  ", .{});
    try expectText(buf, 2, 1, "○ Q", focus);
    try expectText(buf, 5, 1, " ", gray);
    try expectText(buf, 2, 2, "    ", gray);
    try expectText(buf, 6, 2, "  ", .{});
}

test "radio: area larger than the buffer is clipped without writing out of range" {
    const items = [_][]const u8{ "One", "Two" };
    const group = RadioGroup.init(&items);

    var buf = try Buffer.init(testing.allocator, 8, 2);
    defer buf.deinit();
    group.render(&buf, .{ .x = 3, .y = 0, .width = 60, .height = 9 });
    buf.check_invariants();

    try expectText(buf, 3, 0, "○ One", focus);
    try expectText(buf, 3, 1, "○ Two", .{}); // help row (y = 8) is off the buffer
    try expectText(buf, 0, 0, "   ", .{});
}

test "radio: empty group renders only the help line" {
    const items = [_][]const u8{};
    const group = RadioGroup.init(&items);

    var buf = try Buffer.init(testing.allocator, 14, 2);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 14, .height = 2 });

    try expectText(buf, 0, 0, " " ** 14, .{});
    try expectText(buf, 0, 1, "↑/↓: Navigate ", gray);
}

test "radio: block draws border and title, items and help go inside" {
    const items = [_][]const u8{ "Option", "Other" };
    const group = RadioGroup.init(&items).withSelected(1)
        .withBlock((Block{}).withTitle("Pick", .top_left));

    var buf = try Buffer.init(testing.allocator, 30, 6);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 6 });

    try expectText(buf, 0, 0, "┌─Pick", .{});
    try expectText(buf, 29, 0, "┐", .{});
    try expectText(buf, 0, 5, "└" ++ "─" ** 28 ++ "┘", .{});
    try expectText(buf, 0, 2, "│", .{});
    try expectText(buf, 29, 4, "│", .{});
    try expectText(buf, 1, 1, "○ Option", focus);
    try expectText(buf, 1, 2, "● Other", green);
    // Clipped to the inner width of 28 cells.
    try expectText(buf, 1, 4, "↑/↓: Navigate | Enter/Space:", gray);
    try expectText(buf, 29, 4, "│", .{});
}

test "radio: block leaving no inner room draws no items over the border" {
    const items = [_][]const u8{"Option"};
    const group = RadioGroup.init(&items).withBlock(Block{});

    var buf = try Buffer.init(testing.allocator, 10, 2);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 2 });

    try expectText(buf, 0, 0, "┌────────┐", .{});
    try expectText(buf, 0, 1, "└────────┘", .{});
}

test "radio: seeded model run matches a trivial selection reference" {
    var prng = std.Random.DefaultPrng.init(0x4AD1_0123);
    const rand = prng.random();
    const n = 4;
    const items = [_][]const u8{ "a", "b", "c", "d" };
    var group = RadioGroup.init(&items);
    var m_sel: ?usize = null;
    var m_focus: usize = 0;

    for (0..500) |_| {
        switch (rand.uintLessThan(u8, 5)) {
            0 => {
                group.focusNext();
                m_focus = (m_focus + 1) % n;
            },
            1 => {
                group.focusPrev();
                m_focus = (m_focus + n - 1) % n;
            },
            2 => {
                group.selectFocused();
                m_sel = m_focus;
            },
            3 => {
                const idx = rand.uintLessThan(usize, n + 2); // sometimes out of range
                group.select(idx);
                if (idx < n) {
                    m_sel = idx;
                    m_focus = idx;
                }
            },
            else => {
                group.clearSelection();
                m_sel = null;
            },
        }
        try testing.expectEqual(m_focus, group.focused);
        try testing.expectEqual(m_sel, group.selected);
        if (m_sel) |s| {
            try testing.expectEqualStrings(items[s], group.selectedItem().?);
        } else {
            try testing.expect(group.selectedItem() == null);
        }
    }
}
