//! Fuzzy string matching — subsequence search with scoring
//!
//! FuzzyMatcher provides efficient fuzzy matching of patterns against text,
//! returning match score (0.0-1.0) and byte positions of matched characters.
//!
//! ## Scoring
//! - Empty pattern: score 0.0 (always matches)
//! - Prefix match (pattern starts text): high score
//! - Word boundary match (after separator): bonus
//! - camelCase boundary: bonus
//! - Consecutive characters: bonus
//! - Case-insensitive matching
//!
//! ## Example
//! ```zig
//! const result = FuzzyMatcher.match("src", "source");
//! // result.score = 0.95 (high score for prefix match)
//! // result.positions = [0, 3, 4] (byte indices of 's', 'r', 'c')
//! ```

const std = @import("std");

/// Maximum number of match positions tracked
const MAX_POSITIONS = 512;

/// Static buffer for positions — valid until next call to match()
var positions_storage: [MAX_POSITIONS]u16 = undefined;

/// Result of a fuzzy match
pub const MatchResult = struct {
    /// Score from 0.0 (empty pattern) to 1.0 (perfect match)
    score: f32,
    /// Byte indices of matched pattern characters in text
    /// Valid until the next call to match()
    positions: []const u16,
};

/// Fuzzy string matcher
pub const FuzzyMatcher = struct {
    /// Fuzzy match pattern against text using greedy left-to-right matching.
    /// Returns null if pattern cannot be matched as a subsequence.
    /// Returns MatchResult with score 0.0 if pattern is empty.
    ///
    /// The positions slice is valid only until the next call to match().
    pub fn match(pattern: []const u8, text: []const u8) ?MatchResult {
        // Case 1: empty pattern → always match with neutral score
        if (pattern.len == 0) {
            return MatchResult{
                .score = 0.0,
                .positions = positions_storage[0..0],
            };
        }

        // Case 2: text too short or pattern too long → no match
        if (text.len == 0 or pattern.len > text.len) {
            return null;
        }

        // Greedy subsequence matching: left-to-right, first match wins
        var len: usize = 0;
        var ti: usize = 0;
        var pi: usize = 0;
        var quality: f32 = 0.0;
        var prev_ti: usize = std.math.maxInt(usize);

        while (pi < pattern.len and ti < text.len) {
            const pc = toLower(pattern[pi]);
            const tc = toLower(text[ti]);

            const chars_match = pc == tc or (isSeparator(pc) and isSeparator(tc));

            if (chars_match) {
                // Record position
                if (len >= MAX_POSITIONS) {
                    return null; // Pattern too long for our buffer
                }
                positions_storage[len] = @intCast(ti);
                len += 1;

                // Calculate quality bonus for this match
                // Prefix bonus: first character at position 0
                if (ti == 0) {
                    quality += 3.0;
                }
                // Consecutive bonus: character directly after previous match
                else if (prev_ti != std.math.maxInt(usize) and ti == prev_ti + 1) {
                    quality += 5.0;
                }
                // Word boundary bonus: after separator
                else if (ti > 0 and isSeparator(text[ti - 1])) {
                    quality += 3.0;
                }
                // camelCase boundary bonus: lowercase -> uppercase
                else if (ti > 0 and std.ascii.isLower(text[ti - 1]) and std.ascii.isUpper(text[ti])) {
                    quality += 2.0;
                }

                prev_ti = ti;
                pi += 1;
            }
            ti += 1;
        }

        // Check if entire pattern was matched
        if (pi < pattern.len) {
            return null;
        }

        // Calculate final score using: coverage * 0.3 + quality_ratio * 0.7
        const coverage = @as(f32, @floatFromInt(pattern.len)) / @as(f32, @floatFromInt(text.len));
        const max_quality = 3.0 + 5.0 * @as(f32, @floatFromInt(pattern.len - 1));
        const quality_ratio = @min(1.0, quality / max_quality);
        const score = coverage * 0.3 + quality_ratio * 0.7;

        return MatchResult{
            .score = score,
            .positions = positions_storage[0..len],
        };
    }

    fn toLower(c: u8) u8 {
        return std.ascii.toLower(c);
    }
};

fn isSeparator(c: u8) bool {
    return c == ' ' or c == '_' or c == '-' or c == '/' or c == '.' or c == ':';
}

// ============================================================================
// Tests
// ============================================================================

test "fuzzy match exact string" {
    const result = FuzzyMatcher.match("hello", "hello");
    try std.testing.expect(result != null);
    try std.testing.expect(result.?.score > 0.8);
}

test "fuzzy match case insensitive" {
    const result = FuzzyMatcher.match("HELLO", "hello");
    try std.testing.expect(result != null);
    try std.testing.expect(result.?.score > 0.8);
}

test "fuzzy match simple subsequence" {
    const result = FuzzyMatcher.match("src", "source");
    try std.testing.expect(result != null);
    try std.testing.expect(result.?.positions.len == 3);
}

test "fuzzy match empty pattern" {
    const result = FuzzyMatcher.match("", "hello");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(f32, 0.0), result.?.score);
}

test "fuzzy match empty text empty pattern" {
    const result = FuzzyMatcher.match("", "");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(f32, 0.0), result.?.score);
}

test "fuzzy match empty text non-empty pattern" {
    const result = FuzzyMatcher.match("a", "");
    try std.testing.expectEqual(@as(?MatchResult, null), result);
}

test "fuzzy match no match returns null" {
    const result = FuzzyMatcher.match("abc", "xyz");
    try std.testing.expectEqual(@as(?MatchResult, null), result);
}
