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

        /// Returns the selection with start <= end guaranteed.
        /// Swaps start and end if they are reversed.
        pub fn normalized(self: Selection) Selection {
            return if (self.start <= self.end)
                self
            else
                .{ .start = self.end, .end = self.start };
        }

        /// Returns true if the selection has zero length (no characters selected).
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

        /// Returns the emoji list for this category (10 emojis).
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

        /// Returns the display name of this category.
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

        /// Returns the next category in order (wraps around).
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

        /// Returns the previous category in order (wraps around).
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

    /// Initializes a new RichTextInput widget with default settings.
    /// Call deinit() when done to free resources.
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

    /// Frees resources used by this widget.
    pub fn deinit(self: *RichTextInput) void {
        self.text.deinit();
    }

    /// Replaces the entire text content and resets cursor/selection.
    pub fn setText(self: *RichTextInput, text: []const u8) !void {
        self.text.clearRetainingCapacity();
        try self.text.appendSlice(text);
        self.cursor = 0;
        self.selection = null;
    }

    /// Returns a copy of the current text content.
    /// Caller owns the returned memory.
    pub fn getText(self: *const RichTextInput, allocator: Allocator) ![]const u8 {
        return allocator.dupe(u8, self.text.items);
    }

    /// Sets the border block for this widget.
    /// Returns self for method chaining.
    pub fn setBlock(self: *RichTextInput, block: Block) *RichTextInput {
        self.block = block;
        return self;
    }

    /// Inserts a single character at the cursor position and advances cursor.
    pub fn insertChar(self: *RichTextInput, ch: u8) !void {
        try self.text.insert(self.cursor, ch);
        self.cursor += 1;
    }

    /// Deletes the character before the cursor (backspace).
    pub fn deleteChar(self: *RichTextInput) void {
        if (self.cursor == 0 or self.text.items.len == 0) return;
        _ = self.text.orderedRemove(self.cursor - 1);
        self.cursor -= 1;
    }

    /// Inserts a string at the cursor position and advances cursor.
    pub fn insertText(self: *RichTextInput, text: []const u8) !void {
        try self.text.insertSlice(self.cursor, text);
        self.cursor += text.len;
    }

    /// Inserts an emoji string at the cursor position.
    pub fn insertEmoji(self: *RichTextInput, emoji: []const u8) !void {
        try self.insertText(emoji);
    }

    /// Toggles the visibility of the emoji picker overlay.
    pub fn toggleEmojiPicker(self: *RichTextInput) void {
        self.emoji_picker_visible = !self.emoji_picker_visible;
    }

    /// Toggles the visibility of the markdown preview pane.
    pub fn togglePreview(self: *RichTextInput) void {
        self.preview_visible = !self.preview_visible;
    }

    /// Moves to the next emoji category and resets selection index.
    pub fn emojiCategoryNext(self: *RichTextInput) void {
        self.emoji_category = self.emoji_category.next();
        self.emoji_index = 0;
    }

    /// Moves to the previous emoji category and resets selection index.
    pub fn emojiCategoryPrev(self: *RichTextInput) void {
        self.emoji_category = self.emoji_category.prev();
        self.emoji_index = 0;
    }

    /// Selects the next emoji in the current category (if not at end).
    pub fn emojiSelectNext(self: *RichTextInput) void {
        const emojis = self.emoji_category.getEmojis();
        if (self.emoji_index + 1 < emojis.len) {
            self.emoji_index += 1;
        }
    }

    /// Selects the previous emoji in the current category (if not at start).
    pub fn emojiSelectPrev(self: *RichTextInput) void {
        if (self.emoji_index > 0) {
            self.emoji_index -= 1;
        }
    }

    /// Returns the currently selected emoji, or null if invalid index.
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

    /// Applies italic markdown formatting (*text*) around selection or cursor.
    pub fn applyItalic(self: *RichTextInput) !void {
        try self.wrapSelection("*", "*");
    }

    /// Applies underline HTML tags (<u>text</u>) around selection or cursor.
    pub fn applyUnderline(self: *RichTextInput) !void {
        try self.wrapSelection("<u>", "</u>");
    }

    /// Applies strikethrough markdown formatting (~~text~~) around selection or cursor.
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

    /// Sets the selection range (clamped to text bounds).
    pub fn setSelection(self: *RichTextInput, start: usize, end: usize) void {
        self.selection = Selection{
            .start = @min(start, self.text.items.len),
            .end = @min(end, self.text.items.len),
        };
    }

    /// Clears the current selection.
    pub fn clearSelection(self: *RichTextInput) void {
        self.selection = null;
    }

    /// Moves the cursor by the given delta (negative = left, positive = right).
    /// Clamps to text bounds.
    pub fn moveCursor(self: *RichTextInput, delta: i32) void {
        if (delta < 0) {
            self.cursor = self.cursor -| @as(usize, @intCast(-delta));
        } else {
            self.cursor = @min(self.cursor + @as(usize, @intCast(delta)), self.text.items.len);
        }
    }

    /// Renders the rich text input widget to the buffer.
    /// Shows input field, toolbar, and optionally emoji picker or markdown preview.
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

    const block = (Block{}).setTitle("Rich Text");
    _ = rt.setBlock(block);

    try testing.expect(rt.block != null);
}

// ============================================================================
// RichText Widget (Span-Based Formatting)
// ============================================================================

/// Rich text editor with span-based formatting
pub const RichText = struct {
    allocator: Allocator,
    text: ArrayList(u8),
    cursor: usize,
    selection: ?Selection,
    spans: ArrayList(FormatSpan),

    /// Formatting span - applies a style to a range of text
    pub const FormatSpan = struct {
        start: usize,
        length: usize,
        style: Style,
    };

    /// Selection range
    pub const Selection = struct {
        start: usize,
        end: usize,
    };

    /// Clipboard with formatted content
    pub const Clipboard = struct {
        text: []const u8,
        spans: []const FormatSpan,

        /// Frees the clipboard's text and span arrays.
        pub fn deinit(self: Clipboard, allocator: Allocator) void {
            allocator.free(self.text);
            allocator.free(self.spans);
        }
    };

    /// Initialize empty rich text
    pub fn init(allocator: Allocator) RichText {
        return .{
            .allocator = allocator,
            .text = ArrayList(u8){},
            .cursor = 0,
            .selection = null,
            .spans = ArrayList(FormatSpan){},
        };
    }

    /// Clean up
    pub fn deinit(self: *RichText) void {
        self.text.deinit(self.allocator);
        self.spans.deinit(self.allocator);
    }

    /// Set text content (clears existing text and formatting)
    pub fn setText(self: *RichText, text: []const u8) !void {
        self.text.clearRetainingCapacity();
        self.spans.clearRetainingCapacity();
        try self.text.appendSlice(self.allocator, text);
        self.cursor = 0;
        self.selection = null;
    }

    /// Get text content
    pub fn getText(self: *const RichText) []const u8 {
        return self.text.items;
    }

    /// Insert character at cursor position
    pub fn insertChar(self: *RichText, ch: u8) !void {
        const was_at_end = self.cursor >= self.text.items.len;
        try self.text.insert(self.allocator, self.cursor, ch);

        // Adjust spans after insertion
        for (self.spans.items) |*span| {
            if (span.start > self.cursor) {
                // Span starts after cursor - shift it
                span.start += 1;
            } else if (self.cursor > span.start and self.cursor < span.start + span.length) {
                // Cursor is strictly inside span - extend it
                span.length += 1;
            } else if (self.cursor == span.start + span.length and !was_at_end) {
                // Cursor is at end of span AND not at end of original text - extend it
                span.length += 1;
            } else if (span.start == self.cursor) {
                // Cursor is exactly at start of span - shift it
                span.start += 1;
            }
        }

        self.cursor += 1;
    }

    /// Insert text at cursor position
    pub fn insertText(self: *RichText, text: []const u8) !void {
        try self.text.insertSlice(self.allocator, self.cursor, text);

        // Adjust spans after insertion
        for (self.spans.items) |*span| {
            if (span.start > self.cursor) {
                // Span starts after cursor - shift it
                span.start += text.len;
            } else if (span.start + span.length > self.cursor) {
                // Cursor is inside span - extend it
                span.length += text.len;
            }
        }

        self.cursor += text.len;
    }

    /// Delete character at cursor position (backspace behavior)
    pub fn deleteChar(self: *RichText) void {
        if (self.cursor == 0 or self.text.items.len == 0) return;

        const pos = self.cursor - 1;
        _ = self.text.orderedRemove(pos);

        // Adjust spans after deletion
        var i: usize = 0;
        while (i < self.spans.items.len) {
            const span = &self.spans.items[i];

            if (span.start > pos) {
                // Span starts after deleted position - shift it
                span.start -= 1;
                i += 1;
            } else if (pos < span.start + span.length) {
                // Deleted position is inside span - shrink it
                span.length -= 1;
                if (span.length == 0) {
                    // Span is now empty - remove it
                    _ = self.spans.orderedRemove(i);
                } else {
                    i += 1;
                }
            } else {
                i += 1;
            }
        }

        self.cursor = pos;
    }

    /// Delete range of text
    pub fn deleteRange(self: *RichText, start: usize, end: usize) !void {
        if (start >= end or start >= self.text.items.len) return;

        const actual_end = @min(end, self.text.items.len);
        const len = actual_end - start;

        // Remove text
        for (0..len) |_| {
            _ = self.text.orderedRemove(start);
        }

        // Adjust spans
        var i: usize = 0;
        while (i < self.spans.items.len) {
            const span = &self.spans.items[i];

            if (span.start >= actual_end) {
                // Span starts after deleted range - shift it
                span.start -= len;
                i += 1;
            } else if (span.start >= start and span.start + span.length <= actual_end) {
                // Span is completely inside deleted range - remove it
                _ = self.spans.orderedRemove(i);
            } else if (span.start < start and span.start + span.length > actual_end) {
                // Span contains deleted range - shrink it
                span.length -= len;
                i += 1;
            } else if (span.start < start and span.start + span.length > start) {
                // Span overlaps start of deleted range
                const overlap = span.start + span.length - start;
                span.length -= @min(overlap, len);
                if (span.length == 0) {
                    _ = self.spans.orderedRemove(i);
                } else {
                    i += 1;
                }
            } else if (span.start >= start and span.start < actual_end) {
                // Span starts inside deleted range and extends beyond
                const new_start = start;
                const overlap = actual_end - span.start;
                span.length -= overlap;
                span.start = new_start;
                if (span.length == 0) {
                    _ = self.spans.orderedRemove(i);
                } else {
                    i += 1;
                }
            } else {
                i += 1;
            }
        }

        self.cursor = start;
    }

    /// Set cursor position
    pub fn setCursor(self: *RichText, pos: usize) void {
        self.cursor = @min(pos, self.text.items.len);
    }

    /// Get cursor position
    pub fn getCursor(self: *const RichText) usize {
        return self.cursor;
    }

    /// Move cursor by delta (can be negative)
    pub fn moveCursor(self: *RichText, delta: i32) void {
        if (delta < 0) {
            const abs_delta = @abs(delta);
            if (abs_delta > self.cursor) {
                self.cursor = 0;
            } else {
                self.cursor -= @intCast(abs_delta);
            }
        } else {
            self.cursor = @min(self.cursor + @as(usize, @intCast(delta)), self.text.items.len);
        }
    }

    /// Set selection range
    pub fn setSelection(self: *RichText, start: usize, end: usize) void {
        self.selection = .{ .start = start, .end = end };
    }

    /// Clear selection
    pub fn clearSelection(self: *RichText) void {
        self.selection = null;
    }

    /// Add formatting span
    pub fn addSpan(self: *RichText, start: usize, length: usize, style: Style) !void {
        if (start + length > self.text.items.len) return error.InvalidSpan;
        try self.spans.append(self.allocator, .{
            .start = start,
            .length = length,
            .style = style,
        });
    }

    /// Get all spans at a position
    pub fn getSpansAt(self: *const RichText, pos: usize, buf: []FormatSpan) usize {
        var count: usize = 0;
        for (self.spans.items) |span| {
            if (pos >= span.start and pos < span.start + span.length) {
                if (count < buf.len) {
                    buf[count] = span;
                    count += 1;
                }
            }
        }
        return count;
    }

    /// Clear formatting in range
    pub fn clearFormatting(self: *RichText) !void {
        if (self.selection) |sel| {
            // Clear formatting in selection
            var i: usize = 0;
            while (i < self.spans.items.len) {
                const span = &self.spans.items[i];

                if (span.start >= sel.end or span.start + span.length <= sel.start) {
                    // Span doesn't overlap selection - keep it
                    i += 1;
                } else if (span.start >= sel.start and span.start + span.length <= sel.end) {
                    // Span is completely inside selection - remove it
                    _ = self.spans.orderedRemove(i);
                } else if (span.start < sel.start and span.start + span.length > sel.end) {
                    // Selection is inside span - split it
                    const second_span = FormatSpan{
                        .start = sel.end,
                        .length = span.start + span.length - sel.end,
                        .style = span.style,
                    };
                    span.length = sel.start - span.start;
                    try self.spans.insert(self.allocator, i + 1, second_span);
                    i += 2;
                } else if (span.start < sel.start) {
                    // Span overlaps start of selection
                    span.length = sel.start - span.start;
                    i += 1;
                } else {
                    // Span overlaps end of selection
                    const overlap = sel.end - span.start;
                    span.start = sel.end;
                    span.length -= overlap;
                    i += 1;
                }
            }
        } else {
            // No selection - clear all formatting
            self.spans.clearRetainingCapacity();
        }
    }

    /// Merge adjacent spans with identical styles
    pub fn mergeSpans(self: *RichText) !void {
        if (self.spans.items.len < 2) return;

        // Sort spans by start position
        std.sort.pdq(FormatSpan, self.spans.items, {}, struct {
            fn lessThan(_: void, a: FormatSpan, b: FormatSpan) bool {
                return a.start < b.start;
            }
        }.lessThan);

        var i: usize = 0;
        while (i + 1 < self.spans.items.len) {
            const current = &self.spans.items[i];
            const next = self.spans.items[i + 1];

            // Check if adjacent and have same style
            if (current.start + current.length == next.start and
                std.meta.eql(current.style, next.style))
            {
                // Merge spans
                current.length += next.length;
                _ = self.spans.orderedRemove(i + 1);
            } else {
                i += 1;
            }
        }
    }

    /// Toggle bold formatting on selection
    pub fn toggleBold(self: *RichText) !void {
        const sel = self.selection orelse return;
        if (sel.start == sel.end) return; // Zero-length selection

        try self.toggleFormatting(sel, "bold");
    }

    /// Toggle italic formatting on selection
    pub fn toggleItalic(self: *RichText) !void {
        const sel = self.selection orelse return;
        if (sel.start == sel.end) return;

        try self.toggleFormatting(sel, "italic");
    }

    /// Toggle underline formatting on selection
    pub fn toggleUnderline(self: *RichText) !void {
        const sel = self.selection orelse return;
        if (sel.start == sel.end) return;

        try self.toggleFormatting(sel, "underline");
    }

    /// Toggle strikethrough formatting on selection
    pub fn toggleStrikethrough(self: *RichText) !void {
        const sel = self.selection orelse return;
        if (sel.start == sel.end) return;

        try self.toggleFormatting(sel, "strikethrough");
    }

    /// Set color formatting on selection
    pub fn setColor(self: *RichText, fg: ?Color, bg: ?Color) !void {
        const sel = self.selection orelse return;
        if (sel.start == sel.end) return;

        var style = Style{};
        if (fg) |c| style.fg = c;
        if (bg) |c| style.bg = c;

        try self.spans.append(self.allocator, .{
            .start = sel.start,
            .length = sel.end - sel.start,
            .style = style,
        });
    }

    /// Helper to toggle formatting attribute
    fn toggleFormatting(self: *RichText, sel: Selection, attr: []const u8) !void {
        // Check if selection already has this formatting
        var has_formatting = false;
        var i: usize = 0;
        while (i < self.spans.items.len) {
            const span = self.spans.items[i];
            if (span.start <= sel.start and span.start + span.length >= sel.end) {
                const has_attr = blk: {
                    if (std.mem.eql(u8, attr, "bold")) break :blk span.style.bold;
                    if (std.mem.eql(u8, attr, "italic")) break :blk span.style.italic;
                    if (std.mem.eql(u8, attr, "underline")) break :blk span.style.underline;
                    if (std.mem.eql(u8, attr, "strikethrough")) break :blk span.style.strikethrough;
                    break :blk false;
                };
                if (has_attr) {
                    has_formatting = true;
                    break;
                }
            }
            i += 1;
        }

        if (has_formatting) {
            // Remove formatting - split spans
            i = 0;
            while (i < self.spans.items.len) {
                const span = &self.spans.items[i];

                const has_attr = blk: {
                    if (std.mem.eql(u8, attr, "bold")) break :blk span.style.bold;
                    if (std.mem.eql(u8, attr, "italic")) break :blk span.style.italic;
                    if (std.mem.eql(u8, attr, "underline")) break :blk span.style.underline;
                    if (std.mem.eql(u8, attr, "strikethrough")) break :blk span.style.strikethrough;
                    break :blk false;
                };

                if (!has_attr) {
                    i += 1;
                    continue;
                }

                if (span.start >= sel.end or span.start + span.length <= sel.start) {
                    // No overlap
                    i += 1;
                } else if (span.start >= sel.start and span.start + span.length <= sel.end) {
                    // Completely inside selection - remove
                    _ = self.spans.orderedRemove(i);
                } else if (span.start < sel.start and span.start + span.length > sel.end) {
                    // Selection inside span - split into 3 parts
                    const left_len = sel.start - span.start;
                    const right_start = sel.end;
                    const right_len = span.start + span.length - sel.end;

                    // Keep left part
                    span.length = left_len;

                    // Add right part
                    try self.spans.insert(self.allocator, i + 1, .{
                        .start = right_start,
                        .length = right_len,
                        .style = span.style,
                    });
                    i += 2;
                } else if (span.start < sel.start) {
                    // Overlaps start
                    span.length = sel.start - span.start;
                    i += 1;
                } else {
                    // Overlaps end
                    const new_start = sel.end;
                    const new_len = span.start + span.length - sel.end;
                    span.start = new_start;
                    span.length = new_len;
                    i += 1;
                }
            }
        } else {
            // Add formatting
            var style = Style{};
            if (std.mem.eql(u8, attr, "bold")) style.bold = true;
            if (std.mem.eql(u8, attr, "italic")) style.italic = true;
            if (std.mem.eql(u8, attr, "underline")) style.underline = true;
            if (std.mem.eql(u8, attr, "strikethrough")) style.strikethrough = true;

            try self.spans.append(self.allocator, .{
                .start = sel.start,
                .length = sel.end - sel.start,
                .style = style,
            });
        }
    }

    /// Export to plain text (strip formatting)
    pub fn toPlainText(self: *const RichText, allocator: Allocator) ![]u8 {
        return try allocator.dupe(u8, self.text.items);
    }

    /// Export to markdown
    pub fn toMarkdown(self: *const RichText, allocator: Allocator) ![]u8 {
        var result = ArrayList(u8){};
        errdefer result.deinit(allocator);

        // Sort spans by start position
        const sorted_spans = try allocator.dupe(FormatSpan, self.spans.items);
        defer allocator.free(sorted_spans);

        std.sort.pdq(FormatSpan, sorted_spans, {}, struct {
            fn lessThan(_: void, a: FormatSpan, b: FormatSpan) bool {
                return a.start < b.start;
            }
        }.lessThan);

        var pos: usize = 0;
        var active_spans = ArrayList(FormatSpan){};
        defer active_spans.deinit(allocator);

        while (pos < self.text.items.len) {
            // Close spans that end here
            var i: usize = 0;
            while (i < active_spans.items.len) {
                if (active_spans.items[i].start + active_spans.items[i].length <= pos) {
                    const span = active_spans.orderedRemove(i);
                    if (span.style.bold and span.style.italic) {
                        try result.appendSlice(allocator, "***");
                    } else if (span.style.bold) {
                        try result.appendSlice(allocator, "**");
                    } else if (span.style.italic) {
                        try result.append(allocator, '*');
                    } else if (span.style.strikethrough) {
                        try result.appendSlice(allocator, "~~");
                    }
                } else {
                    i += 1;
                }
            }

            // Open new spans starting here
            for (sorted_spans) |span| {
                if (span.start == pos and !hasSpan(&active_spans, span)) {
                    // Skip color-only spans (markdown doesn't support colors)
                    if (span.style.fg == null and span.style.bg == null and
                        (span.style.bold or span.style.italic or span.style.strikethrough))
                    {
                        if (span.style.bold and span.style.italic) {
                            try result.appendSlice(allocator, "***");
                        } else if (span.style.bold) {
                            try result.appendSlice(allocator, "**");
                        } else if (span.style.italic) {
                            try result.append(allocator, '*');
                        } else if (span.style.strikethrough) {
                            try result.appendSlice(allocator, "~~");
                        }
                        try active_spans.append(allocator, span);
                    }
                }
            }

            // Append character
            try result.append(allocator, self.text.items[pos]);
            pos += 1;
        }

        // Close remaining spans
        for (active_spans.items) |span| {
            if (span.style.bold and span.style.italic) {
                try result.appendSlice(allocator, "***");
            } else if (span.style.bold) {
                try result.appendSlice(allocator, "**");
            } else if (span.style.italic) {
                try result.append(allocator, '*');
            } else if (span.style.strikethrough) {
                try result.appendSlice(allocator, "~~");
            }
        }

        return result.toOwnedSlice(allocator);
    }

    fn hasSpan(list: *ArrayList(FormatSpan), span: FormatSpan) bool {
        for (list.items) |s| {
            if (s.start == span.start and s.length == span.length and
                std.meta.eql(s.style, span.style))
            {
                return true;
            }
        }
        return false;
    }

    /// Copy formatted text from selection
    pub fn copyFormatted(self: *const RichText, allocator: Allocator) !Clipboard {
        const sel = self.selection orelse return Clipboard{
            .text = try allocator.dupe(u8, ""),
            .spans = try allocator.alloc(FormatSpan, 0),
        };

        const text = try allocator.dupe(u8, self.text.items[sel.start..sel.end]);
        errdefer allocator.free(text);

        // Collect spans that overlap with selection
        var spans_list = ArrayList(FormatSpan){};
        defer spans_list.deinit(allocator);

        for (self.spans.items) |span| {
            if (span.start >= sel.end or span.start + span.length <= sel.start) {
                continue; // No overlap
            }

            // Calculate overlapping range
            const overlap_start = @max(span.start, sel.start);
            const overlap_end = @min(span.start + span.length, sel.end);

            // Adjust to 0-based relative to copied text
            try spans_list.append(allocator, .{
                .start = overlap_start - sel.start,
                .length = overlap_end - overlap_start,
                .style = span.style,
            });
        }

        const spans = try spans_list.toOwnedSlice(allocator);

        return Clipboard{
            .text = text,
            .spans = spans,
        };
    }

    /// Paste formatted text at cursor
    pub fn pasteFormatted(self: *RichText, clipboard: Clipboard) !void {
        const insert_pos = self.cursor;

        // Insert text
        try self.text.insertSlice(self.allocator, insert_pos, clipboard.text);

        // Add clipboard spans first (at insertion position)
        for (clipboard.spans) |span| {
            try self.spans.insert(self.allocator, 0, .{
                .start = insert_pos + span.start,
                .length = span.length,
                .style = span.style,
            });
        }

        // Shift existing spans (skip newly inserted clipboard spans)
        const clipboard_span_count = clipboard.spans.len;
        for (self.spans.items[clipboard_span_count..]) |*span| {
            if (span.start >= insert_pos) {
                span.start += clipboard.text.len;
            }
        }

        self.cursor = insert_pos + clipboard.text.len;
    }

    /// Render rich text to buffer
    pub fn render(self: *const RichText, buf: *Buffer, area: Rect) void {
        var x: u16 = area.x;
        const y: u16 = area.y;

        for (self.text.items, 0..) |ch, i| {
            if (x >= area.x + area.width) break; // Truncate at width

            // Collect all spans at this position
            var merged_style = Style{};
            for (self.spans.items) |span| {
                if (i >= span.start and i < span.start + span.length) {
                    // Merge styles
                    if (span.style.bold) merged_style.bold = true;
                    if (span.style.italic) merged_style.italic = true;
                    if (span.style.underline) merged_style.underline = true;
                    if (span.style.strikethrough) merged_style.strikethrough = true;
                    if (span.style.fg) |c| merged_style.fg = c;
                    if (span.style.bg) |c| merged_style.bg = c;
                }
            }

            // Apply selection style
            if (self.selection) |sel| {
                if (i >= sel.start and i < sel.end) {
                    merged_style.bg = Color.blue;
                }
            }

            // Apply cursor style
            if (i == self.cursor) {
                merged_style.reverse = true;
            }

            buf.setChar(x, y, @intCast(ch), merged_style);
            x += 1;
        }

        // Render cursor if at end of text
        if (self.cursor == self.text.items.len and x < area.x + area.width) {
            buf.setChar(x, y, ' ', .{ .reverse = true });
        }
    }
};
