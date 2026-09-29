//! Environment variable configuration system
//!
//! Provides standardized access to environment variables with:
//! - String retrieval with defaults (`get`)
//! - Boolean parsing with case-insensitive matching (`getBool`)
//! - Integer parsing with type bounds checking (`getInt`)

const std = @import("std");

/// Retrieves an environment variable with a fallback default.
///
/// If the environment variable is set (even to an empty string),
/// its value is duplicated using the provided allocator and returned.
/// If the environment variable is not set, the default value is duplicated
/// instead. The caller is responsible for freeing the returned memory.
///
/// Args:
///   allocator: Memory allocator for duplicating the result
///   environ_map: Injected environment (borrowed)
///   key: Environment variable name
///   default: Fallback value if env var is not set
///
/// Returns:
///   Allocated string containing either the env var value or the default.
///   Caller must free the returned slice.
pub fn get(
    allocator: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
    key: []const u8,
    default: []const u8,
) ![]const u8 {
    // Precondition: an empty key can never name a variable.
    std.debug.assert(key.len > 0);
    const env_value = environ_map.get(key) orelse default;
    const result = try allocator.dupe(u8, env_value);
    std.debug.assert(result.len == env_value.len);
    return result;
}

/// Parses an environment variable as a boolean value.
///
/// Recognizes the following as true (case-insensitive):
///   "1", "true", "yes", "on", "y"
///
/// Recognizes the following as false (case-insensitive):
///   "0", "false", "no", "off", "n"
///
/// Any other value (including empty string) is treated as false.
/// If the environment variable is not set, returns the provided default.
///
/// Args:
///   environ_map: Injected environment (borrowed)
///   key: Environment variable name
///   default: Fallback value if env var is not set
///
/// Returns:
///   Parsed boolean value or default
pub fn getBool(
    environ_map: *const std.process.Environ.Map,
    key: []const u8,
    default: bool,
) bool {
    // Precondition: an empty key can never name a variable.
    std.debug.assert(key.len > 0);
    const env_value = environ_map.get(key) orelse return default;

    // Convert to lowercase for case-insensitive comparison
    if (env_value.len >= 32) {
        // Value too long to fit in buffer; treat as false
        return false;
    }

    var lowercase: [32]u8 = undefined;
    for (env_value, 0..) |c, i| {
        std.debug.assert(i < lowercase.len);
        lowercase[i] = std.ascii.toLower(c);
    }

    const lower = lowercase[0..env_value.len];

    // Check for true values
    if (std.mem.eql(u8, lower, "1") or
        std.mem.eql(u8, lower, "true") or
        std.mem.eql(u8, lower, "yes") or
        std.mem.eql(u8, lower, "on") or
        std.mem.eql(u8, lower, "y"))
    {
        return true;
    }

    // Check for false values
    if (std.mem.eql(u8, lower, "0") or
        std.mem.eql(u8, lower, "false") or
        std.mem.eql(u8, lower, "no") or
        std.mem.eql(u8, lower, "off") or
        std.mem.eql(u8, lower, "n"))
    {
        return false;
    }

    // Any other value (including empty string) is treated as false
    return false;
}

/// Parses an environment variable as an integer of the specified type.
///
/// Attempts to parse the environment variable value as an integer.
/// If parsing fails (invalid format, overflow, or env var not set),
/// returns the provided default value.
///
/// The parser uses `std.fmt.parseInt` with base 10 and expects
/// strictly numeric input (leading/trailing whitespace is rejected).
///
/// Args:
///   T: The integer type to parse into (e.g., u8, u16, u32, i32, i64)
///   environ_map: Injected environment (borrowed)
///   key: Environment variable name
///   default: Fallback value on parse error or missing env var
///
/// Returns:
///   Parsed integer or default value
pub fn getInt(
    comptime T: type,
    environ_map: *const std.process.Environ.Map,
    key: []const u8,
    default: T,
) T {
    comptime std.debug.assert(@typeInfo(T) == .int);
    // Precondition: an empty key can never name a variable.
    std.debug.assert(key.len > 0);
    const env_value = environ_map.get(key) orelse return default;

    // Try to parse as integer with base 10
    const result = std.fmt.parseInt(T, env_value, 10) catch {
        // On any parse error, return the default
        return default;
    };

    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "get retrieves set environment variable" {
    const allocator = std.testing.allocator;

    // Set test env var
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_GET", "test_value");

    const result = try get(allocator, &map, "SAILOR_TEST_GET", "default");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("test_value", result);
}

test "get returns default for unset variable" {
    const allocator = std.testing.allocator;

    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();

    const result = try get(allocator, &map, "SAILOR_TEST_UNSET", "fallback");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("fallback", result);
}

test "get returns empty string when variable is set to empty" {
    const allocator = std.testing.allocator;

    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_EMPTY", "");

    const result = try get(allocator, &map, "SAILOR_TEST_EMPTY", "default");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

test "get does not leak memory" {
    const allocator = std.testing.allocator;

    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_LEAK", "some_value");

    // Multiple allocations and frees
    for (0..10) |_| {
        const result = try get(allocator, &map, "SAILOR_TEST_LEAK", "default");
        allocator.free(result);
    }

    // If there's a leak, allocator will catch it
}

test "getBool recognizes true value: 1" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "1");

    try std.testing.expect(getBool(&map, "SAILOR_TEST_BOOL", false));
}

test "getBool recognizes true value: true" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "true");

    try std.testing.expect(getBool(&map, "SAILOR_TEST_BOOL", false));
}

test "getBool recognizes true value: yes" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "yes");

    try std.testing.expect(getBool(&map, "SAILOR_TEST_BOOL", false));
}

test "getBool recognizes true value: on" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "on");

    try std.testing.expect(getBool(&map, "SAILOR_TEST_BOOL", false));
}

test "getBool recognizes true value: y" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "y");

    try std.testing.expect(getBool(&map, "SAILOR_TEST_BOOL", false));
}

test "getBool recognizes false value: 0" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "0");

    try std.testing.expect(!getBool(&map, "SAILOR_TEST_BOOL", true));
}

test "getBool recognizes false value: false" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "false");

    try std.testing.expect(!getBool(&map, "SAILOR_TEST_BOOL", true));
}

test "getBool recognizes false value: no" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "no");

    try std.testing.expect(!getBool(&map, "SAILOR_TEST_BOOL", true));
}

test "getBool recognizes false value: off" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "off");

    try std.testing.expect(!getBool(&map, "SAILOR_TEST_BOOL", true));
}

test "getBool recognizes false value: n" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "n");

    try std.testing.expect(!getBool(&map, "SAILOR_TEST_BOOL", true));
}

test "getBool is case-insensitive: TRUE" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "TRUE");

    try std.testing.expect(getBool(&map, "SAILOR_TEST_BOOL", false));
}

test "getBool is case-insensitive: False" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "False");

    try std.testing.expect(!getBool(&map, "SAILOR_TEST_BOOL", true));
}

test "getBool is case-insensitive: YeS" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "YeS");

    try std.testing.expect(getBool(&map, "SAILOR_TEST_BOOL", false));
}

test "getBool returns default when variable is unset" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();

    try std.testing.expect(getBool(&map, "SAILOR_TEST_BOOL_UNSET", true));
    try std.testing.expect(!getBool(&map, "SAILOR_TEST_BOOL_UNSET", false));
}

test "getBool treats empty string as false" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "");

    try std.testing.expect(!getBool(&map, "SAILOR_TEST_BOOL", true));
}

test "getBool treats invalid value as false" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", "invalid");

    try std.testing.expect(!getBool(&map, "SAILOR_TEST_BOOL", true));
}

test "getBool treats long value (>32 chars) as false" {
    const long_value = "this_is_a_very_long_string_that_exceeds_32_characters";
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_BOOL", long_value);

    try std.testing.expect(!getBool(&map, "SAILOR_TEST_BOOL", true));
}

test "getInt parses valid positive integer (u32)" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_INT", "12345");

    const result = getInt(u32, &map, "SAILOR_TEST_INT", 0);
    try std.testing.expectEqual(@as(u32, 12345), result);
}

test "getInt parses valid negative integer (i32)" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_INT", "-9876");

    const result = getInt(i32, &map, "SAILOR_TEST_INT", 0);
    try std.testing.expectEqual(@as(i32, -9876), result);
}

test "getInt returns default on overflow (u8)" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_INT", "300");

    const result = getInt(u8, &map, "SAILOR_TEST_INT", 42);
    try std.testing.expectEqual(@as(u8, 42), result);
}

test "getInt returns default on underflow (u32)" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_INT", "-100");

    const result = getInt(u32, &map, "SAILOR_TEST_INT", 99);
    try std.testing.expectEqual(@as(u32, 99), result);
}

test "getInt returns default on invalid format" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_INT", "not_a_number");

    const result = getInt(i32, &map, "SAILOR_TEST_INT", -1);
    try std.testing.expectEqual(@as(i32, -1), result);
}

test "getInt returns default when variable is unset" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();

    const result = getInt(i32, &map, "SAILOR_TEST_INT_UNSET", 777);
    try std.testing.expectEqual(@as(i32, 777), result);
}

test "getInt parses max value for type (i8)" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_INT", "127");

    const result = getInt(i8, &map, "SAILOR_TEST_INT", 0);
    try std.testing.expectEqual(@as(i8, 127), result);
}

test "getInt parses min value for type (i8)" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_INT", "-128");

    const result = getInt(i8, &map, "SAILOR_TEST_INT", 0);
    try std.testing.expectEqual(@as(i8, -128), result);
}

test "getInt parses max value for type (u16)" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_INT", "65535");

    const result = getInt(u16, &map, "SAILOR_TEST_INT", 0);
    try std.testing.expectEqual(@as(u16, 65535), result);
}

test "getInt rejects leading whitespace" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_INT", " 123");

    const result = getInt(i32, &map, "SAILOR_TEST_INT", 999);
    try std.testing.expectEqual(@as(i32, 999), result);
}

test "getInt rejects trailing whitespace" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_INT", "123 ");

    const result = getInt(i32, &map, "SAILOR_TEST_INT", 999);
    try std.testing.expectEqual(@as(i32, 999), result);
}

test "getInt parses zero" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_INT", "0");

    const result = getInt(i32, &map, "SAILOR_TEST_INT", -1);
    try std.testing.expectEqual(@as(i32, 0), result);
}

test "getInt rejects empty string" {
    var map = std.process.Environ.Map.init(std.testing.allocator);
    defer map.deinit();
    try map.put("SAILOR_TEST_INT", "");

    const result = getInt(i32, &map, "SAILOR_TEST_INT", 555);
    try std.testing.expectEqual(@as(i32, 555), result);
}
