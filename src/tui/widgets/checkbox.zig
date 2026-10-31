//! Single and grouped checkbox widgets with focus, checked, and disabled styling.
const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Cell = @import("../buffer.zig").Cell;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;
const symbols = @import("../symbols.zig");
const UnicodeWidth = @import("../../unicode.zig").UnicodeWidth;

const help_text = "↑/↓: Navigate | Space: Toggle | A: All | N: None";

/// Draw `text` at (x, y), clipped to `max_cells` terminal cells (never splits a character).
fn putText(buf: *Buffer, x: u16, y: u16, max_cells: u16, text: []const u8, style: Style) void {
    const bytes = UnicodeWidth.truncate(text, max_cells);
    buf.setString(x, y, text[0..bytes], style);
}

/// Single checkbox widget
pub const Checkbox = struct {
    label: []const u8,
    checked: bool = false,
    style: Style = .{},
    checked_style: Style = .{ .fg = .green },
    focused_style: Style = .{ .bold = true },
    is_focused: bool = false,

    /// Creates a new checkbox with the given label.
    /// Default state: unchecked, unfocused, default styles.
    pub fn init(label: []const u8) Checkbox {
        return .{ .label = label };
    }

    /// Sets the checked state of the checkbox.
    /// Returns a new checkbox instance for method chaining.
    pub fn withChecked(self: Checkbox, checked: bool) Checkbox {
        var result = self;
        result.checked = checked;
        return result;
    }

    /// Sets the default style applied when the checkbox is neither checked nor focused.
    /// Returns a new checkbox instance for method chaining.
    pub fn withStyle(self: Checkbox, style: Style) Checkbox {
        var result = self;
        result.style = style;
        return result;
    }

    /// Sets the style applied when the checkbox is checked.
    /// Default: green foreground. Returns a new checkbox instance for method chaining.
    pub fn withCheckedStyle(self: Checkbox, style: Style) Checkbox {
        var result = self;
        result.checked_style = style;
        return result;
    }

    /// Sets the style applied when the checkbox has focus.
    /// Default: bold. Returns a new checkbox instance for method chaining.
    pub fn withFocusedStyle(self: Checkbox, style: Style) Checkbox {
        var result = self;
        result.focused_style = style;
        return result;
    }

    /// Sets the focus state of the checkbox.
    /// Used by CheckboxGroup to highlight the currently selected item.
    /// Returns a new checkbox instance for method chaining.
    pub fn withFocus(self: Checkbox, focused: bool) Checkbox {
        var result = self;
        result.is_focused = focused;
        return result;
    }

    /// Toggles the checkbox state between checked and unchecked.
    pub fn toggle(self: *Checkbox) void {
        self.checked = !self.checked;
    }

    /// Renders the checkbox to the given buffer within the specified area.
    /// Format: `[✓] Label` or `[ ] Label` depending on checked state.
    /// Applies appropriate style based on focus and checked state.
    pub fn render(self: Checkbox, buf: *Buffer, area: Rect) void {
        if (area.width < 4 or area.height == 0) return;

        const display_style = if (self.is_focused)
            self.focused_style
        else if (self.checked)
            self.checked_style
        else
            self.style;

        // Render checkbox indicator [✓] or [ ]
        buf.set(area.x, area.y, .{
            .char = '[',
            .style = display_style,
        });

        const sym = symbols.checkbox;
        const indicator = if (self.checked) sym.checked else sym.unchecked;
        buf.set(area.x + 1, area.y, .{
            .char = indicator,
            .style = display_style,
        });

        buf.set(area.x + 2, area.y, .{
            .char = ']',
            .style = display_style,
        });

        buf.set(area.x + 3, area.y, .{
            .char = ' ',
            .style = display_style,
        });

        // Render label (UTF-8 aware, clipped to the area)
        putText(buf, area.x +| 4, area.y, area.width - 4, self.label, display_style);
    }
};

/// Checkbox group for managing multiple related checkboxes
pub const CheckboxGroup = struct {
    items: []Checkbox,
    focused: usize = 0,
    block: ?Block = null,
    style: Style = .{},
    show_help: bool = true,

    /// Creates a new checkbox group from a slice of checkboxes.
    /// Focus starts on the first item. Help text is shown by default.
    pub fn init(items: []Checkbox) CheckboxGroup {
        return .{ .items = items };
    }

    /// Sets an optional border block around the checkbox group.
    /// Returns a new group instance for method chaining.
    pub fn withBlock(self: CheckboxGroup, block: Block) CheckboxGroup {
        var result = self;
        result.block = block;
        return result;
    }

    /// Sets the default style for the checkbox group background.
    /// Returns a new group instance for method chaining.
    pub fn withStyle(self: CheckboxGroup, style: Style) CheckboxGroup {
        var result = self;
        result.style = style;
        return result;
    }

    /// Controls whether to display keyboard shortcut help text at the bottom.
    /// Help text: "↑/↓: Navigate | Space: Toggle | A: All | N: None"
    /// Returns a new group instance for method chaining.
    pub fn withHelp(self: CheckboxGroup, show: bool) CheckboxGroup {
        var result = self;
        result.show_help = show;
        return result;
    }

    /// Get currently focused checkbox
    pub fn focusedItem(self: *CheckboxGroup) ?*Checkbox {
        if (self.focused < self.items.len) {
            return &self.items[self.focused];
        }
        return null;
    }

    /// Move focus to next checkbox
    pub fn focusNext(self: *CheckboxGroup) void {
        if (self.items.len == 0) return;
        self.focused = (self.focused + 1) % self.items.len;
    }

    /// Move focus to previous checkbox
    pub fn focusPrev(self: *CheckboxGroup) void {
        if (self.items.len == 0) return;
        if (self.focused == 0) {
            self.focused = self.items.len - 1;
        } else {
            self.focused -= 1;
        }
    }

    /// Toggle currently focused checkbox
    pub fn toggleFocused(self: *CheckboxGroup) void {
        if (self.focusedItem()) |item| {
            item.toggle();
        }
    }

    /// Get all checked items
    pub fn checkedItems(self: CheckboxGroup, allocator: std.mem.Allocator) ![][]const u8 {
        var count: usize = 0;
        for (self.items) |item| {
            if (item.checked) count += 1;
        }

        var result = try allocator.alloc([]const u8, count);
        var idx: usize = 0;
        for (self.items) |item| {
            if (item.checked) {
                result[idx] = item.label;
                idx += 1;
            }
        }
        return result;
    }

    /// Check all checkboxes
    pub fn checkAll(self: *CheckboxGroup) void {
        for (self.items) |*item| {
            item.checked = true;
        }
    }

    /// Uncheck all checkboxes
    pub fn uncheckAll(self: *CheckboxGroup) void {
        for (self.items) |*item| {
            item.checked = false;
        }
    }

    /// Renders the checkbox group to the given buffer within the specified area.
    /// Displays all checkboxes vertically with optional border block and help text.
    /// The focused checkbox is visually highlighted.
    pub fn render(self: CheckboxGroup, buf: *Buffer, area: Rect) void {
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

        // Render checkboxes
        var y: u16 = 0;
        for (self.items, 0..) |item, i| {
            if (y >= items_height) break;

            const is_focused = (i == self.focused);
            const checkbox = item.withFocus(is_focused);

            const item_area = Rect{
                .x = render_area.x,
                .y = render_area.y + y,
                .width = render_area.width,
                .height = 1,
            };
            checkbox.render(buf, item_area);
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
const bold: Style = .{ .bold = true };
const gray: Style = .{ .fg = .gray };

test "checkbox: init uses documented defaults" {
    const cb = Checkbox.init("Accept terms");
    try testing.expectEqualStrings("Accept terms", cb.label);
    try testing.expect(!cb.checked);
    try testing.expect(!cb.is_focused);
    try testing.expectEqual(Style{}, cb.style);
    try testing.expectEqual(green, cb.checked_style);
    try testing.expectEqual(bold, cb.focused_style);
}

test "checkbox: each builder replaces only its own field" {
    const base = Checkbox.init("X");
    const red: Style = .{ .fg = .red };

    const checked = base.withChecked(true);
    try testing.expect(checked.checked);
    try testing.expect(!checked.is_focused);
    try testing.expect(!base.checked); // builders return copies

    const styled = base.withStyle(red);
    try testing.expectEqual(red, styled.style);
    try testing.expectEqual(green, styled.checked_style);

    const cs = base.withCheckedStyle(red);
    try testing.expectEqual(red, cs.checked_style);
    try testing.expectEqual(Style{}, cs.style);

    const fs = base.withFocusedStyle(red);
    try testing.expectEqual(red, fs.focused_style);
    try testing.expectEqual(bold, base.focused_style);

    const focused = base.withFocus(true);
    try testing.expect(focused.is_focused);
    try testing.expect(!focused.checked);
    try testing.expect(!focused.withFocus(false).is_focused);
}

test "checkbox: toggle flips state and is its own inverse" {
    var cb = Checkbox.init("Toggle me");
    cb.toggle();
    try testing.expect(cb.checked);
    cb.toggle();
    try testing.expect(!cb.checked);
    try testing.expectEqualStrings("Toggle me", cb.label);
}

test "checkbox: render unchecked draws brackets, blank mark and label with base style" {
    var buf = try Buffer.init(testing.allocator, 12, 2);
    defer buf.deinit();

    Checkbox.init("Test").render(&buf, .{ .x = 0, .y = 0, .width = 12, .height = 1 });
    buf.check_invariants();

    try expectText(buf, 0, 0, "[ ] Test", .{});
    try expectText(buf, 8, 0, "    ", .{});
    try expectText(buf, 0, 1, " " ** 12, .{}); // row below the area untouched
}

test "checkbox: render checked draws the check mark in checked style" {
    var buf = try Buffer.init(testing.allocator, 12, 1);
    defer buf.deinit();

    Checkbox.init("Test").withChecked(true)
        .render(&buf, .{ .x = 0, .y = 0, .width = 12, .height = 1 });

    try expectText(buf, 0, 0, "[✓] Test", green);
    try testing.expectEqual(@as(u21, symbols.checkbox.checked), buf.getChar(1, 0));
    try expectText(buf, 8, 0, "    ", .{});
}

test "checkbox: base style is used for unchecked unfocused cells" {
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();

    const dim: Style = .{ .fg = .blue, .italic = true };
    Checkbox.init("ab").withStyle(dim).render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 1 });

    try expectText(buf, 0, 0, "[ ] ab", dim);
}

test "checkbox: focused style takes precedence over checked style on every cell" {
    var buf = try Buffer.init(testing.allocator, 12, 1);
    defer buf.deinit();

    const focused: Style = .{ .fg = .red, .bold = true };
    const cb = Checkbox.init("Test").withChecked(true).withFocus(true)
        .withCheckedStyle(green).withFocusedStyle(focused);
    cb.render(&buf, .{ .x = 0, .y = 0, .width = 12, .height = 1 });

    try expectText(buf, 0, 0, "[✓] Test", focused);
}

test "checkbox: label is clipped at the area width, not the buffer width" {
    var buf = try Buffer.init(testing.allocator, 20, 1);
    defer buf.deinit();

    Checkbox.init("Hello world").render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 1 });

    try expectText(buf, 0, 0, "[ ] Hell", .{});
    try expectText(buf, 8, 0, " " ** 12, .{});
}

test "checkbox: area narrower than the indicator or without height draws nothing" {
    var buf = try Buffer.init(testing.allocator, 10, 2);
    defer buf.deinit();

    const cb = Checkbox.init("Test").withChecked(true);
    cb.render(&buf, .{ .x = 0, .y = 0, .width = 3, .height = 1 });
    cb.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 0 });
    cb.render(&buf, .{ .x = 0, .y = 0, .width = 0, .height = 1 });
    try expectBlank(buf);
}

test "checkbox: area exactly four wide draws the indicator and no label" {
    var buf = try Buffer.init(testing.allocator, 10, 1);
    defer buf.deinit();

    Checkbox.init("Test").render(&buf, .{ .x = 0, .y = 0, .width = 4, .height = 1 });

    try expectText(buf, 0, 0, "[ ] ", .{});
    try expectText(buf, 4, 0, " " ** 6, .{});
}

test "checkbox: render honours the area origin and stays inside it" {
    var buf = try Buffer.init(testing.allocator, 12, 4);
    defer buf.deinit();

    const cb = Checkbox.init("ok").withChecked(true);
    cb.render(&buf, .{ .x = 3, .y = 2, .width = 7, .height = 2 });

    try expectText(buf, 3, 2, "[✓] ok", green);
    try expectText(buf, 0, 2, "   ", .{});
    try expectText(buf, 9, 2, "   ", .{});
    try expectText(buf, 0, 0, " " ** 12, .{});
    try expectText(buf, 0, 3, " " ** 12, .{}); // only the first row of the area is used
}

test "checkbox: multibyte label is drawn as codepoints, not bytes" {
    var buf = try Buffer.init(testing.allocator, 12, 1);
    defer buf.deinit();

    Checkbox.init("café").render(&buf, .{ .x = 0, .y = 0, .width = 12, .height = 1 });

    try expectText(buf, 0, 0, "[ ] café", .{});
    try expectText(buf, 8, 0, "    ", .{});
}

test "checkbox: wide character that does not fit the area is dropped whole" {
    var buf = try Buffer.init(testing.allocator, 12, 1);
    defer buf.deinit();

    Checkbox.init("日本").render(&buf, .{ .x = 0, .y = 0, .width = 7, .height = 1 });

    try expectText(buf, 0, 0, "[ ] 日", .{});
    // The second wide glyph needs cells 6-7 but the area ends at 7: not split.
    try testing.expectEqual(@as(u21, ' '), buf.getChar(6, 0));
    try testing.expectEqual(@as(u21, ' '), buf.getChar(7, 0));
}

test "checkbox: empty label renders just the indicator" {
    var buf = try Buffer.init(testing.allocator, 8, 1);
    defer buf.deinit();

    Checkbox.init("").withChecked(true).render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 1 });

    try expectText(buf, 0, 0, "[✓] ", green);
    try expectText(buf, 4, 0, "    ", .{});
}

test "checkbox group: init focuses the first item with help enabled" {
    var items = [_]Checkbox{ Checkbox.init("Option 1"), Checkbox.init("Option 2") };
    const group = CheckboxGroup.init(&items);

    try testing.expectEqual(@as(usize, 2), group.items.len);
    try testing.expectEqual(@as(usize, 0), group.focused);
    try testing.expect(group.show_help);
    try testing.expect(group.block == null);
    try testing.expectEqual(Style{}, group.style);
}

test "checkbox group: builders replace only their own field" {
    var items = [_]Checkbox{Checkbox.init("a")};
    const base = CheckboxGroup.init(&items);
    const blk = (Block{}).withTitle("T", .top_left);

    const with_block = base.withBlock(blk);
    try testing.expect(with_block.block != null);
    try testing.expect(with_block.show_help);

    const styled = base.withStyle(gray);
    try testing.expectEqual(gray, styled.style);
    try testing.expect(styled.block == null);

    const no_help = base.withHelp(false);
    try testing.expect(!no_help.show_help);
    try testing.expectEqual(Style{}, no_help.style);
    try testing.expect(base.show_help);
}

test "checkbox group: focus wraps forward and backward" {
    var items = [_]Checkbox{ Checkbox.init("1"), Checkbox.init("2"), Checkbox.init("3") };
    var group = CheckboxGroup.init(&items);

    group.focusPrev(); // wraps from the first to the last
    try testing.expectEqual(@as(usize, 2), group.focused);
    group.focusNext(); // wraps from the last to the first
    try testing.expectEqual(@as(usize, 0), group.focused);
    group.focusNext();
    try testing.expectEqual(@as(usize, 1), group.focused);
    group.focusPrev();
    try testing.expectEqual(@as(usize, 0), group.focused);
}

test "checkbox group: empty group ignores focus and toggle requests" {
    var items = [_]Checkbox{};
    var group = CheckboxGroup.init(&items);

    group.focusNext();
    group.focusPrev();
    group.toggleFocused();
    group.checkAll();
    group.uncheckAll();
    try testing.expectEqual(@as(usize, 0), group.focused);
    try testing.expect(group.focusedItem() == null);

    const checked = try group.checkedItems(testing.allocator);
    defer testing.allocator.free(checked);
    try testing.expectEqual(@as(usize, 0), checked.len);
}

test "checkbox group: focusedItem is null when focus is out of range" {
    var items = [_]Checkbox{Checkbox.init("only")};
    var group = CheckboxGroup.init(&items);

    try testing.expectEqualStrings("only", group.focusedItem().?.label);
    group.focused = 1;
    try testing.expect(group.focusedItem() == null);
    group.toggleFocused(); // no item to toggle
    try testing.expect(!items[0].checked);
}

test "checkbox group: toggleFocused flips only the focused item" {
    var items = [_]Checkbox{ Checkbox.init("A"), Checkbox.init("B") };
    var group = CheckboxGroup.init(&items);

    group.toggleFocused();
    try testing.expect(items[0].checked);
    try testing.expect(!items[1].checked);

    group.focusNext();
    group.toggleFocused();
    try testing.expect(items[0].checked);
    try testing.expect(items[1].checked);

    group.focusPrev();
    group.toggleFocused();
    try testing.expect(!items[0].checked);
    try testing.expect(items[1].checked);
}

test "checkbox group: checkedItems returns checked labels in order" {
    var items = [_]Checkbox{
        Checkbox.init("Red").withChecked(true),
        Checkbox.init("Green"),
        Checkbox.init("Blue").withChecked(true),
    };
    const group = CheckboxGroup.init(&items);

    const checked = try group.checkedItems(testing.allocator);
    defer testing.allocator.free(checked);
    try testing.expectEqual(@as(usize, 2), checked.len);
    try testing.expectEqualStrings("Red", checked[0]);
    try testing.expectEqualStrings("Blue", checked[1]);
}

test "checkbox group: checkedItems with nothing checked is empty" {
    var items = [_]Checkbox{ Checkbox.init("A"), Checkbox.init("B") };
    const group = CheckboxGroup.init(&items);

    const checked = try group.checkedItems(testing.allocator);
    defer testing.allocator.free(checked);
    try testing.expectEqual(@as(usize, 0), checked.len);
}

test "checkbox group: checkedItems propagates allocation failure" {
    var items = [_]Checkbox{Checkbox.init("A").withChecked(true)};
    const group = CheckboxGroup.init(&items);

    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    try testing.expectError(error.OutOfMemory, group.checkedItems(failing.allocator()));
}

test "checkbox group: checkAll and uncheckAll cover every item" {
    var items = [_]Checkbox{
        Checkbox.init("A"),
        Checkbox.init("B").withChecked(true),
        Checkbox.init("C"),
    };
    var group = CheckboxGroup.init(&items);

    group.checkAll();
    for (items) |item| try testing.expect(item.checked);

    group.uncheckAll();
    for (items) |item| try testing.expect(!item.checked);
}

test "checkbox group: render stacks items, highlights focus, and draws help" {
    var items = [_]Checkbox{
        Checkbox.init("Item 1"),
        Checkbox.init("Item 2").withChecked(true),
        Checkbox.init("Item 3"),
    };
    var group = CheckboxGroup.init(&items);
    group.focused = 1;

    var buf = try Buffer.init(testing.allocator, 50, 6);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 50, .height = 6 });
    buf.check_invariants();

    try expectText(buf, 0, 0, "[ ] Item 1", .{});
    try expectText(buf, 0, 1, "[✓] Item 2", bold); // focused wins over checked
    try expectText(buf, 0, 2, "[ ] Item 3", .{});
    try expectText(buf, 0, 3, " " ** 50, .{});
    try expectText(buf, 0, 4, " " ** 50, .{});
    try expectText(buf, 0, 5, "↑/↓: Navigate | Space: Toggle | A: All | N: None", gray);
    try expectText(buf, 48, 5, "  ", .{});
    // Rendering works on a copy: the caller's items keep their own focus flag.
    for (items) |item| try testing.expect(!item.is_focused);
}

test "checkbox group: checked unfocused item uses checked style" {
    var items = [_]Checkbox{ Checkbox.init("A"), Checkbox.init("B").withChecked(true) };
    const group = CheckboxGroup.init(&items).withHelp(false);

    var buf = try Buffer.init(testing.allocator, 10, 2);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 10, .height = 2 });

    try expectText(buf, 0, 0, "[ ] A", bold);
    try expectText(buf, 0, 1, "[✓] B", green);
}

test "checkbox group: help row replaces the last item when height is short" {
    var items = [_]Checkbox{ Checkbox.init("A"), Checkbox.init("B"), Checkbox.init("C") };
    const group = CheckboxGroup.init(&items);

    var buf = try Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 2 });

    try expectText(buf, 0, 0, "[ ] A", bold);
    try expectText(buf, 0, 1, "↑/↓: Navigate | Spac", gray);
    try expectText(buf, 0, 2, " " ** 20, .{}); // outside the area
}

test "checkbox group: without help every row up to the height shows an item" {
    var items = [_]Checkbox{ Checkbox.init("A"), Checkbox.init("B"), Checkbox.init("C") };
    const group = CheckboxGroup.init(&items).withHelp(false);

    var buf = try Buffer.init(testing.allocator, 8, 4);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 2 });

    try expectText(buf, 0, 0, "[ ] A", bold);
    try expectText(buf, 0, 1, "[ ] B", .{});
    try expectText(buf, 0, 2, " " ** 8, .{}); // third item does not fit
    try expectText(buf, 0, 3, " " ** 8, .{});
}

test "checkbox group: empty group renders only the help line" {
    var items = [_]Checkbox{};
    const group = CheckboxGroup.init(&items);

    var buf = try Buffer.init(testing.allocator, 12, 3);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 12, .height = 3 });

    try expectText(buf, 0, 0, " " ** 12, .{});
    try expectText(buf, 0, 1, " " ** 12, .{});
    try expectText(buf, 0, 2, "↑/↓: Navigat", gray);
}

test "checkbox group: background style fills the area and a zero-size area draws nothing" {
    var items = [_]Checkbox{Checkbox.init("A")};
    const group = CheckboxGroup.init(&items).withStyle(gray).withHelp(false);

    var buf = try Buffer.init(testing.allocator, 8, 3);
    defer buf.deinit();
    group.render(&buf, .{ .x = 1, .y = 1, .width = 6, .height = 2 });

    try expectText(buf, 0, 0, " " ** 8, .{});
    try expectText(buf, 0, 1, " ", .{});
    try expectText(buf, 1, 1, "[ ] A", bold);
    try expectText(buf, 6, 1, " ", gray);
    try expectText(buf, 1, 2, " " ** 6, gray);
    try expectText(buf, 7, 2, " ", .{});

    var empty = try Buffer.init(testing.allocator, 8, 3);
    defer empty.deinit();
    group.render(&empty, .{ .x = 0, .y = 0, .width = 0, .height = 0 });
    try expectBlank(empty);
}

test "checkbox group: area larger than the buffer is clipped without writing out of range" {
    var items = [_]Checkbox{Checkbox.init("Long label here")};
    const group = CheckboxGroup.init(&items);

    var buf = try Buffer.init(testing.allocator, 10, 2);
    defer buf.deinit();
    group.render(&buf, .{ .x = 4, .y = 0, .width = 40, .height = 9 });
    buf.check_invariants();

    try expectText(buf, 4, 0, "[ ] Lo", bold);
    try expectText(buf, 0, 0, "    ", .{});
    // The help row (y = 8) lies below the buffer and is clipped away.
    try expectText(buf, 0, 1, " " ** 10, .{});
}

test "checkbox group: block draws border and title, items and help go inside" {
    var items = [_]Checkbox{ Checkbox.init("One"), Checkbox.init("Two").withChecked(true) };
    const group = CheckboxGroup.init(&items)
        .withBlock((Block{}).withTitle("Pick", .top_left));

    var buf = try Buffer.init(testing.allocator, 30, 6);
    defer buf.deinit();
    group.render(&buf, .{ .x = 0, .y = 0, .width = 30, .height = 6 });

    try expectText(buf, 0, 0, "┌─Pick", .{});
    try expectText(buf, 29, 0, "┐", .{});
    try expectText(buf, 0, 5, "└" ++ "─" ** 28 ++ "┘", .{});
    try expectText(buf, 0, 1, "│", .{});
    try expectText(buf, 29, 3, "│", .{});
    try expectText(buf, 1, 1, "[ ] One", bold);
    try expectText(buf, 1, 2, "[✓] Two", green);
    try expectText(buf, 1, 4, "↑/↓: Navigate | Space: Toggl", gray);
    try expectText(buf, 29, 4, "│", .{}); // help is clipped to the inner width
}

test "checkbox group: seeded model run matches a plain bool-array reference" {
    var prng = std.Random.DefaultPrng.init(0xC4EC_B0C5);
    const rand = prng.random();
    const n = 5;
    var items: [n]Checkbox = undefined;
    for (&items) |*it| it.* = Checkbox.init("x");
    var group = CheckboxGroup.init(&items);
    var model = [_]bool{false} ** n;
    var focus: usize = 0;

    for (0..400) |_| {
        switch (rand.uintLessThan(u8, 5)) {
            0 => {
                group.focusNext();
                focus = (focus + 1) % n;
            },
            1 => {
                group.focusPrev();
                focus = (focus + n - 1) % n;
            },
            2 => {
                group.toggleFocused();
                model[focus] = !model[focus];
            },
            3 => {
                group.checkAll();
                model = [_]bool{true} ** n;
            },
            else => {
                group.uncheckAll();
                model = [_]bool{false} ** n;
            },
        }
        try testing.expectEqual(focus, group.focused);
        var want: usize = 0;
        for (model, 0..) |m, i| {
            try testing.expectEqual(m, items[i].checked);
            if (m) want += 1;
        }
        const got = try group.checkedItems(testing.allocator);
        defer testing.allocator.free(got);
        try testing.expectEqual(want, got.len);
    }
}
