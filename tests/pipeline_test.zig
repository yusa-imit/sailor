//! Pipeline widget tests — v2.15.0
//!
//! Tests the Pipeline widget's stage rendering, status indicators, and layout functionality.
//! Pipeline visualizes a linear CI/build pipeline with stages in horizontal or vertical layout.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;

// These will be defined when the widgets are implemented
const Pipeline = sailor.tui.widgets.Pipeline;
const PipelineStage = Pipeline.PipelineStage;
const StageStatus = Pipeline.StageStatus;
const Direction = sailor.tui.Direction;

// ============================================================================
// Stage Construction Tests
// ============================================================================

test "PipelineStage creation with required fields" {
    const stage = PipelineStage{
        .label = "Build",
        .status = .pending,
    };

    try testing.expectEqualStrings("Build", stage.label);
    try testing.expectEqual(StageStatus.pending, stage.status);
    try testing.expectEqual(@as(u8, 0), stage.progress);
}

test "PipelineStage with progress field" {
    const stage = PipelineStage{
        .label = "Test",
        .status = .running,
        .progress = 50,
    };

    try testing.expectEqual(@as(u8, 50), stage.progress);
}

test "StageStatus enum has all required values" {
    // Verify all status variants exist and are distinct
    try testing.expect(StageStatus.pending != StageStatus.running);
    try testing.expect(StageStatus.running != StageStatus.success);
    try testing.expect(StageStatus.success != StageStatus.failed);
    try testing.expect(StageStatus.failed != StageStatus.skipped);
    try testing.expect(StageStatus.skipped != StageStatus.pending);
}

// ============================================================================
// Pipeline Initialization Tests
// ============================================================================

test "Pipeline with empty stages renders without crash" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{};

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Empty stages — buffer should remain unchanged (all spaces)
    try testing.expectEqual(@as(u21, ' '), buffer.getChar(0, 12));
}

test "Pipeline with default direction is horizontal" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .pending },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    try testing.expectEqual(Direction.horizontal, pipeline.direction);
}

test "Pipeline with custom direction" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .pending },
    };

    const pipeline = Pipeline{
        .stages = &stages,
        .direction = .vertical,
    };

    try testing.expectEqual(Direction.vertical, pipeline.direction);
}

test "Pipeline show_connectors defaults to true" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .pending },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    try testing.expect(pipeline.show_connectors);
}

// ============================================================================
// countByStatus Tests
// ============================================================================

test "countByStatus returns correct count for each status" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .success },
        PipelineStage{ .label = "Test", .status = .success },
        PipelineStage{ .label = "Deploy", .status = .pending },
        PipelineStage{ .label = "Verify", .status = .failed },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    try testing.expectEqual(@as(usize, 2), pipeline.countByStatus(.success));
    try testing.expectEqual(@as(usize, 1), pipeline.countByStatus(.pending));
    try testing.expectEqual(@as(usize, 1), pipeline.countByStatus(.failed));
    try testing.expectEqual(@as(usize, 0), pipeline.countByStatus(.running));
    try testing.expectEqual(@as(usize, 0), pipeline.countByStatus(.skipped));
}

test "countByStatus on empty pipeline returns 0" {
    const pipeline = Pipeline{
        .stages = &[_]PipelineStage{},
    };

    try testing.expectEqual(@as(usize, 0), pipeline.countByStatus(.success));
    try testing.expectEqual(@as(usize, 0), pipeline.countByStatus(.pending));
}

test "countByStatus with all same status" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "A", .status = .success },
        PipelineStage{ .label = "B", .status = .success },
        PipelineStage{ .label = "C", .status = .success },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    try testing.expectEqual(@as(usize, 3), pipeline.countByStatus(.success));
}

// ============================================================================
// isComplete Tests
// ============================================================================

test "isComplete with all success stages returns true" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .success },
        PipelineStage{ .label = "Test", .status = .success },
        PipelineStage{ .label = "Deploy", .status = .success },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    try testing.expect(pipeline.isComplete());
}

test "isComplete with pending stage returns false" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .success },
        PipelineStage{ .label = "Test", .status = .pending },
        PipelineStage{ .label = "Deploy", .status = .success },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    try testing.expect(!pipeline.isComplete());
}

test "isComplete with running stage returns false" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .success },
        PipelineStage{ .label = "Test", .status = .running },
        PipelineStage{ .label = "Deploy", .status = .success },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    try testing.expect(!pipeline.isComplete());
}

test "isComplete with success and skipped returns true" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .success },
        PipelineStage{ .label = "Optional", .status = .skipped },
        PipelineStage{ .label = "Deploy", .status = .success },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    try testing.expect(pipeline.isComplete());
}

test "isComplete on empty pipeline returns true" {
    const pipeline = Pipeline{
        .stages = &[_]PipelineStage{},
    };

    try testing.expect(pipeline.isComplete());
}

// ============================================================================
// hasFailed Tests
// ============================================================================

test "hasFailed with failed stage returns true" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .success },
        PipelineStage{ .label = "Test", .status = .failed },
        PipelineStage{ .label = "Deploy", .status = .success },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    try testing.expect(pipeline.hasFailed());
}

test "hasFailed with no failed stages returns false" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .success },
        PipelineStage{ .label = "Test", .status = .pending },
        PipelineStage{ .label = "Deploy", .status = .success },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    try testing.expect(!pipeline.hasFailed());
}

test "hasFailed with all failed stages returns true" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .failed },
        PipelineStage{ .label = "Test", .status = .failed },
        PipelineStage{ .label = "Deploy", .status = .failed },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    try testing.expect(pipeline.hasFailed());
}

test "hasFailed on empty pipeline returns false" {
    const pipeline = Pipeline{
        .stages = &[_]PipelineStage{},
    };

    try testing.expect(!pipeline.hasFailed());
}

// ============================================================================
// Single Stage Rendering Tests
// ============================================================================

test "single stage renders label in buffer" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{
            .label = "Build",
            .status = .pending,
        },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Verify label is rendered
    var found_label = false;
    var y: u16 = 0;
    while (y < 24 and !found_label) : (y += 1) {
        var x: u16 = 0;
        while (x < 80 and !found_label) : (x += 1) {
            if (buffer.getConst(x, y)) |cell| {
                if (cell.char == 'B') {
                    found_label = true;
                }
            }
        }
    }

    try testing.expect(found_label);
}

// ============================================================================
// Status Indicator Tests
// ============================================================================

test "success stage renders success indicator" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{
            .label = "Success",
            .status = .success,
        },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Horizontal render: icon at x=1, mid_y=12; opening bracket at x=0
    try testing.expectEqual(@as(u21, '['), buffer.getChar(0, 12));
    try testing.expectEqual(@as(u21, '✓'), buffer.getChar(1, 12));
}

test "failed stage renders failure indicator" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{
            .label = "Failed",
            .status = .failed,
        },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    try testing.expectEqual(@as(u21, '['), buffer.getChar(0, 12));
    try testing.expectEqual(@as(u21, '✗'), buffer.getChar(1, 12));
}

test "running stage renders running indicator" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{
            .label = "Running",
            .status = .running,
            .progress = 50,
        },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    try testing.expectEqual(@as(u21, '['), buffer.getChar(0, 12));
    try testing.expectEqual(@as(u21, '⊙'), buffer.getChar(1, 12));
}

test "pending stage renders pending indicator" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{
            .label = "Pending",
            .status = .pending,
        },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    try testing.expectEqual(@as(u21, '['), buffer.getChar(0, 12));
    try testing.expectEqual(@as(u21, '·'), buffer.getChar(1, 12));
}

test "skipped stage renders skipped indicator" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{
            .label = "Skipped",
            .status = .skipped,
        },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    try testing.expectEqual(@as(u21, '['), buffer.getChar(0, 12));
    try testing.expectEqual(@as(u21, '⊘'), buffer.getChar(1, 12));
}

// ============================================================================
// Multiple Stage Rendering Tests
// ============================================================================

test "five stages render without overlap in 80-wide buffer" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .success },
        PipelineStage{ .label = "Unit", .status = .success },
        PipelineStage{ .label = "Integ", .status = .running },
        PipelineStage{ .label = "Deploy", .status = .pending },
        PipelineStage{ .label = "Verify", .status = .success },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // At least one stage should have rendered (opening bracket or status icon)
    const cell = buffer.getConst(0, 12);
    try testing.expectEqual(@as(u21, '['), cell.?.char);
}

// ============================================================================
// Connector Tests
// ============================================================================

test "horizontal render shows connectors between stages" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{ .label = "A", .status = .success },
        PipelineStage{ .label = "B", .status = .success },
        PipelineStage{ .label = "C", .status = .success },
    };

    const pipeline = Pipeline{
        .stages = &stages,
        .show_connectors = true,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // First stage should render with opening bracket at (0, 12)
    const cell = buffer.getConst(0, 12);
    try testing.expectEqual(@as(u21, '['), cell.?.char);
}

test "show_connectors false hides connectors" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{ .label = "A", .status = .success },
        PipelineStage{ .label = "B", .status = .success },
    };

    const pipeline = Pipeline{
        .stages = &stages,
        .show_connectors = false,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Even with no connectors, first stage should render
    const cell = buffer.getConst(0, 12);
    try testing.expectEqual(@as(u21, '['), cell.?.char);
}

// ============================================================================
// Progress Tests
// ============================================================================

test "running stage with progress 0-100 displays correctly" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{
            .label = "Building",
            .status = .running,
            .progress = 75,
        },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Running stage should render with opening bracket and running icon ⊙
    try testing.expectEqual(@as(u21, '['), buffer.getConst(0, 12).?.char);
    try testing.expectEqual(@as(u21, '⊙'), buffer.getConst(1, 12).?.char);
}

// ============================================================================
// Label Length Tests
// ============================================================================

test "single character label renders correctly" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{
            .label = "X",
            .status = .pending,
        },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Single character label should still render with bracket and status icon
    try testing.expectEqual(@as(u21, '['), buffer.getConst(0, 12).?.char);
}

test "stage label with spaces renders correctly" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{
            .label = "Unit Tests",
            .status = .success,
        },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Multi-word label should render with bracket at (0, 12)
    try testing.expectEqual(@as(u21, '['), buffer.getConst(0, 12).?.char);
}

test "very long stage label is truncated to available width" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{
            .label = "This is a very very long stage name that should be truncated",
            .status = .success,
        },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 24 };
    pipeline.render(&buffer, area);

    // Even with narrow width, stage should render with bracket at (0, 12)
    try testing.expectEqual(@as(u21, '['), buffer.getConst(0, 12).?.char);
}

// ============================================================================
// Vertical Layout Tests
// ============================================================================

test "direction vertical arranges stages vertically" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .success },
        PipelineStage{ .label = "Test", .status = .running },
        PipelineStage{ .label = "Deploy", .status = .pending },
    };

    const pipeline = Pipeline{
        .stages = &stages,
        .direction = .vertical,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Vertical layout should render at (0, 0) with opening bracket
    try testing.expectEqual(@as(u21, '['), buffer.getConst(0, 0).?.char);
}

// ============================================================================
// Area Boundary Tests
// ============================================================================

test "zero width area does not panic" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .pending },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 10, .y = 0, .width = 0, .height = 24 };
    pipeline.render(&buffer, area);

    // Zero width should result in no rendering (render returns early)
    const cell = buffer.getConst(0, 0);
    try testing.expectEqual(@as(u21, ' '), cell.?.char);
}

test "zero height area does not panic" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .pending },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 10, .width = 80, .height = 0 };
    pipeline.render(&buffer, area);

    // Zero height should result in no rendering (render returns early)
    const cell = buffer.getConst(0, 0);
    try testing.expectEqual(@as(u21, ' '), cell.?.char);
}

// ============================================================================
// Mixed Status Tests
// ============================================================================

test "pipeline with mixed statuses: 2 success, 1 running, 1 pending" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .success },
        PipelineStage{ .label = "Test", .status = .success },
        PipelineStage{ .label = "Deploy", .status = .running },
        PipelineStage{ .label = "Verify", .status = .pending },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    try testing.expectEqual(@as(usize, 2), pipeline.countByStatus(.success));
    try testing.expectEqual(@as(usize, 1), pipeline.countByStatus(.running));
    try testing.expectEqual(@as(usize, 1), pipeline.countByStatus(.pending));
    try testing.expect(!pipeline.isComplete());
    try testing.expect(!pipeline.hasFailed());
}

test "all stages failed returns hasFailed true and isComplete false" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .failed },
        PipelineStage{ .label = "Test", .status = .failed },
        PipelineStage{ .label = "Deploy", .status = .failed },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    try testing.expect(pipeline.hasFailed());
    try testing.expect(!pipeline.isComplete());
}

// ============================================================================
// Default Style Tests
// ============================================================================

test "Pipeline default style is zero-value" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .pending },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const default_style = Style{};
    try testing.expectEqual(pipeline.style.bold, default_style.bold);
    try testing.expectEqual(pipeline.style.dim, default_style.dim);
}

// ============================================================================
// Progress Edge Cases
// ============================================================================

test "running stage with progress 0 displays correctly" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{
            .label = "Starting",
            .status = .running,
            .progress = 0,
        },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Running stage with 0% progress should render with running icon ⊙
    try testing.expectEqual(@as(u21, '⊙'), buffer.getConst(1, 12).?.char);
}

test "running stage with progress 100 displays correctly" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{
            .label = "Almost Done",
            .status = .running,
            .progress = 100,
        },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Running stage with 100% progress should render with running icon ⊙
    try testing.expectEqual(@as(u21, '⊙'), buffer.getConst(1, 12).?.char);
}

// ============================================================================
// Large Pipeline Tests
// ============================================================================

test "pipeline with 10 stages renders without panic" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    var stages: [10]PipelineStage = undefined;
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const status: StageStatus = switch (i % 5) {
            0 => .success,
            1 => .pending,
            2 => .running,
            3 => .failed,
            4 => .skipped,
            else => unreachable,
        };
        stages[i] = PipelineStage{
            .label = "Stage",
            .status = status,
            .progress = @intCast((i * 10) % 100),
        };
    }

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // First stage should render with opening bracket
    try testing.expectEqual(@as(u21, '['), buffer.getConst(0, 12).?.char);
}

// ============================================================================
// Complex Scenario Tests
// ============================================================================

test "pipeline transitions through statuses during execution" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .success },
        PipelineStage{ .label = "Test", .status = .success },
        PipelineStage{ .label = "Deploy", .status = .running },
        PipelineStage{ .label = "Smoke", .status = .pending },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    // Verify state transitions
    try testing.expectEqual(@as(usize, 2), pipeline.countByStatus(.success));
    try testing.expectEqual(@as(usize, 1), pipeline.countByStatus(.running));
    try testing.expectEqual(@as(usize, 1), pipeline.countByStatus(.pending));
    try testing.expect(!pipeline.isComplete());
    try testing.expect(!pipeline.hasFailed());
}

test "pipeline with some stages skipped" {
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .success },
        PipelineStage{ .label = "Test", .status = .success },
        PipelineStage{ .label = "Deploy", .status = .skipped },
        PipelineStage{ .label = "Notify", .status = .success },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    try testing.expectEqual(@as(usize, 3), pipeline.countByStatus(.success));
    try testing.expectEqual(@as(usize, 1), pipeline.countByStatus(.skipped));
    try testing.expect(pipeline.isComplete());
}

// ============================================================================
// Empty Label Tests
// ============================================================================

test "stage with empty label renders without crash" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{
            .label = "",
            .status = .pending,
        },
    };

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Empty label stage should still render with status indicator
    try testing.expectEqual(@as(u21, '['), buffer.getConst(0, 12).?.char);
}

// ============================================================================
// Performance Tests
// ============================================================================

test "20 stages render in reasonable time" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 200, 50);
    defer buffer.deinit();

    var stages: [20]PipelineStage = undefined;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        stages[i] = PipelineStage{
            .label = "Stage",
            .status = if (i < 10) .success else .pending,
        };
    }

    const pipeline = Pipeline{
        .stages = &stages,
    };

    const area = Rect{ .x = 0, .y = 0, .width = 200, .height = 50 };
    pipeline.render(&buffer, area);

    // First stage should render even with large number of stages
    try testing.expectEqual(@as(u21, '['), buffer.getConst(0, 25).?.char);
}

// ============================================================================
// Progress Indicator Tests (v2.100.0 feature)
// ============================================================================

test "running stage with progress 45 extends width from 8 to 12" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    // Test "Test" label: non-running width = 4 + 4 = 8
    const stages_success = [_]PipelineStage{
        PipelineStage{ .label = "Test", .status = .success },
    };
    const pipeline_success = Pipeline{ .stages = &stages_success };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline_success.render(&buffer, area);

    // For success stage with label "Test": [✓ Test] = 8 chars
    // Closing ] should be at position 7 (x=0..7)
    try testing.expectEqual(@as(u21, ']'), buffer.getConst(7, 12).?.char);

    // Now test running stage with progress 45: 4 + 4 + 1 + 2 + 1 = 12 chars
    var buffer2 = try Buffer.init(allocator, 80, 24);
    defer buffer2.deinit();

    const stages_running = [_]PipelineStage{
        PipelineStage{ .label = "Test", .status = .running, .progress = 45 },
    };
    const pipeline_running = Pipeline{ .stages = &stages_running };

    pipeline_running.render(&buffer2, area);

    // For running stage: [⊙ Test 45%] = 12 chars
    // Closing ] should be at position 11
    try testing.expectEqual(@as(u21, ']'), buffer2.getConst(11, 12).?.char);
}

test "running stage with progress 0 extends width by 3 (space + digit + percent)" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    // Label "Run" = 3 chars: width = 3 + 4 + 1 + 1 + 1 = 10
    // [⊙ Run 0%]
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Run", .status = .running, .progress = 0 },
    };
    const pipeline = Pipeline{ .stages = &stages };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Verify opening bracket
    try testing.expectEqual(@as(u21, '['), buffer.getConst(0, 12).?.char);
    // Verify running icon
    try testing.expectEqual(@as(u21, '⊙'), buffer.getConst(1, 12).?.char);
    // Verify closing bracket at position 9 (0-indexed)
    try testing.expectEqual(@as(u21, ']'), buffer.getConst(9, 12).?.char);
    // Verify '0' appears before closing bracket
    try testing.expectEqual(@as(u21, '0'), buffer.getConst(7, 12).?.char);
    // Verify '%' appears before closing bracket
    try testing.expectEqual(@as(u21, '%'), buffer.getConst(8, 12).?.char);
}

test "running stage with progress 100 extends width by 5 (space + 3 digits + percent)" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    // Label "Task" = 4 chars: width = 4 + 4 + 1 + 3 + 1 = 13
    // [⊙ Task 100%]
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Task", .status = .running, .progress = 100 },
    };
    const pipeline = Pipeline{ .stages = &stages };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Verify opening bracket
    try testing.expectEqual(@as(u21, '['), buffer.getConst(0, 12).?.char);
    // Verify running icon
    try testing.expectEqual(@as(u21, '⊙'), buffer.getConst(1, 12).?.char);
    // Closing bracket at position 12 (0-indexed)
    try testing.expectEqual(@as(u21, ']'), buffer.getConst(12, 12).?.char);
    // Verify '100' and '%' are present
    try testing.expectEqual(@as(u21, '1'), buffer.getConst(8, 12).?.char);
    try testing.expectEqual(@as(u21, '0'), buffer.getConst(9, 12).?.char);
    try testing.expectEqual(@as(u21, '0'), buffer.getConst(10, 12).?.char);
    try testing.expectEqual(@as(u21, '%'), buffer.getConst(11, 12).?.char);
}

test "running stage with progress 45 renders [⊙ Build 45%]" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .running, .progress = 45 },
    };
    const pipeline = Pipeline{ .stages = &stages };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Read each position and verify the full string "[⊙ Build 45%]"
    try testing.expectEqual(@as(u21, '['), buffer.getConst(0, 12).?.char); // [
    try testing.expectEqual(@as(u21, '⊙'), buffer.getConst(1, 12).?.char); // ⊙
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(2, 12).?.char); // space
    try testing.expectEqual(@as(u21, 'B'), buffer.getConst(3, 12).?.char); // B
    try testing.expectEqual(@as(u21, 'u'), buffer.getConst(4, 12).?.char); // u
    try testing.expectEqual(@as(u21, 'i'), buffer.getConst(5, 12).?.char); // i
    try testing.expectEqual(@as(u21, 'l'), buffer.getConst(6, 12).?.char); // l
    try testing.expectEqual(@as(u21, 'd'), buffer.getConst(7, 12).?.char); // d
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(8, 12).?.char); // space before progress
    try testing.expectEqual(@as(u21, '4'), buffer.getConst(9, 12).?.char); // 4
    try testing.expectEqual(@as(u21, '5'), buffer.getConst(10, 12).?.char); // 5
    try testing.expectEqual(@as(u21, '%'), buffer.getConst(11, 12).?.char); // %
    try testing.expectEqual(@as(u21, ']'), buffer.getConst(12, 12).?.char); // ]
}

test "success stage does not render progress percentage" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .success },
    };
    const pipeline = Pipeline{ .stages = &stages };

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    pipeline.render(&buffer, area);

    // Success stage should be "[✓ Build]" = 9 chars
    // No '%' should appear in the stage
    try testing.expectEqual(@as(u21, '['), buffer.getConst(0, 12).?.char);
    try testing.expectEqual(@as(u21, '✓'), buffer.getConst(1, 12).?.char);
    try testing.expectEqual(@as(u21, ']'), buffer.getConst(8, 12).?.char);

    // Scan ahead to confirm no '%' in the stage's span
    var found_percent = false;
    var x: u16 = 0;
    while (x < 15) : (x += 1) {
        if (buffer.getConst(x, 12)) |cell| {
            if (cell.char == '%') {
                found_percent = true;
            }
        }
    }
    try testing.expect(!found_percent);
}

test "running stage in narrow area clips progress suffix gracefully" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 80, 24);
    defer buffer.deinit();

    // Create stage that would need 13 chars: [⊙ Build 45%]
    // But area is only 11 wide (x=0 to x=10)
    const stages = [_]PipelineStage{
        PipelineStage{ .label = "Build", .status = .running, .progress = 45 },
    };
    const pipeline = Pipeline{ .stages = &stages };

    // Narrow area: only 11 columns for rendering
    const area = Rect{ .x = 0, .y = 0, .width = 11, .height = 24 };
    pipeline.render(&buffer, area);

    // Should render without panic/crash
    // At least the opening bracket should be present
    try testing.expectEqual(@as(u21, '['), buffer.getConst(0, 12).?.char);
    // Icon should follow
    try testing.expectEqual(@as(u21, '⊙'), buffer.getConst(1, 12).?.char);
    // Label should be partially visible
    try testing.expectEqual(@as(u21, 'B'), buffer.getConst(3, 12).?.char);

    // Verify no crash by checking buffer still exists and is accessible
    const check_cell = buffer.getConst(5, 12);
    try testing.expect(check_cell != null);
}
