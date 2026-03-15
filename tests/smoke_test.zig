//! Smoke tests — validate build system and test infrastructure
//!
//! These tests ensure:
//! - Test framework is working
//! - Cross-platform compilation guards work
//! - Memory utilities are available
//! - Writer-based testing patterns work

const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");

test "test framework is operational" {
    // Verify basic arithmetic works in tests
    const result = 2 + 2;
    try testing.expectEqual(4, result);
}

test "platform detection works" {
    const is_windows = builtin.os.tag == .windows;
    const is_linux = builtin.os.tag == .linux;
    const is_macos = builtin.os.tag == .macos;

    // At least one platform should be true
    try testing.expect(is_windows or is_linux or is_macos);
}

test "allocator basics" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const buf = try allocator.alloc(u8, 100);
    defer allocator.free(buf);

    try testing.expect(buf.len == 100);
}

test "fixed buffer stream for writer testing" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try writer.writeAll("Hello, sailor!");

    const written = fbs.getWritten();
    try testing.expectEqualStrings("Hello, sailor!", written);
}

test "comptime string operations" {
    const str = "sailor";
    try testing.expectEqual(6, str.len);
    try testing.expect(std.mem.eql(u8, str, "sailor"));
}

test "error handling patterns" {
    const TestError = error{
        InvalidInput,
        NotATty,
    };

    const result: TestError!u32 = TestError.InvalidInput;

    if (result) |_| {
        try testing.expect(false); // Should not reach
    } else |err| {
        try testing.expectEqual(TestError.InvalidInput, err);
    }
}

test "unicode support" {
    const unicode_str = "🚢 sailor";
    try testing.expect(unicode_str.len > 0);

    // Test that we can handle UTF-8
    var count: usize = 0;
    var iter = std.unicode.Utf8View.initUnchecked(unicode_str).iterator();
    while (iter.nextCodepoint()) |_| {
        count += 1;
    }

    try testing.expect(count > 0);
}

test "writer-based API pattern" {
    // This pattern is MANDATORY for all sailor modules
    // No stdout/stderr allowed — always write to user-provided Writer

    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    // Simulate a library function that writes output
    const writeOutput = struct {
        fn call(writer: anytype, msg: []const u8) !void {
            try writer.writeAll(msg);
        }
    }.call;

    try writeOutput(fbs.writer(), "test");
    try testing.expectEqualStrings("test", fbs.getWritten());
}

test "no global state pattern" {
    // All state should be in structs, caller owns lifetime

    const Counter = struct {
        value: u32,

        pub fn init() @This() {
            return .{ .value = 0 };
        }

        pub fn increment(self: *@This()) void {
            self.value += 1;
        }
    };

    var counter1 = Counter.init();
    const counter2 = Counter.init();

    counter1.increment();

    try testing.expectEqual(1, counter1.value);
    try testing.expectEqual(0, counter2.value);
}

test "cross-platform path handling" {
    const sep = std.fs.path.sep;

    if (builtin.os.tag == .windows) {
        try testing.expectEqual('\\', sep);
    } else {
        try testing.expectEqual('/', sep);
    }
}

test "arena allocator pattern for request-scoped work" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Allocate multiple things without manual free
    const buf1 = try allocator.alloc(u8, 100);
    const buf2 = try allocator.alloc(u8, 200);

    try testing.expect(buf1.len == 100);
    try testing.expect(buf2.len == 200);

    // Arena cleanup happens in defer
}
