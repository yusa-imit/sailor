//! Reactive signal system for state management (v2.12.0)
//!
//! Provides core reactive primitives:
//! - Signal(T): Mutable reactive value with subscribers
//! - Computed(T, S): Read-only derived value from Signal(S)
//! - Effect(T): Side effect callback when Signal(T) changes
//! - Scope: Batch updates to defer notifications

const std = @import("std");

/// Subscription callback signature
/// Receives the current value and optional context pointer
pub const SubscriptionCallback = *const fn (value: anytype, ctx: ?*anyopaque) void;

/// A mutable reactive value with subscribers
pub fn Signal(T: type) type {
    return struct {
        const Self = @This();

        value: T,
        subscribers: std.ArrayList(Subscriber),
        next_id: usize = 0,
        in_batch: bool = false,
        pending_notify: bool = false,

        const Subscriber = struct {
            id: usize,
            callback: *const fn (T, ?*anyopaque) void,
            ctx: ?*anyopaque,
        };

        /// Initialize a new Signal with an initial value
        pub fn init(allocator: std.mem.Allocator, initial_value: T) !Self {
            return Self{
                .value = initial_value,
                .subscribers = std.ArrayList(Subscriber).init(allocator),
            };
        }

        /// Clean up the signal and free all subscriber memory
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            _ = allocator;
            self.subscribers.deinit();
        }

        /// Get the current value
        pub fn get(self: Self) T {
            return self.value;
        }

        /// Set a new value and notify all subscribers
        pub fn set(self: *Self, new_value: T) !void {
            self.value = new_value;

            if (self.in_batch) {
                self.pending_notify = true;
            } else {
                try self.notifySubscribers();
            }
        }

        /// Subscribe to changes with a callback
        /// Returns a subscription ID that can be used to unsubscribe
        pub fn subscribe(
            self: *Self,
            ctx: ?*anyopaque,
            callback: *const fn (T, ?*anyopaque) void,
        ) !usize {
            const id = self.next_id;
            self.next_id += 1;

            try self.subscribers.append(Subscriber{
                .id = id,
                .callback = callback,
                .ctx = ctx,
            });

            return id;
        }

        /// Unsubscribe from changes by subscription ID
        pub fn unsubscribe(self: *Self, id: usize) void {
            for (self.subscribers.items, 0..) |item, idx| {
                if (item.id == id) {
                    _ = self.subscribers.orderedRemove(idx);
                    return;
                }
            }
        }

        /// Start batching updates (defers notifications)
        pub fn beginBatch(self: *Self) void {
            self.in_batch = true;
            self.pending_notify = false;
        }

        /// End batch and flush deferred notifications
        pub fn endBatch(self: *Self) !void {
            self.in_batch = false;
            if (self.pending_notify) {
                self.pending_notify = false;
                try self.notifySubscribers();
            }
        }

        /// Notify all subscribers of the current value
        fn notifySubscribers(self: Self) !void {
            for (self.subscribers.items) |sub| {
                sub.callback(self.value, sub.ctx);
            }
        }
    };
}

/// A read-only computed value derived from a source Signal(S)
pub fn Computed(T: type, S: type) type {
    return struct {
        const Self = @This();

        source: *Signal(S),
        transform: *const fn (S) T,
        current_value: T,
        subscription_id: usize,

        /// Initialize a Computed value from a source signal and transform function
        pub fn init(
            allocator: std.mem.Allocator,
            source: *Signal(S),
            transform: *const fn (S) T,
        ) !Self {
            _ = allocator;
            const initial = transform(source.get());

            var self = Self{
                .source = source,
                .transform = transform,
                .current_value = initial,
                .subscription_id = undefined,
            };

            // Subscribe to source changes
            const callback = struct {
                fn callback(value: S, ctx: ?*anyopaque) void {
                    const ptr: *Self = @ptrCast(@alignCast(ctx.?));
                    ptr.current_value = ptr.transform(value);
                }
            }.callback;

            self.subscription_id = try source.subscribe(&self, callback);
            return self;
        }

        /// Clean up and unsubscribe from source
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            _ = allocator;
            self.source.unsubscribe(self.subscription_id);
        }

        /// Get the current derived value
        pub fn get(self: Self) T {
            return self.current_value;
        }
    };
}

/// A side effect that runs when a Signal(T) changes
pub fn Effect(T: type) type {
    return struct {
        const Self = @This();

        signal: *Signal(T),
        callback: *const fn (T, ?*anyopaque) void,
        ctx: ?*anyopaque,
        subscription_id: usize,

        /// Initialize an Effect that runs when the signal changes
        pub fn init(
            allocator: std.mem.Allocator,
            signal: *Signal(T),
            ctx: ?*anyopaque,
            callback: *const fn (T, ?*anyopaque) void,
        ) !Self {
            _ = allocator;
            var self = Self{
                .signal = signal,
                .callback = callback,
                .ctx = ctx,
                .subscription_id = undefined,
            };

            // Subscribe to signal changes
            self.subscription_id = try signal.subscribe(ctx, callback);
            return self;
        }

        /// Clean up and unsubscribe from signal
        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            _ = allocator;
            self.signal.unsubscribe(self.subscription_id);
        }
    };
}

/// Batch scope for deferring notifications
pub const Scope = struct {
    /// Initialize a new scope
    pub fn init() Scope {
        return Scope{};
    }

    /// Clean up scope
    pub fn deinit(_: *Scope) void {}

    /// Run a function within a batch context
    pub fn batch(
        _: Scope,
        allocator: std.mem.Allocator,
        signal_ptr: anytype,
        comptime fn_body: fn (@TypeOf(signal_ptr)) anyerror!void,
    ) !void {
        _ = allocator;

        signal_ptr.beginBatch();
        defer _ = signal_ptr.endBatch() catch {};

        try fn_body(signal_ptr);
    }
};
