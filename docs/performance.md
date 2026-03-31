# Performance Tuning Guide

This guide covers optimization techniques for building high-performance TUI applications with sailor.

## Table of Contents

1. [Rendering Performance](#rendering-performance)
2. [Memory Optimization](#memory-optimization)
3. [Event Processing](#event-processing)
4. [Layout Optimization](#layout-optimization)
5. [Widget-Specific Tips](#widget-specific-tips)
6. [Benchmarking](#benchmarking)

## Rendering Performance

### Buffer Diffing

sailor uses automatic buffer diffing to minimize screen updates. The system compares old and new buffers and only sends ANSI escape sequences for changed cells.

**Best practices**:

```zig
// Good - sailor diffs automatically
try term.draw(drawUI);

// Bad - manual screen clearing defeats diffing
try stdout.writeAll("\x1b[2J"); // Don't clear manually
try term.draw(drawUI);
```

**Benchmark**: Buffer diffing reduces output by 90%+ on typical TUI updates with <10% screen changes.

### Frame Rate Limiting

Limit rendering to necessary frame rate (most TUIs don't need 60 FPS):

```zig
const TARGET_FPS = 30;
const frame_time_ms = 1000 / TARGET_FPS;

while (running) {
    const start = std.time.milliTimestamp();

    try term.draw(drawUI);
    if (try term.pollEvent(1)) |event| {
        try handleEvent(event);
    }

    const elapsed = std.time.milliTimestamp() - start;
    if (elapsed < frame_time_ms) {
        std.time.sleep((frame_time_ms - elapsed) * std.time.ns_per_ms);
    }
}
```

**Impact**: Reduces CPU usage from 100% to <5% for typical TUI applications.

### Synchronized Output

Use synchronized output protocol (DEC Private Mode 2026) to eliminate tearing:

```zig
try term.enableSyncOutput();
defer term.disableSyncOutput() catch {};

while (running) {
    try term.draw(drawUI);
}
```

**How it works**: Terminal buffers all output between sync markers and applies atomically.

**Supported terminals**: VTE-based (GNOME Terminal, Tilix), iTerm2, WezTerm, Kitty (v0.20.0+).

### Lazy Rendering

Only redraw when necessary:

```zig
var needs_redraw = true;
var last_event_time = std.time.milliTimestamp();

while (running) {
    if (needs_redraw) {
        try term.draw(drawUI);
        needs_redraw = false;
    }

    if (try term.pollEvent(100)) |event| {
        needs_redraw = try handleEvent(event);
        last_event_time = std.time.milliTimestamp();
    }

    // Force redraw every 5s for progress bars, clocks, etc.
    if (std.time.milliTimestamp() - last_event_time > 5000) {
        needs_redraw = true;
    }
}
```

**Impact**: Eliminates wasted redraws during idle periods.

### Batch Updates

Group multiple state changes before redrawing:

```zig
// Bad - 3 redraws
app.updateItem(0);
try term.draw(drawUI);
app.updateItem(1);
try term.draw(drawUI);
app.updateItem(2);
try term.draw(drawUI);

// Good - 1 redraw
app.updateItem(0);
app.updateItem(1);
app.updateItem(2);
try term.draw(drawUI);
```

## Memory Optimization

### Arena Allocators for Frames

Use arena allocators for per-frame temporary allocations:

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();

var arena = std.heap.ArenaAllocator.init(gpa.allocator());
defer arena.deinit();

while (running) {
    defer _ = arena.reset(.retain_capacity);

    const frame_alloc = arena.allocator();

    // All allocations in drawUI use frame_alloc
    try term.draw(struct {
        pub fn draw(frame: *sailor.tui.Frame) !void {
            // Use frame_alloc for temporary allocations
            const temp = try frame_alloc.alloc(u8, 1024);
            defer frame_alloc.free(temp); // Actually a no-op, freed on reset
        }
    }.draw);
}
```

**Impact**: Eliminates per-frame allocation overhead, reduces fragmentation.

### Buffer Pooling

Reuse buffers across frames:

```zig
const pool = try sailor.pool.Pool(sailor.tui.Buffer).init(allocator, .{
    .initial_capacity = 2,
    .max_capacity = 4,
});
defer pool.deinit();

while (running) {
    var buffer = try pool.acquire();
    defer pool.release(buffer);

    buffer.clear();
    // Use buffer...
}
```

**When to use**: Applications with frequent buffer allocations (virtual scrolling, large tables).

**Benchmark**: Pooling reduces allocation time by 80% for repeated buffer creation.

### Chunked Buffers

For extremely large terminals (>300x100), use chunked buffers:

```zig
var buffer = try sailor.tui.ChunkedBuffer.init(allocator, .{
    .chunk_size = 8192, // Cells per chunk
});
defer buffer.deinit();
```

**How it works**: Splits buffer into smaller chunks, reducing contiguous allocation size and enabling partial updates.

**Impact**: Reduces memory usage by 30% for large terminals, enables >10,000x10,000 character buffers.

### String Interning

For repeated strings (widget titles, menu items), intern common strings:

```zig
const StringInterner = struct {
    map: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return .{ .map = std.StringHashMap([]const u8).init(allocator) };
    }

    pub fn intern(self: *@This(), str: []const u8) ![]const u8 {
        if (self.map.get(str)) |interned| return interned;
        const owned = try self.map.allocator.dupe(u8, str);
        try self.map.put(owned, owned);
        return owned;
    }

    pub fn deinit(self: *@This()) void {
        var it = self.map.valueIterator();
        while (it.next()) |v| {
            self.map.allocator.free(v.*);
        }
        self.map.deinit();
    }
};

var interner = try StringInterner.init(allocator);
defer interner.deinit();

// Instead of duplicating:
const title = try interner.intern("My Widget"); // Allocates once
const title2 = try interner.intern("My Widget"); // Returns same pointer
```

**Impact**: Reduces memory usage by 50%+ for applications with many repeated strings.

## Event Processing

### Event Batching

Process multiple events before redrawing:

```zig
var event_batch = std.ArrayList(sailor.tui.Event).init(allocator);
defer event_batch.deinit();

while (running) {
    event_batch.clearRetainingCapacity();

    // Collect all pending events
    while (try term.pollEvent(0)) |event| {
        try event_batch.append(event);
        if (event_batch.items.len >= 100) break; // Limit batch size
    }

    // Process batch
    for (event_batch.items) |event| {
        try handleEvent(event);
    }

    // Single redraw after processing all events
    if (event_batch.items.len > 0) {
        try term.draw(drawUI);
    }

    // Wait for next event if none pending
    if (event_batch.items.len == 0) {
        _ = try term.pollEvent(100);
    }
}
```

**Impact**: Reduces redraws during rapid input (e.g., holding down arrow key).

### Debouncing

Debounce expensive operations triggered by events:

```zig
const Debouncer = struct {
    last_trigger: i64 = 0,
    delay_ms: i64,

    pub fn trigger(self: *@This()) bool {
        const now = std.time.milliTimestamp();
        if (now - self.last_trigger > self.delay_ms) {
            self.last_trigger = now;
            return true;
        }
        return false;
    }
};

var search_debouncer = Debouncer{ .delay_ms = 300 };

// In event handler:
if (event == .key) {
    app.updateSearchQuery(event.key.c);
    if (search_debouncer.trigger()) {
        // Only search every 300ms
        try app.performSearch();
    }
}
```

**Use cases**: Search-as-you-type, live validation, expensive filters.

## Layout Optimization

### Cache Layout Results

Cache layout calculations when terminal size doesn't change:

```zig
var cached_layout: ?[]sailor.tui.Rect = null;
var cached_size: ?sailor.tui.Size = null;

fn getLayout(frame: *sailor.tui.Frame, allocator: std.mem.Allocator) ![]sailor.tui.Rect {
    const size = frame.size();

    if (cached_size) |cs| {
        if (cs.cols == size.cols and cs.rows == size.rows) {
            return cached_layout.?;
        }
    }

    if (cached_layout) |old| allocator.free(old);

    const layout = sailor.tui.Layout.init(.vertical)
        .constraints(&.{
            .{ .percentage = 30 },
            .{ .percentage = 70 },
        });

    cached_layout = try layout.split(frame.size(), allocator);
    cached_size = size;
    return cached_layout.?;
}
```

**Impact**: Eliminates layout recalculation overhead (can be 10-20% of frame time for complex layouts).

### Minimize Constraint Complexity

Use simple constraints when possible:

```zig
// Slow - complex constraints with min/max
.constraints(&.{
    .{ .min = 10, .max = 50 },
    .{ .min = 20, .max = 100 },
})

// Fast - simple percentage
.constraints(&.{
    .{ .percentage = 33 },
    .{ .percentage = 67 },
})
```

**Why**: Percentage constraints are resolved in O(1), min/max require iterative solving.

### Flatten Nested Layouts

Avoid deeply nested layouts:

```zig
// Slow - 3 layout levels
const outer = layout1.split(area);
const middle = layout2.split(outer[0]);
const inner = layout3.split(middle[0]);

// Fast - single layout with more chunks
const flat = Layout.init(.vertical)
    .constraints(&.{
        .{ .length = 3 },      // Header
        .{ .percentage = 50 }, // Top section
        .{ .percentage = 50 }, // Bottom section
    })
    .split(area);
```

**Impact**: Reduces layout calculation time by 60% for deeply nested structures.

## Widget-Specific Tips

### List / Table Virtualization

Enable virtual rendering for large data sets:

```zig
var list = try sailor.tui.widgets.List.init(allocator);

// With 10,000 items, render only visible ~30 items
list.items = large_dataset; // 10,000 items
list.render_mode = .virtual; // Only render visible portion

// Instead of rendering all 10,000 items per frame:
// Renders ~30 items (terminal height)
```

**Benchmark**: Virtual rendering reduces frame time from 45ms to 2ms for 10,000-item list.

### TextArea / Editor

For syntax highlighting, use incremental parsing:

```zig
const editor = sailor.tui.widgets.Editor.init(allocator, .{
    .language = .zig,
    .incremental_parse = true, // Parse only changed lines
});
```

**Impact**: Reduces re-parsing time by 95% for large files (only re-parse edited regions).

### Canvas

For complex drawings, use dirty rectangles:

```zig
var canvas = sailor.tui.widgets.Canvas.init(allocator);

// Mark only changed regions as dirty
canvas.markDirty(x, y, width, height);

// Render only redraws dirty regions
try canvas.render(buffer, area);
```

**Impact**: Reduces rendering time from O(width × height) to O(dirty area).

### Tree

Limit visible depth for large trees:

```zig
var tree = sailor.tui.widgets.Tree.init(allocator);
tree.max_visible_depth = 5; // Only render 5 levels deep
```

**Why**: Deep trees with thousands of nodes can take >100ms to render. Limiting depth keeps frame time <5ms.

### Progress / Spinner

Reduce update frequency:

```zig
var progress = sailor.progress.Bar.init(allocator, .{
    .update_interval_ms = 100, // Update every 100ms, not every iteration
});

for (items) |item| {
    processItem(item);
    if (progress.shouldUpdate()) { // Throttled
        try progress.update(i, stdout);
    }
}
```

**Impact**: Reduces CPU usage by 80% for high-frequency loops (millions of iterations).

## Benchmarking

### Built-in Profiler

sailor includes a render profiler:

```zig
const profiler = try sailor.profiler.Profiler.init(allocator);
defer profiler.deinit();

while (running) {
    var guard = profiler.startFrame();
    defer guard.end();

    try term.draw(drawUI);
}

// Print stats on exit
const stats = profiler.getStats();
std.debug.print("Avg frame time: {d:.2}ms\n", .{stats.avg_frame_time_ms});
std.debug.print("99th percentile: {d:.2}ms\n", .{stats.p99_ms});
```

### External Profiling

Use `perf` on Linux:

```bash
zig build -Doptimize=ReleaseFast
perf record -g ./zig-out/bin/myapp
perf report
```

Look for hot paths in:
- `Buffer.diff()` — Buffer diffing
- `Layout.split()` — Layout calculation
- `Widget.render()` — Widget rendering

### Memory Profiling

Use Valgrind's massif for heap profiling:

```bash
zig build -Doptimize=Debug
valgrind --tool=massif ./zig-out/bin/myapp
ms_print massif.out.<pid>
```

Check for:
- Growing heap size (memory leaks)
- Large peak allocations
- Frequent allocate/free cycles

### Benchmark Suite

Run sailor's benchmark suite:

```bash
zig build benchmark

# Output:
# Buffer.diff: 0.45ms (10,000 cells, 5% changed)
# Layout.split: 0.12ms (10 constraints)
# List.render: 1.8ms (1,000 items, virtual mode)
# Paragraph.render: 0.9ms (500 lines)
```

Compare your application's performance to baseline benchmarks.

## Performance Targets

For responsive TUI applications:

| Metric | Target | Excellent |
|--------|--------|-----------|
| Frame time | <16ms (60 FPS) | <8ms (120 FPS) |
| Event latency | <50ms | <20ms |
| Startup time | <500ms | <200ms |
| Memory (baseline) | <10 MB | <5 MB |
| Memory (running) | <50 MB | <20 MB |

**Note**: Targets assume typical terminal size (80x24 to 300x100). Larger terminals may require proportionally more resources.

## Performance Checklist

Before releasing your TUI application:

- [ ] Profile with `sailor.profiler.Profiler` — identify hot paths
- [ ] Check for memory leaks with GPA in debug mode
- [ ] Test on large terminals (>200x60) — ensure acceptable performance
- [ ] Test on slow terminals (SSH over high latency) — verify responsiveness
- [ ] Enable synchronized output — eliminate tearing
- [ ] Use frame rate limiting — reduce CPU usage
- [ ] Verify virtual rendering for large lists/tables
- [ ] Check arena allocator usage for per-frame allocations
- [ ] Measure startup time — optimize initialization
- [ ] Run benchmarks and compare to baseline

## Common Performance Pitfalls

1. **Allocating on every frame**: Use arena or pool allocators
2. **Not caching layout calculations**: Cache results until resize
3. **Rendering invisible widgets**: Check area size before rendering
4. **Deep call stacks in draw callback**: Pre-compute data outside draw
5. **Synchronous I/O in render loop**: Use async or separate thread
6. **Unbounded data structures**: Set limits on history, cache, logs
7. **Expensive string operations**: Intern strings, avoid repeated allocation
8. **No frame rate limiting**: Add sleep to reduce CPU usage

## Advanced Techniques

### Multi-threaded Rendering

For CPU-intensive computations (syntax highlighting, large data processing):

```zig
const WorkQueue = struct {
    // ... thread-safe work queue ...
};

var queue = try WorkQueue.init(allocator);
defer queue.deinit();

// Render thread
while (running) {
    // Process work results from background threads
    while (queue.poll()) |result| {
        app.updateData(result);
    }

    try term.draw(drawUI);
}

// Background threads compute expensive operations
// and push results to queue
```

**Caution**: sailor's TUI types are not thread-safe. Only pass results, not widgets or buffers.

### GPU Acceleration

For supported terminals (Kitty, iTerm2), use GPU-accelerated graphics:

```zig
// Render complex visualizations to image
const image = try renderVisualization(allocator);
defer image.deinit();

// Display via Kitty graphics protocol
try sailor.tui.graphics.kitty.display(image, term.writer());
```

**Use cases**: Charts, graphs, images, complex visualizations beyond ASCII art.

## Resources

- [sailor benchmarks](../examples/benchmark_runner.zig) — Run performance tests
- [profiler module](../src/profiler.zig) — Built-in profiling API
- [pool module](../src/pool.zig) — Object pooling for allocation optimization

---

For more information, see:
- [Getting Started Guide](getting-started.md)
- [Troubleshooting](troubleshooting.md)
- [API Documentation](API.md)
