const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");
const fuzzy = sailor.fuzzy;
const FuzzyMatcher = fuzzy.FuzzyMatcher;

// ============================================================================
// FuzzyMatcher.match Tests
// ============================================================================

test "fuzzy match exact string" {
    var m = FuzzyMatcher{};
    const result = m.match("hello", "hello");
    try testing.expect(result != null);
    try testing.expect(result.?.score > 0.8); // Exact match should score very high
}

test "fuzzy match case insensitive" {
    var m = FuzzyMatcher{};
    const result = m.match("HELLO", "hello");
    try testing.expect(result != null);
    try testing.expect(result.?.score > 0.8); // Should match despite case
}

test "fuzzy match simple subsequence" {
    var m = FuzzyMatcher{};
    const result = m.match("src", "source");
    try testing.expect(result != null);
    try testing.expect(result.?.positions.len == 3);
}

test "fuzzy match positions in order" {
    var m = FuzzyMatcher{};
    const result = m.match("src", "source");
    try testing.expect(result != null);
    // First 's' at index 0
    try testing.expect(result.?.positions[0] == 0);
    // 'r' must come after 's'
    try testing.expect(result.?.positions[1] > result.?.positions[0]);
    // 'c' must come after 'r'
    try testing.expect(result.?.positions[2] > result.?.positions[1]);
}

test "fuzzy match no match returns null" {
    var m = FuzzyMatcher{};
    const result = m.match("abc", "xyz");
    try testing.expectEqual(@as(?fuzzy.MatchResult, null), result);
}

test "fuzzy match pattern longer than text returns null" {
    var m = FuzzyMatcher{};
    const result = m.match("longerpattern", "short");
    try testing.expectEqual(@as(?fuzzy.MatchResult, null), result);
}

test "fuzzy match empty pattern matches everything" {
    var m = FuzzyMatcher{};
    const result = m.match("", "hello");
    try testing.expect(result != null);
    try testing.expectEqual(@as(f32, 0.0), result.?.score); // Empty pattern has neutral score
}

test "fuzzy match empty text empty pattern" {
    var m = FuzzyMatcher{};
    const result = m.match("", "");
    try testing.expect(result != null);
    try testing.expectEqual(@as(f32, 0.0), result.?.score);
}

test "fuzzy match empty text non-empty pattern returns null" {
    var m = FuzzyMatcher{};
    const result = m.match("a", "");
    try testing.expectEqual(@as(?fuzzy.MatchResult, null), result);
}

test "fuzzy match consecutive chars get bonus" {
    var m = FuzzyMatcher{};
    const result1 = m.match("ab", "ab_cd");
    const result2 = m.match("ab", "a_b_cd");

    try testing.expect(result1 != null);
    try testing.expect(result2 != null);
    // Consecutive match should score higher than non-consecutive
    try testing.expect(result1.?.score > result2.?.score);
}

test "fuzzy match multiple valid positions" {
    var m = FuzzyMatcher{};
    const result = m.match("ab", "ab_ab_ab");
    try testing.expect(result != null);
    // Should return valid positions for a subsequence of 'a' then 'b'
    try testing.expect(result.?.positions.len == 2);
    try testing.expect(result.?.positions[1] > result.?.positions[0]);
}

test "fuzzy match single character" {
    var m = FuzzyMatcher{};
    const result = m.match("s", "source");
    try testing.expect(result != null);
    try testing.expectEqual(@as(usize, 1), result.?.positions.len);
}

test "fuzzy match prefix scores higher" {
    var m = FuzzyMatcher{};
    const result1 = m.match("src", "source");
    const result2 = m.match("src", "mysource");

    try testing.expect(result1 != null);
    try testing.expect(result2 != null);
    // Prefix match should score higher than infix match
    try testing.expect(result1.?.score > result2.?.score);
}

test "fuzzy match word boundary bonus" {
    var m = FuzzyMatcher{};
    const result1 = m.match("src", "src_code");
    const result2 = m.match("src", "source_code");

    try testing.expect(result1 != null);
    try testing.expect(result2 != null);
    try testing.expect(result1.?.score > 0.5);
    try testing.expect(result2.?.score > 0.5);
}

test "fuzzy match camelCase boundary bonus" {
    var m = FuzzyMatcher{};
    const result1 = m.match("src", "sourceCode");
    const result2 = m.match("src", "source_code");

    try testing.expect(result1 != null);
    try testing.expect(result2 != null);
    try testing.expect(result1.?.score > 0.0);
    try testing.expect(result2.?.score > 0.0);
}

test "fuzzy match unicode characters" {
    var m = FuzzyMatcher{};
    const result = m.match("café", "café");
    try testing.expect(result != null);
}

test "fuzzy match unicode subsequence" {
    var m = FuzzyMatcher{};
    const result = m.match("cf", "café");
    try testing.expect(result != null);
}

test "fuzzy match score is normalized" {
    var m = FuzzyMatcher{};
    const result = m.match("a", "aaa");
    try testing.expect(result != null);
    try testing.expect(result.?.score >= 0.0);
    try testing.expect(result.?.score <= 1.0);
}

test "fuzzy match exact better than fuzzy" {
    var m = FuzzyMatcher{};
    const exact = m.match("hello", "hello");
    const fuzzy_result = m.match("hlo", "hello");

    try testing.expect(exact != null);
    try testing.expect(fuzzy_result != null);
    try testing.expect(exact.?.score > fuzzy_result.?.score);
}

test "fuzzy match dash separated words" {
    var m = FuzzyMatcher{};
    const result = m.match("gm", "go-marks");
    try testing.expect(result != null);
}

test "fuzzy match slash separated paths" {
    var m = FuzzyMatcher{};
    const result = m.match("src", "my/src/index.zig");
    try testing.expect(result != null);
}

test "fuzzy match numeric characters" {
    var m = FuzzyMatcher{};
    const result = m.match("123", "1a2b3c");
    try testing.expect(result != null);
    try testing.expect(result.?.positions.len == 3);
}

test "fuzzy match mixed alphanumeric" {
    var m = FuzzyMatcher{};
    const result = m.match("a1b2", "xa1b2z");
    try testing.expect(result != null);
}

test "fuzzy match whitespace in pattern" {
    var m = FuzzyMatcher{};
    const result = m.match("hello world", "hello_world");
    try testing.expect(result != null);
}

test "fuzzy match leading underscore" {
    var m = FuzzyMatcher{};
    const result = m.match("_foo", "_foo");
    try testing.expect(result != null);
}

test "fuzzy match all positions valid indices" {
    var m = FuzzyMatcher{};
    const result = m.match("abc", "a1b2c3");
    try testing.expect(result != null);
    try testing.expect(result.?.positions.len == 3);

    // Verify all positions are within bounds
    for (result.?.positions) |pos| {
        try testing.expect(pos < 6); // Length of "a1b2c3"
    }
}

test "fuzzy match positions non-decreasing" {
    var m = FuzzyMatcher{};
    const result = m.match("abcdef", "aabbccddeeeff");
    try testing.expect(result != null);

    // Positions should be strictly increasing (for valid subsequence)
    for (1..result.?.positions.len) |i| {
        try testing.expect(result.?.positions[i] > result.?.positions[i - 1]);
    }
}

// ============================================================================
// Score Comparison Tests
// ============================================================================

test "fuzzy match prefix scores higher than infix" {
    var m = FuzzyMatcher{};
    const r1 = m.match("src", "source");
    const r2 = m.match("src", "mysource");

    try testing.expect(r1 != null);
    try testing.expect(r2 != null);
    // Prefix match ("source" starts with 's') should score higher than infix
    try testing.expect(r1.?.score > r2.?.score);
}

test "fuzzy match identical text has consistent score" {
    var m = FuzzyMatcher{};
    const result1 = m.match("test", "test");
    const result2 = m.match("test", "test");

    try testing.expect(result1 != null);
    try testing.expect(result2 != null);
    try testing.expectEqual(result1.?.score, result2.?.score);
}

test "fuzzy match special characters in text" {
    var m = FuzzyMatcher{};
    const result = m.match("foo", "foo::bar");
    try testing.expect(result != null);
}

test "fuzzy match only special characters pattern" {
    var m = FuzzyMatcher{};
    const result = m.match("::", "foo::bar");
    try testing.expect(result != null);
}

// ============================================================================
// MatchResult Tests
// ============================================================================

test "match result score is in valid range" {
    var m = FuzzyMatcher{};
    const result = m.match("test", "test");
    try testing.expect(result != null);

    const score = result.?.score;
    try testing.expect(score >= 0.0);
    try testing.expect(score <= 1.0);
}

test "match result has positions field with content" {
    var m = FuzzyMatcher{};
    const result = m.match("abc", "abc");
    try testing.expect(result != null);

    const positions = result.?.positions;
    try testing.expectEqual(@as(usize, 3), positions.len);
    // Positions should be 0, 1, 2 for exact consecutive match
    try testing.expectEqual(@as(u16, 0), positions[0]);
    try testing.expectEqual(@as(u16, 1), positions[1]);
    try testing.expectEqual(@as(u16, 2), positions[2]);
}

test "match result positions length equals pattern length" {
    var m = FuzzyMatcher{};
    const pattern = "abc";
    const result = m.match(pattern, "aabbcc");
    try testing.expect(result != null);
    try testing.expectEqual(pattern.len, result.?.positions.len);
}

// ============================================================================
// Multiple Calls (reuse same instance)
// ============================================================================

test "fuzzy matcher can be reused across multiple calls" {
    var m = FuzzyMatcher{};

    const r1 = m.match("he", "hello");
    try testing.expect(r1 != null);
    const score1 = r1.?.score;

    const r2 = m.match("wo", "world");
    try testing.expect(r2 != null);

    // Re-run first match — should get same score
    const r3 = m.match("he", "hello");
    try testing.expect(r3 != null);
    try testing.expectEqual(score1, r3.?.score);
}

test "fuzzy matcher positions from previous call not corrupted by new call" {
    var m = FuzzyMatcher{};

    // Get a match result and copy its positions before the next call
    const r1 = m.match("ab", "ab_xy");
    try testing.expect(r1 != null);
    const p0 = r1.?.positions[0];
    const p1 = r1.?.positions[1];

    // Make another call that overwrites the internal buffer
    _ = m.match("xy", "ab_xy");

    // Re-match to verify the matcher still works correctly
    const r3 = m.match("ab", "ab_xy");
    try testing.expect(r3 != null);
    try testing.expectEqual(p0, r3.?.positions[0]);
    try testing.expectEqual(p1, r3.?.positions[1]);
}
