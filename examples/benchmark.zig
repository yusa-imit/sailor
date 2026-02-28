//! Benchmark runner for sailor library performance tests
//!
//! Usage: zig build benchmark

const std = @import("std");
const sailor = @import("sailor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Use a large buffer for benchmark output
    var buf: [65536]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try sailor.bench.runAll(allocator, writer);

    // Print results to stdout
    std.debug.print("{s}", .{fbs.getWritten()});
}
