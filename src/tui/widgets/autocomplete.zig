const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Buffer = @import("../buffer.zig").Buffer;
const Cell = @import("../buffer.zig").Cell;
const Rect = @import("../layout.zig").Rect;
const Style = @import("../style.zig").Style;
const Color = @import("../style.zig").Color;
const Block = @import("block.zig").Block;

/// Autocomplete widget for displaying suggestion lists with fuzzy matching
///
/// Features:
/// - Fuzzy matching with score-based ranking
/// - Keyboard navigation (up/down, home/end, Tab, Ctrl+Space)
/// - Selected item highlighting
/// - Max visible items with scrolling
/// - Multi-column layout with optional metadata columns
/// - Documentation preview pane for selected item
/// - Custom provider callback for dynamic suggestions
/// - Optional block borders
///
/// Example (basic):
/// ```zig
/// var autocomplete = Autocomplete.init(allocator);
/// defer autocomplete.deinit();
///
/// try autocomplete.setInput("hel");
/// try autocomplete.setSuggestions(&.{ "hello", "help", "helmet" });
/// autocomplete.setMaxVisible(5);
/// autocomplete.selectNext(); // Navigate down
/// const selected = autocomplete.getSelected(); // Returns "hello"
///
/// autocomplete.render(buffer, area);
/// ```
///
/// Example (with documentation):
/// ```zig
/// var autocomplete = Autocomplete.init(allocator);
/// defer autocomplete.deinit();
///
/// try autocomplete.setSuggestionsWithDocs(&.{
///     .{ .text = "println", .doc = "Prints a line to stdout", .metadata = "macro" },
///     .{ .text = "printf", .doc = "Formatted print", .metadata = "fn" },
/// });
/// autocomplete.enableDocPreview(true);
/// autocomplete.setPreviewWidth(40); // 40 columns for preview pane
///
/// autocomplete.render(buffer, area); // Splits area: list | preview
/// ```
pub const Autocomplete = struct {
    allocator: Allocator,
    input: []const u8,
    suggestions: ArrayList(Suggestion),
    selected_index: usize,
    scroll_offset: usize,
    max_visible: usize,
    block: ?Block,
    highlight_style: Style,
    normal_style: Style,
    metadata_style: Style,
    doc_style: Style,
    provider: ?*const ProviderFn,
    show_doc_preview: bool,
    preview_width: u16,
    show_metadata_column: bool,
    metadata_column_width: u16,

    /// Suggestion item with optional metadata and documentation
    pub const Suggestion = struct {
        text: []const u8,
        score: f32 = 1.0,
        metadata: ?[]const u8 = null, // e.g., type annotation, file path
        doc: ?[]const u8 = null,      // documentation preview text
    };

    /// Simple suggestion item for basic use cases (backward compatible)
    pub const SuggestionItem = struct {
        text: []const u8,
        metadata: ?[]const u8 = null,
        doc: ?[]const u8 = null,
    };

    pub const ProviderFn = fn (input: []const u8, allocator: Allocator) anyerror![]const []const u8;

    /// Initializes an Autocomplete widget with default settings.
    /// The returned instance must be freed with `.deinit()`.
    /// Default configuration: 10 max visible items, black-on-white highlight style.
    pub fn init(allocator: Allocator) Autocomplete {
        return .{
            .allocator = allocator,
            .input = "",
            .suggestions = ArrayList(Suggestion).init(allocator),
            .selected_index = 0,
            .scroll_offset = 0,
            .max_visible = 10,
            .block = null,
            .highlight_style = Style{ .fg = Color{ .indexed = 0 }, .bg = Color{ .indexed = 7 } },
            .normal_style = Style{},
            .metadata_style = Style{ .fg = Color{ .indexed = 8 } }, // gray
            .doc_style = Style{ .fg = Color{ .indexed = 7 } },       // white
            .provider = null,
            .show_doc_preview = false,
            .preview_width = 40,
            .show_metadata_column = false,
            .metadata_column_width = 10,
        };
    }

    /// Frees resources associated with this autocomplete widget.
    /// Clears the internal suggestions list.
    pub fn deinit(self: *Autocomplete) void {
        self.suggestions.deinit();
    }

    /// Sets the optional border block around the autocomplete list.
    /// Returns `self` for method chaining.
    pub fn setBlock(self: *Autocomplete, block: Block) *Autocomplete {
        self.block = block;
        return self;
    }

    /// Sets the maximum number of visible suggestions in the list.
    /// If more suggestions exist, the list will scroll.
    /// Returns `self` for method chaining.
    pub fn setMaxVisible(self: *Autocomplete, max: usize) *Autocomplete {
        self.max_visible = max;
        return self;
    }

    /// Sets the style applied to the currently selected suggestion.
    /// Returns `self` for method chaining.
    pub fn setHighlightStyle(self: *Autocomplete, style: Style) *Autocomplete {
        self.highlight_style = style;
        return self;
    }

    /// Sets the style applied to non-selected suggestions.
    /// Returns `self` for method chaining.
    pub fn setNormalStyle(self: *Autocomplete, style: Style) *Autocomplete {
        self.normal_style = style;
        return self;
    }

    /// Sets the dynamic suggestion provider function.
    /// The provider is called automatically when input changes via `setInput()`.
    /// Returns `self` for method chaining.
    pub fn setProvider(self: *Autocomplete, provider: *const ProviderFn) *Autocomplete {
        self.provider = provider;
        return self;
    }

    /// Enable or disable documentation preview pane
    /// When enabled, splits the render area into list | preview
    /// Returns `self` for method chaining.
    pub fn enableDocPreview(self: *Autocomplete, enable: bool) *Autocomplete {
        self.show_doc_preview = enable;
        return self;
    }

    /// Set width of documentation preview pane (in columns)
    /// Returns `self` for method chaining.
    pub fn setPreviewWidth(self: *Autocomplete, width: u16) *Autocomplete {
        self.preview_width = width;
        return self;
    }

    /// Enable or disable metadata column (e.g., type annotations)
    /// Returns `self` for method chaining.
    pub fn enableMetadataColumn(self: *Autocomplete, enable: bool) *Autocomplete {
        self.show_metadata_column = enable;
        return self;
    }

    /// Set width of metadata column (in columns)
    /// Returns `self` for method chaining.
    pub fn setMetadataColumnWidth(self: *Autocomplete, width: u16) *Autocomplete {
        self.metadata_column_width = width;
        return self;
    }

    /// Set style for metadata column text
    /// Returns `self` for method chaining.
    pub fn setMetadataStyle(self: *Autocomplete, style: Style) *Autocomplete {
        self.metadata_style = style;
        return self;
    }

    /// Set style for documentation preview text
    /// Returns `self` for method chaining.
    pub fn setDocStyle(self: *Autocomplete, style: Style) *Autocomplete {
        self.doc_style = style;
        return self;
    }

    /// Set input text and trigger suggestion update
    pub fn setInput(self: *Autocomplete, input: []const u8) !void {
        self.input = input;
        try self.updateSuggestions();
    }

    /// Manually set suggestions (bypasses provider) - backward compatible
    pub fn setSuggestions(self: *Autocomplete, items: []const []const u8) !void {
        self.suggestions.clearRetainingCapacity();
        for (items) |item| {
            const score = fuzzyMatch(self.input, item);
            if (score > 0.0) {
                try self.suggestions.append(.{ .text = item, .score = score });
            }
        }
        // Sort by score descending
        std.mem.sort(Suggestion, self.suggestions.items, {}, suggestionLessThan);
        self.selected_index = if (self.suggestions.items.len > 0) 0 else 0;
        self.scroll_offset = 0;
    }

    /// Set suggestions with metadata and documentation
    pub fn setSuggestionsWithDocs(self: *Autocomplete, items: []const SuggestionItem) !void {
        self.suggestions.clearRetainingCapacity();
        for (items) |item| {
            const score = fuzzyMatch(self.input, item.text);
            if (score > 0.0) {
                try self.suggestions.append(.{
                    .text = item.text,
                    .score = score,
                    .metadata = item.metadata,
                    .doc = item.doc,
                });
            }
        }
        // Sort by score descending
        std.mem.sort(Suggestion, self.suggestions.items, {}, suggestionLessThan);
        self.selected_index = if (self.suggestions.items.len > 0) 0 else 0;
        self.scroll_offset = 0;
    }

    fn updateSuggestions(self: *Autocomplete) !void {
        if (self.provider) |provider| {
            const items = try provider(self.input, self.allocator);
            defer self.allocator.free(items);
            try self.setSuggestions(items);
        }
    }

    /// Moves selection down to the next suggestion.
    /// If at the end of the list, selection remains on the last item.
    /// Automatically adjusts scroll offset to keep selection visible.
    pub fn selectNext(self: *Autocomplete) void {
        if (self.suggestions.items.len == 0) return;
        if (self.selected_index + 1 < self.suggestions.items.len) {
            self.selected_index += 1;
            // Scroll down if selected item is below visible window
            if (self.selected_index >= self.scroll_offset + self.max_visible) {
                self.scroll_offset = self.selected_index - self.max_visible + 1;
            }
        }
    }

    /// Moves selection up to the previous suggestion.
    /// If at the beginning of the list, selection remains on the first item.
    /// Automatically adjusts scroll offset to keep selection visible.
    pub fn selectPrev(self: *Autocomplete) void {
        if (self.suggestions.items.len == 0) return;
        if (self.selected_index > 0) {
            self.selected_index -= 1;
            // Scroll up if selected item is above visible window
            if (self.selected_index < self.scroll_offset) {
                self.scroll_offset = self.selected_index;
            }
        }
    }

    /// Jumps selection to the first suggestion and resets scroll to the top.
    pub fn selectFirst(self: *Autocomplete) void {
        self.selected_index = 0;
        self.scroll_offset = 0;
    }

    /// Jumps selection to the last suggestion and adjusts scroll to make it visible.
    pub fn selectLast(self: *Autocomplete) void {
        if (self.suggestions.items.len == 0) return;
        self.selected_index = self.suggestions.items.len - 1;
        if (self.selected_index >= self.max_visible) {
            self.scroll_offset = self.selected_index - self.max_visible + 1;
        }
    }

    /// Returns the text of the currently selected suggestion, or `null` if no suggestions exist.
    pub fn getSelected(self: *const Autocomplete) ?[]const u8 {
        if (self.suggestions.items.len == 0) return null;
        if (self.selected_index >= self.suggestions.items.len) return null;
        return self.suggestions.items[self.selected_index].text;
    }

    /// Returns the total number of suggestions currently available.
    pub fn getSuggestionCount(self: *const Autocomplete) usize {
        return self.suggestions.items.len;
    }

    /// Renders the autocomplete suggestion list to the given buffer within the specified area.
    /// Displays suggestions with fuzzy match scoring, highlights the selected item,
    /// supports scrolling, multi-column layout, and documentation preview pane.
    pub fn render(self: *const Autocomplete, buf: *Buffer, area: Rect) void {
        const inner = if (self.block) |b| b.inner(area) else area;

        // Render block border if present
        if (self.block) |b| {
            b.render(buf, area);
        }

        if (self.suggestions.items.len == 0) {
            return; // No suggestions to render
        }

        // Split area if doc preview is enabled
        var list_area = inner;
        var preview_area: ?Rect = null;

        if (self.show_doc_preview and inner.width > self.preview_width + 2) {
            const list_width = inner.width - self.preview_width - 1; // -1 for separator
            list_area = Rect{
                .x = inner.x,
                .y = inner.y,
                .width = list_width,
                .height = inner.height,
            };
            preview_area = Rect{
                .x = inner.x + list_width + 1,
                .y = inner.y,
                .width = self.preview_width,
                .height = inner.height,
            };

            // Render separator between list and preview
            const sep_x = inner.x + list_width;
            var sep_y: u16 = inner.y;
            while (sep_y < inner.y + inner.height) : (sep_y += 1) {
                buf.set(sep_x, sep_y, .{ .char = '│', .style = self.normal_style });
            }
        }

        // Render suggestion list
        self.renderList(buf, list_area);

        // Render documentation preview if enabled
        if (preview_area) |parea| {
            self.renderDocPreview(buf, parea);
        }
    }

    fn renderList(self: *const Autocomplete, buf: *Buffer, area: Rect) void {
        const visible_count = @min(self.max_visible, self.suggestions.items.len);
        const end_index = @min(self.scroll_offset + visible_count, self.suggestions.items.len);

        var y: u16 = area.y;
        for (self.suggestions.items[self.scroll_offset..end_index], 0..) |suggestion, i| {
            if (y >= area.y + area.height) break;

            const is_selected = (self.scroll_offset + i) == self.selected_index;
            const style = if (is_selected) self.highlight_style else self.normal_style;

            var x: u16 = area.x;

            // Render suggestion text
            const text_width = if (self.show_metadata_column and suggestion.metadata != null)
                @min(suggestion.text.len, area.width -| self.metadata_column_width -| 1)
            else
                @min(suggestion.text.len, area.width);

            for (suggestion.text[0..text_width]) |c| {
                if (x >= area.x + area.width) break;
                buf.set(x, y, .{ .char = c, .style = style });
                x += 1;
            }

            // Render metadata column if enabled
            if (self.show_metadata_column and suggestion.metadata != null) {
                // Pad to metadata column start
                const meta_start = area.x + area.width - self.metadata_column_width;
                while (x < meta_start and x < area.x + area.width) : (x += 1) {
                    buf.set(x, y, .{ .char = ' ', .style = style });
                }

                // Render metadata
                const meta_style = if (is_selected)
                    Style{ .fg = self.metadata_style.fg, .bg = self.highlight_style.bg }
                else
                    self.metadata_style;

                for (suggestion.metadata.?) |c| {
                    if (x >= area.x + area.width) break;
                    buf.set(x, y, .{ .char = c, .style = meta_style });
                    x += 1;
                }
            }

            // Fill remaining width with background
            while (x < area.x + area.width) : (x += 1) {
                buf.set(x, y, .{ .char = ' ', .style = style });
            }

            y += 1;
        }
    }

    fn renderDocPreview(self: *const Autocomplete, buf: *Buffer, area: Rect) void {
        if (self.selected_index >= self.suggestions.items.len) return;

        const selected = self.suggestions.items[self.selected_index];
        if (selected.doc == null) return;

        const doc = selected.doc.?;

        // Render doc text with word wrapping
        var y: u16 = area.y;
        var char_idx: usize = 0;

        while (char_idx < doc.len and y < area.y + area.height) {
            var x: u16 = area.x;
            const line_start = char_idx;

            // Find line break or wrap point
            while (char_idx < doc.len and x < area.x + area.width) {
                const c = doc[char_idx];
                if (c == '\n') {
                    char_idx += 1;
                    break;
                }
                buf.set(x, y, .{ .char = c, .style = self.doc_style });
                x += 1;
                char_idx += 1;
            }

            // Fill rest of line
            while (x < area.x + area.width) : (x += 1) {
                buf.set(x, y, .{ .char = ' ', .style = self.doc_style });
            }

            y += 1;

            // Word wrap if needed
            if (char_idx < doc.len and doc[char_idx] != '\n' and char_idx > line_start) {
                // Backtrack to last space
                while (char_idx > line_start and doc[char_idx] != ' ') {
                    char_idx -= 1;
                }
                if (char_idx == line_start) {
                    // No space found, hard break
                    char_idx = line_start + (area.width);
                } else {
                    char_idx += 1; // Skip the space
                }
            }
        }
    }

    fn suggestionLessThan(_: void, a: Suggestion, b: Suggestion) bool {
        return a.score > b.score; // Descending order (higher score first)
    }

    /// Fuzzy matching algorithm with score calculation
    fn fuzzyMatch(input: []const u8, candidate: []const u8) f32 {
        if (input.len == 0) return 1.0; // Empty input matches everything

        var score: f32 = 0.0;
        var input_idx: usize = 0;
        var last_match_idx: usize = 0;

        for (candidate, 0..) |c, i| {
            if (input_idx >= input.len) break;

            const input_char = std.ascii.toLower(input[input_idx]);
            const candidate_char = std.ascii.toLower(c);

            if (input_char == candidate_char) {
                // Consecutive match bonus
                const consecutive_bonus: f32 = if (i == last_match_idx + 1) 0.2 else 0.0;
                // Start-of-word bonus
                const start_bonus: f32 = if (i == 0 or !std.ascii.isAlphanumeric(candidate[i - 1])) 0.1 else 0.0;
                score += 1.0 + consecutive_bonus + start_bonus;
                last_match_idx = i;
                input_idx += 1;
            }
        }

        // All input characters must match
        if (input_idx < input.len) return 0.0;

        // Normalize by candidate length (prefer shorter matches)
        const length_penalty = @as(f32, @floatFromInt(candidate.len)) / 100.0;
        return score - length_penalty;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "autocomplete: init and deinit" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try std.testing.expectEqual(@as(usize, 0), ac.selected_index);
    try std.testing.expectEqual(@as(usize, 0), ac.scroll_offset);
    try std.testing.expectEqual(@as(usize, 10), ac.max_visible);
}

test "autocomplete: set suggestions" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const suggestions = [_][]const u8{ "hello", "help", "helmet" };
    try ac.setSuggestions(&suggestions);

    try std.testing.expectEqual(@as(usize, 3), ac.getSuggestionCount());
}

test "autocomplete: fuzzy match scoring" {
    const score1 = Autocomplete.fuzzyMatch("hel", "hello");
    const score2 = Autocomplete.fuzzyMatch("hel", "helmet");
    const score3 = Autocomplete.fuzzyMatch("hel", "help");
    const score4 = Autocomplete.fuzzyMatch("xyz", "hello");

    try std.testing.expect(score1 > 0.0);
    try std.testing.expect(score2 > 0.0);
    try std.testing.expect(score3 > 0.0);
    try std.testing.expectEqual(@as(f32, 0.0), score4); // No match
}

test "autocomplete: fuzzy match prefers consecutive" {
    const consecutive = Autocomplete.fuzzyMatch("hel", "hello");
    const scattered = Autocomplete.fuzzyMatch("hel", "hxeyl");

    try std.testing.expect(consecutive > scattered);
}

test "autocomplete: fuzzy match case insensitive" {
    const lower = Autocomplete.fuzzyMatch("hel", "hello");
    const upper = Autocomplete.fuzzyMatch("hel", "HELLO");
    const mixed = Autocomplete.fuzzyMatch("HEL", "HeLLo");

    try std.testing.expect(lower > 0.0);
    try std.testing.expect(upper > 0.0);
    try std.testing.expect(mixed > 0.0);
}

test "autocomplete: select navigation" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const suggestions = [_][]const u8{ "a", "b", "c", "d", "e" };
    try ac.setSuggestions(&suggestions);

    try std.testing.expectEqual(@as(usize, 0), ac.selected_index);

    ac.selectNext();
    try std.testing.expectEqual(@as(usize, 1), ac.selected_index);

    ac.selectNext();
    try std.testing.expectEqual(@as(usize, 2), ac.selected_index);

    ac.selectPrev();
    try std.testing.expectEqual(@as(usize, 1), ac.selected_index);

    ac.selectFirst();
    try std.testing.expectEqual(@as(usize, 0), ac.selected_index);

    ac.selectLast();
    try std.testing.expectEqual(@as(usize, 4), ac.selected_index);
}

test "autocomplete: select navigation boundary" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const suggestions = [_][]const u8{ "a", "b", "c" };
    try ac.setSuggestions(&suggestions);

    ac.selectPrev(); // Should stay at 0
    try std.testing.expectEqual(@as(usize, 0), ac.selected_index);

    ac.selectLast();
    ac.selectNext(); // Should stay at last
    try std.testing.expectEqual(@as(usize, 2), ac.selected_index);
}

test "autocomplete: scroll offset" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();
    ac.setMaxVisible(3);

    const suggestions = [_][]const u8{ "a", "b", "c", "d", "e", "f" };
    try ac.setSuggestions(&suggestions);

    // Select beyond visible window
    ac.selectNext(); // idx=1
    ac.selectNext(); // idx=2
    ac.selectNext(); // idx=3, scroll_offset should be 1
    try std.testing.expectEqual(@as(usize, 3), ac.selected_index);
    try std.testing.expectEqual(@as(usize, 1), ac.scroll_offset);

    // Scroll back up
    ac.selectPrev(); // idx=2
    ac.selectPrev(); // idx=1
    ac.selectPrev(); // idx=0, scroll_offset should be 0
    try std.testing.expectEqual(@as(usize, 0), ac.selected_index);
    try std.testing.expectEqual(@as(usize, 0), ac.scroll_offset);
}

test "autocomplete: get selected" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const suggestions = [_][]const u8{ "hello", "world" };
    try ac.setSuggestions(&suggestions);

    const selected1 = ac.getSelected();
    try std.testing.expect(selected1 != null);
    try std.testing.expectEqualStrings("hello", selected1.?);

    ac.selectNext();
    const selected2 = ac.getSelected();
    try std.testing.expect(selected2 != null);
    try std.testing.expectEqualStrings("world", selected2.?);
}

test "autocomplete: get selected on empty" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const selected = ac.getSelected();
    try std.testing.expectEqual(@as(?[]const u8, null), selected);
}

test "autocomplete: set input filters suggestions" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    // Manually set without provider
    const all_suggestions = [_][]const u8{ "hello", "world", "help", "helmet" };
    try ac.setSuggestions(&all_suggestions);
    try std.testing.expectEqual(@as(usize, 4), ac.getSuggestionCount());

    // Set input to filter
    ac.input = "hel";
    try ac.setSuggestions(&all_suggestions);

    // Should only match "hello", "help", "helmet" (not "world")
    try std.testing.expectEqual(@as(usize, 3), ac.getSuggestionCount());
}

test "autocomplete: builder pattern" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const block = (Block{}).setTitle("Autocomplete");
    _ = ac.setBlock(block).setMaxVisible(5).setHighlightStyle(.{ .fg = Color{ .indexed = 3 } });

    try std.testing.expectEqual(@as(usize, 5), ac.max_visible);
    try std.testing.expect(ac.block != null);
}

test "autocomplete: render empty" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    ac.render(&buffer, area);

    // Should not crash, buffer should remain default
    const cell = buffer.get(0, 0);
    try std.testing.expectEqual(@as(u21, ' '), cell.char);
}

test "autocomplete: render suggestions" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const suggestions = [_][]const u8{ "hello", "world" };
    try ac.setSuggestions(&suggestions);

    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    ac.render(&buffer, area);

    // Check first suggestion rendered
    const cell_h = buffer.get(0, 0);
    try std.testing.expectEqual(@as(u21, 'h'), cell_h.char);

    // Check highlight style applied to first item (selected by default)
    try std.testing.expectEqual(ac.highlight_style.fg, cell_h.style.fg);
}

test "autocomplete: render with block" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const block = (Block{}).setTitle("Suggestions");
    _ = ac.setBlock(block);

    const suggestions = [_][]const u8{"hello"};
    try ac.setSuggestions(&suggestions);

    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    ac.render(&buffer, area);

    // Block border should be rendered (top-left corner)
    const cell = buffer.get(0, 0);
    try std.testing.expect(cell.char != ' '); // Should be border character
}

test "autocomplete: render max visible" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();
    ac.setMaxVisible(2);

    const suggestions = [_][]const u8{ "a", "b", "c", "d" };
    try ac.setSuggestions(&suggestions);

    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    ac.render(&buffer, area);

    // Only first 2 suggestions should be rendered
    const cell_a = buffer.get(0, 0);
    const cell_b = buffer.get(0, 1);
    const cell_c = buffer.get(0, 2); // Should be empty

    try std.testing.expectEqual(@as(u21, 'a'), cell_a.char);
    try std.testing.expectEqual(@as(u21, 'b'), cell_b.char);
    try std.testing.expectEqual(@as(u21, ' '), cell_c.char);
}

test "autocomplete: render scrolled" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();
    ac.setMaxVisible(2);

    const suggestions = [_][]const u8{ "a", "b", "c", "d" };
    try ac.setSuggestions(&suggestions);

    // Scroll down
    ac.selectNext(); // idx=1
    ac.selectNext(); // idx=2, scroll_offset=1

    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    ac.render(&buffer, area);

    // Should render "b" and "c" (offset by 1)
    const cell_first = buffer.get(0, 0);
    const cell_second = buffer.get(0, 1);

    try std.testing.expectEqual(@as(u21, 'b'), cell_first.char);
    try std.testing.expectEqual(@as(u21, 'c'), cell_second.char);
}

// ============================================================================
// Multi-Column and Documentation Preview Tests
// ============================================================================

test "autocomplete: setSuggestionsWithDocs" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "println", .metadata = "macro", .doc = "Prints a line to stdout" },
        .{ .text = "printf", .metadata = "fn", .doc = "Formatted print function" },
        .{ .text = "print", .metadata = "fn", .doc = "Print without newline" },
    });

    try std.testing.expectEqual(@as(usize, 3), ac.getSuggestionCount());
    try std.testing.expect(std.mem.eql(u8, "println", ac.suggestions.items[0].text));
    try std.testing.expect(ac.suggestions.items[0].metadata != null);
    try std.testing.expect(std.mem.eql(u8, "macro", ac.suggestions.items[0].metadata.?));
    try std.testing.expect(ac.suggestions.items[0].doc != null);
}

test "autocomplete: enable doc preview" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try std.testing.expectEqual(false, ac.show_doc_preview);

    _ = ac.enableDocPreview(true);
    try std.testing.expectEqual(true, ac.show_doc_preview);

    _ = ac.setPreviewWidth(50);
    try std.testing.expectEqual(@as(u16, 50), ac.preview_width);
}

test "autocomplete: enable metadata column" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try std.testing.expectEqual(false, ac.show_metadata_column);

    _ = ac.enableMetadataColumn(true);
    try std.testing.expectEqual(true, ac.show_metadata_column);

    _ = ac.setMetadataColumnWidth(15);
    try std.testing.expectEqual(@as(u16, 15), ac.metadata_column_width);
}

test "autocomplete: render with metadata column" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "foo", .metadata = "fn" },
        .{ .text = "bar", .metadata = "type" },
    });

    _ = ac.enableMetadataColumn(true);
    _ = ac.setMetadataColumnWidth(8);

    var buffer = try Buffer.init(allocator, 30, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    ac.render(&buffer, area);

    // Should render both suggestions with metadata
    const cell_first = buffer.get(0, 0);
    try std.testing.expectEqual(@as(u21, 'f'), cell_first.char);
}

test "autocomplete: render with doc preview" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    try ac.setSuggestionsWithDocs(&.{
        .{ .text = "println", .doc = "Prints a line with newline" },
    });

    _ = ac.enableDocPreview(true);
    _ = ac.setPreviewWidth(30);

    var buffer = try Buffer.init(allocator, 80, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    ac.render(&buffer, area);

    // Should render suggestion on left and doc preview on right
    const cell_first = buffer.get(0, 0);
    try std.testing.expectEqual(@as(u21, 'p'), cell_first.char);
}

test "autocomplete: metadata and doc styles" {
    const allocator = std.testing.allocator;
    var ac = Autocomplete.init(allocator);
    defer ac.deinit();

    const custom_meta_style = Style{ .fg = Color{ .indexed = 3 } };
    const custom_doc_style = Style{ .fg = Color{ .indexed = 4 } };

    _ = ac.setMetadataStyle(custom_meta_style);
    _ = ac.setDocStyle(custom_doc_style);

    try std.testing.expectEqual(custom_meta_style.fg, ac.metadata_style.fg);
    try std.testing.expectEqual(custom_doc_style.fg, ac.doc_style.fg);
}
