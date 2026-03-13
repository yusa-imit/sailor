const std = @import("std");
const tui = @import("../tui.zig");
const Buffer = tui.Buffer;
const Rect = tui.Rect;
const Color = tui.Color;
const Style = tui.Style;
const Cell = tui.Cell;

/// ParticleType defines different particle effects
pub const ParticleType = enum {
    confetti,
    sparkles,
    stars,
    hearts,
    snowflakes,
    bubbles,
    custom,
};

/// Particle represents a single animated particle
pub const Particle = struct {
    x: f32,
    y: f32,
    vx: f32, // velocity x
    vy: f32, // velocity y
    lifetime: u32, // frames remaining
    max_lifetime: u32,
    char: u21,
    color: Color,
    opacity: u8, // 0-255

    pub fn init(x: f32, y: f32, vx: f32, vy: f32, lifetime: u32, char: u21, color: Color) Particle {
        return .{
            .x = x,
            .y = y,
            .vx = vx,
            .vy = vy,
            .lifetime = lifetime,
            .max_lifetime = lifetime,
            .char = char,
            .color = color,
            .opacity = 255,
        };
    }

    pub fn update(self: *Particle, gravity: f32) bool {
        // Already dead - remove on next update
        if (self.lifetime == 0) return false;

        self.x += self.vx;
        self.y += self.vy;
        self.vy += gravity;

        // Decrement lifetime
        self.lifetime -= 1;

        // Fade out near end of life
        const life_ratio = @as(f32, @floatFromInt(self.lifetime)) / @as(f32, @floatFromInt(self.max_lifetime));
        self.opacity = @intFromFloat(life_ratio * 255.0);

        // Keep alive even when lifetime reaches 0 (will be removed on next update)
        return true;
    }
};

/// ParticleSystem manages a collection of particles
pub const ParticleSystem = struct {
    particles: std.ArrayList(Particle),
    particle_type: ParticleType,
    gravity: f32,
    spawn_rate: u32, // particles per spawn() call
    allocator: std.mem.Allocator,
    rng: std.Random.DefaultPrng,

    pub fn init(allocator: std.mem.Allocator, particle_type: ParticleType) !ParticleSystem {
        const rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
        return .{
            .particles = std.ArrayList(Particle){},
            .particle_type = particle_type,
            .gravity = 0.1,
            .spawn_rate = 5,
            .allocator = allocator,
            .rng = rng,
        };
    }

    pub fn deinit(self: *ParticleSystem) void {
        self.particles.deinit(self.allocator);
    }

    pub fn setGravity(self: *ParticleSystem, gravity: f32) void {
        self.gravity = gravity;
    }

    pub fn setSpawnRate(self: *ParticleSystem, rate: u32) void {
        self.spawn_rate = rate;
    }

    /// Spawn particles at the given position (creates spawn_rate particles)
    pub fn spawn(self: *ParticleSystem, x: u16, y: u16) !void {
        const fx = @as(f32, @floatFromInt(x));
        const fy = @as(f32, @floatFromInt(y));

        var i: u32 = 0;
        while (i < self.spawn_rate) : (i += 1) {
            const particle = try self.createParticle(fx, fy);
            try self.particles.append(self.allocator, particle);
        }
    }

    /// Spawn particles across an area (creates spawn_rate particles total)
    pub fn spawnArea(self: *ParticleSystem, area: Rect) !void {
        if (area.width == 0 or area.height == 0) return;

        const particle_count = self.spawn_rate;
        var i: u32 = 0;
        while (i < particle_count) : (i += 1) {
            const x = area.x + (self.rng.random().int(u16) % area.width);
            const y = area.y + (self.rng.random().int(u16) % area.height);
            const fx = @as(f32, @floatFromInt(x));
            const fy = @as(f32, @floatFromInt(y));
            const particle = try self.createParticle(fx, fy);
            try self.particles.append(self.allocator, particle);
        }
    }

    fn createParticle(self: *ParticleSystem, x: f32, y: f32) !Particle {
        const random = self.rng.random();

        // Random velocity
        const vx = (random.float(f32) - 0.5) * 2.0;
        const vy = (random.float(f32) - 0.5) * 2.0 - 1.0; // bias upward

        // Lifetime: 30-90 frames (0.5-1.5 seconds at 60fps)
        const lifetime = 30 + (random.int(u32) % 60);

        const char = self.getParticleChar();
        const color = self.getParticleColor(random);

        return Particle.init(x, y, vx, vy, lifetime, char, color);
    }

    fn getParticleChar(self: *ParticleSystem) u21 {
        const random = self.rng.random();
        return switch (self.particle_type) {
            .confetti => blk: {
                const chars = [_]u21{ '▪', '▫', '●', '○', '■', '□', '◆', '◇' };
                break :blk chars[random.int(usize) % chars.len];
            },
            .sparkles => blk: {
                const chars = [_]u21{ '✨', '⭐', '★', '✦', '✧', '⋆', '∗', '＊' };
                break :blk chars[random.int(usize) % chars.len];
            },
            .stars => blk: {
                const chars = [_]u21{ '⭐', '★', '☆', '✦', '✧' };
                break :blk chars[random.int(usize) % chars.len];
            },
            .hearts => blk: {
                const chars = [_]u21{ '❤', '♥', '💕', '💖', '💗', '💓' };
                break :blk chars[random.int(usize) % chars.len];
            },
            .snowflakes => blk: {
                const chars = [_]u21{ '❄', '❅', '❆', '＊', '✻', '✼' };
                break :blk chars[random.int(usize) % chars.len];
            },
            .bubbles => blk: {
                const chars = [_]u21{ '○', '◯', '◌', '◍', '◎' };
                break :blk chars[random.int(usize) % chars.len];
            },
            .custom => '*',
        };
    }

    fn getParticleColor(self: *ParticleSystem, random: std.Random) Color {
        return switch (self.particle_type) {
            .confetti => blk: {
                const colors = [_]Color{ .red, .green, .yellow, .blue, .magenta, .cyan };
                break :blk colors[random.int(usize) % colors.len];
            },
            .sparkles => .yellow,
            .stars => .yellow,
            .hearts => .red,
            .snowflakes => .white,
            .bubbles => .cyan,
            .custom => .white,
        };
    }

    /// Update all particles (physics simulation)
    pub fn update(self: *ParticleSystem) void {
        var i: usize = 0;
        while (i < self.particles.items.len) {
            var particle = &self.particles.items[i];
            if (particle.update(self.gravity)) {
                i += 1;
            } else {
                // Remove dead particle
                _ = self.particles.swapRemove(i);
            }
        }
    }

    /// Render particles to buffer
    pub fn render(self: *ParticleSystem, buf: *Buffer, area: Rect) void {
        for (self.particles.items) |particle| {
            const px = @as(i32, @intFromFloat(particle.x));
            const py = @as(i32, @intFromFloat(particle.y));

            // Check bounds
            if (px < 0 or py < 0) continue;
            const ux: u16 = @intCast(px);
            const uy: u16 = @intCast(py);

            if (ux < area.x or uy < area.y) continue;
            if (ux >= area.x + area.width or uy >= area.y + area.height) continue;

            // Apply opacity to color (simplified: just use normal color)
            const style = Style{
                .fg = particle.color,
                .bg = null,
                .bold = false,
                .dim = particle.opacity < 128,
                .italic = false,
                .underline = false,
            };

            const cell = Cell.init(particle.char, style);
            buf.set(ux, uy, cell);
        }
    }

    /// Get active particle count
    pub fn count(self: *ParticleSystem) usize {
        return self.particles.items.len;
    }

    /// Clear all particles
    pub fn clear(self: *ParticleSystem) void {
        self.particles.clearRetainingCapacity();
    }
};

// Tests
const testing = std.testing;

test "Particle.init and update" {
    var p = Particle.init(10.0, 10.0, 1.0, -2.0, 60, '*', .yellow);
    try testing.expectEqual(@as(f32, 10.0), p.x);
    try testing.expectEqual(@as(f32, 10.0), p.y);
    try testing.expectEqual(@as(u32, 60), p.lifetime);
    try testing.expectEqual(@as(u8, 255), p.opacity);

    // Update moves particle
    const alive = p.update(0.1);
    try testing.expect(alive);
    try testing.expectEqual(@as(f32, 11.0), p.x);
    try testing.expectEqual(@as(f32, 8.0), p.y); // 10 + (-2) = 8
    try testing.expectEqual(@as(u32, 59), p.lifetime);
}

test "Particle expires after lifetime" {
    var p = Particle.init(0.0, 0.0, 0.0, 0.0, 1, '*', .white);
    _ = p.update(0.0);
    try testing.expectEqual(@as(u32, 0), p.lifetime);

    const alive = p.update(0.0);
    try testing.expect(!alive);
}

test "Particle gravity affects velocity" {
    var p = Particle.init(0.0, 0.0, 0.0, 0.0, 60, '*', .white);
    const initial_vy = p.vy;

    _ = p.update(0.5);
    try testing.expectEqual(initial_vy + 0.5, p.vy);
}

test "ParticleSystem.init and deinit" {
    var sys = try ParticleSystem.init(testing.allocator, .confetti);
    defer sys.deinit();

    try testing.expectEqual(ParticleType.confetti, sys.particle_type);
    try testing.expectEqual(@as(usize, 0), sys.particles.items.len);
}

test "ParticleSystem.spawn creates particles" {
    var sys = try ParticleSystem.init(testing.allocator, .sparkles);
    defer sys.deinit();

    sys.setSpawnRate(3);
    try sys.spawn(10, 5);

    try testing.expectEqual(@as(usize, 3), sys.particles.items.len);
}

test "ParticleSystem.spawnArea" {
    var sys = try ParticleSystem.init(testing.allocator, .stars);
    defer sys.deinit();

    sys.setSpawnRate(10);
    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    try sys.spawnArea(area);

    try testing.expectEqual(@as(usize, 10), sys.particles.items.len);

    // Particles should be within area bounds
    for (sys.particles.items) |p| {
        try testing.expect(p.x >= 0.0 and p.x < 20.0);
        try testing.expect(p.y >= 0.0 and p.y < 10.0);
    }
}

test "ParticleSystem.spawnArea with zero area" {
    var sys = try ParticleSystem.init(testing.allocator, .hearts);
    defer sys.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };
    try sys.spawnArea(area);

    try testing.expectEqual(@as(usize, 0), sys.particles.items.len);
}

test "ParticleSystem.update removes dead particles" {
    var sys = try ParticleSystem.init(testing.allocator, .confetti);
    defer sys.deinit();

    // Create short-lived particles
    try sys.particles.append(sys.allocator, Particle.init(0.0, 0.0, 0.0, 0.0, 1, '*', .white));
    try sys.particles.append(sys.allocator, Particle.init(0.0, 0.0, 0.0, 0.0, 1, '*', .white));

    try testing.expectEqual(@as(usize, 2), sys.particles.items.len);

    sys.update(); // lifetime: 1 -> 0
    try testing.expectEqual(@as(usize, 2), sys.particles.items.len);

    sys.update(); // lifetime: 0 -> dead
    try testing.expectEqual(@as(usize, 0), sys.particles.items.len);
}

test "ParticleSystem.setGravity" {
    var sys = try ParticleSystem.init(testing.allocator, .snowflakes);
    defer sys.deinit();

    sys.setGravity(0.5);
    try testing.expectEqual(@as(f32, 0.5), sys.gravity);
}

test "ParticleSystem.setSpawnRate" {
    var sys = try ParticleSystem.init(testing.allocator, .bubbles);
    defer sys.deinit();

    sys.setSpawnRate(20);
    try testing.expectEqual(@as(u32, 20), sys.spawn_rate);
}

test "ParticleSystem.count" {
    var sys = try ParticleSystem.init(testing.allocator, .confetti);
    defer sys.deinit();

    try testing.expectEqual(@as(usize, 0), sys.count());

    try sys.spawn(10, 10);
    try testing.expect(sys.count() > 0);
}

test "ParticleSystem.clear" {
    var sys = try ParticleSystem.init(testing.allocator, .sparkles);
    defer sys.deinit();

    try sys.spawn(5, 5);
    try testing.expect(sys.count() > 0);

    sys.clear();
    try testing.expectEqual(@as(usize, 0), sys.count());
}

test "ParticleSystem.render to buffer" {
    var sys = try ParticleSystem.init(testing.allocator, .stars);
    defer sys.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    var buf = try Buffer.init(testing.allocator, area.width, area.height);
    defer buf.deinit();

    try sys.spawn(5, 5);
    sys.render(&buf, area);

    // At least one cell should be set
    var found = false;
    for (0..area.height) |y| {
        for (0..area.width) |x| {
            if (buf.get(@intCast(x), @intCast(y))) |cell| {
                if (cell.char != ' ') {
                    found = true;
                    break;
                }
            }
        }
    }
    try testing.expect(found);
}

test "ParticleSystem.render respects bounds" {
    var sys = try ParticleSystem.init(testing.allocator, .confetti);
    defer sys.deinit();

    // Create particle outside buffer
    try sys.particles.append(sys.allocator, Particle.init(100.0, 100.0, 0.0, 0.0, 60, '*', .white));

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    var buf = try Buffer.init(testing.allocator, area.width, area.height);
    defer buf.deinit();

    // Should not crash or write out of bounds
    sys.render(&buf, area);
}

test "ParticleType.confetti uses varied chars" {
    var sys = try ParticleSystem.init(testing.allocator, .confetti);
    defer sys.deinit();

    sys.setSpawnRate(20);
    try sys.spawn(10, 10);

    // Should have some variety in characters
    var chars = std.AutoHashMap(u21, void).init(testing.allocator);
    defer chars.deinit();

    for (sys.particles.items) |p| {
        try chars.put(p.char, {});
    }

    // With 20 particles, we should have at least 2 different chars
    try testing.expect(chars.count() >= 2);
}

test "ParticleType.sparkles uses sparkle chars" {
    var sys = try ParticleSystem.init(testing.allocator, .sparkles);
    defer sys.deinit();

    sys.setSpawnRate(10);
    try sys.spawn(10, 10);

    for (sys.particles.items) |p| {
        // All sparkle chars are > 127 (Unicode)
        try testing.expect(p.char > 127);
    }
}

test "ParticleType.hearts uses red color" {
    var sys = try ParticleSystem.init(testing.allocator, .hearts);
    defer sys.deinit();

    sys.setSpawnRate(10);
    try sys.spawn(10, 10);

    for (sys.particles.items) |p| {
        try testing.expectEqual(Color.red, p.color);
    }
}

test "ParticleType.snowflakes uses white color" {
    var sys = try ParticleSystem.init(testing.allocator, .snowflakes);
    defer sys.deinit();

    sys.setSpawnRate(10);
    try sys.spawn(10, 10);

    for (sys.particles.items) |p| {
        try testing.expectEqual(Color.white, p.color);
    }
}

test "Particle opacity fades over lifetime" {
    var p = Particle.init(0.0, 0.0, 0.0, 0.0, 10, '*', .white);

    try testing.expectEqual(@as(u8, 255), p.opacity);

    // After 5 updates (50% lifetime)
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        _ = p.update(0.0);
    }

    // Opacity should be around 127 (50% of 255)
    try testing.expect(p.opacity < 200);
    try testing.expect(p.opacity > 50);
}

test "ParticleSystem confetti uses varied colors" {
    var sys = try ParticleSystem.init(testing.allocator, .confetti);
    defer sys.deinit();

    sys.setSpawnRate(30);
    try sys.spawn(10, 10);

    // Should have multiple colors
    var colors = std.AutoHashMap(Color, void).init(testing.allocator);
    defer colors.deinit();

    for (sys.particles.items) |p| {
        try colors.put(p.color, {});
    }

    // With 30 confetti particles, expect at least 3 different colors
    try testing.expect(colors.count() >= 3);
}
