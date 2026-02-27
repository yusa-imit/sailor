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
// Test organization (73 tests total):
// - tests/smoke_test.zig (12 tests): basic patterns, allocators, writers
// - tests/cross_platform_test.zig (17 tests): OS/arch detection, Unicode, platform-specific behavior
// - tests/memory_safety_test.zig (20 tests): GPA leak detection, bounds checking, alignment
// - tests/build_verification_test.zig (24 tests): compiler settings, target verification, dependency validation

// Build system runs both:
// 1. lib_tests (src/sailor.zig and all module tests)
// 2. smoke_tests (tests/*.zig standalone tests)
```

## Memory Safety Patterns

### GPA Leak Detection
```zig
test "no leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        testing.expect(leaked == .ok) catch @panic("memory leak detected");
    }
    const allocator = gpa.allocator();
    // allocations here
}
```

### Arena for Request-Scoped Work
```zig
var arena = std.heap.ArenaAllocator.init(gpa.allocator());
defer arena.deinit();
const allocator = arena.allocator();
// Multiple allocations without individual frees
```

### Error Cleanup
```zig
const buf = try allocator.alloc(u8, 100);
errdefer allocator.free(buf);
// If error occurs after this, buf is freed
```

## Cross-Platform Verification

Verified targets (all passing):
- x86_64-linux-gnu
- x86_64-windows-msvc
- aarch64-linux-gnu
- x86_64-macos (native)
- aarch64-macos (native)
