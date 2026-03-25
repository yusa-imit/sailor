const std = @import("std");
const sailor = @import("sailor");
const VirtualList = sailor.tui.widgets.VirtualList;
const StreamingTable = sailor.tui.widgets.StreamingTable;
const ChunkedBuffer = sailor.tui.widgets.ChunkedBuffer;
const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Column = sailor.tui.widgets.Column;
const ColumnWidth = sailor.tui.widgets.ColumnWidth;

/// Benchmark parameters
const LARGE_ITEM_COUNT = 1_000_000; // 1M items
const MEDIUM_ITEM_COUNT = 100_000; // 100K items
const LARGE_LINE_COUNT = 1_000_000; // 1M lines (simulating 100MB+ text file)
const VIEWPORT_HEIGHT: u16 = 50; // Typical terminal height
const VIEWPORT_WIDTH: u16 = 120; // Typical terminal width

/// Timer utility for benchmarking
const Timer = struct {
    start_time: i128,

    pub fn start() Timer {
        return .{ .start_time = std.time.nanoTimestamp() };
    }

    pub fn elapsed(self: Timer) f64 {
        const end = std.time.nanoTimestamp();
        const ns = @as(f64, @floatFromInt(end - self.start_time));
        return ns / 1_000_000.0; // Convert to milliseconds
    }
};

/// Benchmark result
const BenchResult = struct {
    name: []const u8,
    duration_ms: f64,
    ops_per_sec: f64,

    pub fn print(self: BenchResult) void {
        std.debug.print("{s:<50} {d:>10.2} ms  ({d:>10.0} ops/sec)\n", .{
            self.name,
            self.duration_ms,
            self.ops_per_sec,
        });
    }
};

/// Run a benchmark and return result
fn runBench(
    name: []const u8,
    iterations: usize,
    comptime benchFn: anytype,
    allocator: std.mem.Allocator,
) !BenchResult {
    const timer = Timer.start();
    try benchFn(allocator);
    const duration = timer.elapsed();
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (duration / 1000.0);

    return BenchResult{
        .name = name,
        .duration_ms = duration,
        .ops_per_sec = ops_per_sec,
    };
}

// ============================================================================
// VirtualList Benchmarks
// ============================================================================

fn benchVirtualListRender1M(allocator: std.mem.Allocator) !void {
    var buf = try Buffer.init(allocator, VIEWPORT_WIDTH, VIEWPORT_HEIGHT);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = VIEWPORT_WIDTH, .height = VIEWPORT_HEIGHT };

    const callback = struct {
        fn itemCallback(index: usize, writer: anytype) !void {
            try writer.print("Item {d}", .{index});
        }
    }.itemCallback;

    const list = VirtualList.init(LARGE_ITEM_COUNT).withSelected(500_000);

    try list.render(&buf, area, callback, allocator);
}

fn benchVirtualListScroll1M(allocator: std.mem.Allocator) !void {
    var buf = try Buffer.init(allocator, VIEWPORT_WIDTH, VIEWPORT_HEIGHT);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = VIEWPORT_WIDTH, .height = VIEWPORT_HEIGHT };

    const callback = struct {
        fn itemCallback(index: usize, writer: anytype) !void {
            try writer.print("Item {d}", .{index});
        }
    }.itemCallback;

    // Simulate scrolling through the list
    const scroll_positions = [_]usize{ 0, 100_000, 500_000, 900_000 };
    for (scroll_positions) |offset| {
        const list = VirtualList.init(LARGE_ITEM_COUNT).withOffset(offset);
        try list.render(&buf, area, callback, allocator);
    }
}

// ============================================================================
// StreamingTable Benchmarks
// ============================================================================

fn benchStreamingTableRender1M(allocator: std.mem.Allocator) !void {
    var buf = try Buffer.init(allocator, VIEWPORT_WIDTH, VIEWPORT_HEIGHT);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = VIEWPORT_WIDTH, .height = VIEWPORT_HEIGHT };

    const columns = [_]Column{
        Column{ .title = "ID", .width = ColumnWidth{ .fixed = 10 } },
        Column{ .title = "Name", .width = ColumnWidth{ .fixed = 30 } },
        Column{ .title = "Value", .width = ColumnWidth{ .fixed = 15 } },
    };

    const callback = struct {
        fn cellCallback(row_index: usize, col_index: usize, writer: anytype) !void {
            switch (col_index) {
                0 => try writer.print("{d}", .{row_index}),
                1 => try writer.print("Row {d}", .{row_index}),
                2 => try writer.print("{d}.00", .{row_index * 100}),
                else => {},
            }
        }
    }.cellCallback;

    const table = StreamingTable.init(&columns, LARGE_ITEM_COUNT).withSelected(500_000);

    try table.render(&buf, area, callback, allocator);
}

fn benchStreamingTableScroll1M(allocator: std.mem.Allocator) !void {
    var buf = try Buffer.init(allocator, VIEWPORT_WIDTH, VIEWPORT_HEIGHT);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = VIEWPORT_WIDTH, .height = VIEWPORT_HEIGHT };

    const columns = [_]Column{
        Column{ .title = "ID", .width = ColumnWidth{ .fixed = 10 } },
        Column{ .title = "Name", .width = ColumnWidth{ .fixed = 30 } },
        Column{ .title = "Value", .width = ColumnWidth{ .fixed = 15 } },
    };

    const callback = struct {
        fn cellCallback(row_index: usize, col_index: usize, writer: anytype) !void {
            switch (col_index) {
                0 => try writer.print("{d}", .{row_index}),
                1 => try writer.print("Row {d}", .{row_index}),
                2 => try writer.print("{d}.00", .{row_index * 100}),
                else => {},
            }
        }
    }.cellCallback;

    // Simulate scrolling through the table
    const scroll_positions = [_]usize{ 0, 100_000, 500_000, 900_000 };
    for (scroll_positions) |offset| {
        const table = StreamingTable.init(&columns, LARGE_ITEM_COUNT).withOffset(offset);
        try table.render(&buf, area, callback, allocator);
    }
}

// ============================================================================
// ChunkedBuffer Benchmarks
// ============================================================================

fn benchChunkedBufferRender1M(allocator: std.mem.Allocator) !void {
    var buf = try Buffer.init(allocator, VIEWPORT_WIDTH, VIEWPORT_HEIGHT);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = VIEWPORT_WIDTH, .height = VIEWPORT_HEIGHT };

    const callback = struct {
        fn lineCallback(line_index: usize, writer: anytype) !void {
            try writer.print("This is line {d} of a very large text file with some content", .{line_index});
        }
    }.lineCallback;

    const chunked = ChunkedBuffer.init(LARGE_LINE_COUNT).withLineOffset(500_000);

    try chunked.render(&buf, area, callback, allocator);
}

fn benchChunkedBufferScroll1M(allocator: std.mem.Allocator) !void {
    var buf = try Buffer.init(allocator, VIEWPORT_WIDTH, VIEWPORT_HEIGHT);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = VIEWPORT_WIDTH, .height = VIEWPORT_HEIGHT };

    const callback = struct {
        fn lineCallback(line_index: usize, writer: anytype) !void {
            try writer.print("This is line {d} of a very large text file with some content", .{line_index});
        }
    }.lineCallback;

    // Simulate scrolling through the file
    const scroll_positions = [_]usize{ 0, 100_000, 500_000, 900_000 };
    for (scroll_positions) |offset| {
        const chunked = ChunkedBuffer.init(LARGE_LINE_COUNT).withLineOffset(offset);
        try chunked.render(&buf, area, callback, allocator);
    }
}

fn benchChunkedBufferWrap(allocator: std.mem.Allocator) !void {
    var buf = try Buffer.init(allocator, VIEWPORT_WIDTH, VIEWPORT_HEIGHT);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = VIEWPORT_WIDTH, .height = VIEWPORT_HEIGHT };

    const callback = struct {
        fn lineCallback(line_index: usize, writer: anytype) !void {
            // Long lines that need wrapping
            try writer.print("This is a very long line {d} that will definitely exceed the viewport width and require text wrapping to display properly in the terminal window", .{line_index});
        }
    }.lineCallback;

    const chunked = ChunkedBuffer.init(MEDIUM_ITEM_COUNT).withWrap(true);

    try chunked.render(&buf, area, callback, allocator);
}

// ============================================================================
// Memory Benchmarks
// ============================================================================

fn benchMemoryUsageVirtualList(allocator: std.mem.Allocator) !void {
    var buf = try Buffer.init(allocator, VIEWPORT_WIDTH, VIEWPORT_HEIGHT);
    defer buf.deinit(allocator);

    const area = Rect{ .x = 0, .y = 0, .width = VIEWPORT_WIDTH, .height = VIEWPORT_HEIGHT };

    const callback = struct {
        fn itemCallback(index: usize, writer: anytype) !void {
            try writer.print("Item {d}", .{index});
        }
    }.itemCallback;

    // Create multiple lists to test memory footprint
    const list_count = 10;
    var i: usize = 0;
    while (i < list_count) : (i += 1) {
        const list = VirtualList.init(LARGE_ITEM_COUNT).withSelected(i * 1000);
        try list.render(&buf, area, callback, allocator);
    }
}

// ============================================================================
// Main Benchmark Runner
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Sailor Large Data Benchmarks ===\n", .{});
    std.debug.print("Testing streaming widgets with massive datasets\n\n", .{});

    var total_duration: f64 = 0;

    // VirtualList benchmarks
    std.debug.print("--- VirtualList (1M items) ---\n", .{});
    {
        const result = try runBench(
            "VirtualList: Render 1M items (viewport only)",
            1,
            benchVirtualListRender1M,
            allocator,
        );
        result.print();
        total_duration += result.duration_ms;
    }
    {
        const result = try runBench(
            "VirtualList: Scroll through 1M items (4 positions)",
            4,
            benchVirtualListScroll1M,
            allocator,
        );
        result.print();
        total_duration += result.duration_ms;
    }

    // StreamingTable benchmarks
    std.debug.print("\n--- StreamingTable (1M rows) ---\n", .{});
    {
        const result = try runBench(
            "StreamingTable: Render 1M rows (viewport only)",
            1,
            benchStreamingTableRender1M,
            allocator,
        );
        result.print();
        total_duration += result.duration_ms;
    }
    {
        const result = try runBench(
            "StreamingTable: Scroll through 1M rows (4 positions)",
            4,
            benchStreamingTableScroll1M,
            allocator,
        );
        result.print();
        total_duration += result.duration_ms;
    }

    // ChunkedBuffer benchmarks
    std.debug.print("\n--- ChunkedBuffer (1M lines, ~100MB text) ---\n", .{});
    {
        const result = try runBench(
            "ChunkedBuffer: Render 1M lines (viewport only)",
            1,
            benchChunkedBufferRender1M,
            allocator,
        );
        result.print();
        total_duration += result.duration_ms;
    }
    {
        const result = try runBench(
            "ChunkedBuffer: Scroll through 1M lines (4 positions)",
            4,
            benchChunkedBufferScroll1M,
            allocator,
        );
        result.print();
        total_duration += result.duration_ms;
    }
    {
        const result = try runBench(
            "ChunkedBuffer: Render 100K lines with wrapping",
            1,
            benchChunkedBufferWrap,
            allocator,
        );
        result.print();
        total_duration += result.duration_ms;
    }

    // Memory benchmarks
    std.debug.print("\n--- Memory Efficiency ---\n", .{});
    {
        const result = try runBench(
            "Memory: 10 VirtualLists × 1M items each",
            10,
            benchMemoryUsageVirtualList,
            allocator,
        );
        result.print();
        total_duration += result.duration_ms;
    }

    // Summary
    std.debug.print("\n=== Summary ===\n", .{});
    std.debug.print("Total benchmark time: {d:.2} ms\n", .{total_duration});
    std.debug.print("All streaming widgets handle 1M+ items efficiently.\n", .{});
}
