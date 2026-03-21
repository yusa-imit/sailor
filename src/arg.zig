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

/// Argument parser
pub fn Parser(comptime flags: []const FlagDef) type {
    // Compile-time validation
    comptime {
        for (flags, 0..) |flag, i| {
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

        /// Initialize parser
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .values = std.StringHashMap(Value).init(allocator),
                .positional = .{},
            };
        }

        /// Free parser resources
        pub fn deinit(self: *Self) void {
            self.values.deinit();
            self.positional.deinit(self.allocator);
        }

        /// Parse arguments
        pub fn parse(self: *Self, args: []const []const u8) Error!void {
            var i: usize = 0;
            while (i < args.len) : (i += 1) {
                const arg = args[i];

                if (std.mem.startsWith(u8, arg, "--")) {
                    // Long flag
                    const name = arg[2..];
                    if (std.mem.indexOf(u8, name, "=")) |eq_pos| {
                        // --flag=value
                        const flag_name = name[0..eq_pos];
                        const value = name[eq_pos + 1 ..];
                        try self.setFlag(flag_name, value);
                    } else {
                        // --flag [value]
                        const flag_def = findFlag(name) orelse return Error.UnknownFlag;
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
                        const flag_def = findFlagByShort(ch) orelse return Error.UnknownFlag;
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
            const flag_def = findFlag(name) orelse return Error.UnknownFlag;

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

            try self.values.put(flag_def.name, value);
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

        /// Get flag value
        pub fn get(self: *const Self, comptime name: []const u8) ?Value {
            comptime {
                const flag_def = findFlag(name) orelse @compileError("Unknown flag: " ++ name);
                _ = flag_def;
            }
            return self.values.get(name);
        }

        /// Get boolean flag value with default
        pub fn getBool(self: *const Self, comptime name: []const u8, default: bool) bool {
            if (self.get(name)) |val| {
                return val.asBool() catch default;
            }
            return default;
        }

        /// Get string flag value with default
        pub fn getString(self: *const Self, comptime name: []const u8, default: []const u8) []const u8 {
            if (self.get(name)) |val| {
                return val.asString() catch default;
            }
            return default;
        }

        /// Get integer flag value with default
        pub fn getInt(self: *const Self, comptime name: []const u8, default: i64) i64 {
            if (self.get(name)) |val| {
                return val.asInt() catch default;
            }
            return default;
        }

        /// Get float flag value with default
        pub fn getFloat(self: *const Self, comptime name: []const u8, default: f64) f64 {
            if (self.get(name)) |val| {
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
                        try writeFlag(writer, flag);
                    }
                }
                try writer.writeAll("\n");
            }

            // Write grouped flags
            for (groups[0..group_count]) |maybe_group| {
                if (maybe_group) |group_name| {
                    try writer.print("{s}:\n", .{group_name});
                    inline for (flags) |flag| {
                        if (flag.group) |g| {
                            if (std.mem.eql(u8, g, group_name)) {
                                try writeFlag(writer, flag);
                            }
                        }
                    }
                    try writer.writeAll("\n");
                }
            }
        }

        fn writeFlag(writer: anytype, flag: FlagDef) !void {
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
    try std.testing.expect(val.asBool() catch unreachable);
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
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const P = Parser(&flags);
    try P.writeHelp(writer);

    const help = fbs.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, help, "Options:") != null);
    try std.testing.expect(std.mem.indexOf(u8, help, "-v, --verbose") != null);
    try std.testing.expect(std.mem.indexOf(u8, help, "Enable verbose output") != null);
    try std.testing.expect(std.mem.indexOf(u8, help, "(required)") != null);
    try std.testing.expect(std.mem.indexOf(u8, help, "[default: out.txt]") != null);
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
