//! Audit coverage for core public functions in term, color, arg, repl, progress, fmt, buffer, layout, tui, async_loop
//! This file fills gaps in test coverage for functions that exist but lack direct tests.

const std = @import("std");
const sailor = @import("sailor");
const layout = sailor.tui.layout;
const Rect = layout.Rect;
const Constraint = layout.Constraint;
const Margin = layout.Margin;
const Padding = layout.Padding;
const Direction = layout.Direction;

// ============================================================================
// Rect ergonomic helpers tests
// ============================================================================

test "Rect.fromSize creates zero-origin rectangle" {
    const r = Rect.fromSize(80, 24);
    try std.testing.expectEqual(@as(u16, 0), r.x);
    try std.testing.expectEqual(@as(u16, 0), r.y);
    try std.testing.expectEqual(@as(u16, 80), r.width);
    try std.testing.expectEqual(@as(u16, 24), r.height);
}

test "Rect.withMargin applies margins correctly" {
    const r = Rect{ .x = 10, .y = 10, .width = 50, .height = 50 };
    const margin = Margin{ .top = 5, .right = 3, .bottom = 5, .left = 2 };
    const inner = r.withMargin(margin);

    try std.testing.expectEqual(@as(u16, 12), inner.x); // 10 + 2
    try std.testing.expectEqual(@as(u16, 15), inner.y); // 10 + 5
    try std.testing.expectEqual(@as(u16, 45), inner.width); // 50 - (2 + 3)
    try std.testing.expectEqual(@as(u16, 40), inner.height); // 50 - (5 + 5)
}

test "Rect.withMargin handles underflow" {
    const r = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const margin = Margin{ .top = 20, .right = 20, .bottom = 20, .left = 20 };
    const inner = r.withMargin(margin);

    try std.testing.expectEqual(@as(u16, 0), inner.width); // Clamped to 0
    try std.testing.expectEqual(@as(u16, 0), inner.height); // Clamped to 0
}

test "Rect.withPadding applies padding correctly" {
    const r = Rect{ .x = 5, .y = 5, .width = 60, .height = 40 };
    const padding = Padding{ .top = 2, .right = 4, .bottom = 2, .left = 3 };
    const inner = r.withPadding(padding);

    try std.testing.expectEqual(@as(u16, 8), inner.x); // 5 + 3
    try std.testing.expectEqual(@as(u16, 7), inner.y); // 5 + 2
    try std.testing.expectEqual(@as(u16, 53), inner.width); // 60 - (3 + 4)
    try std.testing.expectEqual(@as(u16, 36), inner.height); // 40 - (2 + 2)
}

test "Rect.withAspectRatio maintains aspect ratio within bounds" {
    // 100x100 area, 16:9 aspect ratio
    const r = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const result = r.withAspectRatio(.{ .width = 16, .height = 9 });

    // Should maintain 16:9; width-constrained: height = (100 * 9) / 16 = 56.25 -> 56
    try std.testing.expectEqual(@as(u16, 100), result.width);
    try std.testing.expect(result.height <= 100);
    // Verify aspect ratio is respected (within rounding): (width * height_ratio) / width_ratio ≈ height
    const calc_height = (100 * 9) / 16;
    try std.testing.expectEqual(@as(u16, @intCast(calc_height)), result.height);
}

test "Rect.withAspectRatio handles height-constrained case" {
    // 50x100 area, 1:1 aspect ratio (square)
    const r = Rect{ .x = 0, .y = 0, .width = 50, .height = 100 };
    const result = r.withAspectRatio(.{ .width = 1, .height = 1 });

    // Should be constrained by width (narrower dimension)
    try std.testing.expectEqual(@as(u16, 50), result.width);
    try std.testing.expectEqual(@as(u16, 50), result.height);
}

test "Rect.debugFormat writes rectangle info" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const r = Rect{ .x = 10, .y = 20, .width = 30, .height = 40 };

    try r.debugFormat(stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "x=10") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "y=20") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "width=30") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "height=40") != null);
}

// ============================================================================
// Constraint convenience constructors tests
// ============================================================================

test "Constraint.len creates fixed-length constraint" {
    const c = Constraint.len(50);
    try std.testing.expectEqual(@as(u16, 50), c.apply(100));
    try std.testing.expectEqual(@as(u16, 30), c.apply(30)); // Clamped to available
}

test "Constraint.pct creates percentage constraint" {
    const c = Constraint.pct(50);
    try std.testing.expectEqual(@as(u16, 50), c.apply(100));
    try std.testing.expectEqual(@as(u16, 25), c.apply(50));
}

test "Constraint.pct clamps to 100" {
    const c = Constraint.pct(150);
    try std.testing.expectEqual(@as(u16, 100), c.apply(100));
}

test "Constraint.rat creates ratio constraint" {
    const c = Constraint.rat(1, 2);
    try std.testing.expectEqual(@as(u16, 50), c.apply(100));
    try std.testing.expectEqual(@as(u16, 30), c.apply(60));
}

test "Constraint.rat handles zero denominator" {
    const c = Constraint.rat(1, 0);
    try std.testing.expectEqual(@as(u16, 0), c.apply(100));
}

test "Constraint.minimum creates min constraint" {
    const c = Constraint.minimum(20);
    try std.testing.expectEqual(@as(u16, 20), c.apply(100));
    try std.testing.expectEqual(@as(u16, 10), c.apply(10)); // Clamped to available
}

test "Constraint.maximum creates max constraint" {
    const c = Constraint.maximum(80);
    try std.testing.expectEqual(@as(u16, 80), c.apply(100));
    try std.testing.expectEqual(@as(u16, 50), c.apply(50));
}

test "Constraint.aspect creates aspect ratio constraint" {
    const c = Constraint.aspect(16, 9);
    // Aspect ratio constraints return available space (caller uses Rect.withAspectRatio)
    try std.testing.expectEqual(@as(u16, 100), c.apply(100));
}

test "Constraint.aspect handles zero dimensions" {
    const c = Constraint.aspect(0, 9);
    try std.testing.expectEqual(@as(u16, 0), c.apply(100));

    const c2 = Constraint.aspect(16, 0);
    try std.testing.expectEqual(@as(u16, 0), c2.apply(100));
}

// ============================================================================
// Margin and Padding helper tests
// ============================================================================

test "Margin.all creates uniform margin" {
    const m = Margin.all(5);
    try std.testing.expectEqual(@as(u16, 5), m.top);
    try std.testing.expectEqual(@as(u16, 5), m.right);
    try std.testing.expectEqual(@as(u16, 5), m.bottom);
    try std.testing.expectEqual(@as(u16, 5), m.left);
}

test "Margin.symmetric creates symmetric margin" {
    const m = Margin.symmetric(3, 7);
    try std.testing.expectEqual(@as(u16, 3), m.top);
    try std.testing.expectEqual(@as(u16, 7), m.right);
    try std.testing.expectEqual(@as(u16, 3), m.bottom);
    try std.testing.expectEqual(@as(u16, 7), m.left);
}

test "Padding.all creates uniform padding" {
    const p = Padding.all(4);
    try std.testing.expectEqual(@as(u16, 4), p.top);
    try std.testing.expectEqual(@as(u16, 4), p.right);
    try std.testing.expectEqual(@as(u16, 4), p.bottom);
    try std.testing.expectEqual(@as(u16, 4), p.left);
}

test "Padding.symmetric creates symmetric padding" {
    const p = Padding.symmetric(2, 6);
    try std.testing.expectEqual(@as(u16, 2), p.top);
    try std.testing.expectEqual(@as(u16, 6), p.right);
    try std.testing.expectEqual(@as(u16, 2), p.bottom);
    try std.testing.expectEqual(@as(u16, 6), p.left);
}

// ============================================================================
// Rect geometric operations tests
// ============================================================================

test "Rect.contains checks point membership" {
    const r = Rect{ .x = 10, .y = 10, .width = 20, .height = 20 };

    try std.testing.expect(r.contains(10, 10)); // Top-left
    try std.testing.expect(r.contains(29, 29)); // Bottom-right (exclusive)
    try std.testing.expect(!r.contains(9, 15)); // Left edge (exclusive)
    try std.testing.expect(!r.contains(15, 30)); // Below bottom edge
}

test "Rect.intersects detects overlap" {
    const r1 = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const r2 = Rect{ .x = 5, .y = 5, .width = 10, .height = 10 };
    const r3 = Rect{ .x = 20, .y = 20, .width = 10, .height = 10 };

    try std.testing.expect(r1.intersects(r2)); // Overlapping
    try std.testing.expect(!r1.intersects(r3)); // No overlap
}

test "Rect.intersection computes overlap region" {
    const r1 = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const r2 = Rect{ .x = 5, .y = 5, .width = 10, .height = 10 };

    const inter = r1.intersection(r2).?;
    try std.testing.expectEqual(@as(u16, 5), inter.x);
    try std.testing.expectEqual(@as(u16, 5), inter.y);
    try std.testing.expectEqual(@as(u16, 5), inter.width);
    try std.testing.expectEqual(@as(u16, 5), inter.height);
}

test "Rect.intersection returns null for non-overlapping" {
    const r1 = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const r2 = Rect{ .x = 20, .y = 20, .width = 10, .height = 10 };

    try std.testing.expectEqual(@as(?Rect, null), r1.intersection(r2));
}

test "Rect.area calculates dimensions product" {
    const r = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try std.testing.expectEqual(@as(u32, 1920), r.area());
}

test "Rect.inner applies uniform inward margin" {
    const r = Rect{ .x = 10, .y = 10, .width = 50, .height = 50 };
    const inner = r.inner(5);

    try std.testing.expectEqual(@as(u16, 15), inner.x); // 10 + 5
    try std.testing.expectEqual(@as(u16, 15), inner.y); // 10 + 5
    try std.testing.expectEqual(@as(u16, 40), inner.width); // 50 - (5*2)
    try std.testing.expectEqual(@as(u16, 40), inner.height); // 50 - (5*2)
}

test "Rect.inner handles underflow" {
    const r = Rect{ .x = 0, .y = 0, .width = 8, .height = 8 };
    const inner = r.inner(10);

    try std.testing.expectEqual(@as(u16, 0), inner.width); // Underflow -> 0
    try std.testing.expectEqual(@as(u16, 0), inner.height);
}

// ============================================================================
// Layout split with constraints tests (basic validation)
// ============================================================================

test "layout.split with percentage constraints" {
    const allocator = std.testing.allocator;
    const area = Rect.fromSize(100, 50);
    const constraints = [_]Constraint{
        .{ .percentage = 30 },
        .{ .percentage = 70 },
    };

    const chunks = try layout.split(allocator, .horizontal, area, &constraints);
    defer allocator.free(chunks);

    try std.testing.expectEqual(@as(usize, 2), chunks.len);
    try std.testing.expectEqual(@as(u16, 30), chunks[0].width);
    try std.testing.expectEqual(@as(u16, 70), chunks[1].width);
}

test "layout.split with fixed-length constraints" {
    const allocator = std.testing.allocator;
    const area = Rect.fromSize(100, 50);
    const constraints = [_]Constraint{
        .{ .length = 20 },
        .{ .length = 30 },
    };

    const chunks = try layout.split(allocator, .vertical, area, &constraints);
    defer allocator.free(chunks);

    try std.testing.expectEqual(@as(usize, 2), chunks.len);
    try std.testing.expectEqual(@as(u16, 20), chunks[0].height);
    try std.testing.expectEqual(@as(u16, 30), chunks[1].height);
}

test "layout.split empty constraints" {
    const allocator = std.testing.allocator;
    const area = Rect.fromSize(100, 50);
    const constraints: [0]Constraint = .{};

    const chunks = try layout.split(allocator, .horizontal, area, &constraints);
    try std.testing.expectEqual(@as(usize, 0), chunks.len);
    if (chunks.len > 0) allocator.free(chunks);
}
