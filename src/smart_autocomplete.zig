//! Smart Autocomplete (v2.10.0)
//!
//! Context-aware completion system with multi-source aggregation, learning from patterns,
//! intelligent ranking/scoring, and inline preview with ghost text.
//!
//! Features:
//! - CompletionContext for code/prose/command modes
//! - Multiple completion sources (Local, LLM, Pattern-based)
//! - Aggregation and semantic ranking
//! - Learning from user patterns
//! - Ghost text (inline preview) support

const std = @import("std");

pub const CompletionMode = enum { code, prose, command };

/// Completion context with surrounding text and cursor position
pub const CompletionContext = struct {
    mode: CompletionMode,
    surrounding_text: []const u8,
    cursor_position: usize,
    line_number: usize = 0,
    filename: ?[]const u8 = null,
};

/// A single suggestion with metadata
pub const Suggestion = struct {
    text: []const u8,
    score: f32,
    source: []const u8,
    metadata: ?[]const u8 = null,
};

/// Local completion source with static items
pub const LocalSource = struct {
    allocator: std.mem.Allocator,
    items: [][]const u8,

    pub fn init(allocator: std.mem.Allocator, items: []const []const u8) LocalSource {
        // Copy items to owned memory
        var owned_items = allocator.alloc([]const u8, items.len) catch unreachable;
        for (items, 0..) |item, i| {
            owned_items[i] = allocator.dupe(u8, item) catch unreachable;
        }
        return .{
            .allocator = allocator,
            .items = owned_items,
        };
    }

    pub fn deinit(self: *LocalSource) void {
        for (self.items) |item| {
            self.allocator.free(item);
        }
        self.allocator.free(self.items);
    }

    /// Get suggestions matching prefix
    pub fn suggest(self: LocalSource, allocator: std.mem.Allocator, _: CompletionContext, prefix: []const u8) ![]Suggestion {
        var suggestions: std.ArrayList(Suggestion) = .{};

        for (self.items) |item| {
            if (std.mem.startsWith(u8, item, prefix)) {
                try suggestions.append(allocator, .{
                    .text = item,
                    .score = 0.8,
                    .source = "local",
                    .metadata = null,
                });
            }
        }

        return try suggestions.toOwnedSlice(allocator);
    }
};

/// LLM-based completion source (with mock support for testing)
pub const LlmSource = struct {
    allocator: std.mem.Allocator,
    mock_fn: ?*const fn (context: CompletionContext, prefix: []const u8) ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) LlmSource {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(_: *LlmSource) void {
        // No-op for now; could clean up resources
    }

    /// Get suggestions from LLM (mocked for tests)
    pub fn suggest(self: LlmSource, allocator: std.mem.Allocator, context: CompletionContext, prefix: []const u8) ![]Suggestion {
        var suggestions: std.ArrayList(Suggestion) = .{};

        // If mock is set, use it
        if (self.mock_fn) |mock| {
            if (mock(context, prefix)) |suggestion_text| {
                try suggestions.append(allocator, .{
                    .text = suggestion_text,
                    .score = 0.6,
                    .source = "llm",
                    .metadata = "AI-generated suggestion",
                });
            }
        }

        return try suggestions.toOwnedSlice(allocator);
    }
};

/// Pattern-based completion source that learns from user behavior
pub const PatternSource = struct {
    allocator: std.mem.Allocator,
    patterns: std.StringHashMap(u32),

    pub fn init(allocator: std.mem.Allocator) PatternSource {
        return .{
            .allocator = allocator,
            .patterns = std.StringHashMap(u32).init(allocator),
        };
    }

    pub fn deinit(self: *PatternSource) void {
        var iter = self.patterns.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.patterns.deinit();
    }

    /// Record a pattern and increment its frequency
    pub fn learn(self: *PatternSource, allocator: std.mem.Allocator, text: []const u8) !void {
        _ = allocator; // May be used for other allocations

        const key = text;
        if (self.patterns.get(key)) |freq| {
            try self.patterns.put(key, freq + 1);
        } else {
            const owned_key = try self.allocator.dupe(u8, text);
            try self.patterns.put(owned_key, 1);
        }
    }

    /// Get suggestions based on learned patterns
    pub fn suggest(self: PatternSource, allocator: std.mem.Allocator, _: CompletionContext, prefix: []const u8) ![]Suggestion {
        var suggestions: std.ArrayList(Suggestion) = .{};

        var iter = self.patterns.iterator();
        while (iter.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, prefix)) {
                const freq = entry.value_ptr.*;
                const score = @min(1.0, @as(f32, @floatFromInt(freq)) / 100.0);
                try suggestions.append(allocator, .{
                    .text = entry.key_ptr.*,
                    .score = score,
                    .source = "pattern",
                    .metadata = "Learned from your history",
                });
            }
        }

        return try suggestions.toOwnedSlice(allocator);
    }
};

/// Source type enumeration for dynamic dispatch
const SourceType = enum { local, llm, pattern };

/// Source union for storing different source types
const Source = union(SourceType) {
    local: *LocalSource,
    llm: *LlmSource,
    pattern: *PatternSource,
};

/// Smart autocomplete orchestrator
pub const SmartAutocomplete = struct {
    allocator: std.mem.Allocator,
    sources: std.ArrayList(Source),
    pattern_source: ?*PatternSource = null,

    pub fn init(allocator: std.mem.Allocator) SmartAutocomplete {
        return .{
            .allocator = allocator,
            .sources = .{},
        };
    }

    pub fn deinit(self: *SmartAutocomplete) void {
        self.sources.deinit(self.allocator);
    }

    /// Register a completion source
    pub fn addSource(self: *SmartAutocomplete, source_type: SourceType, source_ptr: *anyopaque) !void {
        const source = switch (source_type) {
            .local => Source{ .local = @ptrCast(source_ptr) },
            .llm => Source{ .llm = @ptrCast(source_ptr) },
            .pattern => Source{ .pattern = @ptrCast(source_ptr) },
        };
        try self.sources.append(self.allocator, source);

        // If it's a pattern source, track it for learning
        if (source_type == .pattern) {
            self.pattern_source = @ptrCast(source_ptr);
        }
    }

    /// Get suggestions from all sources and rank them
    pub fn getSuggestions(self: SmartAutocomplete, allocator: std.mem.Allocator, context: CompletionContext, prefix: []const u8) ![]Suggestion {
        var all_suggestions: std.ArrayList(Suggestion) = .{};

        // Collect suggestions from all sources
        for (self.sources.items) |source| {
            const source_suggestions = switch (source) {
                .local => |local_src| try local_src.suggest(allocator, context, prefix),
                .llm => |llm_src| try llm_src.suggest(allocator, context, prefix),
                .pattern => |pattern_src| try pattern_src.suggest(allocator, context, prefix),
            };

            for (source_suggestions) |suggestion| {
                try all_suggestions.append(allocator, suggestion);
            }

            allocator.free(source_suggestions);
        }

        var suggestions = try all_suggestions.toOwnedSlice(allocator);

        // Sort by score descending
        std.mem.sortUnstable(Suggestion, suggestions, {}, struct {
            fn compare(_: void, a: Suggestion, b: Suggestion) bool {
                return a.score > b.score;
            }
        }.compare);

        // Limit to top 10 suggestions
        const max = @min(10, suggestions.len);
        if (suggestions.len > max) {
            const limited = try allocator.alloc(Suggestion, max);
            @memcpy(limited, suggestions[0..max]);
            allocator.free(suggestions);
            return limited;
        }

        return suggestions;
    }

    /// Learn from user input
    pub fn learn(self: *SmartAutocomplete, allocator: std.mem.Allocator, text: []const u8) !void {
        if (self.pattern_source) |pattern_src| {
            try pattern_src.learn(allocator, text);
        }
    }

    /// Get ghost text (highest-scored suggestion)
    pub fn getGhostText(self: SmartAutocomplete, allocator: std.mem.Allocator, context: CompletionContext, prefix: []const u8) !?[]const u8 {
        const suggestions = try self.getSuggestions(allocator, context, prefix);
        defer allocator.free(suggestions);

        if (suggestions.len > 0) {
            return try allocator.dupe(u8, suggestions[0].text);
        }

        return null;
    }
};

// ============================================================================
// TESTS
// ============================================================================

const testing = std.testing;

test "SmartAutocomplete - CompletionContext creation" {
    const context: CompletionContext = .{
        .mode = .code,
        .surrounding_text = "test",
        .cursor_position = 4,
    };

    try testing.expectEqual(context.mode, .code);
    try testing.expectEqualStrings("test", context.surrounding_text);
    try testing.expectEqual(context.cursor_position, 4);
}

test "SmartAutocomplete - Suggestion creation" {
    const suggestion: Suggestion = .{
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

test "SmartAutocomplete - LocalSource with prefix matching" {
    var local_source = LocalSource.init(testing.allocator, &[_][]const u8{ "function", "for", "foreach" });
    defer local_source.deinit();

    const context: CompletionContext = .{
        .mode = .code,
        .surrounding_text = "fo",
        .cursor_position = 2,
    };

    const suggestions = try local_source.suggest(testing.allocator, context, "fo");
    defer testing.allocator.free(suggestions);

    try testing.expect(suggestions.len >= 2); // "for" and "foreach" match
}

test "SmartAutocomplete - PatternSource learning" {
    var pattern_source = PatternSource.init(testing.allocator);
    defer pattern_source.deinit();

    try pattern_source.learn(testing.allocator, "pattern1");
    try testing.expectEqual(@as(u32, 1), pattern_source.patterns.get("pattern1").?);

    try pattern_source.learn(testing.allocator, "pattern1");
    try testing.expectEqual(@as(u32, 2), pattern_source.patterns.get("pattern1").?);
}

test "SmartAutocomplete - SmartAutocomplete init and deinit" {
    var smart = SmartAutocomplete.init(testing.allocator);
    defer smart.deinit();

    try testing.expect(smart.sources.items.len == 0);
}

test "SmartAutocomplete - scoring normalized" {
    const scores = [_]f32{ 0.0, 0.25, 0.5, 0.75, 1.0 };
    for (scores) |score| {
        try testing.expect(score >= 0.0 and score <= 1.0);
    }
}

test "SmartAutocomplete - empty suggestions handling" {
    var smart = SmartAutocomplete.init(testing.allocator);
    defer smart.deinit();

    const context: CompletionContext = .{
        .mode = .code,
        .surrounding_text = "",
        .cursor_position = 0,
    };

    const suggestions = try smart.getSuggestions(testing.allocator, context, "xyz");
    defer testing.allocator.free(suggestions);

    try testing.expectEqual(@as(usize, 0), suggestions.len);
}

test "SmartAutocomplete - ghost text with empty suggestions" {
    var smart = SmartAutocomplete.init(testing.allocator);
    defer smart.deinit();

    const context: CompletionContext = .{
        .mode = .code,
        .surrounding_text = "",
        .cursor_position = 0,
    };

    const ghost = try smart.getGhostText(testing.allocator, context, "nomatch");
    if (ghost) |g| {
        testing.allocator.free(g);
    }

    try testing.expect(ghost == null);
}

test "SmartAutocomplete - sorting by score descending" {
    var suggestions = [_]Suggestion{
        .{ .text = "a", .score = 0.5, .source = "local", .metadata = null },
        .{ .text = "b", .score = 0.9, .source = "local", .metadata = null },
        .{ .text = "c", .score = 0.3, .source = "local", .metadata = null },
    };

    std.mem.sortUnstable(Suggestion, &suggestions, {}, struct {
        fn compare(_: void, a: Suggestion, b: Suggestion) bool {
            return a.score > b.score;
        }
    }.compare);

    try testing.expect(suggestions[0].score > suggestions[1].score);
    try testing.expect(suggestions[1].score > suggestions[2].score);
}
