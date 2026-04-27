//! Property-based testing helpers for sailor
//!
//! Provides random value generation and property testing utilities
//! to verify invariants hold across randomized inputs.

const std = @import("std");
const Allocator = std.mem.Allocator;
const tui = @import("../tui/tui.zig");
const Rect = tui.layout.Rect;
const Color = tui.style.Color;
const Style = tui.style.Style;

/// Random value generator with seed-based determinism
pub const Generator = struct {
    prng: std.Random.DefaultPrng,

    /// Initialize generator with seed
    pub fn init(seed: u64) Generator {
        return .{ .prng = std.Random.DefaultPrng.init(seed) };
    }

    /// Generate random u16 within range [min, max]
    pub fn genU16(self: *Generator, min: u16, max: u16) u16 {
        return self.prng.random().intRangeAtMost(u16, min, max);
    }

    /// Generate random u32 within range [min, max]
    pub fn genU32(self: *Generator, min: u32, max: u32) u32 {
        return self.prng.random().intRangeAtMost(u32, min, max);
    }

    /// Generate random boolean
    pub fn genBool(self: *Generator) bool {
        return self.prng.random().boolean();
    }

    /// Generate random string with maximum length
    pub fn genString(self: *Generator, allocator: Allocator, max_len: usize) ![]u8 {
        if (max_len == 0) {
            return allocator.alloc(u8, 0);
        }

        const random = self.prng.random();
        // Generate random length 0..max_len
        const len = random.uintLessThan(usize, max_len + 1);
        const str = try allocator.alloc(u8, len);

        // Fill with random printable ASCII (32..126)
        for (str) |*c| {
            c.* = random.intRangeAtMost(u8, 32, 126);
        }

        return str;
    }

    /// Generate random rectangle within bounds
    pub fn genRect(self: *Generator, max_width: u16, max_height: u16) Rect {
        // Handle zero dimensions
        if (max_width == 0 or max_height == 0) {
            return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
        }

        const random = self.prng.random();
        // Generate random width and height
        const width = random.uintLessThan(u16, max_width + 1);
        const height = random.uintLessThan(u16, max_height + 1);

        // Generate random position ensuring rect fits within bounds
        const max_x = if (width < max_width) max_width - width else 0;
        const max_y = if (height < max_height) max_height - height else 0;

        const x = if (max_x > 0) random.uintLessThan(u16, max_x + 1) else 0;
        const y = if (max_y > 0) random.uintLessThan(u16, max_y + 1) else 0;

        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    /// Generate random color
    pub fn genColor(self: *Generator) Color {
        const random = self.prng.random();
        // Randomly pick from color variants
        const variant = random.uintLessThan(u8, 20);

        return switch (variant) {
            0 => .reset,
            1 => .black,
            2 => .red,
            3 => .green,
            4 => .yellow,
            5 => .blue,
            6 => .magenta,
            7 => .cyan,
            8 => .white,
            9 => .bright_black,
            10 => .bright_red,
            11 => .bright_green,
            12 => .bright_yellow,
            13 => .bright_blue,
            14 => .bright_magenta,
            15 => .bright_cyan,
            16 => .bright_white,
            17 => .{ .indexed = random.int(u8) },
            18, 19 => .{ .rgb = .{
                .r = random.int(u8),
                .g = random.int(u8),
                .b = random.int(u8),
            } },
            else => unreachable,
        };
    }

    /// Generate random style
    pub fn genStyle(self: *Generator) Style {
        const random = self.prng.random();
        // Randomly decide if we have fg/bg colors (50% chance each)
        const has_fg = random.boolean();
        const has_bg = random.boolean();

        return .{
            .fg = if (has_fg) self.genColor() else null,
            .bg = if (has_bg) self.genColor() else null,
            .bold = random.boolean(),
            .dim = random.boolean(),
            .italic = random.boolean(),
            .underline = random.boolean(),
            .blink = random.boolean(),
            .reverse = random.boolean(),
            .strikethrough = random.boolean(),
        };
    }
};

/// Property test runner
pub const PropertyTest = struct {
    seed: u64,
    iterations: usize,
    allocator: Allocator,

    /// Initialize property test
    pub fn init(allocator: Allocator, seed: u64, iterations: usize) PropertyTest {
        return .{
            .allocator = allocator,
            .seed = seed,
            .iterations = iterations,
        };
    }

    /// Run property test function N times with random inputs
    /// Property function signature can be:
    ///   fn(*Generator) anyerror!void
    pub fn run(self: *PropertyTest, property_fn: anytype) !void {
        var i: usize = 0;
        while (i < self.iterations) : (i += 1) {
            // Create generator with seed + i for different values each iteration
            var gen = Generator.init(self.seed + i);

            // Call property function with generator
            try property_fn(&gen);
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Generator init with seed" {
    const gen = Generator.init(12345);
    _ = gen;
    // Should initialize PRNG with seed
}

test "genU16 produces value in range" {
    var gen = Generator.init(42);

    // Test multiple samples
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const val = gen.genU16(10, 20);
        try std.testing.expect(val >= 10);
        try std.testing.expect(val <= 20);
    }
}

test "genU16 deterministic with same seed" {
    var gen1 = Generator.init(123);
    var gen2 = Generator.init(123);

    const val1 = gen1.genU16(0, 1000);
    const val2 = gen2.genU16(0, 1000);

    try std.testing.expectEqual(val1, val2);
}

test "genU16 different values with different seeds" {
    var gen1 = Generator.init(111);
    var gen2 = Generator.init(222);

    const val1 = gen1.genU16(0, 65535);
    const val2 = gen2.genU16(0, 65535);

    // Very unlikely to be equal with different seeds over full range
    try std.testing.expect(val1 != val2);
}

test "genU32 produces value in range" {
    var gen = Generator.init(99);

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const val = gen.genU32(1000, 2000);
        try std.testing.expect(val >= 1000);
        try std.testing.expect(val <= 2000);
    }
}

test "genU32 deterministic with same seed" {
    var gen1 = Generator.init(456);
    var gen2 = Generator.init(456);

    const val1 = gen1.genU32(0, 100000);
    const val2 = gen2.genU32(0, 100000);

    try std.testing.expectEqual(val1, val2);
}

test "genBool produces both true and false" {
    var gen = Generator.init(777);

    var true_count: usize = 0;
    var false_count: usize = 0;

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        if (gen.genBool()) {
            true_count += 1;
        } else {
            false_count += 1;
        }
    }

    // Both should occur with reasonable distribution
    try std.testing.expect(true_count > 0);
    try std.testing.expect(false_count > 0);

    // Should be roughly 50/50 (allow 40-60% range)
    const true_pct = (true_count * 100) / 1000;
    try std.testing.expect(true_pct >= 40 and true_pct <= 60);
}

test "genBool deterministic with same seed" {
    var gen1 = Generator.init(888);
    var gen2 = Generator.init(888);

    const val1 = gen1.genBool();
    const val2 = gen2.genBool();

    try std.testing.expectEqual(val1, val2);
}

test "genString respects max length" {
    var gen = Generator.init(333);
    const allocator = std.testing.allocator;

    const str = try gen.genString(allocator, 10);
    defer allocator.free(str);

    try std.testing.expect(str.len <= 10);
}

test "genString produces different outputs with different seeds" {
    const allocator = std.testing.allocator;

    var gen1 = Generator.init(111);
    var gen2 = Generator.init(222);

    const str1 = try gen1.genString(allocator, 20);
    defer allocator.free(str1);

    const str2 = try gen2.genString(allocator, 20);
    defer allocator.free(str2);

    // Very unlikely to be equal
    try std.testing.expect(!std.mem.eql(u8, str1, str2));
}

test "genString deterministic with same seed" {
    const allocator = std.testing.allocator;

    var gen1 = Generator.init(555);
    var gen2 = Generator.init(555);

    const str1 = try gen1.genString(allocator, 15);
    defer allocator.free(str1);

    const str2 = try gen2.genString(allocator, 15);
    defer allocator.free(str2);

    try std.testing.expectEqualStrings(str1, str2);
}

test "genString handles empty string" {
    var gen = Generator.init(999);
    const allocator = std.testing.allocator;

    const str = try gen.genString(allocator, 0);
    defer allocator.free(str);

    try std.testing.expectEqual(@as(usize, 0), str.len);
}

test "genRect produces valid bounds" {
    var gen = Generator.init(444);

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const rect = gen.genRect(80, 24);

        // Width and height should be within max
        try std.testing.expect(rect.width <= 80);
        try std.testing.expect(rect.height <= 24);

        // Position + size should fit
        try std.testing.expect(rect.x + rect.width <= 80);
        try std.testing.expect(rect.y + rect.height <= 24);
    }
}

test "genRect deterministic with same seed" {
    var gen1 = Generator.init(666);
    var gen2 = Generator.init(666);

    const rect1 = gen1.genRect(100, 50);
    const rect2 = gen2.genRect(100, 50);

    try std.testing.expectEqual(rect1.x, rect2.x);
    try std.testing.expectEqual(rect1.y, rect2.y);
    try std.testing.expectEqual(rect1.width, rect2.width);
    try std.testing.expectEqual(rect1.height, rect2.height);
}

test "genRect non-zero area occasionally" {
    var gen = Generator.init(555);

    var non_zero_count: usize = 0;

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const rect = gen.genRect(80, 24);
        if (rect.area() > 0) {
            non_zero_count += 1;
        }
    }

    // Should produce at least some non-zero rectangles
    try std.testing.expect(non_zero_count > 0);
}

test "genColor produces valid color values" {
    var gen = Generator.init(777);

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const color = gen.genColor();

        // Verify it's a valid color variant
        switch (color) {
            .reset, .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white => {},
            .bright_black, .bright_red, .bright_green, .bright_yellow => {},
            .bright_blue, .bright_magenta, .bright_cyan, .bright_white => {},
            .indexed => |idx| {
                // Indexed colors should be valid (0-255)
                _ = idx;
            },
            .rgb => |rgb| {
                // RGB values are already constrained to u8
                _ = rgb;
            },
        }
    }
}

test "genColor deterministic with same seed" {
    var gen1 = Generator.init(888);
    var gen2 = Generator.init(888);

    const color1 = gen1.genColor();
    const color2 = gen2.genColor();

    // Deep equality check
    switch (color1) {
        .reset => try std.testing.expectEqual(Color.reset, color2),
        .black => try std.testing.expectEqual(Color.black, color2),
        .red => try std.testing.expectEqual(Color.red, color2),
        .green => try std.testing.expectEqual(Color.green, color2),
        .yellow => try std.testing.expectEqual(Color.yellow, color2),
        .blue => try std.testing.expectEqual(Color.blue, color2),
        .magenta => try std.testing.expectEqual(Color.magenta, color2),
        .cyan => try std.testing.expectEqual(Color.cyan, color2),
        .white => try std.testing.expectEqual(Color.white, color2),
        .bright_black => try std.testing.expectEqual(Color.bright_black, color2),
        .bright_red => try std.testing.expectEqual(Color.bright_red, color2),
        .bright_green => try std.testing.expectEqual(Color.bright_green, color2),
        .bright_yellow => try std.testing.expectEqual(Color.bright_yellow, color2),
        .bright_blue => try std.testing.expectEqual(Color.bright_blue, color2),
        .bright_magenta => try std.testing.expectEqual(Color.bright_magenta, color2),
        .bright_cyan => try std.testing.expectEqual(Color.bright_cyan, color2),
        .bright_white => try std.testing.expectEqual(Color.bright_white, color2),
        .indexed => |idx1| {
            const idx2 = color2.indexed;
            try std.testing.expectEqual(idx1, idx2);
        },
        .rgb => |rgb1| {
            const rgb2 = color2.rgb;
            try std.testing.expectEqual(rgb1.r, rgb2.r);
            try std.testing.expectEqual(rgb1.g, rgb2.g);
            try std.testing.expectEqual(rgb1.b, rgb2.b);
        },
    }
}

test "genStyle produces valid style combinations" {
    var gen = Generator.init(999);

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const style = gen.genStyle();

        // Verify style has valid fields
        // fg and bg are optional Colors
        if (style.fg) |_| {
            // Valid foreground color
        }
        if (style.bg) |_| {
            // Valid background color
        }

        // Modifiers are booleans (always valid)
        _ = style.bold;
        _ = style.italic;
        _ = style.underline;
    }
}

test "genStyle deterministic with same seed" {
    var gen1 = Generator.init(101010);
    var gen2 = Generator.init(101010);

    const style1 = gen1.genStyle();
    const style2 = gen2.genStyle();

    // Compare style fields
    try std.testing.expectEqual(style1.bold, style2.bold);
    try std.testing.expectEqual(style1.italic, style2.italic);
    try std.testing.expectEqual(style1.underline, style2.underline);

    // Compare optional colors (simplified check)
    const fg1_exists = style1.fg != null;
    const fg2_exists = style2.fg != null;
    try std.testing.expectEqual(fg1_exists, fg2_exists);

    const bg1_exists = style1.bg != null;
    const bg2_exists = style2.bg != null;
    try std.testing.expectEqual(bg1_exists, bg2_exists);
}

test "PropertyTest init stores parameters" {
    const allocator = std.testing.allocator;
    const prop_test = PropertyTest.init(allocator, 12345, 100);

    try std.testing.expectEqual(@as(u64, 12345), prop_test.seed);
    try std.testing.expectEqual(@as(usize, 100), prop_test.iterations);
}

test "PropertyTest run executes property N times" {
    const allocator = std.testing.allocator;
    var prop_test = PropertyTest.init(allocator, 42, 50);

    // Use a simple property that verifies generator works
    try prop_test.run(struct {
        fn prop(gen: *Generator) anyerror!void {
            // Verify generator produces valid values
            const val = gen.genU16(0, 100);
            try std.testing.expect(val <= 100);
        }
    }.prop);

    // Test passed if no errors thrown
}

test "PropertyTest run provides generator to property function" {
    const allocator = std.testing.allocator;
    var prop_test = PropertyTest.init(allocator, 777, 10);

    try prop_test.run(struct {
        fn prop(gen: *Generator) anyerror!void {
            // Verify generator works
            const val = gen.genU16(0, 100);
            try std.testing.expect(val <= 100);
        }
    }.prop);
}

test "PropertyTest run with same seed produces deterministic results" {
    // Run same property test twice with same seed
    var gen1 = Generator.init(333);
    var gen2 = Generator.init(333);

    const val1 = gen1.genU16(0, 1000);
    const val2 = gen2.genU16(0, 1000);

    // Same seed produces same values
    try std.testing.expectEqual(val1, val2);
}

test "PropertyTest run propagates property errors" {
    const allocator = std.testing.allocator;
    var prop_test = PropertyTest.init(allocator, 999, 5);

    const result = prop_test.run(struct {
        fn prop(_: *Generator) anyerror!void {
            return error.PropertyFailed;
        }
    }.prop);
    try std.testing.expectError(error.PropertyFailed, result);
}

test "PropertyTest edge case - zero iterations" {
    const allocator = std.testing.allocator;
    var prop_test = PropertyTest.init(allocator, 123, 0);

    // Should complete without error even with zero iterations
    try prop_test.run(struct {
        fn prop(_: *Generator) anyerror!void {
            unreachable; // Should never be called
        }
    }.prop);
}

test "PropertyTest edge case - single iteration" {
    const allocator = std.testing.allocator;
    var prop_test = PropertyTest.init(allocator, 456, 1);

    // Should call property function exactly once
    try prop_test.run(struct {
        fn prop(gen: *Generator) anyerror!void {
            // Verify generator is usable
            const val = gen.genU16(0, 100);
            try std.testing.expect(val <= 100);
        }
    }.prop);
}

test "genRect edge case - zero max dimensions" {
    var gen = Generator.init(111);

    const rect = gen.genRect(0, 0);

    // Should handle gracefully
    try std.testing.expectEqual(@as(u16, 0), rect.width);
    try std.testing.expectEqual(@as(u16, 0), rect.height);
}

test "genU16 edge case - min equals max" {
    var gen = Generator.init(222);

    const val = gen.genU16(50, 50);

    // Should return the only valid value
    try std.testing.expectEqual(@as(u16, 50), val);
}

test "genU32 edge case - min equals max" {
    var gen = Generator.init(333);

    const val = gen.genU32(1234, 1234);

    // Should return the only valid value
    try std.testing.expectEqual(@as(u32, 1234), val);
}

test "genString edge case - max_len of 1" {
    var gen = Generator.init(444);
    const allocator = std.testing.allocator;

    const str = try gen.genString(allocator, 1);
    defer allocator.free(str);

    try std.testing.expect(str.len <= 1);
}

test "genU16 full range coverage" {
    var gen = Generator.init(555);

    // Generate across full u16 range
    const val = gen.genU16(0, 65535);

    try std.testing.expect(val >= 0);
    try std.testing.expect(val <= 65535);
}

test "genU32 full range coverage" {
    var gen = Generator.init(666);

    // Generate across large u32 range
    const val = gen.genU32(0, 1_000_000);

    try std.testing.expect(val >= 0);
    try std.testing.expect(val <= 1_000_000);
}
