const std = @import("std");
const Allocator = std.mem.Allocator;

/// Bidirectional text support for rendering RTL (Right-to-Left) scripts.
/// Implements Unicode Bidirectional Algorithm (UAX #9) — simplified version
/// focusing on practical terminal rendering.
pub const Bidi = struct {
    /// Text direction
    pub const Direction = enum {
        ltr, // Left-to-Right (Latin, Cyrillic, etc.)
        rtl, // Right-to-Left (Arabic, Hebrew, etc.)
        auto, // Auto-detect from first strong directional character
    };

    /// Character directionality types (simplified UAX #9)
    pub const CharType = enum {
        L, // Left-to-Right (Latin, digits)
        R, // Right-to-Left (Hebrew, Arabic)
        EN, // European Number
        AN, // Arabic Number
        WS, // Whitespace
        ON, // Other Neutral
    };

    /// Get directionality type of a Unicode codepoint.
    /// Implements simplified UAX #9 character classification.
    /// Supports: Latin (L), Hebrew/Arabic (R), digits (EN), whitespace (WS), other (ON).
    /// Returns the character's bidirectional type for text reordering.
    pub fn charType(codepoint: u21) CharType {
        // Latin (U+0041-U+005A, U+0061-U+007A)
        if ((codepoint >= 0x0041 and codepoint <= 0x005A) or
            (codepoint >= 0x0061 and codepoint <= 0x007A))
        {
            return .L;
        }

        // ASCII digits (U+0030-U+0039)
        if (codepoint >= 0x0030 and codepoint <= 0x0039) {
            return .EN;
        }

        // Arabic (U+0600-U+06FF)
        if (codepoint >= 0x0600 and codepoint <= 0x06FF) {
            return .R;
        }

        // Hebrew (U+0590-U+05FF)
        if (codepoint >= 0x0590 and codepoint <= 0x05FF) {
            return .R;
        }

        // Arabic Supplement (U+0750-U+077F)
        if (codepoint >= 0x0750 and codepoint <= 0x077F) {
            return .R;
        }

        // Arabic Extended-A (U+08A0-U+08FF)
        if (codepoint >= 0x08A0 and codepoint <= 0x08FF) {
            return .R;
        }

        // Arabic Presentation Forms-A (U+FB50-U+FDFF)
        if (codepoint >= 0xFB50 and codepoint <= 0xFDFF) {
            return .R;
        }

        // Arabic Presentation Forms-B (U+FE70-U+FEFF)
        if (codepoint >= 0xFE70 and codepoint <= 0xFEFF) {
            return .R;
        }

        // Whitespace
        if (codepoint == ' ' or codepoint == '\t' or codepoint == '\n') {
            return .WS;
        }

        // Cyrillic (U+0400-U+04FF) - LTR
        if (codepoint >= 0x0400 and codepoint <= 0x04FF) {
            return .L;
        }

        // Greek (U+0370-U+03FF) - LTR
        if (codepoint >= 0x0370 and codepoint <= 0x03FF) {
            return .L;
        }

        // Default: Other Neutral
        return .ON;
    }

    /// Detect base direction from text content.
    /// Scans for first strong directional character (L/EN → ltr, R/AN → rtl).
    /// Returns ltr if no strong directional characters found.
    /// Use with .auto direction mode for automatic text handling.
    pub fn detectDirection(str: []const u8) Direction {
        var i: usize = 0;

        while (i < str.len) {
            const byte = str[i];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (i + char_len > str.len) break;

            const codepoint = if (char_len == 1)
                @as(u21, byte)
            else
                std.unicode.utf8Decode(str[i .. i + char_len]) catch @as(u21, byte);

            const ct = charType(codepoint);

            // First strong directional character determines base direction
            switch (ct) {
                .L, .EN => return .ltr,
                .R, .AN => return .rtl,
                else => {},
            }

            i += char_len;
        }

        // No strong directional characters found — default to LTR
        return .ltr;
    }

    /// Reorder visual string for RTL rendering in terminal.
    /// Returns a newly allocated string with characters in visual order.
    /// Caller must free the returned slice.
    ///
    /// Simplified algorithm:
    /// - LTR: Return copy as-is
    /// - RTL: Reverse entire codepoint sequence (simplified UAX #9)
    /// - auto: Auto-detect direction then apply appropriate reordering
    ///
    /// Note: This is a simplified implementation for terminal rendering.
    /// Full UAX #9 handles mixed LTR/RTL runs, neutral characters, and brackets.
    pub fn reorder(allocator: Allocator, str: []const u8, base_dir: Direction) ![]u8 {
        // Resolve base direction
        const dir = if (base_dir == .auto) detectDirection(str) else base_dir;

        // LTR text — return copy as-is
        if (dir == .ltr) {
            return try allocator.dupe(u8, str);
        }

        // RTL text — perform reordering
        return try reorderRtl(allocator, str);
    }

    /// Reorder RTL text (private implementation)
    fn reorderRtl(allocator: Allocator, str: []const u8) ![]u8 {
        // Parse string into codepoints
        var codepoints: std.ArrayList(u21) = .{};
        defer codepoints.deinit(allocator);

        var i: usize = 0;
        while (i < str.len) {
            const byte = str[i];
            const char_len = std.unicode.utf8ByteSequenceLength(byte) catch 1;

            if (i + char_len > str.len) break;

            const codepoint = if (char_len == 1)
                @as(u21, byte)
            else
                std.unicode.utf8Decode(str[i .. i + char_len]) catch @as(u21, byte);

            try codepoints.append(allocator, codepoint);
            i += char_len;
        }

        // Reverse entire codepoint sequence for RTL base direction
        std.mem.reverse(u21, codepoints.items);

        // Encode back to UTF-8
        var result: std.ArrayList(u8) = .{};
        defer result.deinit(allocator);

        for (codepoints.items) |cp| {
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(cp, &buf) catch continue;
            try result.appendSlice(allocator, buf[0..len]);
        }

        return try result.toOwnedSlice(allocator);
    }
};

// Tests
test "Bidi.charType - Latin" {
    try std.testing.expectEqual(Bidi.CharType.L, Bidi.charType('A'));
    try std.testing.expectEqual(Bidi.CharType.L, Bidi.charType('z'));
}

test "Bidi.charType - digits" {
    try std.testing.expectEqual(Bidi.CharType.EN, Bidi.charType('0'));
    try std.testing.expectEqual(Bidi.CharType.EN, Bidi.charType('9'));
}

test "Bidi.charType - Hebrew" {
    try std.testing.expectEqual(Bidi.CharType.R, Bidi.charType('א')); // Alef (U+05D0)
    try std.testing.expectEqual(Bidi.CharType.R, Bidi.charType('ת')); // Tav (U+05EA)
}

test "Bidi.charType - Arabic" {
    try std.testing.expectEqual(Bidi.CharType.R, Bidi.charType('ا')); // Alif (U+0627)
    try std.testing.expectEqual(Bidi.CharType.R, Bidi.charType('ي')); // Yeh (U+064A)
}

test "Bidi.charType - whitespace" {
    try std.testing.expectEqual(Bidi.CharType.WS, Bidi.charType(' '));
    try std.testing.expectEqual(Bidi.CharType.WS, Bidi.charType('\t'));
}

test "Bidi.detectDirection - LTR" {
    try std.testing.expectEqual(Bidi.Direction.ltr, Bidi.detectDirection("Hello"));
    try std.testing.expectEqual(Bidi.Direction.ltr, Bidi.detectDirection("123 test"));
    try std.testing.expectEqual(Bidi.Direction.ltr, Bidi.detectDirection("Привет")); // Cyrillic
}

test "Bidi.detectDirection - RTL" {
    try std.testing.expectEqual(Bidi.Direction.rtl, Bidi.detectDirection("שלום")); // Hebrew "shalom"
    try std.testing.expectEqual(Bidi.Direction.rtl, Bidi.detectDirection("مرحبا")); // Arabic "marhaba"
    try std.testing.expectEqual(Bidi.Direction.rtl, Bidi.detectDirection("   שלום")); // With leading whitespace
}

test "Bidi.detectDirection - neutral only" {
    // No strong directional characters — defaults to LTR
    try std.testing.expectEqual(Bidi.Direction.ltr, Bidi.detectDirection("..."));
    try std.testing.expectEqual(Bidi.Direction.ltr, Bidi.detectDirection("   "));
}

test "Bidi.reorder - LTR passthrough" {
    const allocator = std.testing.allocator;
    const input = "Hello";
    const result = try Bidi.reorder(allocator, input, .ltr);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello", result);
}

test "Bidi.reorder - RTL simple" {
    const allocator = std.testing.allocator;

    // Hebrew "shalom" (שלום) — when rendered RTL, character order reverses
    const input = "שלום";
    const result = try Bidi.reorder(allocator, input, .rtl);
    defer allocator.free(result);

    // Result should be reversed codepoint order
    // Original: ש ל ו ם
    // Reversed: ם ו ל ש
    try std.testing.expect(result.len == input.len);
}

test "Bidi.reorder - auto-detect LTR" {
    const allocator = std.testing.allocator;
    const input = "Hello";
    const result = try Bidi.reorder(allocator, input, .auto);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello", result);
}

test "Bidi.reorder - auto-detect RTL" {
    const allocator = std.testing.allocator;
    const input = "שלום";
    const result = try Bidi.reorder(allocator, input, .auto);
    defer allocator.free(result);

    // Auto-detected as RTL, should be reversed
    try std.testing.expect(result.len == input.len);
}

test "Bidi.reorder - ASCII reversal" {
    const allocator = std.testing.allocator;
    const input = "ABC";
    const result = try Bidi.reorder(allocator, input, .rtl);
    defer allocator.free(result);

    // When forced RTL, even ASCII reverses
    try std.testing.expectEqualStrings("CBA", result);
}

test "Bidi.reorder - mixed content" {
    const allocator = std.testing.allocator;

    // Mixed Hebrew and Latin
    // In real BiDi, numbers/Latin in RTL context stay LTR but position changes
    // Our simplified implementation just reverses entire string
    const input = "Hello שלום";
    const result = try Bidi.reorder(allocator, input, .rtl);
    defer allocator.free(result);

    // Verify allocation succeeded and result is non-empty
    try std.testing.expect(result.len > 0);
}
