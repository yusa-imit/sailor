//! State persistence system (v2.13.0)
//!
//! Provides serialization and deserialization of store state with user-provided
//! encode/decode functions.

const std = @import("std");

/// State persistence helper
pub fn StatePersist(State: type) type {
    return struct {
        const Self = @This();

        encode_fn: *const fn (State, std.io.AnyWriter) anyerror!void,
        decode_fn: *const fn (std.io.AnyReader, std.mem.Allocator) anyerror!State,

        /// Initialize StatePersist with encode and decode functions
        pub fn init(
            encode_fn: *const fn (State, std.io.AnyWriter) anyerror!void,
            decode_fn: *const fn (std.io.AnyReader, std.mem.Allocator) anyerror!State,
        ) Self {
            return Self{
                .encode_fn = encode_fn,
                .decode_fn = decode_fn,
            };
        }

        /// Save state to a writer
        pub fn save(self: Self, state: State, writer: anytype) !void {
            try self.encode_fn(state, writer.any());
        }

        /// Load state from a reader
        pub fn load(self: Self, reader: anytype, allocator: std.mem.Allocator) !State {
            return try self.decode_fn(reader.any(), allocator);
        }
    };
}
