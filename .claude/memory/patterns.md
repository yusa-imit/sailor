# Sailor Code Patterns

## Library Output Pattern
```zig
// WRONG: direct stdout
std.debug.print("hello\n", .{});

// RIGHT: writer-based
pub fn render(self: Self, writer: anytype) !void {
    try writer.print("hello\n", .{});
}
```

## Test Output Capture Pattern
```zig
test "renders correctly" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try myModule.render(stream.writer());
    try std.testing.expectEqualStrings("expected output", stream.getWritten());
}
```

## Cross-Platform Guard Pattern
```zig
const builtin = @import("builtin");

pub fn enableRawMode() !RawMode {
    if (comptime builtin.os.tag == .windows) {
        return enableRawModeWindows();
    } else {
        return enableRawModePosix();
    }
}
```

## RAII Cleanup Pattern
```zig
pub fn init(allocator: Allocator) !Self {
    const buf = try allocator.alloc(Cell, width * height);
    return .{ .allocator = allocator, .cells = buf };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.cells);
}

// Caller:
var obj = try Thing.init(allocator);
defer obj.deinit();
```

## Test Infrastructure Pattern
```zig
// Smoke tests in tests/smoke_test.zig validate:
// - Test framework operational
// - Platform detection (Windows/Linux/macOS)
// - Allocator basics (GPA, arena)
// - Writer-based testing with fixedBufferStream
// - Error handling patterns
// - Unicode support
// - No global state pattern
// - Cross-platform path handling

// Build system runs both:
// 1. lib_tests (src/sailor.zig and all module tests)
// 2. smoke_tests (tests/*.zig standalone tests)
```
