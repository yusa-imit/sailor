const std = @import("std");
const Allocator = std.mem.Allocator;
const accessibility = @import("../accessibility.zig");
const Role = accessibility.Role;
const Metadata = accessibility.Metadata;

/// Terminal screen reader integration for TUI applications.
/// Provides enhanced announcements and semantic markup for screen readers.
pub const ScreenReaderOutput = struct {
    allocator: Allocator,
    enabled: bool,
    verbosity: Verbosity,
    output_mode: OutputMode,

    pub const Verbosity = enum {
        quiet, // Only essential announcements
        normal, // Standard screen reader output
        verbose, // Detailed descriptions and hints
    };

    pub const OutputMode = enum {
        /// OSC 8 hyperlink sequences for semantic markup
        osc8,
        /// Plain text with ARIA-like annotations
        aria_text,
        /// JSON structured output (for external screen reader tools)
        json,
        /// Auto-detect based on terminal capabilities
        auto,
    };

    pub fn init(allocator: Allocator) ScreenReaderOutput {
        return .{
            .allocator = allocator,
            .enabled = detectScreenReader(),
            .verbosity = .normal,
            .output_mode = .auto,
        };
    }

    /// Detect if a screen reader is active in the terminal
    pub fn detectScreenReader() bool {
        // Check for screen reader environment variables
        const screen_reader_vars = [_][]const u8{
            "SCREEN_READER", // Generic
            "NVDA", // NVDA on Windows
            "JAWS", // JAWS on Windows
            "ORCA", // Orca on Linux
            "VOICEOVER", // VoiceOver on macOS
        };

        for (screen_reader_vars) |var_name| {
            if (std.posix.getenv(var_name)) |_| {
                return true;
            }
        }

        return false;
    }

    /// Enable or disable screen reader output
    pub fn setEnabled(self: *ScreenReaderOutput, enabled: bool) void {
        self.enabled = enabled;
    }

    /// Set verbosity level
    pub fn setVerbosity(self: *ScreenReaderOutput, verbosity: Verbosity) void {
        self.verbosity = verbosity;
    }

    /// Set output mode
    pub fn setOutputMode(self: *ScreenReaderOutput, mode: OutputMode) void {
        self.output_mode = mode;
    }

    /// Announce a message to the screen reader
    pub fn announce(self: *ScreenReaderOutput, writer: anytype, message: []const u8, priority: AnnouncePriority) !void {
        if (!self.enabled) return;

        // Skip quiet messages in quiet mode
        if (self.verbosity == .quiet and priority == .quiet) return;

        switch (self.output_mode) {
            .osc8 => try self.announceOSC8(writer, message, priority),
            .aria_text => try self.announceAriaText(writer, message, priority),
            .json => try self.announceJson(writer, message, priority),
            .auto => try self.announceAriaText(writer, message, priority), // Default to ARIA text
        }
    }

    pub const AnnouncePriority = enum {
        /// Low priority, can be skipped
        quiet,
        /// Normal priority (default)
        polite,
        /// High priority, should interrupt
        assertive,
    };

    fn announceOSC8(self: *ScreenReaderOutput, writer: anytype, message: []const u8, priority: AnnouncePriority) !void {
        _ = self;
        // OSC 8 hyperlink format: \x1b]8;;params\x1b\\message\x1b]8;;\x1b\\
        const priority_param = switch (priority) {
            .quiet => "priority=quiet",
            .polite => "priority=polite",
            .assertive => "priority=assertive",
        };
        try writer.print("\x1b]8;;{s}\x1b\\{s}\x1b]8;;\x1b\\", .{ priority_param, message });
    }

    fn announceAriaText(self: *ScreenReaderOutput, writer: anytype, message: []const u8, priority: AnnouncePriority) !void {
        _ = self;
        const priority_str = switch (priority) {
            .quiet => "[quiet]",
            .polite => "[polite]",
            .assertive => "[assertive]",
        };
        try writer.print("{s} {s}\n", .{ priority_str, message });
    }

    fn announceJson(self: *ScreenReaderOutput, writer: anytype, message: []const u8, priority: AnnouncePriority) !void {
        _ = self;
        try writer.print("{{\"type\":\"announce\",\"priority\":\"{s}\",\"message\":\"{s}\"}}\n", .{
            @tagName(priority),
            message,
        });
    }

    /// Announce widget metadata
    pub fn announceWidget(self: *ScreenReaderOutput, writer: anytype, metadata: Metadata) !void {
        if (!self.enabled) return;

        const hint = try accessibility.generateHint(self.allocator, metadata);
        defer self.allocator.free(hint);

        const priority: AnnouncePriority = switch (metadata.live) {
            .off => .quiet,
            .polite => .polite,
            .assertive => .assertive,
        };

        try self.announce(writer, hint, priority);
    }

    /// Announce navigation event
    pub fn announceNavigation(self: *ScreenReaderOutput, writer: anytype, from: ?[]const u8, to: []const u8) !void {
        if (!self.enabled) return;

        var buf: [512]u8 = undefined;
        const message = if (from) |f|
            try std.fmt.bufPrint(&buf, "Navigated from {s} to {s}", .{ f, to })
        else
            try std.fmt.bufPrint(&buf, "Navigated to {s}", .{to});

        try self.announce(writer, message, .polite);
    }

    /// Announce error
    pub fn announceError(self: *ScreenReaderOutput, writer: anytype, error_msg: []const u8) !void {
        if (!self.enabled) return;

        var buf: [512]u8 = undefined;
        const message = try std.fmt.bufPrint(&buf, "Error: {s}", .{error_msg});

        try self.announce(writer, message, .assertive);
    }

    /// Announce success
    pub fn announceSuccess(self: *ScreenReaderOutput, writer: anytype, success_msg: []const u8) !void {
        if (!self.enabled) return;

        var buf: [512]u8 = undefined;
        const message = try std.fmt.bufPrint(&buf, "Success: {s}", .{success_msg});

        try self.announce(writer, message, .polite);
    }

    /// Announce keyboard shortcut hint
    pub fn announceShortcut(self: *ScreenReaderOutput, writer: anytype, key: []const u8, action: []const u8) !void {
        if (!self.enabled) return;
        if (self.verbosity == .quiet) return; // Skip shortcuts in quiet mode

        var buf: [512]u8 = undefined;
        const message = try std.fmt.bufPrint(&buf, "Press {s} to {s}", .{ key, action });

        try self.announce(writer, message, .quiet);
    }

    /// Announce context-sensitive help
    pub fn announceHelp(self: *ScreenReaderOutput, writer: anytype, help_text: []const u8) !void {
        if (!self.enabled) return;
        if (self.verbosity != .verbose) return; // Only in verbose mode

        try self.announce(writer, help_text, .quiet);
    }
};

/// Region labeling for screen reader navigation
pub const Region = struct {
    name: []const u8,
    role: Role,
    landmarks: []const Landmark = &.{},

    pub const Landmark = struct {
        name: []const u8,
        shortcut: ?[]const u8 = null,
    };

    /// Generate region announcement
    pub fn announce(self: Region, allocator: Allocator) ![]const u8 {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(allocator);
        const writer = buf.writer(allocator);

        try writer.print("Region: {s}, ", .{self.name});
        try writer.print("{s}", .{@tagName(self.role)});

        if (self.landmarks.len > 0) {
            try writer.print(", Landmarks: ", .{});
            for (self.landmarks, 0..) |landmark, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("{s}", .{landmark.name});
                if (landmark.shortcut) |shortcut| {
                    try writer.print(" ({s})", .{shortcut});
                }
            }
        }

        return buf.toOwnedSlice(allocator);
    }
};

// Tests
test "ScreenReaderOutput: init" {
    const allocator = std.testing.allocator;
    const sr = ScreenReaderOutput.init(allocator);

    // Detection should work (true or false is fine)
    try std.testing.expect(sr.enabled == true or sr.enabled == false);
    try std.testing.expectEqual(ScreenReaderOutput.Verbosity.normal, sr.verbosity);
}

test "ScreenReaderOutput: enable/disable" {
    const allocator = std.testing.allocator;
    var sr = ScreenReaderOutput.init(allocator);

    sr.setEnabled(true);
    try std.testing.expect(sr.enabled);

    sr.setEnabled(false);
    try std.testing.expect(!sr.enabled);
}

test "ScreenReaderOutput: set verbosity" {
    const allocator = std.testing.allocator;
    var sr = ScreenReaderOutput.init(allocator);

    sr.setVerbosity(.quiet);
    try std.testing.expectEqual(ScreenReaderOutput.Verbosity.quiet, sr.verbosity);

    sr.setVerbosity(.verbose);
    try std.testing.expectEqual(ScreenReaderOutput.Verbosity.verbose, sr.verbosity);
}

test "ScreenReaderOutput: announce ARIA text" {
    const allocator = std.testing.allocator;
    var sr = ScreenReaderOutput.init(allocator);
    sr.setEnabled(true);
    sr.setOutputMode(.aria_text);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try sr.announce(writer, "Test message", .polite);

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "[polite]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Test message") != null);
}

test "ScreenReaderOutput: announce JSON" {
    const allocator = std.testing.allocator;
    var sr = ScreenReaderOutput.init(allocator);
    sr.setEnabled(true);
    sr.setOutputMode(.json);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try sr.announce(writer, "Test", .assertive);

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "\"type\":\"announce\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"priority\":\"assertive\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"message\":\"Test\"") != null);
}

test "ScreenReaderOutput: announce widget" {
    const allocator = std.testing.allocator;
    var sr = ScreenReaderOutput.init(allocator);
    sr.setEnabled(true);
    sr.setOutputMode(.aria_text);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    const metadata = Metadata{
        .role = .button,
        .label = "Submit",
        .state = .{ .focused = true },
    };

    try sr.announceWidget(writer, metadata);

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "button") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Submit") != null);
}

test "ScreenReaderOutput: announce navigation" {
    const allocator = std.testing.allocator;
    var sr = ScreenReaderOutput.init(allocator);
    sr.setEnabled(true);
    sr.setOutputMode(.aria_text);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try sr.announceNavigation(writer, "Home", "Settings");

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "Navigated from Home to Settings") != null);
}

test "ScreenReaderOutput: announce error" {
    const allocator = std.testing.allocator;
    var sr = ScreenReaderOutput.init(allocator);
    sr.setEnabled(true);
    sr.setOutputMode(.aria_text);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try sr.announceError(writer, "File not found");

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "Error: File not found") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[assertive]") != null);
}

test "ScreenReaderOutput: announce success" {
    const allocator = std.testing.allocator;
    var sr = ScreenReaderOutput.init(allocator);
    sr.setEnabled(true);
    sr.setOutputMode(.aria_text);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try sr.announceSuccess(writer, "File saved");

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "Success: File saved") != null);
}

test "ScreenReaderOutput: announce shortcut" {
    const allocator = std.testing.allocator;
    var sr = ScreenReaderOutput.init(allocator);
    sr.setEnabled(true);
    sr.setOutputMode(.aria_text);
    sr.setVerbosity(.normal);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try sr.announceShortcut(writer, "Ctrl+S", "save");

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "Press Ctrl+S to save") != null);
}

test "ScreenReaderOutput: quiet mode skips shortcuts" {
    const allocator = std.testing.allocator;
    var sr = ScreenReaderOutput.init(allocator);
    sr.setEnabled(true);
    sr.setOutputMode(.aria_text);
    sr.setVerbosity(.quiet);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try sr.announceShortcut(writer, "Ctrl+S", "save");

    const output = buf.items;
    try std.testing.expectEqual(@as(usize, 0), output.len); // Should be empty
}

test "ScreenReaderOutput: announce help" {
    const allocator = std.testing.allocator;
    var sr = ScreenReaderOutput.init(allocator);
    sr.setEnabled(true);
    sr.setOutputMode(.aria_text);
    sr.setVerbosity(.verbose);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try sr.announceHelp(writer, "Use arrow keys to navigate");

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "Use arrow keys") != null);
}

test "ScreenReaderOutput: disabled skips announcements" {
    const allocator = std.testing.allocator;
    var sr = ScreenReaderOutput.init(allocator);
    sr.setEnabled(false);
    sr.setOutputMode(.aria_text);

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try sr.announce(writer, "Test", .polite);

    const output = buf.items;
    try std.testing.expectEqual(@as(usize, 0), output.len); // Should be empty
}

test "Region: announce" {
    const allocator = std.testing.allocator;

    const landmarks = [_]Region.Landmark{
        .{ .name = "Search", .shortcut = "Ctrl+F" },
        .{ .name = "Settings", .shortcut = "Ctrl+," },
    };

    const region = Region{
        .name = "Main Content",
        .role = .application,
        .landmarks = &landmarks,
    };

    const announcement = try region.announce(allocator);
    defer allocator.free(announcement);

    try std.testing.expect(std.mem.indexOf(u8, announcement, "Region: Main Content") != null);
    try std.testing.expect(std.mem.indexOf(u8, announcement, "Search") != null);
    try std.testing.expect(std.mem.indexOf(u8, announcement, "Ctrl+F") != null);
}

test "Region: announce without landmarks" {
    const allocator = std.testing.allocator;

    const region = Region{
        .name = "Sidebar",
        .role = .group,
    };

    const announcement = try region.announce(allocator);
    defer allocator.free(announcement);

    try std.testing.expect(std.mem.indexOf(u8, announcement, "Region: Sidebar") != null);
    try std.testing.expect(std.mem.indexOf(u8, announcement, "group") != null);
}
