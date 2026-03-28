//! Memory pooling system for efficient object reuse.
//!
//! Provides a generic object pool with capacity management, growth policies,
//! acquire/release semantics, statistics tracking, and thread-safety.
//!
//! Usage:
//! ```zig
//! var pool = try Pool(MyType).init(allocator, .{
//!     .capacity = 100,
//!     .grow_policy = .double,
//! });
//! defer pool.deinit(allocator);
//!
//! const obj = try pool.acquire();
//! defer pool.release(obj);
//! ```

const std = @import("std");

/// Growth policy for pool expansion
pub const GrowPolicy = union(enum) {
    /// Double capacity on growth
    double,
    /// Linearly increase capacity by specified step
    linear: usize,
};

/// Configuration options for pool initialization
pub const PoolConfig = struct {
    /// Initial capacity of the pool
    capacity: usize,
    /// Growth policy when capacity is exceeded
    grow_policy: GrowPolicy,
};

/// Generic object pool with statistics and thread-safety
pub fn Pool(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        storage: std.ArrayList(T),
        free_stack: std.ArrayList(*T),
        mutex: std.Thread.Mutex,

        /// Total number of objects that can fit without growing
        capacity: usize,
        /// Total number of objects allocated from the pool
        allocated: usize,
        /// Number of objects currently in use
        in_use: usize,
        /// Maximum concurrent in-use count ever reached
        peak_usage: usize,

        /// Growth policy for this pool
        grow_policy: GrowPolicy,

        /// Initialize a new pool with the given configuration
        pub fn init(alloc: std.mem.Allocator, config: PoolConfig) !Self {
            var storage: std.ArrayList(T) = .{};
            errdefer storage.deinit(alloc);
            try storage.ensureTotalCapacity(alloc, config.capacity);

            var free_stack: std.ArrayList(*T) = .{};
            errdefer free_stack.deinit(alloc);
            try free_stack.ensureTotalCapacity(alloc, config.capacity);

            return Self{
                .allocator = alloc,
                .storage = storage,
                .free_stack = free_stack,
                .mutex = .{},
                .capacity = config.capacity,
                .allocated = 0,
                .in_use = 0,
                .peak_usage = 0,
                .grow_policy = config.grow_policy,
            };
        }

        /// Deinitialize the pool and release all resources
        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.storage.deinit(self.allocator);
            self.free_stack.deinit(self.allocator);
        }

        /// Acquire an object from the pool.
        /// Returns a pointer to an object, either from the free stack or newly allocated.
        pub fn acquire(self: *Self) !*T {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Try to get from free stack first
            if (self.free_stack.items.len > 0) {
                // Get from the top of the free stack (LIFO)
                const obj = self.free_stack.pop() orelse unreachable; // Safe: we checked len > 0

                // Update statistics
                self.in_use += 1;
                if (self.in_use > self.peak_usage) {
                    self.peak_usage = self.in_use;
                }

                return obj;
            }

            // Need to allocate a new object
            // Check if we need to grow
            if (self.allocated >= self.capacity) {
                try self.growUnsafe();
            }

            // Allocate new object in storage
            try self.storage.append(self.allocator, std.mem.zeroes(T));
            const obj = &self.storage.items[self.allocated];
            self.allocated += 1;

            // Update statistics
            self.in_use += 1;
            if (self.in_use > self.peak_usage) {
                self.peak_usage = self.in_use;
            }

            return obj;
        }

        /// Release an object back to the pool for reuse
        pub fn release(self: *Self, obj: *T) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Add back to free stack
            self.free_stack.append(self.allocator, obj) catch return; // Silently ignore allocation failure

            // Update statistics
            if (self.in_use > 0) {
                self.in_use -= 1;
            }
        }

        /// Reset the pool, clearing all allocated objects.
        /// Preserves capacity but clears all storage.
        pub fn reset(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Clear both storage and free stack
            self.storage.clearRetainingCapacity();
            self.free_stack.clearRetainingCapacity();

            // Reset all counters
            self.in_use = 0;
            self.allocated = 0;
        }

        /// Grow the pool according to its growth policy (internal, mutex must be held)
        fn growUnsafe(self: *Self) !void {
            const new_capacity = switch (self.grow_policy) {
                .double => self.capacity * 2,
                .linear => |step| self.capacity + step,
            };

            self.capacity = new_capacity;

            // Ensure storage can accommodate the new capacity
            try self.storage.ensureTotalCapacity(self.allocator, new_capacity);
        }
    };
}

const TestObject = struct {
    value: u32,
};

test "pool initialization with double growth policy" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 10,
        .grow_policy = .double,
    });
    defer pool.deinit();

    try std.testing.expectEqual(@as(usize, 10), pool.capacity);
    try std.testing.expectEqual(@as(usize, 0), pool.allocated);
    try std.testing.expectEqual(@as(usize, 0), pool.in_use);
    try std.testing.expectEqual(@as(usize, 0), pool.peak_usage);
}

test "pool initialization with linear growth policy" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 5,
        .grow_policy = .{ .linear = 3 },
    });
    defer pool.deinit();

    try std.testing.expectEqual(@as(usize, 5), pool.capacity);
    try std.testing.expectEqual(@as(usize, 0), pool.allocated);
    try std.testing.expectEqual(@as(usize, 0), pool.in_use);
    try std.testing.expectEqual(@as(usize, 0), pool.peak_usage);
}

test "acquire from empty pool allocates new object" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 10,
        .grow_policy = .double,
    });
    defer pool.deinit();

    const obj = try pool.acquire();
    obj.value = 42;
    try std.testing.expectEqual(@as(u32, 42), obj.value);
    try std.testing.expectEqual(@as(usize, 1), pool.allocated);
    try std.testing.expectEqual(@as(usize, 1), pool.in_use);
    try std.testing.expectEqual(@as(usize, 1), pool.peak_usage);
}

test "release object adds to free stack" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 10,
        .grow_policy = .double,
    });
    defer pool.deinit();

    const obj = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 1), pool.in_use);

    pool.release(obj);
    try std.testing.expectEqual(@as(usize, 0), pool.in_use);
    try std.testing.expectEqual(@as(usize, 1), pool.allocated);
}

test "acquire after release reuses object (LIFO)" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 10,
        .grow_policy = .double,
    });
    defer pool.deinit();

    const obj1 = try pool.acquire();
    obj1.value = 42;
    pool.release(obj1);

    const obj2 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 42), obj2.value);
    try std.testing.expectEqual(@as(usize, 1), pool.allocated);
}

test "LIFO behavior: last released is first acquired" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 10,
        .grow_policy = .double,
    });
    defer pool.deinit();

    const obj1 = try pool.acquire();
    obj1.value = 1;
    const obj2 = try pool.acquire();
    obj2.value = 2;
    const obj3 = try pool.acquire();
    obj3.value = 3;

    pool.release(obj1);
    pool.release(obj2);
    pool.release(obj3);

    // LIFO: obj3 was released last, should be acquired first
    const reacquired = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 3), reacquired.value);
}

test "double growth policy: capacity doubles when exceeded" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 2,
        .grow_policy = .double,
    });
    defer pool.deinit();

    const obj1 = try pool.acquire();
    const obj2 = try pool.acquire();
    const obj3 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 4), pool.capacity);

    pool.release(obj1);
    pool.release(obj2);
    pool.release(obj3);
}

test "linear growth policy: capacity grows by step" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 2,
        .grow_policy = .{ .linear = 3 },
    });
    defer pool.deinit();

    const obj1 = try pool.acquire();
    const obj2 = try pool.acquire();
    const obj3 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 5), pool.capacity);

    pool.release(obj1);
    pool.release(obj2);
    pool.release(obj3);
}

test "statistics: in_use increases on acquire, decreases on release" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 10,
        .grow_policy = .double,
    });
    defer pool.deinit();

    try std.testing.expectEqual(@as(usize, 0), pool.in_use);

    const obj1 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 1), pool.in_use);

    const obj2 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 2), pool.in_use);

    pool.release(obj1);
    try std.testing.expectEqual(@as(usize, 1), pool.in_use);

    pool.release(obj2);
    try std.testing.expectEqual(@as(usize, 0), pool.in_use);
}

test "statistics: peak_usage tracks maximum concurrent usage" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 10,
        .grow_policy = .double,
    });
    defer pool.deinit();

    try std.testing.expectEqual(@as(usize, 0), pool.peak_usage);

    const obj1 = try pool.acquire();
    const obj2 = try pool.acquire();
    const obj3 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 3), pool.peak_usage);

    pool.release(obj1);
    pool.release(obj2);
    pool.release(obj3);

    const obj4 = try pool.acquire();
    const obj5 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 3), pool.peak_usage);

    pool.release(obj4);
    pool.release(obj5);
}

test "statistics: allocated count increases on new object creation" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 10,
        .grow_policy = .double,
    });
    defer pool.deinit();

    try std.testing.expectEqual(@as(usize, 0), pool.allocated);

    const obj1 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 1), pool.allocated);

    const obj2 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 2), pool.allocated);

    // Releasing doesn't change allocated
    pool.release(obj1);
    try std.testing.expectEqual(@as(usize, 2), pool.allocated);

    // Re-acquiring doesn't increase allocated
    const obj3 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 2), pool.allocated);

    pool.release(obj3);
    pool.release(obj2);
}

test "reset clears storage and resets counters" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 10,
        .grow_policy = .double,
    });
    defer pool.deinit();

    const obj1 = try pool.acquire();
    const obj2 = try pool.acquire();
    pool.release(obj1);
    pool.release(obj2);

    try std.testing.expectEqual(@as(usize, 2), pool.allocated);
    try std.testing.expectEqual(@as(usize, 0), pool.in_use);

    pool.reset();

    try std.testing.expectEqual(@as(usize, 0), pool.allocated);
    try std.testing.expectEqual(@as(usize, 0), pool.in_use);
    try std.testing.expectEqual(@as(usize, 10), pool.capacity);
}

test "reset preserves capacity" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 5,
        .grow_policy = .double,
    });
    defer pool.deinit();

    const obj1 = try pool.acquire();
    const obj2 = try pool.acquire();
    const obj3 = try pool.acquire();
    pool.release(obj1);
    pool.release(obj2);
    pool.release(obj3);

    pool.reset();

    try std.testing.expectEqual(@as(usize, 5), pool.capacity);
}

test "acquire many objects with growth" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 2,
        .grow_policy = .double,
    });
    defer pool.deinit();

    var objects: [10]*TestObject = undefined;
    for (0..10) |i| {
        objects[i] = try pool.acquire();
        objects[i].value = @intCast(i);
    }

    try std.testing.expectEqual(@as(usize, 10), pool.allocated);
    try std.testing.expectEqual(@as(usize, 10), pool.in_use);
    try std.testing.expectEqual(@as(usize, 10), pool.peak_usage);

    for (0..10) |i| {
        pool.release(objects[i]);
    }

    try std.testing.expectEqual(@as(usize, 0), pool.in_use);
    try std.testing.expectEqual(@as(usize, 10), pool.allocated);
}

test "release unbalanced with acquire is safe" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 10,
        .grow_policy = .double,
    });
    defer pool.deinit();

    const obj1 = try pool.acquire();
    const obj2 = try pool.acquire();

    pool.release(obj1);
    pool.release(obj2);
    pool.release(obj2); // Release same object again

    // Should not crash, in_use won't go below 0
    try std.testing.expectEqual(@as(usize, 0), pool.in_use);
}

test "multiple acquire-release cycles" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 5,
        .grow_policy = .double,
    });
    defer pool.deinit();

    // First cycle
    const obj1 = try pool.acquire();
    obj1.value = 10;
    pool.release(obj1);

    // Second cycle - should reuse
    const obj2 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 10), obj2.value);
    pool.release(obj2);

    // Third cycle
    const obj3 = try pool.acquire();
    obj3.value = 20;
    pool.release(obj3);

    const obj4 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 20), obj4.value);

    pool.release(obj4);
}

test "zeroed initialization on new objects" {
    const alloc = std.testing.allocator;
    var pool = try Pool(TestObject).init(alloc, .{
        .capacity = 10,
        .grow_policy = .double,
    });
    defer pool.deinit();

    const obj = try pool.acquire();
    try std.testing.expectEqual(@as(u32, 0), obj.value);
}

test {
    std.testing.refAllDecls(@This());
}
