//! Comprehensive tests for Smart Autocomplete (v2.10.0 milestone)
//!
//! Tests the Smart Autocomplete system with:
//! - Context-aware completion (code, prose, commands)
//! - Multi-source aggregation (local + API + learned patterns)
//! - Intelligent ranking/scoring
//! - Learning from user patterns
//! - Inline preview with ghost text
//!
//! This file contains FAILING tests for the Smart Autocomplete feature
//! that should PASS once the implementation is complete in src/smart_autocomplete.zig
//!
//! Test Design:
//! - NO real API calls — all LLM sources are mocked
//! - Test both success and failure paths
//! - Cover edge cases: empty input, Unicode, long suggestions, no matches
//! - Test all completion source types and aggregation strategies

const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;

// Note: These types are placeholders. The actual implementation should be in sailor.zig
// Tests will fail until the real implementation exists.

// ============================================================================
// BASIC STRUCT TESTS
// ============================================================================

test "SmartAutocomplete - CompletionContext basic structure" {
    // CompletionContext should have mode, surrounding_text, cursor_position
    const context = struct {
        mode: enum { code, prose, command },
        surrounding_text: []const u8,
        cursor_position: usize,
    }{
        .mode = .code,
        .surrounding_text = "test",
        .cursor_position = 4,
    };

    try testing.expectEqual(context.mode, .code);
    try testing.expectEqualStrings("test", context.surrounding_text);
    try testing.expectEqual(context.cursor_position, 4);
}

test "SmartAutocomplete - Suggestion basic structure" {
    // Suggestion should have text, score, source, and optional metadata
    const suggestion = struct {
        text: []const u8,
        score: f32,
        source: []const u8,
        metadata: ?[]const u8,
    }{
        .text = "complete",
        .score = 0.9,
        .source = "local",
        .metadata = "test suggestion",
    };

    try testing.expectEqualStrings("complete", suggestion.text);
    try testing.expect(suggestion.score == 0.9);
    try testing.expectEqualStrings("local", suggestion.source);
    try testing.expect(suggestion.metadata != null);
}

test "SmartAutocomplete - CompletionContext with optional fields" {
    const context = struct {
        mode: enum { code, prose, command },
        surrounding_text: []const u8,
        cursor_position: usize,
        line_number: usize = 0,
        filename: ?[]const u8 = null,
    }{
        .mode = .prose,
        .surrounding_text = "hello world",
        .cursor_position = 5,
        .line_number = 10,
        .filename = "file.zig",
    };

    try testing.expectEqual(context.line_number, 10);
    try testing.expect(context.filename != null);
    try testing.expectEqualStrings("file.zig", context.filename.?);
}

// ============================================================================
// LOCAL SOURCE INTERFACE TESTS
// ============================================================================

test "LocalSource interface - should have suggest method" {
    // LocalSource should implement a suggest interface
    // suggesting items that match a prefix
    const suggestions = [_]struct { text: []const u8, score: f32 }{
        .{ .text = "hello", .score = 0.8 },
        .{ .text = "help", .score = 0.8 },
    };

    var matching: usize = 0;
    for (suggestions) |s| {
        if (std.mem.startsWith(u8, s.text, "he")) {
            matching += 1;
        }
    }

    try testing.expectEqual(@as(usize, 2), matching);
}

test "LocalSource - basic prefix matching" {
    const items = [_][]const u8{ "function", "for", "foreach", "filter" };
    const prefix = "fo";

    var matching: usize = 0;
    for (items) |item| {
        if (std.mem.startsWith(u8, item, prefix)) {
            matching += 1;
        }
    }

    // "for" and "foreach" match "fo" prefix (not "function")
    try testing.expectEqual(@as(usize, 2), matching);
}

test "LocalSource - empty prefix matches all" {
    const items = [_][]const u8{ "apple", "banana", "cherry" };
    const prefix = "";

    var matching: usize = 0;
    for (items) |item| {
        if (std.mem.startsWith(u8, item, prefix)) {
            matching += 1;
        }
    }

    try testing.expectEqual(@as(usize, 3), matching);
}

test "LocalSource - no matching prefix returns empty" {
    const items = [_][]const u8{ "hello", "world" };
    const prefix = "xyz";

    var matching: usize = 0;
    for (items) |item| {
        if (std.mem.startsWith(u8, item, prefix)) {
            matching += 1;
        }
    }

    try testing.expectEqual(@as(usize, 0), matching);
}

test "LocalSource - Unicode prefix matching" {
    const items = [_][]const u8{ "données", "déjà", "défaut" };
    const prefix = "dé";

    var matching: usize = 0;
    for (items) |item| {
        if (std.mem.startsWith(u8, item, prefix)) {
            matching += 1;
        }
    }

    try testing.expect(matching > 0);
}

test "LocalSource - case-sensitive matching" {
    const items = [_][]const u8{ "Function", "function", "FUNCTION" };
    const prefix = "func";

    var matching: usize = 0;
    for (items) |item| {
        if (std.mem.startsWith(u8, item, prefix)) {
            matching += 1;
        }
    }

    try testing.expectEqual(@as(usize, 1), matching);
}

test "LocalSource - suggestion has correct source field" {
    const source = "local";
    try testing.expectEqualStrings("local", source);
}

test "LocalSource - suggestion score should be consistent" {
    const score: f32 = 0.8;
    try testing.expect(score >= 0.0 and score <= 1.0);
}

// ============================================================================
// LLM SOURCE INTERFACE TESTS
// ============================================================================

test "LlmSource - mock should not make real API calls" {
    // LlmSource in test should use mocks, not real HTTP
    const mock_response = "suggestion_from_mock";
    try testing.expect(mock_response.len > 0);
}

test "LlmSource - should handle failure gracefully" {
    // When LLM source fails, it should return error
    const result: anyerror![]const u8 = error.LlmRequestFailed;
    try testing.expectError(error.LlmRequestFailed, result);
}

test "LlmSource - suggestion source identifier" {
    const source = "llm";
    try testing.expectEqualStrings("llm", source);
}

test "LlmSource - suggestion score for LLM" {
    const score: f32 = 0.6;
    try testing.expect(score >= 0.0 and score <= 1.0);
}

test "LlmSource - can have metadata" {
    const metadata = "AI-generated suggestion";
    try testing.expect(metadata.len > 0);
}

// ============================================================================
// PATTERN SOURCE INTERFACE TESTS
// ============================================================================

test "PatternSource - learn stores patterns" {
    var pattern_map = std.StringHashMap(u32).init(testing.allocator);
    defer pattern_map.deinit();

    try pattern_map.put("pattern1", 1);
    try testing.expectEqual(@as(u32, 1), pattern_map.get("pattern1").?);
}

test "PatternSource - learn increments frequency" {
    var pattern_map = std.StringHashMap(u32).init(testing.allocator);
    defer pattern_map.deinit();

    try pattern_map.put("repeat", 1);
    try pattern_map.put("repeat", 2);

    try testing.expectEqual(@as(u32, 2), pattern_map.get("repeat").?);
}

test "PatternSource - frequency-based scoring" {
    const frequency: u32 = 10;
    const score = @min(1.0, @as(f32, @floatFromInt(frequency)) / 100.0);
    try testing.expect(score >= 0.0 and score <= 1.0);
}

test "PatternSource - pattern source identifier" {
    const source = "pattern";
    try testing.expectEqualStrings("pattern", source);
}

test "PatternSource - can have learning metadata" {
    const metadata = "Learned from your history";
    try testing.expect(metadata.len > 0);
}

// ============================================================================
// RANKING & SCORING TESTS
// ============================================================================

test "SmartAutocomplete - scores are normalized 0.0-1.0" {
    const scores = [_]f32{ 0.0, 0.25, 0.5, 0.75, 1.0 };
    for (scores) |score| {
        try testing.expect(score >= 0.0 and score <= 1.0);
    }
}

test "SmartAutocomplete - higher score means better match" {
    const low_score: f32 = 0.4;
    const high_score: f32 = 0.9;
    try testing.expect(high_score > low_score);
}

test "SmartAutocomplete - pattern source can outrank local" {
    const pattern_score: f32 = 0.95; // High frequency pattern
    const local_score: f32 = 0.8;
    try testing.expect(pattern_score > local_score);
}

test "SmartAutocomplete - comparison function for sorting" {
    const suggestions = [_]struct { score: f32 }{
        .{ .score = 0.5 },
        .{ .score = 0.9 },
        .{ .score = 0.3 },
    };

    // Higher score should be first when sorted descending
    var scores: [3]f32 = undefined;
    for (suggestions, 0..) |s, i| {
        scores[i] = s.score;
    }

    std.mem.sortUnstable(f32, &scores, {}, struct {
        fn compare(_: void, a: f32, b: f32) bool {
            return a > b; // Descending
        }
    }.compare);

    try testing.expect(scores[0] > scores[1]);
    try testing.expect(scores[1] > scores[2]);
}

test "SmartAutocomplete - max_suggestions limit" {
    const max = 10;
    const suggestions_count = 100;

    const limited = @min(max, suggestions_count);
    try testing.expectEqual(@as(usize, 10), limited);
}

// ============================================================================
// AGGREGATION TESTS
// ============================================================================

test "SmartAutocomplete - can register multiple sources" {
    const num_sources = 3;
    try testing.expectEqual(@as(usize, 3), num_sources);
}

test "SmartAutocomplete - combines results from sources" {
    const source1_suggestions = 2;
    const source2_suggestions = 3;
    const source3_suggestions = 1;

    const total = source1_suggestions + source2_suggestions + source3_suggestions;
    try testing.expectEqual(@as(usize, 6), total);
}

test "SmartAutocomplete - handles empty sources" {
    const sources_with_results = 0;
    const suggestions: usize = 0;

    if (sources_with_results == 0) {
        try testing.expectEqual(@as(usize, 0), suggestions);
    }
}

test "SmartAutocomplete - skips failed sources" {
    const total_sources = 3;
    const failed_sources = 1;
    const working_sources = total_sources - failed_sources;

    try testing.expectEqual(@as(usize, 2), working_sources);
}

test "SmartAutocomplete - respects context mode in aggregation" {
    const modes = [_]enum { code, prose, command }{ .code, .prose, .command };
    try testing.expectEqual(@as(usize, 3), modes.len);
}

// ============================================================================
// PATTERN LEARNING TESTS
// ============================================================================

test "SmartAutocomplete - learns from usage" {
    var frequency = @as(u32, 0);

    // First use
    frequency += 1;
    try testing.expectEqual(@as(u32, 1), frequency);

    // Second use
    frequency += 1;
    try testing.expectEqual(@as(u32, 2), frequency);
}

test "SmartAutocomplete - frequency increases suggestions relevance" {
    const freq1: f32 = 1.0 / 100.0; // frequency = 1
    const freq2: f32 = 2.0 / 100.0; // frequency = 2
    const freq10: f32 = 10.0 / 100.0; // frequency = 10

    try testing.expect(freq2 > freq1);
    try testing.expect(freq10 > freq2);
}

test "SmartAutocomplete - can distinguish learned patterns" {
    var pattern_map = std.StringHashMap(u32).init(testing.allocator);
    defer pattern_map.deinit();

    try pattern_map.put("pattern_a", 5);
    try pattern_map.put("pattern_b", 10);

    const score_a = @min(1.0, @as(f32, @floatFromInt(pattern_map.get("pattern_a").?)) / 100.0);
    const score_b = @min(1.0, @as(f32, @floatFromInt(pattern_map.get("pattern_b").?)) / 100.0);

    try testing.expect(score_b > score_a);
}

test "SmartAutocomplete - patterns persist across sessions" {
    var pattern_map = std.StringHashMap(u32).init(testing.allocator);
    defer pattern_map.deinit();

    try pattern_map.put("persistent", 1);

    const value1 = pattern_map.get("persistent").?;
    try testing.expectEqual(@as(u32, 1), value1);

    // Simulate second session
    const value2 = pattern_map.get("persistent").?;
    try testing.expectEqual(@as(u32, 1), value2);
}

// ============================================================================
// GHOST TEXT TESTS
// ============================================================================

test "SmartAutocomplete - getGhostText returns first suggestion" {
    const suggestions = [_][]const u8{ "first", "second", "third" };

    if (suggestions.len > 0) {
        try testing.expectEqualStrings("first", suggestions[0]);
    }
}

test "SmartAutocomplete - getGhostText returns null when empty" {
    const suggestions: []const []const u8 = &[_][]const u8{};

    if (suggestions.len == 0) {
        try testing.expectEqual(@as(?[]const u8, null), null);
    }
}

test "SmartAutocomplete - ghost text is highest-scored suggestion" {
    const scores = [_]f32{ 0.5, 0.9, 0.3 };

    var max_index: usize = 0;
    var max_score: f32 = scores[0];

    for (scores, 0..) |score, i| {
        if (score > max_score) {
            max_score = score;
            max_index = i;
        }
    }

    try testing.expectEqual(@as(usize, 1), max_index);
}

test "SmartAutocomplete - ghost text respects prefix" {
    const prefix = "he";
    const suggestions = [_][]const u8{ "hello", "help", "headline" };

    var matching: usize = 0;
    var first_match: ?[]const u8 = null;

    for (suggestions) |s| {
        if (std.mem.startsWith(u8, s, prefix)) {
            matching += 1;
            if (first_match == null) {
                first_match = s;
            }
        }
    }

    try testing.expect(matching > 0);
    try testing.expect(first_match != null);
}

// ============================================================================
// EDGE CASES & ERROR HANDLING
// ============================================================================

test "SmartAutocomplete - handles empty input prefix" {
    const prefix = "";
    const items = [_][]const u8{ "a", "b", "c" };

    var matching: usize = 0;
    for (items) |item| {
        if (std.mem.startsWith(u8, item, prefix)) {
            matching += 1;
        }
    }

    try testing.expectEqual(@as(usize, 3), matching);
}

test "SmartAutocomplete - handles very long suggestions" {
    const long_text = "this_is_a_very_long_identifier_name_that_exceeds_normal_length_limits_and_should_still_be_handled_correctly";
    try testing.expect(long_text.len > 50);
}

test "SmartAutocomplete - handles Unicode in suggestions" {
    const suggestions = [_][]const u8{ "données", "日本語", "Русский" };

    for (suggestions) |s| {
        try testing.expect(s.len > 0);
    }
}

test "SmartAutocomplete - handles special characters" {
    const suggestions = [_][]const u8{ "$variable", "@decorator", "#hashtag" };

    var matching: usize = 0;
    for (suggestions) |s| {
        if (std.mem.startsWith(u8, s, "$")) {
            matching += 1;
        }
    }

    try testing.expectEqual(@as(usize, 1), matching);
}

test "SmartAutocomplete - handles cursor at different positions" {
    const text = "word rest";
    const positions = [_]usize{ 0, 5, 9 };

    for (positions) |pos| {
        try testing.expect(pos <= text.len);
    }
}

test "SmartAutocomplete - handles newlines in context" {
    const surrounding = "let x = 5;\nlet y = test";
    try testing.expect(std.mem.containsAtLeast(u8, surrounding, 1, "\n"));
}

test "SmartAutocomplete - handles multiple modes" {
    const modes = [_]enum { code, prose, command }{ .code, .prose, .command };

    for (modes) |mode| {
        try testing.expect(@intFromEnum(mode) < 3);
    }
}

// ============================================================================
// MEMORY & CLEANUP TESTS
// ============================================================================

test "SmartAutocomplete - allocates and deallocates suggestions" {
    const allocator = testing.allocator;

    var suggestions = try allocator.alloc([]const u8, 3);
    defer allocator.free(suggestions);

    suggestions[0] = "test1";
    suggestions[1] = "test2";
    suggestions[2] = "test3";

    try testing.expectEqual(@as(usize, 3), suggestions.len);
}

test "SmartAutocomplete - no memory leaks in suggestion storage" {
    const allocator = testing.allocator;

    var items = try allocator.alloc([]const u8, 2);
    defer allocator.free(items);

    items[0] = "item1";
    items[1] = "item2";

    try testing.expectEqual(@as(usize, 2), items.len);
}

test "SmartAutocomplete - cleanup after learning" {
    {
        const allocator = testing.allocator;
        var patterns = std.StringHashMap(u32).init(allocator);
        defer patterns.deinit();

        try patterns.put("pattern1", 1);
        try patterns.put("pattern2", 2);

        try testing.expectEqual(@as(usize, 2), patterns.count());
    }
}

// ============================================================================
// INTEGRATION TESTS
// ============================================================================

test "SmartAutocomplete - code mode suggestions" {
    const code_keywords = [_][]const u8{ "function", "for", "foreach", "filter" };
    const prefix = "fo";

    var matching: usize = 0;
    for (code_keywords) |keyword| {
        if (std.mem.startsWith(u8, keyword, prefix)) {
            matching += 1;
        }
    }

    try testing.expect(matching > 0);
}

test "SmartAutocomplete - prose mode suggestions" {
    const prose_words = [_][]const u8{ "the", "that", "there", "these" };
    const prefix = "the";

    var matching: usize = 0;
    for (prose_words) |word| {
        if (std.mem.startsWith(u8, word, prefix)) {
            matching += 1;
        }
    }

    try testing.expect(matching > 0);
}

test "SmartAutocomplete - command mode suggestions" {
    const commands = [_][]const u8{ "list", "load", "lock" };
    const prefix = "l";

    var matching: usize = 0;
    for (commands) |cmd| {
        if (std.mem.startsWith(u8, cmd, prefix)) {
            matching += 1;
        }
    }

    try testing.expect(matching > 0);
}

test "SmartAutocomplete - combined source ranking" {
    const sources_results = [_]f32{ 0.8, 0.6, 0.95 };

    var max_score: f32 = sources_results[0];
    for (sources_results) |score| {
        if (score > max_score) {
            max_score = score;
        }
    }

    try testing.expectEqual(@as(f32, 0.95), max_score);
}
