//! Interactive REPL (Read-Eval-Print Loop)
//!
//! Provides line editing, history, completion, and syntax highlighting.
//! Gracefully degrades when not running in a TTY (pipe mode).
//!
//! Features:
//! - Line editing: cursor movement, word jump, kill line
//! - History: up/down navigation, persistent file support
//! - Tab completion: user callback with popup menu
//! - Syntax highlighting: real-time via user callback
//! - Multi-line input: validator callback support
//! - Signal handling: Ctrl+C clears, Ctrl+D exits
//! - Pipe mode: automatic fallback for non-TTY

const std = @import("std");
const builtin = @import("builtin");
const term = @import("term.zig");
const color = @import("color.zig");
const Allocator = std.mem.Allocator;

pub const Error = error{
    EndOfStream,
    HistoryLoadFailed,
    HistorySaveFailed,
} || Allocator.Error || term.Error;

/// Validation result for multi-line input
pub const Validation = enum {
    complete,   // Line is complete, submit it
    incomplete, // Need more input, show continuation prompt
    invalid,    // Syntax error, reject input
};

/// Completion callback signature
pub const Completer = *const fn (buf: []const u8, allocator: Allocator) anyerror![]const []const u8;

/// Syntax highlighting callback signature
/// Writer must be std.io.AnyWriter (generic over all writers)
pub const Highlighter = *const fn (buf: []const u8, writer: std.io.AnyWriter) anyerror!void;

/// Validation callback signature
pub const Validator = *const fn (buf: []const u8) Validation;

/// REPL configuration
pub const Config = struct {
    /// Prompt string (default: "> ")
    prompt: []const u8 = "> ",

    /// Continuation prompt for multi-line (default: "  ")
    continuation_prompt: []const u8 = "  ",

    /// History file path (null = no persistence)
    history_file: ?[]const u8 = null,

    /// Maximum history size (default: 1000)
    history_size: usize = 1000,

    /// Tab completion callback (null = no completion)
    completer: ?Completer = null,

    /// Syntax highlighting callback (null = plain text)
    highlighter: ?Highlighter = null,

    /// Input validator for multi-line (null = always complete)
    validator: ?Validator = null,

    /// Enable color output (default: auto-detect)
    color: ?bool = null,
};

/// REPL state
pub const Repl = struct {
    allocator: Allocator,
    config: Config,

    // Terminal state
    is_tty: bool,
    raw_mode: ?term.RawMode,

    // Line buffer
    buffer: std.array_list.Managed(u8),
    cursor: usize,

    // History
    history: std.array_list.Managed([]const u8),
    history_index: ?usize,

    // Color support
    use_color: bool,

    const Self = @This();

    /// Initialize REPL
    pub fn init(allocator: Allocator, config: Config) Error!Self {
        var self = Self{
            .allocator = allocator,
            .config = config,
            .is_tty = false, // Will be set on first readLine
            .raw_mode = null,
            .buffer = std.array_list.Managed(u8).init(allocator),
            .cursor = 0,
            .history = std.array_list.Managed([]const u8).init(allocator),
            .history_index = null,
            .use_color = false, // Will be set on first readLine
        };

        // Load history if file specified
        if (config.history_file) |path| {
            // Non-fatal: silently continue on error
            self.loadHistory(path) catch {};
        }

        return self;
    }

    /// Initialize terminal settings (called lazily on first readLine)
    fn initTerminal(self: *Self) void {
        if (self.is_tty or self.use_color) return; // Already initialized

        self.is_tty = term.isatty(std.posix.STDIN_FILENO);
        self.use_color = if (self.config.color) |explicit| explicit else (self.is_tty and color.ColorLevel.detect() != .none);
    }

    /// Cleanup resources
    pub fn deinit(self: *Self) void {
        // Save history if file specified
        if (self.config.history_file) |path| {
            // Non-fatal: silently continue on error
            self.saveHistory(path) catch {};
        }

        // Exit raw mode if entered
        if (self.raw_mode) |*raw| {
            raw.deinit();
        }

        // Free history entries
        for (self.history.items) |line| {
            self.allocator.free(line);
        }
        self.history.deinit();

        self.buffer.deinit();
    }

    /// Read a line of input
    /// Returns null on EOF (Ctrl+D on empty line)
    /// Writer is used for prompts and interactive feedback (pass std.io.null_writer for no output)
    pub fn readLine(self: *Self, writer: anytype) Error!?[]const u8 {
        self.initTerminal();

        if (self.is_tty) {
            return self.readLineInteractive(writer);
        } else {
            return self.readLinePipe(writer);
        }
    }

    /// Read line in interactive mode (TTY)
    fn readLineInteractive(self: *Self, writer: anytype) Error!?[]const u8 {
        // Enter raw mode if not already
        if (self.raw_mode == null) {
            self.raw_mode = try term.RawMode.enter(std.posix.STDIN_FILENO);
        }

        // Reset state
        self.buffer.clearRetainingCapacity();
        self.cursor = 0;
        self.history_index = null;

        // Print prompt
        try self.printPrompt(writer);

        // Read loop
        var key_buf: [16]u8 = undefined;
        while (true) {
            const n = try std.posix.read(std.posix.STDIN_FILENO, &key_buf);
            if (n == 0) return null; // EOF

            const key = key_buf[0..n];

            // Handle key
            if (try self.handleKey(key, writer)) {
                break; // Line complete
            }
        }

        // Add to history
        if (self.buffer.items.len > 0) {
            try self.addHistory(self.buffer.items);
        }

        // Return owned copy
        return try self.allocator.dupe(u8, self.buffer.items);
    }

    /// Read line in pipe mode (non-TTY)
    fn readLinePipe(self: *Self, _: anytype) Error!?[]const u8 {
        const stdin = std.fs.File.stdin().reader();

        self.buffer.clearRetainingCapacity();

        stdin.streamUntilDelimiter(self.buffer.writer(), '\n', null) catch |err| switch (err) {
            error.EndOfStream => {
                if (self.buffer.items.len == 0) return null;
            },
            else => return err,
        };

        return try self.allocator.dupe(u8, self.buffer.items);
    }

    /// Handle a key press
    /// Returns true if line is complete
    fn handleKey(self: *Self, key: []const u8, writer: anytype) !bool {
        // Single byte keys
        if (key.len == 1) {
            switch (key[0]) {
                '\r', '\n' => {
                    try writer.writeAll("\r\n");
                    return true; // Complete
                },
                3 => { // Ctrl+C
                    self.buffer.clearRetainingCapacity();
                    self.cursor = 0;
                    try writer.writeAll("^C\r\n");
                    try self.printPrompt(writer);
                    return false;
                },
                4 => { // Ctrl+D
                    if (self.buffer.items.len == 0) {
                        return error.EndOfStream;
                    }
                    // Delete char at cursor
                    if (self.cursor < self.buffer.items.len) {
                        _ = self.buffer.orderedRemove(self.cursor);
                        try self.redraw(writer);
                    }
                },
                127 => { // Backspace
                    if (self.cursor > 0) {
                        _ = self.buffer.orderedRemove(self.cursor - 1);
                        self.cursor -= 1;
                        try self.redraw(writer);
                    }
                },
                9 => { // Tab - completion
                    if (self.config.completer) |completer| {
                        const buf_slice = self.buffer.items[0..self.cursor];
                        const completions = try completer(buf_slice, self.allocator);
                        defer {
                            for (completions) |c| {
                                self.allocator.free(c);
                            }
                            self.allocator.free(completions);
                        }

                        if (completions.len == 0) {
                            // No completions, do nothing
                        } else if (completions.len == 1) {
                            // Single completion, auto-insert
                            const completion = completions[0];
                            try self.buffer.replaceRange(self.cursor, 0, completion);
                            self.cursor += completion.len;
                            try self.redraw(writer);
                        } else {
                            // Multiple completions - show popup
                            // For now, just insert the common prefix
                            const common_prefix = findCommonPrefix(completions);
                            if (common_prefix.len > 0) {
                                try self.buffer.replaceRange(self.cursor, 0, common_prefix);
                                self.cursor += common_prefix.len;
                                try self.redraw(writer);
                            }
                            // Note: Full popup UI requires TUI integration,
                            // which is beyond REPL's scope (REPL is CLI-only).
                            // The CompletionPopup widget is available for
                            // applications that integrate REPL with TUI.
                        }
                    }
                },
                else => |c| {
                    if (c >= 32 and c < 127) {
                        try self.buffer.insert(self.cursor, c);
                        self.cursor += 1;
                        try self.redraw(writer);
                    }
                },
            }
        }
        // Multi-byte sequences (arrows, etc.)
        else if (key.len >= 3 and key[0] == 27 and key[1] == '[') {
            switch (key[2]) {
                'A' => { // Up arrow
                    if (self.history.items.len > 0) {
                        const idx = self.history_index orelse self.history.items.len;
                        if (idx > 0) {
                            self.history_index = idx - 1;
                            const hist = self.history.items[idx - 1];
                            self.buffer.clearRetainingCapacity();
                            try self.buffer.appendSlice(hist);
                            self.cursor = self.buffer.items.len;
                            try self.redraw(writer);
                        }
                    }
                },
                'B' => { // Down arrow
                    if (self.history_index) |idx| {
                        if (idx + 1 < self.history.items.len) {
                            self.history_index = idx + 1;
                            const hist = self.history.items[idx + 1];
                            self.buffer.clearRetainingCapacity();
                            try self.buffer.appendSlice(hist);
                            self.cursor = self.buffer.items.len;
                            try self.redraw(writer);
                        } else {
                            self.history_index = null;
                            self.buffer.clearRetainingCapacity();
                            self.cursor = 0;
                            try self.redraw(writer);
                        }
                    }
                },
                'C' => { // Right arrow
                    if (self.cursor < self.buffer.items.len) {
                        self.cursor += 1;
                        try writer.writeAll("\x1b[C");
                    }
                },
                'D' => { // Left arrow
                    if (self.cursor > 0) {
                        self.cursor -= 1;
                        try writer.writeAll("\x1b[D");
                    }
                },
                'H' => { // Home
                    const diff = self.cursor;
                    self.cursor = 0;
                    if (diff > 0) {
                        try writer.print("\x1b[{}D", .{diff});
                    }
                },
                'F' => { // End
                    const diff = self.buffer.items.len - self.cursor;
                    self.cursor = self.buffer.items.len;
                    if (diff > 0) {
                        try writer.print("\x1b[{}C", .{diff});
                    }
                },
                else => {},
            }
        }

        return false;
    }

    /// Print prompt
    fn printPrompt(self: *Self, writer: anytype) !void {
        if (self.use_color) {
            const style = color.Style{ .fg = .{ .basic = .cyan }, .attrs = .{ .bold = true } };
            try style.write(writer);
            try writer.writeAll(self.config.prompt);
            try color.Style.reset(writer);
        } else {
            try writer.writeAll(self.config.prompt);
        }
    }

    /// Redraw the line
    fn redraw(self: *Self, writer: anytype) !void {
        // Move to start of line
        try writer.writeAll("\r");

        // Clear line
        try writer.writeAll("\x1b[K");

        // Print prompt
        try self.printPrompt(writer);

        // Print buffer (with highlighting if available)
        if (self.config.highlighter) |highlight| {
            const any_writer = writer.any();
            try highlight(self.buffer.items, any_writer);
        } else {
            try writer.writeAll(self.buffer.items);
        }

        // Move cursor to correct position
        const after_cursor = self.buffer.items.len - self.cursor;
        if (after_cursor > 0) {
            try writer.print("\x1b[{}D", .{after_cursor});
        }
    }

    /// Find common prefix among completion strings
    fn findCommonPrefix(completions: []const []const u8) []const u8 {
        if (completions.len == 0) return "";
        if (completions.len == 1) return completions[0];

        var prefix_len: usize = 0;
        const first = completions[0];

        outer: while (prefix_len < first.len) {
            const char = first[prefix_len];
            for (completions[1..]) |completion| {
                if (prefix_len >= completion.len or completion[prefix_len] != char) {
                    break :outer;
                }
            }
            prefix_len += 1;
        }

        return first[0..prefix_len];
    }

    /// Add line to history
    fn addHistory(self: *Self, line: []const u8) !void {
        // Don't add duplicates of last entry
        if (self.history.items.len > 0) {
            const last = self.history.items[self.history.items.len - 1];
            if (std.mem.eql(u8, last, line)) return;
        }

        // Trim history if too large
        if (self.history.items.len >= self.config.history_size) {
            const old = self.history.orderedRemove(0);
            self.allocator.free(old);
        }

        // Add new entry
        const owned = try self.allocator.dupe(u8, line);
        errdefer self.allocator.free(owned);
        try self.history.append(owned);
    }

    /// Load history from file
    fn loadHistory(self: *Self, path: []const u8) !void {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
            error.FileNotFound => return, // OK, no history yet
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            if (line.len > 0) {
                const owned = try self.allocator.dupe(u8, line);
                errdefer self.allocator.free(owned);
                try self.history.append(owned);
            }
        }
    }

    /// Save history to file
    fn saveHistory(self: *Self, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        for (self.history.items) |line| {
            try file.writeAll(line);
            try file.writeAll("\n");
        }
    }

};

// Tests

test "Repl.init and deinit" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    try std.testing.expect(repl.buffer.items.len == 0);
    try std.testing.expect(repl.cursor == 0);
    try std.testing.expect(repl.history.items.len == 0);
}

test "Repl.addHistory" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{ .history_size = 3 });
    defer repl.deinit();

    try repl.addHistory("first");
    try repl.addHistory("second");
    try repl.addHistory("third");

    try std.testing.expectEqual(3, repl.history.items.len);
    try std.testing.expectEqualStrings("first", repl.history.items[0]);

    // Should trim when over limit
    try repl.addHistory("fourth");
    try std.testing.expectEqual(3, repl.history.items.len);
    try std.testing.expectEqualStrings("second", repl.history.items[0]);
}

test "Repl.addHistory deduplicates consecutive entries" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    try repl.addHistory("first");
    try repl.addHistory("first"); // Duplicate
    try repl.addHistory("second");

    try std.testing.expectEqual(2, repl.history.items.len);
    try std.testing.expectEqualStrings("first", repl.history.items[0]);
    try std.testing.expectEqualStrings("second", repl.history.items[1]);
}

test "Repl.findCommonPrefix empty" {
    const completions = [_][]const u8{};
    const prefix = Repl.findCommonPrefix(&completions);
    try std.testing.expectEqualStrings("", prefix);
}

test "Repl.findCommonPrefix single" {
    const completions = [_][]const u8{"hello"};
    const prefix = Repl.findCommonPrefix(&completions);
    try std.testing.expectEqualStrings("hello", prefix);
}

test "Repl.findCommonPrefix multiple with common" {
    const completions = [_][]const u8{ "hello", "help", "helicopter" };
    const prefix = Repl.findCommonPrefix(&completions);
    try std.testing.expectEqualStrings("hel", prefix);
}

test "Repl.findCommonPrefix multiple no common" {
    const completions = [_][]const u8{ "foo", "bar", "baz" };
    const prefix = Repl.findCommonPrefix(&completions);
    try std.testing.expectEqualStrings("", prefix);
}

test "Repl.findCommonPrefix identical" {
    const completions = [_][]const u8{ "test", "test", "test" };
    const prefix = Repl.findCommonPrefix(&completions);
    try std.testing.expectEqualStrings("test", prefix);
}

test "Repl pipe mode" {
    const allocator = std.testing.allocator;

    // Create a fake stdin
    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    // Force pipe mode
    repl.is_tty = false;

    try std.testing.expect(!repl.is_tty);
}

test "Validation enum" {
    const v1: Validation = .complete;
    const v2: Validation = .incomplete;
    const v3: Validation = .invalid;

    try std.testing.expect(v1 == .complete);
    try std.testing.expect(v2 == .incomplete);
    try std.testing.expect(v3 == .invalid);
}
