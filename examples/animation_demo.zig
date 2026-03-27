//! Animation Demo — Showcases sailor animation features (v1.24.0)
//!
//! Demonstrates:
//! - Easing functions (bounce, elastic, smooth cubic, exponential)
//! - Value animations with different easing curves
//! - Color animations with interpolation
//!
//! Run with: zig build example-animation_demo

const std = @import("std");
const sailor = @import("sailor");
const animation = sailor.tui.animation;
const Color = sailor.tui.style.Color;

pub fn main() !void {
    std.debug.print("=== Sailor Animation Demo (v1.24.0) ===\n\n", .{});

    // Demonstrate easing functions
    std.debug.print("Available Easing Functions (22 total):\n\n", .{});
    std.debug.print("  Basic: linear, easeIn, easeOut, easeInOut\n", .{});
    std.debug.print("  Cubic: easeInCubic, easeOutCubic, easeInOutCubic\n", .{});
    std.debug.print("  Elastic: easeInElastic, easeOutElastic, easeInOutElastic\n", .{});
    std.debug.print("  Bounce: easeInBounce, easeOutBounce, easeInOutBounce\n", .{});
    std.debug.print("  Back: easeInBack, easeOutBack, easeInOutBack\n", .{});
    std.debug.print("  Circ: easeInCirc, easeOutCirc, easeInOutCirc\n", .{});
    std.debug.print("  Expo: easeInExpo, easeOutExpo, easeInOutExpo\n\n", .{});

    // Test all easing functions
    std.debug.print("Testing easing functions at t=0.5:\n\n", .{});
    std.debug.print("  linear(0.5)        = {d:.3}\n", .{animation.linear(0.5)});
    std.debug.print("  easeInOut(0.5)     = {d:.3}\n", .{animation.easeInOut(0.5)});
    std.debug.print("  easeInOutCubic(0.5)= {d:.3}\n", .{animation.easeInOutCubic(0.5)});
    std.debug.print("  easeOutBounce(0.5) = {d:.3}\n", .{animation.easeOutBounce(0.5)});
    std.debug.print("  easeOutElastic(0.5)= {d:.3} (may overshoot)\n\n", .{animation.easeOutElastic(0.5)});

    // Create animations with different easing
    std.debug.print("Creating animations:\n", .{});
    const red = Color{ .rgb = .{ .r = 255, .g = 0, .b = 0 } };
    const blue = Color{ .rgb = .{ .r = 0, .g = 100, .b = 255 } };

    var bounce_anim = animation.Animation.init(0.0, 100.0, 1000, animation.easeOutBounce);
    var smooth_anim = animation.Animation.init(0.0, 100.0, 1000, animation.easeInOutCubic);
    var color_anim = animation.ColorAnimation.init(red, blue, 1000, animation.easeInOutCubic);

    const start_time = @as(u64, @intCast(std.time.milliTimestamp()));
    bounce_anim.begin(start_time);
    smooth_anim.begin(start_time);
    color_anim.begin(start_time);

    // Sample animations at different time points
    std.debug.print("\nAnimation values over time:\n\n", .{});
    std.debug.print("Time | Bounce | Smooth | Color (R)\n", .{});
    std.debug.print("-----|--------|--------|----------\n", .{});

    var i: u32 = 0;
    while (i <= 10) : (i += 1) {
        const t = start_time + i * 100; // 0ms to 1000ms in 100ms steps
        const bounce_val = bounce_anim.update(t);
        const smooth_val = smooth_anim.update(t);
        const current_color = color_anim.update(t);

        const red_component = if (current_color == .rgb) current_color.rgb.r else 0;

        std.debug.print("{d:>3}% | {d:>6.1} | {d:>6.1} | {d:>3}\n", .{
            i * 10,
            bounce_val,
            smooth_val,
            red_component,
        });
    }

    std.debug.print("\nAll animations complete!\n", .{});
    std.debug.print("\nFeatures demonstrated:\n", .{});
    std.debug.print("  ✓ Value interpolation (Animation struct)\n", .{});
    std.debug.print("  ✓ Color interpolation (ColorAnimation struct)\n", .{});
    std.debug.print("  ✓ Multiple easing functions\n", .{});
    std.debug.print("  ✓ Time-based animation control\n\n", .{});
}

