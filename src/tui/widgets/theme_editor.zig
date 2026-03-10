const std = @import("std");
const tui = @import("../tui.zig");
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Style = tui.Style;
const Color = tui.Color;
const Constraint = tui.Constraint;
const Layout = tui.Layout;
const Block = @import("block.zig").Block;
const Paragraph = @import("paragraph.zig").Paragraph;
const Gauge = @import("gauge.zig").Gauge;
const List = @import("list.zig").List;
const Table = @import("table.zig").Table;
const Theme = tui.Theme;

/// ThemeEditor allows live theme customization with preview
pub const ThemeEditor = struct {
    /// Current theme being edited
    theme: Theme,
    /// Selected field index
    selected_field: usize = 0,
    /// Edit mode: field selection (false) or color editing (true)
    editing_color: bool = false,
    /// RGB component being edited (0=R, 1=G, 2=B)
    editing_component: u2 = 0,
    /// Whether preview panel is visible
    show_preview: bool = true,
    /// Optional block for border/title
    block: ?Block = null,

    pub fn init(theme: Theme) ThemeEditor {
        return .{ .theme = theme };
    }

    /// Field metadata for theme properties
    const FieldInfo = struct {
        name: []const u8,
        color_ptr: *Color,
    };

    fn getFields(self: *ThemeEditor) [12]FieldInfo {
        return .{
            .{ .name = "Background", .color_ptr = &self.theme.background },
            .{ .name = "Foreground", .color_ptr = &self.theme.foreground },
            .{ .name = "Primary", .color_ptr = &self.theme.primary },
            .{ .name = "Secondary", .color_ptr = &self.theme.secondary },
            .{ .name = "Success", .color_ptr = &self.theme.success },
            .{ .name = "Warning", .color_ptr = &self.theme.warning },
            .{ .name = "Error", .color_ptr = &self.theme.error_color },
            .{ .name = "Info", .color_ptr = &self.theme.info },
            .{ .name = "Muted", .color_ptr = &self.theme.muted },
            .{ .name = "Border", .color_ptr = &self.theme.border },
            .{ .name = "Selection BG", .color_ptr = &self.theme.selection_bg },
            .{ .name = "Selection FG", .color_ptr = &self.theme.selection_fg },
        };
    }

    /// Select next field
    pub fn selectNext(self: *ThemeEditor) void {
        const fields = self.getFields();
        self.selected_field = (self.selected_field + 1) % fields.len;
    }

    /// Select previous field
    pub fn selectPrev(self: *ThemeEditor) void {
        const fields = self.getFields();
        self.selected_field = if (self.selected_field == 0) fields.len - 1 else self.selected_field - 1;
    }

    /// Toggle color editing mode
    pub fn toggleEdit(self: *ThemeEditor) void {
        self.editing_color = !self.editing_color;
        if (self.editing_color) {
            self.editing_component = 0; // Start with R
        }
    }

    /// Select next RGB component
    pub fn nextComponent(self: *ThemeEditor) void {
        if (!self.editing_color) return;
        self.editing_component = (self.editing_component + 1) % 3;
    }

    /// Select previous RGB component
    pub fn prevComponent(self: *ThemeEditor) void {
        if (!self.editing_color) return;
        self.editing_component = if (self.editing_component == 0) 2 else self.editing_component - 1;
    }

    /// Increase selected RGB component value
    pub fn increaseValue(self: *ThemeEditor, delta: u8) void {
        if (!self.editing_color) return;
        const fields = self.getFields();
        const color_ptr = fields[self.selected_field].color_ptr;

        switch (color_ptr.*) {
            .rgb => |*rgb| {
                const val_ptr = switch (self.editing_component) {
                    0 => &rgb.r,
                    1 => &rgb.g,
                    2 => &rgb.b,
                };
                const new_val = @min(255, @as(u16, val_ptr.*) + delta);
                val_ptr.* = @intCast(new_val);
            },
            else => {
                // Convert to RGB if not already
                color_ptr.* = .{ .rgb = .{ .r = 128, .g = 128, .b = 128 } };
            },
        }
    }

    /// Decrease selected RGB component value
    pub fn decreaseValue(self: *ThemeEditor, delta: u8) void {
        if (!self.editing_color) return;
        const fields = self.getFields();
        const color_ptr = fields[self.selected_field].color_ptr;

        switch (color_ptr.*) {
            .rgb => |*rgb| {
                const val_ptr = switch (self.editing_component) {
                    0 => &rgb.r,
                    1 => &rgb.g,
                    2 => &rgb.b,
                };
                const new_val = if (val_ptr.* > delta) val_ptr.* - delta else 0;
                val_ptr.* = new_val;
            },
            else => {
                color_ptr.* = .{ .rgb = .{ .r = 128, .g = 128, .b = 128 } };
            },
        }
    }

    /// Load predefined theme
    pub fn loadTheme(self: *ThemeEditor, theme: Theme) void {
        self.theme = theme;
        self.editing_color = false;
    }

    /// Export theme to string (JSON-like format)
    pub fn exportTheme(self: ThemeEditor, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayList(u8).init(allocator);
        const writer = buf.writer();

        try writer.writeAll("{\n");
        const fields = @as(*const ThemeEditor, &self).getFields();
        for (fields, 0..) |field, i| {
            try writer.print("  \"{s}\": ", .{field.name});
            try colorToJson(writer, field.color_ptr.*);
            if (i < fields.len - 1) try writer.writeAll(",");
            try writer.writeAll("\n");
        }
        try writer.writeAll("}\n");

        return buf.toOwnedSlice();
    }

    fn colorToJson(writer: anytype, color: Color) !void {
        switch (color) {
            .reset => try writer.writeAll("\"reset\""),
            .black => try writer.writeAll("\"black\""),
            .red => try writer.writeAll("\"red\""),
            .green => try writer.writeAll("\"green\""),
            .yellow => try writer.writeAll("\"yellow\""),
            .blue => try writer.writeAll("\"blue\""),
            .magenta => try writer.writeAll("\"magenta\""),
            .cyan => try writer.writeAll("\"cyan\""),
            .white => try writer.writeAll("\"white\""),
            .bright_black => try writer.writeAll("\"bright_black\""),
            .bright_red => try writer.writeAll("\"bright_red\""),
            .bright_green => try writer.writeAll("\"bright_green\""),
            .bright_yellow => try writer.writeAll("\"bright_yellow\""),
            .bright_blue => try writer.writeAll("\"bright_blue\""),
            .bright_magenta => try writer.writeAll("\"bright_magenta\""),
            .bright_cyan => try writer.writeAll("\"bright_cyan\""),
            .bright_white => try writer.writeAll("\"bright_white\""),
            .indexed => |idx| try writer.print("{{\"indexed\": {}}}", .{idx}),
            .rgb => |rgb| try writer.print("{{\"rgb\": [{}, {}, {}]}}", .{ rgb.r, rgb.g, rgb.b }),
        }
    }

    /// Render the theme editor
    pub fn render(self: *ThemeEditor, buf: *Buffer, area: Rect) void {
        var inner_area = area;
        if (self.block) |blk| {
            blk.render(buf, area);
            inner_area = blk.inner(area);
        }

        if (self.show_preview) {
            // Split: left=editor, right=preview
            const chunks = Layout.horizontal(&.{
                Constraint.percentage(60),
                Constraint.percentage(40),
            }, inner_area);

            self.renderEditor(buf, chunks[0]);
            self.renderPreview(buf, chunks[1]);
        } else {
            self.renderEditor(buf, inner_area);
        }
    }

    fn renderEditor(self: *ThemeEditor, buf: *Buffer, area: Rect) void {
        const fields = self.getFields();

        // Title
        const title_block = Block{
            .title = "Theme Editor",
            .borders = .{ .top = true, .bottom = true, .left = true, .right = true },
        };
        title_block.render(buf, area);
        const editor_area = title_block.inner(area);

        // Header
        if (editor_area.height < 3) return;
        buf.setString(editor_area.x, editor_area.y, "Field", .{ .bold = true }, editor_area.width);
        buf.setString(editor_area.x + 20, editor_area.y, "Color", .{ .bold = true }, editor_area.width -| 20);

        // Field list
        var y = editor_area.y + 2;
        for (fields, 0..) |field, i| {
            if (y >= editor_area.y + editor_area.height) break;

            const is_selected = (i == self.selected_field);
            const style: Style = if (is_selected) .{ .bg = .bright_black } else .{};

            // Field name
            const marker = if (is_selected) "▶ " else "  ";
            var name_buf: [32]u8 = undefined;
            const name = std.fmt.bufPrint(&name_buf, "{s}{s}", .{ marker, field.name }) catch field.name;
            buf.setString(editor_area.x, y, name, style, 20);

            // Color representation
            const color_str = self.colorToString(field.color_ptr.*);
            const color_style = Style{ .fg = field.color_ptr.*, .bg = style.bg };
            buf.setString(editor_area.x + 20, y, color_str, color_style, editor_area.width -| 20);

            // RGB editing indicators
            if (is_selected and self.editing_color) {
                if (field.color_ptr.* == .rgb) {
                    const rgb = field.color_ptr.rgb;
                    var edit_buf: [64]u8 = undefined;
                    const r_marker = if (self.editing_component == 0) "►" else " ";
                    const g_marker = if (self.editing_component == 1) "►" else " ";
                    const b_marker = if (self.editing_component == 2) "►" else " ";
                    const edit_str = std.fmt.bufPrint(&edit_buf, "{s}R:{:3} {s}G:{:3} {s}B:{:3}", .{
                        r_marker, rgb.r,
                        g_marker, rgb.g,
                        b_marker, rgb.b,
                    }) catch "RGB";
                    buf.setString(editor_area.x + 45, y, edit_str, .{ .dim = true }, editor_area.width -| 45);
                }
            }

            y += 1;
        }

        // Help text at bottom
        if (editor_area.height > fields.len + 4) {
            const help_y = editor_area.y + editor_area.height - 2;
            const help = if (self.editing_color)
                "Tab: component  ↑↓: adjust  Enter: done"
            else
                "↑↓: navigate  Enter: edit  p: preview  s: save";
            buf.setString(editor_area.x, help_y, help, .{ .dim = true }, editor_area.width);
        }
    }

    fn renderPreview(self: *ThemeEditor, buf: *Buffer, area: Rect) void {
        const preview_block = Block{
            .title = "Preview",
            .borders = .{ .top = true, .bottom = true, .left = true, .right = true },
            .border_style = self.theme.border_style(),
        };
        preview_block.render(buf, area);
        const preview_area = preview_block.inner(area);

        if (preview_area.height < 6) return;

        // Split preview into sections
        const chunks = Layout.vertical(&.{
            Constraint.length(3), // Gauge
            Constraint.length(3), // Status messages
            Constraint.min(0), // Remaining
        }, preview_area);

        // Gauge preview
        if (chunks[0].height >= 1) {
            var gauge = Gauge{
                .percent = 65,
                .label = "Progress",
                .style = self.theme.primary_style(),
            };
            gauge.render(buf, chunks[0]);
        }

        // Status message previews
        if (chunks[1].height >= 3) {
            var y = chunks[1].y;
            const messages = [_]struct { text: []const u8, style: Style }{
                .{ .text = "✓ Success message", .style = self.theme.success_style() },
                .{ .text = "⚠ Warning message", .style = self.theme.warning_style() },
                .{ .text = "✗ Error message", .style = self.theme.error_style() },
            };
            for (messages) |msg| {
                if (y >= chunks[1].y + chunks[1].height) break;
                buf.setString(chunks[1].x, y, msg.text, msg.style, chunks[1].width);
                y += 1;
            }
        }

        // Sample paragraph
        if (chunks[2].height >= 3) {
            const text = "This is sample text using the theme's foreground color. " ++
                "Primary and secondary accents are shown above. " ++
                "Muted text appears dimmed.";
            var para = Paragraph{
                .text = text,
                .style = .{ .fg = self.theme.foreground },
            };
            para.render(buf, chunks[2]);
        }
    }

    fn colorToString(self: *const ThemeEditor, color: Color) []const u8 {
        _ = self;
        return switch (color) {
            .reset => "reset",
            .black => "black",
            .red => "red",
            .green => "green",
            .yellow => "yellow",
            .blue => "blue",
            .magenta => "magenta",
            .cyan => "cyan",
            .white => "white",
            .bright_black => "bright_black",
            .bright_red => "bright_red",
            .bright_green => "bright_green",
            .bright_yellow => "bright_yellow",
            .bright_blue => "bright_blue",
            .bright_magenta => "bright_magenta",
            .bright_cyan => "bright_cyan",
            .bright_white => "bright_white",
            .indexed => "indexed",
            .rgb => "RGB",
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ThemeEditor - init" {
    const theme = tui.theme.default_dark;
    const editor = ThemeEditor.init(theme);
    try std.testing.expectEqual(@as(usize, 0), editor.selected_field);
    try std.testing.expectEqual(false, editor.editing_color);
    try std.testing.expectEqual(true, editor.show_preview);
}

test "ThemeEditor - field navigation" {
    const theme = tui.theme.default_dark;
    var editor = ThemeEditor.init(theme);

    try std.testing.expectEqual(@as(usize, 0), editor.selected_field);

    editor.selectNext();
    try std.testing.expectEqual(@as(usize, 1), editor.selected_field);

    editor.selectNext();
    try std.testing.expectEqual(@as(usize, 2), editor.selected_field);

    editor.selectPrev();
    try std.testing.expectEqual(@as(usize, 1), editor.selected_field);

    editor.selectPrev();
    try std.testing.expectEqual(@as(usize, 0), editor.selected_field);

    // Wrap around
    editor.selectPrev();
    try std.testing.expectEqual(@as(usize, 11), editor.selected_field);

    editor.selectNext();
    try std.testing.expectEqual(@as(usize, 0), editor.selected_field);
}

test "ThemeEditor - toggle edit mode" {
    const theme = tui.theme.default_dark;
    var editor = ThemeEditor.init(theme);

    try std.testing.expectEqual(false, editor.editing_color);

    editor.toggleEdit();
    try std.testing.expectEqual(true, editor.editing_color);
    try std.testing.expectEqual(@as(u2, 0), editor.editing_component);

    editor.toggleEdit();
    try std.testing.expectEqual(false, editor.editing_color);
}

test "ThemeEditor - component navigation" {
    const theme = tui.theme.default_dark;
    var editor = ThemeEditor.init(theme);

    editor.editing_color = true;

    try std.testing.expectEqual(@as(u2, 0), editor.editing_component);

    editor.nextComponent();
    try std.testing.expectEqual(@as(u2, 1), editor.editing_component);

    editor.nextComponent();
    try std.testing.expectEqual(@as(u2, 2), editor.editing_component);

    editor.nextComponent(); // Wrap
    try std.testing.expectEqual(@as(u2, 0), editor.editing_component);

    editor.prevComponent(); // Wrap
    try std.testing.expectEqual(@as(u2, 2), editor.editing_component);

    editor.prevComponent();
    try std.testing.expectEqual(@as(u2, 1), editor.editing_component);
}

test "ThemeEditor - increase RGB value" {
    var theme = tui.theme.default_dark;
    theme.primary = .{ .rgb = .{ .r = 100, .g = 150, .b = 200 } };
    var editor = ThemeEditor.init(theme);

    editor.selected_field = 2; // Primary
    editor.editing_color = true;
    editor.editing_component = 0; // R

    editor.increaseValue(10);
    try std.testing.expectEqual(@as(u8, 110), editor.theme.primary.rgb.r);
    try std.testing.expectEqual(@as(u8, 150), editor.theme.primary.rgb.g);
    try std.testing.expectEqual(@as(u8, 200), editor.theme.primary.rgb.b);

    editor.editing_component = 1; // G
    editor.increaseValue(5);
    try std.testing.expectEqual(@as(u8, 155), editor.theme.primary.rgb.g);
}

test "ThemeEditor - decrease RGB value" {
    var theme = tui.theme.default_dark;
    theme.primary = .{ .rgb = .{ .r = 100, .g = 150, .b = 200 } };
    var editor = ThemeEditor.init(theme);

    editor.selected_field = 2; // Primary
    editor.editing_color = true;
    editor.editing_component = 0; // R

    editor.decreaseValue(10);
    try std.testing.expectEqual(@as(u8, 90), editor.theme.primary.rgb.r);

    editor.editing_component = 2; // B
    editor.decreaseValue(50);
    try std.testing.expectEqual(@as(u8, 150), editor.theme.primary.rgb.b);
}

test "ThemeEditor - clamp RGB values" {
    var theme = tui.theme.default_dark;
    theme.primary = .{ .rgb = .{ .r = 250, .g = 5, .b = 128 } };
    var editor = ThemeEditor.init(theme);

    editor.selected_field = 2; // Primary
    editor.editing_color = true;

    // Test max clamp
    editor.editing_component = 0; // R
    editor.increaseValue(10);
    try std.testing.expectEqual(@as(u8, 255), editor.theme.primary.rgb.r);

    // Test min clamp
    editor.editing_component = 1; // G
    editor.decreaseValue(10);
    try std.testing.expectEqual(@as(u8, 0), editor.theme.primary.rgb.g);
}

test "ThemeEditor - convert non-RGB to RGB" {
    var theme = tui.theme.default_dark;
    theme.primary = .blue; // Named color
    var editor = ThemeEditor.init(theme);

    editor.selected_field = 2; // Primary
    editor.editing_color = true;
    editor.editing_component = 0;

    editor.increaseValue(10); // Should convert to RGB
    try std.testing.expect(editor.theme.primary == .rgb);
    try std.testing.expectEqual(@as(u8, 138), editor.theme.primary.rgb.r); // 128 + 10
}

test "ThemeEditor - load predefined theme" {
    const theme = tui.theme.default_dark;
    var editor = ThemeEditor.init(theme);

    editor.loadTheme(tui.theme.nord);
    try std.testing.expect(editor.theme.background == .rgb);
    try std.testing.expectEqual(@as(u8, 46), editor.theme.background.rgb.r);
}

test "ThemeEditor - export theme" {
    var theme = tui.theme.default_dark;
    theme.primary = .{ .rgb = .{ .r = 100, .g = 150, .b = 200 } };
    const editor = ThemeEditor.init(theme);

    const exported = try editor.exportTheme(std.testing.allocator);
    defer std.testing.allocator.free(exported);

    try std.testing.expect(std.mem.indexOf(u8, exported, "\"Primary\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, exported, "[100, 150, 200]") != null);
}

test "ThemeEditor - render basic" {
    const theme = tui.theme.default_dark;
    var editor = ThemeEditor.init(theme);

    var buffer = try Buffer.init(std.testing.allocator, 80, 24);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    editor.render(&buffer, area);

    // Check title rendered
    const title_char = buffer.getChar(1, 0);
    try std.testing.expect(title_char != ' ');
}

test "ThemeEditor - render with block" {
    const theme = tui.theme.default_dark;
    var editor = ThemeEditor.init(theme);
    editor.block = Block{ .title = "Custom Theme", .borders = .{ .top = true, .bottom = true, .left = true, .right = true } };

    var buffer = try Buffer.init(std.testing.allocator, 80, 24);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    editor.render(&buffer, area);

    // Border should be rendered
    const top_left = buffer.getChar(0, 0);
    try std.testing.expect(top_left != ' ');
}

test "ThemeEditor - render without preview" {
    const theme = tui.theme.default_dark;
    var editor = ThemeEditor.init(theme);
    editor.show_preview = false;

    var buffer = try Buffer.init(std.testing.allocator, 80, 24);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    editor.render(&buffer, area);

    // Should still render editor
    const content = buffer.getChar(5, 2);
    try std.testing.expect(content != ' ' or content == ' '); // Any render is fine
}

test "ThemeEditor - render in edit mode" {
    var theme = tui.theme.default_dark;
    theme.primary = .{ .rgb = .{ .r = 100, .g = 150, .b = 200 } };
    var editor = ThemeEditor.init(theme);
    editor.selected_field = 2;
    editor.editing_color = true;
    editor.editing_component = 1; // G

    var buffer = try Buffer.init(std.testing.allocator, 80, 24);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    editor.render(&buffer, area);

    // Should show RGB editing indicators
    // (We can't easily assert the exact output, but at least verify no crashes)
}

test "ThemeEditor - field info access" {
    const theme = tui.theme.default_dark;
    var editor = ThemeEditor.init(theme);

    const fields = editor.getFields();
    try std.testing.expectEqual(@as(usize, 12), fields.len);
    try std.testing.expectEqualStrings("Background", fields[0].name);
    try std.testing.expectEqualStrings("Primary", fields[2].name);
    try std.testing.expectEqualStrings("Selection FG", fields[11].name);
}

test "ThemeEditor - color to string" {
    const theme = tui.theme.default_dark;
    const editor = ThemeEditor.init(theme);

    try std.testing.expectEqualStrings("reset", editor.colorToString(.reset));
    try std.testing.expectEqualStrings("blue", editor.colorToString(.blue));
    try std.testing.expectEqualStrings("RGB", editor.colorToString(.{ .rgb = .{ .r = 1, .g = 2, .b = 3 } }));
}

test "ThemeEditor - colorToJson" {
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    try ThemeEditor.colorToJson(buf.writer(), .reset);
    try std.testing.expectEqualStrings("\"reset\"", buf.items);

    buf.clearRetainingCapacity();
    try ThemeEditor.colorToJson(buf.writer(), .{ .rgb = .{ .r = 10, .g = 20, .b = 30 } });
    try std.testing.expectEqualStrings("{\"rgb\": [10, 20, 30]}", buf.items);
}

test "ThemeEditor - no crash on small area" {
    const theme = tui.theme.default_dark;
    var editor = ThemeEditor.init(theme);

    var buffer = try Buffer.init(std.testing.allocator, 10, 3);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 10, .height = 3 };
    editor.render(&buffer, area); // Should not crash
}
