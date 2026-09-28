//! State persistence system (v2.13.0)
//!
//! Provides serialization and deserialization of store state with user-provided
//! encode/decode functions.

const std = @import("std");

/// State persistence helper
pub fn StatePersist(State: type) type {
    return struct {
        const Self = @This();

        encode_fn: *const fn (State, *std.Io.Writer) anyerror!void,
        decode_fn: *const fn (*std.Io.Reader, std.mem.Allocator) anyerror!State,

        /// Initialize StatePersist with encode and decode functions
        pub fn init(
            encode_fn: *const fn (State, *std.Io.Writer) anyerror!void,
            decode_fn: *const fn (*std.Io.Reader, std.mem.Allocator) anyerror!State,
        ) Self {
            return Self{
                .encode_fn = encode_fn,
                .decode_fn = decode_fn,
            };
        }

        /// Save state to a writer
        pub fn save(self: Self, state: State, writer: *std.Io.Writer) !void {
            try self.encode_fn(state, writer);
        }

        /// Load state from a reader
        pub fn load(self: Self, reader: *std.Io.Reader, allocator: std.mem.Allocator) !State {
            return try self.decode_fn(reader, allocator);
        }
    };
}
