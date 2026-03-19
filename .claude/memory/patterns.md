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

## Builder Pattern (Widget API)

Widgets in sailor use a fluent builder pattern for configuration:

```zig
pub const Menu = struct {
    items: []const MenuItem,
    selected: usize = 0,
    // ... fields

    pub fn init(items: []const MenuItem) Menu {
        return .{ .items = items };
    }

    pub fn withSelected(self: Menu, index: usize) Menu {
        var result = self;
        result.selected = index;
        return result;
    }
};

// Usage:
var menu = Menu.init(items)
    .withSelected(1)
    .withBlock(block);
```

**Key points**:
- `init` creates the widget with required fields
- Builder methods (`with*`) take `self` by value, modify a copy, return the modified copy
- Enables method chaining and declarative configuration
- Works well with Zig's struct value semantics
- Variables can be `var` or `const` (both work, but `const` is preferred for immutability)

## Date Arithmetic Pattern (Zeller's Congruence)

Calendar systems use Zeller's congruence for day-of-week calculation:

```zig
// Returns 0=Sunday, 1=Monday, ..., 6=Saturday
pub fn dayOfWeek(self: Date) u3 {
    var m = self.month;
    var y = self.year;

    // Adjust: January=1, February=12, March=1, etc.
    if (m < 3) {
        m += 12;
        y -= 1;
    }

    const q = self.day;
    const k = y % 100;  // Year of century
    const j = y / 100;  // Century

    // Zeller formula (gives 0=Saturday)
    const h = (q + (13 * (m + 1)) / 5 + k + k / 4 + j / 4 - 2 * j) % 7;

    // Convert from Zeller (0=Sat) to custom (0=Sun)
    const day_val = @as(i8, @intCast(h)) - 1;
    return @intCast(@mod(day_val, 7));
}
```

**Key points**:
- Zeller's congruence works for Gregorian calendar (1582+)
- Formula naturally gives 0=Saturday, convert as needed
- Modulo arithmetic: `@mod(negative_i8, 7)` properly handles negatives in Zig
- Use u3 for day-of-week (3 bits = 0-7)

## Calendar Grid Rendering Pattern

Calendar widgets render a 6-week x 7-day grid:

```zig
// Calculate day to display at position (week, day_of_week)
const first_day = Date.init(year, month, 1).dayOfWeek();
const offset = (first_day - first_day_of_week + 7) % 7;

for (0..6) |week| {
    for (0..7) |dow| {
        const total_cells = week * 7 + dow;
        const day_to_show = total_cells + 1 - offset;

        if (day_to_show >= 1 and day_to_show <= days_in_month) {
            // Current month
        } else if (day_to_show < 1) {
            // Previous month
        } else {
            // Next month
        }
    }
}
```

**Key points**:
- `offset` = columns before month starts (0-6)
- `day_to_show` = calculated day number (can be negative or >31)
- Handle all three cases: prev/current/next month
- Apply styles based on: selected > today > in_range > out_of_bounds > default

## Widget Test Pattern (FileBrowser v1.17.0 style)

Comprehensive widget testing with real filesystem operations:

```zig
// Setup: Create temp test directory
fn createTestDir(allocator) !std.fs.Dir {
    var tmp_dir = try std.fs.cwd().makeOpenPath("test_widget_tmp", .{
        .iterate = true,
    });
    try tmp_dir.makePath("subdir1");
    // ... create test files
    return tmp_dir;
}

// Cleanup (defer at test start)
fn cleanupTestDir() void {
    std.fs.cwd().deleteTree("test_widget_tmp") catch {};
}

// Test pattern: isolate with real files
test "widget navigates directory" {
    cleanupTestDir();
    defer cleanupTestDir();

    var tmp_dir = try createTestDir(std.testing.allocator);
    defer tmp_dir.close();

    const cwd_path = try std.fs.cwd().realpathAlloc(allocator, "test_widget_tmp");
    defer allocator.free(cwd_path);

    var widget = try Widget.init(allocator, cwd_path);
    defer widget.deinit();

    try widget.refresh();
    try std.testing.expect(widget.entries.len > 0);
}
```

**Key points**:
- Each test is isolated with its own temp directory
- Real filesystem operations (not mocks) ensure correctness
- Cleanup happens in defer blocks to prevent pollution
- Tests can be run in any order without side effects
- 55+ tests with ~25 lines each achieves comprehensive coverage

**Test Categories for File Browser**:
1. Initialization & Memory (4 tests)
2. Configuration API / Builder (7 tests)
3. Entry Listing & Sorting (7 tests)
4. Navigation & Movement (8 tests)
5. Selection & State (6 tests)
6. Tree Expansion (7 tests)
7. Preview Pane (4 tests)
8. Rendering to Buffer (8 tests)
9. Edge Cases & Errors (4 tests)
10. Search/Filter (2 tests)
11. Performance (3 tests)

## Cross-Platform Verification

Verified targets (all passing):
- x86_64-linux-gnu
- x86_64-windows-msvc
- aarch64-linux-gnu
- x86_64-macos (native)
- aarch64-macos (native)
