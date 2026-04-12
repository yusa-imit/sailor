//! Widget composition helpers tests (TDD — Red phase)
//!
//! Tests for v1.23.0 milestone: generic widget decorators, wrappers, and containers.
//! These tests verify:
//! 1. Padding(T) — uniform and custom padding around any widget
//! 2. Centered(T) — centering any widget in available area
//! 3. Aligned(T) — alignment control (horizontal + vertical)
//! 4. Stack — vertical/horizontal stacking of heterogeneous widgets
//! 5. Constrained(T) — min/max size enforcement
//!
//! All helpers must work with ANY widget type that implements the widget protocol.
//! These tests should FAIL until src/tui/widget_helpers.zig is implemented.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Size = sailor.tui.widget_trait.Size;

// Import widget helpers (will fail until implemented)
const helpers = sailor.tui.widget_helpers;
const Padding = helpers.Padding;
const Centered = helpers.Centered;
const Aligned = helpers.Aligned;
const Alignment = helpers.Alignment;
const Stack = helpers.Stack;
const Constrained = helpers.Constrained;

// ============================================================================
// Test Widgets — Simple widgets with predictable output
// ============================================================================

/// Simple widget that fills area with a character
const FillWidget = struct {
    char: u21,
    style: Style = .{},

    pub fn render(self: FillWidget, buf: *Buffer, area: Rect) void {
        var y: u16 = area.y;
        while (y < area.y + area.height) : (y += 1) {
            var x: u16 = area.x;
            while (x < area.x + area.width) : (x += 1) {
                buf.set(x, y, .{ .char = self.char, .style = self.style });
            }
        }
    }
};

/// Widget that renders fixed text at top-left
const TextWidget = struct {
    text: []const u8,
    style: Style = .{},

    pub fn render(self: TextWidget, buf: *Buffer, area: Rect) void {
        if (area.width == 0 or area.height == 0) return;
        var x: u16 = area.x;
        for (self.text) |byte| {
            if (x >= area.x + area.width) break;
            if (byte >= 32 and byte < 127) {
                buf.set(x, area.y, .{ .char = byte, .style = self.style });
                x += 1;
            }
        }
    }
};

/// Widget with measure() support — returns preferred size
const MeasuredWidget = struct {
    pref_width: u16,
    pref_height: u16,
    char: u21 = 'M',

    pub fn measure(self: MeasuredWidget, _: std.mem.Allocator, _: u16, _: u16) !Size {
        return Size{ .width = self.pref_width, .height = self.pref_height };
    }

    pub fn render(self: MeasuredWidget, buf: *Buffer, area: Rect) void {
        const widget = FillWidget{ .char = self.char };
        widget.render(buf, area);
    }
};

// ============================================================================
// Padding Tests
// ============================================================================

test "Padding with uniform padding adds space around widget" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit();

    const inner_widget = FillWidget{ .char = 'X' };
    const padded = Padding(FillWidget).init(inner_widget, 2); // 2 cells on all sides

    const area = Rect.new(0, 0, 20, 10);
    padded.render(&buffer, area);

    // Verify padding is empty (default space char)
    // Top padding (y=0,1)
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(5, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(5, 1).?.char);

    // Left padding (x=0,1)
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(0, 5).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(1, 5).?.char);

    // Inner content should be 'X' starting at (2,2)
    try testing.expectEqual(@as(u21, 'X'), buffer.getConst(2, 2).?.char);
    try testing.expectEqual(@as(u21, 'X'), buffer.getConst(10, 5).?.char);

    // Right padding (x=18,19)
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(18, 5).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(19, 5).?.char);

    // Bottom padding (y=8,9)
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(10, 8).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(10, 9).?.char);
}

test "Padding with custom padding per side" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 15);
    defer buffer.deinit();

    const inner_widget = FillWidget{ .char = 'Y' };
    // top=1, right=3, bottom=2, left=4
    const padded = Padding(FillWidget).initCustom(inner_widget, 1, 3, 2, 4);

    const area = Rect.new(0, 0, 30, 15);
    padded.render(&buffer, area);

    // Left padding: 4 cells
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(0, 5).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(3, 5).?.char);

    // Top padding: 1 cell
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(10, 0).?.char);

    // Content starts at (4, 1)
    try testing.expectEqual(@as(u21, 'Y'), buffer.getConst(4, 1).?.char);

    // Right padding: 3 cells (area.width=30, so content ends at 26, padding at 27-29)
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(27, 5).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(29, 5).?.char);

    // Bottom padding: 2 cells (area.height=15, padding at 13-14)
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(10, 13).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(10, 14).?.char);
}

test "Padding with zero padding renders widget unchanged" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 5);
    defer buffer.deinit();

    const inner_widget = FillWidget{ .char = 'Z' };
    const padded = Padding(FillWidget).init(inner_widget, 0);

    const area = Rect.new(0, 0, 10, 5);
    padded.render(&buffer, area);

    // No padding, entire area should be 'Z'
    try testing.expectEqual(@as(u21, 'Z'), buffer.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'Z'), buffer.getConst(9, 4).?.char);
}

test "Padding exceeds available space renders nothing" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 10);
    defer buffer.deinit();

    const inner_widget = FillWidget{ .char = 'Q' };
    const padded = Padding(FillWidget).init(inner_widget, 10); // padding larger than area

    const area = Rect.new(0, 0, 10, 10);
    padded.render(&buffer, area);

    // All padding, no content
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(9, 9).?.char);
}

// ============================================================================
// Centered Tests
// ============================================================================

test "Centered centers widget with measure() support" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 20);
    defer buffer.deinit();

    const inner_widget = MeasuredWidget{ .pref_width = 10, .pref_height = 6, .char = 'C' };
    const centered = Centered(MeasuredWidget).init(inner_widget);

    const area = Rect.new(0, 0, 30, 20);
    centered.render(&buffer, area);

    // Widget is 10x6, area is 30x20
    // Centered: x = (30-10)/2 = 10, y = (20-6)/2 = 7
    // Content should be at (10,7) to (19,12)
    try testing.expectEqual(@as(u21, 'C'), buffer.getConst(10, 7).?.char);
    try testing.expectEqual(@as(u21, 'C'), buffer.getConst(19, 12).?.char);

    // Outside centered area should be empty
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(9, 7).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(20, 12).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(10, 6).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(19, 13).?.char);
}

test "Centered with widget without measure() centers entire area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit();

    const inner_widget = FillWidget{ .char = 'F' };
    const centered = Centered(FillWidget).init(inner_widget);

    const area = Rect.new(0, 0, 20, 10);
    centered.render(&buffer, area);

    // Without measure(), widget takes full area (no centering needed)
    try testing.expectEqual(@as(u21, 'F'), buffer.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'F'), buffer.getConst(19, 9).?.char);
}

test "Centered with widget larger than area clips correctly" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 10);
    defer buffer.deinit();

    const inner_widget = MeasuredWidget{ .pref_width = 50, .pref_height = 50, .char = 'L' };
    const centered = Centered(MeasuredWidget).init(inner_widget);

    const area = Rect.new(0, 0, 10, 10);
    centered.render(&buffer, area);

    // Widget larger than area: render at (0,0) with area size
    try testing.expectEqual(@as(u21, 'L'), buffer.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'L'), buffer.getConst(9, 9).?.char);
}

// ============================================================================
// Aligned Tests
// ============================================================================

test "Aligned left-top alignment" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 20);
    defer buffer.deinit();

    const inner_widget = MeasuredWidget{ .pref_width = 8, .pref_height = 4, .char = 'A' };
    const aligned = Aligned(MeasuredWidget).init(inner_widget, .{ .horizontal = .left, .vertical = .top });

    const area = Rect.new(5, 3, 30, 20);
    aligned.render(&buffer, area);

    // Left-top: starts at area origin (5, 3), size 8x4
    try testing.expectEqual(@as(u21, 'A'), buffer.getConst(5, 3).?.char);
    try testing.expectEqual(@as(u21, 'A'), buffer.getConst(12, 6).?.char);

    // Outside widget area should be empty
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(13, 3).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(5, 7).?.char);
}

test "Aligned center-middle alignment" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 30);
    defer buffer.deinit();

    const inner_widget = MeasuredWidget{ .pref_width = 10, .pref_height = 6, .char = 'M' };
    const aligned = Aligned(MeasuredWidget).init(inner_widget, .{ .horizontal = .center, .vertical = .middle });

    const area = Rect.new(0, 0, 40, 30);
    aligned.render(&buffer, area);

    // Center-middle: x=(40-10)/2=15, y=(30-6)/2=12
    try testing.expectEqual(@as(u21, 'M'), buffer.getConst(15, 12).?.char);
    try testing.expectEqual(@as(u21, 'M'), buffer.getConst(24, 17).?.char);

    // Outside should be empty
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(14, 12).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(25, 17).?.char);
}

test "Aligned right-bottom alignment" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 50, 40);
    defer buffer.deinit();

    const inner_widget = MeasuredWidget{ .pref_width = 12, .pref_height = 8, .char = 'R' };
    const aligned = Aligned(MeasuredWidget).init(inner_widget, .{ .horizontal = .right, .vertical = .bottom });

    const area = Rect.new(0, 0, 50, 40);
    aligned.render(&buffer, area);

    // Right-bottom: x=50-12=38, y=40-8=32
    try testing.expectEqual(@as(u21, 'R'), buffer.getConst(38, 32).?.char);
    try testing.expectEqual(@as(u21, 'R'), buffer.getConst(49, 39).?.char);

    // Outside should be empty
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(37, 32).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(38, 31).?.char);
}

test "Aligned with widget without measure() uses full area" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit();

    const inner_widget = TextWidget{ .text = "Hello" };
    const aligned = Aligned(TextWidget).init(inner_widget, .{ .horizontal = .right, .vertical = .bottom });

    const area = Rect.new(0, 0, 20, 10);
    aligned.render(&buffer, area);

    // Without measure(), widget renders at area origin (no alignment calculation)
    try testing.expectEqual(@as(u21, 'H'), buffer.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'e'), buffer.getConst(1, 0).?.char);
}

// ============================================================================
// Stack Tests
// ============================================================================

test "Stack vertical stacking of multiple widgets" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 21);
    defer buffer.deinit();

    var stack = try Stack.initVertical(allocator);
    defer stack.deinit();

    // Add three widgets: each takes equal space in vertical stack
    const widget1 = FillWidget{ .char = '1' };
    const widget2 = FillWidget{ .char = '2' };
    const widget3 = FillWidget{ .char = '3' };

    try stack.push(widget1);
    try stack.push(widget2);
    try stack.push(widget3);

    const area = Rect.new(0, 0, 30, 21); // 21/3 = 7 per widget
    stack.render(&buffer, area);

    // First widget: rows 0-6
    try testing.expectEqual(@as(u21, '1'), buffer.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, '1'), buffer.getConst(29, 6).?.char);

    // Second widget: rows 7-13
    try testing.expectEqual(@as(u21, '2'), buffer.getConst(0, 7).?.char);
    try testing.expectEqual(@as(u21, '2'), buffer.getConst(29, 13).?.char);

    // Third widget: rows 14-20
    try testing.expectEqual(@as(u21, '3'), buffer.getConst(0, 14).?.char);
    try testing.expectEqual(@as(u21, '3'), buffer.getConst(29, 20).?.char);
}

test "Stack horizontal stacking of multiple widgets" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 10);
    defer buffer.deinit();

    var stack = try Stack.initHorizontal(allocator);
    defer stack.deinit();

    const widget1 = FillWidget{ .char = 'A' };
    const widget2 = FillWidget{ .char = 'B' };

    try stack.push(widget1);
    try stack.push(widget2);

    const area = Rect.new(0, 0, 30, 10); // 30/2 = 15 per widget
    stack.render(&buffer, area);

    // First widget: columns 0-14
    try testing.expectEqual(@as(u21, 'A'), buffer.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'A'), buffer.getConst(14, 9).?.char);

    // Second widget: columns 15-29
    try testing.expectEqual(@as(u21, 'B'), buffer.getConst(15, 0).?.char);
    try testing.expectEqual(@as(u21, 'B'), buffer.getConst(29, 9).?.char);
}

test "Stack with empty stack renders nothing" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit();

    var stack = try Stack.initVertical(allocator);
    defer stack.deinit();

    const area = Rect.new(0, 0, 20, 10);
    stack.render(&buffer, area);

    // Empty stack: buffer remains default (spaces)
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(19, 9).?.char);
}

test "Stack with mixed widget types" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 15);
    defer buffer.deinit();

    var stack = try Stack.initVertical(allocator);
    defer stack.deinit();

    // NOTE: Stack must support heterogeneous widgets via type erasure or interface
    const text_widget = TextWidget{ .text = "Header" };
    const fill_widget = FillWidget{ .char = '=' };

    try stack.pushAny(text_widget); // First 50% (7 rows)
    try stack.pushAny(fill_widget); // Second 50% (8 rows)

    const area = Rect.new(0, 0, 40, 15);
    stack.render(&buffer, area);

    // First widget (text): rows 0-6
    try testing.expectEqual(@as(u21, 'H'), buffer.getConst(0, 0).?.char);

    // Second widget (fill): rows 7-14
    try testing.expectEqual(@as(u21, '='), buffer.getConst(0, 7).?.char);
    try testing.expectEqual(@as(u21, '='), buffer.getConst(39, 14).?.char);
}

// ============================================================================
// Constrained Tests
// ============================================================================

test "Constrained enforces min width and height" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 50, 30);
    defer buffer.deinit();

    const inner_widget = FillWidget{ .char = 'K' };
    const constrained = Constrained(FillWidget).init(inner_widget, .{
        .min_width = 20,
        .min_height = 10,
    });

    // Provide small area: constraints should expand it
    const small_area = Rect.new(0, 0, 10, 5);
    constrained.render(&buffer, small_area);

    // Widget should render at min size (20x10), clipped to buffer size
    // Since buffer is 50x30, min size fits
    try testing.expectEqual(@as(u21, 'K'), buffer.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'K'), buffer.getConst(19, 9).?.char);

    // Outside min area should be empty
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(20, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(0, 10).?.char);
}

test "Constrained enforces max width and height" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 60, 40);
    defer buffer.deinit();

    const inner_widget = FillWidget{ .char = 'N' };
    const constrained = Constrained(FillWidget).init(inner_widget, .{
        .max_width = 30,
        .max_height = 20,
    });

    // Provide large area: constraints should shrink it
    const large_area = Rect.new(0, 0, 60, 40);
    constrained.render(&buffer, large_area);

    // Widget should render at max size (30x20)
    try testing.expectEqual(@as(u21, 'N'), buffer.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'N'), buffer.getConst(29, 19).?.char);

    // Outside max area should be empty
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(30, 0).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(0, 20).?.char);
}

test "Constrained with both min and max clamps to valid range" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 30);
    defer buffer.deinit();

    const inner_widget = FillWidget{ .char = 'B' };
    const constrained = Constrained(FillWidget).init(inner_widget, .{
        .min_width = 15,
        .max_width = 25,
        .min_height = 10,
        .max_height = 20,
    });

    // Area within range: should render unchanged
    const area = Rect.new(0, 0, 20, 15);
    constrained.render(&buffer, area);

    try testing.expectEqual(@as(u21, 'B'), buffer.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'B'), buffer.getConst(19, 14).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(20, 0).?.char);
}

test "Constrained with impossible constraints renders at min" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 50, 30);
    defer buffer.deinit();

    const inner_widget = FillWidget{ .char = 'E' };
    // Impossible: min > max
    const constrained = Constrained(FillWidget).init(inner_widget, .{
        .min_width = 30,
        .max_width = 10, // max < min
        .min_height = 20,
        .max_height = 5, // max < min
    });

    const area = Rect.new(0, 0, 50, 30);
    constrained.render(&buffer, area);

    // Should render at min size (30x20) when constraints conflict
    try testing.expectEqual(@as(u21, 'E'), buffer.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'E'), buffer.getConst(29, 19).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(30, 0).?.char);
}

// ============================================================================
// Composition Tests — Helpers composed together
// ============================================================================

test "Padding + Centered composition" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 40, 30);
    defer buffer.deinit();

    // Center a 10x6 widget, then add padding
    const inner_widget = MeasuredWidget{ .pref_width = 10, .pref_height = 6, .char = 'P' };
    const centered = Centered(MeasuredWidget).init(inner_widget);
    const padded = Padding(Centered(MeasuredWidget)).init(centered, 3);

    const area = Rect.new(0, 0, 40, 30);
    padded.render(&buffer, area);

    // Padding reduces area by 3 on each side: inner area is 34x24
    // Centered widget is 10x6 in 34x24: x=(34-10)/2=12, y=(24-6)/2=9
    // Offset by padding: x=12+3=15, y=9+3=12
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(2, 2).?.char); // padding
    try testing.expectEqual(@as(u21, 'P'), buffer.getConst(15, 12).?.char); // content
    try testing.expectEqual(@as(u21, 'P'), buffer.getConst(24, 17).?.char); // content
}

test "Aligned + Constrained composition" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 50, 40);
    defer buffer.deinit();

    // Constrain to 20x15, then align to bottom-right
    const inner_widget = FillWidget{ .char = 'C' };
    const constrained = Constrained(FillWidget).init(inner_widget, .{
        .max_width = 20,
        .max_height = 15,
    });
    const aligned = Aligned(Constrained(FillWidget)).init(constrained, .{
        .horizontal = .right,
        .vertical = .bottom,
    });

    const area = Rect.new(0, 0, 50, 40);
    aligned.render(&buffer, area);

    // Constrained to 20x15, aligned to bottom-right: x=50-20=30, y=40-15=25
    try testing.expectEqual(@as(u21, 'C'), buffer.getConst(30, 25).?.char);
    try testing.expectEqual(@as(u21, 'C'), buffer.getConst(49, 39).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(29, 25).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(30, 24).?.char);
}

test "Stack with Padding on each child" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 30);
    defer buffer.deinit();

    var stack = try Stack.initVertical(allocator);
    defer stack.deinit();

    const widget1 = FillWidget{ .char = '1' };
    const widget2 = FillWidget{ .char = '2' };

    const padded1 = Padding(FillWidget).init(widget1, 1);
    const padded2 = Padding(FillWidget).init(widget2, 2);

    try stack.pushAny(padded1); // 50% of 30 = 15 rows
    try stack.pushAny(padded2); // 50% of 30 = 15 rows

    const area = Rect.new(0, 0, 30, 30);
    stack.render(&buffer, area);

    // First widget (padded1): rows 0-14, padding=1
    // Padding at row 0, content at rows 1-13, padding at row 14
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(5, 0).?.char);
    try testing.expectEqual(@as(u21, '1'), buffer.getConst(5, 1).?.char);
    try testing.expectEqual(@as(u21, '1'), buffer.getConst(5, 13).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(5, 14).?.char);

    // Second widget (padded2): rows 15-29, padding=2
    // Padding at rows 15-16, content at rows 17-27, padding at rows 28-29
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(5, 15).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(5, 16).?.char);
    try testing.expectEqual(@as(u21, '2'), buffer.getConst(5, 17).?.char);
    try testing.expectEqual(@as(u21, '2'), buffer.getConst(5, 27).?.char);
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(5, 28).?.char);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "Padding on zero-size area renders nothing" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 10);
    defer buffer.deinit();

    const inner_widget = FillWidget{ .char = 'Z' };
    const padded = Padding(FillWidget).init(inner_widget, 1);

    const zero_area = Rect.new(5, 5, 0, 0);
    padded.render(&buffer, zero_area);

    // Should not crash, buffer remains default
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(5, 5).?.char);
}

test "Centered on zero-size area renders nothing" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 10, 10);
    defer buffer.deinit();

    const inner_widget = MeasuredWidget{ .pref_width = 5, .pref_height = 5, .char = 'X' };
    const centered = Centered(MeasuredWidget).init(inner_widget);

    const zero_area = Rect.new(0, 0, 0, 0);
    centered.render(&buffer, zero_area);

    // Should not crash
    try testing.expectEqual(@as(u21, ' '), buffer.getConst(0, 0).?.char);
}

test "Stack with single widget renders correctly" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 20, 10);
    defer buffer.deinit();

    var stack = try Stack.initVertical(allocator);
    defer stack.deinit();

    const widget = FillWidget{ .char = 'S' };
    try stack.push(widget);

    const area = Rect.new(0, 0, 20, 10);
    stack.render(&buffer, area);

    // Single widget takes entire area
    try testing.expectEqual(@as(u21, 'S'), buffer.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'S'), buffer.getConst(19, 9).?.char);
}

test "Constrained with no constraints renders unchanged" {
    const allocator = testing.allocator;
    var buffer = try Buffer.init(allocator, 30, 20);
    defer buffer.deinit();

    const inner_widget = FillWidget{ .char = 'U' };
    const constrained = Constrained(FillWidget).init(inner_widget, .{}); // no constraints

    const area = Rect.new(0, 0, 30, 20);
    constrained.render(&buffer, area);

    // No constraints: widget uses full area
    try testing.expectEqual(@as(u21, 'U'), buffer.getConst(0, 0).?.char);
    try testing.expectEqual(@as(u21, 'U'), buffer.getConst(29, 19).?.char);
}
