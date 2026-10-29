//! Dialog widget: a centered modal for confirmation prompts and button-based interaction.
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
/// dialog.render(&buf, area);
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
/// dialog.render(&buf, area);
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

        const message_spans = [_]Span{Span.styled(self.message, self.style)};
        const message_lines = [_]Line{.{ .spans = &message_spans }};
        const para = Paragraph.fromLines(&message_lines).withAlignment(.center);
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
    const buttons = [_][]const u8{"OK"};
    var dialog = Dialog.init("Info", "Short", &buttons);
    dialog.width = 40;
    dialog.height = 10;

    const size = dialog.calculateSize();

    try std.testing.expectEqual(40, size.width);
    try std.testing.expectEqual(10, size.height);
}

const test_area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };

fn expect_row(buf: *const Buffer, x: u16, y: u16, text: []const u8) !void {
    for (text, 0..) |ch, i| {
        const cell = buf.getConst(x + @as(u16, @intCast(i)), y).?;
        try std.testing.expectEqual(@as(u21, ch), cell.char);
    }
}

test "Dialog.render centers frame, message and buttons" {
    const buttons = [_][]const u8{ "OK", "Cancel" };
    const dialog = Dialog.init("Alert", "Test message", &buttons);
    // Auto size is 18x8, so the frame sits at x=11, y=1 inside the 40x10 area.
    try std.testing.expectEqual(@as(u16, 18), dialog.calculateSize().width);
    try std.testing.expectEqual(@as(u16, 8), dialog.calculateSize().height);

    var buf = try Buffer.init(std.testing.allocator, test_area.width, test_area.height);
    defer buf.deinit();

    dialog.render(&buf, test_area);

    try std.testing.expectEqual(@as(u21, '┌'), buf.getConst(11, 1).?.char);
    try std.testing.expectEqual(@as(u21, '┐'), buf.getConst(28, 1).?.char);
    try std.testing.expectEqual(@as(u21, '└'), buf.getConst(11, 8).?.char);
    try std.testing.expectEqual(@as(u21, '┘'), buf.getConst(28, 8).?.char);
    try expect_row(&buf, 13, 1, "Alert");
    // Message is centered in the 16 column inner area: (16 - 12) / 2 = 2.
    try expect_row(&buf, 14, 2, "Test message");
    try expect_row(&buf, 12, 6, "[OK]");
    try expect_row(&buf, 18, 6, "[Cancel]");
    // Nothing leaks outside the frame.
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(10, 1).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(29, 8).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(0, 0).?.char);
}

test "Dialog.render styles the message and only the selected button" {
    const buttons = [_][]const u8{ "Yes", "No" };
    var dialog = Dialog.init("Confirm", "Delete file?", &buttons);
    dialog.style = Style{ .fg = .{ .indexed = 3 } };
    dialog.setSelected(1);

    var buf = try Buffer.init(std.testing.allocator, test_area.width, test_area.height);
    defer buf.deinit();

    dialog.render(&buf, test_area);

    // Auto size is 15x7: frame x = 12, y = 1; inner x = 13, width 13, height 5.
    try expect_row(&buf, 13, 2, "Delete file?");
    try std.testing.expectEqual(dialog.style, buf.getConst(13, 2).?.style);
    // Buttons start below the two message rows; their total width fills the inner width.
    try expect_row(&buf, 13, 5, "[Yes]");
    try std.testing.expectEqual(dialog.style, buf.getConst(13, 5).?.style);
    try expect_row(&buf, 20, 5, "[No]");
    try std.testing.expectEqual(dialog.selected_style, buf.getConst(20, 5).?.style);
    try std.testing.expectEqual(dialog.selected_style, buf.getConst(23, 5).?.style);
}

test "Dialog.render leaves the buffer untouched for an empty area" {
    const buttons = [_][]const u8{"OK"};
    const dialog = Dialog.init("Test", "Message", &buttons);
    const empty = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    dialog.render(&buf, empty);

    for (0..10) |row| {
        for (0..10) |col| {
            const cell = buf.getConst(@intCast(col), @intCast(row)).?;
            try std.testing.expectEqual(@as(u21, ' '), cell.char);
        }
    }
}

test "Dialog.render clamps the frame to a small area" {
    const buttons = [_][]const u8{ "A", "B", "C", "D", "E" };
    const dialog = Dialog.init("Choose", "Select an option", &buttons);
    const small = Rect{ .x = 2, .y = 1, .width = 8, .height = 4 };

    var buf = try Buffer.init(std.testing.allocator, 12, 6);
    defer buf.deinit();

    dialog.render(&buf, small);

    // The frame fills the clamped area exactly; cells outside stay blank.
    try std.testing.expectEqual(@as(u21, '┌'), buf.getConst(2, 1).?.char);
    try std.testing.expectEqual(@as(u21, '┐'), buf.getConst(9, 1).?.char);
    try std.testing.expectEqual(@as(u21, '└'), buf.getConst(2, 4).?.char);
    try std.testing.expectEqual(@as(u21, '┘'), buf.getConst(9, 4).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(1, 1).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(10, 4).?.char);
    try std.testing.expectEqual(@as(u21, ' '), buf.getConst(2, 5).?.char);
}

test "Dialog.render draws a bracket pair per button when they fit" {
    const buttons = [_][]const u8{ "A", "B", "C", "D", "E" };
    var dialog = Dialog.init("Choose", "Select an option", &buttons);
    dialog.setSelected(2);

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 15 };
    var buf = try Buffer.init(std.testing.allocator, area.width, area.height);
    defer buf.deinit();

    dialog.render(&buf, area);

    var open_count: u32 = 0;
    var close_count: u32 = 0;
    for (0..area.height) |row| {
        for (0..area.width) |col| {
            const cell = buf.getConst(@intCast(col), @intCast(row)).?;
            if (cell.char == '[') open_count += 1;
            if (cell.char == ']') close_count += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 5), open_count);
    try std.testing.expectEqual(@as(u32, 5), close_count);
}
