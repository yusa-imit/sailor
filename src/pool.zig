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
        pub fn init(allocator: std.mem.Allocator, config: PoolConfig) !Self {
            var self = Self{
                .allocator = allocator,
                .storage = std.ArrayList(T){},
                .free_stack = std.ArrayList(*T){},
                .mutex = std.Thread.Mutex{},
                .capacity = config.capacity,
                .allocated = 0,
                .in_use = 0,
                .peak_usage = 0,
                .grow_policy = config.grow_policy,
            };

            // Pre-allocate storage to initial capacity
            try self.storage.ensureTotalCapacity(allocator, config.capacity);
            try self.free_stack.ensureTotalCapacity(allocator, config.capacity);

            return self;
        }

        /// Deinitialize the pool and release all resources
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.storage.deinit(allocator);
            self.free_stack.deinit(allocator);
            self.* = undefined;
        }

        /// Acquire an object from the pool.
        /// Returns a pointer to an object, either from the free stack or newly allocated.
        pub fn acquire(self: *Self) !*T {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Try to get from free stack first
            if (self.free_stack.items.len > 0) {
                // Get from the top of the free stack (LIFO)
                const obj = self.free_stack.items[self.free_stack.items.len - 1];
                _ = self.free_stack.pop();

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

        /// Reset the pool, clearing all allocated objects and returning them to the free stack.
        /// Preserves capacity.
        pub fn reset(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Clear the free stack
            self.free_stack.clearRetainingCapacity();

            // Put all allocated objects back on the free stack
            for (0..self.allocated) |i| {
                self.free_stack.append(self.allocator, &self.storage.items[i]) catch return;
            }

            // Reset counters
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

test {
    std.testing.refAllDecls(@This());
}
