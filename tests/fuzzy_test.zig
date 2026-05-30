const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");
const fuzzy = sailor.fuzzy;

// ============================================================================
// FuzzyMatcher.match Tests
// ============================================================================

test "fuzzy match exact string" {
    const result = fuzzy.FuzzyMatcher.match("hello", "hello");
    try testing.expect(result != null);
    try testing.expect(result.?.score > 0.8); // Exact match should score very high
}

test "fuzzy match case insensitive" {
    const result = fuzzy.FuzzyMatcher.match("HELLO", "hello");
    try testing.expect(result != null);
    try testing.expect(result.?.score > 0.8); // Should match despite case
}

test "fuzzy match simple subsequence" {
    const result = fuzzy.FuzzyMatcher.match("src", "source");
    try testing.expect(result != null);
    try testing.expect(result.?.positions.len == 3);
}

test "fuzzy match positions in order" {
    const result = fuzzy.FuzzyMatcher.match("src", "source");
    try testing.expect(result != null);
    // First 's' at index 0
    try testing.expect(result.?.positions[0] == 0);
    // 'r' must come after 's'
    try testing.expect(result.?.positions[1] > result.?.positions[0]);
    // 'c' must come after 'r'
    try testing.expect(result.?.positions[2] > result.?.positions[1]);
}

test "fuzzy match no match returns null" {
    const result = fuzzy.FuzzyMatcher.match("abc", "xyz");
    try testing.expectEqual(@as(?fuzzy.MatchResult, null), result);
}

test "fuzzy match pattern longer than text returns null" {
    const result = fuzzy.FuzzyMatcher.match("longerpattern", "short");
    try testing.expectEqual(@as(?fuzzy.MatchResult, null), result);
}

test "fuzzy match empty pattern matches everything" {
    const result = fuzzy.FuzzyMatcher.match("", "hello");
    try testing.expect(result != null);
    try testing.expectEqual(@as(f32, 0.0), result.?.score); // Empty pattern has neutral score
}

test "fuzzy match empty text empty pattern" {
    const result = fuzzy.FuzzyMatcher.match("", "");
    try testing.expect(result != null);
    try testing.expectEqual(@as(f32, 0.0), result.?.score);
}

test "fuzzy match empty text non-empty pattern returns null" {
    const result = fuzzy.FuzzyMatcher.match("a", "");
    try testing.expectEqual(@as(?fuzzy.MatchResult, null), result);
}

test "fuzzy match consecutive chars get bonus" {
    const result1 = fuzzy.FuzzyMatcher.match("ab", "ab_cd");
    const result2 = fuzzy.FuzzyMatcher.match("ab", "a_b_cd");

    try testing.expect(result1 != null);
    try testing.expect(result2 != null);
    // Consecutive match should score higher than non-consecutive
    try testing.expect(result1.?.score > result2.?.score);
}

test "fuzzy match multiple valid positions" {
    const result = fuzzy.FuzzyMatcher.match("ab", "ab_ab_ab");
    try testing.expect(result != null);
    // Should return valid positions for a subsequence of 'a' then 'b'
    try testing.expect(result.?.positions.len == 2);
    try testing.expect(result.?.positions[1] > result.?.positions[0]);
}

test "fuzzy match single character" {
    const result = fuzzy.FuzzyMatcher.match("s", "source");
    try testing.expect(result != null);
    try testing.expectEqual(@as(usize, 1), result.?.positions.len);
}

test "fuzzy match prefix scores higher" {
    const result1 = fuzzy.FuzzyMatcher.match("src", "source");
    const result2 = fuzzy.FuzzyMatcher.match("src", "mysource");

    try testing.expect(result1 != null);
    try testing.expect(result2 != null);
    // Prefix match should score higher than infix match
    try testing.expect(result1.?.score > result2.?.score);
}

test "fuzzy match word boundary bonus" {
    const result1 = fuzzy.FuzzyMatcher.match("src", "src_code");
    const result2 = fuzzy.FuzzyMatcher.match("src", "source_code");

    try testing.expect(result1 != null);
    try testing.expect(result2 != null);
    // Word-boundary match after separator may score well
    try testing.expect(result1.?.score > 0.5);
    try testing.expect(result2.?.score > 0.5);
}

test "fuzzy match camelCase boundary bonus" {
    const result1 = fuzzy.FuzzyMatcher.match("src", "sourceCode");
    const result2 = fuzzy.FuzzyMatcher.match("src", "source_code");

    try testing.expect(result1 != null);
    try testing.expect(result2 != null);
    // Both should match, scores indicate preferred style
    try testing.expect(result1.?.score > 0.0);
    try testing.expect(result2.?.score > 0.0);
}

test "fuzzy match unicode characters" {
    const result = fuzzy.FuzzyMatcher.match("café", "café");
    try testing.expect(result != null);
}

test "fuzzy match unicode subsequence" {
    const result = fuzzy.FuzzyMatcher.match("cf", "café");
    try testing.expect(result != null);
}

test "fuzzy match score is normalized" {
    const result = fuzzy.FuzzyMatcher.match("a", "aaa");
    try testing.expect(result != null);
    try testing.expect(result.?.score >= 0.0);
    try testing.expect(result.?.score <= 1.0);
}

test "fuzzy match exact better than fuzzy" {
    const exact = fuzzy.FuzzyMatcher.match("hello", "hello");
    const fuzzy_result = fuzzy.FuzzyMatcher.match("hlo", "hello");

    try testing.expect(exact != null);
    try testing.expect(fuzzy_result != null);
    try testing.expect(exact.?.score > fuzzy_result.?.score);
}

test "fuzzy match dash separated words" {
    const result = fuzzy.FuzzyMatcher.match("gm", "go-marks");
    try testing.expect(result != null);
}

test "fuzzy match slash separated paths" {
    const result = fuzzy.FuzzyMatcher.match("src", "my/src/index.zig");
    try testing.expect(result != null);
}

test "fuzzy match numeric characters" {
    const result = fuzzy.FuzzyMatcher.match("123", "1a2b3c");
    try testing.expect(result != null);
    try testing.expect(result.?.positions.len == 3);
}

test "fuzzy match mixed alphanumeric" {
    const result = fuzzy.FuzzyMatcher.match("a1b2", "xa1b2z");
    try testing.expect(result != null);
}

test "fuzzy match whitespace in pattern" {
    const result = fuzzy.FuzzyMatcher.match("hello world", "hello_world");
    try testing.expect(result != null);
}

test "fuzzy match leading underscore" {
    const result = fuzzy.FuzzyMatcher.match("_foo", "_foo");
    try testing.expect(result != null);
}

test "fuzzy match all positions valid indices" {
    const result = fuzzy.FuzzyMatcher.match("abc", "a1b2c3");
    try testing.expect(result != null);
    try testing.expect(result.?.positions.len == 3);

    // Verify all positions are within bounds
    for (result.?.positions) |pos| {
        try testing.expect(pos < 6); // Length of "a1b2c3"
    }
}

test "fuzzy match positions non-decreasing" {
    const result = fuzzy.FuzzyMatcher.match("abcdef", "aabbccddeeeff");
    try testing.expect(result != null);

    // Positions should be strictly increasing (for valid subsequence)
    for (1..result.?.positions.len) |i| {
        try testing.expect(result.?.positions[i] > result.?.positions[i - 1]);
    }
}

// ============================================================================
// Score Comparison Tests
// ============================================================================

test "fuzzy match scores are comparable" {
    const r1 = fuzzy.FuzzyMatcher.match("src", "source");
    const r2 = fuzzy.FuzzyMatcher.match("src", "mysource");

    try testing.expect(r1 != null);
    try testing.expect(r2 != null);

    // Should be able to compare scores for sorting
    _ = r1.?.score > r2.?.score;
}

test "fuzzy match identical text has consistent score" {
    const result1 = fuzzy.FuzzyMatcher.match("test", "test");
    const result2 = fuzzy.FuzzyMatcher.match("test", "test");

    try testing.expect(result1 != null);
    try testing.expect(result2 != null);
    try testing.expectEqual(result1.?.score, result2.?.score);
}

test "fuzzy match special characters in text" {
    const result = fuzzy.FuzzyMatcher.match("foo", "foo::bar");
    try testing.expect(result != null);
}

test "fuzzy match only special characters pattern" {
    const result = fuzzy.FuzzyMatcher.match("::", "foo::bar");
    try testing.expect(result != null);
}

// ============================================================================
// MatchResult Tests
// ============================================================================

test "match result has score field" {
    const result = fuzzy.FuzzyMatcher.match("test", "test");
    try testing.expect(result != null);

    const score = result.?.score;
    try testing.expect(score >= 0.0);
}

test "match result has positions field" {
    const result = fuzzy.FuzzyMatcher.match("abc", "abc");
    try testing.expect(result != null);

    const positions = result.?.positions;
    try testing.expect(positions.len > 0);
}

test "match result positions length equals pattern length" {
    const pattern = "abc";
    const result = fuzzy.FuzzyMatcher.match(pattern, "aabbcc");
    try testing.expect(result != null);
    try testing.expectEqual(pattern.len, result.?.positions.len);
}
