const std = @import("std");
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Form = sailor.tui.widgets.Form;
const Field = sailor.tui.widgets.Field;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const validators = sailor.tui.validators;
const symbols = sailor.tui.symbols;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const term_size = try sailor.term.getSize();
    const width = @min(term_size.cols, 80);
    const height = @min(term_size.rows, 30);

    var buffer = try Buffer.init(allocator, width, height);
    defer buffer.deinit();

    // Login form fields
    var login_fields = [_]Field{
        Field.init("Email").withValidator(validators.email),
        Field.init("Password").withPassword().withValidator(validators.notEmpty),
    };

    const login_form = Form.init(&login_fields)
        .withBlock(Block.init().withTitle("Login Form", .top_center).withBorderSet(symbols.BoxSet.rounded))
        .withLabelWidth(15)
        .withFocusedStyle(Style{ .fg = .cyan, .bold = true })
        .withErrorStyle(Style{ .fg = .red });

    // Center the form
    const form_width = 60;
    const form_height = 12;
    const form_area = Rect{
        .x = if (width > form_width) (width - form_width) / 2 else 0,
        .y = if (height > form_height) (height - form_height) / 2 else 0,
        .width = @min(form_width, width),
        .height = @min(form_height, height),
    };

    // Render form
    login_form.render(&buffer, form_area);

    // Instructions at bottom
    const instructions = "Tab: Next Field | Shift+Tab: Previous | Enter: Submit";
    const inst_y = form_area.y + form_area.height + 2;
    if (inst_y < height) {
        const inst_x = if (width > instructions.len)
            (width - @as(u16, @intCast(instructions.len))) / 2
        else
            0;
        for (instructions, 0..) |ch, i| {
            if (inst_x + i >= width) break;
            buffer.set(@intCast(inst_x + i), inst_y, .{
                .char = @intCast(ch),
                .style = Style{ .fg = .bright_black },
            });
        }
    }

    // Render to stdout
    var previous = try Buffer.init(allocator, width, height);
    defer previous.deinit();

    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);
    const writer = output_buf.writer(allocator);

    const diff_ops = try sailor.tui.buffer.diff(allocator, previous, buffer);
    defer allocator.free(diff_ops);
    try sailor.tui.buffer.renderDiff(diff_ops, writer);

    _ = try std.posix.write(std.posix.STDOUT_FILENO, output_buf.items);

    // Show feature summary
    std.debug.print("\n\n", .{});
    std.debug.print("Form Widget Demo (v1.25.0)\n", .{});
    std.debug.print("===========================\n\n", .{});
    std.debug.print("Features demonstrated:\n", .{});
    std.debug.print("  ✓ Form widget with multiple fields\n", .{});
    std.debug.print("  ✓ Field validators (email, notEmpty)\n", .{});
    std.debug.print("  ✓ Password field masking\n", .{});
    std.debug.print("  ✓ Custom label width\n", .{});
    std.debug.print("  ✓ Focused field styling\n", .{});
    std.debug.print("  ✓ Error display styling\n", .{});
    std.debug.print("  ✓ Rounded border block\n", .{});
    std.debug.print("  ✓ Help text at bottom\n\n", .{});
    std.debug.print("Available validators:\n", .{});
    std.debug.print("  • notEmpty, minLength, maxLength, exactLength\n", .{});
    std.debug.print("  • numeric, integer, decimal, minValue, maxValue\n", .{});
    std.debug.print("  • email, url, ipv4, hexadecimal\n", .{});
    std.debug.print("  • alphanumeric, alphabetic\n", .{});
    std.debug.print("  • Input masks (SSN, phone, date, credit card, etc.)\n\n", .{});
}
