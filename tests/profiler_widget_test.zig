//! PerformanceProfiler Widget Tests — TDD Red Phase
//!
//! Tests PerformanceProfiler widget with frame timing history, memory statistics,
//! hot path profiling, different display modes, render edge cases, and regression
//! tests for unclamped @intFromFloat casts that can panic.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const PerformanceProfiler = sailor.tui.widgets.PerformanceProfiler;
const FrameStats = sailor.tui.widgets.FrameStats;
const AllocStats = sailor.tui.widgets.AllocStats;
const HotPath = sailor.tui.widgets.HotPath;
const ProfilerMode = sailor.tui.widgets.ProfilerMode;

// ============================================================================
// Helper Functions
// ============================================================================

/// Count non-empty cells (non-space characters) in a buffer area
fn countNonEmptyCells(buf: Buffer, area: Rect) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ' and cell.char != 0) {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Check if buffer area contains a specific character
fn areaHasChar(buf: Buffer, area: Rect, ch: u21) bool {
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == ch) {
                    return true;
                }
            }
        }
    }
    return false;
}

// ============================================================================
// Group 1: Initialization and Defaults
// ============================================================================

test "PerformanceProfiler init creates empty history with correct defaults" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    try testing.expectEqual(ProfilerMode.all, profiler.mode);
    try testing.expectEqual(@as(usize, 100), profiler.max_history);
    try testing.expectEqual(60.0, profiler.target_fps);
    try testing.expectEqual(@as(usize, 0), profiler.frame_history.items.len);
    try testing.expectEqual(@as(usize, 0), profiler.hot_paths.items.len);
    try testing.expect(profiler.show_sparkline);
}

test "PerformanceProfiler init allocates with correct allocator" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    // Should be able to record frames after init
    const frame = FrameStats{ .frame_time_ms = 16.7, .render_time_ms = 12.0, .event_time_ms = 2.0, .timestamp = 0 };
    try profiler.recordFrame(frame);
    try testing.expectEqual(@as(usize, 1), profiler.frame_history.items.len);
}

// ============================================================================
// Group 2: Recording and History Management
// ============================================================================

test "PerformanceProfiler recordFrame appends to history" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    const frame = FrameStats{ .frame_time_ms = 16.7, .render_time_ms = 12.5, .event_time_ms = 2.1, .timestamp = 1234567890 };
    try profiler.recordFrame(frame);

    try testing.expectEqual(@as(usize, 1), profiler.frame_history.items.len);
    try testing.expectEqual(16.7, profiler.frame_history.items[0].frame_time_ms);
    try testing.expectEqual(12.5, profiler.frame_history.items[0].render_time_ms);
}

test "PerformanceProfiler recordFrame trims history when exceeding max_history" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    profiler.max_history = 3;

    // Record 5 frames
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const frame = FrameStats{
            .frame_time_ms = @floatFromInt(i),
            .render_time_ms = 0,
            .event_time_ms = 0,
            .timestamp = @intCast(i),
        };
        try profiler.recordFrame(frame);
    }

    // Should only keep last 3
    try testing.expectEqual(@as(usize, 3), profiler.frame_history.items.len);
    try testing.expectEqual(2.0, profiler.frame_history.items[0].frame_time_ms);
    try testing.expectEqual(3.0, profiler.frame_history.items[1].frame_time_ms);
    try testing.expectEqual(4.0, profiler.frame_history.items[2].frame_time_ms);
}

// ============================================================================
// Group 3: Mode and Configuration
// ============================================================================

test "PerformanceProfiler setMode changes mode correctly" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    profiler.setMode(.frame_times);
    try testing.expectEqual(ProfilerMode.frame_times, profiler.mode);

    profiler.setMode(.memory);
    try testing.expectEqual(ProfilerMode.memory, profiler.mode);

    profiler.setMode(.hot_paths);
    try testing.expectEqual(ProfilerMode.hot_paths, profiler.mode);

    profiler.setMode(.all);
    try testing.expectEqual(ProfilerMode.all, profiler.mode);
}

test "PerformanceProfiler supports custom max_history" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    profiler.max_history = 10;
    try testing.expectEqual(@as(usize, 10), profiler.max_history);

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const frame = FrameStats{ .frame_time_ms = 16.0, .render_time_ms = 0, .event_time_ms = 0, .timestamp = 0 };
        try profiler.recordFrame(frame);
    }

    try testing.expectEqual(@as(usize, 10), profiler.frame_history.items.len);
}

test "PerformanceProfiler supports custom target_fps" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    profiler.target_fps = 30.0;
    try testing.expectEqual(30.0, profiler.target_fps);

    profiler.target_fps = 120.0;
    try testing.expectEqual(120.0, profiler.target_fps);
}

test "PerformanceProfiler show_sparkline toggle" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    try testing.expect(profiler.show_sparkline);

    profiler.show_sparkline = false;
    try testing.expect(!profiler.show_sparkline);

    profiler.show_sparkline = true;
    try testing.expect(profiler.show_sparkline);
}

// ============================================================================
// Group 4: Memory Statistics
// ============================================================================

test "PerformanceProfiler updateMemory stores allocation stats" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    const stats = AllocStats{
        .total_allocated = 1024 * 1024,
        .total_freed = 512 * 1024,
        .current_usage = 512 * 1024,
        .peak_usage = 768 * 1024,
        .alloc_count = 100,
        .free_count = 50,
    };

    profiler.updateMemory(stats);

    try testing.expectEqual(@as(usize, 1024 * 1024), profiler.alloc_stats.total_allocated);
    try testing.expectEqual(@as(usize, 512 * 1024), profiler.alloc_stats.total_freed);
    try testing.expectEqual(@as(usize, 512 * 1024), profiler.alloc_stats.current_usage);
    try testing.expectEqual(@as(usize, 768 * 1024), profiler.alloc_stats.peak_usage);
}

// ============================================================================
// Group 5: Hot Path Tracking
// ============================================================================

test "PerformanceProfiler recordHotPath adds new path" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    const path = HotPath{
        .name = "render_widgets",
        .call_count = 100,
        .total_time_ms = 250.0,
        .avg_time_ms = 2.5,
    };

    try profiler.recordHotPath(path);
    try testing.expectEqual(@as(usize, 1), profiler.hot_paths.items.len);
    try testing.expectEqualStrings("render_widgets", profiler.hot_paths.items[0].name);
}

test "PerformanceProfiler recordHotPath updates existing path" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    const path1 = HotPath{
        .name = "render",
        .call_count = 100,
        .total_time_ms = 250.0,
        .avg_time_ms = 2.5,
    };
    try profiler.recordHotPath(path1);

    const path2 = HotPath{
        .name = "render",
        .call_count = 200,
        .total_time_ms = 500.0,
        .avg_time_ms = 2.5,
    };
    try profiler.recordHotPath(path2);

    try testing.expectEqual(@as(usize, 1), profiler.hot_paths.items.len);
    try testing.expectEqual(@as(usize, 200), profiler.hot_paths.items[0].call_count);
}

test "PerformanceProfiler clearHotPaths removes all paths" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    const path = HotPath{
        .name = "test",
        .call_count = 10,
        .total_time_ms = 100.0,
        .avg_time_ms = 10.0,
    };

    try profiler.recordHotPath(path);
    try testing.expectEqual(@as(usize, 1), profiler.hot_paths.items.len);

    profiler.clearHotPaths();
    try testing.expectEqual(@as(usize, 0), profiler.hot_paths.items.len);
}

// ============================================================================
// Group 6: FPS and Timing Statistics
// ============================================================================

test "PerformanceProfiler getAverageFPS returns 0 for empty history" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    try testing.expectEqual(0.0, profiler.getAverageFPS());
}

test "PerformanceProfiler getAverageFPS calculates correctly" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    // Add frames at ~60 FPS (16.67ms per frame)
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const frame = FrameStats{
            .frame_time_ms = 16.67,
            .render_time_ms = 0,
            .event_time_ms = 0,
            .timestamp = 0,
        };
        try profiler.recordFrame(frame);
    }

    const fps = profiler.getAverageFPS();
    try testing.expect(fps > 59.0 and fps < 61.0); // ~60 FPS
}

test "PerformanceProfiler getMinFrameTime returns min of history" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    const times = [_]f64{ 16.0, 20.0, 12.0, 18.0, 25.0 };
    for (times) |time| {
        const frame = FrameStats{
            .frame_time_ms = time,
            .render_time_ms = 0,
            .event_time_ms = 0,
            .timestamp = 0,
        };
        try profiler.recordFrame(frame);
    }

    try testing.expectEqual(12.0, profiler.getMinFrameTime());
}

test "PerformanceProfiler getMaxFrameTime returns max of history" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    const times = [_]f64{ 16.0, 20.0, 12.0, 18.0, 25.0 };
    for (times) |time| {
        const frame = FrameStats{
            .frame_time_ms = time,
            .render_time_ms = 0,
            .event_time_ms = 0,
            .timestamp = 0,
        };
        try profiler.recordFrame(frame);
    }

    try testing.expectEqual(25.0, profiler.getMaxFrameTime());
}

// ============================================================================
// Group 7: Rendering Edge Cases
// ============================================================================

test "PerformanceProfiler render handles zero-size area without crashing" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Zero width
    try profiler.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 10 });

    // Zero height
    try profiler.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 0 });

    // Both zero
    try profiler.render(&buf, Rect{ .x = 0, .y = 0, .width = 0, .height = 0 });
}

test "PerformanceProfiler render frame_times mode with no data" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    profiler.setMode(.frame_times);

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    try profiler.render(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // Should render border
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).?.char);
}

test "PerformanceProfiler render memory mode with stats" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    const stats = AllocStats{
        .total_allocated = 1024,
        .total_freed = 512,
        .current_usage = 512,
        .peak_usage = 768,
        .alloc_count = 10,
        .free_count = 5,
    };
    profiler.updateMemory(stats);
    profiler.setMode(.memory);

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    try profiler.render(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // Should render border
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).?.char);
}

test "PerformanceProfiler render hot_paths mode with paths" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    const path = HotPath{
        .name = "test_path",
        .call_count = 100,
        .total_time_ms = 50.0,
        .avg_time_ms = 0.5,
    };
    try profiler.recordHotPath(path);

    profiler.setMode(.hot_paths);

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    try profiler.render(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // Should render border
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).?.char);
}

test "PerformanceProfiler render all mode shows three sections" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    profiler.setMode(.all);

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    try profiler.render(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // Top section (frame times) should have border
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, 0).?.char);

    // Middle section should have border at height/3
    const mid_y = 24 / 3;
    try testing.expectEqual(@as(u21, '┌'), buf.get(0, mid_y).?.char);
}

test "PerformanceProfiler render minimal area without panic" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    // Add a frame
    const frame = FrameStats{ .frame_time_ms = 16.0, .render_time_ms = 0, .event_time_ms = 0, .timestamp = 0 };
    try profiler.recordFrame(frame);

    profiler.setMode(.frame_times);

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Render in minimal area
    try profiler.render(&buf, Rect{ .x = 0, .y = 0, .width = 10, .height = 5 });

    // Should not crash
}

// ============================================================================
// Group 8: REGRESSION TESTS — Unclamped @intFromFloat Casts (RED Phase)
// ============================================================================

test "PerformanceProfiler.renderFrameTimes extremely large frame_time_ms with show_sparkline=true does not panic" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    profiler.setMode(.frame_times);
    profiler.show_sparkline = true;

    // CRITICAL REGRESSION: renderFrameTimes() at line 225 casts frame.frame_time_ms * 100.0 to u64 without clamping.
    // Values that result in products > u64::MAX (~1.8e19) cause panic: "integer part of floating point value out of bounds"
    // This test locks in the fix: extremely large frame times must be clamped before cast.
    const frame = FrameStats{
        .frame_time_ms = 1e18,  // 1e18 * 100 = 1e20 > u64::MAX
        .render_time_ms = 1.0,
        .event_time_ms = 1.0,
        .timestamp = 0,
    };
    try profiler.recordFrame(frame);

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Render with sufficient height to trigger sparkline (inner.height > 2)
    // Block has 1px borders, so inner.height = 24 - 2 = 22 > 2
    try profiler.render(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // No panic is success; render must complete without overflow
}

test "PerformanceProfiler.renderFrameTimes near-zero target_fps with show_sparkline=true does not panic" {
    var profiler = PerformanceProfiler.init(testing.allocator);
    defer profiler.deinit();

    profiler.setMode(.frame_times);
    profiler.show_sparkline = true;

    // CRITICAL REGRESSION: renderFrameTimes() at line 230 calculates target_ms = 1000.0 / target_fps,
    // then casts target_ms * 2.0 * 100.0 to u64 without clamping.
    // Extremely small target_fps values make target_ms huge, causing overflow when multiplied.
    // This test locks in the fix: target_fps must be clamped or the sparkline.max calculation must be guarded.
    profiler.target_fps = 1e-20;  // target_ms = 1000 / 1e-20 = 1e23, then * 2 * 100 = 2e25 > u64::MAX

    // Add a normal frame to trigger the calculation
    const frame = FrameStats{
        .frame_time_ms = 16.0,
        .render_time_ms = 1.0,
        .event_time_ms = 1.0,
        .timestamp = 0,
    };
    try profiler.recordFrame(frame);

    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    // Render with sufficient height to trigger sparkline
    try profiler.render(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // No panic is success; render must complete without overflow
}
