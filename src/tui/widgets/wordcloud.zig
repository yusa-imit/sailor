//! WordCloud Widget — displays weighted words in spiral layout
//!
//! The WordCloud widget renders a collection of words at positions determined
//! by an Archimedean spiral, with font weights applied based on word weights.
//! High-weight words appear in the center, low-weight words toward the edges.
//!
//! ## Features
//! - Archimedean spiral placement algorithm
//! - Weight-based styling (bold for high weight, dim for low weight)
//! - Overlap detection with configurable gaps
//! - Block border support for framed rendering
//! - Builder API for fluent configuration
//!
//! ## Usage
//! ```zig
//! var words = [_]Word{
//!     .{ .text = "hello", .weight = 5 },
//!     .{ .text = "world", .weight = 3 },
//! };
//! var wc = WordCloud.init()
//!     .withWords(&words)
//!     .withBoldStyle(Style{ .bold = true });
//! wc.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// A single word with associated weight
pub const Word = struct {
    text: []const u8,
    weight: u8 = 1,
};

/// WordCloud widget for displaying weighted words in spiral layout
pub const WordCloud = struct {
    /// Maximum number of words to place
    const MAX_WORDS: usize = 64;

    /// Array of words to render
    words: []const Word = &.{},

    /// Base style for words
    style: Style = .{},

    /// Style for high-weight words (weight >= 5)
    bold_style: Style = .{},

    /// Style for low-weight words (weight <= 2)
    dim_style: Style = .{},

    /// Optional border block
    block: ?Block = null,

    /// Initialize a new WordCloud with defaults
    pub fn init() WordCloud {
        return .{};
    }

    /// Create a copy with different words
    pub fn withWords(self: WordCloud, words: []const Word) WordCloud {
        var result = self;
        result.words = words;
        return result;
    }

    /// Create a copy with different base style
    pub fn withStyle(self: WordCloud, style: Style) WordCloud {
        var result = self;
        result.style = style;
        return result;
    }

    /// Create a copy with different bold style
    pub fn withBoldStyle(self: WordCloud, style: Style) WordCloud {
        var result = self;
        result.bold_style = style;
        return result;
    }

    /// Create a copy with different dim style
    pub fn withDimStyle(self: WordCloud, style: Style) WordCloud {
        var result = self;
        result.dim_style = style;
        return result;
    }

    /// Create a copy with a block border
    pub fn withBlock(self: WordCloud, block: Block) WordCloud {
        var result = self;
        result.block = block;
        return result;
    }

    /// Check if a style is empty (equals default Style{})
    fn styleIsEmpty(s: Style) bool {
        return std.meta.eql(s, Style{});
    }

    /// Render the word cloud to the buffer
    pub fn render(self: WordCloud, buf: *Buffer, area: Rect) void {
        // Early exit for zero-area
        if (area.width == 0 or area.height == 0) {
            return;
        }

        var inner = area;

        // Render block border if present
        if (self.block) |b| {
            b.render(buf, area);
            inner = b.inner(area);
        }

        // Early exit if inner area is zero
        if (inner.width == 0 or inner.height == 0) {
            return;
        }

        // Early exit if no words
        if (self.words.len == 0) {
            return;
        }

        // Copy and sort words by weight (descending)
        const count = @min(self.words.len, MAX_WORDS);
        var sorted: [MAX_WORDS]Word = undefined;
        @memcpy(sorted[0..count], self.words[0..count]);

        // Bubble sort by weight (descending)
        var i: usize = 0;
        while (i < count) : (i += 1) {
            var j: usize = i + 1;
            while (j < count) : (j += 1) {
                if (sorted[j].weight > sorted[i].weight) {
                    const tmp = sorted[i];
                    sorted[i] = sorted[j];
                    sorted[j] = tmp;
                }
            }
        }

        // Track placed words for overlap detection
        const PlacedWord = struct { x: u16, y: u16, end_x: u16 };
        var placed: [MAX_WORDS]PlacedWord = undefined;
        var placed_count: usize = 0;

        // Calculate center
        const cx = inner.x + inner.width / 2;
        const cy = inner.y + inner.height / 2;

        // Try to place each word
        var word_idx: usize = 0;
        while (word_idx < count) : (word_idx += 1) {
            const word = sorted[word_idx];

            // Skip empty words
            if (word.text.len == 0) {
                continue;
            }

            // Try positions on Archimedean spiral
            var theta: f32 = 0.0;
            var placed_word = false;

            while (theta < 200.0 and !placed_word) : (theta += 0.5) {
                const r = 0.3 + theta * 0.25;

                // Calculate position (apply 2x factor to x for terminal aspect ratio)
                const px_f = @as(f32, @floatFromInt(cx)) + r * std.math.cos(theta) * 2.0;
                const py_f = @as(f32, @floatFromInt(cy)) + r * std.math.sin(theta);

                const px = @as(i32, @intFromFloat(@round(px_f)));
                const py = @as(i32, @intFromFloat(@round(py_f)));

                const word_len = @as(i32, @intCast(word.text.len));

                // Bounds check: word must fit entirely within inner area
                if (px < @as(i32, @intCast(inner.x))) {
                    continue;
                }
                if (px + word_len > @as(i32, @intCast(inner.x + inner.width))) {
                    continue;
                }
                if (py < @as(i32, @intCast(inner.y)) or py >= @as(i32, @intCast(inner.y + inner.height))) {
                    continue;
                }

                // Check for overlaps with 1-char gap
                var overlaps = false;
                var check_idx: usize = 0;
                while (check_idx < placed_count and !overlaps) : (check_idx += 1) {
                    const p = placed[check_idx];
                    const py_u16 = @as(u16, @intCast(py));

                    // Only check if on same row
                    if (py_u16 == p.y) {
                        // Check if [px, px+word_len) overlaps [p.x-1, p.end_x+1)
                        const px_u16 = @as(u16, @intCast(px));
                        if (px_u16 <= p.end_x and px_u16 + @as(u16, @intCast(word_len)) >= p.x) {
                            overlaps = true;
                        }
                    }
                }

                if (!overlaps) {
                    // Choose style based on weight
                    const word_style = if (word.weight >= 5 and !styleIsEmpty(self.bold_style))
                        self.bold_style
                    else if (word.weight <= 2 and !styleIsEmpty(self.dim_style))
                        self.dim_style
                    else
                        self.style;

                    // Render the word
                    buf.setString(@as(u16, @intCast(px)), @as(u16, @intCast(py)), word.text, word_style);

                    // Record placement
                    placed[placed_count] = .{
                        .x = @as(u16, @intCast(px)),
                        .y = @as(u16, @intCast(py)),
                        .end_x = @as(u16, @intCast(px + word_len - 1)),
                    };
                    placed_count += 1;
                    placed_word = true;
                }
            }
        }
    }
};
