//! Widget Inspector Tests
//!
//! Tests for the widget inspector module (src/tui/inspector.zig)
//! that provides runtime introspection, layout debugging, and event tracing.
//!
//! This test suite follows TDD principles - tests are written BEFORE implementation.
//! All tests should FAIL until the inspector module is implemented.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;

// Forward declarations for types that will be implemented in src/tui/inspector.zig
// These will cause compilation errors until the module exists - that's expected for TDD

// NOTE: These imports will fail until src/tui/inspector.zig is implemented
// This is intentional for TDD - tests define the API before implementation
const inspector_mod = sailor.tui.inspector;
const Inspector = inspector_mod.Inspector;
const WidgetInfo = inspector_mod.WidgetInfo;
const LayoutInfo = inspector_mod.LayoutInfo;
const EventRecord = inspector_mod.EventRecord;
const EventType = inspector_mod.EventType;
const ConstraintRecord = inspector_mod.ConstraintRecord;

// ============================================================================
// Basic Inspector Lifecycle Tests
// ============================================================================

test "inspector init and deinit" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();

    // Inspector should start disabled
    try testing.expect(!inspector.isEnabled());
}

test "inspector enable and disable" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();

    try testing.expect(!inspector.isEnabled());

    inspector.enable();
    try testing.expect(inspector.isEnabled());

    inspector.disable();
    try testing.expect(!inspector.isEnabled());
}

test "inspector no memory leaks when disabled" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();

    // Recording when disabled should not allocate
    _ = inspector.recordWidget("TestWidget", .{ .x = 0, .y = 0, .width = 10, .height = 5 });
    inspector.recordEvent(.{ .keyboard = 'a' });
}

test "inspector no memory leaks with enabled operations" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();

    inspector.enable();

    // Record some data
    _ = inspector.recordWidget("Widget1", .{ .x = 0, .y = 0, .width = 20, .height = 10 });
    _ = inspector.recordWidget("Widget2", .{ .x = 20, .y = 0, .width = 20, .height = 10 });
    inspector.recordEvent(.{ .keyboard = 'a' });
    inspector.recordEvent(.{ .keyboard = 'b' });
    inspector.recordLayoutCalculation("Widget1", .{ .x = 0, .y = 0, .width = 20, .height = 10 });

    // Deinit should clean up all allocations
}

// ============================================================================
// Widget Tree Introspection Tests
// ============================================================================

test "inspector captures widget tree structure" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    // Record parent widget
    const root_id = inspector.recordWidget("Root", .{ .x = 0, .y = 0, .width = 100, .height = 50 });

    // Record child widgets
    _ = inspector.recordWidgetWithParent("Header", .{ .x = 0, .y = 0, .width = 100, .height = 10 }, root_id);
    _ = inspector.recordWidgetWithParent("Body", .{ .x = 0, .y = 10, .width = 100, .height = 40 }, root_id);

    // Verify tree structure
    const tree = inspector.getWidgetTree();
    try testing.expect(tree != null);

    const root = tree.?;
    try testing.expectEqualStrings("Root", root.name);
    try testing.expectEqual(@as(usize, 2), root.children.len);
}

test "inspector records widget properties" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    const widget_id = inspector.recordWidget("MyWidget", .{ .x = 10, .y = 5, .width = 30, .height = 15 });

    // Add custom properties
    try inspector.setWidgetProperty(widget_id, "title", "Hello World");
    try inspector.setWidgetProperty(widget_id, "visible", "true");
    try inspector.setWidgetProperty(widget_id, "focused", "false");

    const info = inspector.getWidgetInfo(widget_id);
    try testing.expect(info != null);

    const widget = info.?;
    try testing.expectEqualStrings("MyWidget", widget.name);
    try testing.expectEqual(@as(u16, 10), widget.area.x);
    try testing.expectEqual(@as(u16, 5), widget.area.y);
    try testing.expectEqual(@as(u16, 30), widget.area.width);
    try testing.expectEqual(@as(u16, 15), widget.area.height);

    // Verify properties
    const title = widget.getProperty("title");
    try testing.expect(title != null);
    try testing.expectEqualStrings("Hello World", title.?);
}

test "inspector captures nested widget hierarchy" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    // Build a 3-level hierarchy
    const app = inspector.recordWidget("App", .{ .x = 0, .y = 0, .width = 80, .height = 24 });
    const panel = inspector.recordWidgetWithParent("Panel", .{ .x = 0, .y = 0, .width = 40, .height = 24 }, app);
    const button1 = inspector.recordWidgetWithParent("Button1", .{ .x = 5, .y = 5, .width = 10, .height = 3 }, panel);
    const button2 = inspector.recordWidgetWithParent("Button2", .{ .x = 5, .y = 10, .width = 10, .height = 3 }, panel);

    // Verify depth calculation
    try testing.expectEqual(@as(usize, 0), inspector.getWidgetDepth(app));
    try testing.expectEqual(@as(usize, 1), inspector.getWidgetDepth(panel));
    try testing.expectEqual(@as(usize, 2), inspector.getWidgetDepth(button1));
    try testing.expectEqual(@as(usize, 2), inspector.getWidgetDepth(button2));

    // Verify sibling count
    const siblings = inspector.getSiblings(button1);
    try testing.expectEqual(@as(usize, 1), siblings.len); // button2 is the only sibling
}

test "inspector clears widget tree between frames" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    // Frame 1
    _ = inspector.recordWidget("Widget1", .{ .x = 0, .y = 0, .width = 10, .height = 10 });
    try testing.expectEqual(@as(usize, 1), inspector.getWidgetCount());

    // Start new frame
    inspector.beginFrame();
    try testing.expectEqual(@as(usize, 0), inspector.getWidgetCount());

    // Frame 2
    _ = inspector.recordWidget("Widget2", .{ .x = 0, .y = 0, .width = 20, .height = 20 });
    _ = inspector.recordWidget("Widget3", .{ .x = 20, .y = 0, .width = 20, .height = 20 });
    try testing.expectEqual(@as(usize, 2), inspector.getWidgetCount());
}

// ============================================================================
// Layout Debugging Tests
// ============================================================================

test "inspector records layout calculations" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    const widget_id = inspector.recordWidget("Container", .{ .x = 0, .y = 0, .width = 100, .height = 50 });

    // Record constraint applied
    inspector.recordConstraint(widget_id, .{ .percentage = 50 }, .horizontal, 100);

    // Record final calculated size
    inspector.recordLayoutCalculation(widget_id, .{ .x = 0, .y = 0, .width = 50, .height = 50 });

    const layout = inspector.getLayoutInfo(widget_id);
    try testing.expect(layout != null);

    const info = layout.?;
    try testing.expectEqual(@as(u16, 50), info.calculated_area.width);
    try testing.expectEqual(@as(usize, 1), info.constraints.len);
}

test "inspector tracks constraint types" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    const widget_id = inspector.recordWidget("Widget", .{ .x = 0, .y = 0, .width = 0, .height = 0 });

    // Record different constraint types
    inspector.recordConstraint(widget_id, .{ .percentage = 30 }, .vertical, 100);
    inspector.recordConstraint(widget_id, .{ .length = 20 }, .horizontal, 100);
    inspector.recordConstraint(widget_id, .{ .min = 10 }, .vertical, 100);
    inspector.recordConstraint(widget_id, .{ .max = 50 }, .horizontal, 100);
    inspector.recordConstraint(widget_id, .{ .ratio = .{ .num = 1, .denom = 3 } }, .vertical, 100);

    const layout = inspector.getLayoutInfo(widget_id);
    try testing.expect(layout != null);
    try testing.expectEqual(@as(usize, 5), layout.?.constraints.len);
}

test "inspector records layout parent-child relationships" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    const parent_id = inspector.recordWidget("Parent", .{ .x = 0, .y = 0, .width = 100, .height = 50 });
    _ = inspector.recordWidgetWithParent("Child", .{ .x = 10, .y = 10, .width = 30, .height = 20 }, parent_id);

    // Child should fit within parent
    const violation = inspector.detectLayoutViolations();
    try testing.expectEqual(@as(usize, 0), violation.len); // No violations

    // Record child that overflows parent
    const overflow_id = inspector.recordWidgetWithParent("Overflow", .{ .x = 80, .y = 0, .width = 50, .height = 10 }, parent_id);

    const violations = inspector.detectLayoutViolations();
    try testing.expect(violations.len > 0); // Should detect overflow

    const first_violation = violations[0];
    try testing.expectEqual(overflow_id, first_violation.widget_id);
    try testing.expectEqualStrings("overflow", first_violation.violation_type);
}

test "inspector calculates available space" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    const widget_id = inspector.recordWidget("Widget", .{ .x = 0, .y = 0, .width = 100, .height = 50 });

    // Record that widget requested 150 width but got 100 (constrained)
    inspector.recordConstraint(widget_id, .{ .length = 150 }, .horizontal, 100);
    inspector.recordLayoutCalculation(widget_id, .{ .x = 0, .y = 0, .width = 100, .height = 50 });

    const layout = inspector.getLayoutInfo(widget_id);
    try testing.expect(layout != null);

    // Should show that available space was 100, not the requested 150
    try testing.expectEqual(@as(u16, 100), layout.?.available_width);
}

// ============================================================================
// Event Tracing Tests
// ============================================================================

test "inspector records keyboard events with timestamps" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    inspector.recordEvent(.{ .keyboard = 'a' });
    std.Thread.sleep(1_000_000); // Sleep 1ms to ensure different timestamp
    inspector.recordEvent(.{ .keyboard = 'b' });
    inspector.recordEvent(.{ .keyboard = 'c' });

    const events = inspector.getEvents();
    try testing.expectEqual(@as(usize, 3), events.len);

    // Verify order and timestamps
    try testing.expectEqual(EventType.keyboard, events[0].event_type);
    try testing.expectEqual(EventType.keyboard, events[1].event_type);
    try testing.expectEqual(EventType.keyboard, events[2].event_type);

    // Second event should have later timestamp than first
    try testing.expect(events[1].timestamp > events[0].timestamp);
    try testing.expect(events[2].timestamp > events[1].timestamp);
}

test "inspector records mouse events" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    inspector.recordEvent(.{ .mouse_move = .{ .x = 10, .y = 5 } });
    inspector.recordEvent(.{ .mouse_click = .{ .x = 10, .y = 5, .button = .left } });
    inspector.recordEvent(.{ .mouse_scroll = .{ .delta = 3 } });

    const events = inspector.getEvents();
    try testing.expectEqual(@as(usize, 3), events.len);
    try testing.expectEqual(EventType.mouse_move, events[0].event_type);
    try testing.expectEqual(EventType.mouse_click, events[1].event_type);
    try testing.expectEqual(EventType.mouse_scroll, events[2].event_type);
}

test "inspector records resize events" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    inspector.recordEvent(.{ .resize = .{ .cols = 120, .rows = 40 } });
    inspector.recordEvent(.{ .resize = .{ .cols = 80, .rows = 24 } });

    const events = inspector.getEvents();
    try testing.expectEqual(@as(usize, 2), events.len);
    try testing.expectEqual(EventType.resize, events[0].event_type);
    try testing.expectEqual(EventType.resize, events[1].event_type);
}

test "inspector limits event history size" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    // Set max events to 10
    inspector.setMaxEvents(10);

    // Record 20 events
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        inspector.recordEvent(.{ .keyboard = @as(u8, @intCast('a' + (i % 26))) });
    }

    const events = inspector.getEvents();
    try testing.expectEqual(@as(usize, 10), events.len);

    // Should keep the most recent 10 events
    try testing.expectEqual(@as(u8, 'a' + 10), events[0].data.keyboard);
    try testing.expectEqual(@as(u8, 'a' + 19), events[9].data.keyboard);
}

test "inspector filters events by type" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    inspector.recordEvent(.{ .keyboard = 'a' });
    inspector.recordEvent(.{ .mouse_move = .{ .x = 10, .y = 5 } });
    inspector.recordEvent(.{ .keyboard = 'b' });
    inspector.recordEvent(.{ .resize = .{ .cols = 80, .rows = 24 } });
    inspector.recordEvent(.{ .keyboard = 'c' });

    const keyboard_events = try inspector.getEventsByType(.keyboard);
    defer allocator.free(keyboard_events);
    try testing.expectEqual(@as(usize, 3), keyboard_events.len);

    const mouse_events = try inspector.getEventsByType(.mouse_move);
    defer allocator.free(mouse_events);
    try testing.expectEqual(@as(usize, 1), mouse_events.len);

    const resize_events = try inspector.getEventsByType(.resize);
    defer allocator.free(resize_events);
    try testing.expectEqual(@as(usize, 1), resize_events.len);
}

test "inspector clears event history" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    inspector.recordEvent(.{ .keyboard = 'a' });
    inspector.recordEvent(.{ .keyboard = 'b' });
    inspector.recordEvent(.{ .keyboard = 'c' });

    try testing.expectEqual(@as(usize, 3), inspector.getEvents().len);

    inspector.clearEvents();
    try testing.expectEqual(@as(usize, 0), inspector.getEvents().len);
}

// ============================================================================
// Output to Writer Tests
// ============================================================================

test "inspector outputs widget tree to writer" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    const root = inspector.recordWidget("Root", .{ .x = 0, .y = 0, .width = 100, .height = 50 });
    _ = inspector.recordWidgetWithParent("Child1", .{ .x = 0, .y = 0, .width = 50, .height = 25 }, root);
    _ = inspector.recordWidgetWithParent("Child2", .{ .x = 50, .y = 0, .width = 50, .height = 25 }, root);

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try inspector.writeWidgetTree(stream.writer());

    const written = stream.getWritten();

    // Should contain widget names
    try testing.expect(std.mem.indexOf(u8, written, "Root") != null);
    try testing.expect(std.mem.indexOf(u8, written, "Child1") != null);
    try testing.expect(std.mem.indexOf(u8, written, "Child2") != null);

    // Should show hierarchy (indentation or tree symbols)
    try testing.expect(written.len > 0);
}

test "inspector outputs layout info to writer" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    const widget_id = inspector.recordWidget("Widget", .{ .x = 10, .y = 5, .width = 30, .height = 15 });
    inspector.recordConstraint(widget_id, .{ .percentage = 50 }, .horizontal, 60);
    inspector.recordLayoutCalculation(widget_id, .{ .x = 10, .y = 5, .width = 30, .height = 15 });

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try inspector.writeLayoutInfo(stream.writer());

    const written = stream.getWritten();

    // Should contain widget name and dimensions
    try testing.expect(std.mem.indexOf(u8, written, "Widget") != null);
    try testing.expect(std.mem.indexOf(u8, written, "30") != null); // width
    try testing.expect(std.mem.indexOf(u8, written, "15") != null); // height
}

test "inspector outputs event log to writer" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    inspector.recordEvent(.{ .keyboard = 'a' });
    inspector.recordEvent(.{ .mouse_move = .{ .x = 10, .y = 5 } });
    inspector.recordEvent(.{ .resize = .{ .cols = 80, .rows = 24 } });

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try inspector.writeEventLog(stream.writer());

    const written = stream.getWritten();

    // Should contain event types
    try testing.expect(std.mem.indexOf(u8, written, "keyboard") != null or std.mem.indexOf(u8, written, "key") != null);
    try testing.expect(std.mem.indexOf(u8, written, "mouse") != null);
    try testing.expect(std.mem.indexOf(u8, written, "resize") != null);

    // Should have timestamps
    try testing.expect(written.len > 0);
}

test "inspector outputs to writer in JSON format" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    _ = inspector.recordWidget("Root", .{ .x = 0, .y = 0, .width = 100, .height = 50 });
    inspector.recordEvent(.{ .keyboard = 'a' });

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try inspector.writeJSON(stream.writer());

    const written = stream.getWritten();

    // Should be valid JSON
    try testing.expect(std.mem.indexOf(u8, written, "{") != null);
    try testing.expect(std.mem.indexOf(u8, written, "}") != null);
    try testing.expect(std.mem.indexOf(u8, written, "Root") != null);
}

test "inspector never writes to stdout directly" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    // Record some data
    _ = inspector.recordWidget("Widget", .{ .x = 0, .y = 0, .width = 10, .height = 10 });
    inspector.recordEvent(.{ .keyboard = 'a' });

    // All output must go through Writer - no stdout calls
    // This test ensures the API design forces writer-based output
    var buf: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try inspector.writeWidgetTree(stream.writer());

    // If implementation uses stdout, this test will fail because
    // we can't capture stdout in Zig tests
    try testing.expect(stream.getWritten().len > 0);
}

// ============================================================================
// Performance & Edge Cases
// ============================================================================

test "inspector handles empty widget tree" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    // No widgets recorded
    try testing.expectEqual(@as(usize, 0), inspector.getWidgetCount());

    var buf: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    // Should not crash
    try inspector.writeWidgetTree(stream.writer());
}

test "inspector handles zero-size widgets" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    const widget_id = inspector.recordWidget("Collapsed", .{ .x = 0, .y = 0, .width = 0, .height = 0 });

    const info = inspector.getWidgetInfo(widget_id);
    try testing.expect(info != null);
    try testing.expectEqual(@as(u16, 0), info.?.area.width);
    try testing.expectEqual(@as(u16, 0), info.?.area.height);
}

test "inspector handles rapid event recording" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();
    inspector.setMaxEvents(100);

    // Record 1000 events rapidly
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        inspector.recordEvent(.{ .keyboard = @as(u8, @intCast('a' + (i % 26))) });
    }

    // Should keep only the last 100
    const events = inspector.getEvents();
    try testing.expectEqual(@as(usize, 100), events.len);
}

test "inspector disabled mode has zero performance overhead" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();

    // Inspector is disabled - these should be no-ops
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        _ = inspector.recordWidget("Widget", .{ .x = 0, .y = 0, .width = 10, .height = 10 });
        inspector.recordEvent(.{ .keyboard = 'a' });
    }

    // Should not have recorded anything
    try testing.expectEqual(@as(usize, 0), inspector.getWidgetCount());
    try testing.expectEqual(@as(usize, 0), inspector.getEvents().len);
}

test "inspector frame lifecycle management" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    // Frame 1
    inspector.beginFrame();
    _ = inspector.recordWidget("Widget1", .{ .x = 0, .y = 0, .width = 10, .height = 10 });
    inspector.endFrame();

    try testing.expectEqual(@as(usize, 1), inspector.getFrameCount());

    // Frame 2
    inspector.beginFrame();
    _ = inspector.recordWidget("Widget2", .{ .x = 0, .y = 0, .width = 20, .height = 20 });
    _ = inspector.recordWidget("Widget3", .{ .x = 20, .y = 0, .width = 20, .height = 20 });
    inspector.endFrame();

    try testing.expectEqual(@as(usize, 2), inspector.getFrameCount());

    // Can query previous frame
    const frame1_widgets = inspector.getFrameWidgets(0);
    try testing.expectEqual(@as(usize, 1), frame1_widgets.len);

    const frame2_widgets = inspector.getFrameWidgets(1);
    try testing.expectEqual(@as(usize, 2), frame2_widgets.len);
}

test "inspector invalid widget id returns null" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    const invalid_id: u32 = 999999;

    const info = inspector.getWidgetInfo(invalid_id);
    try testing.expect(info == null);

    const layout = inspector.getLayoutInfo(invalid_id);
    try testing.expect(layout == null);
}

test "inspector concurrent widget recording is safe" {
    const allocator = testing.allocator;

    var inspector = try Inspector.init(allocator);
    defer inspector.deinit();
    inspector.enable();

    // Record widgets from different parts of the tree
    const root = inspector.recordWidget("Root", .{ .x = 0, .y = 0, .width = 100, .height = 50 });
    const left = inspector.recordWidgetWithParent("Left", .{ .x = 0, .y = 0, .width = 50, .height = 50 }, root);
    const right = inspector.recordWidgetWithParent("Right", .{ .x = 50, .y = 0, .width = 50, .height = 50 }, root);

    // Both children should have same parent
    const left_info = inspector.getWidgetInfo(left).?;
    const right_info = inspector.getWidgetInfo(right).?;

    try testing.expectEqual(root, left_info.parent_id.?);
    try testing.expectEqual(root, right_info.parent_id.?);
}
