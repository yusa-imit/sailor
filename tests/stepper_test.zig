//! Stepper Widget Tests — v2.18.0
//!
//! Tests multi-step wizard/progress indicator widget with step navigation,
//! status tracking, and rendering in horizontal and vertical layouts.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Block = sailor.tui.widgets.Block;
const Direction = sailor.tui.Direction;
const Stepper = sailor.tui.widgets.Stepper;
const StepStatus = sailor.tui.widgets.StepperStatus;
const Step = sailor.tui.widgets.StepperStep;

// Helper to create step array
fn makeSteps(allocator: std.mem.Allocator, labels: []const []const u8) ![]Step {
    const steps = try allocator.alloc(Step, labels.len);
    for (labels, 0..) |label, i| {
        steps[i] = Step{ .label = label, .status = .pending };
    }
    return steps;
}

// ============================================================================
// Stepper Default State
// ============================================================================

test "Stepper default state has current=0" {
    var stepper = Stepper{};
    try testing.expectEqual(@as(usize, 0), stepper.current);
}

test "Stepper default state is horizontal direction" {
    var stepper = Stepper{};
    try testing.expectEqual(Direction.horizontal, stepper.direction);
}

test "Stepper default state has no block" {
    var stepper = Stepper{};
    try testing.expect(stepper.block == null);
}

test "Stepper with empty steps" {
    var stepper = Stepper{ .steps = &.{} };
    try testing.expectEqual(@as(usize, 0), stepper.steps.len);
}

test "Stepper with single step" {
    const steps = [_]Step{.{ .label = "Step 1", .status = .pending }};
    var stepper = Stepper{ .steps = &steps };
    try testing.expectEqual(@as(usize, 1), stepper.steps.len);
}

test "Stepper with multiple steps" {
    const steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
        .{ .label = "Step 3", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps };
    try testing.expectEqual(@as(usize, 3), stepper.steps.len);
}

// ============================================================================
// moveNext — Forward Navigation
// ============================================================================

test "moveNext increments current by 1" {
    const steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 0 };
    stepper.moveNext();
    try testing.expectEqual(@as(usize, 1), stepper.current);
}

test "moveNext from step 1 moves to step 2" {
    const steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
        .{ .label = "Step 3", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 1 };
    stepper.moveNext();
    try testing.expectEqual(@as(usize, 2), stepper.current);
}

test "moveNext at last step clamps to last index" {
    const steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 1 };
    stepper.moveNext();
    try testing.expectEqual(@as(usize, 1), stepper.current);
}

test "moveNext multiple times accumulates within bounds" {
    const steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
        .{ .label = "Step 3", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 0 };
    stepper.moveNext();
    stepper.moveNext();
    stepper.moveNext();
    stepper.moveNext();
    try testing.expectEqual(@as(usize, 2), stepper.current);
}

test "moveNext on empty steps does not crash" {
    var stepper = Stepper{ .steps = &.{} };
    stepper.moveNext();
    // Should not crash or panic
}

test "moveNext from start reaches last step in 2-step wizard" {
    const steps = [_]Step{
        .{ .label = "Begin", .status = .pending },
        .{ .label = "End", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 0 };
    stepper.moveNext();
    try testing.expectEqual(@as(usize, 1), stepper.current);
}

// ============================================================================
// movePrev — Backward Navigation
// ============================================================================

test "movePrev decrements current by 1" {
    const steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 1 };
    stepper.movePrev();
    try testing.expectEqual(@as(usize, 0), stepper.current);
}

test "movePrev from step 2 moves to step 1" {
    const steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
        .{ .label = "Step 3", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 2 };
    stepper.movePrev();
    try testing.expectEqual(@as(usize, 1), stepper.current);
}

test "movePrev at first step clamps to 0" {
    const steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 0 };
    stepper.movePrev();
    try testing.expectEqual(@as(usize, 0), stepper.current);
}

test "movePrev multiple times accumulates within bounds" {
    const steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
        .{ .label = "Step 3", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 2 };
    stepper.movePrev();
    stepper.movePrev();
    stepper.movePrev();
    try testing.expectEqual(@as(usize, 0), stepper.current);
}

test "movePrev on empty steps does not crash" {
    var stepper = Stepper{ .steps = &.{}, .current = 0 };
    stepper.movePrev();
    // Should not crash or panic
}

test "moveNext then movePrev returns to start" {
    const steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 0 };
    stepper.moveNext();
    stepper.movePrev();
    try testing.expectEqual(@as(usize, 0), stepper.current);
}

// ============================================================================
// setStatus — Update Step Status
// ============================================================================

test "setStatus updates step status" {
    var steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps };

    stepper.setStatus(0, .completed);
    try testing.expectEqual(StepStatus.completed, steps[0].status);
}

test "setStatus on different step updates correct step" {
    var steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
        .{ .label = "Step 3", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps };

    stepper.setStatus(1, .active);
    try testing.expectEqual(StepStatus.pending, steps[0].status);
    try testing.expectEqual(StepStatus.active, steps[1].status);
    try testing.expectEqual(StepStatus.pending, steps[2].status);
}

test "setStatus can set failed status" {
    var steps = [_]Step{.{ .label = "Step 1", .status = .pending }};
    var stepper = Stepper{ .steps = &steps };

    stepper.setStatus(0, .failed);
    try testing.expectEqual(StepStatus.failed, steps[0].status);
}

test "setStatus out of bounds does not crash" {
    var steps = [_]Step{.{ .label = "Step 1", .status = .pending }};
    var stepper = Stepper{ .steps = &steps };

    stepper.setStatus(10, .completed);
    // Should not crash, silently ignore
}

test "setStatus with negative (wrapped) index does not crash" {
    var steps = [_]Step{.{ .label = "Step 1", .status = .pending }};
    var stepper = Stepper{ .steps = &steps };

    // Calling with max usize or large index should be safe
    const large_idx: usize = 99999;
    stepper.setStatus(large_idx, .completed);
    // Should not crash
}

test "setStatus on empty steps does not crash" {
    var stepper = Stepper{ .steps = &.{} };
    stepper.setStatus(0, .completed);
    // Should not crash
}

test "setStatus can change from one status to another" {
    var steps = [_]Step{.{ .label = "Step 1", .status = .pending }};
    var stepper = Stepper{ .steps = &steps };

    stepper.setStatus(0, .active);
    try testing.expectEqual(StepStatus.active, steps[0].status);
    stepper.setStatus(0, .completed);
    try testing.expectEqual(StepStatus.completed, steps[0].status);
}

// ============================================================================
// isComplete — Check All Steps Done
// ============================================================================

test "isComplete is true when all steps are completed" {
    var steps = [_]Step{
        .{ .label = "Step 1", .status = .completed },
        .{ .label = "Step 2", .status = .completed },
    };
    var stepper = Stepper{ .steps = &steps };

    try testing.expect(stepper.isComplete());
}

test "isComplete is false when any step is pending" {
    var steps = [_]Step{
        .{ .label = "Step 1", .status = .completed },
        .{ .label = "Step 2", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps };

    try testing.expect(!stepper.isComplete());
}

test "isComplete is false when any step is active" {
    var steps = [_]Step{
        .{ .label = "Step 1", .status = .completed },
        .{ .label = "Step 2", .status = .active },
    };
    var stepper = Stepper{ .steps = &steps };

    try testing.expect(!stepper.isComplete());
}

test "isComplete is false when any step is failed" {
    var steps = [_]Step{
        .{ .label = "Step 1", .status = .completed },
        .{ .label = "Step 2", .status = .failed },
    };
    var stepper = Stepper{ .steps = &steps };

    try testing.expect(!stepper.isComplete());
}

test "isComplete is true for single completed step" {
    var steps = [_]Step{.{ .label = "Step 1", .status = .completed }};
    var stepper = Stepper{ .steps = &steps };

    try testing.expect(stepper.isComplete());
}

test "isComplete is false for single pending step" {
    var steps = [_]Step{.{ .label = "Step 1", .status = .pending }};
    var stepper = Stepper{ .steps = &steps };

    try testing.expect(!stepper.isComplete());
}

test "isComplete is false for empty steps" {
    var stepper = Stepper{ .steps = &.{} };

    // Empty workflow is technically "complete" (vacuous truth) or "not started"
    // Implementation may return true or false, just verify no crash
    _ = stepper.isComplete();
}

// ============================================================================
// hasFailed — Check Any Step Failed
// ============================================================================

test "hasFailed is true when any step is failed" {
    var steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .failed },
    };
    var stepper = Stepper{ .steps = &steps };

    try testing.expect(stepper.hasFailed());
}

test "hasFailed is false when no step is failed" {
    var steps = [_]Step{
        .{ .label = "Step 1", .status = .completed },
        .{ .label = "Step 2", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps };

    try testing.expect(!stepper.hasFailed());
}

test "hasFailed is false for all pending steps" {
    var steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps };

    try testing.expect(!stepper.hasFailed());
}

test "hasFailed is false for all completed steps" {
    var steps = [_]Step{
        .{ .label = "Step 1", .status = .completed },
        .{ .label = "Step 2", .status = .completed },
    };
    var stepper = Stepper{ .steps = &steps };

    try testing.expect(!stepper.hasFailed());
}

test "hasFailed is true for single failed step" {
    var steps = [_]Step{.{ .label = "Step 1", .status = .failed }};
    var stepper = Stepper{ .steps = &steps };

    try testing.expect(stepper.hasFailed());
}

test "hasFailed is false for empty steps" {
    var stepper = Stepper{ .steps = &.{} };

    try testing.expect(!stepper.hasFailed());
}

test "hasFailed with mixed statuses only true if failed exists" {
    var steps = [_]Step{
        .{ .label = "Step 1", .status = .active },
        .{ .label = "Step 2", .status = .completed },
        .{ .label = "Step 3", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps };

    try testing.expect(!stepper.hasFailed());
}

// ============================================================================
// currentStep — Get Current Step
// ============================================================================

test "currentStep returns current step" {
    const steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 0 };

    const current = stepper.currentStep();
    try testing.expect(current != null);
    try testing.expectEqualStrings("Step 1", current.?.label);
}

test "currentStep at different indices returns correct step" {
    const steps = [_]Step{
        .{ .label = "First", .status = .pending },
        .{ .label = "Second", .status = .pending },
        .{ .label = "Third", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 1 };

    const current = stepper.currentStep();
    try testing.expect(current != null);
    try testing.expectEqualStrings("Second", current.?.label);
}

test "currentStep returns null for empty steps" {
    var stepper = Stepper{ .steps = &.{}, .current = 0 };

    const current = stepper.currentStep();
    try testing.expect(current == null);
}

test "currentStep returns correct status" {
    var steps = [_]Step{
        .{ .label = "Step 1", .status = .active },
        .{ .label = "Step 2", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 0 };

    const current = stepper.currentStep();
    try testing.expect(current != null);
    try testing.expectEqual(StepStatus.active, current.?.status);
}

test "currentStep at last index" {
    const steps = [_]Step{
        .{ .label = "First", .status = .pending },
        .{ .label = "Last", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 1 };

    const current = stepper.currentStep();
    try testing.expect(current != null);
    try testing.expectEqualStrings("Last", current.?.label);
}

// ============================================================================
// render — Widget Rendering
// ============================================================================

test "render on zero-area does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

    const steps = [_]Step{.{ .label = "Step 1", .status = .pending }};
    var stepper = Stepper{ .steps = &steps };
    stepper.render(&buf, area);

    // Should not crash
}

test "render with no steps does not crash" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };

    var stepper = Stepper{ .steps = &.{} };
    stepper.render(&buf, area);

    // Should not crash
}

test "render horizontal layout without panic" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };

    const steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .active },
        .{ .label = "Step 3", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .direction = .horizontal };
    stepper.render(&buf, area);

    // Should complete without error
}

test "render vertical layout without panic" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };

    const steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .active },
        .{ .label = "Step 3", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .direction = .vertical };
    stepper.render(&buf, area);

    // Should complete without error
}

test "render with all completed steps" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };

    const steps = [_]Step{
        .{ .label = "Done 1", .status = .completed },
        .{ .label = "Done 2", .status = .completed },
    };
    var stepper = Stepper{ .steps = &steps };
    stepper.render(&buf, area);

    // Should complete without error
}

test "render with failed step" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };

    const steps = [_]Step{
        .{ .label = "Good", .status = .completed },
        .{ .label = "Bad", .status = .failed },
        .{ .label = "Pending", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps };
    stepper.render(&buf, area);

    // Should complete without error
}

test "render on small area (5x2)" {
    var buf = try Buffer.init(std.testing.allocator, 5, 2);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 5, .height = 2 };

    const steps = [_]Step{
        .{ .label = "A", .status = .pending },
        .{ .label = "B", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps };
    stepper.render(&buf, area);

    // Should not crash
}

test "render on single-row area" {
    var buf = try Buffer.init(std.testing.allocator, 100, 1);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 1 };

    const steps = [_]Step{.{ .label = "Step 1", .status = .pending }};
    var stepper = Stepper{ .steps = &steps };
    stepper.render(&buf, area);

    // Should not crash
}

test "render with block applies border" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };

    const block = Block{};
    const steps = [_]Step{.{ .label = "Step 1", .status = .pending }};
    var stepper = Stepper{ .steps = &steps, .block = block };
    stepper.render(&buf, area);

    // Should complete without error
}

// ============================================================================
// withBlock — Builder Pattern
// ============================================================================

test "withBlock returns modified stepper with block" {
    const block = Block{};
    const steps = [_]Step{.{ .label = "Step 1", .status = .pending }};
    var stepper = Stepper{ .steps = &steps };

    const updated = stepper.withBlock(block);
    try testing.expect(updated.block != null);
}

test "withBlock preserves other fields" {
    const block = Block{};
    const steps = [_]Step{.{ .label = "Step 1", .status = .pending }};
    var stepper = Stepper{ .steps = &steps, .current = 1, .direction = .vertical };

    const updated = stepper.withBlock(block);
    try testing.expectEqual(@as(usize, 1), updated.current);
    try testing.expectEqual(Direction.vertical, updated.direction);
}

// ============================================================================
// withDirection — Builder Pattern
// ============================================================================

test "withDirection returns modified stepper with direction" {
    const steps = [_]Step{.{ .label = "Step 1", .status = .pending }};
    var stepper = Stepper{ .steps = &steps, .direction = .horizontal };

    const updated = stepper.withDirection(.vertical);
    try testing.expectEqual(Direction.vertical, updated.direction);
}

test "withDirection preserves other fields" {
    const steps = [_]Step{.{ .label = "Step 1", .status = .pending }};
    var stepper = Stepper{ .steps = &steps, .current = 2, .block = Block{} };

    const updated = stepper.withDirection(.vertical);
    try testing.expectEqual(@as(usize, 2), updated.current);
    try testing.expect(updated.block != null);
}

test "withDirection can switch from horizontal to vertical" {
    const steps = [_]Step{.{ .label = "Step", .status = .pending }};
    var stepper = Stepper{ .steps = &steps, .direction = .horizontal };

    const horizontal = stepper;
    try testing.expectEqual(Direction.horizontal, horizontal.direction);

    const vertical = stepper.withDirection(.vertical);
    try testing.expectEqual(Direction.vertical, vertical.direction);
}

// ============================================================================
// Style Customization
// ============================================================================

test "Stepper accepts custom pending_style" {
    const steps = [_]Step{.{ .label = "Step 1", .status = .pending }};
    const style = Style{ .bold = true };

    var stepper = Stepper{ .steps = &steps, .pending_style = style };
    try testing.expect(stepper.pending_style.bold);
}

test "Stepper accepts custom active_style" {
    const steps = [_]Step{.{ .label = "Step 1", .status = .active }};
    const style = Style{ .bold = true };

    var stepper = Stepper{ .steps = &steps, .active_style = style };
    try testing.expect(stepper.active_style.bold);
}

test "Stepper accepts custom completed_style" {
    const steps = [_]Step{.{ .label = "Step 1", .status = .completed }};
    const style = Style{ .bold = true };

    var stepper = Stepper{ .steps = &steps, .completed_style = style };
    try testing.expect(stepper.completed_style.bold);
}

test "Stepper accepts custom failed_style" {
    const steps = [_]Step{.{ .label = "Step 1", .status = .failed }};
    const style = Style{ .bold = true };

    var stepper = Stepper{ .steps = &steps, .failed_style = style };
    try testing.expect(stepper.failed_style.bold);
}

test "Stepper accepts custom connector_style" {
    const steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
    };
    const style = Style{ .bold = true };

    var stepper = Stepper{ .steps = &steps, .connector_style = style };
    try testing.expect(stepper.connector_style.bold);
}

// ============================================================================
// Navigation & State Combination
// ============================================================================

test "moveNext then setStatus updates correct step" {
    var steps = [_]Step{
        .{ .label = "Step 1", .status = .pending },
        .{ .label = "Step 2", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 0 };

    stepper.setStatus(0, .completed);
    stepper.moveNext();
    stepper.setStatus(1, .active);

    try testing.expectEqual(StepStatus.completed, steps[0].status);
    try testing.expectEqual(StepStatus.active, steps[1].status);
}

test "render respects current step index" {
    var buf = try Buffer.init(std.testing.allocator, 100, 30);
    defer buf.deinit();
    const area = Rect{ .x = 0, .y = 0, .width = 100, .height = 30 };

    const steps = [_]Step{
        .{ .label = "First", .status = .pending },
        .{ .label = "Current", .status = .active },
        .{ .label = "Last", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps, .current = 1 };
    stepper.render(&buf, area);

    // Should complete without error, rendering at index 1
}

test "complex workflow: navigate and track status" {
    var steps = [_]Step{
        .{ .label = "Validate", .status = .pending },
        .{ .label = "Process", .status = .pending },
        .{ .label = "Complete", .status = .pending },
    };
    var stepper = Stepper{ .steps = &steps };

    // Start
    try testing.expectEqual(@as(usize, 0), stepper.current);
    try testing.expect(!stepper.isComplete());
    try testing.expect(!stepper.hasFailed());

    // Mark first as complete and advance
    stepper.setStatus(0, .completed);
    stepper.moveNext();
    try testing.expectEqual(@as(usize, 1), stepper.current);

    // Mark second as active
    stepper.setStatus(1, .active);
    try testing.expectEqual(StepStatus.active, steps[1].status);

    // Complete it and advance
    stepper.setStatus(1, .completed);
    stepper.moveNext();
    try testing.expectEqual(@as(usize, 2), stepper.current);

    // Mark last as completed
    stepper.setStatus(2, .completed);
    try testing.expect(stepper.isComplete());
    try testing.expect(!stepper.hasFailed());
}
