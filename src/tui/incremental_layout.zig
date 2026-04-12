//! Incremental Layout Solver — Automatic caching for constraint-based layouts
//!
//! The IncrementalLayout provides a high-level API for constraint-based layout
//! computation with automatic result caching. This eliminates redundant
//! calculations when the same layout is requested across multiple frames.
//!
//! ## Performance Impact
//!
//! Without caching, every frame recomputes layouts even if constraints haven't changed:
//! - Frame 1: Compute split (100μs)
//! - Frame 2: Compute identical split (100μs) ← Wasted work
//! - Frame 3: Compute identical split (100μs) ← Wasted work
//!
//! With IncrementalLayout:
//! - Frame 1: Compute split (100μs), cache result
//! - Frame 2: Cache hit (1μs) — 99% faster
//! - Frame 3: Cache hit (1μs) — 99% faster
//!
//! ## Example Usage
//!
//! ```zig
//! var cache = LayoutCache.init(allocator, 100);
//! defer cache.deinit();
//!
//! var layout = IncrementalLayout.init(allocator, &cache);
//! defer layout.deinit();
//!
//! // In your render loop:
//! while (running) {
//!     cache.nextFrame(); // Advance frame counter
//!
//!     const constraints = &[_]Constraint{
//!         .{ .percentage = 20 },
//!         .{ .percentage = 80 },
//!     };
//!
//!     const chunks = try layout.split(.horizontal, area, constraints);
//!     // First call: cache miss, computes layout
//!     // Subsequent calls with same constraints: cache hit, instant return
//!
//!     // Use chunks for widget rendering...
//! }
//! ```
//!
//! ## When to Use
//!
//! IncrementalLayout is most beneficial for:
//! - Static layouts (constraints don't change across frames)
//! - Complex constraint hierarchies (nested splits)
//! - High frame rates (60+ FPS)
//! - Applications with many widgets requiring layout computation
//!
//! ## Memory Considerations
//!
//! The cache stores `[]Rect` arrays for each unique layout configuration.
//! Typical memory usage:
//! - Per cache entry: ~16 bytes (CacheKey) + N×8 bytes (Rect array)
//! - 100 cached 4-split layouts: ~16KB
//!
//! The cache uses LRU eviction when `max_entries` is reached, automatically
//! removing least recently used entries to control memory growth.

const std = @import("std");
const Allocator = std.mem.Allocator;
const layout_mod = @import("layout.zig");
const Direction = layout_mod.Direction;
const Rect = layout_mod.Rect;
const Constraint = layout_mod.Constraint;
const layout_split = layout_mod.split;
const layout_cache_mod = @import("layout_cache.zig");
const LayoutCache = layout_cache_mod.LayoutCache;

/// Incremental layout solver with automatic caching
///
/// Wraps the low-level `split()` function with transparent caching.
/// The cache is externally owned and shared across multiple IncrementalLayout
/// instances if desired.
pub const IncrementalLayout = struct {
    allocator: Allocator,
    cache: *LayoutCache,

    /// Initialize incremental layout solver
    ///
    /// The cache is externally owned — caller must manage its lifetime.
    /// Multiple IncrementalLayout instances can share the same cache.
    ///
    /// Example:
    /// ```zig
    /// var cache = LayoutCache.init(allocator, 100);
    /// defer cache.deinit();
    ///
    /// var layout = IncrementalLayout.init(allocator, &cache);
    /// defer layout.deinit();
    /// ```
    pub fn init(allocator: Allocator, cache: *LayoutCache) IncrementalLayout {
        return .{
            .allocator = allocator,
            .cache = cache,
        };
    }

    /// Clean up resources
    ///
    /// Note: This does NOT deinit the cache, as it's externally owned.
    /// The cache must be deinitialized separately by the owner.
    pub fn deinit(self: *IncrementalLayout) void {
        // Cache is externally owned, no cleanup needed
        _ = self;
    }

    /// Split an area into multiple rectangles using constraints
    ///
    /// This function automatically checks the cache before computing.
    /// If a matching layout was previously computed, it returns the cached
    /// result instantly. Otherwise, it computes the layout using the low-level
    /// `split()` function and stores the result in the cache.
    ///
    /// **Important**: The returned slice is owned by the cache and remains
    /// valid until the cache entry is evicted (LRU policy). Do not free it.
    ///
    /// Example:
    /// ```zig
    /// const constraints = &[_]Constraint{
    ///     .{ .length = 10 },
    ///     .{ .percentage = 50 },
    ///     .{ .min = 20 },
    /// };
    ///
    /// const chunks = try layout.split(.vertical, terminal_area, constraints);
    /// // chunks[0]: 10 cells tall
    /// // chunks[1]: 50% of remaining space
    /// // chunks[2]: At least 20 cells tall
    /// ```
    pub fn split(
        self: *IncrementalLayout,
        direction: Direction,
        area: Rect,
        constraints: []const Constraint,
    ) ![]const Rect {
        // Check cache first
        if (self.cache.get(constraints, area, direction)) |cached| {
            return cached;
        }

        // Cache miss — compute layout
        const result = try layout_split(self.allocator, direction, area, constraints);

        // Store in cache (cache makes a copy and takes ownership)
        try self.cache.put(constraints, area, direction, result);

        // Free our original allocation (cache made its own copy)
        defer self.allocator.free(result);

        // Return cached version (guaranteed to exist after put())
        return self.cache.get(constraints, area, direction).?;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "IncrementalLayout.init and deinit" {
    var cache = LayoutCache.init(testing.allocator, 100);
    defer cache.deinit();

    var layout = IncrementalLayout.init(testing.allocator, &cache);
    defer layout.deinit();

    // Verify initialization
    try testing.expectEqual(@intFromPtr(&cache), @intFromPtr(layout.cache));
}

test "IncrementalLayout.split caches results" {
    var cache = LayoutCache.init(testing.allocator, 100);
    defer cache.deinit();

    var layout = IncrementalLayout.init(testing.allocator, &cache);
    defer layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = &[_]Constraint{
        .{ .percentage = 30 },
        .{ .percentage = 70 },
    };

    // First call: cache miss, computes layout
    const result1 = try layout.split(.horizontal, area, constraints);
    try testing.expectEqual(@as(usize, 2), result1.len);
    try testing.expectEqual(@as(u16, 30), result1[0].width);
    try testing.expectEqual(@as(u16, 70), result1[1].width);

    // Second call: cache hit, same result
    const result2 = try layout.split(.horizontal, area, constraints);
    try testing.expectEqual(@as(usize, 2), result2.len);
    try testing.expectEqual(@as(u16, 30), result2[0].width);
    try testing.expectEqual(@as(u16, 70), result2[1].width);

    // Verify same allocation (cache hit)
    try testing.expectEqual(@intFromPtr(result1.ptr), @intFromPtr(result2.ptr));
}

test "IncrementalLayout.split different constraints trigger new computation" {
    var cache = LayoutCache.init(testing.allocator, 100);
    defer cache.deinit();

    var layout = IncrementalLayout.init(testing.allocator, &cache);
    defer layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };

    const constraints1 = &[_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };

    const constraints2 = &[_]Constraint{
        .{ .percentage = 30 },
        .{ .percentage = 70 },
    };

    const result1 = try layout.split(.horizontal, area, constraints1);
    const result2 = try layout.split(.horizontal, area, constraints2);

    // Different constraints yield different results
    try testing.expect(result1[0].width != result2[0].width);

    // Verify both are cached (different allocations)
    try testing.expect(@intFromPtr(result1.ptr) != @intFromPtr(result2.ptr));
}

test "IncrementalLayout.split empty constraints" {
    var cache = LayoutCache.init(testing.allocator, 100);
    defer cache.deinit();

    var layout = IncrementalLayout.init(testing.allocator, &cache);
    defer layout.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const constraints = &[_]Constraint{};

    const result = try layout.split(.horizontal, area, constraints);
    try testing.expectEqual(@as(usize, 0), result.len);
}
