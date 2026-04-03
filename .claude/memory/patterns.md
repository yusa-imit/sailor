# Sailor Code Patterns

## Widget Testing Pattern (TDD)
```zig
// PATTERN: Test interface and behavior BEFORE implementation
// 1. Create widget struct with stub render() method
// 2. Write comprehensive tests covering:
//    - Initialization with default config
//    - Builder methods (withX pattern)
//    - Threshold/status evaluation (pure functions first)
//    - Edge cases (zero dimensions, negative values, overflow)
//    - Memory safety (allocator usage, no leaks)
//    - Rendering (stub initially, assert cells after implementation)
// 3. Run tests (should compile, pass with stub)
// 4. Implement render() logic to make meaningful assertions pass

// Example: MetricsPanel widget (v1.33.0)
test "MetricsPanel.evaluateThreshold warning zone" {
    const metric = Metric{
        .name = "Test",
        .value = 75.0,
        .max_value = 100.0,
        .thresholds = .{ .warning = 70.0, .critical = 90.0 },
    };
    const status = MetricsPanel.evaluateThreshold(metric);
    try std.testing.expectEqual(ThresholdStatus.warning, status);
}

test "MetricsPanel.render zero width area" {
    var panel = MetricsPanel.init(std.testing.allocator);
    defer panel.deinit();
    try panel.addMetric(.{ .name = "CPU", .value = 50.0 });

    var buf = try Buffer.init(std.testing.allocator, 10, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    panel.render(buf, area); // Should not crash
}
```

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

## Terminal Widget Pattern (v1.17.0)

Terminal widget for embedding shell sessions with scrollback and ANSI support:

```zig
pub const TerminalWidget = struct {
    lines: std.ArrayList([]const u8),
    scroll_offset: usize = 0,
    pty_fd: i32 = -1,
    child_pid: i32 = -1,
    width: u16 = 80,
    height: u16 = 24,
    allocator: std.mem.Allocator,
    block: ?Block = null,
    text_style: Style = .{},
    max_lines: usize = 10000,
    ansi_state: AnsiParseState = .{},

    pub fn init(allocator: Allocator) !TerminalWidget
    pub fn deinit(self: *TerminalWidget) void
    pub fn addLine(self: *TerminalWidget, line: []const u8) !void
    pub fn clear(self: *TerminalWidget) void
    pub fn lineCount(self: TerminalWidget) usize
    pub fn scrollUp(self: *TerminalWidget, n: usize) void
    pub fn scrollDown(self: *TerminalWidget, n: usize) void
    pub fn visibleLines(self: TerminalWidget) []const []const u8
    pub fn render(self: TerminalWidget, buf: *Buffer, area: Rect) void

    // Builder methods
    pub fn withBlock(self: TerminalWidget, new_block: Block) TerminalWidget
    pub fn withTitle(self: TerminalWidget, title: []const u8) TerminalWidget
    pub fn withMaxLines(self: TerminalWidget, max: usize) TerminalWidget
    pub fn withSize(self: TerminalWidget, width: u16, height: u16) TerminalWidget
};

pub const AnsiParseState = struct {
    cursor_x: u16 = 0,
    cursor_y: u16 = 0,
    foreground: ?Color = null,
    background: ?Color = null,
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    reverse: bool = false,

    pub fn parseSequence(self: *AnsiParseState, seq: []const u8) void
    pub fn reset(self: *AnsiParseState) void
};
```

**Key design patterns**:
- `ArrayList([]const u8)` for line storage (each line is a duped string)
- `scroll_offset` tracks position in history (0 = bottom/newest)
- `visibleLines()` returns slice of lines currently visible in viewport
- `addLine()` enforces `max_lines` limit by removing oldest lines
- `render()` handles block borders via `blk.inner(area)`
- ANSI state machine supports: 0 (reset), 1 (bold), 2 (dim), 3 (italic), 4 (underline), 7 (reverse)
- Builder pattern for fluent configuration

**Test coverage** (43 tests):
- Initialization & cleanup (deinit, GPA leak testing)
- Line management (add, clear, count)
- Scrollback limits and enforcement
- Scroll operations (up/down, bounds, edge cases)
- Visible line calculation (with/without scroll, height constraints)
- Rendering (empty buffer, with content, block wrapping, offset position)
- ANSI state parsing (individual attributes, reset, independence)
- Memory safety (no leaks, proper deallocation)
- Edge cases (empty strings, special chars, zero area, rapid updates, mixed line lengths)

## Environment Variable Testing Pattern

Test environment variables using C bindings (cross-platform):

```zig
// Declare C bindings at top of file
extern "c" fn setenv(key: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(key: [*:0]const u8) c_int;

test "env var with cleanup" {
    _ = setenv("TEST_VAR", "value", 1);
    defer _ = unsetenv("TEST_VAR");

    const result = getEnvVar("TEST_VAR");
    try std.testing.expectEqualStrings("value", result);
}
```

**Key points**:
- Use `setenv/unsetenv` C bindings for test isolation (Zig 0.15.x doesn't provide these)
- Always `defer unsetenv()` to avoid test pollution
- Test both set and unset conditions
- For boolean parsing: test all true values (1/true/yes/on/y), all false values (0/false/no/off/n), case-insensitivity
- For integer parsing: test overflow/underflow, boundary values, invalid format, whitespace rejection
- Memory safety: test leak-free allocations with `std.testing.allocator`

**Test categories for env module** (34 tests):
1. String retrieval: set var, unset var, empty string, memory leak check
2. Boolean parsing: true values (5), false values (5), case-insensitivity (3), edge cases (4)
3. Integer parsing: valid values (2), overflow/underflow (2), invalid format (1), boundary values (3), whitespace/empty (3), unset var (1)

## Cross-Platform Verification

Verified targets (all passing):
- x86_64-linux-gnu
- x86_64-windows-msvc
- aarch64-linux-gnu
- x86_64-macos (native)
- aarch64-macos (native)
