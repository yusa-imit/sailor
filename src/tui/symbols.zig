const std = @import("std");

/// Box-drawing character sets for borders and frames
pub const BoxSet = struct {
    horizontal: []const u8,
    vertical: []const u8,
    top_left: []const u8,
    top_right: []const u8,
    bottom_left: []const u8,
    bottom_right: []const u8,
    vertical_left: []const u8,
    vertical_right: []const u8,
    horizontal_down: []const u8,
    horizontal_up: []const u8,
    cross: []const u8,

    /// Single-line box-drawing characters (thin)
    pub const single: BoxSet = .{
        .horizontal = "─",
        .vertical = "│",
        .top_left = "┌",
        .top_right = "┐",
        .bottom_left = "└",
        .bottom_right = "┘",
        .vertical_left = "├",
        .vertical_right = "┤",
        .horizontal_down = "┬",
        .horizontal_up = "┴",
        .cross = "┼",
    };

    /// Double-line box-drawing characters
    pub const double: BoxSet = .{
        .horizontal = "═",
        .vertical = "║",
        .top_left = "╔",
        .top_right = "╗",
        .bottom_left = "╚",
        .bottom_right = "╝",
        .vertical_left = "╠",
        .vertical_right = "╣",
        .horizontal_down = "╦",
        .horizontal_up = "╩",
        .cross = "╬",
    };

    /// Thick box-drawing characters
    pub const thick: BoxSet = .{
        .horizontal = "━",
        .vertical = "┃",
        .top_left = "┏",
        .top_right = "┓",
        .bottom_left = "┗",
        .bottom_right = "┛",
        .vertical_left = "┣",
        .vertical_right = "┫",
        .horizontal_down = "┳",
        .horizontal_up = "┻",
        .cross = "╋",
    };

    /// Rounded corners with single lines
    pub const rounded: BoxSet = .{
        .horizontal = "─",
        .vertical = "│",
        .top_left = "╭",
        .top_right = "╮",
        .bottom_left = "╰",
        .bottom_right = "╯",
        .vertical_left = "├",
        .vertical_right = "┤",
        .horizontal_down = "┬",
        .horizontal_up = "┴",
        .cross = "┼",
    };

    /// Dashed border style
    pub const dashed: BoxSet = .{
        .horizontal = "╌",
        .vertical = "╎",
        .top_left = "┌",
        .top_right = "┐",
        .bottom_left = "└",
        .bottom_right = "┘",
        .vertical_left = "├",
        .vertical_right = "┤",
        .horizontal_down = "┬",
        .horizontal_up = "┴",
        .cross = "┼",
    };

    /// ASCII fallback (for terminals without Unicode support)
    pub const ascii: BoxSet = .{
        .horizontal = "-",
        .vertical = "|",
        .top_left = "+",
        .top_right = "+",
        .bottom_left = "+",
        .bottom_right = "+",
        .vertical_left = "+",
        .vertical_right = "+",
        .horizontal_down = "+",
        .horizontal_up = "+",
        .cross = "+",
    };

    /// Draw a horizontal line
    pub fn drawHorizontal(self: BoxSet, writer: anytype, width: usize) !void {
        var i: usize = 0;
        while (i < width) : (i += 1) {
            try writer.writeAll(self.horizontal);
        }
    }

    /// Draw a vertical line
    pub fn drawVertical(self: BoxSet, writer: anytype, height: usize) !void {
        var i: usize = 0;
        while (i < height) : (i += 1) {
            try writer.writeAll(self.vertical);
            if (i < height - 1) {
                try writer.writeAll("\n");
            }
        }
    }

    /// Draw a complete box border
    pub fn drawBox(self: BoxSet, writer: anytype, width: usize, height: usize) !void {
        if (width < 2 or height < 2) return error.BoxTooSmall;

        // Top border
        try writer.writeAll(self.top_left);
        try self.drawHorizontal(writer, width - 2);
        try writer.writeAll(self.top_right);
        try writer.writeAll("\n");

        // Middle rows (empty inside)
        var row: usize = 1;
        while (row < height - 1) : (row += 1) {
            try writer.writeAll(self.vertical);
            var col: usize = 0;
            while (col < width - 2) : (col += 1) {
                try writer.writeAll(" ");
            }
            try writer.writeAll(self.vertical);
            try writer.writeAll("\n");
        }

        // Bottom border
        try writer.writeAll(self.bottom_left);
        try self.drawHorizontal(writer, width - 2);
        try writer.writeAll(self.bottom_right);
    }
};

/// Braille patterns for high-resolution graphics in terminal
pub const Braille = struct {
    /// Braille Unicode block starts at U+2800
    const BASE: u21 = 0x2800;

    /// Get braille character for given dot pattern
    /// Dots are numbered 1-8:
    /// 1 4
    /// 2 5
    /// 3 6
    /// 7 8
    pub fn pattern(dots: u8) u21 {
        return BASE + @as(u21, dots);
    }

    /// Empty braille character (no dots)
    pub const empty: u21 = BASE;

    /// Full braille character (all 8 dots)
    pub const full: u21 = BASE + 0xFF;

    /// Create a vertical bar pattern for sparkline
    pub fn verticalBar(level: u3) u21 {
        return switch (level) {
            0 => empty,
            1 => pattern(0b01000000), // dot 7
            2 => pattern(0b01000100), // dots 3,7
            3 => pattern(0b01010100), // dots 3,5,7
            4 => pattern(0b01010101), // dots 1,3,5,7
            5 => pattern(0b11010101), // dots 1,3,5,7,8
            6 => pattern(0b11010111), // dots 1,2,3,5,7,8
            7 => pattern(0b11011111), // all except dot 6
        };
    }
};

/// Block elements for progress bars and charts
pub const Block = struct {
    /// Horizontal block eighths for fine-grained progress bars
    pub const horizontal_eighth = [_][]const u8{
        " ",  // 0/8
        "▏", // 1/8
        "▎", // 2/8
        "▍", // 3/8
        "▌", // 4/8
        "▋", // 5/8
        "▊", // 6/8
        "▉", // 7/8
        "█", // 8/8 (full)
    };

    /// Vertical block eighths
    pub const vertical_eighth = [_][]const u8{
        " ",  // 0/8
        "▁", // 1/8
        "▂", // 2/8
        "▃", // 3/8
        "▄", // 4/8
        "▅", // 5/8
        "▆", // 6/8
        "▇", // 7/8
        "█", // 8/8 (full)
    };

    /// Quadrant blocks for pixel art
    pub const upper_half = "▀";
    pub const lower_half = "▄";
    pub const left_half = "▌";
    pub const right_half = "▐";
    pub const full = "█";
    pub const light_shade = "░";
    pub const medium_shade = "▒";
    pub const dark_shade = "▓";

    /// Get horizontal block character for progress (0.0 to 1.0)
    pub fn horizontalProgress(progress: f64) []const u8 {
        const clamped = @max(0.0, @min(1.0, progress));
        const index: usize = @intFromFloat(clamped * 8.0);
        return horizontal_eighth[index];
    }

    /// Get vertical block character for value (0.0 to 1.0)
    pub fn verticalLevel(level: f64) []const u8 {
        const clamped = @max(0.0, @min(1.0, level));
        const index: usize = @intFromFloat(clamped * 8.0);
        return vertical_eighth[index];
    }
};

/// Spinner animation frames
pub const Spinner = struct {
    pub const dots = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
    pub const line = [_][]const u8{ "-", "\\", "|", "/" };
    pub const arc = [_][]const u8{ "◜", "◠", "◝", "◞", "◡", "◟" };
    pub const arrow = [_][]const u8{ "←", "↖", "↑", "↗", "→", "↘", "↓", "↙" };
    pub const box = [_][]const u8{ "◰", "◳", "◲", "◱" };
    pub const circle = [_][]const u8{ "◐", "◓", "◑", "◒" };
    pub const braille = [_][]const u8{ "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" };

    /// Get spinner frame at given index (wraps around)
    pub fn frame(comptime frames: []const []const u8, index: usize) []const u8 {
        return frames[index % frames.len];
    }
};

// ============================================================================
// Tests
// ============================================================================

test "BoxSet.single - characters" {
    try std.testing.expectEqualStrings("─", BoxSet.single.horizontal);
    try std.testing.expectEqualStrings("│", BoxSet.single.vertical);
    try std.testing.expectEqualStrings("┌", BoxSet.single.top_left);
    try std.testing.expectEqualStrings("┐", BoxSet.single.top_right);
    try std.testing.expectEqualStrings("└", BoxSet.single.bottom_left);
    try std.testing.expectEqualStrings("┘", BoxSet.single.bottom_right);
}

test "BoxSet.double - characters" {
    try std.testing.expectEqualStrings("═", BoxSet.double.horizontal);
    try std.testing.expectEqualStrings("║", BoxSet.double.vertical);
    try std.testing.expectEqualStrings("╔", BoxSet.double.top_left);
}

test "BoxSet.thick - characters" {
    try std.testing.expectEqualStrings("━", BoxSet.thick.horizontal);
    try std.testing.expectEqualStrings("┃", BoxSet.thick.vertical);
}

test "BoxSet.rounded - characters" {
    try std.testing.expectEqualStrings("╭", BoxSet.rounded.top_left);
    try std.testing.expectEqualStrings("╮", BoxSet.rounded.top_right);
    try std.testing.expectEqualStrings("╰", BoxSet.rounded.bottom_left);
    try std.testing.expectEqualStrings("╯", BoxSet.rounded.bottom_right);
}

test "BoxSet.ascii - characters" {
    try std.testing.expectEqualStrings("-", BoxSet.ascii.horizontal);
    try std.testing.expectEqualStrings("|", BoxSet.ascii.vertical);
    try std.testing.expectEqualStrings("+", BoxSet.ascii.top_left);
}

test "BoxSet.drawHorizontal" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try BoxSet.single.drawHorizontal(writer, 5);
    try std.testing.expectEqualStrings("─────", fbs.getWritten());
}

test "BoxSet.drawVertical" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try BoxSet.single.drawVertical(writer, 3);
    try std.testing.expectEqualStrings("│\n│\n│", fbs.getWritten());
}

test "BoxSet.drawBox - simple" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try BoxSet.single.drawBox(writer, 5, 3);
    const expected =
        \\┌───┐
        \\│   │
        \\└───┘
    ;
    try std.testing.expectEqualStrings(expected, fbs.getWritten());
}

test "BoxSet.drawBox - too small" {
    var buf: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try std.testing.expectError(error.BoxTooSmall, BoxSet.single.drawBox(writer, 1, 1));
}

test "Braille.pattern" {
    try std.testing.expectEqual(0x2800, Braille.pattern(0));
    try std.testing.expectEqual(0x2801, Braille.pattern(1));
    try std.testing.expectEqual(0x28FF, Braille.pattern(0xFF));
}

test "Braille.empty and full" {
    try std.testing.expectEqual(0x2800, Braille.empty);
    try std.testing.expectEqual(0x28FF, Braille.full);
}

test "Braille.verticalBar" {
    try std.testing.expectEqual(Braille.empty, Braille.verticalBar(0));
    try std.testing.expectEqual(Braille.pattern(0b01000000), Braille.verticalBar(1));
    try std.testing.expectEqual(Braille.pattern(0b01010101), Braille.verticalBar(4));
    try std.testing.expectEqual(Braille.pattern(0b11011111), Braille.verticalBar(7));
}

test "Block.horizontal_eighth" {
    try std.testing.expectEqualStrings(" ", Block.horizontal_eighth[0]);
    try std.testing.expectEqualStrings("▏", Block.horizontal_eighth[1]);
    try std.testing.expectEqualStrings("▌", Block.horizontal_eighth[4]);
    try std.testing.expectEqualStrings("█", Block.horizontal_eighth[8]);
}

test "Block.vertical_eighth" {
    try std.testing.expectEqualStrings(" ", Block.vertical_eighth[0]);
    try std.testing.expectEqualStrings("▁", Block.vertical_eighth[1]);
    try std.testing.expectEqualStrings("▄", Block.vertical_eighth[4]);
    try std.testing.expectEqualStrings("█", Block.vertical_eighth[8]);
}

test "Block.horizontalProgress" {
    try std.testing.expectEqualStrings(" ", Block.horizontalProgress(0.0));
    try std.testing.expectEqualStrings(" ", Block.horizontalProgress(0.1)); // 0.1 * 8 = 0.8 -> index 0
    try std.testing.expectEqualStrings("▌", Block.horizontalProgress(0.5));
    try std.testing.expectEqualStrings("█", Block.horizontalProgress(1.0));
    try std.testing.expectEqualStrings(" ", Block.horizontalProgress(-0.5)); // clamped
    try std.testing.expectEqualStrings("█", Block.horizontalProgress(1.5)); // clamped
}

test "Block.verticalLevel" {
    try std.testing.expectEqualStrings(" ", Block.verticalLevel(0.0));
    try std.testing.expectEqualStrings("▁", Block.verticalLevel(0.2)); // 0.2 * 8 = 1.6 -> index 1
    try std.testing.expectEqualStrings("▄", Block.verticalLevel(0.5));
    try std.testing.expectEqualStrings("█", Block.verticalLevel(1.0));
}

/// Radio button symbols
pub const radio = struct {
    pub const selected: u21 = '●';
    pub const unselected: u21 = '○';
};

/// Checkbox symbols
pub const checkbox = struct {
    pub const checked: u21 = '✓';
    pub const unchecked: u21 = ' ';
};

test "Spinner.frame - dots" {
    try std.testing.expectEqualStrings("⠋", Spinner.frame(&Spinner.dots, 0));
    try std.testing.expectEqualStrings("⠙", Spinner.frame(&Spinner.dots, 1));
    try std.testing.expectEqualStrings("⠋", Spinner.frame(&Spinner.dots, 10)); // wraps
}

test "Spinner.frame - line" {
    try std.testing.expectEqualStrings("-", Spinner.frame(&Spinner.line, 0));
    try std.testing.expectEqualStrings("\\", Spinner.frame(&Spinner.line, 1));
    try std.testing.expectEqualStrings("|", Spinner.frame(&Spinner.line, 2));
    try std.testing.expectEqualStrings("/", Spinner.frame(&Spinner.line, 3));
    try std.testing.expectEqualStrings("-", Spinner.frame(&Spinner.line, 4)); // wraps
}

test "Spinner.frame - all sets exist" {
    // Just verify all spinner sets have frames
    try std.testing.expect(Spinner.arc.len > 0);
    try std.testing.expect(Spinner.arrow.len > 0);
    try std.testing.expect(Spinner.box.len > 0);
    try std.testing.expect(Spinner.circle.len > 0);
    try std.testing.expect(Spinner.braille.len > 0);
}
