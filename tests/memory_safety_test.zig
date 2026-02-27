//! Memory safety tests
//!
//! These tests verify memory management patterns and catch
//! common memory safety issues.

const std = @import("std");
const testing = std.testing;

test "no use-after-free with defer" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch @panic("memory leak detected");
    }

    const allocator = gpa.allocator();

    {
        const buf = try allocator.alloc(u8, 100);
        defer allocator.free(buf);

        // Use buffer
        @memset(buf, 42);
        try testing.expectEqual(42, buf[0]);
    }

    // Buffer is freed here, no leak
}

test "arena allocator prevents leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch @panic("memory leak detected");
    }

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const allocator = arena.allocator();

    // Multiple allocations without individual frees
    _ = try allocator.alloc(u8, 100);
    _ = try allocator.alloc(u8, 200);
    _ = try allocator.alloc(u8, 300);

    // All freed by arena.deinit()
}

test "double free detection" {
    // This test verifies that we don't accidentally double-free
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch @panic("memory leak detected");
    }

    const allocator = gpa.allocator();

    const buf = try allocator.alloc(u8, 100);
    allocator.free(buf);

    // Double free would be caught here by GPA if we did:
    // allocator.free(buf); // DON'T DO THIS
}

test "slice bounds checking" {
    const data = [_]u8{ 1, 2, 3, 4, 5 };

    // Valid access
    try testing.expectEqual(1, data[0]);
    try testing.expectEqual(5, data[4]);

    // Slice operations stay in bounds
    const slice = data[1..4];
    try testing.expectEqual(3, slice.len);
    try testing.expectEqual(2, slice[0]);
    try testing.expectEqual(4, slice[2]);
}

test "null pointer checking with optional" {
    var ptr: ?*const u32 = null;

    if (ptr) |p| {
        _ = p;
        try testing.expect(false); // Should not reach
    } else {
        // Correctly handled null
    }

    const value: u32 = 42;
    ptr = &value;

    if (ptr) |p| {
        try testing.expectEqual(42, p.*);
    } else {
        try testing.expect(false); // Should not reach
    }
}

test "buffer overflow protection via bounds" {
    var buf: [10]u8 = undefined;

    // Safe write
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = @intCast(i);
    }

    try testing.expectEqual(0, buf[0]);
    try testing.expectEqual(9, buf[9]);

    // buf[10] would be a compile error or runtime panic
}

test "alignment requirements" {
    const allocator = testing.allocator;

    // Aligned allocations
    const aligned_buf = try allocator.alignedAlloc(u8, 16, 64);
    defer allocator.free(aligned_buf);

    const addr = @intFromPtr(aligned_buf.ptr);
    try testing.expectEqual(0, addr % 16);
}

test "integer overflow detection" {
    // Zig provides overflow checking in debug/safe modes
    const a: u8 = 255;

    // Checked addition
    const result = @addWithOverflow(a, 1);
    try testing.expectEqual(0, result[0]); // Wrapped value
    try testing.expectEqual(1, result[1]); // Overflow flag
}

test "unitialized memory detection pattern" {
    // Use undefined carefully
    var buf: [10]u8 = undefined;

    // Must initialize before reading
    @memset(&buf, 0);

    try testing.expectEqual(0, buf[0]);
    try testing.expectEqual(0, buf[9]);
}

test "fixed buffer stream prevents overrun" {
    var buf: [10]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // Write within bounds
    try writer.writeAll("hello");
    try testing.expectEqualStrings("hello", fbs.getWritten());

    // Writing too much returns error
    const result = writer.writeAll("world!!!");
    try testing.expectError(error.NoSpaceLeft, result);
}

test "arraylist automatic resizing" {
    var list = std.ArrayList(u32).init(testing.allocator);
    defer list.deinit();

    // Grow dynamically without overflow
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        try list.append(i);
    }

    try testing.expectEqual(1000, list.items.len);
    try testing.expectEqual(0, list.items[0]);
    try testing.expectEqual(999, list.items[999]);
}

test "string builder memory management" {
    var list = std.ArrayList(u8).init(testing.allocator);
    defer list.deinit();

    const writer = list.writer();

    try writer.writeAll("Hello, ");
    try writer.writeAll("sailor!");

    try testing.expectEqualStrings("Hello, sailor!", list.items);
}

test "hash map memory management" {
    var map = std.StringHashMap(u32).init(testing.allocator);
    defer map.deinit();

    try map.put("one", 1);
    try map.put("two", 2);
    try map.put("three", 3);

    try testing.expectEqual(3, map.count());

    const value = map.get("two");
    try testing.expectEqual(2, value.?);
}

test "manual memory management pattern" {
    const allocator = testing.allocator;

    // Allocate
    const buffer = try allocator.create(std.ArrayList(u8));
    defer allocator.destroy(buffer);

    buffer.* = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try buffer.append('x');
    try testing.expectEqual(1, buffer.items.len);
}

test "errdefer for cleanup on error" {
    const allocator = testing.allocator;

    const allocateAndFill = struct {
        fn call(alloc: std.mem.Allocator) ![]u8 {
            const buf = try alloc.alloc(u8, 100);
            errdefer alloc.free(buf);

            // If this fails, errdefer ensures cleanup
            @memset(buf, 42);

            return buf;
        }
    }.call;

    const result = try allocateAndFill(allocator);
    defer allocator.free(result);

    try testing.expectEqual(42, result[0]);
}

test "stack vs heap allocation patterns" {
    // Stack allocation (no cleanup needed)
    var stack_buf: [256]u8 = undefined;
    @memset(&stack_buf, 0);
    try testing.expectEqual(0, stack_buf[0]);

    // Heap allocation (must free)
    const heap_buf = try testing.allocator.alloc(u8, 256);
    defer testing.allocator.free(heap_buf);
    @memset(heap_buf, 1);
    try testing.expectEqual(1, heap_buf[0]);
}

test "comptime allocation is safe" {
    const comptime_data = comptime blk: {
        var data: [10]u32 = undefined;
        for (&data, 0..) |*item, i| {
            item.* = @intCast(i * 2);
        }
        break :blk data;
    };

    try testing.expectEqual(0, comptime_data[0]);
    try testing.expectEqual(18, comptime_data[9]);
}
