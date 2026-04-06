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
/// - Keyboard navigation (up/down, home/end)
/// - Selected item highlighting
/// - Max visible items with scrolling
/// - Custom provider callback for dynamic suggestions
/// - Optional block borders
///
/// Example:
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
    provider: ?*const ProviderFn,

    const Suggestion = struct {
        text: []const u8,
        score: f32,
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
            .provider = null,
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

    /// Set input text and trigger suggestion update
    pub fn setInput(self: *Autocomplete, input: []const u8) !void {
        self.input = input;
        try self.updateSuggestions();
    }

    /// Manually set suggestions (bypasses provider)
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
    /// and supports scrolling when suggestions exceed max visible count.
    pub fn render(self: *const Autocomplete, buf: *Buffer, area: Rect) void {
        const inner = if (self.block) |b| b.inner(area) else area;

        // Render block border if present
        if (self.block) |b| {
            b.render(buf, area);
        }

        if (self.suggestions.items.len == 0) {
            return; // No suggestions to render
        }

        const visible_count = @min(self.max_visible, self.suggestions.items.len);
        const end_index = @min(self.scroll_offset + visible_count, self.suggestions.items.len);

        var y: u16 = inner.y;
        for (self.suggestions.items[self.scroll_offset..end_index], 0..) |suggestion, i| {
            if (y >= inner.y + inner.height) break;

            const is_selected = (self.scroll_offset + i) == self.selected_index;
            const style = if (is_selected) self.highlight_style else self.normal_style;

            // Render suggestion text
            var x: u16 = inner.x;
            for (suggestion.text) |c| {
                if (x >= inner.x + inner.width) break;
                var cell = buf.get(x, y);
                cell.char = c;
                cell.style = style;
                buf.setChar(x, y, cell.char, cell.style);
                x += 1;
            }

            // Fill remaining width with background
            while (x < inner.x + inner.width) : (x += 1) {
                var cell = buf.get(x, y);
                cell.char = ' ';
                cell.style = style;
                buf.setChar(x, y, cell.char, cell.style);
            }

            y += 1;
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
