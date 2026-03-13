const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = @import("../buffer.zig").Buffer;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Span = @import("../style.zig").Span;
const Line = @import("../style.zig").Line;
const Block = @import("block.zig").Block;

/// Rich text input widget with inline formatting, emoji picker, and markdown preview
///
/// Features:
/// - Inline text formatting (bold, italic, underline, strikethrough)
/// - Emoji picker with search and categories
/// - Live markdown preview rendering
/// - Format toolbar with keybindings (Ctrl+B, Ctrl+I, Ctrl+U)
/// - Selection-based formatting
///
/// Example:
/// ```zig
/// var rich = RichTextInput.init(allocator);
/// defer rich.deinit();
///
/// try rich.setText("Hello **world**!");
/// rich.toggleEmojiPicker(); // Show emoji picker
/// rich.insertEmoji("👋"); // Insert emoji at cursor
/// rich.togglePreview(); // Show markdown preview
///
/// rich.render(buffer, area);
/// ```
pub const RichTextInput = struct {
    allocator: Allocator,
    /// Raw text content (with markdown syntax)
    text: ArrayList(u8),
    /// Cursor position in text
    cursor: usize,
    /// Selection range (start, end)
    selection: ?Selection,
    /// Show emoji picker
    emoji_picker_visible: bool,
    /// Selected emoji category
    emoji_category: EmojiCategory,
    /// Selected emoji index within category
    emoji_index: usize,
    /// Show markdown preview
    preview_visible: bool,
    /// Optional block border
    block: ?Block,
    /// Normal text style
    normal_style: Style,
    /// Cursor style
    cursor_style: Style,
    /// Selection style
    selection_style: Style,
    /// Format toolbar style
    toolbar_style: Style,

    const Selection = struct {
        start: usize,
        end: usize,

        pub fn normalized(self: Selection) Selection {
            return if (self.start <= self.end)
                self
            else
                .{ .start = self.end, .end = self.start };
        }

        pub fn isEmpty(self: Selection) bool {
            return self.start == self.end;
        }
    };

    pub const EmojiCategory = enum {
        smileys, // 😀😃😄😁😆
        gestures, // 👍👎👏🙌🤝
        hearts, // ❤️💛💚💙💜
        animals, // 🐶🐱🐭🐹🐰
        food, // 🍎🍊🍋🍌🍉
        travel, // ✈️🚗🚕🚙🚌
        objects, // 💡🔦🔌💻📱
        symbols, // ⭐✨💫⚡🔥

        pub fn getEmojis(self: EmojiCategory) []const []const u8 {
            return switch (self) {
                .smileys => &.{ "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇" },
                .gestures => &.{ "👍", "👎", "👏", "🙌", "🤝", "✊", "👊", "🤛", "🤜", "👌" },
                .hearts => &.{ "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔" },
                .animals => &.{ "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯" },
                .food => &.{ "🍎", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈", "🍒" },
                .travel => &.{ "✈️", "🚗", "🚕", "🚙", "🚌", "🚎", "🏎️", "🚓", "🚑", "🚒" },
                .objects => &.{ "💡", "🔦", "🔌", "💻", "📱", "⌚", "📷", "📹", "🎥", "📞" },
                .symbols => &.{ "⭐", "✨", "💫", "⚡", "🔥", "💧", "🌈", "☀️", "🌙", "⭐" },
            };
        }

        pub fn name(self: EmojiCategory) []const u8 {
            return switch (self) {
                .smileys => "Smileys",
                .gestures => "Gestures",
                .hearts => "Hearts",
                .animals => "Animals",
                .food => "Food",
                .travel => "Travel",
                .objects => "Objects",
                .symbols => "Symbols",
            };
        }

        pub fn next(self: EmojiCategory) EmojiCategory {
            return switch (self) {
                .smileys => .gestures,
                .gestures => .hearts,
                .hearts => .animals,
                .animals => .food,
                .food => .travel,
                .travel => .objects,
                .objects => .symbols,
                .symbols => .smileys,
            };
        }

        pub fn prev(self: EmojiCategory) EmojiCategory {
            return switch (self) {
                .smileys => .symbols,
                .gestures => .smileys,
                .hearts => .gestures,
                .animals => .hearts,
                .food => .animals,
                .travel => .food,
                .objects => .travel,
                .symbols => .objects,
            };
        }
    };

    pub fn init(allocator: Allocator) RichTextInput {
        return .{
            .allocator = allocator,
            .text = ArrayList(u8).init(allocator),
            .cursor = 0,
            .selection = null,
            .emoji_picker_visible = false,
            .emoji_category = .smileys,
            .emoji_index = 0,
            .preview_visible = false,
            .block = null,
            .normal_style = Style{},
            .cursor_style = Style{ .bg = Color.white, .fg = Color.black },
            .selection_style = Style{ .bg = Color{ .indexed = 237 } },
            .toolbar_style = Style{ .fg = Color{ .indexed = 8 } },
        };
    }

    pub fn deinit(self: *RichTextInput) void {
        self.text.deinit();
    }

    pub fn setText(self: *RichTextInput, text: []const u8) !void {
        self.text.clearRetainingCapacity();
        try self.text.appendSlice(text);
        self.cursor = 0;
        self.selection = null;
    }

    pub fn getText(self: *const RichTextInput, allocator: Allocator) ![]const u8 {
        return allocator.dupe(u8, self.text.items);
    }

    pub fn setBlock(self: *RichTextInput, block: Block) *RichTextInput {
        self.block = block;
        return self;
    }

    pub fn insertChar(self: *RichTextInput, ch: u8) !void {
        try self.text.insert(self.cursor, ch);
        self.cursor += 1;
    }

    pub fn deleteChar(self: *RichTextInput) void {
        if (self.cursor == 0 or self.text.items.len == 0) return;
        _ = self.text.orderedRemove(self.cursor - 1);
        self.cursor -= 1;
    }

    pub fn insertText(self: *RichTextInput, text: []const u8) !void {
        try self.text.insertSlice(self.cursor, text);
        self.cursor += text.len;
    }

    pub fn insertEmoji(self: *RichTextInput, emoji: []const u8) !void {
        try self.insertText(emoji);
    }

    pub fn toggleEmojiPicker(self: *RichTextInput) void {
        self.emoji_picker_visible = !self.emoji_picker_visible;
    }

    pub fn togglePreview(self: *RichTextInput) void {
        self.preview_visible = !self.preview_visible;
    }

    pub fn emojiCategoryNext(self: *RichTextInput) void {
        self.emoji_category = self.emoji_category.next();
        self.emoji_index = 0;
    }

    pub fn emojiCategoryPrev(self: *RichTextInput) void {
        self.emoji_category = self.emoji_category.prev();
        self.emoji_index = 0;
    }

    pub fn emojiSelectNext(self: *RichTextInput) void {
        const emojis = self.emoji_category.getEmojis();
        if (self.emoji_index + 1 < emojis.len) {
            self.emoji_index += 1;
        }
    }

    pub fn emojiSelectPrev(self: *RichTextInput) void {
        if (self.emoji_index > 0) {
            self.emoji_index -= 1;
        }
    }

    pub fn getSelectedEmoji(self: *const RichTextInput) ?[]const u8 {
        const emojis = self.emoji_category.getEmojis();
        if (self.emoji_index < emojis.len) {
            return emojis[self.emoji_index];
        }
        return null;
    }

    /// Apply markdown formatting around selection
    pub fn applyBold(self: *RichTextInput) !void {
        try self.wrapSelection("**", "**");
    }

    pub fn applyItalic(self: *RichTextInput) !void {
        try self.wrapSelection("*", "*");
    }

    pub fn applyUnderline(self: *RichTextInput) !void {
        try self.wrapSelection("<u>", "</u>");
    }

    pub fn applyStrikethrough(self: *RichTextInput) !void {
        try self.wrapSelection("~~", "~~");
    }

    fn wrapSelection(self: *RichTextInput, prefix: []const u8, suffix: []const u8) !void {
        if (self.selection) |sel| {
            const norm = sel.normalized();
            // Insert suffix first (to not shift positions)
            try self.text.insertSlice(norm.end, suffix);
            // Then insert prefix
            try self.text.insertSlice(norm.start, prefix);
            // Update cursor position
            self.cursor = norm.end + prefix.len + suffix.len;
            self.selection = null;
        } else {
            // No selection: insert markers at cursor
            try self.text.insertSlice(self.cursor, prefix);
            try self.text.insertSlice(self.cursor + prefix.len, suffix);
            self.cursor += prefix.len;
        }
    }

    pub fn setSelection(self: *RichTextInput, start: usize, end: usize) void {
        self.selection = Selection{
            .start = @min(start, self.text.items.len),
            .end = @min(end, self.text.items.len),
        };
    }

    pub fn clearSelection(self: *RichTextInput) void {
        self.selection = null;
    }

    pub fn moveCursor(self: *RichTextInput, delta: i32) void {
        if (delta < 0) {
            self.cursor = self.cursor -| @as(usize, @intCast(-delta));
        } else {
            self.cursor = @min(self.cursor + @as(usize, @intCast(delta)), self.text.items.len);
        }
    }

    pub fn render(self: *const RichTextInput, buf: *Buffer, area: Rect) void {
        var render_area = area;

        // Render block border if present
        if (self.block) |blk| {
            blk.render(buf, area);
            render_area = blk.inner(area);
        }

        if (render_area.width < 2 or render_area.height < 1) return;

        if (self.preview_visible) {
            // Split area: 50% input, 50% preview
            const input_height = render_area.height / 2;
            const preview_height = render_area.height - input_height;

            const input_area = Rect{
                .x = render_area.x,
                .y = render_area.y,
                .width = render_area.width,
                .height = input_height,
            };

            const preview_area = Rect{
                .x = render_area.x,
                .y = render_area.y + input_height,
                .width = render_area.width,
                .height = preview_height,
            };

            self.renderInput(buf, input_area);
            self.renderPreview(buf, preview_area);
        } else if (self.emoji_picker_visible) {
            // Split area: 70% input, 30% emoji picker
            const input_height = (render_area.height * 7) / 10;
            const picker_height = render_area.height - input_height;

            const input_area = Rect{
                .x = render_area.x,
                .y = render_area.y,
                .width = render_area.width,
                .height = input_height,
            };

            const picker_area = Rect{
                .x = render_area.x,
                .y = render_area.y + input_height,
                .width = render_area.width,
                .height = picker_height,
            };

            self.renderInput(buf, input_area);
            self.renderEmojiPicker(buf, picker_area);
        } else {
            self.renderInput(buf, render_area);
        }
    }

    fn renderInput(self: *const RichTextInput, buf: *Buffer, area: Rect) void {
        if (area.height < 2) return;

        // Render toolbar (Ctrl+B Bold, Ctrl+I Italic, ...)
        const toolbar_text = " Ctrl+B:Bold Ctrl+I:Italic Ctrl+U:Underline Ctrl+~:Strike ";
        var x: u16 = area.x;
        for (toolbar_text) |ch| {
            if (x >= area.x + area.width) break;
            buf.setChar(x, area.y, ch, self.toolbar_style);
            x += 1;
        }

        // Render text input
        const text_y = area.y + 1;
        x = area.x;

        for (self.text.items, 0..) |ch, i| {
            if (x >= area.x + area.width or text_y >= area.y + area.height) break;

            var style = self.normal_style;

            // Apply selection style
            if (self.selection) |sel| {
                const norm = sel.normalized();
                if (i >= norm.start and i < norm.end) {
                    style.bg = self.selection_style.bg;
                }
            }

            // Apply cursor style
            if (i == self.cursor) {
                style.bg = self.cursor_style.bg;
                style.fg = self.cursor_style.fg;
            }

            buf.setChar(x, text_y, ch, style);
            x += 1;
        }

        // Render cursor at end if applicable
        if (self.cursor == self.text.items.len and x < area.x + area.width) {
            buf.setChar(x, text_y, ' ', self.cursor_style);
        }
    }

    fn renderEmojiPicker(self: *const RichTextInput, buf: *Buffer, area: Rect) void {
        if (area.height < 1) return;

        // Render category name
        const category_name = self.emoji_category.name();
        var x: u16 = area.x;
        const category_style = Style{ .fg = Color.yellow, .bold = true };
        for (category_name) |ch| {
            if (x >= area.x + area.width) break;
            buf.setChar(x, area.y, ch, category_style);
            x += 1;
        }

        // Render emoji list
        const emojis = self.emoji_category.getEmojis();
        var y: u16 = area.y + 1;
        for (emojis, 0..) |emoji, i| {
            if (y >= area.y + area.height) break;

            x = area.x;
            const is_selected = i == self.emoji_index;
            const style = if (is_selected)
                Style{ .fg = Color.black, .bg = Color.white }
            else
                Style{};

            // Render selection indicator
            if (is_selected) {
                buf.setChar(x, y, '>', style);
                x += 1;
            } else {
                buf.setChar(x, y, ' ', style);
                x += 1;
            }

            // Render emoji
            for (emoji) |byte| {
                if (x >= area.x + area.width) break;
                buf.setChar(x, y, byte, style);
                x += 1;
            }

            y += 1;
        }
    }

    fn renderPreview(self: *const RichTextInput, buf: *Buffer, area: Rect) void {
        if (area.height < 1) return;

        // Simple markdown preview: render formatted text
        const preview_label = "Preview:";
        var x: u16 = area.x;
        const label_style = Style{ .fg = Color.cyan, .bold = true };
        for (preview_label) |ch| {
            if (x >= area.x + area.width) break;
            buf.setChar(x, area.y, ch, label_style);
            x += 1;
        }

        // Render formatted text (simplified markdown rendering)
        var y: u16 = area.y + 1;
        x = area.x;

        var i: usize = 0;
        while (i < self.text.items.len) {
            if (y >= area.y + area.height) break;

            // Check for **bold**
            if (i + 4 < self.text.items.len and
                self.text.items[i] == '*' and self.text.items[i + 1] == '*')
            {
                i += 2; // Skip **
                const bold_style = Style{ .bold = true };
                while (i < self.text.items.len) {
                    if (i + 1 < self.text.items.len and
                        self.text.items[i] == '*' and self.text.items[i + 1] == '*')
                    {
                        i += 2; // Skip closing **
                        break;
                    }
                    if (x >= area.x + area.width) {
                        x = area.x;
                        y += 1;
                        if (y >= area.y + area.height) break;
                    }
                    buf.setChar(x, y, self.text.items[i], bold_style);
                    x += 1;
                    i += 1;
                }
                continue;
            }

            // Check for *italic*
            if (i + 2 < self.text.items.len and self.text.items[i] == '*') {
                i += 1; // Skip *
                const italic_style = Style{ .italic = true };
                while (i < self.text.items.len) {
                    if (self.text.items[i] == '*') {
                        i += 1; // Skip closing *
                        break;
                    }
                    if (x >= area.x + area.width) {
                        x = area.x;
                        y += 1;
                        if (y >= area.y + area.height) break;
                    }
                    buf.setChar(x, y, self.text.items[i], italic_style);
                    x += 1;
                    i += 1;
                }
                continue;
            }

            // Regular character
            if (x >= area.x + area.width) {
                x = area.x;
                y += 1;
                if (y >= area.y + area.height) break;
            }
            buf.setChar(x, y, self.text.items[i], Style{});
            x += 1;
            i += 1;
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "richtext: init and deinit" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try testing.expectEqual(@as(usize, 0), rt.text.items.len);
    try testing.expectEqual(@as(usize, 0), rt.cursor);
}

test "richtext: setText and getText" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello world");
    try testing.expectEqualStrings("Hello world", rt.text.items);

    const text = try rt.getText(allocator);
    defer allocator.free(text);
    try testing.expectEqualStrings("Hello world", text);
}

test "richtext: insertChar" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try rt.setText("hello");
    rt.cursor = 5;
    try rt.insertChar('!');

    try testing.expectEqualStrings("hello!", rt.text.items);
    try testing.expectEqual(@as(usize, 6), rt.cursor);
}

test "richtext: deleteChar" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try rt.setText("hello!");
    rt.cursor = 6;
    rt.deleteChar();

    try testing.expectEqualStrings("hello", rt.text.items);
    try testing.expectEqual(@as(usize, 5), rt.cursor);
}

test "richtext: insertText" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try rt.setText("hello");
    rt.cursor = 5;
    try rt.insertText(" world");

    try testing.expectEqualStrings("hello world", rt.text.items);
    try testing.expectEqual(@as(usize, 11), rt.cursor);
}

test "richtext: insertEmoji" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello ");
    rt.cursor = 6;
    try rt.insertEmoji("👋");

    try testing.expect(std.mem.startsWith(u8, rt.text.items, "Hello "));
}

test "richtext: toggleEmojiPicker" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try testing.expect(!rt.emoji_picker_visible);
    rt.toggleEmojiPicker();
    try testing.expect(rt.emoji_picker_visible);
}

test "richtext: togglePreview" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try testing.expect(!rt.preview_visible);
    rt.togglePreview();
    try testing.expect(rt.preview_visible);
}

test "richtext: emoji category navigation" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try testing.expectEqual(RichTextInput.EmojiCategory.smileys, rt.emoji_category);

    rt.emojiCategoryNext();
    try testing.expectEqual(RichTextInput.EmojiCategory.gestures, rt.emoji_category);

    rt.emojiCategoryPrev();
    try testing.expectEqual(RichTextInput.EmojiCategory.smileys, rt.emoji_category);
}

test "richtext: emoji selection" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try testing.expectEqual(@as(usize, 0), rt.emoji_index);

    rt.emojiSelectNext();
    try testing.expectEqual(@as(usize, 1), rt.emoji_index);

    rt.emojiSelectPrev();
    try testing.expectEqual(@as(usize, 0), rt.emoji_index);
}

test "richtext: getSelectedEmoji" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    const emoji = rt.getSelectedEmoji();
    try testing.expect(emoji != null);
    try testing.expectEqualStrings("😀", emoji.?);
}

test "richtext: applyBold" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try rt.setText("hello");
    rt.setSelection(0, 5);
    try rt.applyBold();

    try testing.expectEqualStrings("**hello**", rt.text.items);
}

test "richtext: applyItalic" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try rt.setText("world");
    rt.setSelection(0, 5);
    try rt.applyItalic();

    try testing.expectEqualStrings("*world*", rt.text.items);
}

test "richtext: applyStrikethrough" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try rt.setText("text");
    rt.setSelection(0, 4);
    try rt.applyStrikethrough();

    try testing.expectEqualStrings("~~text~~", rt.text.items);
}

test "richtext: applyBold without selection" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try rt.setText("hello");
    rt.cursor = 5;
    try rt.applyBold();

    try testing.expectEqualStrings("hello****", rt.text.items);
    try testing.expectEqual(@as(usize, 7), rt.cursor); // Between **|**
}

test "richtext: setSelection and clearSelection" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try rt.setText("hello world");

    rt.setSelection(0, 5);
    try testing.expect(rt.selection != null);
    try testing.expectEqual(@as(usize, 0), rt.selection.?.start);
    try testing.expectEqual(@as(usize, 5), rt.selection.?.end);

    rt.clearSelection();
    try testing.expect(rt.selection == null);
}

test "richtext: moveCursor forward" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try rt.setText("hello");
    rt.cursor = 0;

    rt.moveCursor(3);
    try testing.expectEqual(@as(usize, 3), rt.cursor);
}

test "richtext: moveCursor backward" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try rt.setText("hello");
    rt.cursor = 5;

    rt.moveCursor(-2);
    try testing.expectEqual(@as(usize, 3), rt.cursor);
}

test "richtext: moveCursor boundary" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try rt.setText("hello");
    rt.cursor = 0;

    rt.moveCursor(-10); // Should clamp to 0
    try testing.expectEqual(@as(usize, 0), rt.cursor);

    rt.moveCursor(100); // Should clamp to text.len
    try testing.expectEqual(@as(usize, 5), rt.cursor);
}

test "richtext: render basic" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    try rt.setText("Hello");

    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    rt.render(&buffer, area);

    // Toolbar should be rendered on first line
    const toolbar_char = buffer.getChar(0, 0);
    try testing.expectEqual(@as(u21, ' '), toolbar_char);
}

test "richtext: emoji category getEmojis" {
    const smileys = RichTextInput.EmojiCategory.smileys.getEmojis();
    try testing.expect(smileys.len > 0);
    try testing.expectEqualStrings("😀", smileys[0]);
}

test "richtext: emoji category name" {
    try testing.expectEqualStrings("Smileys", RichTextInput.EmojiCategory.smileys.name());
    try testing.expectEqualStrings("Hearts", RichTextInput.EmojiCategory.hearts.name());
}

test "richtext: selection normalized" {
    const sel = RichTextInput.Selection{ .start = 5, .end = 2 };
    const norm = sel.normalized();
    try testing.expectEqual(@as(usize, 2), norm.start);
    try testing.expectEqual(@as(usize, 5), norm.end);
}

test "richtext: selection isEmpty" {
    const empty = RichTextInput.Selection{ .start = 3, .end = 3 };
    const not_empty = RichTextInput.Selection{ .start = 3, .end = 5 };

    try testing.expect(empty.isEmpty());
    try testing.expect(!not_empty.isEmpty());
}

test "richtext: builder pattern" {
    const allocator = testing.allocator;
    var rt = RichTextInput.init(allocator);
    defer rt.deinit();

    const block = Block.init().setTitle("Rich Text");
    _ = rt.setBlock(block);

    try testing.expect(rt.block != null);
}
