//! Particle effects system for TUI animations.
//!
//! Provides configurable particle systems for visual effects like fire, rain, snow, and sparkles.
//! All particles are rendered to a Buffer without using stdout directly.
//!
//! ## Features
//! - Multiple particle kinds (fire, rain, snow, sparkle)
//! - Physics-based particle movement and lifetime
//! - Fixed-size particle pool (no allocations during update/render)
//! - Deterministic spawning with seed control
//! - Bounds checking and area constraints
//!
//! ## Usage
//! ```zig
//! var system = try ParticleSystem.init(allocator, .fire, area, .{ .spawn_rate = 5 });
//! defer system.deinit();
//! system.update(delta_ms);
//! system.render(&buffer);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

const buffer_mod = @import("buffer.zig");
const Buffer = buffer_mod.Buffer;
const Cell = buffer_mod.Cell;

const layout_mod = @import("layout.zig");
const Rect = layout_mod.Rect;

const style_mod = @import("style.zig");
const Style = style_mod.Style;
const Color = style_mod.Color;

/// Particle effect type
pub const ParticleKind = enum {
    fire,    // Upward rising flame
    rain,    // Downward falling rain
    snow,    // Slow falling snow
    sparkle, // Static twinkling sparkles
};

/// Configuration for particle systems
pub const ParticleConfig = struct {
    spawn_rate: u8 = 5,           // particles to spawn per 100ms
    max_particles: u16 = 100,     // maximum active particles
    seed: u64 = 42,               // PRNG seed for determinism
};

/// Internal particle state (not public)
const Particle = struct {
    x: f32,                    // Float position for smooth movement
    y: f32,
    vx: f32,                   // Velocity
    vy: f32,
    lifetime_ms: f32,          // Remaining lifetime
    max_lifetime_ms: f32,      // Initial lifetime
    char: u21,                 // Unicode character to render
    color: Color,              // Color to render
    active: bool,              // Whether this particle is alive
};

/// Particle system manager
pub const ParticleSystem = struct {
    allocator: Allocator,
    particles: []Particle,           // Fixed pool of particles
    kind: ParticleKind,
    area: Rect,                      // Constrained area for spawning/rendering
    config: ParticleConfig,
    prng: std.Random.DefaultPrng,    // Deterministic random number generator
    spawn_accumulator: f32,          // Fractional spawn accumulation

    /// Initialize a new particle system
    pub fn init(allocator: Allocator, kind: ParticleKind, area: Rect, config: ParticleConfig) !ParticleSystem {
        const particles = try allocator.alloc(Particle, config.max_particles);
        for (particles) |*p| {
            p.active = false;
        }
        return .{
            .allocator = allocator,
            .particles = particles,
            .kind = kind,
            .area = area,
            .config = config,
            .prng = std.Random.DefaultPrng.init(config.seed),
            .spawn_accumulator = 0,
        };
    }

    /// Clean up particle system and free memory
    pub fn deinit(self: *ParticleSystem) void {
        self.allocator.free(self.particles);
    }

    /// Update particle system by delta_ms
    pub fn update(self: *ParticleSystem, delta_ms: u32) void {
        if (delta_ms == 0) return;
        if (self.area.width == 0 or self.area.height == 0) return;

        const delta_sec: f32 = @as(f32, @floatFromInt(delta_ms)) / 1000.0;
        const rng = self.prng.random();

        // Update existing particles
        for (self.particles) |*p| {
            if (!p.active) continue;

            p.x += p.vx * delta_sec;
            p.y += p.vy * delta_sec;
            p.lifetime_ms -= @as(f32, @floatFromInt(delta_ms));

            if (p.lifetime_ms <= 0) {
                p.active = false;
            }
        }

        // Spawn new particles
        if (self.config.spawn_rate > 0) {
            const spawn_count_f: f32 = @as(f32, @floatFromInt(self.config.spawn_rate)) *
                @as(f32, @floatFromInt(delta_ms)) / 100.0 +
                self.spawn_accumulator;

            const spawn_count: u32 = @intFromFloat(@floor(spawn_count_f));
            self.spawn_accumulator = spawn_count_f - @as(f32, @floatFromInt(spawn_count));

            var i: u32 = 0;
            while (i < spawn_count) : (i += 1) {
                // Find first inactive particle
                var spawned = false;
                for (self.particles) |*p| {
                    if (!p.active) {
                        self.spawnParticle(p, rng);
                        spawned = true;
                        break;
                    }
                }
                if (!spawned) break; // Pool full
            }
        }
    }

    /// Render all active particles to buffer
    pub fn render(self: *const ParticleSystem, buf: *Buffer) void {
        for (self.particles) |p| {
            if (!p.active) continue;

            // Convert float position to integer
            const ix = @as(i32, @intFromFloat(@round(p.x)));
            const iy = @as(i32, @intFromFloat(@round(p.y)));

            // Bounds check against area
            if (ix < self.area.x or ix >= self.area.x + self.area.width) continue;
            if (iy < self.area.y or iy >= self.area.y + self.area.height) continue;

            // Bounds check against buffer
            if (ix < 0 or ix >= buf.width) continue;
            if (iy < 0 or iy >= buf.height) continue;

            // Render particle
            const x: u16 = @intCast(ix);
            const y: u16 = @intCast(iy);
            buf.set(x, y, Cell.init(p.char, Style{ .fg = p.color }));
        }
    }

    /// Reset all particles to inactive state
    pub fn reset(self: *ParticleSystem) void {
        for (self.particles) |*p| {
            p.active = false;
        }
        self.spawn_accumulator = 0;
    }

    /// Get count of active particles
    pub fn activeCount(self: *const ParticleSystem) u32 {
        var count: u32 = 0;
        for (self.particles) |p| {
            if (p.active) count += 1;
        }
        return count;
    }

    /// Spawn a new particle (private helper)
    fn spawnParticle(self: *ParticleSystem, p: *Particle, rng: std.Random) void {
        const area_x_f: f32 = @floatFromInt(self.area.x);
        const area_y_f: f32 = @floatFromInt(self.area.y);
        const area_w_f: f32 = @floatFromInt(self.area.width);
        const area_h_f: f32 = @floatFromInt(self.area.height);

        switch (self.kind) {
            .fire => {
                // Spawn at bottom center area, move upward
                p.x = area_x_f + (rng.float(f32) * area_w_f);
                p.y = area_y_f + area_h_f - 1.0;
                p.vx = -0.5 + rng.float(f32) * 1.0; // -0.5 to +0.5
                p.vy = -1.5 - rng.float(f32) * 1.5; // -1.5 to -3.0
                p.max_lifetime_ms = 500.0 + rng.float(f32) * 1000.0; // 500-1500ms
                p.lifetime_ms = p.max_lifetime_ms;

                // Cycle through fire characters
                const fire_chars = [_]u21{ '^', '*', 0x00B7 }; // 0x00B7 = ·
                p.char = fire_chars[rng.intRangeLessThan(usize, 0, fire_chars.len)];

                // Cycle through fire colors
                const fire_colors = [_]Color{
                    Color.bright_yellow,
                    Color.yellow,
                    Color.red,
                    Color.bright_red,
                };
                p.color = fire_colors[rng.intRangeLessThan(usize, 0, fire_colors.len)];
            },

            .rain => {
                // Spawn at top, fall downward
                p.x = area_x_f + (rng.float(f32) * area_w_f);
                p.y = area_y_f;
                p.vx = 0.0;
                p.vy = 2.0 + rng.float(f32) * 2.0; // 2.0 to 4.0
                p.max_lifetime_ms = (area_h_f / p.vy) * 1000.0;
                p.lifetime_ms = p.max_lifetime_ms;

                const rain_chars = [_]u21{ '|', '\\', '/' };
                p.char = rain_chars[rng.intRangeLessThan(usize, 0, rain_chars.len)];
                p.color = Color.blue;
            },

            .snow => {
                // Spawn at top, fall slowly with drift
                p.x = area_x_f + (rng.float(f32) * area_w_f);
                p.y = area_y_f;
                p.vx = -0.3 + rng.float(f32) * 0.6; // -0.3 to +0.3
                p.vy = 0.5 + rng.float(f32) * 1.0;  // 0.5 to 1.5
                p.max_lifetime_ms = 2000.0 + rng.float(f32) * 2000.0; // 2000-4000ms
                p.lifetime_ms = p.max_lifetime_ms;

                const snow_chars = [_]u21{ '*', 0x00B7, 'o' }; // 0x00B7 = ·
                p.char = snow_chars[rng.intRangeLessThan(usize, 0, snow_chars.len)];
                p.color = Color.white;
            },

            .sparkle => {
                // Spawn at random position in area, no movement
                p.x = area_x_f + (rng.float(f32) * area_w_f);
                p.y = area_y_f + (rng.float(f32) * area_h_f);
                p.vx = 0.0;
                p.vy = 0.0;
                p.max_lifetime_ms = 200.0 + rng.float(f32) * 300.0; // 200-500ms
                p.lifetime_ms = p.max_lifetime_ms;

                const sparkle_chars = [_]u21{ '*', '+', 0x00B7 }; // 0x00B7 = ·
                p.char = sparkle_chars[rng.intRangeLessThan(usize, 0, sparkle_chars.len)];

                const sparkle_colors = [_]Color{
                    Color.bright_white,
                    Color.bright_yellow,
                };
                p.color = sparkle_colors[rng.intRangeLessThan(usize, 0, sparkle_colors.len)];
            },
        }

        p.active = true;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "particles: init and deinit success" {
    var sys = try ParticleSystem.init(std.testing.allocator, .fire, Rect{ .x = 0, .y = 0, .width = 80, .height = 24 }, .{});
    defer sys.deinit();
    try std.testing.expectEqual(@as(u32, 0), sys.activeCount());
}
