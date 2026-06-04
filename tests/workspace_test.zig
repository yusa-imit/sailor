//! Workspace Tests — v2.22.0
//!
//! Tests Workspace widget for multi-pane layout management with focus cycling.
//! Workspace holds pane descriptors, computes layout rects, and manages focus navigation.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;

// Forward declarations — will be implemented after tests pass
const Workspace = sailor.tui.workspace.Workspace;
const WorkspacePane = sailor.tui.workspace.WorkspacePane;
const WorkspaceSplit = sailor.tui.workspace.WorkspaceSplit;

// ============================================================================
// Test Suite: Initialization and Default State
// ============================================================================

test "Workspace with single pane" {
    const panes = [_]WorkspacePane{
        .{ .id = "main", .flex = 1.0, .focusable = true },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .horizontal,
        .focus_idx = 0,
    };
    try testing.expectEqual(@as(usize, 1), ws.panes.len);
}

test "Workspace default gap is zero" {
    const panes = [_]WorkspacePane{
        .{ .id = "main", .flex = 1.0, .focusable = true },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .horizontal,
    };
    try testing.expectEqual(@as(u16, 0), ws.gap);
}

test "Workspace default split is horizontal" {
    const panes = [_]WorkspacePane{
        .{ .id = "main", .flex = 1.0, .focusable = true },
    };
    const ws = Workspace{
        .panes = &panes,
    };
    try testing.expectEqual(WorkspaceSplit.horizontal, ws.split);
}

test "Workspace default focus_idx is zero" {
    const panes = [_]WorkspacePane{
        .{ .id = "main", .flex = 1.0, .focusable = true },
    };
    const ws = Workspace{
        .panes = &panes,
    };
    try testing.expectEqual(@as(usize, 0), ws.focus_idx);
}

test "WorkspacePane default flex is 1.0" {
    const pane = WorkspacePane{ .id = "test" };
    try testing.expectEqual(1.0, pane.flex);
}

test "WorkspacePane default min_size is 3" {
    const pane = WorkspacePane{ .id = "test" };
    try testing.expectEqual(@as(u16, 3), pane.min_size);
}

test "WorkspacePane default focusable is true" {
    const pane = WorkspacePane{ .id = "test" };
    try testing.expect(pane.focusable);
}

// ============================================================================
// Test Suite: computeRects — Equal Flex
// ============================================================================

test "computeRects equal flex horizontal splits area equally" {
    var panes = [_]WorkspacePane{
        .{ .id = "left", .flex = 1.0, .min_size = 3 },
        .{ .id = "right", .flex = 1.0, .min_size = 3 },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .horizontal,
    };
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expectEqual(@as(u16, 40), rects[0].width);
    try testing.expectEqual(@as(u16, 40), rects[1].width);
}

test "computeRects equal flex vertical splits area equally" {
    var panes = [_]WorkspacePane{
        .{ .id = "top", .flex = 1.0, .min_size = 3 },
        .{ .id = "bottom", .flex = 1.0, .min_size = 3 },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .vertical,
    };
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expectEqual(@as(u16, 12), rects[0].height);
    try testing.expectEqual(@as(u16, 12), rects[1].height);
}

// ============================================================================
// Test Suite: computeRects — Proportional Flex
// ============================================================================

test "computeRects proportional flex 2:1 horizontal" {
    var panes = [_]WorkspacePane{
        .{ .id = "wide", .flex = 2.0, .min_size = 3 },
        .{ .id = "narrow", .flex = 1.0, .min_size = 3 },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .horizontal,
    };
    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 24 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    // 2/(2+1) = 2/3 of 90 = 60
    // 1/(2+1) = 1/3 of 90 = 30
    try testing.expectEqual(@as(u16, 60), rects[0].width);
    try testing.expectEqual(@as(u16, 30), rects[1].width);
}

test "computeRects proportional flex 2:1 vertical" {
    var panes = [_]WorkspacePane{
        .{ .id = "tall", .flex = 2.0, .min_size = 3 },
        .{ .id = "short", .flex = 1.0, .min_size = 3 },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .vertical,
    };
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    // 2/(2+1) = 2/3 of 30 = 20
    // 1/(2+1) = 1/3 of 30 = 10
    try testing.expectEqual(@as(u16, 20), rects[0].height);
    try testing.expectEqual(@as(u16, 10), rects[1].height);
}

// ============================================================================
// Test Suite: computeRects — Min Size Respected
// ============================================================================

test "computeRects respects min_size in horizontal layout" {
    var panes = [_]WorkspacePane{
        .{ .id = "left", .flex = 1.0, .min_size = 20 },
        .{ .id = "right", .flex = 1.0, .min_size = 3 },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .horizontal,
    };
    const area = Rect{ .x = 0, .y = 0, .width = 30, .height = 24 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expect(rects[0].width >= 20);
}

test "computeRects respects min_size in vertical layout" {
    var panes = [_]WorkspacePane{
        .{ .id = "top", .flex = 1.0, .min_size = 10 },
        .{ .id = "bottom", .flex = 1.0, .min_size = 3 },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .vertical,
    };
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 15 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expect(rects[0].height >= 10);
}

// ============================================================================
// Test Suite: computeRects — Edge Cases
// ============================================================================

test "computeRects single pane gets full area" {
    var panes = [_]WorkspacePane{
        .{ .id = "only", .flex = 1.0, .min_size = 3 },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .horizontal,
    };
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 1), rects.len);
    try testing.expectEqual(area.width, rects[0].width);
    try testing.expectEqual(area.height, rects[0].height);
}

test "computeRects zero-width area returns rects with zero width" {
    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .min_size = 3 },
        .{ .id = "b", .flex = 1.0, .min_size = 3 },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .horizontal,
    };
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 24 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expectEqual(@as(u16, 0), rects[0].width);
}

test "computeRects zero-height area returns rects with zero height" {
    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .min_size = 3 },
        .{ .id = "b", .flex = 1.0, .min_size = 3 },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .vertical,
    };
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 0 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    try testing.expectEqual(@as(u16, 0), rects[0].height);
}

test "computeRects preserves rect positions from area" {
    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .min_size = 3 },
        .{ .id = "b", .flex = 1.0, .min_size = 3 },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .horizontal,
    };
    const area = Rect{ .x = 10, .y = 5, .width = 60, .height = 20 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(u16, 10), rects[0].x);
    try testing.expectEqual(@as(u16, 5), rects[0].y);
}

// ============================================================================
// Test Suite: computeRects — Contiguity (no gaps)
// ============================================================================

test "computeRects horizontal panes are contiguous" {
    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .min_size = 3 },
        .{ .id = "b", .flex = 1.0, .min_size = 3 },
        .{ .id = "c", .flex = 1.0, .min_size = 3 },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .horizontal,
        .gap = 0,
    };
    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 24 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 3), rects.len);
    // rect[0].x + rect[0].width == rect[1].x
    try testing.expectEqual(rects[0].x + rects[0].width, rects[1].x);
    // rect[1].x + rect[1].width == rect[2].x
    try testing.expectEqual(rects[1].x + rects[1].width, rects[2].x);
}

test "computeRects vertical panes are contiguous" {
    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .min_size = 3 },
        .{ .id = "b", .flex = 1.0, .min_size = 3 },
        .{ .id = "c", .flex = 1.0, .min_size = 3 },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .vertical,
        .gap = 0,
    };
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 3), rects.len);
    // rect[0].y + rect[0].height == rect[1].y
    try testing.expectEqual(rects[0].y + rects[0].height, rects[1].y);
    // rect[1].y + rect[1].height == rect[2].y
    try testing.expectEqual(rects[1].y + rects[1].height, rects[2].y);
}

// ============================================================================
// Test Suite: Focus Navigation — focusNext
// ============================================================================

test "focusNext advances focus to next pane" {
    var panes = [_]WorkspacePane{
        .{ .id = "first", .flex = 1.0, .focusable = true },
        .{ .id = "second", .flex = 1.0, .focusable = true },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 0,
    };

    ws.focusNext();
    try testing.expectEqual(@as(usize, 1), ws.focus_idx);
}

test "focusNext wraps around from last to first" {
    var panes = [_]WorkspacePane{
        .{ .id = "first", .flex = 1.0, .focusable = true },
        .{ .id = "second", .flex = 1.0, .focusable = true },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 1,
    };

    ws.focusNext();
    try testing.expectEqual(@as(usize, 0), ws.focus_idx);
}

test "focusNext skips non-focusable panes" {
    var panes = [_]WorkspacePane{
        .{ .id = "first", .flex = 1.0, .focusable = true },
        .{ .id = "disabled", .flex = 1.0, .focusable = false },
        .{ .id = "third", .flex = 1.0, .focusable = true },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 0,
    };

    ws.focusNext();
    // Should skip "disabled" and land on "third"
    try testing.expectEqual(@as(usize, 2), ws.focus_idx);
}

// ============================================================================
// Test Suite: Focus Navigation — focusPrev
// ============================================================================

test "focusPrev moves focus to previous pane" {
    var panes = [_]WorkspacePane{
        .{ .id = "first", .flex = 1.0, .focusable = true },
        .{ .id = "second", .flex = 1.0, .focusable = true },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 1,
    };

    ws.focusPrev();
    try testing.expectEqual(@as(usize, 0), ws.focus_idx);
}

test "focusPrev wraps around from first to last" {
    var panes = [_]WorkspacePane{
        .{ .id = "first", .flex = 1.0, .focusable = true },
        .{ .id = "second", .flex = 1.0, .focusable = true },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 0,
    };

    ws.focusPrev();
    try testing.expectEqual(@as(usize, 1), ws.focus_idx);
}

test "focusPrev skips non-focusable panes" {
    var panes = [_]WorkspacePane{
        .{ .id = "first", .flex = 1.0, .focusable = true },
        .{ .id = "disabled", .flex = 1.0, .focusable = false },
        .{ .id = "third", .flex = 1.0, .focusable = true },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 2,
    };

    ws.focusPrev();
    // Should skip "disabled" and land on "first"
    try testing.expectEqual(@as(usize, 0), ws.focus_idx);
}

// ============================================================================
// Test Suite: Focus Navigation — focusPane by ID
// ============================================================================

test "focusPane sets focus by id" {
    var panes = [_]WorkspacePane{
        .{ .id = "left", .flex = 1.0, .focusable = true },
        .{ .id = "right", .flex = 1.0, .focusable = true },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 0,
    };

    const found = ws.focusPane("right");
    try testing.expect(found);
    try testing.expectEqual(@as(usize, 1), ws.focus_idx);
}

test "focusPane returns false for unknown id" {
    var panes = [_]WorkspacePane{
        .{ .id = "left", .flex = 1.0, .focusable = true },
        .{ .id = "right", .flex = 1.0, .focusable = true },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 0,
    };

    const found = ws.focusPane("nonexistent");
    try testing.expect(!found);
    // focus_idx should not change
    try testing.expectEqual(@as(usize, 0), ws.focus_idx);
}

test "focusPane finds first matching id" {
    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .focusable = true },
        .{ .id = "target", .flex = 1.0, .focusable = true },
        .{ .id = "b", .flex = 1.0, .focusable = true },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 0,
    };

    _ = ws.focusPane("target");
    try testing.expectEqual(@as(usize, 1), ws.focus_idx);
}

// ============================================================================
// Test Suite: Focus Query Functions
// ============================================================================

test "getFocusedId returns current pane id" {
    var panes = [_]WorkspacePane{
        .{ .id = "left", .flex = 1.0, .focusable = true },
        .{ .id = "right", .flex = 1.0, .focusable = true },
    };
    const ws = Workspace{
        .panes = &panes,
        .focus_idx = 1,
    };

    const id = ws.getFocusedId();
    try testing.expect(id != null);
    try testing.expectEqualStrings("right", id.?);
}

test "getFocusedId returns null for invalid focus_idx" {
    var panes = [_]WorkspacePane{
        .{ .id = "left", .flex = 1.0, .focusable = true },
    };
    const ws = Workspace{
        .panes = &panes,
        .focus_idx = 5, // out of bounds
    };

    const id = ws.getFocusedId();
    try testing.expect(id == null);
}

test "isFocused returns true only for focused pane" {
    var panes = [_]WorkspacePane{
        .{ .id = "left", .flex = 1.0, .focusable = true },
        .{ .id = "right", .flex = 1.0, .focusable = true },
    };
    const ws = Workspace{
        .panes = &panes,
        .focus_idx = 0,
    };

    try testing.expect(ws.isFocused("left"));
    try testing.expect(!ws.isFocused("right"));
}

test "isFocused returns false for unknown pane" {
    var panes = [_]WorkspacePane{
        .{ .id = "left", .flex = 1.0, .focusable = true },
    };
    const ws = Workspace{
        .panes = &panes,
        .focus_idx = 0,
    };

    try testing.expect(!ws.isFocused("unknown"));
}

// ============================================================================
// Test Suite: Focus Navigation — Edge Cases
// ============================================================================

test "focusNext on single pane is no-op" {
    var panes = [_]WorkspacePane{
        .{ .id = "only", .flex = 1.0, .focusable = true },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 0,
    };

    ws.focusNext();
    // Should stay at 0
    try testing.expectEqual(@as(usize, 0), ws.focus_idx);
}

test "focusPrev on single pane is no-op" {
    var panes = [_]WorkspacePane{
        .{ .id = "only", .flex = 1.0, .focusable = true },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 0,
    };

    ws.focusPrev();
    // Should stay at 0
    try testing.expectEqual(@as(usize, 0), ws.focus_idx);
}

test "focusNext with all non-focusable panes does not infinite loop" {
    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .focusable = false },
        .{ .id = "b", .flex = 1.0, .focusable = false },
        .{ .id = "c", .flex = 1.0, .focusable = false },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 0,
    };

    // Should not hang; should eventually settle on current or nearby idx
    ws.focusNext();
    // focus_idx should still be valid (< panes.len)
    try testing.expect(ws.focus_idx < ws.panes.len);
}

test "focusPrev with all non-focusable panes does not infinite loop" {
    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .focusable = false },
        .{ .id = "b", .flex = 1.0, .focusable = false },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 1,
    };

    ws.focusPrev();
    try testing.expect(ws.focus_idx < ws.panes.len);
}

// ============================================================================
// Test Suite: renderDividers
// ============================================================================

test "renderDividers does not panic on zero area" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .focusable = true },
        .{ .id = "b", .flex = 1.0, .focusable = true },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .horizontal,
    };

    const zero_area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    const rects = try ws.computeRects(testing.allocator, zero_area);
    defer testing.allocator.free(rects);

    // Should not crash
    ws.renderDividers(&buf, rects);
}

test "renderDividers horizontal layout renders dividers at boundaries" {
    var buf = try Buffer.init(testing.allocator, 90, 24);
    defer buf.deinit();

    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .focusable = true },
        .{ .id = "b", .flex = 1.0, .focusable = true },
        .{ .id = "c", .flex = 1.0, .focusable = true },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .horizontal,
        .gap = 1,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 90, .height = 24 };
    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    ws.renderDividers(&buf, rects);
    // Should have rendered dividers; no assertion on exact content for now
}

test "renderDividers vertical layout renders dividers at boundaries" {
    var buf = try Buffer.init(testing.allocator, 80, 30);
    defer buf.deinit();

    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .focusable = true },
        .{ .id = "b", .flex = 1.0, .focusable = true },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .vertical,
        .gap = 1,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };
    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    ws.renderDividers(&buf, rects);
    // Should not crash
}

test "renderDividers single pane renders no dividers" {
    var buf = try Buffer.init(testing.allocator, 80, 24);
    defer buf.deinit();

    var panes = [_]WorkspacePane{
        .{ .id = "only", .flex = 1.0, .focusable = true },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .horizontal,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    ws.renderDividers(&buf, rects);
    // Should not crash (no dividers to render)
}

// ============================================================================
// Test Suite: Boundary Checks
// ============================================================================

test "focus_idx stays in bounds after focus navigation" {
    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .focusable = true },
        .{ .id = "b", .flex = 1.0, .focusable = true },
        .{ .id = "c", .flex = 1.0, .focusable = true },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 2,
    };

    ws.focusNext();
    try testing.expect(ws.focus_idx < ws.panes.len);

    ws.focusPrev();
    try testing.expect(ws.focus_idx < ws.panes.len);
}

test "computeRects allocation is properly freed without leaks" {
    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .focusable = true },
        .{ .id = "b", .flex = 1.0, .focusable = true },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .horizontal,
    };
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    try testing.expectEqual(@as(usize, 2), rects.len);
    // Allocator tracks freed memory; this test passes if no leak is detected
}

// ============================================================================
// Test Suite: Multiple Configurations
// ============================================================================

test "workspace 3 panes equal flex horizontal sums to full width" {
    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .min_size = 3 },
        .{ .id = "b", .flex = 1.0, .min_size = 3 },
        .{ .id = "c", .flex = 1.0, .min_size = 3 },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .horizontal,
        .gap = 0,
    };
    const area = Rect{ .x = 0, .y = 0, .width = 99, .height = 24 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    const total_width = rects[0].width + rects[1].width + rects[2].width;
    try testing.expectEqual(area.width, total_width);
}

test "workspace 3 panes equal flex vertical sums to full height" {
    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .min_size = 3 },
        .{ .id = "b", .flex = 1.0, .min_size = 3 },
        .{ .id = "c", .flex = 1.0, .min_size = 3 },
    };
    const ws = Workspace{
        .panes = &panes,
        .split = .vertical,
        .gap = 0,
    };
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 30 };

    const rects = try ws.computeRects(testing.allocator, area);
    defer testing.allocator.free(rects);

    const total_height = rects[0].height + rects[1].height + rects[2].height;
    try testing.expectEqual(area.height, total_height);
}

test "focus cycle through 3 focusable panes" {
    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .focusable = true },
        .{ .id = "b", .flex = 1.0, .focusable = true },
        .{ .id = "c", .flex = 1.0, .focusable = true },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 0,
    };

    ws.focusNext();
    try testing.expectEqual(@as(usize, 1), ws.focus_idx);

    ws.focusNext();
    try testing.expectEqual(@as(usize, 2), ws.focus_idx);

    ws.focusNext();
    try testing.expectEqual(@as(usize, 0), ws.focus_idx);
}

test "focus cycle backwards through 3 panes" {
    var panes = [_]WorkspacePane{
        .{ .id = "a", .flex = 1.0, .focusable = true },
        .{ .id = "b", .flex = 1.0, .focusable = true },
        .{ .id = "c", .flex = 1.0, .focusable = true },
    };
    var ws = Workspace{
        .panes = &panes,
        .focus_idx = 0,
    };

    ws.focusPrev();
    try testing.expectEqual(@as(usize, 2), ws.focus_idx);

    ws.focusPrev();
    try testing.expectEqual(@as(usize, 1), ws.focus_idx);

    ws.focusPrev();
    try testing.expectEqual(@as(usize, 0), ws.focus_idx);
}
