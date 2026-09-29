//! Profiling demonstration showing all profiler features

const std = @import("std");
const sailor = @import("sailor");
const profiler_mod = sailor.profiler;
const Profiler = profiler_mod.Profiler;
const MemoryTracker = profiler_mod.MemoryTracker;
const EventLoopProfiler = profiler_mod.EventLoopProfiler;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    std.debug.print("\n=== sailor Profiling Demo ===\n\n", .{});

    try demoRenderProfiler(allocator, io);
    try demoMemoryTracker(allocator, io);
    try demoEventLoopProfiler(allocator, io);
    try demoWidgetMetrics(allocator, io);

    std.debug.print("\n=== Demo Complete ===\n", .{});
}

fn demoRenderProfiler(allocator: std.mem.Allocator, io: std.Io) !void {
    std.debug.print("1. Render Profiler with Flame Graphs\n", .{});
    std.debug.print("   ===================================\n\n", .{});

    var prof = try Profiler.init(allocator, io, 16.0);
    defer prof.deinit();

    try prof.beginScope("Frame");
    try io.sleep(.fromNanoseconds(500_000), .awake);
    try prof.beginScope("Layout");
    try io.sleep(.fromNanoseconds(300_000), .awake);
    try prof.endScope();
    try prof.beginScope("Render");
    try io.sleep(.fromNanoseconds(200_000), .awake);
    try prof.endScope();
    try prof.endScope();

    const flame_data = try prof.flameGraphData(allocator);
    defer {
        for (flame_data) |*frame| {
            var mutable_frame = frame.*;
            mutable_frame.deinitRecursive(allocator);
        }
        allocator.free(flame_data);
    }

    std.debug.print("   Flame Graph Root Scopes: {}\n", .{flame_data.len});
    std.debug.print("   Frame Total Time: {d:.2}ms\n\n", .{
        @as(f64, @floatFromInt(flame_data[0].total_time_ns)) / 1_000_000.0,
    });
}

fn demoMemoryTracker(allocator: std.mem.Allocator, io: std.Io) !void {
    std.debug.print("2. Memory Allocation Tracker\n", .{});
    std.debug.print("   ==========================\n\n", .{});

    var tracker = try MemoryTracker.init(allocator, io);
    defer tracker.deinit();

    try tracker.recordAlloc("Button", 1024);
    try tracker.recordAlloc("Table", 8192);
    try tracker.recordAlloc("Canvas", 16384);

    const hot_spots = try tracker.getHotSpots(allocator, 3);
    defer allocator.free(hot_spots);

    std.debug.print("   Top Allocation Hot Spots:\n", .{});
    for (hot_spots, 0..) |stats, i| {
        std.debug.print("   {}. {s} - {} bytes\n", .{ i + 1, stats.location, stats.total_allocated });
    }
    std.debug.print("\n", .{});
}

fn demoEventLoopProfiler(allocator: std.mem.Allocator, io: std.Io) !void {
    std.debug.print("3. Event Loop Profiler\n", .{});
    std.debug.print("   ====================\n\n", .{});

    var prof = try EventLoopProfiler.init(allocator, io, 10.0);
    defer prof.deinit();

    // Use guard for proper profiling
    {
        var guard = prof.startEvent("key", 0);
        try io.sleep(.fromNanoseconds(2_000_000), .awake);
        try guard.end();
    }
    {
        var guard = prof.startEvent("mouse", 0);
        try io.sleep(.fromNanoseconds(15_000_000), .awake);
        try guard.end();
    }

    const stats = try prof.getStats("key");
    std.debug.print("   Key Events: avg={d:.2}ms\n", .{stats.avgLatencyMs()});

    const slow = try prof.detectSlowEvents(allocator);
    defer allocator.free(slow);
    std.debug.print("   Slow Events (>10ms): {}\n\n", .{slow.len});
}

fn demoWidgetMetrics(allocator: std.mem.Allocator, io: std.Io) !void {
    std.debug.print("4. Widget Performance Metrics\n", .{});
    std.debug.print("   ===========================\n\n", .{});

    var prof = try Profiler.init(allocator, io, 16.0);
    defer prof.deinit();

    try prof.recordWithCache("Button", 1_000_000, true);
    try prof.recordWithCache("Button", 5_000_000, false);
    try prof.recordWithCache("Table", 3_000_000, true);

    const metrics = try prof.getWidgetMetrics("Button");
    std.debug.print("   Button: {} renders, {d:.1}% cache hit\n", .{
        metrics.render_count,
        metrics.cacheHitRate() * 100.0,
    });
    std.debug.print("   Total Render Time: {d:.2}ms\n\n", .{
        @as(f64, @floatFromInt(prof.totalRenderTime())) / 1_000_000.0,
    });
}
