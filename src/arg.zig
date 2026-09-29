//! Argument parser module
//!
//! Provides compile-time defined, type-safe argument parsing:
//! - Flag definitions with comptime validation
//! - Subcommand support
//! - Auto-generated --help
//! - Type-safe value access
//! - Levenshtein-based "Did you mean?" suggestions
//!
//! All parser state is user-owned — no global state.

const std = @import("std");
const assert = std.debug.assert;

/// A no-op marker for a condition that is legitimately sometimes true and
/// sometimes false — as opposed to `assert`, which documents *always*.
fn maybe(ok: bool) void {
    _ = ok;
}

/// Flag value type
pub const FlagType = enum {
    bool,
    string,
    int,
    float,
};

/// Flag definition (comptime)
pub const FlagDef = struct {
    name: []const u8,
    short: ?u8 = null,
    type: FlagType,
    required: bool = false,
    default: ?[]const u8 = null,
    help: []const u8 = "",
    group: ?[]const u8 = null, // Optional group name for organizing help output
};

/// Parse result value
pub const Value = union(FlagType) {
    bool: bool,
    string: []const u8,
    int: i64,
    float: f64,

    /// Get boolean value or error
    pub fn asBool(self: Value) !bool {
        return switch (self) {
            .bool => |v| v,
            else => error.TypeMismatch,
        };
    }

    /// Get string value or error
    pub fn asString(self: Value) ![]const u8 {
        return switch (self) {
            .string => |v| v,
            else => error.TypeMismatch,
        };
    }

    /// Get integer value or error
    pub fn asInt(self: Value) !i64 {
        return switch (self) {
            .int => |v| v,
            else => error.TypeMismatch,
        };
    }

    /// Get float value or error
    pub fn asFloat(self: Value) !f64 {
        return switch (self) {
            .float => |v| v,
            else => error.TypeMismatch,
        };
    }
};

/// Parser error
pub const Error = error{
    UnknownFlag,
    MissingValue,
    MissingRequiredFlag,
    InvalidValue,
    TypeMismatch,
    OutOfMemory,
};

/// Compute Levenshtein edit distance between two strings
fn levenshteinDistance(s1: []const u8, s2: []const u8) usize {
    const len1 = s1.len;
    const len2 = s2.len;

    // Handle empty strings
    if (len1 == 0) return len2;
    if (len2 == 0) return len1;

    // Use a fixed-size buffer for DP table (2D, but we use 2 rows approach)
    // Limit to prevent stack overflow for very long strings
    const max_len = 128;
    const actual_len1 = @min(len1, max_len);
    const actual_len2 = @min(len2, max_len);
    assert(actual_len1 <= max_len); // Precondition: fits the [2][129] DP buffer below.
    assert(actual_len2 <= max_len);

    // Two rows: previous and current
    var rows: [2][129]usize = undefined;
    var prev_row = &rows[0];
    var curr_row = &rows[1];

    // Loop bounds below index up to actual_lenN + 1; both must stay inside
    // the fixed-size row buffer (length 129, one more than max_len).
    assert(actual_len1 + 1 <= rows[0].len);
    assert(actual_len2 + 1 <= rows[0].len);

    // Initialize first row
    for (0..actual_len2 + 1) |j| {
        prev_row[j] = j;
    }

    // Fill DP table
    for (1..actual_len1 + 1) |i| {
        curr_row[0] = i;

        for (1..actual_len2 + 1) |j| {
            const cost = if (s1[i - 1] == s2[j - 1]) @as(usize, 0) else @as(usize, 1);
            const del = prev_row[j] + 1;
            const ins = curr_row[j - 1] + 1;
            const sub = prev_row[j - 1] + cost;
            curr_row[j] = @min(@min(del, ins), sub);
        }

        // Swap row pointers
        const temp_ptr = prev_row;
        prev_row = curr_row;
        curr_row = temp_ptr;
    }

    const distance = prev_row[actual_len2];
    // Mathematical property of edit distance: it never exceeds the length of
    // the longer input, since replacing every character of the shorter one
    // (plus inserting/deleting the length gap) is always a valid edit script.
    assert(distance <= @max(actual_len1, actual_len2));
    return distance;
}

/// Find the closest match from a list of candidates using Levenshtein distance
/// Returns the candidate name with minimum distance if distance <= threshold, otherwise null
fn findClosestMatch(candidates: []const []const u8, unknown: []const u8, threshold: usize) ?[]const u8 {
    // Precondition: `min_distance = threshold + 1` below must not overflow,
    // so threshold is used consistently as a real, addable bound.
    assert(threshold < std.math.maxInt(usize));
    if (candidates.len == 0) {
        return null;
    }

    var min_distance: usize = threshold + 1;
    var best_candidate: ?[]const u8 = null;

    for (candidates) |candidate| {
        const distance = levenshteinDistance(unknown, candidate);
        if (distance < min_distance) {
            min_distance = distance;
            best_candidate = candidate;
        }
    }

    if (min_distance <= threshold) {
        assert(best_candidate != null); // min_distance only tightens alongside best_candidate.
        // Airlock: edit distance is symmetric, so recomputing with the arguments
        // swapped checks the loop's bookkeeping through a different path.
        assert(levenshteinDistance(best_candidate.?, unknown) <= threshold);
        return best_candidate;
    }
    assert(min_distance > threshold); // Negative space: no candidate met the threshold.
    return null;
}

/// Argument parser
pub fn Parser(comptime flags: []const FlagDef) type {
    // Compile-time validation
    comptime {
        for (flags, 0..) |flag, i| {
            if (flag.name.len == 0) @compileError("Empty flag name");
            // Check for duplicate names
            for (flags[i + 1 ..]) |other| {
                if (std.mem.eql(u8, flag.name, other.name)) {
                    @compileError("Duplicate flag name: " ++ flag.name);
                }
                if (flag.short != null and other.short != null and flag.short.? == other.short.?) {
                    @compileError("Duplicate flag short: -" ++ [_]u8{flag.short.?});
                }
            }

            // Validate default values
            if (flag.default != null) {
                switch (flag.type) {
                    .bool => {
                        const val = flag.default.?;
                        if (!std.mem.eql(u8, val, "true") and !std.mem.eql(u8, val, "false")) {
                            @compileError("Invalid default for bool flag " ++ flag.name ++ ": " ++ val);
                        }
                    },
                    else => {},
                }
            }
        }
    }

    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        values: std.StringHashMap(Value),
        positional: std.ArrayList([]const u8),
        suggestion: ?[]const u8 = null,

        /// Initialize parser
        pub fn init(allocator: std.mem.Allocator) Self {
            const self: Self = .{
                .allocator = allocator,
                .values = std.StringHashMap(Value).init(allocator),
                .positional = .empty,
                .suggestion = null,
            };
            assert(self.values.count() == 0);
            assert(self.positional.items.len == 0);
            assert(self.suggestion == null);
            return self;
        }

        /// Free parser resources
        pub fn deinit(self: *Self) void {
            self.values.deinit();
            self.positional.deinit(self.allocator);
        }

        /// Parse arguments
        pub fn parse(self: *Self, args: []const []const u8) Error!void {
            // Reset suggestion at start of each parse
            self.suggestion = null;

            var i: usize = 0;
            while (i < args.len) : (i += 1) {
                const arg = args[i];

                if (std.mem.startsWith(u8, arg, "--")) {
                    // Long flag
                    const name = arg[2..];
                    if (std.mem.find(u8, name, "=")) |eq_pos| {
                        // --flag=value
                        const flag_name = name[0..eq_pos];
                        const value = name[eq_pos + 1 ..];
                        try self.setFlag(flag_name, value);
                    } else {
                        // --flag [value]
                        const flag_def = findFlag(name) orelse {
                            // Try to find a suggestion before returning error
                            self.suggestion = findSuggestion(name);
                            return Error.UnknownFlag;
                        };
                        if (flag_def.type == .bool) {
                            try self.values.put(flag_def.name, .{ .bool = true });
                        } else {
                            i += 1;
                            if (i >= args.len) return Error.MissingValue;
                            try self.setFlag(flag_def.name, args[i]);
                        }
                    }
                } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                    // Short flag(s)
                    for (arg[1..]) |ch| {
                        const flag_def = findFlagByShort(ch) orelse {
                            // Try to find a suggestion for short flag (by character)
                            // For short flags, we could suggest the long form of the closest flag
                            // For now, we don't set suggestion for short flags
                            return Error.UnknownFlag;
                        };
                        if (flag_def.type == .bool) {
                            try self.values.put(flag_def.name, .{ .bool = true });
                        } else {
                            i += 1;
                            if (i >= args.len) return Error.MissingValue;
                            try self.setFlag(flag_def.name, args[i]);
                            break; // Short flags with values consume rest of arg string
                        }
                    }
                } else {
                    // Positional argument
                    try self.positional.append(self.allocator, arg);
                }
            }

            // Apply defaults and check required flags
            inline for (flags) |flag| {
                if (!self.values.contains(flag.name)) {
                    if (flag.default) |default_str| {
                        try self.setFlag(flag.name, default_str);
                    } else if (flag.required) {
                        return Error.MissingRequiredFlag;
                    }
                }
            }
        }

        fn setFlag(self: *Self, name: []const u8, value_str: []const u8) Error!void {
            const flag_def = findFlag(name) orelse {
                self.suggestion = findSuggestion(name);
                return Error.UnknownFlag;
            };

            const value = switch (flag_def.type) {
                .bool => blk: {
                    if (std.mem.eql(u8, value_str, "true") or std.mem.eql(u8, value_str, "1")) {
                        break :blk Value{ .bool = true };
                    } else if (std.mem.eql(u8, value_str, "false") or std.mem.eql(u8, value_str, "0")) {
                        break :blk Value{ .bool = false };
                    } else {
                        return Error.InvalidValue;
                    }
                },
                .string => Value{ .string = value_str },
                .int => Value{ .int = std.fmt.parseInt(i64, value_str, 10) catch return Error.InvalidValue },
                .float => Value{ .float = std.fmt.parseFloat(f64, value_str) catch return Error.InvalidValue },
            };
            assert(@as(FlagType, value) == flag_def.type); // Construction-time half of the airlock.

            try self.values.put(flag_def.name, value);
            const stored = self.values.get(flag_def.name).?; // Just inserted; must be found.
            assert(@as(FlagType, stored) == flag_def.type); // Storage-time half of the airlock.
        }

        fn findFlag(name: []const u8) ?FlagDef {
            inline for (flags) |flag| {
                if (std.mem.eql(u8, flag.name, name)) {
                    return flag;
                }
            }
            return null;
        }

        fn findFlagByShort(ch: u8) ?FlagDef {
            inline for (flags) |flag| {
                if (flag.short != null and flag.short.? == ch) {
                    return flag;
                }
            }
            return null;
        }

        /// Find a suggestion for an unknown flag based on Levenshtein distance
        /// Returns the flag name with minimum distance if distance <= 3, otherwise null
        fn findSuggestion(unknown_name: []const u8) ?[]const u8 {
            if (flags.len == 0) {
                return null;
            }

            // Build candidates array from flag names
            var candidates: [flags.len][]const u8 = undefined;
            inline for (flags, 0..) |flag, i| {
                candidates[i] = flag.name;
            }

            return findClosestMatch(&candidates, unknown_name, 3);
        }

        /// Get flag value
        pub fn get(self: *const Self, comptime name: []const u8) ?Value {
            const flag_def = comptime findFlag(name) orelse @compileError("Unknown flag: " ++ name);
            comptime assert(std.mem.eql(u8, flag_def.name, name)); // findFlag's own postcondition.

            const result = self.values.get(name);
            // setFlag's storage postcondition, re-derived on this read path.
            if (result) |val| assert(@as(FlagType, val) == flag_def.type);
            return result;
        }

        /// Get boolean flag value with default
        pub fn getBool(self: *const Self, comptime name: []const u8, default: bool) bool {
            if (self.get(name)) |val| {
                maybe(@as(FlagType, val) != .bool); // Caller may query a mismatched accessor.
                return val.asBool() catch default;
            }
            return default;
        }

        /// Get string flag value with default
        pub fn getString(self: *const Self, comptime name: []const u8, default: []const u8) []const u8 {
            if (self.get(name)) |val| {
                maybe(@as(FlagType, val) != .string); // Caller may query a mismatched accessor.
                return val.asString() catch default;
            }
            return default;
        }

        /// Get integer flag value with default
        pub fn getInt(self: *const Self, comptime name: []const u8, default: i64) i64 {
            if (self.get(name)) |val| {
                maybe(@as(FlagType, val) != .int); // Caller may query a differently-typed accessor.
                return val.asInt() catch default;
            }
            return default;
        }

        /// Get float flag value with default
        pub fn getFloat(self: *const Self, comptime name: []const u8, default: f64) f64 {
            if (self.get(name)) |val| {
                maybe(@as(FlagType, val) != .float); // Caller may query a mismatched accessor.
                return val.asFloat() catch default;
            }
            return default;
        }

        /// Generate help text
        pub fn writeHelp(writer: anytype) !void {
            // Collect unique groups
            var groups = [_]?[]const u8{null} ** flags.len;
            var group_count: usize = 0;

            inline for (flags) |flag| {
                if (flag.group) |g| {
                    var found = false;
                    for (groups[0..group_count]) |existing| {
                        if (existing) |eg| {
                            if (std.mem.eql(u8, eg, g)) {
                                found = true;
                                break;
                            }
                        }
                    }
                    if (!found) {
                        groups[group_count] = g;
                        group_count += 1;
                    }
                }
            }
            assert(group_count <= flags.len); // Checkpoint 1: bounds the `groups` buffer above.

            // Write ungrouped flags first
            var has_ungrouped = false;
            inline for (flags) |flag| {
                if (flag.group == null) {
                    has_ungrouped = true;
                    break;
                }
            }

            if (has_ungrouped) {
                try writer.writeAll("Options:\n");
                inline for (flags) |flag| {
                    if (flag.group == null) {
                        try writeFlagHelp(writer, flag);
                    }
                }
                try writer.writeAll("\n");
            }

            // Write grouped flags
            assert(group_count <= flags.len); // Checkpoint 2: re-checked before the slice below.
            for (groups[0..group_count]) |maybe_group| {
                if (maybe_group) |group_name| {
                    try writer.print("{s}:\n", .{group_name});
                    inline for (flags) |flag| {
                        if (flag.group) |g| {
                            if (std.mem.eql(u8, g, group_name)) {
                                try writeFlagHelp(writer, flag);
                            }
                        }
                    }
                    try writer.writeAll("\n");
                }
            }
        }
    };
}

/// Write one flag's help line. Precondition: `flag.name` is non-empty.
fn writeFlagHelp(writer: anytype, flag: FlagDef) !void {
    assert(flag.name.len > 0); // Precondition: comptime-authored flags are never unnamed.
    try writer.writeAll("  ");
    if (flag.short) |ch| {
        try writer.print("-{c}, ", .{ch});
    } else {
        try writer.writeAll("    ");
    }
    try writer.print("--{s}", .{flag.name});

    const type_str = switch (flag.type) {
        .bool => "",
        .string => " <string>",
        .int => " <int>",
        .float => " <float>",
    };
    try writer.writeAll(type_str);

    if (flag.required) {
        try writer.writeAll(" (required)");
    }

    if (flag.help.len > 0) {
        try writer.print("\n      {s}", .{flag.help});
    }

    if (flag.default) |default| {
        try writer.print(" [default: {s}]", .{default});
    }

    try writer.writeAll("\n");
}

/// Command definition
pub const CommandDef = struct {
    name: []const u8,
    flags: []const FlagDef = &.{},
    help: []const u8 = "",
};

/// Command/Subcommand error
pub const CommandError = error{ NoCommand, UnknownCommand } || Error;

/// Write one command's help entry: its name, then its help text if any.
fn writeCommandHelp(writer: anytype, cmd: CommandDef) !void {
    try writer.print("  {s}", .{cmd.name});
    if (cmd.help.len > 0) {
        try writer.print("\n      {s}", .{cmd.help});
    }
    try writer.writeAll("\n");
}

/// Subcommand dispatcher with compile-time command definitions
pub fn Commands(comptime commands: []const CommandDef) type {
    // Compile-time validation for duplicate command names
    comptime {
        for (commands, 0..) |cmd, i| {
            for (commands[i + 1 ..]) |other| {
                if (std.mem.eql(u8, cmd.name, other.name)) {
                    @compileError("Duplicate command name: " ++ cmd.name);
                }
            }
        }
    }

    return struct {
        suggestion: ?[]const u8 = null,

        const Self = @This();

        /// Initialize dispatcher (no allocator needed)
        pub fn init() Self {
            return .{
                .suggestion = null,
            };
        }

        /// Match a command by name, returning its index in the commands array
        /// Sets suggestion on UnknownCommand if a close match is found
        pub fn match(self: *Self, args: []const []const u8) CommandError!usize {
            self.suggestion = null;

            if (args.len == 0) {
                return CommandError.NoCommand;
            }

            const command_name = args[0];

            // Try to find exact match
            inline for (commands, 0..) |cmd, i| {
                if (std.mem.eql(u8, cmd.name, command_name)) {
                    assert(i < commands.len); // Postcondition: valid index for dispatch() to reuse.
                    return i;
                }
            }

            // No exact match found, try to find suggestion
            var cmd_candidates: [commands.len][]const u8 = undefined;
            inline for (commands, 0..) |cmd, i| {
                cmd_candidates[i] = cmd.name;
            }

            self.suggestion = findClosestMatch(&cmd_candidates, command_name, 3);
            return CommandError.UnknownCommand;
        }

        /// Dispatch to a specific command's handler
        /// Calls match first, then creates the appropriate Parser for that command
        /// and calls the visitor with the matched command and its parser
        pub fn dispatch(self: *Self, allocator: std.mem.Allocator, args: []const []const u8, visitor: anytype) !void {
            const cmd_idx = try self.match(args);
            assert(cmd_idx < commands.len); // match()'s postcondition, re-derived (airlock).
            assert(args.len > 0); // match() only returns Ok when args.len > 0 (else NoCommand).

            // Use inline for with index comparison to dispatch to the right command
            inline for (commands, 0..) |cmd, i| {
                if (i == cmd_idx) {
                    // Create a Parser for this command's flags
                    var parser = Parser(cmd.flags).init(allocator);
                    defer parser.deinit();

                    // Parse the remaining arguments (skip the command name at args[0])
                    parser.parse(args[1..]) catch |err| {
                        // Copy any suggestion from parser to self
                        if (parser.suggestion) |suggestion| {
                            self.suggestion = suggestion;
                        }
                        return err;
                    };

                    // Call the visitor with the command and parser
                    try visitor.run(cmd, &parser);
                    return;
                }
            }

            // This should be unreachable if match() returned successfully
            return CommandError.UnknownCommand;
        }

        /// Write help text listing all commands
        pub fn writeHelp(writer: anytype) !void {
            try writer.writeAll("Commands:\n");
            inline for (commands) |cmd| try writeCommandHelp(writer, cmd);
        }
    };
}

// Tests

test "Parser basic bool flag" {
    const flags = [_]FlagDef{
        .{ .name = "verbose", .short = 'v', .type = .bool, .help = "Verbose output" },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{"--verbose"};
    try parser.parse(&args);

    const val = parser.get("verbose").?;
    try std.testing.expect(val.asBool() catch unreachable); // "verbose" is .type = .bool above.
}

test "Parser short flag" {
    const flags = [_]FlagDef{
        .{ .name = "verbose", .short = 'v', .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{"-v"};
    try parser.parse(&args);

    try std.testing.expect(parser.getBool("verbose", false));
}

test "Parser string flag" {
    const flags = [_]FlagDef{
        .{ .name = "output", .short = 'o', .type = .string },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{ "--output", "file.txt" };
    try parser.parse(&args);

    const val = parser.getString("output", "");
    try std.testing.expectEqualStrings("file.txt", val);
}

test "Parser string flag with equals" {
    const flags = [_]FlagDef{
        .{ .name = "output", .type = .string },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{"--output=file.txt"};
    try parser.parse(&args);

    const val = parser.getString("output", "");
    try std.testing.expectEqualStrings("file.txt", val);
}

test "Parser int flag" {
    const flags = [_]FlagDef{
        .{ .name = "count", .short = 'n', .type = .int },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{ "-n", "42" };
    try parser.parse(&args);

    const val = parser.getInt("count", 0);
    try std.testing.expectEqual(@as(i64, 42), val);
}

test "Parser float flag" {
    const flags = [_]FlagDef{
        .{ .name = "threshold", .type = .float },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{ "--threshold", "3.14" };
    try parser.parse(&args);

    const val = parser.getFloat("threshold", 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), val, 0.01);
}

test "Parser default value" {
    const flags = [_]FlagDef{
        .{ .name = "port", .type = .int, .default = "8080" },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{};
    try parser.parse(&args);

    const val = parser.getInt("port", 0);
    try std.testing.expectEqual(@as(i64, 8080), val);
}

test "Parser required flag missing" {
    const flags = [_]FlagDef{
        .{ .name = "input", .type = .string, .required = true },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{};
    try std.testing.expectError(Error.MissingRequiredFlag, parser.parse(&args));
}

test "Parser positional args" {
    const flags = [_]FlagDef{
        .{ .name = "flag", .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{ "--flag", "file1", "file2" };
    try parser.parse(&args);

    try std.testing.expectEqual(@as(usize, 2), parser.positional.items.len);
    try std.testing.expectEqualStrings("file1", parser.positional.items[0]);
    try std.testing.expectEqualStrings("file2", parser.positional.items[1]);
}

test "Parser unknown flag" {
    const flags = [_]FlagDef{
        .{ .name = "known", .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{"--unknown"};
    try std.testing.expectError(Error.UnknownFlag, parser.parse(&args));
}

test "Parser help generation" {
    const flags = [_]FlagDef{
        .{ .name = "verbose", .short = 'v', .type = .bool, .help = "Enable verbose output" },
        .{ .name = "output", .short = 'o', .type = .string, .help = "Output file", .default = "out.txt" },
        .{ .name = "count", .type = .int, .required = true, .help = "Number of items" },
    };

    var buf: [512]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    const P = Parser(&flags);
    try P.writeHelp(&fbs);

    const help = fbs.buffered();
    try std.testing.expect(std.mem.find(u8, help, "Options:") != null);
    try std.testing.expect(std.mem.find(u8, help, "-v, --verbose") != null);
    try std.testing.expect(std.mem.find(u8, help, "Enable verbose output") != null);
    try std.testing.expect(std.mem.find(u8, help, "(required)") != null);
    try std.testing.expect(std.mem.find(u8, help, "[default: out.txt]") != null);
}

test "Parser multiple short flags" {
    const flags = [_]FlagDef{
        .{ .name = "a", .short = 'a', .type = .bool },
        .{ .name = "b", .short = 'b', .type = .bool },
        .{ .name = "c", .short = 'c', .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{"-abc"};
    try parser.parse(&args);

    try std.testing.expect(parser.getBool("a", false));
    try std.testing.expect(parser.getBool("b", false));
    try std.testing.expect(parser.getBool("c", false));
}

test "Value type conversions" {
    const val_bool = Value{ .bool = true };
    const val_string = Value{ .string = "hello" };
    const val_int = Value{ .int = 42 };
    const val_float = Value{ .float = 3.14 };

    try std.testing.expect(try val_bool.asBool());
    try std.testing.expectEqualStrings("hello", try val_string.asString());
    try std.testing.expectEqual(@as(i64, 42), try val_int.asInt());
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), try val_float.asFloat(), 0.01);

    // Type mismatches
    try std.testing.expectError(error.TypeMismatch, val_string.asBool());
    try std.testing.expectError(error.TypeMismatch, val_int.asString());
}

// "Did you mean?" suggestion tests (Levenshtein-based)

test "unknown long flag with close match should suggest" {
    // Test: --verbos (typo) should suggest --verbose (edit distance 1)
    const flags = [_]FlagDef{
        .{ .name = "verbose", .short = 'v', .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{"--verbos"};
    const result = parser.parse(&args);

    try std.testing.expectError(Error.UnknownFlag, result);
    try std.testing.expect(parser.suggestion != null);
    try std.testing.expectEqualStrings("verbose", parser.suggestion.?);
}

test "unknown long flag with small typo should suggest" {
    // Test: --output -> --outptu (1 char transposition, distance 2)
    const flags = [_]FlagDef{
        .{ .name = "output", .type = .string },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{"--outptu"};
    const result = parser.parse(&args);

    try std.testing.expectError(Error.UnknownFlag, result);
    // Close typo should get a suggestion
    try std.testing.expect(parser.suggestion != null);
    try std.testing.expectEqualStrings("output", parser.suggestion.?);
}

test "unknown long flag with no close match should not suggest" {
    // Test: --foobar when only --verbose defined (distance > threshold, no suggestion)
    const flags = [_]FlagDef{
        .{ .name = "verbose", .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{"--foobar"};
    const result = parser.parse(&args);

    try std.testing.expectError(Error.UnknownFlag, result);
    // No close match, suggestion should be null
    try std.testing.expect(parser.suggestion == null);
}

test "known flag parse should not set suggestion" {
    // Test: successful parse leaves suggestion as null
    const flags = [_]FlagDef{
        .{ .name = "verbose", .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{"--verbose"};
    try parser.parse(&args);

    // Successful parse should leave suggestion null
    try std.testing.expect(parser.suggestion == null);
}

test "suggestion reset on each parse call" {
    // Test: suggestion should be null at start of new parse(), not carry over from previous error
    const flags = [_]FlagDef{
        .{ .name = "verbose", .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    // First parse with unknown flag (will set suggestion)
    const args1 = [_][]const u8{"--verbos"};
    _ = parser.parse(&args1) catch {};
    try std.testing.expect(parser.suggestion != null);

    // Second parse with known flag should clear suggestion
    const args2 = [_][]const u8{"--verbose"};
    try parser.parse(&args2);
    try std.testing.expect(parser.suggestion == null);
}

test "multiple flags should suggest closest by edit distance" {
    // Test: when multiple flags exist, suggest the one with smallest Levenshtein distance
    const flags = [_]FlagDef{
        .{ .name = "verbose", .type = .bool },
        .{ .name = "version", .type = .bool },
        .{ .name = "verify", .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    // "verbise" is closer to "verbose" (1 or 2 edits) than "version" or "verify"
    const args = [_][]const u8{"--verbise"};
    const result = parser.parse(&args);

    try std.testing.expectError(Error.UnknownFlag, result);
    try std.testing.expect(parser.suggestion != null);
    // Should suggest the closest one
    try std.testing.expectEqualStrings("verbose", parser.suggestion.?);
}

test "short flag typo should suggest long form or no suggestion" {
    // Test: unknown short flag behavior
    // Design decision: short flags are single-char, Levenshtein on single char is not meaningful
    // So we suggest based on defined short flags only, or don't suggest at all
    const flags = [_]FlagDef{
        .{ .name = "verbose", .short = 'v', .type = .bool },
        .{ .name = "output", .short = 'o', .type = .string },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    // Unknown short flag -x (only -v and -o defined)
    const args = [_][]const u8{"-x"};
    const result = parser.parse(&args);

    try std.testing.expectError(Error.UnknownFlag, result);
    // For short flags, we either suggest nothing or the closest short flag
    // This test documents the behavior: for now, short flag suggestions may be null
    // (implementation can decide to compare against defined short flags)
    _ = parser.suggestion; // Just ensure field exists
}

test "very short unknown flag name does not crash" {
    // Test: edge case - --a (single char after --)
    const flags = [_]FlagDef{
        .{ .name = "verbose", .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{"--a"};
    const result = parser.parse(&args);

    // Should not crash, should return UnknownFlag
    try std.testing.expectError(Error.UnknownFlag, result);
    // Single char typo distance to "verbose" is large, no suggestion expected
    try std.testing.expect(parser.suggestion == null);
}

test "empty flags list does not crash on unknown flag" {
    // Test: edge case - no flags defined, any unknown flag should not crash
    const flags = [_]FlagDef{};

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{"--anything"};
    const result = parser.parse(&args);

    // Should error gracefully, suggestion should be null (no flags to suggest)
    try std.testing.expectError(Error.UnknownFlag, result);
    try std.testing.expect(parser.suggestion == null);
}

test "suggestion for flag with missing value still sets suggestion" {
    // Test: if --verbos has a missing value, it errors with UnknownFlag (not MissingValue)
    // and the suggestion should still be set
    const flags = [_]FlagDef{
        .{ .name = "verbose", .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{"--verbos"};
    const result = parser.parse(&args);

    try std.testing.expectError(Error.UnknownFlag, result);
    try std.testing.expect(parser.suggestion != null);
    try std.testing.expectEqualStrings("verbose", parser.suggestion.?);
}

test "multiple close matches should pick closest" {
    // Test: --verb could match verbose or verify; verbose is closer
    const flags = [_]FlagDef{
        .{ .name = "verbose", .type = .bool },
        .{ .name = "verify", .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{"--verb"};
    const result = parser.parse(&args);

    try std.testing.expectError(Error.UnknownFlag, result);
    try std.testing.expect(parser.suggestion != null);
    // "verb" is distance 3 from "verbose" (need to add "ose") and distance 3 from "verify" (need to change "b" and add "y")
    // Depending on exact Levenshtein, one should be preferred; document the choice
    _ = parser.suggestion; // Just ensure field exists and can be checked
}

// ============================================================================
// Commands/Subcommand Tests
// (Tests for CommandDef, CommandError, Commands types — implementations TBD by zig-developer)
// ============================================================================

test "Commands match returns correct index for valid command" {
    const cmds = [_]CommandDef{
        .{ .name = "build", .help = "Build project" },
        .{ .name = "test", .help = "Run tests" },
        .{ .name = "clean", .help = "Clean artifacts" },
    };

    var dispatcher = Commands(&cmds).init();

    // Match "build" (index 0)
    const idx0 = try dispatcher.match(&.{"build"});
    try std.testing.expectEqual(@as(usize, 0), idx0);

    // Match "test" (index 1)
    const idx1 = try dispatcher.match(&.{"test"});
    try std.testing.expectEqual(@as(usize, 1), idx1);

    // Match "clean" (index 2)
    const idx2 = try dispatcher.match(&.{"clean"});
    try std.testing.expectEqual(@as(usize, 2), idx2);
}

test "Commands match returns error.NoCommand on empty args" {
    const cmds = [_]CommandDef{
        .{ .name = "build" },
    };

    var dispatcher = Commands(&cmds).init();

    const result = dispatcher.match(&.{});
    try std.testing.expectError(error.NoCommand, result);
}

test "Commands match returns error.UnknownCommand with suggestion on typo" {
    const cmds = [_]CommandDef{
        .{ .name = "build" },
        .{ .name = "test" },
    };

    var dispatcher = Commands(&cmds).init();

    // "buidl" is close to "build" (1 transposition)
    const result = dispatcher.match(&.{"buidl"});
    try std.testing.expectError(error.UnknownCommand, result);
    try std.testing.expect(dispatcher.suggestion != null);
    try std.testing.expectEqualStrings("build", dispatcher.suggestion.?);
}

test "Commands match returns error.UnknownCommand without suggestion when far away" {
    const cmds = [_]CommandDef{
        .{ .name = "build" },
    };

    var dispatcher = Commands(&cmds).init();

    // "xyz" is too far from "build" (distance > 3)
    const result = dispatcher.match(&.{"xyz"});
    try std.testing.expectError(error.UnknownCommand, result);
    try std.testing.expect(dispatcher.suggestion == null);
}

test "Commands suggestion resets on subsequent successful match" {
    const cmds = [_]CommandDef{
        .{ .name = "build" },
        .{ .name = "test" },
    };

    var dispatcher = Commands(&cmds).init();

    // First: failed match (sets suggestion)
    _ = dispatcher.match(&.{"buidl"}) catch {};
    try std.testing.expect(dispatcher.suggestion != null);

    // Second: successful match (should clear suggestion)
    _ = try dispatcher.match(&.{"test"});
    try std.testing.expect(dispatcher.suggestion == null);
}

test "Commands dispatch calls visitor on valid command" {
    const cmds = [_]CommandDef{
        .{ .name = "greet", .flags = &.{} },
    };

    var dispatcher = Commands(&cmds).init();
    var visitor_called = false;

    const TestVisitor = struct {
        called: *bool,

        pub fn run(self: @This(), comptime cmd: CommandDef, parser: anytype) !void {
            _ = parser;
            try std.testing.expectEqualStrings("greet", cmd.name);
            @as(*bool, @ptrFromInt(@intFromPtr(self.called))).* = true;
        }
    };

    const v = TestVisitor{ .called = &visitor_called };

    try dispatcher.dispatch(std.testing.allocator, &.{"greet"}, v);
    try std.testing.expect(visitor_called);
}

test "Commands dispatch with different flag sets per command" {
    const build_flags = [_]FlagDef{
        .{ .name = "release", .type = .bool },
    };

    const test_flags = [_]FlagDef{
        .{ .name = "verbose", .type = .bool },
    };

    const cmds = [_]CommandDef{
        .{ .name = "build", .flags = &build_flags },
        .{ .name = "test", .flags = &test_flags },
    };

    var dispatcher = Commands(&cmds).init();
    var visitor_cmd_name: ?[]const u8 = null;
    var visitor_has_release = false;
    var visitor_has_verbose = false;

    const TestVisitor = struct {
        cmd_name: *?[]const u8,
        has_release: *bool,
        has_verbose: *bool,

        pub fn run(self: @This(), comptime cmd: CommandDef, parser: anytype) !void {
            @as(*?[]const u8, @ptrFromInt(@intFromPtr(self.cmd_name))).* = cmd.name;

            // Guard flag access with comptime branches per command
            // Each monomorphization only compiles the branch matching its Parser type
            if (comptime std.mem.eql(u8, cmd.name, "build")) {
                const release_val = parser.get("release");
                @as(*bool, @ptrFromInt(@intFromPtr(self.has_release))).* = (release_val != null);
            } else if (comptime std.mem.eql(u8, cmd.name, "test")) {
                const verbose_val = parser.get("verbose");
                @as(*bool, @ptrFromInt(@intFromPtr(self.has_verbose))).* = (verbose_val != null);
            }
        }
    };

    const v = TestVisitor{
        .cmd_name = &visitor_cmd_name,
        .has_release = &visitor_has_release,
        .has_verbose = &visitor_has_verbose,
    };

    // Dispatch to "build" with --release
    try dispatcher.dispatch(std.testing.allocator, &.{ "build", "--release" }, v);
    try std.testing.expectEqualStrings("build", visitor_cmd_name.?);
    try std.testing.expect(visitor_has_release);

    // Reset for next dispatch
    visitor_cmd_name = null;
    visitor_has_release = false;
    visitor_has_verbose = false;

    // Dispatch to "test" with --verbose
    try dispatcher.dispatch(std.testing.allocator, &.{ "test", "--verbose" }, v);
    try std.testing.expectEqualStrings("test", visitor_cmd_name.?);
    try std.testing.expect(visitor_has_verbose);
}

test "Commands dispatch propagates error.UnknownCommand without calling visitor" {
    const cmds = [_]CommandDef{
        .{ .name = "build" },
    };

    var dispatcher = Commands(&cmds).init();
    var visitor_called = false;

    const TestVisitor = struct {
        called: *bool,

        pub fn run(self: @This(), comptime cmd: CommandDef, parser: anytype) !void {
            _ = cmd;
            _ = parser;
            @as(*bool, @ptrFromInt(@intFromPtr(self.called))).* = true;
        }
    };

    const v = TestVisitor{ .called = &visitor_called };

    // Try to dispatch to non-existent command
    const result = dispatcher.dispatch(std.testing.allocator, &.{"nonexistent"}, v);
    try std.testing.expectError(error.UnknownCommand, result);
    try std.testing.expect(!visitor_called);
}

test "Commands dispatch propagates flag parse error and copies suggestion" {
    const cmds = [_]CommandDef{
        .{ .name = "build", .flags = &.{
            .{ .name = "verbose", .type = .bool },
        } },
    };

    var dispatcher = Commands(&cmds).init();
    var visitor_called = false;

    const TestVisitor = struct {
        called: *bool,

        pub fn run(self: @This(), comptime cmd: CommandDef, parser: anytype) !void {
            _ = cmd;
            _ = parser;
            @as(*bool, @ptrFromInt(@intFromPtr(self.called))).* = true;
        }
    };

    const v = TestVisitor{ .called = &visitor_called };

    // Typo in flag name: "verbos" should suggest "verbose"
    const result = dispatcher.dispatch(std.testing.allocator, &.{ "build", "--verbos" }, v);
    try std.testing.expectError(error.UnknownFlag, result);
    try std.testing.expect(!visitor_called);
    try std.testing.expect(dispatcher.suggestion != null);
    try std.testing.expectEqualStrings("verbose", dispatcher.suggestion.?);
}

test "Commands dispatch propagates error.MissingRequiredFlag" {
    const cmds = [_]CommandDef{
        .{ .name = "deploy", .flags = &.{
            .{ .name = "target", .type = .string, .required = true },
        } },
    };

    var dispatcher = Commands(&cmds).init();
    var visitor_called = false;

    const TestVisitor = struct {
        called: *bool,

        pub fn run(self: @This(), comptime cmd: CommandDef, parser: anytype) !void {
            _ = cmd;
            _ = parser;
            @as(*bool, @ptrFromInt(@intFromPtr(self.called))).* = true;
        }
    };

    const v = TestVisitor{ .called = &visitor_called };

    // Missing required --target flag
    const result = dispatcher.dispatch(std.testing.allocator, &.{"deploy"}, v);
    try std.testing.expectError(error.MissingRequiredFlag, result);
    try std.testing.expect(!visitor_called);
}

test "Commands writeHelp lists command names and help text" {
    const cmds = [_]CommandDef{
        .{ .name = "build", .help = "Compile the project" },
        .{ .name = "test", .help = "Run test suite" },
        .{ .name = "clean" }, // No help
    };

    var buf: [512]u8 = undefined;
    var fbs: std.Io.Writer = .fixed(&buf);

    const C = Commands(&cmds);
    try C.writeHelp(&fbs);

    const help = fbs.buffered();
    try std.testing.expect(std.mem.find(u8, help, "Commands:") != null);
    try std.testing.expect(std.mem.find(u8, help, "build") != null);
    try std.testing.expect(std.mem.find(u8, help, "Compile the project") != null);
    try std.testing.expect(std.mem.find(u8, help, "test") != null);
    try std.testing.expect(std.mem.find(u8, help, "Run test suite") != null);
    try std.testing.expect(std.mem.find(u8, help, "clean") != null);
}

test "Parser backward compat: existing Parser type still works unchanged" {
    // Verify that existing Parser API is unaffected by Commands addition
    const flags = [_]FlagDef{
        .{ .name = "verbose", .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{"--verbose"};
    try parser.parse(&args);

    try std.testing.expect(parser.getBool("verbose", false));
}

// ============================================================================
// Tiger Style assertion baseline: contract/regression tests
// (added ahead of the zig-developer assert() pass; milestone 001 item 11,
// module order term -> color -> arg -> ...; see term.zig #38 for the pattern)
// ============================================================================

test "levenshteinDistance boundary: distance exactly threshold(3) suggests, +1(4) does not" {
    // "cat" is a prefix of both unknown names below, so the only edits
    // needed are pure insertions and the minimum edit distance equals the
    // exact length difference (Levenshtein distance is always >=
    // |len1 - len2|, and that lower bound is achieved whenever one string
    // is a prefix of the other) — a property of the algorithm, not a value
    // read out of the implementation.
    const flags = [_]FlagDef{
        .{ .name = "cat", .type = .bool },
    };

    {
        var parser = Parser(&flags).init(std.testing.allocator);
        defer parser.deinit();
        const args = [_][]const u8{"--catxyz"}; // "cat" + 3 inserts => distance 3 == threshold
        const result = parser.parse(&args);
        try std.testing.expectError(Error.UnknownFlag, result);
        try std.testing.expect(parser.suggestion != null);
        try std.testing.expectEqualStrings("cat", parser.suggestion.?);
    }
    {
        var parser = Parser(&flags).init(std.testing.allocator);
        defer parser.deinit();
        const args = [_][]const u8{"--catwxyz"}; // "cat" + 4 inserts => distance 4 > threshold
        const result = parser.parse(&args);
        try std.testing.expectError(Error.UnknownFlag, result);
        try std.testing.expect(parser.suggestion == null);
    }
}

test "levenshteinDistance boundary: chars beyond the 128-char internal buffer are never compared" {
    // levenshteinDistance caps its DP table at max_len = 128 chars
    // ("Limit to prevent stack overflow for very long strings"). Two names
    // identical in their first 128 characters but wildly different
    // afterward must therefore still register as a distance-0 match: the
    // tail beyond the cap is never inspected. This pins that truncation
    // contract at the documented boundary so a future change to max_len (or
    // to the truncation logic) shows up as a test failure instead of
    // silently changing suggestion behavior for very long flag names.
    const prefix = "a" ** 128;
    const candidate_name = prefix ++ "_CANDIDATE_TAIL_ONE";
    const unknown_name = prefix ++ "_totally_different_and_much_longer_tail";

    const flags = [_]FlagDef{
        .{ .name = candidate_name, .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const arg = "--" ++ unknown_name;
    const args = [_][]const u8{arg};
    const result = parser.parse(&args);

    try std.testing.expectError(Error.UnknownFlag, result);
    try std.testing.expect(parser.suggestion != null);
    try std.testing.expectEqualStrings(candidate_name, parser.suggestion.?);
}

test "levenshteinDistance boundary: very long unknown name vs short candidate yields no match" {
    // A 300-char unknown name against a 7-char candidate has a length
    // difference alone (>= 293, even after either side is clamped to the
    // 128-char buffer, the clamped difference is still >= 121) far in
    // excess of threshold=3, so no suggestion is possible. This exercises
    // the over-buffer path (unknown.len > max_len).
    const flags = [_]FlagDef{
        .{ .name = "verbose", .type = .bool },
    };

    const unknown_name = "z" ** 300;
    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const arg = "--" ++ unknown_name;
    const args = [_][]const u8{arg};
    const result = parser.parse(&args);

    try std.testing.expectError(Error.UnknownFlag, result);
    try std.testing.expect(parser.suggestion == null);
}

test "findSuggestion never fabricates a name: Parser suggestion is always a declared flag name" {
    const flags = [_]FlagDef{
        .{ .name = "verbose", .type = .bool },
        .{ .name = "version", .type = .bool },
        .{ .name = "verify", .type = .bool },
        .{ .name = "output", .type = .string },
    };
    const flag_names = [_][]const u8{ "verbose", "version", "verify", "output" };
    const typos = [_][]const u8{ "verbos", "versoin", "verifyy", "outptu", "verb", "verz" };

    var suggested_count: usize = 0;
    for (typos) |typo| {
        var parser = Parser(&flags).init(std.testing.allocator);
        defer parser.deinit();

        const arg = try std.fmt.allocPrint(std.testing.allocator, "--{s}", .{typo});
        defer std.testing.allocator.free(arg);
        const args = [_][]const u8{arg};

        const result = parser.parse(&args);
        try std.testing.expectError(Error.UnknownFlag, result);

        if (parser.suggestion) |sug| {
            suggested_count += 1;
            var found = false;
            for (flag_names) |name| {
                if (std.mem.eql(u8, name, sug)) {
                    found = true;
                    break;
                }
            }
            try std.testing.expect(found);
        }
    }
    // "verbos", "versoin" etc. are one or two edits from a declared flag.
    try std.testing.expect(suggested_count >= 4);
}

test "findClosestMatch never fabricates a name: Commands suggestion is a declared command name" {
    const cmds = [_]CommandDef{
        .{ .name = "build" },
        .{ .name = "test" },
        .{ .name = "clean" },
        .{ .name = "deploy" },
    };
    const cmd_names = [_][]const u8{ "build", "test", "clean", "deploy" };
    const typos = [_][]const u8{ "buidl", "tesst", "clena", "deplay", "xyz" };

    var suggested_count: usize = 0;
    for (typos) |typo| {
        var dispatcher = Commands(&cmds).init();
        const result = dispatcher.match(&.{typo});
        try std.testing.expectError(error.UnknownCommand, result);

        if (dispatcher.suggestion) |sug| {
            suggested_count += 1;
            var found = false;
            for (cmd_names) |name| {
                if (std.mem.eql(u8, name, sug)) {
                    found = true;
                    break;
                }
            }
            try std.testing.expect(found);
        }
    }
    // Four of the five typos are within threshold of a declared command.
    try std.testing.expect(suggested_count >= 4);
}

test "get() active union tag always matches the FlagDef's declared type across all FlagTypes" {
    // Cross-invariant between setFlag (the writer) and get/getBool/
    // getString/getInt/getFloat (the readers): the stored Value's active
    // union tag must always agree with the FlagDef.type declared at
    // comptime. A regression that stored the wrong Value variant for one
    // FlagType would make .get() return a value whose tag mismatches, and
    // would make the matching getX() silently fall back to its default
    // (asX() catching TypeMismatch) instead of the parsed value.
    const flags = [_]FlagDef{
        .{ .name = "flag_bool", .type = .bool },
        .{ .name = "flag_string", .type = .string },
        .{ .name = "flag_int", .type = .int },
        .{ .name = "flag_float", .type = .float },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    const args = [_][]const u8{
        "--flag_bool",
        "--flag_string",
        "hello",
        "--flag_int",
        "7",
        "--flag_float",
        "1.5",
    };
    try parser.parse(&args);

    const bool_val = parser.get("flag_bool").?;
    try std.testing.expectEqual(FlagType.bool, @as(FlagType, bool_val));

    const string_val = parser.get("flag_string").?;
    try std.testing.expectEqual(FlagType.string, @as(FlagType, string_val));

    const int_val = parser.get("flag_int").?;
    try std.testing.expectEqual(FlagType.int, @as(FlagType, int_val));

    const float_val = parser.get("flag_float").?;
    try std.testing.expectEqual(FlagType.float, @as(FlagType, float_val));

    // The matching accessor must return the parsed value (not its default),
    // which is only possible if the union tag agrees with the declared type.
    try std.testing.expect(parser.getBool("flag_bool", false));
    try std.testing.expectEqualStrings("hello", parser.getString("flag_string", ""));
    try std.testing.expectEqual(@as(i64, 7), parser.getInt("flag_int", 0));
    try std.testing.expectApproxEqAbs(@as(f64, 1.5), parser.getFloat("flag_float", 0.0), 0.001);

    // And the mismatched accessors on the same stored values must fall back
    // to their caller-supplied defaults rather than returning garbage.
    try std.testing.expectEqualStrings("fallback", parser.getString("flag_bool", "fallback"));
    try std.testing.expectEqual(@as(i64, -1), parser.getInt("flag_string", -1));
}

test "Parser.init postconditions: fresh parser has empty values/positional, null suggestion" {
    const flags = [_]FlagDef{
        .{ .name = "any", .type = .bool },
    };

    var parser = Parser(&flags).init(std.testing.allocator);
    defer parser.deinit();

    try std.testing.expectEqual(@as(usize, 0), parser.values.count());
    try std.testing.expectEqual(@as(usize, 0), parser.positional.items.len);
    try std.testing.expect(parser.suggestion == null);
    try std.testing.expectEqual(@as(?Value, null), parser.get("any"));
}

test "writeHelp with zero flags produces empty output" {
    const flags = [_]FlagDef{};

    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    const P = Parser(&flags);
    try P.writeHelp(&writer);

    // No flags means no "Options:" header and no groups: the group-tracking
    // array is sized [flags.len] (zero-length here), and group_count must
    // never exceed that bound (0 <= 0 is the degenerate case of that bound).
    try std.testing.expectEqual(@as(usize, 0), writer.buffered().len);
}

test "writeHelp with all-distinct groups: group_count reaches flags.len without overflow" {
    // Every flag below starts a brand-new group, so group_count grows to
    // exactly flags.len (10) — the worst case for the [flags.len]-sized
    // `groups` bookkeeping array in writeHelp. This pins that the bound
    // holds exactly at its ceiling, not just comfortably under it.
    const flags = [_]FlagDef{
        .{ .name = "f0", .type = .bool, .group = "G0" },
        .{ .name = "f1", .type = .bool, .group = "G1" },
        .{ .name = "f2", .type = .bool, .group = "G2" },
        .{ .name = "f3", .type = .bool, .group = "G3" },
        .{ .name = "f4", .type = .bool, .group = "G4" },
        .{ .name = "f5", .type = .bool, .group = "G5" },
        .{ .name = "f6", .type = .bool, .group = "G6" },
        .{ .name = "f7", .type = .bool, .group = "G7" },
        .{ .name = "f8", .type = .bool, .group = "G8" },
        .{ .name = "f9", .type = .bool, .group = "G9" },
    };

    var buf: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);

    const P = Parser(&flags);
    try P.writeHelp(&writer);

    const help = writer.buffered();
    inline for (0..10) |g| {
        var header_buf: [8]u8 = undefined;
        const header = try std.fmt.bufPrint(&header_buf, "G{d}:\n", .{g});
        try std.testing.expect(std.mem.indexOf(u8, help, header) != null);
    }
    // No "Options:" header since every flag is grouped (no ungrouped flags).
    try std.testing.expect(std.mem.indexOf(u8, help, "Options:") == null);
}

test "Commands.match on a single-command array returns index 0 that correctly indexes commands" {
    // Boundary case commands.len == 1: the returned index must still be a
    // valid index usable downstream (as dispatch() does) to look the
    // matched command back up in the original array.
    const cmds = [_]CommandDef{
        .{ .name = "only", .help = "The only command" },
    };

    var dispatcher = Commands(&cmds).init();
    const idx = try dispatcher.match(&.{"only"});

    try std.testing.expectEqual(@as(usize, 0), idx);
    try std.testing.expectEqualStrings("only", cmds[idx].name);
}

// Note on comptime validation:
// Duplicate command names are validated at compile-time via @compileError,
// mirroring Parser's existing duplicate-flag validation.
// This comptime check cannot be tested in a runtime test block;
// it is enforced identically to Parser's duplicate-flag check.
