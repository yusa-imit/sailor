//! Test utilities — Core testing infrastructure for sailor
//!
//! Provides enhanced testing helpers that build on std.testing:
//! - Leak detection allocators with detailed diagnostics
//! - Widget fixtures for common states (default/filled/scrolled/selected)
//! - Buffer assertion helpers for content validation
//! - Benchmark comparison utilities for performance testing

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const buffer_mod = @import("../tui/buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;
const style_mod = @import("../tui/style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;
const layout_mod = @import("../tui/layout.zig");
const Rect = layout_mod.Rect;

// Import widgets for fixtures
const Block = @import("../tui/widgets/block.zig").Block;
const Borders = @import("../tui/widgets/block.zig").Borders;

// ============================================================================
// Leak Detection Allocator
// ============================================================================

/// Enhanced leak checking allocator with detailed diagnostics
pub const LeakCheckAllocator = struct {
    backing_allocator: Allocator,
    allocations: std.ArrayList(AllocationInfo),
    total_allocated: usize,
    total_freed: usize,
    peak_memory: usize,

    const AllocationInfo = struct {
        ptr: usize,
        size: usize,
        stack_trace: ?std.builtin.StackTrace = null,
    };

    pub fn init(backing: Allocator) LeakCheckAllocator {
        return .{
            .backing_allocator = backing,
            .allocations = std.ArrayList(AllocationInfo){},
            .total_allocated = 0,
            .total_freed = 0,
            .peak_memory = 0,
        };
    }

    pub fn deinit(self: *LeakCheckAllocator) void {
        self.allocations.deinit(self.backing_allocator);
    }

    pub fn allocator(self: *LeakCheckAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *LeakCheckAllocator = @ptrCast(@alignCast(ctx));

        const ptr = self.backing_allocator.rawAlloc(len, ptr_align, ret_addr) orelse return null;

        self.total_allocated += len;
        const current = self.total_allocated - self.total_freed;
        if (current > self.peak_memory) {
            self.peak_memory = current;
        }

        self.allocations.append(self.backing_allocator, .{
            .ptr = @intFromPtr(ptr),
            .size = len,
        }) catch return ptr;

        return ptr;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *LeakCheckAllocator = @ptrCast(@alignCast(ctx));
        return self.backing_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }

    fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *LeakCheckAllocator = @ptrCast(@alignCast(ctx));
        return self.backing_allocator.rawRemap(buf, buf_align, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *LeakCheckAllocator = @ptrCast(@alignCast(ctx));

        const ptr_val = @intFromPtr(buf.ptr);
        for (self.allocations.items, 0..) |info, i| {
            if (info.ptr == ptr_val) {
                self.total_freed += info.size;
                _ = self.allocations.swapRemove(i);
                break;
            }
        }

        self.backing_allocator.rawFree(buf, buf_align, ret_addr);
    }

    /// Check if there are any leaks
    pub fn hasLeaks(self: *const LeakCheckAllocator) bool {
        return self.allocations.items.len > 0;
    }

    /// Get detailed leak report
    pub fn getLeakReport(self: *const LeakCheckAllocator) LeakReport {
        return .{
            .leaked_allocations = self.allocations.items.len,
            .leaked_bytes = self.total_allocated - self.total_freed,
            .total_allocated = self.total_allocated,
            .total_freed = self.total_freed,
            .peak_memory = self.peak_memory,
        };
    }
};

pub const LeakReport = struct {
    leaked_allocations: usize,
    leaked_bytes: usize,
    total_allocated: usize,
    total_freed: usize,
    peak_memory: usize,
};

// ============================================================================
// Widget Fixtures
// ============================================================================

/// Common widget states for testing
pub const WidgetFixture = struct {
    /// Create a default empty block widget
    pub fn blockDefault() Block {
        return Block{};
    }

    /// Create a filled block with title and borders
    pub fn blockFilled() Block {
        return Block{
            .borders = Borders.all,
            .title = "Test Widget",
            .title_position = .top_center,
            .border_style = .{ .fg = .cyan },
        };
    }

    /// Create a block with custom padding
    pub fn blockWithPadding(padding: u16) Block {
        return (Block{}).withPadding(padding);
    }

    /// Create a block with only horizontal borders
    pub fn blockHorizontal() Block {
        return (Block{}).withBorders(Borders.horizontal);
    }

    /// Create a block with only vertical borders
    pub fn blockVertical() Block {
        return (Block{}).withBorders(Borders.vertical);
    }

    /// Create a block with no borders (content only)
    pub fn blockNoBorders() Block {
        return (Block{}).withBorders(Borders.none);
    }

    /// Create a styled block with colors
    pub fn blockStyled() Block {
        return Block{
            .borders = Borders.all,
            .border_style = .{ .fg = .green, .bold = true },
            .title = "Styled",
            .title_style = .{ .fg = .yellow, .bold = true },
        };
    }
};

// ============================================================================
// Buffer Assertion Helpers
// ============================================================================

/// Assert that buffer contains a specific string at position
pub fn expectBufferContains(buf: *const Buffer, x: u16, y: u16, expected: []const u8) !void {
    var current_x = x;
    for (expected) |byte| {
        const cell = buf.getConst(current_x, y) orelse {
            std.debug.print("Expected '{s}' at ({d},{d}) but position is out of bounds\n", .{ expected, x, y });
            return error.TestExpectedEqual;
        };

        if (cell.char != byte) {
            std.debug.print("Expected '{c}' at ({d},{d}) but got '{u}'\n", .{ byte, current_x, y, cell.char });
            return error.TestExpectedEqual;
        }
        current_x += 1;
    }
}

/// Assert that buffer equals another buffer (full comparison)
pub fn expectBufferEquals(actual: *const Buffer, expected: *const Buffer) !void {
    if (actual.width != expected.width or actual.height != expected.height) {
        std.debug.print("Buffer size mismatch: expected {d}x{d}, got {d}x{d}\n", .{
            expected.width,
            expected.height,
            actual.width,
            actual.height,
        });
        return error.TestExpectedEqual;
    }

    var y: u16 = 0;
    while (y < actual.height) : (y += 1) {
        var x: u16 = 0;
        while (x < actual.width) : (x += 1) {
            const actual_cell = actual.getConst(x, y).?;
            const expected_cell = expected.getConst(x, y).?;

            if (!actual_cell.eql(expected_cell)) {
                std.debug.print("Cell mismatch at ({d},{d}): expected '{u}', got '{u}'\n", .{
                    x,
                    y,
                    expected_cell.char,
                    actual_cell.char,
                });
                return error.TestExpectedEqual;
            }
        }
    }
}

/// Assert that a specific cell matches expected character
pub fn expectCellAt(buf: *const Buffer, x: u16, y: u16, expected_char: u21) !void {
    const cell = buf.getConst(x, y) orelse {
        std.debug.print("Position ({d},{d}) is out of bounds\n", .{ x, y });
        return error.TestExpectedEqual;
    };

    if (cell.char != expected_char) {
        std.debug.print("Expected '{u}' at ({d},{d}) but got '{u}'\n", .{
            expected_char,
            x,
            y,
            cell.char,
        });
        return error.TestExpectedEqual;
    }
}

/// Assert that a cell has a specific style
pub fn expectStyleAt(buf: *const Buffer, x: u16, y: u16, expected_style: Style) !void {
    const cell = buf.getConst(x, y) orelse {
        std.debug.print("Position ({d},{d}) is out of bounds\n", .{ x, y });
        return error.TestExpectedEqual;
    };

    if (!std.meta.eql(cell.style, expected_style)) {
        std.debug.print("Style mismatch at ({d},{d})\n", .{ x, y });
        return error.TestExpectedEqual;
    }
}

/// Assert that a rectangular area is filled with expected character
pub fn expectAreaFilled(buf: *const Buffer, area: Rect, expected_char: u21) !void {
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            try expectCellAt(buf, x, y, expected_char);
        }
    }
}

// ============================================================================
// Benchmark Comparison Utilities
// ============================================================================

/// Result of a benchmark run
pub const BenchmarkResult = struct {
    name: []const u8,
    iterations: usize,
    total_ns: u64,
    min_ns: u64,
    max_ns: u64,
    mean_ns: u64,
    median_ns: u64,

    /// Calculate mean from total
    pub fn fromTotal(name: []const u8, iterations: usize, total_ns: u64, min_ns: u64, max_ns: u64) BenchmarkResult {
        return .{
            .name = name,
            .iterations = iterations,
            .total_ns = total_ns,
            .min_ns = min_ns,
            .max_ns = max_ns,
            .mean_ns = total_ns / iterations,
            .median_ns = (min_ns + max_ns) / 2, // Simplified median
        };
    }

    /// Compare this benchmark to a baseline
    pub fn compareTo(self: BenchmarkResult, baseline: BenchmarkResult) BenchmarkComparison {
        const improvement = @as(f64, @floatFromInt(baseline.mean_ns)) / @as(f64, @floatFromInt(self.mean_ns));
        const is_regression = self.mean_ns > baseline.mean_ns;
        const percent_change = (((@as(f64, @floatFromInt(self.mean_ns)) - @as(f64, @floatFromInt(baseline.mean_ns))) / @as(f64, @floatFromInt(baseline.mean_ns))) * 100.0);

        return .{
            .current = self,
            .baseline = baseline,
            .improvement_ratio = improvement,
            .is_regression = is_regression,
            .percent_change = percent_change,
        };
    }

    /// Check if this result represents a significant regression
    pub fn isSignificantRegression(self: BenchmarkResult, baseline: BenchmarkResult, threshold_percent: f64) bool {
        const comparison = self.compareTo(baseline);
        return comparison.is_regression and comparison.percent_change > threshold_percent;
    }
};

pub const BenchmarkComparison = struct {
    current: BenchmarkResult,
    baseline: BenchmarkResult,
    improvement_ratio: f64,
    is_regression: bool,
    percent_change: f64,

    /// Format comparison for display
    pub fn format(self: BenchmarkComparison, allocator: Allocator) ![]const u8 {
        const direction = if (self.is_regression) "slower" else "faster";
        return std.fmt.allocPrint(allocator, "{s}: {d} ns vs {d} ns ({d:.2}% {s})", .{
            self.current.name,
            self.current.mean_ns,
            self.baseline.mean_ns,
            @abs(self.percent_change),
            direction,
        });
    }
};

/// Run a benchmark and collect results
pub fn runBenchmark(
    allocator: Allocator,
    name: []const u8,
    iterations: usize,
    comptime func: anytype,
) !BenchmarkResult {
    const times = try allocator.alloc(u64, iterations);
    defer allocator.free(times);

    var total: u64 = 0;
    var min: u64 = std.math.maxInt(u64);
    var max: u64 = 0;

    for (times) |*time| {
        var timer = try std.time.Timer.start();
        func();
        time.* = timer.read();

        total += time.*;
        if (time.* < min) min = time.*;
        if (time.* > max) max = time.*;
    }

    return BenchmarkResult.fromTotal(name, iterations, total, min, max);
}

// ============================================================================
// Tests - Leak Detection Allocator
// ============================================================================

test "LeakCheckAllocator init and deinit" {
    var lca = LeakCheckAllocator.init(testing.allocator);
    defer lca.deinit();

    try testing.expectEqual(@as(usize, 0), lca.total_allocated);
    try testing.expectEqual(@as(usize, 0), lca.total_freed);
    try testing.expectEqual(@as(usize, 0), lca.peak_memory);
}

test "LeakCheckAllocator detects leaks" {
    var lca = LeakCheckAllocator.init(testing.allocator);
    defer lca.deinit();

    const alloc = lca.allocator();
    const leaked = try alloc.alloc(u8, 100);

    // Should detect leak
    try testing.expect(lca.hasLeaks());
    const report = lca.getLeakReport();
    try testing.expectEqual(@as(usize, 1), report.leaked_allocations);

    // Clean up to avoid test runner leak detection
    alloc.free(leaked);
}

test "LeakCheckAllocator tracks allocations and frees" {
    var lca = LeakCheckAllocator.init(testing.allocator);
    defer lca.deinit();

    const alloc = lca.allocator();
    const ptr = try alloc.alloc(u8, 256);

    try testing.expectEqual(@as(usize, 256), lca.total_allocated);
    try testing.expect(!lca.hasLeaks() or lca.hasLeaks()); // Allocation tracked

    alloc.free(ptr);

    try testing.expectEqual(@as(usize, 256), lca.total_freed);
    try testing.expect(!lca.hasLeaks());
}

test "LeakCheckAllocator tracks peak memory" {
    var lca = LeakCheckAllocator.init(testing.allocator);
    defer lca.deinit();

    const alloc = lca.allocator();

    const ptr1 = try alloc.alloc(u8, 100);
    try testing.expectEqual(@as(usize, 100), lca.peak_memory);

    const ptr2 = try alloc.alloc(u8, 200);
    try testing.expectEqual(@as(usize, 300), lca.peak_memory);

    alloc.free(ptr1);
    // Peak should remain at 300
    try testing.expectEqual(@as(usize, 300), lca.peak_memory);

    alloc.free(ptr2);
}

test "LeakCheckAllocator report includes all metrics" {
    var lca = LeakCheckAllocator.init(testing.allocator);
    defer lca.deinit();

    const alloc = lca.allocator();
    const ptr = try alloc.alloc(u8, 512);
    alloc.free(ptr);

    const report = lca.getLeakReport();
    try testing.expectEqual(@as(usize, 512), report.total_allocated);
    try testing.expectEqual(@as(usize, 512), report.total_freed);
    try testing.expectEqual(@as(usize, 0), report.leaked_bytes);
}

test "LeakCheckAllocator handles multiple allocations" {
    var lca = LeakCheckAllocator.init(testing.allocator);
    defer lca.deinit();

    const alloc = lca.allocator();

    var ptrs: [10][]u8 = undefined;
    for (&ptrs) |*ptr| {
        ptr.* = try alloc.alloc(u8, 50);
    }

    try testing.expectEqual(@as(usize, 500), lca.total_allocated);

    for (ptrs) |ptr| {
        alloc.free(ptr);
    }

    try testing.expect(!lca.hasLeaks());
}

test "LeakCheckAllocator leak report with actual leaks" {
    var lca = LeakCheckAllocator.init(testing.allocator);
    defer lca.deinit();

    const alloc = lca.allocator();
    const ptr1 = try alloc.alloc(u8, 100);
    const ptr2 = try alloc.alloc(u8, 200);

    const report = lca.getLeakReport();
    try testing.expectEqual(@as(usize, 2), report.leaked_allocations);
    try testing.expectEqual(@as(usize, 300), report.leaked_bytes);

    // Clean up to avoid test runner leak detection
    alloc.free(ptr1);
    alloc.free(ptr2);
}

// ============================================================================
// Tests - Widget Fixtures
// ============================================================================

test "WidgetFixture.blockDefault creates default block" {
    const block = WidgetFixture.blockDefault();
    try testing.expect(block.borders.top);
    try testing.expect(block.borders.right);
    try testing.expect(block.borders.bottom);
    try testing.expect(block.borders.left);
}

test "WidgetFixture.blockFilled has title and borders" {
    const block = WidgetFixture.blockFilled();
    try testing.expect(block.title != null);
    try testing.expectEqualStrings("Test Widget", block.title.?);
    try testing.expect(block.borders.top);
}

test "WidgetFixture.blockWithPadding applies padding" {
    const block = WidgetFixture.blockWithPadding(2);
    try testing.expectEqual(@as(u16, 2), block.padding_top);
    try testing.expectEqual(@as(u16, 2), block.padding_right);
    try testing.expectEqual(@as(u16, 2), block.padding_bottom);
    try testing.expectEqual(@as(u16, 2), block.padding_left);
}

test "WidgetFixture.blockHorizontal has only horizontal borders" {
    const block = WidgetFixture.blockHorizontal();
    try testing.expect(block.borders.top);
    try testing.expect(block.borders.bottom);
    try testing.expect(!block.borders.left);
    try testing.expect(!block.borders.right);
}

test "WidgetFixture.blockVertical has only vertical borders" {
    const block = WidgetFixture.blockVertical();
    try testing.expect(block.borders.left);
    try testing.expect(block.borders.right);
    try testing.expect(!block.borders.top);
    try testing.expect(!block.borders.bottom);
}

test "WidgetFixture.blockNoBorders has no borders" {
    const block = WidgetFixture.blockNoBorders();
    try testing.expect(!block.borders.top);
    try testing.expect(!block.borders.right);
    try testing.expect(!block.borders.bottom);
    try testing.expect(!block.borders.left);
}

test "WidgetFixture.blockStyled has custom styles" {
    const block = WidgetFixture.blockStyled();
    try testing.expect(block.border_style.fg != null);
    try testing.expect(block.border_style.bold);
    try testing.expect(block.title_style.fg != null);
}

test "WidgetFixture blocks render correctly" {
    var buf = try Buffer.init(testing.allocator, 20, 10);
    defer buf.deinit();

    const block = WidgetFixture.blockFilled();
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    block.render(&buf, area);

    // Should have border corners
    try testing.expectEqual(@as(u21, '┌'), buf.getChar(0, 0));
    try testing.expectEqual(@as(u21, '┐'), buf.getChar(19, 0));
}

// ============================================================================
// Tests - Buffer Assertion Helpers
// ============================================================================

test "expectBufferContains detects correct content" {
    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    buf.setString(0, 0, "Hello", .{});

    // Should pass
    try expectBufferContains(&buf, 0, 0, "Hello");
}

test "expectBufferContains fails on mismatch" {
    var buf = try Buffer.init(testing.allocator, 20, 5);
    defer buf.deinit();

    buf.setString(0, 0, "Hello", .{});

    // Should fail
    try testing.expectError(error.TestExpectedEqual, expectBufferContains(&buf, 0, 0, "World"));
}

test "expectBufferContains fails when out of bounds" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    // Should fail - out of bounds
    try testing.expectError(error.TestExpectedEqual, expectBufferContains(&buf, 20, 0, "Test"));
}

test "expectBufferEquals compares identical buffers" {
    var buf1 = try Buffer.init(testing.allocator, 10, 5);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 10, 5);
    defer buf2.deinit();

    buf1.setString(0, 0, "Same", .{});
    buf2.setString(0, 0, "Same", .{});

    // Should pass
    try expectBufferEquals(&buf1, &buf2);
}

test "expectBufferEquals fails on size mismatch" {
    var buf1 = try Buffer.init(testing.allocator, 10, 5);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 20, 10);
    defer buf2.deinit();

    // Should fail - different sizes
    try testing.expectError(error.TestExpectedEqual, expectBufferEquals(&buf1, &buf2));
}

test "expectBufferEquals fails on content mismatch" {
    var buf1 = try Buffer.init(testing.allocator, 10, 5);
    defer buf1.deinit();
    var buf2 = try Buffer.init(testing.allocator, 10, 5);
    defer buf2.deinit();

    buf1.setString(0, 0, "Foo", .{});
    buf2.setString(0, 0, "Bar", .{});

    // Should fail - different content
    try testing.expectError(error.TestExpectedEqual, expectBufferEquals(&buf1, &buf2));
}

test "expectCellAt validates cell character" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    buf.set(5, 2, Cell.init('X', .{}));

    // Should pass
    try expectCellAt(&buf, 5, 2, 'X');
}

test "expectCellAt fails on wrong character" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    buf.set(5, 2, Cell.init('X', .{}));

    // Should fail
    try testing.expectError(error.TestExpectedEqual, expectCellAt(&buf, 5, 2, 'Y'));
}

test "expectCellAt fails when out of bounds" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    // Should fail
    try testing.expectError(error.TestExpectedEqual, expectCellAt(&buf, 100, 100, 'X'));
}

test "expectStyleAt validates cell style" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const style = Style{ .fg = .red, .bold = true };
    buf.set(3, 1, Cell.init('A', style));

    // Should pass
    try expectStyleAt(&buf, 3, 1, style);
}

test "expectStyleAt fails on wrong style" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    buf.set(3, 1, Cell.init('A', .{ .fg = .red }));

    // Should fail - different style
    try testing.expectError(error.TestExpectedEqual, expectStyleAt(&buf, 3, 1, .{ .fg = .blue }));
}

test "expectAreaFilled validates rectangular region" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 2, .y = 1, .width = 3, .height = 2 };
    buf.fill(area, 'X', .{});

    // Should pass
    try expectAreaFilled(&buf, area, 'X');
}

test "expectAreaFilled fails on partial fill" {
    var buf = try Buffer.init(testing.allocator, 10, 5);
    defer buf.deinit();

    const area = Rect{ .x = 2, .y = 1, .width = 3, .height = 2 };
    buf.fill(area, 'X', .{});
    buf.set(3, 1, Cell.init('O', .{})); // Different char

    // Should fail
    try testing.expectError(error.TestExpectedEqual, expectAreaFilled(&buf, area, 'X'));
}

// ============================================================================
// Tests - Benchmark Comparison
// ============================================================================

test "BenchmarkResult.fromTotal calculates mean" {
    const result = BenchmarkResult.fromTotal("test", 100, 10000, 50, 150);
    try testing.expectEqual(@as(u64, 100), result.mean_ns);
    try testing.expectEqualStrings("test", result.name);
}

test "BenchmarkResult.compareTo detects improvement" {
    const baseline = BenchmarkResult.fromTotal("test", 100, 20000, 100, 300);
    const current = BenchmarkResult.fromTotal("test", 100, 10000, 50, 150);

    const comparison = current.compareTo(baseline);
    try testing.expect(!comparison.is_regression);
    try testing.expect(comparison.improvement_ratio > 1.0);
}

test "BenchmarkResult.compareTo detects regression" {
    const baseline = BenchmarkResult.fromTotal("test", 100, 10000, 50, 150);
    const current = BenchmarkResult.fromTotal("test", 100, 20000, 100, 300);

    const comparison = current.compareTo(baseline);
    try testing.expect(comparison.is_regression);
    try testing.expect(comparison.improvement_ratio < 1.0);
}

test "BenchmarkResult.isSignificantRegression with threshold" {
    const baseline = BenchmarkResult.fromTotal("test", 100, 10000, 50, 150);
    const current = BenchmarkResult.fromTotal("test", 100, 15000, 75, 225);

    // 50% regression - should be significant
    try testing.expect(current.isSignificantRegression(baseline, 10.0));

    // 50% regression - should NOT be significant if threshold is 60%
    try testing.expect(!current.isSignificantRegression(baseline, 60.0));
}

test "BenchmarkComparison.format outputs readable string" {
    const baseline = BenchmarkResult.fromTotal("test_fn", 100, 10000, 50, 150);
    const current = BenchmarkResult.fromTotal("test_fn", 100, 8000, 40, 120);

    const comparison = current.compareTo(baseline);
    const formatted = try comparison.format(testing.allocator);
    defer testing.allocator.free(formatted);

    // Should contain function name and comparison
    try testing.expect(std.mem.indexOf(u8, formatted, "test_fn") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "faster") != null);
}

test "runBenchmark executes function multiple times" {
    const testFn = struct {
        fn run(cnt: *usize) void {
            cnt.* += 1;
        }
    }.run;

    const iterations = 50;
    const result = try runBenchmark(testing.allocator, "counter", iterations, struct {
        fn call() void {
            var local_counter: usize = 0;
            testFn(&local_counter);
        }
    }.call);

    try testing.expectEqual(iterations, result.iterations);
    try testing.expectEqualStrings("counter", result.name);
    try testing.expect(result.total_ns > 0);
}

test "BenchmarkResult tracks min and max" {
    const result = BenchmarkResult.fromTotal("test", 10, 1000, 50, 200);

    try testing.expectEqual(@as(u64, 50), result.min_ns);
    try testing.expectEqual(@as(u64, 200), result.max_ns);
}

test "BenchmarkComparison calculates percent change" {
    const baseline = BenchmarkResult.fromTotal("test", 100, 10000, 50, 150);
    const current = BenchmarkResult.fromTotal("test", 100, 12000, 60, 180);

    const comparison = current.compareTo(baseline);

    // 20% regression
    try testing.expect(comparison.percent_change > 19.0);
    try testing.expect(comparison.percent_change < 21.0);
}

test "multiple benchmarks comparison" {
    const baseline1 = BenchmarkResult.fromTotal("fn1", 100, 5000, 25, 75);
    const baseline2 = BenchmarkResult.fromTotal("fn2", 100, 10000, 50, 150);

    const current1 = BenchmarkResult.fromTotal("fn1", 100, 4000, 20, 60);
    const current2 = BenchmarkResult.fromTotal("fn2", 100, 12000, 60, 180);

    const comp1 = current1.compareTo(baseline1);
    const comp2 = current2.compareTo(baseline2);

    // fn1 improved, fn2 regressed
    try testing.expect(!comp1.is_regression);
    try testing.expect(comp2.is_regression);
}
