//! Tests for IncrementalLayout — wrapper that automatically caches layout.split() results
//! Tests validate cache hits, cache misses, frame advancement, and memory safety.

const std = @import("std");
const sailor = @import("sailor");
const layout = sailor.tui.layout;
const layout_cache = sailor.tui.layout_cache;

const Rect = layout.Rect;
const Constraint = layout.Constraint;
const Direction = layout.Direction;
const LayoutCache = layout_cache.LayoutCache;

// Forward declaration — will be implemented after tests pass
const IncrementalLayout = sailor.tui.IncrementalLayout;

// ============================================================================
// Test Suite: Initialization and Cleanup
// ============================================================================

test "IncrementalLayout: init creates wrapper with cache reference" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    // Verify wrapper is initialized
    try std.testing.expect(inc_layout.cache == &cache);
}

test "IncrementalLayout: deinit does not free externally-owned cache" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    {
        var inc_layout = IncrementalLayout.init(allocator, &cache);
        inc_layout.deinit();
    }

    // Cache should still be usable after IncrementalLayout deinit
    const constraints = [_]Constraint{.{ .length = 10 }};
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const result = [_]Rect{Rect{ .x = 0, .y = 0, .width = 10, .height = 50 }};

    try cache.put(&constraints, area, .horizontal, &result);
    try std.testing.expect(cache.get(&constraints, area, .horizontal) != null);
}

// ============================================================================
// Test Suite: Cache Hit Detection
// ============================================================================

test "IncrementalLayout: first split triggers computation (cache miss)" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{
        .{ .length = 30 },
        .{ .length = 70 },
    };

    // First call should compute via layout.split() and cache the result
    const result = try inc_layout.split(.horizontal, area, &constraints);

    try std.testing.expectEqual(2, result.len);
    try std.testing.expectEqual(30, result[0].width);
    try std.testing.expectEqual(70, result[1].width);

    // Verify entry was cached
    try std.testing.expectEqual(@as(usize, 1), cache.stats().entries);
}

test "IncrementalLayout: second identical split returns cached result" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };

    // First split — cache miss
    const result1 = try inc_layout.split(.horizontal, area, &constraints);

    const cache_entries_after_first = cache.stats().entries;

    // Second identical split — should return cached result without new allocation
    const result2 = try inc_layout.split(.horizontal, area, &constraints);

    // Cache should not have grown
    try std.testing.expectEqual(cache_entries_after_first, cache.stats().entries);

    // Results should be equivalent
    try std.testing.expectEqual(result1.len, result2.len);
    for (result1, result2) |r1, r2| {
        try std.testing.expectEqual(r1.x, r2.x);
        try std.testing.expectEqual(r1.y, r2.y);
        try std.testing.expectEqual(r1.width, r2.width);
        try std.testing.expectEqual(r1.height, r2.height);
    }
}

test "IncrementalLayout: different constraints trigger new computation" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints1 = [_]Constraint{
        .{ .length = 20 },
        .{ .length = 80 },
    };
    const constraints2 = [_]Constraint{
        .{ .length = 50 },
        .{ .length = 50 },
    };

    // First split with constraints1
    const result1 = try inc_layout.split(.horizontal, area, &constraints1);

    try std.testing.expectEqual(@as(usize, 1), cache.stats().entries);

    // Second split with different constraints2
    const result2 = try inc_layout.split(.horizontal, area, &constraints2);

    // Cache should have two entries now
    try std.testing.expectEqual(@as(usize, 2), cache.stats().entries);

    // Results should be different
    try std.testing.expectEqual(20, result1[0].width);
    try std.testing.expectEqual(50, result2[0].width);
}

test "IncrementalLayout: different areas trigger new computation" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    const area1 = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const area2 = Rect{ .x = 0, .y = 0, .width = 200, .height = 50 };
    const constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };

    // First split with area1
    const result1 = try inc_layout.split(.horizontal, area1, &constraints);

    try std.testing.expectEqual(@as(usize, 1), cache.stats().entries);

    // Second split with different area2
    const result2 = try inc_layout.split(.horizontal, area2, &constraints);

    // Cache should have two entries now
    try std.testing.expectEqual(@as(usize, 2), cache.stats().entries);

    // Results should have different widths
    try std.testing.expectEqual(50, result1[0].width);
    try std.testing.expectEqual(100, result2[0].width);
}

test "IncrementalLayout: different directions trigger new computation" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };

    // First split — horizontal
    const result1 = try inc_layout.split(.horizontal, area, &constraints);

    try std.testing.expectEqual(@as(usize, 1), cache.stats().entries);

    // Second split — vertical with same area and constraints
    const result2 = try inc_layout.split(.vertical, area, &constraints);

    // Cache should have two entries
    try std.testing.expectEqual(@as(usize, 2), cache.stats().entries);

    // Horizontal result should have width differences
    try std.testing.expectEqual(50, result1[0].width);
    try std.testing.expectEqual(100, result1[0].height);

    // Vertical result should have height differences
    try std.testing.expectEqual(100, result2[0].width);
    try std.testing.expectEqual(50, result2[0].height);
}

// ============================================================================
// Test Suite: Multi-Frame Scenarios
// ============================================================================

test "IncrementalLayout: frame advancement allows cache reuse across frames" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{
        .{ .ratio = .{ .num = 1, .denom = 3 } },
        .{ .ratio = .{ .num = 2, .denom = 3 } },
    };

    // Frame 0: First split
    const result1 = try inc_layout.split(.horizontal, area, &constraints);
    const cached_width1 = result1[0].width;

    // Advance to frame 1
    cache.nextFrame();

    // Frame 1: Same split should still be cached
    const result2 = try inc_layout.split(.horizontal, area, &constraints);
    const cached_width2 = result2[0].width;

    try std.testing.expectEqual(cached_width1, cached_width2);
    try std.testing.expectEqual(@as(usize, 1), cache.stats().entries);
}

test "IncrementalLayout: frame advancement with new constraints adds cache entry" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints1 = [_]Constraint{.{ .length = 25 }, .{ .length = 75 }};
    const constraints2 = [_]Constraint{.{ .length = 40 }, .{ .length = 60 }};

    // Frame 0: First split with constraints1
    const result1 = try inc_layout.split(.horizontal, area, &constraints1);

    try std.testing.expectEqual(@as(usize, 1), cache.stats().entries);

    // Advance to frame 1
    cache.nextFrame();

    // Frame 1: Different constraints
    const result2 = try inc_layout.split(.horizontal, area, &constraints2);

    // Both should be cached
    try std.testing.expectEqual(@as(usize, 2), cache.stats().entries);

    // Verify results are different
    try std.testing.expectEqual(25, result1[0].width);
    try std.testing.expectEqual(40, result2[0].width);
}

// ============================================================================
// Test Suite: Memory Safety and Cleanup
// ============================================================================

test "IncrementalLayout: no memory leaks with repeated splits" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{.{ .percentage = 50 }, .{ .percentage = 50 }};

    // Perform 100 identical splits — cache should grow only once
    for (0..100) |_| {
        _ = try inc_layout.split(.horizontal, area, &constraints);
    }

    // Only one cache entry should exist
    try std.testing.expectEqual(@as(usize, 1), cache.stats().entries);
}

test "IncrementalLayout: cache respects max_entries limit and evicts LRU" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 3); // Small cache
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    // Create 4 different constraint sets
    const c1 = [_]Constraint{.{ .length = 10 }};
    const c2 = [_]Constraint{.{ .length = 20 }};
    const c3 = [_]Constraint{.{ .length = 30 }};
    const c4 = [_]Constraint{.{ .length = 40 }};

    // Add first three
    _ = try inc_layout.split(.horizontal, area, &c1);
    try std.testing.expectEqual(@as(usize, 1), cache.stats().entries);

    cache.nextFrame();
    _ = try inc_layout.split(.horizontal, area, &c2);
    try std.testing.expectEqual(@as(usize, 2), cache.stats().entries);

    cache.nextFrame();
    _ = try inc_layout.split(.horizontal, area, &c3);
    try std.testing.expectEqual(@as(usize, 3), cache.stats().entries);

    // Add fourth — should evict oldest (c1)
    cache.nextFrame();
    _ = try inc_layout.split(.horizontal, area, &c4);
    try std.testing.expectEqual(@as(usize, 3), cache.stats().entries);

    // c1 should be evicted
    try std.testing.expect(cache.get(&c1, area, .horizontal) == null);
    try std.testing.expect(cache.get(&c2, area, .horizontal) != null);
    try std.testing.expect(cache.get(&c3, area, .horizontal) != null);
    try std.testing.expect(cache.get(&c4, area, .horizontal) != null);
}

test "IncrementalLayout: multiple splits with different areas produce correct output" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    // Test vertical split with different areas
    const area1 = Rect{ .x = 0, .y = 0, .width = 80, .height = 60 };
    const area2 = Rect{ .x = 10, .y = 5, .width = 80, .height = 40 };

    const constraints = [_]Constraint{
        .{ .length = 10 },
        .{ .percentage = 50 },
        .{ .length = 10 },
    };

    const result1 = try inc_layout.split(.vertical, area1, &constraints);

    const result2 = try inc_layout.split(.vertical, area2, &constraints);

    // Both should be cached (different areas)
    try std.testing.expectEqual(@as(usize, 2), cache.stats().entries);

    // Verify first result
    try std.testing.expectEqual(3, result1.len);
    try std.testing.expectEqual(10, result1[0].height);
    try std.testing.expectEqual(0, result1[0].y);

    // Verify second result (different area)
    try std.testing.expectEqual(3, result2.len);
    try std.testing.expectEqual(10, result2[0].height);
    try std.testing.expectEqual(5, result2[0].y); // Different y offset
}

// ============================================================================
// Test Suite: Edge Cases
// ============================================================================

test "IncrementalLayout: split with empty constraints returns empty result" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{};

    const result = try inc_layout.split(.horizontal, area, &constraints);

    try std.testing.expectEqual(0, result.len);
}

test "IncrementalLayout: split with single constraint" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{.{ .percentage = 100 }};

    const result = try inc_layout.split(.horizontal, area, &constraints);

    try std.testing.expectEqual(1, result.len);
    try std.testing.expectEqual(100, result[0].width);
}

test "IncrementalLayout: split with ratio constraints" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 120, .height = 50 };
    const constraints = [_]Constraint{
        .{ .ratio = .{ .num = 1, .denom = 3 } },
        .{ .ratio = .{ .num = 1, .denom = 3 } },
        .{ .ratio = .{ .num = 1, .denom = 3 } },
    };

    const result = try inc_layout.split(.horizontal, area, &constraints);

    try std.testing.expectEqual(3, result.len);
    // Each should get approximately 40 width (120 / 3)
    try std.testing.expectEqual(40, result[0].width);
    try std.testing.expectEqual(40, result[1].width);
    try std.testing.expectEqual(40, result[2].width);
}

// ============================================================================
// Test Suite: Constraint Types Coverage
// ============================================================================

test "IncrementalLayout: mixed constraint types in single split" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{
        .{ .length = 20 },
        .{ .percentage = 40 },
        .{ .ratio = .{ .num = 1, .denom = 5 } },
        .{ .min = 10 },
    };

    const result = try inc_layout.split(.horizontal, area, &constraints);

    try std.testing.expectEqual(4, result.len);
    // First should be fixed at 20
    try std.testing.expectEqual(20, result[0].width);
    // Total should fit in available space
    const total = result[0].width + result[1].width + result[2].width + result[3].width;
    try std.testing.expectEqual(100, total);
}

// ============================================================================
// Test Suite: Repeated Caching Behavior
// ============================================================================

test "IncrementalLayout: cache hit counter verification" {
    const allocator = std.testing.allocator;
    var cache = LayoutCache.init(allocator, 100);
    defer cache.deinit();

    var inc_layout = IncrementalLayout.init(allocator, &cache);
    defer inc_layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = [_]Constraint{.{ .percentage = 50 }, .{ .percentage = 50 }};

    // Perform multiple identical splits
    for (0..10) |i| {
        const result = try inc_layout.split(.horizontal, area, &constraints);

        // Cache size should remain 1
        try std.testing.expectEqual(@as(usize, 1), cache.stats().entries);

        // Result should always be the same
        try std.testing.expectEqual(50, result[0].width);
        try std.testing.expectEqual(50, result[1].width);

        if (i < 9) cache.nextFrame();
    }
}
