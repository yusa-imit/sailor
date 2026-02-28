const std = @import("std");
const style = @import("style.zig");
const Color = style.Color;
const Style = style.Style;

/// Theme defines colors for common UI elements
pub const Theme = struct {
    /// Background color
    background: Color = .reset,
    /// Foreground/text color
    foreground: Color = .reset,
    /// Primary accent color (buttons, highlights)
    primary: Color = .blue,
    /// Secondary accent color
    secondary: Color = .cyan,
    /// Success state color
    success: Color = .green,
    /// Warning state color
    warning: Color = .yellow,
    /// Error state color
    error_color: Color = .red,
    /// Info state color
    info: Color = .bright_blue,
    /// Muted/disabled color
    muted: Color = .bright_black,
    /// Border color
    border: Color = .white,
    /// Selection/highlight background
    selection_bg: Color = .bright_blue,
    /// Selection foreground
    selection_fg: Color = .black,

    /// Get style for background
    pub fn bg(self: Theme) Style {
        return .{ .bg = self.background, .fg = self.foreground };
    }

    /// Get style for primary element
    pub fn primary_style(self: Theme) Style {
        return .{ .fg = self.primary, .bold = true };
    }

    /// Get style for secondary element
    pub fn secondary_style(self: Theme) Style {
        return .{ .fg = self.secondary };
    }

    /// Get style for success message
    pub fn success_style(self: Theme) Style {
        return .{ .fg = self.success, .bold = true };
    }

    /// Get style for warning message
    pub fn warning_style(self: Theme) Style {
        return .{ .fg = self.warning, .bold = true };
    }

    /// Get style for error message
    pub fn error_style(self: Theme) Style {
        return .{ .fg = self.error_color, .bold = true };
    }

    /// Get style for info message
    pub fn info_style(self: Theme) Style {
        return .{ .fg = self.info };
    }

    /// Get style for muted/disabled text
    pub fn muted_style(self: Theme) Style {
        return .{ .fg = self.muted, .dim = true };
    }

    /// Get style for border
    pub fn border_style(self: Theme) Style {
        return .{ .fg = self.border };
    }

    /// Get style for selected item
    pub fn selection_style(self: Theme) Style {
        return .{ .fg = self.selection_fg, .bg = self.selection_bg };
    }
};

/// Default dark theme (terminal default colors)
pub const default_dark: Theme = .{
    .background = .reset,
    .foreground = .reset,
    .primary = .bright_blue,
    .secondary = .bright_cyan,
    .success = .bright_green,
    .warning = .bright_yellow,
    .error_color = .bright_red,
    .info = .bright_blue,
    .muted = .bright_black,
    .border = .white,
    .selection_bg = .bright_blue,
    .selection_fg = .black,
};

/// Light theme (optimized for light backgrounds)
pub const light: Theme = .{
    .background = .white,
    .foreground = .black,
    .primary = .blue,
    .secondary = .cyan,
    .success = .green,
    .warning = .yellow,
    .error_color = .red,
    .info = .blue,
    .muted = .bright_black,
    .border = .black,
    .selection_bg = .blue,
    .selection_fg = .white,
};

/// Nord theme (https://www.nordtheme.com/)
pub const nord: Theme = .{
    .background = .{ .rgb = .{ .r = 46, .g = 52, .b = 64 } }, // nord0
    .foreground = .{ .rgb = .{ .r = 216, .g = 222, .b = 233 } }, // nord4
    .primary = .{ .rgb = .{ .r = 136, .g = 192, .b = 208 } }, // nord8
    .secondary = .{ .rgb = .{ .r = 129, .g = 161, .b = 193 } }, // nord9
    .success = .{ .rgb = .{ .r = 163, .g = 190, .b = 140 } }, // nord14
    .warning = .{ .rgb = .{ .r = 235, .g = 203, .b = 139 } }, // nord13
    .error_color = .{ .rgb = .{ .r = 191, .g = 97, .b = 106 } }, // nord11
    .info = .{ .rgb = .{ .r = 136, .g = 192, .b = 208 } }, // nord8
    .muted = .{ .rgb = .{ .r = 76, .g = 86, .b = 106 } }, // nord3
    .border = .{ .rgb = .{ .r = 67, .g = 76, .b = 94 } }, // nord2
    .selection_bg = .{ .rgb = .{ .r = 136, .g = 192, .b = 208 } }, // nord8
    .selection_fg = .{ .rgb = .{ .r = 46, .g = 52, .b = 64 } }, // nord0
};

/// Dracula theme (https://draculatheme.com/)
pub const dracula: Theme = .{
    .background = .{ .rgb = .{ .r = 40, .g = 42, .b = 54 } },
    .foreground = .{ .rgb = .{ .r = 248, .g = 248, .b = 242 } },
    .primary = .{ .rgb = .{ .r = 189, .g = 147, .b = 249 } }, // purple
    .secondary = .{ .rgb = .{ .r = 139, .g = 233, .b = 253 } }, // cyan
    .success = .{ .rgb = .{ .r = 80, .g = 250, .b = 123 } }, // green
    .warning = .{ .rgb = .{ .r = 241, .g = 250, .b = 140 } }, // yellow
    .error_color = .{ .rgb = .{ .r = 255, .g = 85, .b = 85 } }, // red
    .info = .{ .rgb = .{ .r = 139, .g = 233, .b = 253 } }, // cyan
    .muted = .{ .rgb = .{ .r = 98, .g = 114, .b = 164 } }, // comment
    .border = .{ .rgb = .{ .r = 68, .g = 71, .b = 90 } },
    .selection_bg = .{ .rgb = .{ .r = 68, .g = 71, .b = 90 } },
    .selection_fg = .{ .rgb = .{ .r = 248, .g = 248, .b = 242 } },
};

/// Gruvbox theme (https://github.com/morhetz/gruvbox)
pub const gruvbox: Theme = .{
    .background = .{ .rgb = .{ .r = 40, .g = 40, .b = 40 } }, // bg0
    .foreground = .{ .rgb = .{ .r = 235, .g = 219, .b = 178 } }, // fg
    .primary = .{ .rgb = .{ .r = 251, .g = 184, .b = 108 } }, // orange
    .secondary = .{ .rgb = .{ .r = 142, .g = 192, .b = 124 } }, // aqua
    .success = .{ .rgb = .{ .r = 184, .g = 187, .b = 38 } }, // green
    .warning = .{ .rgb = .{ .r = 250, .g = 189, .b = 47 } }, // yellow
    .error_color = .{ .rgb = .{ .r = 251, .g = 73, .b = 52 } }, // red
    .info = .{ .rgb = .{ .r = 131, .g = 165, .b = 152 } }, // blue
    .muted = .{ .rgb = .{ .r = 146, .g = 131, .b = 116 } }, // gray
    .border = .{ .rgb = .{ .r = 80, .g = 73, .b = 69 } }, // bg2
    .selection_bg = .{ .rgb = .{ .r = 80, .g = 73, .b = 69 } }, // bg2
    .selection_fg = .{ .rgb = .{ .r = 235, .g = 219, .b = 178 } }, // fg
};

/// Solarized Dark theme
pub const solarized_dark: Theme = .{
    .background = .{ .rgb = .{ .r = 0, .g = 43, .b = 54 } }, // base03
    .foreground = .{ .rgb = .{ .r = 131, .g = 148, .b = 150 } }, // base0
    .primary = .{ .rgb = .{ .r = 38, .g = 139, .b = 210 } }, // blue
    .secondary = .{ .rgb = .{ .r = 42, .g = 161, .b = 152 } }, // cyan
    .success = .{ .rgb = .{ .r = 133, .g = 153, .b = 0 } }, // green
    .warning = .{ .rgb = .{ .r = 181, .g = 137, .b = 0 } }, // yellow
    .error_color = .{ .rgb = .{ .r = 220, .g = 50, .b = 47 } }, // red
    .info = .{ .rgb = .{ .r = 38, .g = 139, .b = 210 } }, // blue
    .muted = .{ .rgb = .{ .r = 88, .g = 110, .b = 117 } }, // base01
    .border = .{ .rgb = .{ .r = 7, .g = 54, .b = 66 } }, // base02
    .selection_bg = .{ .rgb = .{ .r = 7, .g = 54, .b = 66 } }, // base02
    .selection_fg = .{ .rgb = .{ .r = 147, .g = 161, .b = 161 } }, // base1
};

/// Get theme by name
pub fn getTheme(name: []const u8) ?Theme {
    const theme_map = std.StaticStringMap(Theme).initComptime(.{
        .{ "default", default_dark },
        .{ "dark", default_dark },
        .{ "light", light },
        .{ "nord", nord },
        .{ "dracula", dracula },
        .{ "gruvbox", gruvbox },
        .{ "solarized", solarized_dark },
        .{ "solarized-dark", solarized_dark },
    });
    return theme_map.get(name);
}

test "Theme - basic creation" {
    const theme = default_dark;
    try std.testing.expectEqual(Color.reset, theme.background);
    try std.testing.expectEqual(Color.bright_blue, theme.primary);
}

test "Theme - style helpers" {
    const theme = default_dark;

    const bg_style = theme.bg();
    try std.testing.expectEqual(theme.background, bg_style.bg.?);
    try std.testing.expectEqual(theme.foreground, bg_style.fg.?);

    const primary = theme.primary_style();
    try std.testing.expectEqual(theme.primary, primary.fg.?);
    try std.testing.expect(primary.bold);

    const err_style = theme.error_style();
    try std.testing.expectEqual(theme.error_color, err_style.fg.?);
    try std.testing.expect(err_style.bold);

    const muted = theme.muted_style();
    try std.testing.expectEqual(theme.muted, muted.fg.?);
    try std.testing.expect(muted.dim);
}

test "Theme - named themes" {
    try std.testing.expect(getTheme("default") != null);
    try std.testing.expect(getTheme("dark") != null);
    try std.testing.expect(getTheme("light") != null);
    try std.testing.expect(getTheme("nord") != null);
    try std.testing.expect(getTheme("dracula") != null);
    try std.testing.expect(getTheme("gruvbox") != null);
    try std.testing.expect(getTheme("solarized") != null);
    try std.testing.expect(getTheme("nonexistent") == null);
}

test "Theme - light theme" {
    const theme = light;
    try std.testing.expectEqual(Color.white, theme.background);
    try std.testing.expectEqual(Color.black, theme.foreground);
    try std.testing.expectEqual(Color.blue, theme.primary);
}

test "Theme - nord theme has RGB colors" {
    const theme = nord;
    switch (theme.background) {
        .rgb => |c| {
            try std.testing.expectEqual(@as(u8, 46), c.r);
            try std.testing.expectEqual(@as(u8, 52), c.g);
            try std.testing.expectEqual(@as(u8, 64), c.b);
        },
        else => return error.ExpectedRgbColor,
    }
}

test "Theme - dracula theme" {
    const theme = dracula;
    switch (theme.primary) {
        .rgb => |c| {
            try std.testing.expectEqual(@as(u8, 189), c.r);
            try std.testing.expectEqual(@as(u8, 147), c.g);
            try std.testing.expectEqual(@as(u8, 249), c.b);
        },
        else => return error.ExpectedRgbColor,
    }
}

test "Theme - selection style" {
    const theme = default_dark;
    const sel = theme.selection_style();
    try std.testing.expectEqual(theme.selection_fg, sel.fg.?);
    try std.testing.expectEqual(theme.selection_bg, sel.bg.?);
}
