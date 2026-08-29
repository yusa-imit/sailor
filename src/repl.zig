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
    complete, // Line is complete, submit it
    incomplete, // Need more input, show continuation prompt
    invalid, // Syntax error, reject input
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

    /// Enable bracketed paste mode (default: true)
    enable_bracketed_paste: bool = true,
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

    // Bracketed paste mode
    paste_mode: ?term.BracketedPaste = null,
    in_paste: bool = false,
    paste_buffer: std.array_list.Managed(u8),

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
            .paste_mode = null,
            .in_paste = false,
            .paste_buffer = std.array_list.Managed(u8).init(allocator),
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

        // Disable bracketed paste mode if enabled
        if (self.paste_mode) |paste| {
            paste.deinit();
        }

        // Free history entries
        for (self.history.items) |line| {
            self.allocator.free(line);
        }
        self.history.deinit();

        self.buffer.deinit();
        self.paste_buffer.deinit();
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

        // Enable bracketed paste mode if not already enabled
        if (self.config.enable_bracketed_paste and self.paste_mode == null) {
            self.paste_mode = term.BracketedPaste.enable(writer.any()) catch null;
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
        // Handle bracketed paste markers
        if (self.in_paste) {
            // Look for end marker
            if (std.mem.indexOf(u8, key, "\x1b[201~")) |idx| {
                // End marker found
                // Append content before end marker to paste_buffer
                try self.paste_buffer.appendSlice(key[0..idx]);

                // Insert entire paste into buffer
                try self.buffer.replaceRange(self.cursor, 0, self.paste_buffer.items);
                self.cursor += self.paste_buffer.items.len;

                // Clear paste state
                self.paste_buffer.clearRetainingCapacity();
                self.in_paste = false;

                // Redraw
                try self.redraw(writer);

                // Handle any bytes after end marker
                const after_marker = idx + 6; // len("\x1b[201~") = 6
                if (after_marker < key.len) {
                    return self.handleKey(key[after_marker..], writer);
                }
                return false;
            } else {
                // No end marker, accumulate content
                try self.paste_buffer.appendSlice(key);
                return false;
            }
        } else if (std.mem.startsWith(u8, key, "\x1b[200~")) {
            // Start marker found
            const remainder = key[6..]; // len("\x1b[200~") = 6

            // Search remainder for end marker
            if (std.mem.indexOf(u8, remainder, "\x1b[201~")) |j| {
                // End marker found in same chunk
                // Insert content between markers
                try self.buffer.replaceRange(self.cursor, 0, remainder[0..j]);
                self.cursor += j;

                // Redraw
                try self.redraw(writer);

                // Handle any bytes after end marker
                const after_marker = j + 6; // len("\x1b[201~") = 6
                if (after_marker < remainder.len) {
                    return self.handleKey(remainder[after_marker..], writer);
                }
                return false;
            } else {
                // No end marker yet, start accumulating
                try self.paste_buffer.appendSlice(remainder);
                self.in_paste = true;
                return false;
            }
        }

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
                0x15 => { // Ctrl+U - kill from line start to cursor (unix-line-discard)
                    if (self.cursor > 0) {
                        try self.buffer.replaceRange(0, self.cursor, "");
                        self.cursor = 0;
                        try self.redraw(writer);
                    }
                },
                0x0B => { // Ctrl+K - kill from cursor to end (kill-line)
                    if (self.cursor < self.buffer.items.len) {
                        try self.buffer.replaceRange(self.cursor, self.buffer.items.len - self.cursor, "");
                        try self.redraw(writer);
                    }
                },
                0x17 => { // Ctrl+W - kill word backward (unix-word-rubout)
                    if (self.cursor > 0) {
                        const word_start = wordStartBefore(self.buffer.items, self.cursor);
                        try self.buffer.replaceRange(word_start, self.cursor - word_start, "");
                        self.cursor = word_start;
                        try self.redraw(writer);
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
        // 2-byte Alt/Meta sequences (Alt+B, Alt+F)
        else if (key.len == 2 and key[0] == 27) {
            switch (key[1]) {
                'b' => { // Alt+B - move cursor backward to start of previous word
                    const new_cursor = wordStartBefore(self.buffer.items, self.cursor);
                    if (new_cursor != self.cursor) {
                        const diff = self.cursor - new_cursor;
                        self.cursor = new_cursor;
                        try writer.print("\x1b[{}D", .{diff});
                    }
                },
                'f' => { // Alt+F - move cursor forward to end of next word
                    const new_cursor = wordEndAfter(self.buffer.items, self.cursor);
                    if (new_cursor != self.cursor) {
                        const diff = new_cursor - self.cursor;
                        self.cursor = new_cursor;
                        try writer.print("\x1b[{}C", .{diff});
                    }
                },
                else => {},
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

    /// Find the start of the word before the given cursor position
    /// Skip trailing whitespace backward, then skip non-whitespace backward
    fn wordStartBefore(buf: []const u8, from: usize) usize {
        var pos = from;
        while (pos > 0 and std.ascii.isWhitespace(buf[pos - 1])) pos -= 1;
        while (pos > 0 and !std.ascii.isWhitespace(buf[pos - 1])) pos -= 1;
        return pos;
    }

    /// Find the end of the word after the given cursor position
    /// Skip leading whitespace forward, then skip non-whitespace forward
    fn wordEndAfter(buf: []const u8, from: usize) usize {
        var pos = from;
        while (pos < buf.len and std.ascii.isWhitespace(buf[pos])) pos += 1;
        while (pos < buf.len and !std.ascii.isWhitespace(buf[pos])) pos += 1;
        return pos;
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

test "loadHistory with missing file is caught gracefully" {
    const allocator = std.testing.allocator;

    // loadHistory catches FileNotFound at line 439 and returns void (no error)
    // This tests that missing files don't cause init to fail
    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    // History should be empty when file doesn't exist
    try std.testing.expectEqual(0, repl.history.items.len);
}

test "init with missing history file does not error" {
    const allocator = std.testing.allocator;

    // init calls loadHistory internally and silently catches errors
    var repl = try Repl.init(allocator, .{ .history_file = "/nonexistent/history.txt" });
    defer repl.deinit();

    // Repl should still be valid even if history file doesn't exist
    try std.testing.expectEqual(0, repl.history.items.len);
}

test "addHistory enforces max size limit" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{ .history_size = 2 });
    defer repl.deinit();

    // Add beyond limit
    try repl.addHistory("first");
    try repl.addHistory("second");
    try repl.addHistory("third");

    // Should trim oldest (first)
    try std.testing.expectEqual(2, repl.history.items.len);
    try std.testing.expectEqualStrings("second", repl.history.items[0]);
    try std.testing.expectEqualStrings("third", repl.history.items[1]);

    try repl.addHistory("fourth");
    try std.testing.expectEqual(2, repl.history.items.len);
    try std.testing.expectEqualStrings("third", repl.history.items[0]);
    try std.testing.expectEqualStrings("fourth", repl.history.items[1]);
}

test "addHistory prevents consecutive duplicates but allows later duplicates" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{ .history_size = 10 });
    defer repl.deinit();

    try repl.addHistory("cmd1");
    try repl.addHistory("cmd1"); // Duplicate - should not be added
    try std.testing.expectEqual(1, repl.history.items.len);

    try repl.addHistory("cmd2");
    try repl.addHistory("cmd1"); // Same cmd1 but not consecutive - SHOULD be added (line 419 only blocks immediate dupes)
    try std.testing.expectEqual(3, repl.history.items.len);
    try std.testing.expectEqualStrings("cmd1", repl.history.items[2]);
}

test "findCommonPrefix with different first char has no prefix" {
    const completions = [_][]const u8{ "apple", "banana", "cherry" };
    const prefix = Repl.findCommonPrefix(&completions);
    try std.testing.expectEqualStrings("", prefix);
}

test "addHistory with empty line is rejected" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    try repl.addHistory("");
    // Empty lines should still be added (readLineInteractive filters at line 189 with `if (self.buffer.items.len > 0)`)
    try std.testing.expectEqual(1, repl.history.items.len);
}

test "addHistory respects history_size boundary" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{ .history_size = 3 });
    defer repl.deinit();

    try repl.addHistory("a");
    try repl.addHistory("b");
    try repl.addHistory("c");
    try std.testing.expectEqual(3, repl.history.items.len);

    // Adding 4th should trigger trim at line 426 (orderedRemove(0))
    try repl.addHistory("d");
    try std.testing.expectEqual(3, repl.history.items.len);
    try std.testing.expectEqualStrings("b", repl.history.items[0]); // "a" was removed
    try std.testing.expectEqualStrings("d", repl.history.items[2]); // "d" was added
}

test "Repl.buffer starts empty" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    try std.testing.expectEqual(0, repl.buffer.items.len);
    try std.testing.expectEqual(0, repl.cursor);
}

// ============================================================================
// Bracketed Paste Tests
// ============================================================================

test "Config default: enable_bracketed_paste is true" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    // New Config field: enable_bracketed_paste should default to true
    try std.testing.expect(repl.config.enable_bracketed_paste);
}

test "single-chunk paste with embedded newline" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    // Use a null writer since we don't care about output
    const writer = std.io.null_writer;

    // Call handleKey with a complete single-chunk paste containing a newline
    const complete = try repl.handleKey("\x1b[200~line1\nline2\x1b[201~", writer);

    // Should return false (line not complete)
    try std.testing.expect(!complete);

    // Buffer should contain the pasted content with newline preserved as literal byte
    try std.testing.expectEqualStrings("line1\nline2", repl.buffer.items);

    // Cursor should be at end of inserted content
    try std.testing.expectEqual(@as(usize, 11), repl.cursor);

    // Should no longer be in paste mode
    try std.testing.expect(!repl.in_paste);
}

test "multi-chunk paste simulating large paste split across read() calls" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // First chunk: start marker + partial content, no end marker
    const complete1 = try repl.handleKey("\x1b[200~hello ", writer);
    try std.testing.expect(!complete1);
    try std.testing.expect(repl.in_paste); // Should be in paste mode
    try std.testing.expectEqual(@as(usize, 0), repl.buffer.items.len); // Nothing inserted yet
    try std.testing.expect(repl.paste_buffer.items.len > 0); // Content accumulated

    // Second chunk: more content, no end marker
    const complete2 = try repl.handleKey("world", writer);
    try std.testing.expect(!complete2);
    try std.testing.expect(repl.in_paste); // Still in paste mode
    try std.testing.expectEqual(@as(usize, 0), repl.buffer.items.len); // Still nothing inserted

    // Third chunk: final content + end marker
    const complete3 = try repl.handleKey(" done\x1b[201~", writer);
    try std.testing.expect(!complete3); // Still not "line complete" via Enter
    try std.testing.expect(!repl.in_paste); // Should exit paste mode
    try std.testing.expectEqualStrings("hello world done", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 16), repl.cursor);
    try std.testing.expectEqual(@as(usize, 0), repl.paste_buffer.items.len); // Cleared after flush
}

test "paste with trailing bytes after end marker in same chunk" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Paste content followed by explicit Enter keypress in the same chunk
    const complete = try repl.handleKey("\x1b[200~abc\x1b[201~\r", writer);

    // Should return true because the trailing \r is processed as Enter (line complete)
    try std.testing.expect(complete);

    // Buffer should contain just the pasted content
    try std.testing.expectEqualStrings("abc", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 3), repl.cursor);
}

test "cursor position after paste followed by normal character insert" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // First: paste some content
    _ = try repl.handleKey("\x1b[200~hello\x1b[201~", writer);
    try std.testing.expectEqualStrings("hello", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 5), repl.cursor);

    // Then: insert a normal character
    _ = try repl.handleKey("x", writer);

    // Should be inserted at cursor position (end), buffer becomes "hellox"
    try std.testing.expectEqualStrings("hellox", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 6), repl.cursor);
}

test "empty paste is handled safely" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Empty paste: start marker immediately followed by end marker
    const complete = try repl.handleKey("\x1b[200~\x1b[201~", writer);

    // Should not crash, return false (not line complete)
    try std.testing.expect(!complete);

    // Buffer should be empty
    try std.testing.expectEqual(@as(usize, 0), repl.buffer.items.len);
    try std.testing.expect(!repl.in_paste);
}

test "paste inserted at mid-buffer cursor position" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    // Setup: buffer = "ab", cursor = 1 (between 'a' and 'b')
    try repl.buffer.appendSlice("ab");
    repl.cursor = 1;

    const writer = std.io.null_writer;

    // Paste "XY" at cursor position 1
    _ = try repl.handleKey("\x1b[200~XY\x1b[201~", writer);

    // Result should be "aXYb" (pasted at cursor, not appended)
    try std.testing.expectEqualStrings("aXYb", repl.buffer.items);

    // Cursor should be at position 3 (after "XY")
    try std.testing.expectEqual(@as(usize, 3), repl.cursor);
}

test "Repl.deinit() safely handles unflushed paste content" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Simulate interrupted paste: only start marker + content, no end marker
    _ = try repl.handleKey("\x1b[200~partial paste data", writer);

    // Should be in paste mode with leftover data in paste_buffer
    try std.testing.expect(repl.in_paste);
    try std.testing.expect(repl.paste_buffer.items.len > 0);

    // Now deinit() is called (via defer in the outer test block)
    // This should not crash or leak - paste_buffer.deinit() is called
    // Test passes if no leak is detected by std.testing.allocator
}

test "paste mode flag is initialized to false" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    // in_paste should be false initially
    try std.testing.expect(!repl.in_paste);
}

test "paste_buffer accumulates content across multiple chunks" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // First chunk: start + "chunk1"
    _ = try repl.handleKey("\x1b[200~chunk1", writer);
    try std.testing.expect(repl.in_paste);
    const size_after_first = repl.paste_buffer.items.len;
    try std.testing.expect(size_after_first > 0);

    // Second chunk: "chunk2" (no markers)
    _ = try repl.handleKey("chunk2", writer);
    try std.testing.expect(repl.in_paste);
    const size_after_second = repl.paste_buffer.items.len;

    // Buffer should have grown
    try std.testing.expect(size_after_second > size_after_first);

    // Third chunk: "chunk3" + end marker
    _ = try repl.handleKey("chunk3\x1b[201~", writer);
    try std.testing.expect(!repl.in_paste);

    // Final buffer should contain all chunks
    try std.testing.expectEqualStrings("chunk1chunk2chunk3", repl.buffer.items);
}

test "paste_buffer is cleared after flushing to buffer" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Multi-chunk paste
    _ = try repl.handleKey("\x1b[200~data", writer);
    try std.testing.expect(repl.paste_buffer.items.len > 0);

    // Flush by sending end marker
    _ = try repl.handleKey(" more\x1b[201~", writer);

    // After flush, paste_buffer should be cleared
    try std.testing.expectEqual(@as(usize, 0), repl.paste_buffer.items.len);
}

test "non-paste input is handled normally when not in paste mode" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Normal character input (not a paste)
    _ = try repl.handleKey("a", writer);

    // Should be inserted normally
    try std.testing.expectEqualStrings("a", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 1), repl.cursor);
    try std.testing.expect(!repl.in_paste);
}

test "paste with special escape sequences in content" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Paste containing arrow key escape sequences as literal text
    const paste_content = "\x1b[A\x1b[B\x1b[C";
    const key_input = "\x1b[200~" ++ paste_content ++ "\x1b[201~";
    _ = try repl.handleKey(key_input, writer);

    // Escape sequences should be preserved as literal bytes, not interpreted as keys
    try std.testing.expectEqualStrings(paste_content, repl.buffer.items);
}

test "paste can be enabled or disabled via config" {
    const allocator = std.testing.allocator;

    // Init with enable_bracketed_paste = false
    var repl = try Repl.init(allocator, .{ .enable_bracketed_paste = false });
    defer repl.deinit();

    // Config should reflect the setting
    try std.testing.expect(!repl.config.enable_bracketed_paste);
}

test "multiple consecutive pastes in sequence" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // First paste
    _ = try repl.handleKey("\x1b[200~first\x1b[201~", writer);
    try std.testing.expectEqualStrings("first", repl.buffer.items);

    // Clear for second paste
    repl.buffer.clearRetainingCapacity();
    repl.cursor = 0;

    // Second paste
    _ = try repl.handleKey("\x1b[200~second\x1b[201~", writer);
    try std.testing.expectEqualStrings("second", repl.buffer.items);
}

// ============================================================================
// Ctrl+U, Ctrl+K, Ctrl+W Kill-Line Operations Tests
// ============================================================================

test "Ctrl+U kills from line start to cursor" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "hello world", cursor = 8 (after "hello wo")
    try repl.buffer.appendSlice("hello world");
    repl.cursor = 8;

    // Send Ctrl+U (byte 21 = 0x15)
    _ = try repl.handleKey("\x15", writer);

    // Expected: buffer = "rld" (chars from cursor to end), cursor = 0
    try std.testing.expectEqualStrings("rld", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 0), repl.cursor);
}

test "Ctrl+U at cursor position 0 is a no-op" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "hello", cursor = 0
    try repl.buffer.appendSlice("hello");
    repl.cursor = 0;

    // Send Ctrl+U
    _ = try repl.handleKey("\x15", writer);

    // Expected: buffer unchanged, cursor unchanged (nothing to delete)
    try std.testing.expectEqualStrings("hello", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 0), repl.cursor);
}

test "Ctrl+U at end of buffer kills entire line" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "hello world", cursor = 11 (at end)
    try repl.buffer.appendSlice("hello world");
    repl.cursor = 11;

    // Send Ctrl+U
    _ = try repl.handleKey("\x15", writer);

    // Expected: buffer = "" (all deleted), cursor = 0
    try std.testing.expectEqualStrings("", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 0), repl.cursor);
}

test "Ctrl+K kills from cursor to end of line" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "hello world", cursor = 6 (after "hello ")
    try repl.buffer.appendSlice("hello world");
    repl.cursor = 6;

    // Send Ctrl+K (byte 11 = 0x0B)
    _ = try repl.handleKey("\x0b", writer);

    // Expected: buffer = "hello " (everything from cursor onward deleted), cursor unchanged
    try std.testing.expectEqualStrings("hello ", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 6), repl.cursor);
}

test "Ctrl+K at cursor position 0 kills entire buffer" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "hello world", cursor = 0
    try repl.buffer.appendSlice("hello world");
    repl.cursor = 0;

    // Send Ctrl+K
    _ = try repl.handleKey("\x0b", writer);

    // Expected: buffer = "" (all deleted), cursor = 0
    try std.testing.expectEqualStrings("", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 0), repl.cursor);
}

test "Ctrl+K at end of buffer is a no-op" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "hello", cursor = 5 (at end)
    try repl.buffer.appendSlice("hello");
    repl.cursor = 5;

    // Send Ctrl+K
    _ = try repl.handleKey("\x0b", writer);

    // Expected: buffer unchanged (nothing to delete), cursor unchanged
    try std.testing.expectEqualStrings("hello", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 5), repl.cursor);
}

test "Ctrl+W kills word backward, skipping trailing whitespace" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "foo bar  " (two spaces at end), cursor = 9 (at end)
    try repl.buffer.appendSlice("foo bar  ");
    repl.cursor = 9;

    // Send Ctrl+W (byte 23 = 0x17)
    _ = try repl.handleKey("\x17", writer);

    // Expected: buffer = "foo " (word "bar" and trailing spaces deleted), cursor = 4
    try std.testing.expectEqualStrings("foo ", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 4), repl.cursor);
}

test "Ctrl+W at start of buffer is a no-op" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "hello", cursor = 0
    try repl.buffer.appendSlice("hello");
    repl.cursor = 0;

    // Send Ctrl+W
    _ = try repl.handleKey("\x17", writer);

    // Expected: buffer unchanged, cursor unchanged
    try std.testing.expectEqualStrings("hello", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 0), repl.cursor);
}

test "Ctrl+W with single word deletes entire word from cursor" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "hello", cursor = 5 (at end)
    try repl.buffer.appendSlice("hello");
    repl.cursor = 5;

    // Send Ctrl+W
    _ = try repl.handleKey("\x17", writer);

    // Expected: buffer = "" (entire word deleted), cursor = 0
    try std.testing.expectEqualStrings("", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 0), repl.cursor);
}

test "Ctrl+W with cursor in middle of word deletes to word start" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "foo bar baz", cursor = 9 (in middle of "baz", at 'a')
    // Canonical algorithm: skip whitespace backward, then skip non-whitespace backward
    // From cursor=9: no whitespace at position 8, skip 'b' backward to position 8
    try repl.buffer.appendSlice("foo bar baz");
    repl.cursor = 9;

    // Send Ctrl+W
    _ = try repl.handleKey("\x17", writer);

    // Expected: buffer = "foo bar az" (delete 'b'), cursor = 8
    try std.testing.expectEqualStrings("foo bar az", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 8), repl.cursor);
}

test "Ctrl+W on empty buffer is a no-op" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: empty buffer, cursor = 0
    // (no need to appendSlice)

    // Send Ctrl+W
    _ = try repl.handleKey("\x17", writer);

    // Expected: no crash, buffer and cursor unchanged
    try std.testing.expectEqualStrings("", repl.buffer.items);
    try std.testing.expectEqual(@as(usize, 0), repl.cursor);
}

// ============================================================================
// Alt+B and Alt+F Word-Jump Operations Tests
// ============================================================================

test "Alt+B from a word boundary moves to start of previous word" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "foo bar baz", cursor = 8 (at word boundary, start of "baz")
    // From cursor=8: skip whitespace backward at position 7, then skip non-whitespace positions 6,5,4
    try repl.buffer.appendSlice("foo bar baz");
    repl.cursor = 8;

    // Send Alt+B (2-byte sequence: ESC + 'b' = 0x1b followed by 'b')
    _ = try repl.handleKey("\x1bb", writer);

    // Expected: cursor moves back to start of "bar" at position 4
    try std.testing.expectEqual(@as(usize, 4), repl.cursor);
}

test "Alt+B at start of buffer is a no-op" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "foo bar", cursor = 0
    try repl.buffer.appendSlice("foo bar");
    repl.cursor = 0;

    // Send Alt+B
    _ = try repl.handleKey("\x1bb", writer);

    // Expected: cursor unchanged (nowhere to go)
    try std.testing.expectEqual(@as(usize, 0), repl.cursor);
}

test "Alt+B from middle of word moves to start of that word" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "foo bar baz", cursor = 9 (in middle of "baz", at 'a')
    // Canonical algorithm: skip whitespace backward, then skip non-whitespace backward
    // From cursor=9: no whitespace at position 8, skip 'b' backward to position 8
    try repl.buffer.appendSlice("foo bar baz");
    repl.cursor = 9;

    // Send Alt+B
    _ = try repl.handleKey("\x1bb", writer);

    // Expected: cursor moves to start of current word "baz" at position 8
    try std.testing.expectEqual(@as(usize, 8), repl.cursor);
}

test "Alt+B on empty buffer is a no-op" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: empty buffer, cursor = 0

    // Send Alt+B
    _ = try repl.handleKey("\x1bb", writer);

    // Expected: no crash, cursor unchanged
    try std.testing.expectEqual(@as(usize, 0), repl.cursor);
}

test "Alt+F moves cursor forward to end of next word" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "foo bar baz", cursor = 0 (before 'f')
    try repl.buffer.appendSlice("foo bar baz");
    repl.cursor = 0;

    // Send Alt+F (2-byte sequence: ESC + 'f' = 0x1b followed by 'f')
    _ = try repl.handleKey("\x1bf", writer);

    // Expected: cursor moves to end of "foo" at position 3
    try std.testing.expectEqual(@as(usize, 3), repl.cursor);
}

test "Alt+F at end of buffer is a no-op" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "hello", cursor = 5 (at end)
    try repl.buffer.appendSlice("hello");
    repl.cursor = 5;

    // Send Alt+F
    _ = try repl.handleKey("\x1bf", writer);

    // Expected: cursor unchanged (nowhere to go)
    try std.testing.expectEqual(@as(usize, 5), repl.cursor);
}

test "Alt+F from middle of word moves to end of current word" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "foo bar baz", cursor = 1 (in "foo", at 'o')
    try repl.buffer.appendSlice("foo bar baz");
    repl.cursor = 1;

    // Send Alt+F
    _ = try repl.handleKey("\x1bf", writer);

    // Expected: cursor moves to end of "foo" at position 3
    try std.testing.expectEqual(@as(usize, 3), repl.cursor);
}

test "Alt+F from whitespace skips to end of next word" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: buffer = "foo bar baz", cursor = 4 (after "foo ", at 'b' in "bar")
    try repl.buffer.appendSlice("foo bar baz");
    repl.cursor = 4;

    // From position 4, skip whitespace forward: buffer[3]=' ', skip; buffer[4]='b', stop
    // Then skip non-whitespace: buffer[4]='b', buffer[5]='a', buffer[6]='r', buffer[7]=' ', stop
    // cursor = 7

    // Send Alt+F
    _ = try repl.handleKey("\x1bf", writer);

    // Expected: cursor moves to end of "bar" at position 7
    try std.testing.expectEqual(@as(usize, 7), repl.cursor);
}

test "Alt+F on empty buffer is a no-op" {
    const allocator = std.testing.allocator;

    var repl = try Repl.init(allocator, .{});
    defer repl.deinit();

    const writer = std.io.null_writer;

    // Setup: empty buffer, cursor = 0

    // Send Alt+F
    _ = try repl.handleKey("\x1bf", writer);

    // Expected: no crash, cursor unchanged
    try std.testing.expectEqual(@as(usize, 0), repl.cursor);
}
