//! Layout Caching System
//! Reuses constraint computation results between frames to avoid redundant calculations.
//! Caches layout results based on constraints + available area as key.

const std = @import("std");
const layout = @import("layout.zig");
const Rect = layout.Rect;
const Constraint = layout.Constraint;
const Direction = layout.Direction;

/// Cache key combining constraints and area dimensions
const CacheKey = struct {
    constraints_hash: u64,
    width: u16,
    height: u16,
    direction: Direction,

    fn init(constraints: []const Constraint, area: Rect, dir: Direction) CacheKey {
        var hasher = std.hash.Wyhash.init(0);
        for (constraints) |c| {
            std.hash.autoHash(&hasher, c);
        }
        return .{
            .constraints_hash = hasher.final(),
            .width = area.width,
            .height = area.height,
            .direction = dir,
        };
    }

    fn eql(self: CacheKey, other: CacheKey) bool {
        return self.constraints_hash == other.constraints_hash and
            self.width == other.width and
            self.height == other.height and
            self.direction == other.direction;
    }

    fn hash(self: CacheKey) u64 {
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, self);
        return hasher.final();
    }
};

/// Cached layout result
const CacheEntry = struct {
    key: CacheKey,
    result: []Rect,
    last_used_frame: u64,
};

/// Layout cache with LRU eviction
pub const LayoutCache = struct {
    allocator: std.mem.Allocator,
    cache: std.AutoHashMap(CacheKey, CacheEntry),
    frame_counter: u64,
    max_entries: usize,

    /// Initialize layout cache with LRU eviction at max_entries limit.
    pub fn init(allocator: std.mem.Allocator, max_entries: usize) LayoutCache {
        return .{
            .allocator = allocator,
            .cache = std.AutoHashMap(CacheKey, CacheEntry).init(allocator),
            .frame_counter = 0,
            .max_entries = max_entries,
        };
    }

    /// Free all cached layout results and the cache map.
    pub fn deinit(self: *LayoutCache) void {
        var it = self.cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.result);
        }
        self.cache.deinit();
    }

    /// Increment frame counter (call once per frame)
    pub fn nextFrame(self: *LayoutCache) void {
        self.frame_counter += 1;
    }

    /// Get cached layout result, or null if not found
    pub fn get(self: *LayoutCache, constraints: []const Constraint, area: Rect, dir: Direction) ?[]const Rect {
        const key = CacheKey.init(constraints, area, dir);
        if (self.cache.getPtr(key)) |entry| {
            entry.last_used_frame = self.frame_counter;
            return entry.result;
        }
        return null;
    }

    /// Store layout result in cache
    pub fn put(self: *LayoutCache, constraints: []const Constraint, area: Rect, dir: Direction, result: []const Rect) !void {
        // Evict LRU entry if cache is full
        if (self.cache.count() >= self.max_entries) {
            try self.evictLRU();
        }

        const key = CacheKey.init(constraints, area, dir);

        // Clone result array
        const result_copy = try self.allocator.alloc(Rect, result.len);
        @memcpy(result_copy, result);

        try self.cache.put(key, .{
            .key = key,
            .result = result_copy,
            .last_used_frame = self.frame_counter,
        });
    }

    /// Clear all cached entries
    pub fn clear(self: *LayoutCache) void {
        var it = self.cache.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.result);
        }
        self.cache.clearRetainingCapacity();
    }

    /// Get cache statistics
    pub fn stats(self: *const LayoutCache) CacheStats {
        return .{
            .entries = self.cache.count(),
            .max_entries = self.max_entries,
            .current_frame = self.frame_counter,
        };
    }

    fn evictLRU(self: *LayoutCache) !void {
        var oldest_key: ?CacheKey = null;
        var oldest_frame: u64 = std.math.maxInt(u64);

        var it = self.cache.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.last_used_frame < oldest_frame) {
                oldest_frame = entry.value_ptr.last_used_frame;
                oldest_key = entry.key_ptr.*;
            }
        }

        if (oldest_key) |key| {
            if (self.cache.fetchRemove(key)) |removed| {
                self.allocator.free(removed.value.result);
            }
        }
    }
};

pub const CacheStats = struct {
    entries: usize,
    max_entries: usize,
    current_frame: u64,
};

// Tests
test "LayoutCache: init and deinit" {
    const testing = std.testing;
    var cache = LayoutCache.init(testing.allocator, 100);
    defer cache.deinit();

    try testing.expectEqual(@as(usize, 0), cache.cache.count());
    try testing.expectEqual(@as(usize, 100), cache.max_entries);
    try testing.expectEqual(@as(u64, 0), cache.frame_counter);
}

test "LayoutCache: put and get basic" {
    const testing = std.testing;
    var cache = LayoutCache.init(testing.allocator, 100);
    defer cache.deinit();

    const constraints = [_]Constraint{.{ .length = 10 }};
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const result = [_]Rect{Rect{ .x = 0, .y = 0, .width = 10, .height = 50 }};

    try cache.put(&constraints, area, .horizontal, &result);

    const cached = cache.get(&constraints, area, .horizontal);
    try testing.expect(cached != null);
    try testing.expectEqual(@as(usize, 1), cached.?.len);
    try testing.expectEqual(@as(u16, 10), cached.?[0].width);
}

test "LayoutCache: cache miss on different constraints" {
    const testing = std.testing;
    var cache = LayoutCache.init(testing.allocator, 100);
    defer cache.deinit();

    const constraints1 = [_]Constraint{.{ .length = 10 }};
    const constraints2 = [_]Constraint{.{ .length = 20 }};
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const result = [_]Rect{Rect{ .x = 0, .y = 0, .width = 10, .height = 50 }};

    try cache.put(&constraints1, area, .horizontal, &result);

    const cached = cache.get(&constraints2, area, .horizontal);
    try testing.expect(cached == null);
}

test "LayoutCache: cache miss on different area" {
    const testing = std.testing;
    var cache = LayoutCache.init(testing.allocator, 100);
    defer cache.deinit();

    const constraints = [_]Constraint{.{ .length = 10 }};
    const area1 = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const area2 = Rect{ .x = 0, .y = 0, .width = 200, .height = 50 };
    const result = [_]Rect{Rect{ .x = 0, .y = 0, .width = 10, .height = 50 }};

    try cache.put(&constraints, area1, .horizontal, &result);

    const cached = cache.get(&constraints, area2, .horizontal);
    try testing.expect(cached == null);
}

test "LayoutCache: cache miss on different direction" {
    const testing = std.testing;
    var cache = LayoutCache.init(testing.allocator, 100);
    defer cache.deinit();

    const constraints = [_]Constraint{.{ .length = 10 }};
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const result = [_]Rect{Rect{ .x = 0, .y = 0, .width = 10, .height = 50 }};

    try cache.put(&constraints, area, .horizontal, &result);

    const cached = cache.get(&constraints, area, .vertical);
    try testing.expect(cached == null);
}

test "LayoutCache: nextFrame updates counter" {
    const testing = std.testing;
    var cache = LayoutCache.init(testing.allocator, 100);
    defer cache.deinit();

    try testing.expectEqual(@as(u64, 0), cache.frame_counter);
    cache.nextFrame();
    try testing.expectEqual(@as(u64, 1), cache.frame_counter);
    cache.nextFrame();
    try testing.expectEqual(@as(u64, 2), cache.frame_counter);
}

test "LayoutCache: LRU eviction when full" {
    const testing = std.testing;
    var cache = LayoutCache.init(testing.allocator, 2);
    defer cache.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const result = [_]Rect{Rect{ .x = 0, .y = 0, .width = 10, .height = 50 }};

    const c1 = [_]Constraint{.{ .length = 10 }};
    const c2 = [_]Constraint{.{ .length = 20 }};
    const c3 = [_]Constraint{.{ .length = 30 }};

    // Fill cache - frame 0
    try cache.put(&c1, area, .horizontal, &result);
    cache.nextFrame(); // frame 1
    try cache.put(&c2, area, .horizontal, &result);
    cache.nextFrame(); // frame 2

    // Both should be cached (c1 at frame 0, c2 at frame 1)
    try testing.expectEqual(@as(usize, 2), cache.cache.count());

    // Add third entry, should evict c1 (oldest - last_used_frame = 0)
    try cache.put(&c3, area, .horizontal, &result);

    try testing.expect(cache.get(&c1, area, .horizontal) == null); // evicted
    try testing.expect(cache.get(&c2, area, .horizontal) != null);
    try testing.expect(cache.get(&c3, area, .horizontal) != null);
}

test "LayoutCache: clear removes all entries" {
    const testing = std.testing;
    var cache = LayoutCache.init(testing.allocator, 100);
    defer cache.deinit();

    const constraints = [_]Constraint{.{ .length = 10 }};
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const result = [_]Rect{Rect{ .x = 0, .y = 0, .width = 10, .height = 50 }};

    try cache.put(&constraints, area, .horizontal, &result);
    try testing.expectEqual(@as(usize, 1), cache.cache.count());

    cache.clear();
    try testing.expectEqual(@as(usize, 0), cache.cache.count());
}

test "LayoutCache: stats returns correct values" {
    const testing = std.testing;
    var cache = LayoutCache.init(testing.allocator, 100);
    defer cache.deinit();

    const constraints = [_]Constraint{.{ .length = 10 }};
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const result = [_]Rect{Rect{ .x = 0, .y = 0, .width = 10, .height = 50 }};

    try cache.put(&constraints, area, .horizontal, &result);
    cache.nextFrame();

    const s = cache.stats();
    try testing.expectEqual(@as(usize, 1), s.entries);
    try testing.expectEqual(@as(usize, 100), s.max_entries);
    try testing.expectEqual(@as(u64, 1), s.current_frame);
}

test "LayoutCache: multiple constraints cached" {
    const testing = std.testing;
    var cache = LayoutCache.init(testing.allocator, 100);
    defer cache.deinit();

    const constraints = [_]Constraint{ .{ .length = 10 }, .{ .percentage = 50 }, .{ .ratio = .{ .num = 1, .denom = 3 } } };
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const result = [_]Rect{
        Rect{ .x = 0, .y = 0, .width = 10, .height = 50 },
        Rect{ .x = 10, .y = 0, .width = 50, .height = 50 },
        Rect{ .x = 60, .y = 0, .width = 40, .height = 50 },
    };

    try cache.put(&constraints, area, .horizontal, &result);

    const cached = cache.get(&constraints, area, .horizontal);
    try testing.expect(cached != null);
    try testing.expectEqual(@as(usize, 3), cached.?.len);
}

test "LayoutCache: update last_used_frame on get" {
    const testing = std.testing;
    var cache = LayoutCache.init(testing.allocator, 100);
    defer cache.deinit();

    const constraints = [_]Constraint{.{ .length = 10 }};
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 50 };
    const result = [_]Rect{Rect{ .x = 0, .y = 0, .width = 10, .height = 50 }};

    try cache.put(&constraints, area, .horizontal, &result);
    try testing.expectEqual(@as(u64, 0), cache.frame_counter);

    cache.nextFrame();
    cache.nextFrame();
    try testing.expectEqual(@as(u64, 2), cache.frame_counter);

    // Get should update last_used_frame to current frame
    _ = cache.get(&constraints, area, .horizontal);

    const key = CacheKey.init(&constraints, area, .horizontal);
    const entry = cache.cache.get(key).?;
    try testing.expectEqual(@as(u64, 2), entry.last_used_frame);
}
