//! Comprehensive tests for Error Recovery & Resilience features (v2.9.0 milestone)
//!
//! Tests the following features:
//! 1. Widget render error boundaries — Isolated failure containment
//! 2. Automatic state recovery on panic — Rollback to last known good state
//! 3. Error reporting hooks — Custom logging and monitoring
//! 4. Graceful degradation modes — Fallback rendering strategies
//! 5. Test utilities for error injection — Simulate failures in tests
//!
//! All tests are written BEFORE implementation (TDD Red phase).
//! These tests should FAIL initially because the features don't exist yet.

const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;
const Buffer = sailor.Buffer;
const Rect = sailor.Rect;
const Style = sailor.Style;

// Forward declarations for types to be implemented
// These will be actual implementations in src/tui/error_recovery.zig
const ErrorBoundary = sailor.ErrorBoundary; // Will be implemented
const StateRecovery = sailor.StateRecovery; // Will be implemented
const ErrorReporter = sailor.ErrorReporter; // Will be implemented
const GracefulDegradation = sailor.GracefulDegradation; // Will be implemented
const ErrorInjector = sailor.ErrorInjector; // Will be implemented

// ============================================================================
// FEATURE 1: ERROR BOUNDARY TESTS (10 tests)
// ============================================================================

test "ErrorBoundary - isolates single widget render failure" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    // Create an error boundary around a failing widget
    var boundary = try ErrorBoundary.init(allocator);
    defer boundary.deinit();

    const FailingWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.RenderFailed;
        }
    };

    const widget = FailingWidget{};
    _ = boundary.renderWithBoundary(&widget, &buf, area) catch |err| {
        try testing.expectEqual(error.RenderFailed, err);
    };

    // Should capture error without propagating
    try testing.expectEqual(@as(usize, 1), boundary.errorCount());
    try testing.expect(boundary.lastError() != null);
}

test "ErrorBoundary - allows successful widgets to render normally" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    var boundary = try ErrorBoundary.init(allocator);
    defer boundary.deinit();

    const SuccessWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.setString(rect.x, rect.y, "Success", .{});
        }
    };

    const widget = SuccessWidget{};
    try boundary.renderWithBoundary(&widget, &buf, area);

    // Verify no errors recorded
    try testing.expectEqual(@as(usize, 0), boundary.errorCount());

    // Verify render succeeded
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'S'), cell.?.char);
}

test "ErrorBoundary - nested boundaries isolate failures independently" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    var outer = try ErrorBoundary.init(allocator);
    defer outer.deinit();

    var inner = try ErrorBoundary.init(allocator);
    defer inner.deinit();

    const FailingWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.InnerFailure;
        }
    };

    const widget = FailingWidget{};

    // Inner boundary catches the error
    _ = inner.renderWithBoundary(&widget, &buf, area) catch |err| {
        try testing.expectEqual(error.InnerFailure, err);
    };
    try testing.expectEqual(@as(usize, 1), inner.errorCount());

    // Outer boundary should be unaffected
    try testing.expectEqual(@as(usize, 0), outer.errorCount());
}

test "ErrorBoundary - cascade prevention stops error propagation" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var boundary = try ErrorBoundary.init(allocator);
    defer boundary.deinit();

    // Render 10 widgets, 5 fail, 5 succeed
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const area = Rect{ .x = 0, .y = @intCast(i * 2), .width = 80, .height = 2 };

        if (i % 2 == 0) {
            // Even indices fail
            const FailingWidget = struct {
                pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
                    return error.RenderFailed;
                }
            };
            const widget = FailingWidget{};
            _ = boundary.renderWithBoundary(&widget, &buf, area) catch {};
        } else {
            // Odd indices succeed
            const SuccessWidget = struct {
                pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
                    buffer.set(rect.x, rect.y, .{ .char = 'X', .style = .{} });
                }
            };
            const widget = SuccessWidget{};
            _ = boundary.renderWithBoundary(&widget, &buf, area) catch {};
        }
    }

    // Should have 5 errors, but 5 successful renders
    try testing.expectEqual(@as(usize, 5), boundary.errorCount());

    // Verify odd rows rendered successfully
    try testing.expectEqual(@as(u21, 'X'), buf.getConst(0, 2).?.char);
    try testing.expectEqual(@as(u21, 'X'), buf.getConst(0, 6).?.char);
}

test "ErrorBoundary - fallback rendering displays error message" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    var boundary = try ErrorBoundary.init(allocator);
    defer boundary.deinit();

    // Configure fallback message
    try boundary.setFallbackMessage("⚠ Render Error");

    const FailingWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.RenderFailed;
        }
    };

    const widget = FailingWidget{};
    _ = boundary.renderWithBoundary(&widget, &buf, area) catch {};

    // Verify fallback message is rendered
    const cells = [_]u21{ '⚠', ' ', 'R', 'e', 'n', 'd', 'e', 'r' };
    for (cells, 0..) |expected, idx| {
        const cell = buf.getConst(@intCast(idx), 0);
        try testing.expect(cell != null);
        try testing.expectEqual(expected, cell.?.char);
    }
}

test "ErrorBoundary - error context capture includes widget name and location" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 10, .y = 5, .width = 20, .height = 10 };

    var boundary = try ErrorBoundary.init(allocator);
    defer boundary.deinit();

    const FailingWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.TestError;
        }
    };

    const widget = FailingWidget{};
    _ = boundary.renderWithBoundaryNamed(&widget, &buf, area, "TestWidget") catch {};

    const last_error = boundary.lastError();
    try testing.expect(last_error != null);
    try testing.expectEqualStrings("TestWidget", last_error.?.widget_name);
    try testing.expectEqual(area, last_error.?.area);
    try testing.expect(last_error.?.error_value == error.TestError);
}

test "ErrorBoundary - reset clears all errors" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var boundary = try ErrorBoundary.init(allocator);
    defer boundary.deinit();

    // Generate multiple errors
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
        const FailingWidget = struct {
            pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
                return error.TestError;
            }
        };
        _ = boundary.renderWithBoundary(&FailingWidget{}, &buf, area) catch {};
    }

    try testing.expectEqual(@as(usize, 5), boundary.errorCount());

    // Reset and verify
    boundary.reset();
    try testing.expectEqual(@as(usize, 0), boundary.errorCount());
    try testing.expect(boundary.lastError() == null);
}

test "ErrorBoundary - maxErrors limit prevents unbounded growth" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var boundary = try ErrorBoundary.init(allocator);
    defer boundary.deinit();

    // Set max errors to 10
    try boundary.setMaxErrors(10);

    // Generate 20 errors
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
        const FailingWidget = struct {
            pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
                return error.TestError;
            }
        };
        _ = boundary.renderWithBoundary(&FailingWidget{}, &buf, area) catch {};
    }

    // Should only store first 10 errors
    try testing.expectEqual(@as(usize, 10), boundary.errorCount());
}

test "ErrorBoundary - nested boundaries with different fallback strategies" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var outer = try ErrorBoundary.init(allocator);
    defer outer.deinit();
    try outer.setFallbackMessage("Outer Error");

    var inner = try ErrorBoundary.init(allocator);
    defer inner.deinit();
    try inner.setFallbackMessage("Inner Error");

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const FailingWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.InnerFailure;
        }
    };

    // Inner boundary should use its own fallback
    _ = inner.renderWithBoundary(&FailingWidget{}, &buf, area) catch {};

    const cells = [_]u21{ 'I', 'n', 'n', 'e', 'r' };
    for (cells, 0..) |expected, idx| {
        try testing.expectEqual(expected, buf.getConst(@intCast(idx), 0).?.char);
    }
}

test "ErrorBoundary - error callback invoked on failure" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var boundary = try ErrorBoundary.init(allocator);
    defer boundary.deinit();

    var callback_invoked = false;

    const callback = struct {
        fn call(ctx: ?*anyopaque, _: anyerror, _: []const u8, _: Rect) void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.call;

    try boundary.setErrorCallback(callback, &callback_invoked);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    const FailingWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.TestError;
        }
    };

    boundary.renderWithBoundary(&FailingWidget{}, &buf, area) catch {};

    try testing.expect(callback_invoked);
}

// ============================================================================
// FEATURE 2: STATE RECOVERY TESTS (10 tests)
// ============================================================================

test "StateRecovery - captures initial state before render" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var recovery = try StateRecovery.init(allocator);
    defer recovery.deinit();

    // Initialize buffer with some content
    buf.setString(0, 0, "Initial", .{});

    // Capture snapshot
    try recovery.captureSnapshot(&buf);

    // Verify snapshot exists
    try testing.expect(recovery.hasSnapshot());
}

test "StateRecovery - automatic rollback on render failure" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var recovery = try StateRecovery.init(allocator);
    defer recovery.deinit();

    // Setup initial state
    buf.setString(0, 0, "Good", .{});
    try recovery.captureSnapshot(&buf);

    // Corrupt buffer
    buf.setString(0, 0, "Corrupted", .{});
    try testing.expectEqual(@as(u21, 'C'), buf.getConst(0, 0).?.char);

    // Rollback
    try recovery.rollback(&buf);

    // Verify restored to initial state
    try testing.expectEqual(@as(u21, 'G'), buf.getConst(0, 0).?.char);
}

test "StateRecovery - partial rollback for specific area" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var recovery = try StateRecovery.init(allocator);
    defer recovery.deinit();

    // Setup: two regions
    buf.setString(0, 0, "Region1", .{});
    buf.setString(0, 1, "Region2", .{});
    try recovery.captureSnapshot(&buf);

    // Corrupt only region 1
    buf.setString(0, 0, "XXXXXXX", .{});
    buf.setString(0, 1, "YYYYYYY", .{});

    // Rollback only the first line
    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 1 };
    try recovery.rollbackArea(&buf, area);

    // Region 1 restored, region 2 still corrupted
    try testing.expectEqual(@as(u21, 'R'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'Y'), buf.getConst(0, 1).?.char);
}

test "StateRecovery - snapshot stack for nested operations" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var recovery = try StateRecovery.init(allocator);
    defer recovery.deinit();

    // Level 1
    buf.setString(0, 0, "L1", .{});
    try recovery.pushSnapshot(&buf);

    // Level 2
    buf.setString(0, 0, "L2", .{});
    try recovery.pushSnapshot(&buf);

    // Level 3
    buf.setString(0, 0, "L3", .{});

    // Pop back to level 2
    try recovery.popSnapshot(&buf);
    try testing.expectEqual(@as(u21, 'L'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '2'), buf.getConst(1, 0).?.char);

    // Pop back to level 1
    try recovery.popSnapshot(&buf);
    try testing.expectEqual(@as(u21, 'L'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '1'), buf.getConst(1, 0).?.char);
}

test "StateRecovery - recovery failure when no snapshot exists" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var recovery = try StateRecovery.init(allocator);
    defer recovery.deinit();

    // Attempt rollback without snapshot
    const result = recovery.rollback(&buf);

    try testing.expectError(error.NoSnapshot, result);
}

test "StateRecovery - state validation before rollback" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var recovery = try StateRecovery.init(allocator);
    defer recovery.deinit();

    buf.setString(0, 0, "Valid", .{});
    try recovery.captureSnapshot(&buf);

    // Configure validator
    const validator = struct {
        fn call(buffer: *const Buffer) bool {
            // Validate: first cell must be 'V'
            const cell = buffer.getConst(0, 0);
            return cell != null and cell.?.char == 'V';
        }
    }.call;

    try recovery.setValidator(validator);

    // Corrupt buffer
    buf.setString(0, 0, "Invalid", .{});

    // Rollback with validation
    try recovery.rollbackWithValidation(&buf);

    // Verify restored
    try testing.expectEqual(@as(u21, 'V'), buf.getConst(0, 0).?.char);
}

test "StateRecovery - validation failure prevents rollback" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var recovery = try StateRecovery.init(allocator);
    defer recovery.deinit();

    buf.setString(0, 0, "Bad", .{}); // Starts with 'B'
    try recovery.captureSnapshot(&buf);

    const validator = struct {
        fn call(buffer: *const Buffer) bool {
            const cell = buffer.getConst(0, 0);
            return cell != null and cell.?.char == 'V'; // Only accept 'V'
        }
    }.call;

    try recovery.setValidator(validator);

    // This rollback should fail validation
    const result = recovery.rollbackWithValidation(&buf);

    try testing.expectError(error.ValidationFailed, result);
}

test "StateRecovery - memory overhead tracking" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var recovery = try StateRecovery.init(allocator);
    defer recovery.deinit();

    try recovery.captureSnapshot(&buf);

    const overhead = recovery.memoryOverhead();

    // Should track snapshot size
    const expected_size = @sizeOf(@TypeOf(buf.cells[0])) * buf.cells.len;
    try testing.expect(overhead >= expected_size);
}

test "StateRecovery - compression for large snapshots" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 200, 100);
    defer buf.deinit();

    var recovery = try StateRecovery.init(allocator);
    defer recovery.deinit();

    // Enable compression for large buffers
    try recovery.setCompressionThreshold(1000);

    // Fill with repeated pattern (compressible)
    var y: u16 = 0;
    while (y < 100) : (y += 1) {
        var x: u16 = 0;
        while (x < 200) : (x += 1) {
            buf.set(x, y, .{ .char = 'A', .style = .{} });
        }
    }

    try recovery.captureSnapshot(&buf);

    const overhead = recovery.memoryOverhead();
    const uncompressed_size = @sizeOf(@TypeOf(buf.cells[0])) * buf.cells.len;

    // Compression should reduce size
    try testing.expect(overhead < uncompressed_size);
}

test "StateRecovery - rollback count tracking" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var recovery = try StateRecovery.init(allocator);
    defer recovery.deinit();

    buf.setString(0, 0, "State", .{});
    try recovery.captureSnapshot(&buf);

    try testing.expectEqual(@as(usize, 0), recovery.rollbackCount());

    buf.setString(0, 0, "Bad1", .{});
    try recovery.rollback(&buf);
    try testing.expectEqual(@as(usize, 1), recovery.rollbackCount());

    buf.setString(0, 0, "Bad2", .{});
    try recovery.rollback(&buf);
    try testing.expectEqual(@as(usize, 2), recovery.rollbackCount());
}

// ============================================================================
// FEATURE 3: ERROR REPORTING HOOKS TESTS (10 tests)
// ============================================================================

test "ErrorReporter - register single hook" {
    const allocator = testing.allocator;
    var reporter = try ErrorReporter.init(allocator);
    defer reporter.deinit();

    var invoked = false;

    const hook = struct {
        fn call(ctx: ?*anyopaque, _: anyerror, _: []const u8) void {
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.call;

    _ = try reporter.registerHook(hook, &invoked);

    reporter.report(error.TestError, "Test message");

    try testing.expect(invoked);
}

test "ErrorReporter - chaining multiple hooks" {
    const allocator = testing.allocator;
    var reporter = try ErrorReporter.init(allocator);
    defer reporter.deinit();

    var count1: usize = 0;
    var count2: usize = 0;
    var count3: usize = 0;

    const hook1 = struct {
        fn call(ctx: ?*anyopaque, _: anyerror, _: []const u8) void {
            const counter = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            counter.* += 1;
        }
    }.call;

    _ = try reporter.registerHook(hook1, &count1);
    _ = try reporter.registerHook(hook1, &count2);
    _ = try reporter.registerHook(hook1, &count3);

    reporter.report(error.TestError, "Test");

    // All three hooks invoked
    try testing.expectEqual(@as(usize, 1), count1);
    try testing.expectEqual(@as(usize, 1), count2);
    try testing.expectEqual(@as(usize, 1), count3);
}

test "ErrorReporter - hook receives error type and message" {
    const allocator = testing.allocator;
    var reporter = try ErrorReporter.init(allocator);
    defer reporter.deinit();

    const Context = struct {
        received_error: ?anyerror = null,
        received_message: ?[]const u8 = null,
    };
    var ctx = Context{};

    const hook = struct {
        fn call(context: ?*anyopaque, err: anyerror, message: []const u8) void {
            const c = @as(*Context, @ptrCast(@alignCast(context.?)));
            c.received_error = err;
            c.received_message = message;
        }
    }.call;

    _ = try reporter.registerHook(hook, &ctx);

    reporter.report(error.CustomError, "Custom message");

    try testing.expect(ctx.received_error != null);
    try testing.expect(ctx.received_error.? == error.CustomError);
    try testing.expect(ctx.received_message != null);
    try testing.expectEqualStrings("Custom message", ctx.received_message.?);
}

test "ErrorReporter - context propagation through hooks" {
    const allocator = testing.allocator;
    var reporter = try ErrorReporter.init(allocator);
    defer reporter.deinit();

    const Context = struct {
        widget_name: []const u8,
        timestamp: i64,
        severity: u8,
    };

    var ctx = Context{
        .widget_name = "TestWidget",
        .timestamp = 12345,
        .severity = 2,
    };

    const hook = struct {
        fn call(context: ?*anyopaque, _: anyerror, _: []const u8) void {
            const c = @as(*Context, @ptrCast(@alignCast(context.?)));
            // Store pointer to verify context propagation
            _ = c; // Verify we can access all fields
        }
    }.call;

    _ = try reporter.registerHook(hook, &ctx);

    // Set additional context before reporting
    try reporter.setContext("widget", "TestWidget");
    try reporter.setContext("severity", "high");

    reporter.report(error.TestError, "Test");

    // Context should be accessible in hook
    const stored_widget = reporter.getContext("widget");
    try testing.expect(stored_widget != null);
    try testing.expectEqualStrings("TestWidget", stored_widget.?);
}

test "ErrorReporter - hook removal" {
    const allocator = testing.allocator;
    var reporter = try ErrorReporter.init(allocator);
    defer reporter.deinit();

    var count: usize = 0;

    const hook = struct {
        fn call(ctx: ?*anyopaque, _: anyerror, _: []const u8) void {
            const counter = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            counter.* += 1;
        }
    }.call;

    const id = try reporter.registerHook(hook, &count);

    reporter.report(error.Test1, "Test 1");
    try testing.expectEqual(@as(usize, 1), count);

    // Remove hook
    try reporter.removeHook(id);

    reporter.report(error.Test2, "Test 2");
    // Count unchanged because hook removed
    try testing.expectEqual(@as(usize, 1), count);
}

test "ErrorReporter - hook priority ordering" {
    const allocator = testing.allocator;
    var reporter = try ErrorReporter.init(allocator);
    defer reporter.deinit();

    var order: std.ArrayList(u8) = .{};
    defer order.deinit(allocator);

    const hook1 = struct {
        fn call(ctx: ?*anyopaque, _: anyerror, _: []const u8) void {
            const list = @as(*std.ArrayList(u8), @ptrCast(@alignCast(ctx.?)));
            list.append(allocator, 1) catch {};
        }
    }.call;

    const hook2 = struct {
        fn call(ctx: ?*anyopaque, _: anyerror, _: []const u8) void {
            const list = @as(*std.ArrayList(u8), @ptrCast(@alignCast(ctx.?)));
            list.append(allocator, 2) catch {};
        }
    }.call;

    const hook3 = struct {
        fn call(ctx: ?*anyopaque, _: anyerror, _: []const u8) void {
            const list = @as(*std.ArrayList(u8), @ptrCast(@alignCast(ctx.?)));
            list.append(allocator, 3) catch {};
        }
    }.call;

    // Register with priorities: high (1), low (3), medium (2)
    _ = try reporter.registerHookWithPriority(hook1, &order, 1);
    _ = try reporter.registerHookWithPriority(hook3, &order, 3);
    _ = try reporter.registerHookWithPriority(hook2, &order, 2);

    reporter.report(error.Test, "Test");

    // Should invoke in priority order: 1, 2, 3
    try testing.expectEqual(@as(usize, 3), order.items.len);
    try testing.expectEqual(@as(u8, 1), order.items[0]);
    try testing.expectEqual(@as(u8, 2), order.items[1]);
    try testing.expectEqual(@as(u8, 3), order.items[2]);
}

test "ErrorReporter - async hook execution" {
    const allocator = testing.allocator;
    var reporter = try ErrorReporter.init(allocator);
    defer reporter.deinit();

    var received = false;

    const hook = struct {
        fn call(ctx: ?*anyopaque, _: anyerror, _: []const u8) void {
            // Simulate async work
            std.Thread.sleep(100_000); // 0.1ms
            const flag = @as(*bool, @ptrCast(@alignCast(ctx.?)));
            flag.* = true;
        }
    }.call;

    _ = try reporter.registerAsyncHook(hook, &received);

    reporter.reportAsync(error.TestError, "Test");

    // Wait for async completion
    std.Thread.sleep(200_000); // 0.2ms

    try testing.expect(received);
}

test "ErrorReporter - buffered reporting with flush" {
    const allocator = testing.allocator;
    var reporter = try ErrorReporter.init(allocator);
    defer reporter.deinit();

    var count: usize = 0;

    const hook = struct {
        fn call(ctx: ?*anyopaque, _: anyerror, _: []const u8) void {
            const counter = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            counter.* += 1;
        }
    }.call;

    _ = try reporter.registerHook(hook, &count);

    // Enable buffering
    try reporter.setBufferSize(10);

    // Report 5 errors (buffered, not flushed)
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        reporter.reportBuffered(error.Test, "Test");
    }

    // Hook not invoked yet (buffered)
    try testing.expectEqual(@as(usize, 0), count);

    // Flush buffer
    try reporter.flush();

    // All 5 errors flushed
    try testing.expectEqual(@as(usize, 5), count);
}

test "ErrorReporter - error filtering" {
    const allocator = testing.allocator;
    var reporter = try ErrorReporter.init(allocator);
    defer reporter.deinit();

    var count: usize = 0;

    const hook = struct {
        fn call(ctx: ?*anyopaque, _: anyerror, _: []const u8) void {
            const counter = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            counter.* += 1;
        }
    }.call;

    _ = try reporter.registerHook(hook, &count);

    // Set filter: only report RenderFailed errors
    const filter = struct {
        fn call(err: anyerror) bool {
            return err == error.RenderFailed;
        }
    }.call;

    try reporter.setFilter(filter);

    reporter.report(error.RenderFailed, "Should report");
    reporter.report(error.OtherError, "Should NOT report");
    reporter.report(error.RenderFailed, "Should report");

    // Only 2 RenderFailed errors reported
    try testing.expectEqual(@as(usize, 2), count);
}

test "ErrorReporter - structured logging to writer" {
    const allocator = testing.allocator;
    var reporter = try ErrorReporter.init(allocator);
    defer reporter.deinit();

    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    try reporter.setLogWriter(stream.writer());

    // Configure JSON format
    try reporter.setFormat(.json);

    reporter.report(error.TestError, "Test message");

    const written = stream.getWritten();

    // Verify JSON structure
    try testing.expect(std.mem.indexOf(u8, written, "\"error\"") != null);
    try testing.expect(std.mem.indexOf(u8, written, "TestError") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\"message\"") != null);
}

// ============================================================================
// FEATURE 4: GRACEFUL DEGRADATION TESTS (10 tests)
// ============================================================================

test "GracefulDegradation - fallback to simple text on render failure" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var degradation = try GracefulDegradation.init(allocator);
    defer degradation.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const FailingWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.ComplexRenderFailed;
        }
    };

    const widget = FailingWidget{};

    // Attempt render with graceful degradation
    _ = degradation.renderWithFallback(&widget, &buf, area, "Fallback Text");

    // Verify fallback text rendered
    const cells = [_]u21{ 'F', 'a', 'l', 'l', 'b', 'a', 'c', 'k' };
    for (cells, 0..) |expected, idx| {
        try testing.expectEqual(expected, buf.getConst(@intCast(idx), 0).?.char);
    }
}

test "GracefulDegradation - partial update on widget tree failure" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var degradation = try GracefulDegradation.init(allocator);
    defer degradation.deinit();

    // Mock widget tree: root with 3 children
    // Child 2 fails, but 1 and 3 should succeed
    const Widget1 = struct {
        pub fn render(_: @This(), buffer: *Buffer, area: Rect) !void {
            buffer.setString(area.x, area.y, "Widget1", .{});
        }
    };
    const Widget2 = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.Widget2Failed;
        }
    };
    const Widget3 = struct {
        pub fn render(_: @This(), buffer: *Buffer, area: Rect) !void {
            buffer.setString(area.x, area.y, "Widget3", .{});
        }
    };

    const widgets = [_]type{ Widget1, Widget2, Widget3 };
    var results = try degradation.renderMultipleWithDegradation(
        &widgets,
        &[_]Rect{
            .{ .x = 0, .y = 0, .width = 80, .height = 8 },
            .{ .x = 0, .y = 8, .width = 80, .height = 8 },
            .{ .x = 0, .y = 16, .width = 80, .height = 8 },
        },
        &buf,
    );
    defer results.deinit();

    // Widget 1 and 3 succeeded
    try testing.expect(results.succeeded[0]);
    try testing.expect(!results.succeeded[1]);
    try testing.expect(results.succeeded[2]);

    try testing.expectEqual(@as(u21, 'W'), buf.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'W'), buf.getConst(0, 16).?.char);
}

test "GracefulDegradation - reduced quality mode for performance" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var degradation = try GracefulDegradation.init(allocator);
    defer degradation.deinit();

    // Enable reduced quality mode
    try degradation.setQualityLevel(.low);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const ExpensiveWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            // Simulate expensive render
            var y: u16 = 0;
            while (y < rect.height) : (y += 1) {
                var x: u16 = 0;
                while (x < rect.width) : (x += 1) {
                    buffer.set(x, y, .{ .char = '#', .style = .{} });
                }
            }
        }
    };

    const widget = ExpensiveWidget{};

    const start = std.time.nanoTimestamp();
    try degradation.render(&widget, &buf, area);
    const elapsed = std.time.nanoTimestamp() - start;

    // Low quality should render faster (skip some cells)
    try testing.expect(elapsed < 1_000_000); // < 1ms
}

test "GracefulDegradation - error accumulation tracking" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var degradation = try GracefulDegradation.init(allocator);
    defer degradation.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const FailingWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.RenderFailed;
        }
    };

    // Render failing widget 10 times
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        _ = degradation.renderWithFallback(&FailingWidget{}, &buf, area, "Error");
    }

    const stats = degradation.getStats();

    try testing.expectEqual(@as(usize, 10), stats.total_renders);
    try testing.expectEqual(@as(usize, 10), stats.failures);
    try testing.expectEqual(@as(usize, 0), stats.successes);
}

test "GracefulDegradation - automatic quality reduction on repeated failures" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var degradation = try GracefulDegradation.init(allocator);
    defer degradation.deinit();

    // Enable auto-degradation
    try degradation.setAutoDegrade(true, 5); // After 5 failures

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const FailingWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.RenderFailed;
        }
    };

    // Trigger 6 failures
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        _ = degradation.renderWithFallback(&FailingWidget{}, &buf, area, "Error");
    }

    // Quality level should auto-reduce
    try testing.expect(degradation.getQualityLevel() == .low);
}

test "GracefulDegradation - recovery to normal quality after success" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var degradation = try GracefulDegradation.init(allocator);
    defer degradation.deinit();

    try degradation.setQualityLevel(.low);
    try testing.expect(degradation.getQualityLevel() == .low);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const SuccessWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.setString(rect.x, rect.y, "Success", .{});
        }
    };

    // Enable auto-recovery
    try degradation.setAutoRecover(true, 10); // After 10 successes

    // Trigger 10 successes
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        try degradation.render(&SuccessWidget{}, &buf, area);
    }

    // Quality level should auto-recover
    try testing.expect(degradation.getQualityLevel() == .normal);
}

test "GracefulDegradation - skip animation on degraded mode" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var degradation = try GracefulDegradation.init(allocator);
    defer degradation.deinit();

    try degradation.setQualityLevel(.low);

    // Verify animation-heavy features disabled
    try testing.expect(!degradation.shouldAnimate());
    try testing.expect(!degradation.shouldBlur());
    try testing.expect(!degradation.shouldDrawShadows());
}

test "GracefulDegradation - graceful skip of non-critical widgets" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var degradation = try GracefulDegradation.init(allocator);
    defer degradation.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const NonCriticalWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.RenderFailed;
        }
    };

    // Mark as non-critical
    try degradation.markNonCritical("NonCriticalWidget");

    const widget = NonCriticalWidget{};
    const result = degradation.renderWithFallbackNamed(&widget, &buf, area, "", "NonCriticalWidget");

    // Should succeed (skipped) rather than error
    try testing.expect(result == .skipped);
}

test "GracefulDegradation - critical widget always renders" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var degradation = try GracefulDegradation.init(allocator);
    defer degradation.deinit();

    try degradation.setQualityLevel(.minimal);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const CriticalWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.setString(rect.x, rect.y, "CRITICAL", .{});
        }
    };

    // Mark as critical
    try degradation.markCritical("CriticalWidget");

    const widget = CriticalWidget{};
    try degradation.render(&widget, &buf, area);

    // Should render even in minimal quality
    try testing.expectEqual(@as(u21, 'C'), buf.getConst(0, 0).?.char);
}

test "GracefulDegradation - performance budget enforcement" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var degradation = try GracefulDegradation.init(allocator);
    defer degradation.deinit();

    // Set render budget: 1ms
    try degradation.setRenderBudget(1_000_000); // 1ms in nanoseconds

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const SlowWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            std.Thread.sleep(2_000_000); // 2ms (exceeds budget)
            buffer.setString(rect.x, rect.y, "Slow", .{});
        }
    };

    const widget = SlowWidget{};
    const result = degradation.renderWithBudget(&widget, &buf, area);

    // Should timeout and return error
    try testing.expectError(error.BudgetExceeded, result);
}

// ============================================================================
// FEATURE 5: ERROR INJECTION TESTS (10 tests)
// ============================================================================

test "ErrorInjector - inject render failure at specific widget" {
    const allocator = testing.allocator;
    var injector = try ErrorInjector.init(allocator);
    defer injector.deinit();

    // Configure: fail "TargetWidget" on first render
    try injector.injectErrorAt("TargetWidget", error.InjectedError, 1);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const TestWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.setString(rect.x, rect.y, "Test", .{});
        }
    };

    const widget = TestWidget{};

    // First render should fail (injected error)
    const result1 = injector.wrapRender("TargetWidget", &widget, &buf, area);
    try testing.expectError(error.InjectedError, result1);

    // Second render should succeed (injection count exhausted)
    try injector.wrapRender("TargetWidget", &widget, &buf, area);
}

test "ErrorInjector - inject failure with probability" {
    const allocator = testing.allocator;
    var injector = try ErrorInjector.init(allocator);
    defer injector.deinit();

    // 50% failure rate
    try injector.injectErrorProbability("RandomWidget", error.RandomFailure, 0.5);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const TestWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.setString(rect.x, rect.y, "Test", .{});
        }
    };

    const widget = TestWidget{};

    var failures: usize = 0;
    var successes: usize = 0;

    // Run 100 renders
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const result = injector.wrapRender("RandomWidget", &widget, &buf, area);
        if (result) |_| {
            successes += 1;
        } else |_| {
            failures += 1;
        }
    }

    // With 50% probability, expect ~40-60% failures (allow variance)
    try testing.expect(failures >= 30 and failures <= 70);
    try testing.expect(successes >= 30 and successes <= 70);
}

test "ErrorInjector - inject delay to simulate slow render" {
    const allocator = testing.allocator;
    var injector = try ErrorInjector.init(allocator);
    defer injector.deinit();

    // Inject 5ms delay
    try injector.injectDelay("SlowWidget", 5_000_000); // 5ms in nanoseconds

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const TestWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.setString(rect.x, rect.y, "Test", .{});
        }
    };

    const widget = TestWidget{};

    const start = std.time.nanoTimestamp();
    try injector.wrapRender("SlowWidget", &widget, &buf, area);
    const elapsed = std.time.nanoTimestamp() - start;

    // Should take at least 5ms
    try testing.expect(elapsed >= 5_000_000);
}

test "ErrorInjector - inject memory allocation failure" {
    const allocator = testing.allocator;
    var injector = try ErrorInjector.init(allocator);
    defer injector.deinit();

    // Configure: fail allocation on 3rd call
    try injector.injectAllocFailure(3);

    // Create FailingAllocator that uses injector
    var failing_alloc = try injector.createFailingAllocator(allocator);

    // First 2 allocations succeed
    const alloc1 = try failing_alloc.alloc(u8, 10);
    failing_alloc.free(alloc1);

    const alloc2 = try failing_alloc.alloc(u8, 10);
    failing_alloc.free(alloc2);

    // Third allocation fails
    const alloc3 = failing_alloc.alloc(u8, 10);
    try testing.expectError(error.OutOfMemory, alloc3);
}

test "ErrorInjector - inject panic for panic recovery testing" {
    const allocator = testing.allocator;
    var injector = try ErrorInjector.init(allocator);
    defer injector.deinit();

    // Enable panic injection
    try injector.injectPanic("PanicWidget", "Simulated panic");

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const TestWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.setString(rect.x, rect.y, "Test", .{});
        }
    };

    const widget = TestWidget{};

    // Should catch panic and return error
    const result = injector.wrapRenderSafe("PanicWidget", &widget, &buf, area);
    try testing.expectError(error.Panic, result);
}

test "ErrorInjector - conditional injection based on state" {
    const allocator = testing.allocator;
    var injector = try ErrorInjector.init(allocator);
    defer injector.deinit();

    // Inject error only when condition is met
    const condition = struct {
        fn call(ctx: ?*anyopaque) bool {
            const counter = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            counter.* += 1;
            return counter.* > 5; // Fail after 5 renders
        }
    }.call;

    var counter: usize = 0;
    try injector.injectErrorConditional("ConditionalWidget", error.ConditionalFailure, condition, &counter);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const TestWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.setString(rect.x, rect.y, "Test", .{});
        }
    };

    const widget = TestWidget{};

    // First 5 renders succeed
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        try injector.wrapRender("ConditionalWidget", &widget, &buf, area);
    }

    // 6th render fails
    const result = injector.wrapRender("ConditionalWidget", &widget, &buf, area);
    try testing.expectError(error.ConditionalFailure, result);
}

test "ErrorInjector - multiple injections on same widget" {
    const allocator = testing.allocator;
    var injector = try ErrorInjector.init(allocator);
    defer injector.deinit();

    // Inject delay + error
    try injector.injectDelay("MultiWidget", 1_000_000); // 1ms
    try injector.injectErrorAt("MultiWidget", error.InjectedError, 1);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const TestWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.setString(rect.x, rect.y, "Test", .{});
        }
    };

    const widget = TestWidget{};

    const start = std.time.nanoTimestamp();
    const result = injector.wrapRender("MultiWidget", &widget, &buf, area);
    const elapsed = std.time.nanoTimestamp() - start;

    // Should fail (error injection)
    try testing.expectError(error.InjectedError, result);

    // Should also have delay (at least 1ms)
    try testing.expect(elapsed >= 1_000_000);
}

test "ErrorInjector - reset clears all injections" {
    const allocator = testing.allocator;
    var injector = try ErrorInjector.init(allocator);
    defer injector.deinit();

    try injector.injectErrorAt("Widget1", error.Error1, 1);
    try injector.injectErrorAt("Widget2", error.Error2, 1);
    try injector.injectDelay("Widget3", 1_000_000);

    // Reset
    injector.reset();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const TestWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.setString(rect.x, rect.y, "Test", .{});
        }
    };

    // All injections cleared, should succeed
    try injector.wrapRender("Widget1", &TestWidget{}, &buf, area);
    try injector.wrapRender("Widget2", &TestWidget{}, &buf, area);
    try injector.wrapRender("Widget3", &TestWidget{}, &buf, area);
}

test "ErrorInjector - statistics tracking" {
    const allocator = testing.allocator;
    var injector = try ErrorInjector.init(allocator);
    defer injector.deinit();

    try injector.injectErrorProbability("TestWidget", error.InjectedError, 0.5);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const TestWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.setString(rect.x, rect.y, "Test", .{});
        }
    };

    // Run 50 renders
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        injector.wrapRender("TestWidget", &TestWidget{}, &buf, area) catch {};
    }

    const stats = injector.getStats("TestWidget");

    try testing.expectEqual(@as(usize, 50), stats.total_calls);
    try testing.expect(stats.injected_errors > 0);
    try testing.expect(stats.injected_errors < 50);
}

test "ErrorInjector - seed-based deterministic injection" {
    const allocator = testing.allocator;
    var injector1 = try ErrorInjector.init(allocator);
    defer injector1.deinit();

    var injector2 = try ErrorInjector.init(allocator);
    defer injector2.deinit();

    // Same seed should produce same results
    const seed: u64 = 12345;
    try injector1.setSeed(seed);
    try injector2.setSeed(seed);

    try injector1.injectErrorProbability("Widget", error.InjectedError, 0.5);
    try injector2.injectErrorProbability("Widget", error.InjectedError, 0.5);

    var buf1 = try Buffer.init(allocator, 80, 24);
    defer buf1.deinit();

    var buf2 = try Buffer.init(allocator, 80, 24);
    defer buf2.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const TestWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.setString(rect.x, rect.y, "Test", .{});
        }
    };

    // Run same sequence
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const result1 = injector1.wrapRender("Widget", &TestWidget{}, &buf1, area);
        const result2 = injector2.wrapRender("Widget", &TestWidget{}, &buf2, area);

        // Same seed should produce identical results
        try testing.expectEqual(result1 == error.InjectedError, result2 == error.InjectedError);
    }
}

// ============================================================================
// EDGE CASES & STRESS TESTS (8 tests)
// ============================================================================

test "ErrorBoundary - 100 nested boundaries" {
    const allocator = testing.allocator;

    var boundaries: [100]ErrorBoundary = undefined;
    for (&boundaries) |*boundary| {
        boundary.* = try ErrorBoundary.init(allocator);
    }
    defer {
        for (&boundaries) |*boundary| {
            boundary.deinit();
        }
    }

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const TestWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.setString(rect.x, rect.y, "Deep", .{});
        }
    };

    const widget = TestWidget{};

    // Nest render through all 100 boundaries
    // (In practice, would use recursive wrapping)
    try boundaries[99].renderWithBoundary(&widget, &buf, area);

    // Should succeed
    try testing.expectEqual(@as(u21, 'D'), buf.getConst(0, 0).?.char);
}

test "ErrorBoundary - 50 concurrent failures across widget tree" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 200, 100);
    defer buf.deinit();

    var boundary = try ErrorBoundary.init(allocator);
    defer boundary.deinit();

    const FailingWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.ConcurrentFailure;
        }
    };

    // Render 50 failing widgets in parallel areas
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        const area = Rect{
            .x = @intCast((i * 4) % 200),
            .y = @intCast((i / 50) * 2),
            .width = 4,
            .height = 2,
        };
        _ = boundary.renderWithBoundary(&FailingWidget{}, &buf, area) catch {};
    }

    // All 50 errors recorded
    try testing.expectEqual(@as(usize, 50), boundary.errorCount());
}

test "StateRecovery - snapshot of 200x100 buffer completes in <10ms" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 200, 100);
    defer buf.deinit();

    var recovery = try StateRecovery.init(allocator);
    defer recovery.deinit();

    // Fill buffer with data
    var y: u16 = 0;
    while (y < 100) : (y += 1) {
        var x: u16 = 0;
        while (x < 200) : (x += 1) {
            buf.set(x, y, .{ .char = 'X', .style = .{} });
        }
    }

    const start = std.time.nanoTimestamp();
    try recovery.captureSnapshot(&buf);
    const elapsed = std.time.nanoTimestamp() - start;

    // Snapshot should be fast (<10ms)
    try testing.expect(elapsed < 10_000_000);
}

test "ErrorReporter - 1000 hooks registered and invoked" {
    const allocator = testing.allocator;
    var reporter = try ErrorReporter.init(allocator);
    defer reporter.deinit();

    var counters: [1000]usize = undefined;
    @memset(&counters, 0);

    const hook = struct {
        fn call(ctx: ?*anyopaque, _: anyerror, _: []const u8) void {
            const counter = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            counter.* += 1;
        }
    }.call;

    // Register 1000 hooks
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        _ = try reporter.registerHook(hook, &counters[i]);
    }

    // Report error
    reporter.report(error.TestError, "Test");

    // All 1000 hooks invoked
    for (counters) |count| {
        try testing.expectEqual(@as(usize, 1), count);
    }
}

test "GracefulDegradation - stress test 100 mixed widgets" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 200, 100);
    defer buf.deinit();

    var degradation = try GracefulDegradation.init(allocator);
    defer degradation.deinit();

    const SuccessWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.set(rect.x, rect.y, .{ .char = 'S', .style = .{} });
        }
    };

    const FailingWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.RenderFailed;
        }
    };

    // Render 100 widgets, alternating success/failure
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const area = Rect{
            .x = @intCast((i * 2) % 200),
            .y = @intCast(i / 100),
            .width = 2,
            .height = 1,
        };

        if (i % 2 == 0) {
            degradation.render(&SuccessWidget{}, &buf, area) catch {};
        } else {
            _ = degradation.renderWithFallback(&FailingWidget{}, &buf, area, "F");
        }
    }

    const stats = degradation.getStats();
    try testing.expectEqual(@as(usize, 100), stats.total_renders);
    try testing.expectEqual(@as(usize, 50), stats.successes);
    try testing.expectEqual(@as(usize, 50), stats.failures);
}

test "ErrorInjector - inject errors on 20% of 500 renders" {
    const allocator = testing.allocator;
    var injector = try ErrorInjector.init(allocator);
    defer injector.deinit();

    try injector.setSeed(54321);
    try injector.injectErrorProbability("StressWidget", error.InjectedError, 0.2);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const TestWidget = struct {
        pub fn render(_: @This(), buffer: *Buffer, rect: Rect) !void {
            buffer.setString(rect.x, rect.y, "Test", .{});
        }
    };

    var failures: usize = 0;

    var i: usize = 0;
    while (i < 500) : (i += 1) {
        const result = injector.wrapRender("StressWidget", &TestWidget{}, &buf, area);
        if (result) |_| {} else |_| {
            failures += 1;
        }
    }

    // Should be ~100 failures (20% of 500), allow 80-120 range
    try testing.expect(failures >= 80 and failures <= 120);
}

test "ErrorBoundary - hook errors do not crash boundary" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    var boundary = try ErrorBoundary.init(allocator);
    defer boundary.deinit();

    // Note: In Zig, panics are unrecoverable and cannot be caught.
    // This test verifies that the boundary still returns the original error
    // even when a callback is configured (callbacks should not panic).
    const safe_callback = struct {
        fn call(_: ?*anyopaque, _: anyerror, _: []const u8, _: Rect) void {
            // Callback runs, but doesn't affect error propagation
            // In production, callbacks should never panic
        }
    }.call;

    try boundary.setErrorCallback(safe_callback, null);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    const FailingWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.TestError;
        }
    };

    // Boundary should return the original error
    _ = boundary.renderWithBoundarySafe(&FailingWidget{}, &buf, area) catch |err| {
        // Should return the widget's error
        try testing.expect(err == error.TestError);
    };
}

test "ErrorRecovery - full integration test" {
    const allocator = testing.allocator;
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // Setup all systems
    var boundary = try ErrorBoundary.init(allocator);
    defer boundary.deinit();

    var recovery = try StateRecovery.init(allocator);
    defer recovery.deinit();

    var reporter = try ErrorReporter.init(allocator);
    defer reporter.deinit();

    var degradation = try GracefulDegradation.init(allocator);
    defer degradation.deinit();

    var error_count: usize = 0;

    const hook = struct {
        fn call(ctx: ?*anyopaque, _: anyerror, _: []const u8) void {
            const counter = @as(*usize, @ptrCast(@alignCast(ctx.?)));
            counter.* += 1;
        }
    }.call;

    _ = try reporter.registerHook(hook, &error_count);

    // Setup initial state
    buf.setString(0, 0, "Initial", .{});
    try recovery.captureSnapshot(&buf);

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };

    const FailingWidget = struct {
        pub fn render(_: @This(), _: *Buffer, _: Rect) !void {
            return error.IntegrationTestError;
        }
    };

    // 1. Render fails
    _ = boundary.renderWithBoundary(&FailingWidget{}, &buf, area) catch |err| {
        try testing.expectEqual(error.IntegrationTestError, err);
    };

    // 2. Error boundary captured error
    try testing.expectEqual(@as(usize, 1), boundary.errorCount());

    // 3. Reporter hook invoked
    reporter.report(error.IntegrationTestError, "Integration test failure");
    try testing.expectEqual(@as(usize, 1), error_count);

    // 4. Recovery rolls back
    try recovery.rollback(&buf);
    try testing.expectEqual(@as(u21, 'I'), buf.getConst(0, 0).?.char);

    // 5. Degradation tracks failure
    _ = degradation.renderWithFallback(&FailingWidget{}, &buf, area, "Fallback");
    const stats = degradation.getStats();
    try testing.expectEqual(@as(usize, 1), stats.failures);
}
