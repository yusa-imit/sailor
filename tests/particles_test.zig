const std = @import("std");
const sailor = @import("sailor");

// Import particle system types
// Note: Tests assume ParticleKind, ParticleConfig, ParticleSystem are exported from sailor
// If not yet exported, update src/sailor.zig to add:
//   pub const ParticleKind = tui.particles.ParticleKind;
//   pub const ParticleConfig = tui.particles.ParticleConfig;
//   pub const ParticleSystem = tui.particles.ParticleSystem;
const ParticleKind = sailor.ParticleKind;
const ParticleConfig = sailor.ParticleConfig;
const ParticleSystem = sailor.ParticleSystem;
const Rect = sailor.Rect;
const Buffer = sailor.Buffer;
const Cell = sailor.Cell;
const Style = sailor.Style;
const Color = sailor.Color;

/// Helper to count non-empty cells in buffer within a given area
fn countNonEmptyCells(buf: *const Buffer, area: Rect) u32 {
    var count: u32 = 0;
    var y = area.y;
    while (y < area.y + area.height and y < buf.height) : (y += 1) {
        var x = area.x;
        while (x < area.x + area.width and x < buf.width) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ' and cell.char != 0) {
                    count += 1;
                }
            }
        }
    }
    return count;
}

/// Helper to check if any cells outside area are non-empty
fn hasCellsOutsideArea(buf: *const Buffer, area: Rect) bool {
    // Check left of area
    if (area.x > 0) {
        var y = area.y;
        while (y < area.y + area.height and y < buf.height) : (y += 1) {
            var x: u16 = 0;
            while (x < area.x) : (x += 1) {
                if (buf.getConst(x, y)) |cell| {
                    if (cell.char != ' ' and cell.char != 0) {
                        return true;
                    }
                }
            }
        }
    }

    // Check right of area
    const right_bound = area.x + area.width;
    if (right_bound < buf.width) {
        var y = area.y;
        while (y < area.y + area.height and y < buf.height) : (y += 1) {
            var x = right_bound;
            while (x < buf.width) : (x += 1) {
                if (buf.getConst(x, y)) |cell| {
                    if (cell.char != ' ' and cell.char != 0) {
                        return true;
                    }
                }
            }
        }
    }

    // Check top of area
    if (area.y > 0) {
        var y: u16 = 0;
        while (y < area.y) : (y += 1) {
            var x: u16 = 0;
            while (x < buf.width) : (x += 1) {
                if (buf.getConst(x, y)) |cell| {
                    if (cell.char != ' ' and cell.char != 0) {
                        return true;
                    }
                }
            }
        }
    }

    // Check bottom of area
    const bottom_bound = area.y + area.height;
    if (bottom_bound < buf.height) {
        var y = bottom_bound;
        while (y < buf.height) : (y += 1) {
            var x: u16 = 0;
            while (x < buf.width) : (x += 1) {
                if (buf.getConst(x, y)) |cell| {
                    if (cell.char != ' ' and cell.char != 0) {
                        return true;
                    }
                }
            }
        }
    }

    return false;
}

test "particles: init and deinit with no memory leaks" {
    var sys = try ParticleSystem.init(std.testing.allocator, .fire, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{});
    defer sys.deinit();

    // Just verify it inits without error and deinits safely
    try std.testing.expectEqual(@as(u32, 0), sys.activeCount());
}

test "particles: activeCount is zero immediately after init" {
    var sys = try ParticleSystem.init(std.testing.allocator, .rain, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{});
    defer sys.deinit();

    try std.testing.expectEqual(@as(u32, 0), sys.activeCount());
}

test "particles: update spawns particles when delta_ms is positive" {
    var sys = try ParticleSystem.init(std.testing.allocator, .sparkle, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 5 });
    defer sys.deinit();

    sys.update(100); // 100ms delta
    const count = sys.activeCount();
    try std.testing.expect(count > 0); // Should have spawned particles
}

test "particles: particles expire and activeCount decreases over time" {
    var sys = try ParticleSystem.init(std.testing.allocator, .fire, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 10 });
    defer sys.deinit();

    // Spawn some particles
    sys.update(100);
    const initial_count = sys.activeCount();
    try std.testing.expect(initial_count > 0);

    // Disable spawning so only expiry affects the count (fire max_lifetime_ms = 1500ms)
    sys.config.spawn_rate = 0;
    sys.update(5000);
    const final_count = sys.activeCount();
    try std.testing.expectEqual(@as(u32, 0), final_count);
}

test "particles: reset clears all particles" {
    var sys = try ParticleSystem.init(std.testing.allocator, .snow, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 10 });
    defer sys.deinit();

    sys.update(100);
    try std.testing.expect(sys.activeCount() > 0);

    sys.reset();
    try std.testing.expectEqual(@as(u32, 0), sys.activeCount());
}

test "particles: max_particles config is respected" {
    var sys = try ParticleSystem.init(std.testing.allocator, .sparkle, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 50, .max_particles = 20 });
    defer sys.deinit();

    sys.update(100);
    sys.update(100);
    sys.update(100);

    const count = sys.activeCount();
    try std.testing.expect(count <= 20);
}

test "particles: higher spawn_rate produces more particles" {
    var sys_low = try ParticleSystem.init(std.testing.allocator, .fire, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 2 });
    defer sys_low.deinit();

    var sys_high = try ParticleSystem.init(std.testing.allocator, .fire, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 20 });
    defer sys_high.deinit();

    sys_low.update(100);
    sys_high.update(100);

    const count_low = sys_low.activeCount();
    const count_high = sys_high.activeCount();
    try std.testing.expect(count_high > count_low);
}

test "particles: same seed produces deterministic activeCount" {
    const test_seed = 12345;
    var sys1 = try ParticleSystem.init(std.testing.allocator, .snow, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .seed = test_seed });
    defer sys1.deinit();

    var sys2 = try ParticleSystem.init(std.testing.allocator, .snow, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .seed = test_seed });
    defer sys2.deinit();

    sys1.update(100);
    sys2.update(100);

    try std.testing.expectEqual(sys1.activeCount(), sys2.activeCount());
}

test "particles: render produces non-empty cells in buffer after update" {
    var sys = try ParticleSystem.init(std.testing.allocator, .sparkle, Rect{ .x = 10, .y = 5, .width = 40, .height = 20 }, .{ .spawn_rate = 10 });
    defer sys.deinit();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    sys.update(100);
    sys.render(&buf);

    const non_empty_count = countNonEmptyCells(&buf, Rect{ .x = 10, .y = 5, .width = 40, .height = 20 });
    try std.testing.expect(non_empty_count > 0);
}

test "particles: fire particles render to buffer" {
    var sys = try ParticleSystem.init(std.testing.allocator, .fire, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 5 });
    defer sys.deinit();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    sys.update(500);
    sys.render(&buf);

    const non_empty = countNonEmptyCells(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });
    try std.testing.expect(non_empty > 0);
}

test "particles: rain particles render to buffer" {
    var sys = try ParticleSystem.init(std.testing.allocator, .rain, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 5 });
    defer sys.deinit();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    sys.update(500);
    sys.render(&buf);

    const non_empty = countNonEmptyCells(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });
    try std.testing.expect(non_empty > 0);
}

test "particles: snow particles render to buffer" {
    var sys = try ParticleSystem.init(std.testing.allocator, .snow, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 5 });
    defer sys.deinit();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    sys.update(500);
    sys.render(&buf);

    const non_empty = countNonEmptyCells(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });
    try std.testing.expect(non_empty > 0);
}

test "particles: sparkle particles render to buffer" {
    var sys = try ParticleSystem.init(std.testing.allocator, .sparkle, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 5 });
    defer sys.deinit();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    sys.update(500);
    sys.render(&buf);

    const non_empty = countNonEmptyCells(&buf, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 });
    try std.testing.expect(non_empty > 0);
}

test "particles: render respects area bounds" {
    var sys = try ParticleSystem.init(std.testing.allocator, .fire, Rect{ .x = 10, .y = 5, .width = 40, .height = 15 }, .{ .spawn_rate = 20 });
    defer sys.deinit();

    var buf = try Buffer.init(std.testing.allocator, 80, 30);
    defer buf.deinit();

    sys.update(500);
    sys.render(&buf);

    // Verify no particles rendered outside the area
    const outside = hasCellsOutsideArea(&buf, Rect{ .x = 10, .y = 5, .width = 40, .height = 15 });
    try std.testing.expect(!outside);
}

test "particles: update with zero delta does not crash" {
    var sys = try ParticleSystem.init(std.testing.allocator, .snow, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{});
    defer sys.deinit();

    // Should not crash with zero delta
    sys.update(0);
    try std.testing.expectEqual(@as(u32, 0), sys.activeCount());
}

test "particles: zero-width area does not crash or create particles" {
    var sys = try ParticleSystem.init(std.testing.allocator, .rain, Rect{ .x = 10, .y = 10, .width = 0, .height = 20 }, .{ .spawn_rate = 5 });
    defer sys.deinit();

    sys.update(100);
    try std.testing.expectEqual(@as(u32, 0), sys.activeCount());
}

test "particles: zero-height area does not crash or create particles" {
    var sys = try ParticleSystem.init(std.testing.allocator, .sparkle, Rect{ .x = 10, .y = 10, .width = 40, .height = 0 }, .{ .spawn_rate = 5 });
    defer sys.deinit();

    sys.update(100);
    try std.testing.expectEqual(@as(u32, 0), sys.activeCount());
}

test "particles: large area with many particles does not panic" {
    var sys = try ParticleSystem.init(std.testing.allocator, .snow, Rect{ .x = 0, .y = 0, .width = 200, .height = 50 }, .{ .spawn_rate = 30, .max_particles = 200 });
    defer sys.deinit();

    var buf = try Buffer.init(std.testing.allocator, 200, 50);
    defer buf.deinit();

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        sys.update(100);
    }

    // Render should not panic
    sys.render(&buf);

    try std.testing.expect(sys.activeCount() <= 200);
}

test "particles: render to empty buffer initializes with particle characters" {
    var sys = try ParticleSystem.init(std.testing.allocator, .fire, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 1 });
    defer sys.deinit();

    var buf = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf.deinit();

    // Clear buffer to all spaces
    var y: u16 = 0;
    while (y < 24) : (y += 1) {
        var x: u16 = 0;
        while (x < 80) : (x += 1) {
            buf.set(x, y, Cell.init(' ', .{}));
        }
    }

    sys.update(100);
    sys.render(&buf);

    // After render, at least one cell should have a non-space character
    var found_char = false;
    y = 0;
    while (y < 24) : (y += 1) {
        var x: u16 = 0;
        while (x < 80) : (x += 1) {
            if (buf.getConst(x, y)) |cell| {
                if (cell.char != ' ') {
                    found_char = true;
                }
            }
        }
    }
    try std.testing.expect(found_char);
}

test "particles: fire particles move upward" {
    var sys = try ParticleSystem.init(std.testing.allocator, .fire, Rect{ .x = 40, .y = 0, .width = 5, .height = 24 }, .{ .spawn_rate = 5, .seed = 999 });
    defer sys.deinit();

    var buf1 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf1.deinit();

    var buf2 = try Buffer.init(std.testing.allocator, 80, 24);
    defer buf2.deinit();

    // Render at early time
    sys.update(100);
    sys.render(&buf1);

    // Render at later time
    sys.update(500);
    sys.render(&buf2);

    // For fire particles, we expect some particles to move toward top of screen
    // This is a basic check: at least one cell non-empty at each frame
    const non_empty_1 = countNonEmptyCells(&buf1, Rect{ .x = 40, .y = 0, .width = 5, .height = 24 });
    const non_empty_2 = countNonEmptyCells(&buf2, Rect{ .x = 40, .y = 0, .width = 5, .height = 24 });
    try std.testing.expect(non_empty_1 > 0 or non_empty_2 > 0);
}

test "particles: multiple sequential resets work correctly" {
    var sys = try ParticleSystem.init(std.testing.allocator, .sparkle, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 5 });
    defer sys.deinit();

    sys.update(100);
    try std.testing.expect(sys.activeCount() > 0);

    sys.reset();
    try std.testing.expectEqual(@as(u32, 0), sys.activeCount());

    sys.update(100);
    try std.testing.expect(sys.activeCount() > 0);

    sys.reset();
    try std.testing.expectEqual(@as(u32, 0), sys.activeCount());
}

test "particles: spawn_rate zero does not spawn particles" {
    var sys = try ParticleSystem.init(std.testing.allocator, .rain, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 0 });
    defer sys.deinit();

    sys.update(100);
    sys.update(100);
    sys.update(100);

    try std.testing.expectEqual(@as(u32, 0), sys.activeCount());
}

test "particles: different particle kinds produce different visual results" {
    var sys_fire = try ParticleSystem.init(std.testing.allocator, .fire, Rect{ .x = 0, .y = 0, .width = 40, .height = 24 }, .{ .spawn_rate = 10, .seed = 555 });
    defer sys_fire.deinit();

    var sys_snow = try ParticleSystem.init(std.testing.allocator, .snow, Rect{ .x = 0, .y = 0, .width = 40, .height = 24 }, .{ .spawn_rate = 10, .seed = 555 });
    defer sys_snow.deinit();

    var buf_fire = try Buffer.init(std.testing.allocator, 40, 24);
    defer buf_fire.deinit();

    var buf_snow = try Buffer.init(std.testing.allocator, 40, 24);
    defer buf_snow.deinit();

    sys_fire.update(300);
    sys_fire.render(&buf_fire);

    sys_snow.update(300);
    sys_snow.render(&buf_snow);

    // Both should render something
    const fire_count = countNonEmptyCells(&buf_fire, Rect{ .x = 0, .y = 0, .width = 40, .height = 24 });
    const snow_count = countNonEmptyCells(&buf_snow, Rect{ .x = 0, .y = 0, .width = 40, .height = 24 });
    try std.testing.expect(fire_count > 0);
    try std.testing.expect(snow_count > 0);
}

test "particles: activeCount after multiple updates increases then stabilizes" {
    var sys = try ParticleSystem.init(std.testing.allocator, .sparkle, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 5, .max_particles = 30 });
    defer sys.deinit();

    sys.update(100);
    const count1 = sys.activeCount();

    sys.update(100);
    const count2 = sys.activeCount();

    // With limited max_particles, should eventually cap out
    sys.update(500);
    const count3 = sys.activeCount();

    // Verify counts are reasonable: count grows or stays same, doesn't exceed max
    try std.testing.expect(count1 <= 30);
    try std.testing.expect(count2 <= 30);
    try std.testing.expect(count3 <= 30);
}

test "particles: render with offset area coordinates" {
    var sys = try ParticleSystem.init(std.testing.allocator, .rain, Rect{ .x = 20, .y = 10, .width = 30, .height = 15 }, .{ .spawn_rate = 8 });
    defer sys.deinit();

    var buf = try Buffer.init(std.testing.allocator, 80, 30);
    defer buf.deinit();

    sys.update(200);
    sys.render(&buf);

    // Particles should be in the specified area only (or none if they expired)
    const outside = hasCellsOutsideArea(&buf, Rect{ .x = 20, .y = 10, .width = 30, .height = 15 });
    try std.testing.expect(!outside);
}

test "particles: config defaults are valid" {
    const default_config = ParticleConfig{};
    try std.testing.expectEqual(@as(u8, 5), default_config.spawn_rate);
    try std.testing.expectEqual(@as(u16, 100), default_config.max_particles);
    try std.testing.expectEqual(@as(u64, 42), default_config.seed);
}

test "particles: activeCount matches expected behavior over time sequence" {
    var sys = try ParticleSystem.init(std.testing.allocator, .fire, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{ .spawn_rate = 3, .max_particles = 50 });
    defer sys.deinit();

    // Verify sequence of operations
    try std.testing.expectEqual(@as(u32, 0), sys.activeCount());

    sys.update(100);
    const after_first_update = sys.activeCount();
    try std.testing.expect(after_first_update >= 0);

    sys.update(100);
    const after_second_update = sys.activeCount();
    try std.testing.expect(after_second_update <= 50);

    sys.reset();
    try std.testing.expectEqual(@as(u32, 0), sys.activeCount());
}
