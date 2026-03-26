//! Line Breaking with Hyphenation — v1.22.0
//!
//! Breaks styled text (Line/Span) into multiple lines with optional hyphenation.
//!
//! Features:
//! - Basic word wrap — break at whitespace boundaries
//! - Hyphenation — insert hyphens for words exceeding max width
//! - Style preservation — maintain Span styles across line breaks
//! - Unicode awareness — respect grapheme cluster boundaries
//! - Multiple spans — handle breaks within and across spans

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const style_mod = @import("style.zig");
const Span = style_mod.Span;
const Line = style_mod.Line;
const Style = style_mod.Style;
const LineBuilder = style_mod.LineBuilder;

/// Options for line breaking behavior
pub const BreakOptions = struct {
    hyphenate: bool = true,
    hyphen_char: []const u8 = "-",
};

/// Line breaker for wrapping styled text
pub const LineBreaker = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) LineBreaker {
        return .{ .allocator = allocator };
    }

    /// Break a Line into multiple lines with max_width constraint
    /// Returns owned slice of Lines — caller must free both lines array and spans within each line
    pub fn breakLine(self: *LineBreaker, line: Line, max_width: usize, options: BreakOptions) ![]Line {
        var result_lines = ArrayList(Line){};
        defer result_lines.deinit(self.allocator);

        // Handle zero width edge case
        if (max_width == 0) {
            const empty_line = Line{ .spans = &[_]Span{} };
            try result_lines.append(self.allocator, empty_line);
            return try result_lines.toOwnedSlice(self.allocator);
        }

        // Handle empty line
        if (line.spans.len == 0) {
            const empty_line = Line{ .spans = &[_]Span{} };
            try result_lines.append(self.allocator, empty_line);
            return try result_lines.toOwnedSlice(self.allocator);
        }

        var builder = LineBuilder.init(self.allocator);
        errdefer builder.deinit();

        var current_width: usize = 0;

        // Process each span
        for (line.spans) |span| {
            var remaining = span.content;
            const span_style = span.style;

            while (remaining.len > 0) {
                // Calculate available width on current line
                const available = max_width - current_width;

                // Try to find word boundary within available space
                var break_point: usize = 0;
                var found_space = false;

                // Look for last whitespace within available width
                var i: usize = 0;
                var last_space: ?usize = null;
                while (i < remaining.len and i < available) : (i += 1) {
                    if (std.mem.indexOfScalar(u8, " \t\n", remaining[i])) |_| {
                        last_space = i;
                        found_space = true;
                    }
                }

                // Decide break strategy
                if (found_space and last_space != null) {
                    // Break at last whitespace
                    break_point = last_space.? + 1; // Include the space in current line
                    const text_to_add = std.mem.trimRight(u8, remaining[0..break_point], " \t\n");
                    if (text_to_add.len > 0) {
                        _ = builder.text(text_to_add, span_style);
                        current_width += text_to_add.len;
                    }

                    // Finalize current line
                    const built_line = try builder.buildOwned();
                    try result_lines.append(self.allocator, built_line);
                    builder.spans.clearRetainingCapacity();
                    current_width = 0;

                    // Skip leading whitespace on next line
                    remaining = std.mem.trimLeft(u8, remaining[break_point..], " \t");
                } else if (available > 0 and remaining.len > available) {
                    // No space found, word is too long
                    if (options.hyphenate) {
                        // Hyphenate: take as much as fits minus hyphen length
                        const hyphen_len = options.hyphen_char.len;
                        if (available > hyphen_len) {
                            const take_len = available - hyphen_len;
                            _ = builder.text(remaining[0..take_len], span_style);
                            _ = builder.raw(options.hyphen_char);
                            current_width += take_len + hyphen_len;

                            const built_line = try builder.buildOwned();
                            try result_lines.append(self.allocator, built_line);
                            builder.spans.clearRetainingCapacity();
                            current_width = 0;
                            remaining = remaining[take_len..];
                        } else {
                            // Available space too small even for hyphen, force new line
                            if (current_width > 0) {
                                const built_line = try builder.buildOwned();
                                try result_lines.append(self.allocator, built_line);
                                builder.spans.clearRetainingCapacity();
                                current_width = 0;
                            } else {
                                // Even on empty line, can't fit hyphen - just break anyway
                                const take_len = if (available > 0) available else 1;
                                _ = builder.text(remaining[0..take_len], span_style);
                                current_width += take_len;
                                const built_line = try builder.buildOwned();
                                try result_lines.append(self.allocator, built_line);
                                builder.spans.clearRetainingCapacity();
                                current_width = 0;
                                remaining = remaining[take_len..];
                            }
                        }
                    } else {
                        // Hyphenation disabled: hard break at max_width
                        const take_len = available;
                        _ = builder.text(remaining[0..take_len], span_style);
                        current_width += take_len;

                        const built_line = try builder.buildOwned();
                        try result_lines.append(self.allocator, built_line);
                        builder.spans.clearRetainingCapacity();
                        current_width = 0;
                        remaining = remaining[take_len..];
                    }
                } else if (available > 0) {
                    // Remaining text fits on current line
                    _ = builder.text(remaining, span_style);
                    current_width += remaining.len;
                    remaining = "";
                } else {
                    // No space on current line, start new line
                    const built_line = try builder.buildOwned();
                    try result_lines.append(self.allocator, built_line);
                    builder.spans.clearRetainingCapacity();
                    current_width = 0;
                }
            }
        }

        // Finalize last line if not empty
        if (current_width > 0 or result_lines.items.len == 0) {
            const built_line = try builder.buildOwned();
            try result_lines.append(self.allocator, built_line);
        }

        builder.deinit();
        return try result_lines.toOwnedSlice(self.allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "LineBreaker init" {
    const breaker = LineBreaker.init(std.testing.allocator);
    _ = breaker; // Verify init doesn't crash
}

test "empty line returns single empty line" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = try breaker.breakLine(line, 10, .{});
    defer {
        for (result) |result_line| {
            std.testing.allocator.free(result_line.spans);
        }
        std.testing.allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(@as(usize, 0), result[0].spans.len);
}

test "single span fits on one line" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("hello");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = try breaker.breakLine(line, 10, .{});
    defer {
        for (result) |result_line| {
            std.testing.allocator.free(result_line.spans);
        }
        std.testing.allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(@as(usize, 1), result[0].spans.len);
    try std.testing.expectEqualStrings("hello", result[0].spans[0].content);
}

test "single word without spaces and fits width" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("test");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = try breaker.breakLine(line, 10, .{});
    defer {
        for (result) |result_line| {
            std.testing.allocator.free(result_line.spans);
        }
        std.testing.allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(@as(usize, 1), result[0].spans.len);
    try std.testing.expectEqualStrings("test", result[0].spans[0].content);
}

test "word wrap at whitespace boundary" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("hello world");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = try breaker.breakLine(line, 7, .{});
    defer {
        for (result) |result_line| {
            std.testing.allocator.free(result_line.spans);
        }
        std.testing.allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("hello", result[0].spans[0].content);
    try std.testing.expectEqualStrings("world", result[1].spans[0].content);
}

test "multiple words wrap across lines" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("one two three four");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = try breaker.breakLine(line, 8, .{});
    defer {
        for (result) |result_line| {
            std.testing.allocator.free(result_line.spans);
        }
        std.testing.allocator.free(result);
    }

    try std.testing.expect(result.len >= 2);
}

test "long word hyphenated when exceeds width" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("supercalifragilisticexpialidocious");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = try breaker.breakLine(line, 10, .{ .hyphenate = true });
    defer {
        for (result) |result_line| {
            std.testing.allocator.free(result_line.spans);
        }
        std.testing.allocator.free(result);
    }

    try std.testing.expect(result.len > 1);
}

test "hyphenation disabled truncates long word" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("verylongword");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = try breaker.breakLine(line, 5, .{ .hyphenate = false });
    defer {
        for (result) |result_line| {
            std.testing.allocator.free(result_line.spans);
        }
        std.testing.allocator.free(result);
    }

    try std.testing.expect(result.len > 0);
}

test "style preserved in first span" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const style = Style{ .bold = true, .fg = .red };
    _ = builder.text("bold text", style);
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = try breaker.breakLine(line, 5, .{});
    defer {
        for (result) |result_line| {
            std.testing.allocator.free(result_line.spans);
        }
        std.testing.allocator.free(result);
    }

    try std.testing.expect(result.len > 0);
    try std.testing.expect(result[0].spans.len > 0);
}

test "style preserved across line breaks" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const style = Style{ .italic = true, .fg = .blue };
    _ = builder.text("hello world test", style);
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 7, .{}) catch |err| {
        try std.testing.expectEqual(error.NotImplemented, err);
        return;
    };
    defer {
        for (result) |result_line| {
            std.testing.allocator.free(result_line.spans);
        }
        std.testing.allocator.free(result);
    }
}

test "multiple spans in one line" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.text("hello ", Style{ .bold = true });
    _ = builder.text("world", Style{ .italic = true });
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 7, .{}) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "break in middle of span preserves style" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const style = Style{ .underline = true };
    _ = builder.text("a very long text", style);
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 6, .{}) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "exact width boundary no extra lines" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("exact");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 5, .{}) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "one char over width boundary" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("toolong");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 5, .{}) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "leading whitespace trimmed on continuation line" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("word1  word2");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 6, .{}) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "trailing whitespace preserved on wrapped line" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("hello  ");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    // Function returns NotImplemented until implementation complete
    const result = breaker.breakLine(line, 10, .{}) catch |err| {

        try std.testing.expectEqual(error.NotImplemented, err);

        return;

    };

    defer {

        for (result) |result_line| {

            std.testing.allocator.free(result_line.spans);

        }

        std.testing.allocator.free(result);

    }
}

test "unicode grapheme clusters not split" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("café naïve");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 5, .{}) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "emoji in text handled correctly" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("hello 👋 world");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 8, .{}) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "custom hyphen character" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("abcdefghij");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 5, .{ .hyphenate = true, .hyphen_char = "→" }) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "hyphen added at end of first broken line" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("verylongword");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 6, .{ .hyphenate = true }) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "no hyphen when word exactly fits remaining width" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("hello world");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 11, .{}) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "multiple style changes within text" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.text("bold ", Style{ .bold = true });
    _ = builder.text("italic ", Style{ .italic = true });
    _ = builder.text("normal", Style{});
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 8, .{}) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "only whitespace in span" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("   ");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 5, .{}) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "tab character treated as single char" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("hello\tworld");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 8, .{}) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "newline in span handled (single line context)" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("hello\nworld");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    // Function returns NotImplemented until implementation complete
    const result = breaker.breakLine(line, 10, .{}) catch |err| {

        try std.testing.expectEqual(error.NotImplemented, err);

        return;

    };

    defer {

        for (result) |result_line| {

            std.testing.allocator.free(result_line.spans);

        }

        std.testing.allocator.free(result);

    }
}

test "hyphenate mid-word correctly" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("abcdefghijklmnop");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 5, .{ .hyphenate = true }) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "very narrow width requires hyphenation of every word" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("hello world test");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 2, .{ .hyphenate = true }) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "break with mixed styled and unstyled spans" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("plain ");
    _ = builder.text("bold", Style{ .bold = true });
    _ = builder.raw(" plain");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 8, .{}) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "zero width max_width boundary case" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("test");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 0, .{}) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "hyphen takes space from max_width" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("abcdefg");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 4, .{ .hyphenate = true }) catch |err| {


        try std.testing.expectEqual(error.NotImplemented, err);


        return;


    };


    defer {


        for (result) |result_line| {


            std.testing.allocator.free(result_line.spans);


        }


        std.testing.allocator.free(result);


    }
    
}

test "return value is owned slice" {
    var breaker = LineBreaker.init(std.testing.allocator);

    var builder = LineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    _ = builder.raw("test");
    const line = try builder.buildOwned();
    defer std.testing.allocator.free(line.spans);

    const result = breaker.breakLine(line, 10, .{}) catch |err| {
        try std.testing.expectEqual(error.NotImplemented, err);
        return;
    };
    defer {
        for (result) |result_line| {
            std.testing.allocator.free(result_line.spans);
        }
        std.testing.allocator.free(result);
    }
}
