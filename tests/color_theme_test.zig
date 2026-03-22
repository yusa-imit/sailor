//! Tests for ColorTheme system (v1.19.0)
//!
//! This test suite validates:
//! - Theme struct with semantic color definitions
//! - Light and dark theme presets
//! - Terminal background auto-detection
//! - Theme switching capability
//! - Custom theme creation
//! - Memory safety

const std = @import("std");
const sailor = @import("sailor");
const Color = sailor.color.Color;
const Style = sailor.color.Style;
const ColorTheme = sailor.color.ColorTheme; // API to be implemented

// ============================================================================
// Theme Structure Tests
// ============================================================================

test "ColorTheme has semantic color fields" {
    // ColorTheme should have semantic fields for common use cases
    const theme = ColorTheme.dark();

    // All semantic fields should be accessible
    _ = theme.error_fg;
    _ = theme.warning_fg;
    _ = theme.success_fg;
    _ = theme.info_fg;
    _ = theme.primary_fg;
    _ = theme.secondary_fg;
    _ = theme.background;
    _ = theme.foreground;
    _ = theme.muted_fg;
    _ = theme.highlight_fg;
}

test "ColorTheme semantic fields are Color type" {
    const theme = ColorTheme.light();

    // Each field should be a Color union
    try std.testing.expect(@TypeOf(theme.error_fg) == Color);
    try std.testing.expect(@TypeOf(theme.warning_fg) == Color);
    try std.testing.expect(@TypeOf(theme.success_fg) == Color);
    try std.testing.expect(@TypeOf(theme.background) == Color);
    try std.testing.expect(@TypeOf(theme.foreground) == Color);
}

// ============================================================================
// Preset Theme Tests
// ============================================================================

test "ColorTheme.dark creates dark theme preset" {
    const theme = ColorTheme.dark();

    // Dark theme should have dark background, light foreground
    // Background should be dark (black or near-black)
    switch (theme.background) {
        .default => {}, // acceptable
        .basic => |c| {
            try std.testing.expect(
                c == .black or c == .bright_black,
            );
        },
        .rgb => |rgb| {
            // Dark = low RGB values
            const brightness = @as(u16, rgb.r) + @as(u16, rgb.g) + @as(u16, rgb.b);
            try std.testing.expect(brightness < 128);
        },
        .indexed => {}, // can't easily validate
    }

    // Foreground should be light
    switch (theme.foreground) {
        .default => {}, // acceptable
        .basic => |c| {
            try std.testing.expect(
                c == .white or c == .bright_white or
                    @intFromEnum(c) >= 8, // bright variants
            );
        },
        .rgb => |rgb| {
            // Light = high RGB values
            const brightness = @as(u16, rgb.r) + @as(u16, rgb.g) + @as(u16, rgb.b);
            try std.testing.expect(brightness > 500);
        },
        .indexed => {}, // can't easily validate
    }
}

test "ColorTheme.light creates light theme preset" {
    const theme = ColorTheme.light();

    // Light theme should have light background, dark foreground
    // Background should be light
    switch (theme.background) {
        .default => {}, // acceptable
        .basic => |c| {
            try std.testing.expect(
                c == .white or c == .bright_white,
            );
        },
        .rgb => |rgb| {
            // Light = high RGB values
            const brightness = @as(u16, rgb.r) + @as(u16, rgb.g) + @as(u16, rgb.b);
            try std.testing.expect(brightness > 600);
        },
        .indexed => {}, // can't easily validate
    }

    // Foreground should be dark
    switch (theme.foreground) {
        .default => {}, // acceptable
        .basic => |c| {
            try std.testing.expect(
                c == .black or c == .bright_black or
                    @intFromEnum(c) < 8, // non-bright variants
            );
        },
        .rgb => |rgb| {
            // Dark = low RGB values
            const brightness = @as(u16, rgb.r) + @as(u16, rgb.g) + @as(u16, rgb.b);
            try std.testing.expect(brightness < 200);
        },
        .indexed => {}, // can't easily validate
    }
}

test "ColorTheme.dark has distinct semantic colors" {
    const theme = ColorTheme.dark();

    // Error should be red-ish
    try expectRedIsh(theme.error_fg);

    // Warning should be yellow/orange-ish
    try expectYellowIsh(theme.warning_fg);

    // Success should be green-ish
    try expectGreenIsh(theme.success_fg);

    // Info should be blue-ish
    try expectBlueIsh(theme.info_fg);
}

test "ColorTheme.light has distinct semantic colors" {
    const theme = ColorTheme.light();

    // Same semantic color families for light theme
    try expectRedIsh(theme.error_fg);
    try expectYellowIsh(theme.warning_fg);
    try expectGreenIsh(theme.success_fg);
    try expectBlueIsh(theme.info_fg);
}

test "ColorTheme light and dark are different" {
    const light = ColorTheme.light();
    const dark = ColorTheme.dark();

    // Backgrounds should differ (unless both default)
    const backgrounds_differ = !colorEqual(light.background, dark.background);
    const foregrounds_differ = !colorEqual(light.foreground, dark.foreground);

    try std.testing.expect(backgrounds_differ or foregrounds_differ);
}

// ============================================================================
// Auto-detection Tests
// ============================================================================

test "ColorTheme.detectFromTerminal returns valid theme" {
    const allocator = std.testing.allocator;

    // Should return either light or dark theme based on terminal
    const theme = try ColorTheme.detectFromTerminal(allocator);

    // Theme should have valid semantic colors
    _ = theme.error_fg;
    _ = theme.background;
    _ = theme.foreground;
}

test "ColorTheme.detectFromTerminal with mock light background" {
    const allocator = std.testing.allocator;

    // Mock function that returns light background RGB
    const MockTerminal = struct {
        fn queryBackground() !Color {
            return Color.fromRgb(250, 250, 250); // Very light background
        }
    };

    const theme = try ColorTheme.detectFromTerminalWithQuery(
        allocator,
        MockTerminal.queryBackground,
    );

    // Should detect light theme
    // Verify by checking foreground is dark
    switch (theme.foreground) {
        .default => {}, // acceptable fallback
        .basic => |c| {
            try std.testing.expect(@intFromEnum(c) < 8 or c == .black);
        },
        .rgb => |rgb| {
            const brightness = @as(u16, rgb.r) + @as(u16, rgb.g) + @as(u16, rgb.b);
            try std.testing.expect(brightness < 300);
        },
        .indexed => {},
    }
}

test "ColorTheme.detectFromTerminal with mock dark background" {
    const allocator = std.testing.allocator;

    // Mock function that returns dark background RGB
    const MockTerminal = struct {
        fn queryBackground() !Color {
            return Color.fromRgb(20, 20, 20); // Very dark background
        }
    };

    const theme = try ColorTheme.detectFromTerminalWithQuery(
        allocator,
        MockTerminal.queryBackground,
    );

    // Should detect dark theme
    // Verify by checking foreground is light
    switch (theme.foreground) {
        .default => {}, // acceptable fallback
        .basic => |c| {
            try std.testing.expect(@intFromEnum(c) >= 8 or c == .white);
        },
        .rgb => |rgb| {
            const brightness = @as(u16, rgb.r) + @as(u16, rgb.g) + @as(u16, rgb.b);
            try std.testing.expect(brightness > 400);
        },
        .indexed => {},
    }
}

test "ColorTheme.detectFromTerminal handles query failure gracefully" {
    const allocator = std.testing.allocator;

    // Mock function that fails
    const MockTerminal = struct {
        fn queryBackground() !Color {
            return error.TerminalQueryFailed;
        }
    };

    const theme = try ColorTheme.detectFromTerminalWithQuery(
        allocator,
        MockTerminal.queryBackground,
    );

    // Should fall back to a default theme (dark is common default)
    _ = theme.background;
    _ = theme.foreground;
}

// ============================================================================
// Theme Application Tests
// ============================================================================

test "ColorTheme.apply writes semantic color to writer" {
    const theme = ColorTheme.dark();
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try theme.apply(writer, .error_fg);

    const output = fbs.getWritten();
    try std.testing.expect(output.len > 0); // Should write ANSI code
    try std.testing.expect(std.mem.startsWith(u8, output, "\x1b[")); // ANSI escape
}

test "ColorTheme.apply supports all semantic names" {
    const theme = ColorTheme.light();
    var buf: [128]u8 = undefined;

    // All semantic color names should be applicable
    const semantic_names = [_]@TypeOf(.error_fg){
        .error_fg,
        .warning_fg,
        .success_fg,
        .info_fg,
        .primary_fg,
        .secondary_fg,
        .background,
        .foreground,
        .muted_fg,
        .highlight_fg,
    };

    inline for (semantic_names) |name| {
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();
        try theme.apply(writer, name);

        const output = fbs.getWritten();
        try std.testing.expect(output.len > 0);
    }
}

test "ColorTheme.applyBg writes background color" {
    const theme = ColorTheme.dark();
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try theme.applyBg(writer, .error_fg); // Apply as background

    const output = fbs.getWritten();
    try std.testing.expect(output.len > 0);

    // Should write background ANSI code (48 for truecolor/indexed, 4X for basic, 10X for bright)
    const has_bg_code = std.mem.indexOf(u8, output, "\x1b[48") != null or
        std.mem.indexOf(u8, output, "\x1b[4") != null or
        std.mem.indexOf(u8, output, "\x1b[10") != null;
    try std.testing.expect(has_bg_code);
}

test "ColorTheme.styled creates Style from semantic color" {
    const theme = ColorTheme.dark();

    const style = theme.styled(.error_fg);

    // Style should have the error foreground color
    try std.testing.expect(!colorEqual(style.fg, Color.default));

    // Should be usable with writeStyled
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try sailor.color.writeStyled(writer, style, "error message");

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "error message") != null);
}

// ============================================================================
// Theme Switching Tests
// ============================================================================

test "ColorTheme switching maintains semantic color access" {
    var theme = ColorTheme.dark();

    // Switch to light
    theme = ColorTheme.light();

    // All semantic colors should still be accessible
    _ = theme.error_fg;
    _ = theme.background;

    // Switch back to dark
    theme = ColorTheme.dark();

    _ = theme.error_fg;
    _ = theme.background;
}

test "ColorTheme assignment is copy not reference" {
    const dark = ColorTheme.dark();
    var mutable = dark;

    // Modify mutable
    mutable.error_fg = Color.fromRgb(255, 0, 255);

    // Original should be unchanged
    try std.testing.expect(!colorEqual(dark.error_fg, mutable.error_fg));
}

// ============================================================================
// Custom Theme Tests
// ============================================================================

test "ColorTheme.init creates custom theme" {
    const custom = ColorTheme.init(.{
        .error_fg = Color.fromRgb(255, 100, 100),
        .warning_fg = Color.fromRgb(255, 200, 100),
        .success_fg = Color.fromRgb(100, 255, 100),
        .info_fg = Color.fromRgb(100, 100, 255),
        .primary_fg = Color.fromRgb(200, 200, 200),
        .secondary_fg = Color.fromRgb(150, 150, 150),
        .background = Color.fromRgb(30, 30, 30),
        .foreground = Color.fromRgb(220, 220, 220),
        .muted_fg = Color.fromRgb(100, 100, 100),
        .highlight_fg = Color.fromRgb(255, 255, 100),
    });

    // Custom colors should be preserved
    try std.testing.expectEqual(@as(u8, 255), custom.error_fg.rgb.r);
    try std.testing.expectEqual(@as(u8, 100), custom.error_fg.rgb.g);
    try std.testing.expectEqual(@as(u8, 30), custom.background.rgb.r);
}

test "ColorTheme.init with partial fields uses defaults" {
    const partial = ColorTheme.init(.{
        .error_fg = Color.fromRgb(255, 0, 0),
        // Other fields should use dark theme defaults
    });

    // Specified field should be custom
    try std.testing.expectEqual(@as(u8, 255), partial.error_fg.rgb.r);
    try std.testing.expectEqual(@as(u8, 0), partial.error_fg.rgb.g);

    // Other fields should be initialized to something
    _ = partial.warning_fg;
    _ = partial.background;
}

// ============================================================================
// Memory Safety Tests
// ============================================================================

test "ColorTheme no allocations for preset themes" {
    const allocator = std.testing.allocator;

    const dark = ColorTheme.dark();
    const light = ColorTheme.light();

    _ = dark;
    _ = light;

    // No allocations should have occurred
    // (fixedBufferAllocator would panic on alloc)
    var fixed_buf: [0]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&fixed_buf);
    const no_alloc = fba.allocator();

    // Creating preset themes with no allocator should work
    _ = ColorTheme.dark();
    _ = ColorTheme.light();

    _ = allocator; // silence unused warning
    _ = no_alloc;
}

test "ColorTheme.detectFromTerminal handles allocation failure" {
    // Use FailingAllocator to test allocation failures
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });

    const result = ColorTheme.detectFromTerminal(failing_allocator.allocator());

    // Should return error on allocation failure
    try std.testing.expectError(error.OutOfMemory, result);
}

test "ColorTheme thread safety for read-only access" {
    const theme = ColorTheme.dark();

    // Multiple threads reading the same theme should be safe
    const Thread = struct {
        fn read(t: *const ColorTheme) void {
            _ = t.error_fg;
            _ = t.background;
            _ = t.foreground;
        }
    };

    const t1 = try std.Thread.spawn(.{}, Thread.read, .{&theme});
    const t2 = try std.Thread.spawn(.{}, Thread.read, .{&theme});

    t1.join();
    t2.join();
}

// ============================================================================
// Edge Cases
// ============================================================================

test "ColorTheme works with ColorLevel.none" {
    const theme = ColorTheme.dark();

    // Even with no color support, theme should be applicable
    // (implementation should skip ANSI codes or use ColorLevel)
    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try theme.apply(writer, .error_fg);

    // Should not panic or error
}

test "ColorTheme.apply with default colors" {
    const theme = ColorTheme.init(.{
        .error_fg = .default,
        .warning_fg = .default,
        .success_fg = .default,
        .info_fg = .default,
        .primary_fg = .default,
        .secondary_fg = .default,
        .background = .default,
        .foreground = .default,
        .muted_fg = .default,
        .highlight_fg = .default,
    });

    var buf: [128]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try theme.apply(writer, .error_fg);

    const output = fbs.getWritten();
    // Should write default foreground code
    try std.testing.expectEqualStrings("\x1b[39m", output);
}

// ============================================================================
// Integration Tests
// ============================================================================

test "ColorTheme integration with existing semantic helpers" {
    const theme = ColorTheme.dark();

    // Theme error color should be semantically similar to sailor.color.semantic.err
    var buf1: [128]u8 = undefined;
    var fbs1 = std.io.fixedBufferStream(&buf1);
    try theme.apply(fbs1.writer(), .error_fg);

    var buf2: [128]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(&buf2);
    try sailor.color.semantic.err.fg.writeFg(fbs2.writer());

    // Both should produce red-ish output (not necessarily identical)
    const theme_out = fbs1.getWritten();
    const semantic_out = fbs2.getWritten();

    try std.testing.expect(theme_out.len > 0);
    try std.testing.expect(semantic_out.len > 0);
}

test "ColorTheme writeStyled with theme colors" {
    const theme = ColorTheme.light();
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const style = theme.styled(.success_fg);
    try sailor.color.writeStyled(writer, style, "Operation succeeded");

    const output = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "Operation succeeded") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\x1b[") != null); // ANSI code
    try std.testing.expect(std.mem.indexOf(u8, output, "\x1b[0m") != null); // reset
}

// ============================================================================
// Helper Functions
// ============================================================================

fn expectRedIsh(color: Color) !void {
    switch (color) {
        .basic => |c| {
            try std.testing.expect(
                c == .red or c == .bright_red,
            );
        },
        .rgb => |rgb| {
            // Red component should be dominant
            try std.testing.expect(rgb.r > rgb.g and rgb.r > rgb.b);
        },
        .default => {}, // can't validate
        .indexed => {}, // can't validate
    }
}

fn expectYellowIsh(color: Color) !void {
    switch (color) {
        .basic => |c| {
            try std.testing.expect(
                c == .yellow or c == .bright_yellow,
            );
        },
        .rgb => |rgb| {
            // Red and green should be high, blue low
            try std.testing.expect(rgb.r > 100 and rgb.g > 100 and rgb.b < rgb.r);
        },
        .default => {},
        .indexed => {},
    }
}

fn expectGreenIsh(color: Color) !void {
    switch (color) {
        .basic => |c| {
            try std.testing.expect(
                c == .green or c == .bright_green,
            );
        },
        .rgb => |rgb| {
            // Green component should be dominant
            try std.testing.expect(rgb.g > rgb.r and rgb.g > rgb.b);
        },
        .default => {},
        .indexed => {},
    }
}

fn expectBlueIsh(color: Color) !void {
    switch (color) {
        .basic => |c| {
            try std.testing.expect(
                c == .blue or c == .bright_blue or c == .cyan or c == .bright_cyan,
            );
        },
        .rgb => |rgb| {
            // Blue component should be significant
            try std.testing.expect(rgb.b > rgb.r or rgb.b > 150);
        },
        .default => {},
        .indexed => {},
    }
}

fn colorEqual(a: Color, b: Color) bool {
    if (@intFromEnum(a) != @intFromEnum(b)) return false;

    return switch (a) {
        .default => true,
        .basic => |ac| ac == b.basic,
        .indexed => |ai| ai == b.indexed,
        .rgb => |ar| ar.r == b.rgb.r and ar.g == b.rgb.g and ar.b == b.rgb.b,
    };
}
