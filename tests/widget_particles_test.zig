const std = @import("std");
const sailor = @import("sailor");
const tui = sailor.tui;

// Widget ParticleSystem types (from src/tui/widgets/particles.zig)
const ParticleSystem = tui.widgets.ParticleSystem;
const Particle = tui.widgets.Particle;
const ParticleType = tui.widgets.ParticleType;
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Color = tui.Color;

const testing = std.testing;

test "ParticleSystem renders with normal gravity and positions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .confetti);
    defer sys.deinit();

    sys.setGravity(0.1);
    sys.setSpawnRate(1);
    try sys.spawn(10, 10);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // Should render without panic
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });

    try testing.expect(sys.count() >= 1);
}

test "ParticleSystem.render() does not panic with direct Particle.init() using extreme positive x" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .confetti);
    defer sys.deinit();

    // Create a particle with an extreme positive x value (1e20)
    // This bypasses spawn() and directly appends to particles
    const extreme_particle = Particle.init(1e20, 5.0, 0.0, 0.0, 100, '*', .white);
    try sys.particles.append(allocator, extreme_particle);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // This should NOT panic. Once fixed, render should clamp the value safely.
    // Before fix: panics with "integer part of floating point value out of bounds"
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "ParticleSystem.render() does not panic with direct Particle.init() using extreme negative x" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .confetti);
    defer sys.deinit();

    // Create a particle with an extreme negative x value (-1e20)
    const extreme_particle = Particle.init(-1e20, 5.0, 0.0, 0.0, 100, '*', .white);
    try sys.particles.append(allocator, extreme_particle);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // This should NOT panic. Once fixed, render should clamp safely.
    // Before fix: panics with "integer part of floating point value out of bounds"
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "ParticleSystem.render() does not panic with direct Particle.init() using extreme positive y" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .confetti);
    defer sys.deinit();

    // Create a particle with an extreme positive y value (1e20)
    const extreme_particle = Particle.init(5.0, 1e20, 0.0, 0.0, 100, '*', .white);
    try sys.particles.append(allocator, extreme_particle);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // This should NOT panic. Once fixed, render should clamp safely.
    // Before fix: panics with "integer part of floating point value out of bounds"
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "ParticleSystem.render() does not panic with direct Particle.init() using extreme negative y" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .confetti);
    defer sys.deinit();

    // Create a particle with an extreme negative y value (-1e20)
    const extreme_particle = Particle.init(5.0, -1e20, 0.0, 0.0, 100, '*', .white);
    try sys.particles.append(allocator, extreme_particle);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // This should NOT panic. Once fixed, render should clamp safely.
    // Before fix: panics with "integer part of floating point value out of bounds"
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "ParticleSystem.render() does not panic with extreme gravity accumulation (positive)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .confetti);
    defer sys.deinit();

    sys.setGravity(1e30);
    sys.setSpawnRate(1);
    try sys.spawn(5, 5);

    // First update: gravity accumulates into vy
    sys.update();
    // Second update: accumulated vy propagates into y
    sys.update();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // This should NOT panic. Once fixed, render should clamp safely.
    // Before fix: panics with "integer part of floating point value out of bounds"
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "ParticleSystem.render() does not panic with extreme gravity accumulation (negative)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .confetti);
    defer sys.deinit();

    sys.setGravity(-1e30);
    sys.setSpawnRate(1);
    try sys.spawn(5, 5);

    // First update: negative gravity accumulates into vy (upward)
    sys.update();
    // Second update: accumulated vy propagates into y (toward negative infinity)
    sys.update();

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // This should NOT panic. Once fixed, render should clamp safely.
    // Before fix: panics with "integer part of floating point value out of bounds"
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "ParticleSystem renders correctly with normal spawn and multiple updates" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .sparkles);
    defer sys.deinit();

    sys.setGravity(0.1);
    sys.setSpawnRate(3);
    try sys.spawn(40, 12);

    // Run several normal updates
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        sys.update();
    }

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // Should render without panic
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });

    try testing.expect(sys.count() > 0);
}

test "Particle.init() with extreme values stores them without truncation" {
    const extreme_x = 1e20;
    const extreme_y = -1e20;
    const p = Particle.init(extreme_x, extreme_y, 0.0, 0.0, 100, '*', .white);

    try testing.expectEqual(extreme_x, p.x);
    try testing.expectEqual(extreme_y, p.y);
}

test "ParticleSystem.render() bounds check prevents out-of-bounds casts" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .confetti);
    defer sys.deinit();

    // Mix of normal and extreme particles
    try sys.particles.append(allocator, Particle.init(10.0, 10.0, 0.0, 0.0, 100, '*', .white));
    try sys.particles.append(allocator, Particle.init(1e20, 1e20, 0.0, 0.0, 100, 'X', .white));
    try sys.particles.append(allocator, Particle.init(-1e20, -1e20, 0.0, 0.0, 100, 'Y', .white));

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // Should render safely without panic, skipping out-of-bounds particles
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });

    // Verify particle count unchanged (render never mutates particle count)
    try testing.expect(sys.count() == 3);

    // Verify that the in-bounds particle (10, 10) was actually drawn to the buffer
    const cell_at_10_10 = buf.getConst(10, 10);
    try testing.expect(cell_at_10_10 != null);
    try testing.expectEqual(@as(u21, '*'), cell_at_10_10.?.char);

    // Verify that the extreme particles were safely skipped (no panic, no out-of-bounds writes)
    // The buffer should remain valid and the in-bounds particle should be the only one drawn
    // (We don't need to exhaustively check every cell, but confirm buffer state is consistent)
    try testing.expect(buf.width == 80 and buf.height == 24);
}

test "ParticleSystem.render() does not panic with NaN particle x" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .confetti);
    defer sys.deinit();

    // Create a particle with NaN x value
    // After clamping via @max/@min (which are NaN-avoiding in Zig 0.15.2),
    // NaN should map to a finite clamped value, preventing panic at @intFromFloat
    const nan_particle = Particle.init(std.math.nan(f32), 5.0, 0.0, 0.0, 100, '*', .white);
    try sys.particles.append(allocator, nan_particle);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // This should NOT panic. NaN values should be safely clamped to finite range.
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "ParticleSystem.render() does not panic with NaN particle y" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .confetti);
    defer sys.deinit();

    // Create a particle with NaN y value
    const nan_particle = Particle.init(5.0, std.math.nan(f32), 0.0, 0.0, 100, '*', .white);
    try sys.particles.append(allocator, nan_particle);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // This should NOT panic. NaN values should be safely clamped to finite range.
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "ParticleSystem.render() does not panic with positive infinity particle x" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .confetti);
    defer sys.deinit();

    // Create a particle with +inf x value
    // Should be clamped to +999_999_999.0, which converts to i32 safely
    const inf_particle = Particle.init(std.math.inf(f32), 5.0, 0.0, 0.0, 100, '*', .white);
    try sys.particles.append(allocator, inf_particle);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // This should NOT panic. +inf should be clamped to safe range.
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "ParticleSystem.render() does not panic with positive infinity particle y" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .confetti);
    defer sys.deinit();

    // Create a particle with +inf y value
    const inf_particle = Particle.init(5.0, std.math.inf(f32), 0.0, 0.0, 100, '*', .white);
    try sys.particles.append(allocator, inf_particle);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // This should NOT panic. +inf should be clamped to safe range.
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "ParticleSystem.render() does not panic with negative infinity particle x" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .confetti);
    defer sys.deinit();

    // Create a particle with -inf x value
    // Should be clamped to -999_999_999.0, which converts to i32 safely
    const neg_inf_particle = Particle.init(-std.math.inf(f32), 5.0, 0.0, 0.0, 100, '*', .white);
    try sys.particles.append(allocator, neg_inf_particle);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // This should NOT panic. -inf should be clamped to safe range.
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}

test "ParticleSystem.render() does not panic with negative infinity particle y" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var sys = try ParticleSystem.init(allocator, .confetti);
    defer sys.deinit();

    // Create a particle with -inf y value
    const neg_inf_particle = Particle.init(5.0, -std.math.inf(f32), 0.0, 0.0, 100, '*', .white);
    try sys.particles.append(allocator, neg_inf_particle);

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    // This should NOT panic. -inf should be clamped to safe range.
    sys.render(&buf, .{ .x = 0, .y = 0, .width = 80, .height = 24 });
}
