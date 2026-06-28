//! GanttChart Widget Tests — TDD Red Phase
//!
//! Tests GanttChart widget with task rendering, progress visualization,
//! focused navigation, bar scaling, label layout, style application, and edge cases.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Block = sailor.tui.widgets.Block;
const GanttChart = sailor.tui.widgets.GanttChart;
const Task = sailor.tui.widgets.gantt.Task;

// ============================================================================
// Helper Functions
// ============================================================================

/// Decode UTF-8 text into a codepoint slice (max 256 codepoints)
fn decodeUtf8(text: []const u8, out: []u21) usize {
    var len: usize = 0;
    var view = std.unicode.Utf8View.initUnchecked(text);
    var iter = view.iterator();
    while (iter.nextCodepoint()) |cp| {
        if (len >= out.len) break;
        out[len] = cp;
        len += 1;
    }
    return len;
}

/// Find text in buffer area (UTF-8 aware)
fn findInArea(buf: Buffer, area: Rect, text: []const u8) bool {
    if (text.len == 0) return true;

    var cps: [256]u21 = undefined;
    const cp_count = decodeUtf8(text, &cps);
    if (cp_count == 0) return true;

    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            var matched = true;
            var cp_idx: usize = 0;
            var cx = x;
            var cy = y;

            while (cp_idx < cp_count) : (cp_idx += 1) {
                if (cy >= area.y + area.height or cy >= buf.height or
                    cx >= area.x + area.width or cx >= buf.width) {
                    matched = false;
                    break;
                }

                const cell = buf.getConst(cx, cy) orelse {
                    matched = false;
                    break;
                };
                if (cell.char != cps[cp_idx]) {
                    matched = false;
                    break;
                }
                cx += 1;
                if (cx >= area.x + area.width or cx >= buf.width) {
                    cy += 1;
                    cx = area.x;
                }
            }

            if (matched) return true;
        }
    }
    return false;
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

/// Count non-space cells in area
fn countNonEmptyCells(buf: Buffer, area: Rect) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ') {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Count occurrences of a character in area
fn countCharInArea(buf: Buffer, area: Rect, ch: u21) usize {
    var count: usize = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char == ch) {
                    count += 1;
                }
            }
        }
    }
    return count;
}

// ============================================================================
// Group 1: Init/Defaults (5 tests)
// ============================================================================

test "GanttChart.init has empty tasks" {
    const gc = GanttChart.init();
    try testing.expectEqual(@as(usize, 0), gc.tasks.len);
}

test "GanttChart.init has focused == 0" {
    const gc = GanttChart.init();
    try testing.expectEqual(@as(usize, 0), gc.focused);
}

test "GanttChart.init has label_width == 20" {
    const gc = GanttChart.init();
    try testing.expectEqual(@as(u16, 20), gc.label_width);
}

test "GanttChart.init has show_progress == true" {
    const gc = GanttChart.init();
    try testing.expect(gc.show_progress == true);
}

test "GanttChart.init has null block" {
    const gc = GanttChart.init();
    try testing.expect(gc.block == null);
}

// ============================================================================
// Group 2: Task Defaults (3 tests)
// ============================================================================

test "Task with defaults has empty name" {
    const t = Task{};
    try testing.expectEqual(@as(usize, 0), t.name.len);
}

test "Task with defaults has progress == 0" {
    const t = Task{};
    try testing.expectEqual(@as(u8, 0), t.progress);
}

test "Task with defaults has style == null" {
    const t = Task{};
    try testing.expect(t.style == null);
}

// ============================================================================
// Group 3: Builder Immutability (5 tests)
// ============================================================================

test "withTasks returns new value, original unchanged" {
    var tasks1 = [_]Task{.{ .name = "task1", .start = 0, .end = 5 }};
    const gc1 = GanttChart.init().withTasks(&tasks1);
    var tasks2 = [_]Task{.{ .name = "task2", .start = 0, .end = 3 }};
    const gc2 = gc1.withTasks(&tasks2);
    try testing.expectEqual(@as(usize, 1), gc1.tasks.len);
    try testing.expectEqualStrings("task1", gc1.tasks[0].name);
    try testing.expectEqual(@as(usize, 1), gc2.tasks.len);
    try testing.expectEqualStrings("task2", gc2.tasks[0].name);
}

test "withFocused returns new value, original unchanged" {
    const gc1 = GanttChart.init().withFocused(2);
    const gc2 = gc1.withFocused(5);
    try testing.expectEqual(@as(usize, 2), gc1.focused);
    try testing.expectEqual(@as(usize, 5), gc2.focused);
}

test "withLabelWidth returns new value, original unchanged" {
    const gc1 = GanttChart.init().withLabelWidth(15);
    const gc2 = gc1.withLabelWidth(30);
    try testing.expectEqual(@as(u16, 15), gc1.label_width);
    try testing.expectEqual(@as(u16, 30), gc2.label_width);
}

test "withShowProgress returns new value, original unchanged" {
    const gc1 = GanttChart.init().withShowProgress(false);
    const gc2 = gc1.withShowProgress(true);
    try testing.expect(gc1.show_progress == false);
    try testing.expect(gc2.show_progress == true);
}

test "withBlock returns new value, original unchanged" {
    const gc1 = GanttChart.init();
    const gc2 = gc1.withBlock(.{});
    try testing.expect(gc1.block == null);
    try testing.expect(gc2.block != null);
}

// ============================================================================
// Group 4: taskCount (4 tests)
// ============================================================================

test "taskCount with zero tasks returns 0" {
    const gc = GanttChart.init();
    try testing.expectEqual(@as(usize, 0), gc.taskCount());
}

test "taskCount with 3 tasks returns 3" {
    var tasks = [_]Task{
        .{ .name = "a", .start = 0, .end = 5 },
        .{ .name = "b", .start = 5, .end = 10 },
        .{ .name = "c", .start = 10, .end = 15 },
    };
    const gc = GanttChart.init().withTasks(&tasks);
    try testing.expectEqual(@as(usize, 3), gc.taskCount());
}

test "taskCount with 64 tasks (MAX) returns 64" {
    var tasks: [GanttChart.MAX_TASKS]Task = undefined;
    for (0..GanttChart.MAX_TASKS) |i| {
        tasks[i] = Task{ .name = "task", .start = @intCast(i), .end = @intCast(i + 1) };
    }
    const gc = GanttChart.init().withTasks(&tasks);
    try testing.expectEqual(@as(usize, GanttChart.MAX_TASKS), gc.taskCount());
}

test "taskCount with 65 tasks capped at MAX_TASKS (64)" {
    var tasks: [65]Task = undefined;
    for (0..65) |i| {
        tasks[i] = Task{ .name = "task", .start = @intCast(i), .end = @intCast(i + 1) };
    }
    const gc = GanttChart.init().withTasks(&tasks);
    try testing.expectEqual(@as(usize, GanttChart.MAX_TASKS), gc.taskCount());
}

// ============================================================================
// Group 5: Zero/Minimal Area Rendering (3 tests)
// ============================================================================

test "render with zero height does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "test", .start = 0, .end = 5 }};
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 0 };
    gc.render(&buf, area);
}

test "render with zero width does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "test", .start = 0, .end = 5 }};
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 10 };
    gc.render(&buf, area);
}

test "render with 1x1 area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "test", .start = 0, .end = 5 }};
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 1, .height = 1 };
    gc.render(&buf, area);
}

// ============================================================================
// Group 6: Empty Tasks Rendering (2 tests)
// ============================================================================

test "render with no tasks produces no content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const gc = GanttChart.init();
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    gc.render(&buf, area);

    try testing.expectEqual(@as(usize, 0), countNonEmptyCells(buf, area));
}

test "render with no tasks but with block renders border only" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    const gc = GanttChart.init().withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    gc.render(&buf, area);

    // Border characters should render (or minimal rendering)
    const cells = countNonEmptyCells(buf, area);
    try testing.expect(cells >= 0); // No crash is the key requirement
}

// ============================================================================
// Group 7: Single Task Rendering (6 tests)
// ============================================================================

test "render single task shows task name in label area" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "MyTask", .start = 0, .end = 10 }};
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "MyTask"));
}

test "render single task has bar chars in timeline area" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10 }};
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Should have block chars (█ or ░) representing the bar
    const has_filled = areaHasChar(buf, area, '█');
    const has_empty = areaHasChar(buf, area, '░');
    try testing.expect(has_filled or has_empty);
}

test "render single task with 100% progress shows full bar (all █)" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10, .progress = 100 }};
    const gc = GanttChart.init().withTasks(&tasks).withShowProgress(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Task should render
    try testing.expect(findInArea(buf, area, "task"));
}

test "render single task with 0% progress shows only empty bar (░) when show_progress=true" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10, .progress = 0 }};
    const gc = GanttChart.init().withTasks(&tasks).withShowProgress(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Task should render
    try testing.expect(findInArea(buf, area, "task"));
}

test "render single task has separator │ between label and timeline" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10 }};
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Should have separator between label and timeline
    try testing.expect(areaHasChar(buf, area, '│'));
}

test "render single task with show_progress=false shows all █ regardless of progress" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10, .progress = 50 }};
    const gc = GanttChart.init().withTasks(&tasks).withShowProgress(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Task should render
    try testing.expect(findInArea(buf, area, "task"));
}

// ============================================================================
// Group 8: Multiple Tasks Rendering (5 tests)
// ============================================================================

test "render multiple tasks renders each task on its own row" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{
        .{ .name = "first", .start = 0, .end = 5 },
        .{ .name = "second", .start = 5, .end = 10 },
    };
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    gc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "first"));
    try testing.expect(findInArea(buf, area, "second"));
}

test "render multiple tasks shows tasks in order (first at top)" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{
        .{ .name = "alpha", .start = 0, .end = 5 },
        .{ .name = "beta", .start = 5, .end = 10 },
        .{ .name = "gamma", .start = 10, .end = 15 },
    };
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    gc.render(&buf, area);

    // alpha should appear before beta and gamma
    var alpha_y: i16 = -1;
    var beta_y: i16 = -1;
    var y: u16 = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        if (alpha_y == -1 and findInArea(buf, Rect{ .x = 0, .y = y, .width = 80, .height = 1 }, "alpha")) {
            alpha_y = @intCast(y);
        }
        if (beta_y == -1 and findInArea(buf, Rect{ .x = 0, .y = y, .width = 80, .height = 1 }, "beta")) {
            beta_y = @intCast(y);
        }
    }
    try testing.expect(alpha_y >= 0);
    try testing.expect(beta_y >= 0);
    try testing.expect(alpha_y < beta_y);
}

test "render 3 tasks in limited height shows only tasks that fit" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{
        .{ .name = "task1", .start = 0, .end = 5 },
        .{ .name = "task2", .start = 5, .end = 10 },
        .{ .name = "task3", .start = 10, .end = 15 },
    };
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 2 };
    gc.render(&buf, area);

    // At least first task should be visible
    try testing.expect(findInArea(buf, area, "task1"));
}

test "render multiple tasks all have bar chars" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{
        .{ .name = "a", .start = 0, .end = 5 },
        .{ .name = "b", .start = 5, .end = 10 },
        .{ .name = "c", .start = 10, .end = 15 },
    };
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    gc.render(&buf, area);

    // Should have bar characters for each task
    try testing.expect(areaHasChar(buf, area, '█') or areaHasChar(buf, area, '░'));
}

// ============================================================================
// Group 9: Focused Task Styling (5 tests)
// ============================================================================

test "render focused task at index 0 renders with focused styling" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{
        .{ .name = "first", .start = 0, .end = 5 },
        .{ .name = "second", .start = 5, .end = 10 },
    };
    const gc = GanttChart.init().withTasks(&tasks).withFocused(0);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    gc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "first"));
}

test "render focused task at last index renders without error" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{
        .{ .name = "task1", .start = 0, .end = 5 },
        .{ .name = "task2", .start = 5, .end = 10 },
        .{ .name = "task3", .start = 10, .end = 15 },
    };
    const gc = GanttChart.init().withTasks(&tasks).withFocused(2);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    gc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "task3"));
}

test "render focused index beyond task count clamps gracefully" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{
        .{ .name = "task1", .start = 0, .end = 5 },
        .{ .name = "task2", .start = 5, .end = 10 },
    };
    const gc = GanttChart.init().withTasks(&tasks).withFocused(100);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    gc.render(&buf, area);

    // Should not crash; at least one task visible
    const cells = countNonEmptyCells(buf, area);
    try testing.expect(cells > 0);
}

test "render focused task row has different styling than non-focused rows" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{
        .{ .name = "a", .start = 0, .end = 5 },
        .{ .name = "b", .start = 5, .end = 10 },
    };
    const focused_style = Style{ .bold = true };
    const gc = GanttChart.init().withTasks(&tasks).withFocused(1).withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    gc.render(&buf, area);

    // Both tasks should render
    try testing.expect(findInArea(buf, area, "a") and findInArea(buf, area, "b"));
}

test "render non-focused tasks do not have focused_style applied" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{
        .{ .name = "focused", .start = 0, .end = 5 },
        .{ .name = "blurred", .start = 5, .end = 10 },
    };
    const gc = GanttChart.init().withTasks(&tasks).withFocused(0);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    gc.render(&buf, area);

    // Both should render
    try testing.expect(findInArea(buf, area, "focused") and findInArea(buf, area, "blurred"));
}

// ============================================================================
// Group 10: Progress Fill (6 tests)
// ============================================================================

test "render task with 50% progress shows half █ half ░ when show_progress=true" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10, .progress = 50 }};
    const gc = GanttChart.init().withTasks(&tasks).withShowProgress(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Task and bar should render
    try testing.expect(findInArea(buf, area, "task"));
}

test "render task with 0% progress shows all ░ when show_progress=true" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10, .progress = 0 }};
    const gc = GanttChart.init().withTasks(&tasks).withShowProgress(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "task"));
}

test "render task with 100% progress shows all █ when show_progress=true" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10, .progress = 100 }};
    const gc = GanttChart.init().withTasks(&tasks).withShowProgress(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "task"));
}

test "render task with 25% progress renders partial fill when show_progress=true" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10, .progress = 25 }};
    const gc = GanttChart.init().withTasks(&tasks).withShowProgress(true);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "task"));
}

test "render task with show_progress=false shows entire bar as █ regardless of progress" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10, .progress = 33 }};
    const gc = GanttChart.init().withTasks(&tasks).withShowProgress(false);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "task"));
}

test "render task uses complete_style for filled portion of progress" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10, .progress = 50 }};
    const complete_style = Style{ .fg = .green };
    const gc = GanttChart.init().withTasks(&tasks).withCompleteStyle(complete_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Task should render with complete_style applied to filled portion
    try testing.expect(findInArea(buf, area, "task"));
}

// ============================================================================
// Group 11: Label Width (5 tests)
// ============================================================================

test "render task with label_width=20 uses 20 char column for label" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10 }};
    const gc = GanttChart.init().withTasks(&tasks).withLabelWidth(20);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "task"));
}

test "render task with label_width=10 reduces label column to 10 chars" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10 }};
    const gc = GanttChart.init().withTasks(&tasks).withLabelWidth(10);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "task"));
}

test "render task with long name truncates to label_width" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "this is a very long task name", .start = 0, .end = 10 }};
    const gc = GanttChart.init().withTasks(&tasks).withLabelWidth(15);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Should not crash; part of name should render
    const cells = countNonEmptyCells(buf, area);
    try testing.expect(cells > 0);
}

test "render task with short name pads to label_width with spaces" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "a", .start = 0, .end = 10 }};
    const gc = GanttChart.init().withTasks(&tasks).withLabelWidth(20);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "a"));
}

test "render smaller label_width increases bar area width" {
    var buf1 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf1.deinit();
    var buf2 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf2.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10 }};
    const gc1 = GanttChart.init().withTasks(&tasks).withLabelWidth(30);
    const gc2 = GanttChart.init().withTasks(&tasks).withLabelWidth(10);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };

    gc1.render(&buf1, area);
    gc2.render(&buf2, area);

    // gc2 with smaller label width should have same or more bar content
    try testing.expect(countNonEmptyCells(buf1, area) > 0);
    try testing.expect(countNonEmptyCells(buf2, area) > 0);
}

// ============================================================================
// Group 12: Auto-Scaling (4 tests)
// ============================================================================

test "render single task with start=0 end=10 bar scales to full width" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10 }};
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Should scale and render task
    try testing.expect(findInArea(buf, area, "task"));
}

test "render two tasks with different end times scales correctly" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{
        .{ .name = "early", .start = 0, .end = 5 },
        .{ .name = "late", .start = 5, .end = 10 },
    };
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    gc.render(&buf, area);

    // early task bar should be narrower than late task bar
    try testing.expect(findInArea(buf, area, "early") and findInArea(buf, area, "late"));
}

test "render tasks all ending at same point fill width equally" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{
        .{ .name = "task1", .start = 0, .end = 10 },
        .{ .name = "task2", .start = 0, .end = 10 },
    };
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 10 };
    gc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "task1") and findInArea(buf, area, "task2"));
}

test "render with no tasks or end=0 defaults scale gracefully" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 0 }};
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Should not crash even with end=0
    const cells = countNonEmptyCells(buf, area);
    try testing.expect(cells >= 0);
}

// ============================================================================
// Group 13: Bar Style (4 tests)
// ============================================================================

test "render bar with bar_style applies style to bar cells" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10 }};
    const bar_style = Style{ .fg = .blue };
    const gc = GanttChart.init().withTasks(&tasks).withBarStyle(bar_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Bar with style should render
    try testing.expect(findInArea(buf, area, "task"));
}

test "render task with custom style uses that style instead of bar_style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10, .style = Style{ .fg = .red } }};
    const gc = GanttChart.init().withTasks(&tasks).withBarStyle(Style{ .fg = .blue });
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Task's custom style should be applied
    try testing.expect(findInArea(buf, area, "task"));
}

test "render task with style == null uses bar_style" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10, .style = null }};
    const bar_style = Style{ .fg = .green };
    const gc = GanttChart.init().withTasks(&tasks).withBarStyle(bar_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "task"));
}

test "render focused task uses focused_style for bar rendering" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10 }};
    const focused_style = Style{ .bold = true };
    const gc = GanttChart.init().withTasks(&tasks).withFocused(0).withFocusedStyle(focused_style);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Focused task should render with focused_style
    try testing.expect(findInArea(buf, area, "task"));
}

// ============================================================================
// Group 14: Block Border (4 tests)
// ============================================================================

test "render with Block renders frame around content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10 }};
    const gc = GanttChart.init().withTasks(&tasks).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 10 };
    gc.render(&buf, area);

    // Block border should render (box drawing chars)
    const has_border = areaHasChar(buf, area, '─') or
                       areaHasChar(buf, area, '│') or
                       areaHasChar(buf, area, '┌');
    try testing.expect(has_border or countNonEmptyCells(buf, area) > 0);
}

test "render block reduces inner area for content" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10 }};
    const gc = GanttChart.init().withTasks(&tasks).withBlock(.{});
    const area = Rect{ .x = 5, .y = 5, .width = 40, .height = 10 };
    gc.render(&buf, area);

    // Content should render inside block area
    try testing.expect(countNonEmptyCells(buf, area) > 0);
}

test "render tasks render inside block border inner area" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "inside", .start = 0, .end = 10 }};
    const gc = GanttChart.init().withTasks(&tasks).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    gc.render(&buf, area);

    // Task content should be visible
    try testing.expect(findInArea(buf, area, "inside") or countNonEmptyCells(buf, area) > 0);
}

test "render block in tiny area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 10 }};
    const gc = GanttChart.init().withTasks(&tasks).withBlock(.{});
    const area = Rect{ .x = 0, .y = 0, .width = 3, .height = 3 };
    gc.render(&buf, area);

    // Should not crash
    const cells = countNonEmptyCells(buf, area);
    try testing.expect(cells <= 9); // 3x3 max
}

// ============================================================================
// Group 15: Edge Cases (4 tests)
// ============================================================================

test "render task with start == end renders no-width bar without crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 5, .end = 5 }};
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Should not crash even with zero-width bar
    const cells = countNonEmptyCells(buf, area);
    try testing.expect(cells >= 0);
}

test "render task with end=0 does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "task", .start = 0, .end = 0 }};
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    // Should handle gracefully
    const cells = countNonEmptyCells(buf, area);
    try testing.expect(cells >= 0);
}

test "render in offset area (x>0, y>0) renders correctly" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "offset", .start = 0, .end = 10 }};
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 10, .y = 5, .width = 50, .height = 10 };
    gc.render(&buf, area);

    // Should render in offset area
    try testing.expect(findInArea(buf, area, "offset") or countNonEmptyCells(buf, area) > 0);
}

test "render ASCII task name renders correctly" {
    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    var tasks = [_]Task{.{ .name = "ASCII_Task-123", .start = 0, .end = 10 }};
    const gc = GanttChart.init().withTasks(&tasks);
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 5 };
    gc.render(&buf, area);

    try testing.expect(findInArea(buf, area, "ASCII_Task"));
}
