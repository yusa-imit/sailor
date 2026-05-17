//! Natural Language Commands (v2.10.0)
//!
//! This module provides natural language command parsing for TUI applications.
//! It enables users to control applications using plain English commands like
//! "show logs", "search for errors", or "close the dialog".
//!
//! Features:
//! - Intent recognition with 11 command types
//! - Context-aware disambiguation based on widget focus and application state
//! - Command history with semantic search (exact/partial/synonym/similarity)
//! - Tutorial mode with progressive disclosure of features
//! - Unicode support and robust edge case handling
//!
//! Library constraints:
//! - NO stdout/stderr usage
//! - NO @panic in library code
//! - Writer-based output for all exports
//! - Caller-provided allocator for all allocations

const std = @import("std");

// ============================================================================
// Intent Types
// ============================================================================

pub const Intent = union(enum) {
    show: ShowIntent,
    search: SearchIntent,
    close: CloseIntent,
    scroll: ScrollIntent,
    select: SelectIntent,
    copy: CopyIntent,
    save: SaveIntent,
    undo: UndoIntent,
    help: HelpIntent,
    quit: QuitIntent,
    unknown: UnknownIntent,

    pub fn deinit(self: *Intent, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .search => |s| if (s.query.len > 0) allocator.free(s.query),
            .unknown => |u| if (u.suggestion) |sug| allocator.free(sug),
            else => {},
        }
    }
};

pub const ShowIntent = struct {
    target: Target,
};

pub const SearchIntent = struct {
    query: []const u8, // Owned by allocator
};

pub const CloseIntent = struct {
    target: ?Target,
};

pub const ScrollIntent = struct {
    direction: Direction,
    amount: ?u32 = null,
};

pub const SelectIntent = struct {
    index: ?u32 = null,
};

pub const CopyIntent = struct {};

pub const SaveIntent = struct {};

pub const UndoIntent = struct {
    steps: u32 = 1,
};

pub const HelpIntent = struct {
    topic: ?Topic = null,
};

pub const QuitIntent = struct {};

pub const UnknownIntent = struct {
    suggestion: ?[]const u8 = null, // Owned by allocator
};

pub const Target = enum {
    logs,
    dialog,
    list,
    table,
    any,
};

pub const Direction = enum {
    up,
    down,
    left,
    right,
};

pub const Topic = enum {
    navigation,
    editing,
    shortcuts,
};

pub const WidgetType = enum {
    list,
    table,
    dialog,
    input,
    textarea,
};

pub const Preferences = struct {};

// ============================================================================
// Context Structure
// ============================================================================

pub const Context = struct {
    focused_widget: ?WidgetType = null,
    open_dialogs: []const WidgetType = &[_]WidgetType{},
    recent_commands: []const []const u8 = &[_][]const u8{},
    user_preferences: Preferences = .{},
};

// ============================================================================
// CommandParser (Intent Recognition + Disambiguation)
// ============================================================================

pub const CommandParser = struct {
    allocator: std.mem.Allocator,
    context: *const Context,

    pub fn init(allocator: std.mem.Allocator, context: *const Context) CommandParser {
        return .{
            .allocator = allocator,
            .context = context,
        };
    }

    pub fn deinit(self: *CommandParser) void {
        _ = self;
        // Nothing to clean up (context is borrowed)
    }

    pub fn parse(self: *CommandParser, input: []const u8) !Intent {
        // Normalize input: trim whitespace, collapse multiple spaces, lowercase
        const normalized = try normalize(self.allocator, input);
        defer self.allocator.free(normalized);

        // Empty string
        if (normalized.len == 0) {
            const suggestion = try self.allocator.dupe(u8, "type 'help' for assistance");
            return Intent{ .unknown = .{ .suggestion = suggestion } };
        }

        // Extract keywords
        const words = try splitWords(self.allocator, normalized);
        defer {
            for (words) |word| self.allocator.free(word);
            self.allocator.free(words);
        }

        if (words.len == 0) {
            const suggestion = try self.allocator.dupe(u8, "type 'help' for assistance");
            return Intent{ .unknown = .{ .suggestion = suggestion } };
        }

        // Check for synonyms
        const first_word = words[0];
        const mapped_word = mapSynonym(first_word);

        // Parse based on first keyword
        if (std.mem.eql(u8, mapped_word, "show")) {
            return try self.parseShow(words);
        } else if (std.mem.eql(u8, mapped_word, "search") or std.mem.eql(u8, mapped_word, "find")) {
            return try self.parseSearch(normalized);
        } else if (std.mem.eql(u8, mapped_word, "close")) {
            return try self.parseClose(words);
        } else if (std.mem.eql(u8, mapped_word, "scroll")) {
            return try self.parseScroll(words);
        } else if (std.mem.eql(u8, mapped_word, "select")) {
            return try self.parseSelect(normalized);
        } else if (std.mem.eql(u8, mapped_word, "copy") or std.mem.eql(u8, mapped_word, "コピー")) {
            return Intent{ .copy = .{} };
        } else if (std.mem.eql(u8, mapped_word, "save")) {
            return Intent{ .save = .{} };
        } else if (std.mem.eql(u8, mapped_word, "undo")) {
            return try self.parseUndo(normalized);
        } else if (std.mem.eql(u8, mapped_word, "help")) {
            return try self.parseHelp(words);
        } else if (std.mem.eql(u8, mapped_word, "quit") or std.mem.eql(u8, mapped_word, "exit")) {
            return Intent{ .quit = .{} };
        }

        // Unknown command - suggest closest match
        const suggestion = try self.findClosestCommand(mapped_word);
        return Intent{ .unknown = .{ .suggestion = suggestion } };
    }

    fn parseShow(self: *CommandParser, words: []const []const u8) !Intent {
        _ = self;
        // Look for target: logs, dialog, list, table
        for (words) |word| {
            if (std.mem.eql(u8, word, "logs") or std.mem.eql(u8, word, "log")) {
                return Intent{ .show = .{ .target = .logs } };
            } else if (std.mem.eql(u8, word, "dialog")) {
                return Intent{ .show = .{ .target = .dialog } };
            } else if (std.mem.eql(u8, word, "list")) {
                return Intent{ .show = .{ .target = .list } };
            } else if (std.mem.eql(u8, word, "table")) {
                return Intent{ .show = .{ .target = .table } };
            }
        }
        // Default to showing any
        return Intent{ .show = .{ .target = .any } };
    }

    fn parseSearch(self: *CommandParser, input: []const u8) !Intent {
        // Extract query after "search" or "find"
        var query_start: usize = 0;
        if (std.mem.indexOf(u8, input, "search")) |idx| {
            query_start = idx + 6; // len("search")
        } else if (std.mem.indexOf(u8, input, "find")) |idx| {
            query_start = idx + 4; // len("find")
        }

        // Skip "for" if present
        var query_slice = std.mem.trimLeft(u8, input[query_start..], " ");
        if (std.mem.startsWith(u8, query_slice, "for ")) {
            query_slice = query_slice[4..];
        }

        query_slice = std.mem.trim(u8, query_slice, " ");

        const query = try self.allocator.dupe(u8, query_slice);
        return Intent{ .search = .{ .query = query } };
    }

    fn parseClose(self: *CommandParser, words: []const []const u8) !Intent {
        // Check for explicit target
        for (words) |word| {
            if (std.mem.eql(u8, word, "dialog")) {
                return Intent{ .close = .{ .target = .dialog } };
            } else if (std.mem.eql(u8, word, "logs") or std.mem.eql(u8, word, "log")) {
                return Intent{ .close = .{ .target = .logs } };
            } else if (std.mem.eql(u8, word, "list")) {
                return Intent{ .close = .{ .target = .list } };
            } else if (std.mem.eql(u8, word, "table")) {
                return Intent{ .close = .{ .target = .table } };
            }
        }

        // Context-aware disambiguation
        if (self.context.open_dialogs.len > 0) {
            // If dialog is open, default to closing dialog
            return Intent{ .close = .{ .target = .dialog } };
        }

        // No context - suggest specifying target
        const suggestion = try self.allocator.dupe(u8, "specify target");
        return Intent{ .unknown = .{ .suggestion = suggestion } };
    }

    fn parseScroll(self: *CommandParser, words: []const []const u8) !Intent {
        // Extract direction
        var direction: ?Direction = null;
        var amount: ?u32 = null;

        for (words) |word| {
            if (std.mem.eql(u8, word, "up")) {
                direction = .up;
            } else if (std.mem.eql(u8, word, "down")) {
                direction = .down;
            } else if (std.mem.eql(u8, word, "left")) {
                direction = .left;
            } else if (std.mem.eql(u8, word, "right")) {
                direction = .right;
            } else if (extractNumber(word)) |num| {
                amount = num;
            }
        }

        if (direction) |dir| {
            return Intent{ .scroll = .{ .direction = dir, .amount = amount } };
        }

        // No direction specified - check context
        if (self.context.focused_widget != null) {
            // Default to down if widget is focused
            return Intent{ .scroll = .{ .direction = .down, .amount = amount } };
        }

        // No context
        const suggestion = try self.allocator.dupe(u8, "specify direction (up/down/left/right)");
        return Intent{ .unknown = .{ .suggestion = suggestion } };
    }

    fn parseSelect(self: *CommandParser, input: []const u8) !Intent {
        _ = self;
        // Extract index
        const index = extractNumber(input);

        // Check for "first" keyword
        if (std.mem.indexOf(u8, input, "first")) |_| {
            return Intent{ .select = .{ .index = 0 } };
        }

        return Intent{ .select = .{ .index = index } };
    }

    fn parseUndo(self: *CommandParser, input: []const u8) !Intent {
        _ = self;
        // Extract number of steps
        const steps = extractNumber(input) orelse 1;
        return Intent{ .undo = .{ .steps = steps } };
    }

    fn parseHelp(self: *CommandParser, words: []const []const u8) !Intent {
        _ = self;
        // Look for topic
        for (words) |word| {
            if (std.mem.eql(u8, word, "navigation")) {
                return Intent{ .help = .{ .topic = .navigation } };
            } else if (std.mem.eql(u8, word, "editing")) {
                return Intent{ .help = .{ .topic = .editing } };
            } else if (std.mem.eql(u8, word, "shortcuts")) {
                return Intent{ .help = .{ .topic = .shortcuts } };
            }
        }
        return Intent{ .help = .{ .topic = null } };
    }

    fn findClosestCommand(self: *CommandParser, word: []const u8) !?[]const u8 {
        const known_commands = [_][]const u8{
            "show",
            "search",
            "close",
            "scroll",
            "select",
            "copy",
            "save",
            "undo",
            "help",
            "quit",
        };

        var min_distance: u32 = std.math.maxInt(u32);
        var closest: ?[]const u8 = null;

        for (known_commands) |cmd| {
            const dist = levenshteinDistance(word, cmd);
            if (dist < min_distance) {
                min_distance = dist;
                closest = cmd;
            }
        }

        // Only suggest if distance is reasonable (< half the word length)
        if (closest) |c| {
            const threshold = @max(word.len / 2, 2);
            if (min_distance <= threshold) {
                return try self.allocator.dupe(u8, c);
            }
        }

        return null;
    }
};

// ============================================================================
// CommandHistory (Semantic Search)
// ============================================================================

pub const CommandHistory = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(HistoryEntry),
    max_size: usize,

    pub fn init(allocator: std.mem.Allocator, max_size: usize) CommandHistory {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList(HistoryEntry){},
            .max_size = max_size,
        };
    }

    pub fn deinit(self: *CommandHistory) void {
        for (self.entries.items) |*entry| {
            self.allocator.free(entry.command);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn add(self: *CommandHistory, command: []const u8) !void {
        // Check if command already exists
        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.command, command)) {
                // Update timestamp and count
                entry.timestamp = std.time.timestamp();
                entry.count += 1;
                return;
            }
        }

        // Add new entry
        const owned_command = try self.allocator.dupe(u8, command);
        errdefer self.allocator.free(owned_command);

        const entry = HistoryEntry{
            .command = owned_command,
            .timestamp = std.time.timestamp(),
            .count = 1,
        };

        try self.entries.append(self.allocator, entry);

        // Enforce max size
        while (self.entries.items.len > self.max_size) {
            const oldest = self.entries.orderedRemove(0);
            self.allocator.free(oldest.command);
        }
    }

    pub fn search(self: *CommandHistory, query: []const u8, max_results: usize) ![]HistoryEntry {
        var results = std.ArrayList(ScoredEntry){};
        defer results.deinit(self.allocator);

        for (self.entries.items) |entry| {
            const score = scoreMatch(query, entry.command);
            if (score > 0) {
                try results.append(self.allocator, .{ .entry = entry, .score = score });
            }
        }

        // Sort by score (descending)
        std.mem.sort(ScoredEntry, results.items, {}, struct {
            fn lessThan(_: void, a: ScoredEntry, b: ScoredEntry) bool {
                return a.score > b.score;
            }
        }.lessThan);

        // Take top N
        const limit = @min(max_results, results.items.len);
        const result_slice = try self.allocator.alloc(HistoryEntry, limit);
        for (0..limit) |i| {
            result_slice[i] = results.items[i].entry;
        }

        return result_slice;
    }

    pub fn clear(self: *CommandHistory) void {
        for (self.entries.items) |*entry| {
            self.allocator.free(entry.command);
        }
        self.entries.clearRetainingCapacity();
    }

    pub fn exportToString(self: *CommandHistory, writer: anytype) !void {
        try writer.writeAll("[\n");
        for (self.entries.items, 0..) |entry, i| {
            try writer.print("  {{\"command\":\"{s}\",\"timestamp\":{d},\"count\":{d}}}", .{
                entry.command,
                entry.timestamp,
                entry.count,
            });
            if (i < self.entries.items.len - 1) {
                try writer.writeAll(",");
            }
            try writer.writeAll("\n");
        }
        try writer.writeAll("]\n");
    }

    pub fn loadFromString(self: *CommandHistory, data: []const u8) !void {
        // Simple JSON-like parser (manual, no std.json)
        var lines = std.mem.splitScalar(u8, data, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '[' or trimmed[0] == ']') continue;

            // Parse: {"command":"...", "timestamp":..., "count":...}
            if (std.mem.indexOf(u8, trimmed, "\"command\":\"")) |cmd_start| {
                const cmd_value_start = cmd_start + 11; // len("\"command\":\"")
                if (std.mem.indexOf(u8, trimmed[cmd_value_start..], "\"")) |cmd_end| {
                    const command = trimmed[cmd_value_start .. cmd_value_start + cmd_end];

                    // Extract timestamp
                    var timestamp: i64 = 0;
                    if (std.mem.indexOf(u8, trimmed, "\"timestamp\":")) |ts_start| {
                        const ts_value_start = ts_start + 12; // len("\"timestamp\":")
                        var ts_end = ts_value_start;
                        while (ts_end < trimmed.len and std.ascii.isDigit(trimmed[ts_end])) {
                            ts_end += 1;
                        }
                        timestamp = std.fmt.parseInt(i64, trimmed[ts_value_start..ts_end], 10) catch 0;
                    }

                    // Extract count
                    var count: u32 = 1;
                    if (std.mem.indexOf(u8, trimmed, "\"count\":")) |cnt_start| {
                        const cnt_value_start = cnt_start + 8; // len("\"count\":")
                        var cnt_end = cnt_value_start;
                        while (cnt_end < trimmed.len and std.ascii.isDigit(trimmed[cnt_end])) {
                            cnt_end += 1;
                        }
                        count = std.fmt.parseInt(u32, trimmed[cnt_value_start..cnt_end], 10) catch 1;
                    }

                    const owned_command = try self.allocator.dupe(u8, command);
                    errdefer self.allocator.free(owned_command);

                    const entry = HistoryEntry{
                        .command = owned_command,
                        .timestamp = timestamp,
                        .count = count,
                    };

                    try self.entries.append(self.allocator, entry);
                }
            }
        }
    }
};

pub const HistoryEntry = struct {
    command: []const u8,
    timestamp: i64,
    count: u32,
};

const ScoredEntry = struct {
    entry: HistoryEntry,
    score: u32,
};

fn scoreMatch(query: []const u8, command: []const u8) u32 {
    // Exact match: highest score
    if (std.mem.eql(u8, query, command)) {
        return 1000;
    }

    // Partial match
    if (std.mem.indexOf(u8, command, query)) |_| {
        return 500;
    }

    // Synonym match
    const query_mapped = mapSynonym(query);
    if (!std.mem.eql(u8, query, query_mapped)) {
        if (std.mem.indexOf(u8, command, query_mapped)) |_| {
            return 400;
        }
    }

    // Semantic similarity (simple word overlap)
    const overlap = countWordOverlap(query, command);
    if (overlap > 0) {
        return overlap * 100;
    }

    return 0;
}

fn countWordOverlap(a: []const u8, b: []const u8) u32 {
    // Simple word overlap count
    var count: u32 = 0;
    var words_a = std.mem.tokenizeScalar(u8, a, ' ');
    while (words_a.next()) |word_a| {
        if (std.mem.indexOf(u8, b, word_a)) |_| {
            count += 1;
        }
    }
    return count;
}

// ============================================================================
// TutorialMode (Progressive Disclosure)
// ============================================================================

pub const TutorialMode = struct {
    enabled: bool,
    tips_shown: std.StringHashMap(bool),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TutorialMode {
        return .{
            .enabled = true,
            .allocator = allocator,
            .tips_shown = std.StringHashMap(bool).init(allocator),
        };
    }

    pub fn deinit(self: *TutorialMode) void {
        self.tips_shown.deinit();
    }

    pub fn getSuggestion(self: *TutorialMode, context: *const Context) ?[]const u8 {
        if (!self.enabled) return null;

        // Empty input
        if (context.recent_commands.len == 0) {
            if (self.tips_shown.get("startup") == null) {
                return "Try 'show logs' or 'search for errors'";
            }
        }

        // Contextual tips based on focused widget
        if (context.focused_widget) |widget| {
            switch (widget) {
                .list => {
                    if (self.tips_shown.get("list_tip") == null) {
                        return "Use 'scroll down' or 'select 3'";
                    }
                },
                .dialog => {
                    if (self.tips_shown.get("dialog_tip") == null) {
                        return "Use 'close dialog' to dismiss";
                    }
                },
                else => {},
            }
        }

        // Open dialogs
        if (context.open_dialogs.len > 0) {
            if (self.tips_shown.get("close_dialog_tip") == null) {
                return "Use 'close dialog' to dismiss";
            }
        }

        return null;
    }

    pub fn dismissTip(self: *TutorialMode, tip_id: []const u8) !void {
        try self.tips_shown.put(tip_id, true);
    }
};

// ============================================================================
// Parser Utilities
// ============================================================================

fn normalize(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");

    // Collapse multiple spaces
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    var last_was_space = false;
    for (trimmed) |c| {
        if (c == ' ' or c == '\t') {
            if (!last_was_space) {
                try result.append(allocator, ' ');
                last_was_space = true;
            }
        } else {
            try result.append(allocator, std.ascii.toLower(c));
            last_was_space = false;
        }
    }

    return result.toOwnedSlice(allocator);
}

fn splitWords(allocator: std.mem.Allocator, input: []const u8) ![][]const u8 {
    var words = std.ArrayList([]const u8){};
    defer words.deinit(allocator);

    var iter = std.mem.tokenizeScalar(u8, input, ' ');
    while (iter.next()) |word| {
        const owned = try allocator.dupe(u8, word);
        try words.append(allocator, owned);
    }

    return words.toOwnedSlice(allocator);
}

fn extractNumber(input: []const u8) ?u32 {
    for (input, 0..) |c, i| {
        if (std.ascii.isDigit(c)) {
            // Found start of number
            var end = i;
            while (end < input.len and std.ascii.isDigit(input[end])) {
                end += 1;
            }
            return std.fmt.parseInt(u32, input[i..end], 10) catch null;
        }
    }
    return null;
}

fn mapSynonym(word: []const u8) []const u8 {
    if (std.mem.eql(u8, word, "exit")) return "quit";
    if (std.mem.eql(u8, word, "find")) return "search";
    if (std.mem.eql(u8, word, "コピー")) return "copy";
    return word;
}

fn levenshteinDistance(a: []const u8, b: []const u8) u32 {
    if (a.len == 0) return @intCast(b.len);
    if (b.len == 0) return @intCast(a.len);

    const max_len = @max(a.len, b.len) + 1;
    if (max_len > 256) {
        // Fallback for very long strings
        return @intCast(@max(a.len, b.len));
    }

    var prev_row: [256]u32 = undefined;
    var prev_len: usize = 0;
    var curr_row: [256]u32 = undefined;
    var curr_len: usize = 0;

    // Initialize first row
    for (0..b.len + 1) |i| {
        prev_row[prev_len] = @intCast(i);
        prev_len += 1;
    }

    // Calculate distance
    for (a, 0..) |char_a, i| {
        curr_len = 0;
        curr_row[curr_len] = @intCast(i + 1);
        curr_len += 1;

        for (b, 0..) |char_b, j| {
            const cost: u32 = if (char_a == char_b) 0 else 1;
            const deletion = prev_row[j + 1] + 1;
            const insertion = curr_row[j] + 1;
            const substitution = prev_row[j] + cost;
            const min_val = @min(deletion, @min(insertion, substitution));
            curr_row[curr_len] = min_val;
            curr_len += 1;
        }

        // Swap rows
        const tmp_row = prev_row;
        const tmp_len = prev_len;
        prev_row = curr_row;
        prev_len = curr_len;
        curr_row = tmp_row;
        curr_len = tmp_len;
    }

    return prev_row[b.len];
}

fn containsWord(haystack: []const u8, needle: []const u8) bool {
    var iter = std.mem.tokenizeScalar(u8, haystack, ' ');
    while (iter.next()) |word| {
        if (std.mem.eql(u8, word, needle)) {
            return true;
        }
    }
    return false;
}

// ============================================================================
// Tests
// ============================================================================

test {
    std.testing.refAllDecls(@This());
}
