# sailor Performance Optimization Guide

> **v1.31.0** — Profiling tools, memory tracking, and optimization best practices

This guide helps you identify and fix performance bottlenecks in your sailor TUI applications.

---

## Table of Contents

1. [Profiling Tools Overview](#profiling-tools-overview)
2. [Render Performance](#render-performance)
3. [Memory Optimization](#memory-optimization)
4. [Event Loop Optimization](#event-loop-optimization)
5. [Common Bottlenecks](#common-bottlenecks)
6. [Best Practices](#best-practices)

---

## Profiling Tools Overview

sailor v1.31.0 provides built-in profiling tools:

### 1. Render Profiler

Tracks widget render times, flame graphs, and performance metrics.

```zig
const sailor = @import("sailor");
const Profiler = sailor.profiler.Profiler;

var profiler = try Profiler.init(allocator, 16.0); // 16ms threshold (60 FPS)
defer profiler.deinit();

// Profile a render operation
var guard = try profiler.start("MyWidget");
myWidget.render(&buffer, area);
try guard.end();

// Detect bottlenecks
const bottlenecks = try profiler.detectBottlenecks(allocator);
defer allocator.free(bottlenecks);
for (bottlenecks) |widget| {
    std.debug.print("Slow widget: {s} ({d:.2}ms)\n", .{
        widget.widget_name,
        widget.durationMs(),
    });
}
```

### 2. Memory Tracker

Identifies allocation hot spots and potential memory leaks.

```zig
const MemoryTracker = sailor.profiler.MemoryTracker;

var tracker = try MemoryTracker.init(allocator);
defer tracker.deinit();

// Track allocations
try tracker.recordAlloc("TableWidget", buffer.len);
// ... later ...
try tracker.recordFree("TableWidget", buffer.len);

// Find hot spots
const hot_spots = try tracker.getHotSpots(allocator, 5);
defer allocator.free(hot_spots);

// Detect leaks
const leaks = try tracker.detectLeaks(allocator);
defer allocator.free(leaks);
```

### 3. Event Loop Profiler

Measures event processing latency and identifies slow handlers.

```zig
const EventLoopProfiler = sailor.profiler.EventLoopProfiler;

var prof = try EventLoopProfiler.init(allocator, 10.0); // 10ms threshold
defer prof.deinit();

// Profile event processing
var guard = prof.startEvent("KeyPress", event_queue.len);
handleKeyPress(event);
try guard.end();

// Get latency stats
const stats = try prof.getStats("KeyPress");
std.debug.print("Key press p95 latency: {d:.2}ms\n", .{stats.p95LatencyMs()});
```

---

## Render Performance

### Target: 60 FPS (16ms per frame)

Achieving smooth rendering requires keeping total frame time under 16ms.

### 1. Use Flame Graphs for Hierarchy Analysis

```zig
// Nested profiling with flame graphs
try profiler.beginScope("Frame");
try profiler.beginScope("Layout");
layout.solve();
try profiler.endScope();

try profiler.beginScope("Render");
try profiler.beginScope("Table");
table.render(&buffer, area);
try profiler.endScope();
try profiler.endScope();
try profiler.endScope();

// Export flame graph
const flame_data = try profiler.flameGraphData(allocator);
defer {
    for (flame_data) |*frame| {
        var mutable = frame.*;
        mutable.deinitRecursive(allocator);
    }
    allocator.free(flame_data);
}

// Analyze self vs. total time
for (flame_data) |frame| {
    const self_pct = @as(f64, @floatFromInt(frame.self_time_ns)) /
                     @as(f64, @floatFromInt(frame.total_time_ns)) * 100.0;
    std.debug.print("{s}: {d:.1}% self time\n", .{frame.name, self_pct});
}
```

### 2. Cache Rendered Content

Track cache hit rates to verify caching effectiveness:

```zig
// Record with cache information
try profiler.recordWithCache("Button", duration_ns, is_cache_hit);

// Check cache hit rate
const metrics = try profiler.getWidgetMetrics("Button");
if (metrics.cacheHitRate() < 0.8) {
    // Cache hit rate below 80% — investigate cache invalidation
    std.debug.print("WARNING: Low cache hit rate: {d:.1}%\n", .{
        metrics.cacheHitRate() * 100.0,
    });
}
```

**Best Practices:**
- Cache widget state and only re-render on state change
- Use `sailor.Buffer.diff()` to minimize terminal writes
- Avoid full-screen redraws — update only changed regions

### 3. Optimize Layout Solver

Layout calculations can be expensive for complex UIs:

```zig
// BAD: Recalculate layout every frame
fn render(self: *Self) void {
    const layout = Layout.solve(self.constraints, self.area); // Expensive!
    // ...
}

// GOOD: Cache layout and invalidate only when needed
fn render(self: *Self) void {
    if (self.layout_dirty) {
        self.cached_layout = Layout.solve(self.constraints, self.area);
        self.layout_dirty = false;
    }
    // Use self.cached_layout
}
```

---

## Memory Optimization

### 1. Identify Allocation Hot Spots

```zig
const hot_spots = try tracker.getHotSpots(allocator, 10);
defer allocator.free(hot_spots);

for (hot_spots) |stats| {
    std.debug.print("{s}: {} bytes allocated, {} allocs, avg {d:.1} KB/alloc\n", .{
        stats.location,
        stats.total_allocated,
        stats.alloc_count,
        @as(f64, @floatFromInt(stats.avg_alloc_size)) / 1024.0,
    });
}
```

### 2. Use Arena Allocators for Short-Lived Data

```zig
// BAD: Many individual allocations per frame
fn render(allocator: Allocator) !void {
    const buffer1 = try allocator.alloc(u8, 100); // Allocation 1
    defer allocator.free(buffer1);
    const buffer2 = try allocator.alloc(u8, 200); // Allocation 2
    defer allocator.free(buffer2);
    // ... many more allocations
}

// GOOD: Use arena for frame-scoped allocations
fn render(parent_allocator: Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    defer arena.deinit(); // Free all at once
    const allocator = arena.allocator();

    const buffer1 = try allocator.alloc(u8, 100); // Fast!
    const buffer2 = try allocator.alloc(u8, 200); // Fast!
    // No individual frees needed
}
```

### 3. Reduce Allocations with Fixed Buffers

```zig
// BAD: Allocate every time
fn formatText(allocator: Allocator, value: i32) ![]u8 {
    return try std.fmt.allocPrint(allocator, "Value: {}", .{value});
}

// GOOD: Use stack buffer when size is known
fn formatText(buf: []u8, value: i32) ![]const u8 {
    return std.fmt.bufPrint(buf, "Value: {}", .{value});
}

// Usage:
var buf: [128]u8 = undefined;
const text = try formatText(&buf, 42);
```

### 4. Track Peak Memory

```zig
std.debug.print("Peak allocated: {} bytes\n", .{tracker.totalPeakAllocated()});

// Set budget and warn if exceeded
const BUDGET_MB: usize = 50;
const peak_mb = tracker.totalPeakAllocated() / (1024 * 1024);
if (peak_mb > BUDGET_MB) {
    std.debug.print("WARNING: Peak memory ({} MB) exceeds budget ({} MB)\n", .{
        peak_mb,
        BUDGET_MB,
    });
}
```

---

## Event Loop Optimization

### Target: <10ms event processing latency

### 1. Monitor Event Processing Latency

```zig
const stats = try profiler.getStats("KeyPress");
std.debug.print("Event latency — avg: {d:.2}ms, p95: {d:.2}ms, p99: {d:.2}ms\n", .{
    stats.avgLatencyMs(),
    stats.p95LatencyMs(),
    stats.p99LatencyMs(),
});

// Alert on high p99 latency
if (stats.p99_latency_ns > 50_000_000) { // 50ms
    std.debug.print("WARNING: High p99 latency detected!\n", .{});
}
```

### 2. Detect Slow Event Handlers

```zig
const slow_events = try profiler.detectSlowEvents(allocator);
defer allocator.free(slow_events);

for (slow_events) |event| {
    std.debug.print("Slow event: {s} took {d:.2}ms (queue depth: {})\n", .{
        event.event_type,
        event.processingTimeMs(),
        event.queue_depth,
    });
}
```

### 3. Optimize Event Handlers

```zig
// BAD: Expensive computation in event handler
fn onKeyPress(key: Key) void {
    computeExpensiveResult(); // Blocks event loop!
    updateUI();
}

// GOOD: Defer expensive work
fn onKeyPress(key: Key) void {
    self.pending_work = .compute;
    updateUI(); // Fast!
}

fn tick() void {
    if (self.pending_work) |work| {
        switch (work) {
            .compute => {
                computeExpensiveResult();
                self.pending_work = null;
            },
        }
    }
}
```

### 4. Monitor Queue Depth

```zig
// High queue depth indicates event processing can't keep up
const stats = try profiler.getStats("MouseMove");
if (stats.avg_queue_depth > 5.0) {
    std.debug.print("WARNING: Event queue backing up (avg depth: {d:.1})\n", .{
        stats.avg_queue_depth,
    });
    // Consider: throttling, debouncing, or optimizing handlers
}
```

---

## Common Bottlenecks

### 1. Excessive String Allocations

**Symptom:** High memory churn in memory tracker

**Solution:**
- Use `std.fmt.bufPrint` instead of `allocPrint`
- Cache formatted strings
- Use `std.BoundedArray` for small strings

```zig
// BAD
const text = try std.fmt.allocPrint(allocator, "Count: {}", .{count});
defer allocator.free(text);

// GOOD
var buf: [64]u8 = undefined;
const text = try std.fmt.bufPrint(&buf, "Count: {}", .{count});
```

### 2. Full-Screen Redraws

**Symptom:** High render times even when content doesn't change

**Solution:**
- Use `Buffer.diff()` to detect changes
- Mark regions as dirty
- Only render changed widgets

### 3. Synchronous I/O in Event Loop

**Symptom:** High p99 latency spikes

**Solution:**
- Move I/O to background thread
- Use async I/O
- Cache I/O results

### 4. Large Table Rendering

**Symptom:** Render time scales with row count

**Solution:**
- Implement virtual scrolling (render only visible rows)
- Use pagination
- Cache row renders

```zig
// Virtual scrolling example
const visible_start = scroll_offset;
const visible_end = @min(scroll_offset + visible_rows, total_rows);
for (visible_start..visible_end) |i| {
    renderRow(i);
}
```

---

## Best Practices

### 1. Profile Before Optimizing

Don't guess — measure:

```zig
// Always profile first
var profiler = try Profiler.init(allocator, 16.0);
defer profiler.deinit();

// Run your app with profiling
while (running) {
    var guard = try profiler.start("Frame");
    renderFrame();
    try guard.end();
}

// Find the slowest widget
if (profiler.slowestWidget()) |widget| {
    std.debug.print("Optimize this first: {s}\n", .{widget.widget_name});
}
```

### 2. Set Performance Budgets

```zig
const FRAME_BUDGET_MS: f64 = 16.0; // 60 FPS
const MEMORY_BUDGET_MB: usize = 100;
const EVENT_BUDGET_MS: f64 = 10.0;

// Enforce budgets in CI
if (profiler.totalRenderTime() > FRAME_BUDGET_MS * 1_000_000) {
    return error.FrameBudgetExceeded;
}
```

### 3. Automate Performance Testing

```zig
// Benchmark mode
const benchmark_frames = 1000;
var total_time: u64 = 0;

for (0..benchmark_frames) |_| {
    var guard = try profiler.start("Frame");
    renderFrame();
    try guard.end();
    total_time += profiler.frameProfiles()[0].duration_ns;
}

const avg_ms = @as(f64, @floatFromInt(total_time / benchmark_frames)) / 1_000_000.0;
std.debug.print("Average frame time: {d:.2}ms\n", .{avg_ms});
```

### 4. Monitor in Production

Enable profiling conditionally:

```zig
const ENABLE_PROFILING = std.process.hasEnvVarConstant("SAILOR_PROFILE");

var profiler: ?Profiler = if (ENABLE_PROFILING)
    try Profiler.init(allocator, 16.0)
else
    null;
defer if (profiler) |*p| p.deinit();

// Use profiler only when enabled
if (profiler) |*p| {
    var guard = try p.start("Widget");
    renderWidget();
    try guard.end();
} else {
    renderWidget();
}
```

### 5. Iterative Optimization

1. **Profile** — Identify slowest widget/event
2. **Optimize** — Fix the bottleneck
3. **Verify** — Confirm improvement with profiling
4. **Repeat** — Move to next bottleneck

**Example workflow:**

```bash
# 1. Run with profiling
SAILOR_PROFILE=1 ./my_app

# 2. Check profiler output:
# "TableWidget: 45ms (SLOW!)"

# 3. Optimize TableWidget (add caching, virtual scrolling)

# 4. Verify improvement:
# "TableWidget: 3ms (OK)"

# 5. Move to next bottleneck
```

---

## See Also

- [Profile Demo Example](../examples/profile_demo.zig) — Hands-on profiling examples
- [Benchmark Suite](../examples/benchmark.zig) — Widget performance benchmarks
- [Memory Profiling](./memory-profiling.md) — Advanced memory optimization techniques

---

**sailor v1.31.0** — Built-in profiling for high-performance TUIs

