const std = @import("std");
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Line = @import("../style.zig").Line;
const Span = @import("../style.zig").Span;
const Block = @import("block.zig").Block;
const Borders = @import("block.zig").Borders;
const Paragraph = @import("paragraph.zig").Paragraph;
const Alignment = @import("paragraph.zig").Alignment;

/// Dialog widget for modal confirmation prompts and user interaction
/// Renders a centered modal dialog with title, message, and button options
///
/// Example: Simple confirmation dialog
/// ```zig
/// const buttons = [_][]const u8{ "Yes", "No" };
/// var dialog = Dialog.init("Delete File", "Are you sure?", &buttons);
///
/// // Handle keyboard input
/// switch (key) {
///     Key.left => dialog.prevButton(),
///     Key.right => dialog.nextButton(),
///     Key.enter => {
///         if (dialog.selected == 0) {
///             // User confirmed
///         }
///     },
///     else => {},
/// }
///
/// try dialog.render(&buf, area);
/// ```
///
/// Example: Custom styled dialog
/// ```zig
/// const options = [_][]const u8{ "Save", "Don't Save", "Cancel" };
/// var dialog = Dialog.init("Unsaved Changes", "Save before closing?", &options);
/// dialog.width = 50;
/// dialog.height = 12;
/// dialog.style = Style{ .fg = .{ .indexed = 15 } };
/// dialog.selected_style = Style{
///     .fg = .{ .indexed = 0 },
///     .bg = .{ .indexed = 12 },
/// };
///
/// try dialog.render(&buf, area);
/// ```
pub const Dialog = struct {
    /// Dialog title
    title: []const u8,
    /// Dialog message/content
    message: []const u8,
    /// Button labels (e.g., &[_][]const u8{"OK", "Cancel"})
    buttons: []const []const u8,
    /// Currently selected button index
    selected: usize,
    /// Style for the dialog box
    style: Style,
    /// Style for the selected button
    selected_style: Style,
    /// Width of the dialog (in cells, 0 = auto-size)
    width: u16,
    /// Height of the dialog (in cells, 0 = auto-size)
    height: u16,

    /// Create dialog with title, message, and button labels.
    pub fn init(title: []const u8, message: []const u8, buttons: []const []const u8) Dialog {
        return Dialog{
            .title = title,
            .message = message,
            .buttons = buttons,
            .selected = 0,
            .style = Style{},
            .selected_style = Style{ .fg = .{ .indexed = 0 }, .bg = .{ .indexed = 7 } },
            .width = 0,
            .height = 0,
        };
    }

    /// Set the selected button index
    pub fn setSelected(self: *Dialog, idx: usize) void {
        if (idx < self.buttons.len) {
            self.selected = idx;
        }
    }

    /// Move selection to next button (wraps around)
    pub fn nextButton(self: *Dialog) void {
        self.selected = (self.selected + 1) % self.buttons.len;
    }

    /// Move selection to previous button (wraps around)
    pub fn prevButton(self: *Dialog) void {
        if (self.selected == 0) {
            self.selected = self.buttons.len - 1;
        } else {
            self.selected -= 1;
        }
    }

    /// Calculate required size for the dialog
    fn calculateSize(self: Dialog) struct { width: u16, height: u16 } {
        // Title length + borders + padding
        const min_width = @as(u16, @intCast(@min(self.title.len + 4, 80)));

        // Message lines (estimate by length / width ratio)
        const msg_width = if (self.width > 0) self.width -| 4 else min_width -| 4;
        const msg_lines = if (msg_width > 0)
            @as(u16, @intCast((self.message.len + msg_width - 1) / msg_width))
        else
            1;

        // Buttons line
        var btn_width: usize = 0;
        for (self.buttons) |btn| {
            btn_width += btn.len + 4; // Button + spacing
        }

        const width = if (self.width > 0)
            self.width
        else
            @max(min_width, @as(u16, @intCast(@min(btn_width + 2, 80))));

        const height = if (self.height > 0)
            self.height
        else
            msg_lines + 5; // Title + message + buttons + borders + spacing

        return .{ .width = width, .height = height };
    }

    /// Render the dialog centered in the given area
    pub fn render(self: Dialog, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;

        const size = self.calculateSize();
        const width = @min(size.width, area.width);
        const height = @min(size.height, area.height);

        // Center the dialog
        const x = area.x + (area.width -| width) / 2;
        const y = area.y + (area.height -| height) / 2;

        const dialog_area = Rect{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };

        // Draw outer block with title
        var block = Block{
            .title = self.title,
            .borders = Borders.all,
            .border_style = self.style,
        };
        block.render(buf, dialog_area);

        // Calculate inner area for content
        const inner = block.inner(dialog_area);
        if (inner.width == 0 or inner.height == 0) return;

        // Render message
        const msg_height = if (inner.height > 3) inner.height -| 3 else 1;
        const msg_area = Rect{
            .x = inner.x,
            .y = inner.y,
            .width = inner.width,
            .height = msg_height,
        };

        var para = Paragraph{
            .text = self.message,
            .style = self.style,
            .alignment = .center,
        };
        para.render(buf, msg_area);

        // Render buttons
        if (inner.height > msg_height + 1) {
            const btn_y = inner.y + msg_height + 1;
            self.renderButtons(buf, Rect{
                .x = inner.x,
                .y = btn_y,
                .width = inner.width,
                .height = inner.height -| (msg_height + 1),
            });
        }
    }

    fn renderButtons(self: Dialog, buf: *Buffer, area: Rect) void {
        if (self.buttons.len == 0 or area.width == 0) return;

        // Calculate total buttons width
        var total_width: usize = 0;
        for (self.buttons) |btn| {
            total_width += btn.len + 4; // [Button] format with spacing
        }

        // Center buttons horizontally
        const start_x = if (total_width < area.width)
            area.x + @as(u16, @intCast((area.width - total_width) / 2))
        else
            area.x;

        var x = start_x;
        for (self.buttons, 0..) |btn, i| {
            const is_selected = (i == self.selected);
            const btn_style = if (is_selected) self.selected_style else self.style;

            // Draw button: [ Label ]
            if (x < area.x + area.width) {
                buf.set(x, area.y, .{ .char = '[', .style = btn_style });
                x += 1;

                // Button text
                for (btn) |ch| {
                    if (x >= area.x + area.width) break;
                    buf.set(x, area.y, .{ .char = ch, .style = btn_style });
                    x += 1;
                }

                if (x < area.x + area.width) {
                    buf.set(x, area.y, .{ .char = ']', .style = btn_style });
                    x += 1;
                }

                // Spacing between buttons
                x += 2;
            }
        }
    }
};

// Tests
test "Dialog.init" {
    const buttons = [_][]const u8{ "Yes", "No" };
    const dialog = Dialog.init("Confirm", "Are you sure?", &buttons);

    try std.testing.expectEqualStrings("Confirm", dialog.title);
    try std.testing.expectEqualStrings("Are you sure?", dialog.message);
    try std.testing.expectEqual(2, dialog.buttons.len);
    try std.testing.expectEqual(0, dialog.selected);
}

test "Dialog.setSelected" {
    const buttons = [_][]const u8{ "Yes", "No", "Cancel" };
    var dialog = Dialog.init("Test", "Message", &buttons);

    try std.testing.expectEqual(0, dialog.selected);

    dialog.setSelected(1);
    try std.testing.expectEqual(1, dialog.selected);

    dialog.setSelected(2);
    try std.testing.expectEqual(2, dialog.selected);

    // Out of bounds should be ignored
    dialog.setSelected(10);
    try std.testing.expectEqual(2, dialog.selected);
}

test "Dialog.nextButton" {
    const buttons = [_][]const u8{ "A", "B", "C" };
    var dialog = Dialog.init("Test", "Message", &buttons);

    try std.testing.expectEqual(0, dialog.selected);

    dialog.nextButton();
    try std.testing.expectEqual(1, dialog.selected);

    dialog.nextButton();
    try std.testing.expectEqual(2, dialog.selected);

    // Should wrap around
    dialog.nextButton();
    try std.testing.expectEqual(0, dialog.selected);
}

test "Dialog.prevButton" {
    const buttons = [_][]const u8{ "A", "B", "C" };
    var dialog = Dialog.init("Test", "Message", &buttons);

    dialog.setSelected(2);
    try std.testing.expectEqual(2, dialog.selected);

    dialog.prevButton();
    try std.testing.expectEqual(1, dialog.selected);

    dialog.prevButton();
    try std.testing.expectEqual(0, dialog.selected);

    // Should wrap around
    dialog.prevButton();
    try std.testing.expectEqual(2, dialog.selected);
}

test "Dialog.calculateSize default" {
    const buttons = [_][]const u8{ "OK", "Cancel" };
    const dialog = Dialog.init("Confirmation", "Are you sure you want to proceed?", &buttons);

    const size = dialog.calculateSize();

    // Should have reasonable defaults
    try std.testing.expect(size.width > 10);
    try std.testing.expect(size.height >= 5); // Title + message + buttons + borders
}

test "Dialog.calculateSize custom" {
    const buttons = [_][]const u8{ "OK" };
    var dialog = Dialog.init("Info", "Short", &buttons);
    dialog.width = 40;
    dialog.height = 10;

    const size = dialog.calculateSize();

    try std.testing.expectEqual(40, size.width);
    try std.testing.expectEqual(10, size.height);
}

test "Dialog.render simple" {
    const allocator = std.testing.allocator;
    const buttons = [_][]const u8{ "OK", "Cancel" };
    const dialog = Dialog.init("Alert", "Test message", &buttons);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    var buf = try Buffer.init(allocator, area);
    defer buf.deinit();

    try dialog.render(&buf, area);

    // Dialog should be rendered (check that some cells are non-empty)
    var non_empty: usize = 0;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getCell(@intCast(col), @intCast(row));
            if (cell.char != ' ') non_empty += 1;
        }
    }

    try std.testing.expect(non_empty > 0);
}

test "Dialog.render with selection" {
    const allocator = std.testing.allocator;
    const buttons = [_][]const u8{ "Yes", "No" };
    var dialog = Dialog.init("Confirm", "Delete file?", &buttons);

    const area = Rect{ .x = 0, .y = 0, .width = 50, .height = 12 };
    var buf = try Buffer.init(allocator, area);
    defer buf.deinit();

    dialog.setSelected(1); // Select "No"

    try dialog.render(&buf, area);

    // Should render without errors
    var found_bracket = false;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getCell(@intCast(col), @intCast(row));
            if (cell.char == '[' or cell.char == ']') {
                found_bracket = true;
            }
        }
    }

    try std.testing.expect(found_bracket); // Buttons should have brackets
}

test "Dialog.render empty area" {
    const allocator = std.testing.allocator;
    const buttons = [_][]const u8{"OK"};
    const dialog = Dialog.init("Test", "Message", &buttons);

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    var buf = try Buffer.init(allocator, Rect{ .x = 0, .y = 0, .width = 10, .height = 10 });
    defer buf.deinit();

    // Should not crash with empty area
    try dialog.render(&buf, area);
}

test "Dialog.render many buttons" {
    const allocator = std.testing.allocator;
    const buttons = [_][]const u8{ "A", "B", "C", "D", "E" };
    var dialog = Dialog.init("Choose", "Select an option", &buttons);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    var buf = try Buffer.init(allocator, area);
    defer buf.deinit();

    dialog.setSelected(2); // Select "C"

    try dialog.render(&buf, area);

    // All buttons should be rendered (check for brackets)
    var bracket_count: usize = 0;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getCell(@intCast(col), @intCast(row));
            if (cell.char == '[' or cell.char == ']') {
                bracket_count += 1;
            }
        }
    }

    // Should have at least 2 brackets per button (opening and closing)
    try std.testing.expect(bracket_count >= 10); // 5 buttons × 2 brackets
}
