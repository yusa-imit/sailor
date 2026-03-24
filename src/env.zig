//! Environment variable configuration system
//!
//! Provides standardized access to environment variables with:
//! - String retrieval with defaults (`get`)
//! - Boolean parsing with case-insensitive matching (`getBool`)
//! - Integer parsing with type bounds checking (`getInt`)

const std = @import("std");

// C library bindings for environment variable manipulation
// These are needed for tests since Zig 0.15.2's std.posix doesn't have setenv/unsetenv
extern "c" fn setenv(key: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(key: [*:0]const u8) c_int;

/// Retrieves an environment variable with a fallback default.
///
/// If the environment variable is set (even to an empty string),
/// its value is duplicated using the provided allocator and returned.
/// If the environment variable is not set, the default value is duplicated
/// instead. The caller is responsible for freeing the returned memory.
///
/// Args:
///   allocator: Memory allocator for duplicating the result
///   key: Environment variable name
///   default: Fallback value if env var is not set
///
/// Returns:
///   Allocated string containing either the env var value or the default.
///   Caller must free the returned slice.
pub fn get(allocator: std.mem.Allocator, key: []const u8, default: []const u8) ![]const u8 {
    // Try to get the env var from the environment
    const env_value = std.posix.getenv(key);

    if (env_value) |value| {
        // Environment variable is set; duplicate it
        return try allocator.dupe(u8, value);
    } else {
        // Environment variable is not set; use default
        return try allocator.dupe(u8, default);
    }
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
///   key: Environment variable name
///   default: Fallback value if env var is not set
///
/// Returns:
///   Parsed boolean value or default
pub fn getBool(key: []const u8, default: bool) bool {
    const env_value = std.posix.getenv(key) orelse return default;

    // Convert to lowercase for case-insensitive comparison
    if (env_value.len >= 32) {
        // Value too long to fit in buffer; treat as false
        return false;
    }

    var lowercase: [32]u8 = undefined;
    for (env_value, 0..) |c, i| {
        lowercase[i] = std.ascii.toLower(c);
    }

    const lower = lowercase[0..env_value.len];

    // Check for true values
    if (std.mem.eql(u8, lower, "1") or
        std.mem.eql(u8, lower, "true") or
        std.mem.eql(u8, lower, "yes") or
        std.mem.eql(u8, lower, "on") or
        std.mem.eql(u8, lower, "y")) {
        return true;
    }

    // Check for false values
    if (std.mem.eql(u8, lower, "0") or
        std.mem.eql(u8, lower, "false") or
        std.mem.eql(u8, lower, "no") or
        std.mem.eql(u8, lower, "off") or
        std.mem.eql(u8, lower, "n")) {
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
///   key: Environment variable name
///   default: Fallback value on parse error or missing env var
///
/// Returns:
///   Parsed integer or default value
pub fn getInt(comptime T: type, key: []const u8, default: T) T {
    const env_value = std.posix.getenv(key) orelse return default;

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
    _ = setenv("SAILOR_TEST_GET", "test_value", 1);
    defer _ = unsetenv("SAILOR_TEST_GET");

    const result = try get(allocator, "SAILOR_TEST_GET", "default");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("test_value", result);
}

test "get returns default for unset variable" {
    const allocator = std.testing.allocator;

    // Ensure the var is not set
    _ = unsetenv("SAILOR_TEST_UNSET");

    const result = try get(allocator, "SAILOR_TEST_UNSET", "fallback");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("fallback", result);
}

test "get returns empty string when variable is set to empty" {
    const allocator = std.testing.allocator;

    _ = setenv("SAILOR_TEST_EMPTY", "", 1);
    defer _ = unsetenv("SAILOR_TEST_EMPTY");

    const result = try get(allocator, "SAILOR_TEST_EMPTY", "default");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}

test "get does not leak memory" {
    const allocator = std.testing.allocator;

    _ = setenv("SAILOR_TEST_LEAK", "some_value", 1);
    defer _ = unsetenv("SAILOR_TEST_LEAK");

    // Multiple allocations and frees
    for (0..10) |_| {
        const result = try get(allocator, "SAILOR_TEST_LEAK", "default");
        allocator.free(result);
    }

    // If there's a leak, allocator will catch it
}

test "getBool recognizes true value: 1" {
    _ = setenv("SAILOR_TEST_BOOL", "1", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(getBool("SAILOR_TEST_BOOL", false));
}

test "getBool recognizes true value: true" {
    _ = setenv("SAILOR_TEST_BOOL", "true", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(getBool("SAILOR_TEST_BOOL", false));
}

test "getBool recognizes true value: yes" {
    _ = setenv("SAILOR_TEST_BOOL", "yes", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(getBool("SAILOR_TEST_BOOL", false));
}

test "getBool recognizes true value: on" {
    _ = setenv("SAILOR_TEST_BOOL", "on", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(getBool("SAILOR_TEST_BOOL", false));
}

test "getBool recognizes true value: y" {
    _ = setenv("SAILOR_TEST_BOOL", "y", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(getBool("SAILOR_TEST_BOOL", false));
}

test "getBool recognizes false value: 0" {
    _ = setenv("SAILOR_TEST_BOOL", "0", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(!getBool("SAILOR_TEST_BOOL", true));
}

test "getBool recognizes false value: false" {
    _ = setenv("SAILOR_TEST_BOOL", "false", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(!getBool("SAILOR_TEST_BOOL", true));
}

test "getBool recognizes false value: no" {
    _ = setenv("SAILOR_TEST_BOOL", "no", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(!getBool("SAILOR_TEST_BOOL", true));
}

test "getBool recognizes false value: off" {
    _ = setenv("SAILOR_TEST_BOOL", "off", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(!getBool("SAILOR_TEST_BOOL", true));
}

test "getBool recognizes false value: n" {
    _ = setenv("SAILOR_TEST_BOOL", "n", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(!getBool("SAILOR_TEST_BOOL", true));
}

test "getBool is case-insensitive: TRUE" {
    _ = setenv("SAILOR_TEST_BOOL", "TRUE", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(getBool("SAILOR_TEST_BOOL", false));
}

test "getBool is case-insensitive: False" {
    _ = setenv("SAILOR_TEST_BOOL", "False", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(!getBool("SAILOR_TEST_BOOL", true));
}

test "getBool is case-insensitive: YeS" {
    _ = setenv("SAILOR_TEST_BOOL", "YeS", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(getBool("SAILOR_TEST_BOOL", false));
}

test "getBool returns default when variable is unset" {
    _ = unsetenv("SAILOR_TEST_BOOL_UNSET");

    try std.testing.expect(getBool("SAILOR_TEST_BOOL_UNSET", true));
    try std.testing.expect(!getBool("SAILOR_TEST_BOOL_UNSET", false));
}

test "getBool treats empty string as false" {
    _ = setenv("SAILOR_TEST_BOOL", "", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(!getBool("SAILOR_TEST_BOOL", true));
}

test "getBool treats invalid value as false" {
    _ = setenv("SAILOR_TEST_BOOL", "invalid", 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(!getBool("SAILOR_TEST_BOOL", true));
}

test "getBool treats long value (>32 chars) as false" {
    const long_value = "this_is_a_very_long_string_that_exceeds_32_characters";
    _ = setenv("SAILOR_TEST_BOOL", long_value, 1);
    defer _ = unsetenv("SAILOR_TEST_BOOL");

    try std.testing.expect(!getBool("SAILOR_TEST_BOOL", true));
}

test "getInt parses valid positive integer (u32)" {
    _ = setenv("SAILOR_TEST_INT", "12345", 1);
    defer _ = unsetenv("SAILOR_TEST_INT");

    const result = getInt(u32, "SAILOR_TEST_INT", 0);
    try std.testing.expectEqual(@as(u32, 12345), result);
}

test "getInt parses valid negative integer (i32)" {
    _ = setenv("SAILOR_TEST_INT", "-9876", 1);
    defer _ = unsetenv("SAILOR_TEST_INT");

    const result = getInt(i32, "SAILOR_TEST_INT", 0);
    try std.testing.expectEqual(@as(i32, -9876), result);
}

test "getInt returns default on overflow (u8)" {
    _ = setenv("SAILOR_TEST_INT", "300", 1); // u8 max is 255
    defer _ = unsetenv("SAILOR_TEST_INT");

    const result = getInt(u8, "SAILOR_TEST_INT", 42);
    try std.testing.expectEqual(@as(u8, 42), result);
}

test "getInt returns default on underflow (u32)" {
    _ = setenv("SAILOR_TEST_INT", "-100", 1);
    defer _ = unsetenv("SAILOR_TEST_INT");

    const result = getInt(u32, "SAILOR_TEST_INT", 99);
    try std.testing.expectEqual(@as(u32, 99), result);
}

test "getInt returns default on invalid format" {
    _ = setenv("SAILOR_TEST_INT", "not_a_number", 1);
    defer _ = unsetenv("SAILOR_TEST_INT");

    const result = getInt(i32, "SAILOR_TEST_INT", -1);
    try std.testing.expectEqual(@as(i32, -1), result);
}

test "getInt returns default when variable is unset" {
    _ = unsetenv("SAILOR_TEST_INT_UNSET");

    const result = getInt(i32, "SAILOR_TEST_INT_UNSET", 777);
    try std.testing.expectEqual(@as(i32, 777), result);
}

test "getInt parses max value for type (i8)" {
    _ = setenv("SAILOR_TEST_INT", "127", 1);
    defer _ = unsetenv("SAILOR_TEST_INT");

    const result = getInt(i8, "SAILOR_TEST_INT", 0);
    try std.testing.expectEqual(@as(i8, 127), result);
}

test "getInt parses min value for type (i8)" {
    _ = setenv("SAILOR_TEST_INT", "-128", 1);
    defer _ = unsetenv("SAILOR_TEST_INT");

    const result = getInt(i8, "SAILOR_TEST_INT", 0);
    try std.testing.expectEqual(@as(i8, -128), result);
}

test "getInt parses max value for type (u16)" {
    _ = setenv("SAILOR_TEST_INT", "65535", 1);
    defer _ = unsetenv("SAILOR_TEST_INT");

    const result = getInt(u16, "SAILOR_TEST_INT", 0);
    try std.testing.expectEqual(@as(u16, 65535), result);
}

test "getInt rejects leading whitespace" {
    _ = setenv("SAILOR_TEST_INT", " 123", 1);
    defer _ = unsetenv("SAILOR_TEST_INT");

    const result = getInt(i32, "SAILOR_TEST_INT", 999);
    try std.testing.expectEqual(@as(i32, 999), result);
}

test "getInt rejects trailing whitespace" {
    _ = setenv("SAILOR_TEST_INT", "123 ", 1);
    defer _ = unsetenv("SAILOR_TEST_INT");

    const result = getInt(i32, "SAILOR_TEST_INT", 999);
    try std.testing.expectEqual(@as(i32, 999), result);
}

test "getInt parses zero" {
    _ = setenv("SAILOR_TEST_INT", "0", 1);
    defer _ = unsetenv("SAILOR_TEST_INT");

    const result = getInt(i32, "SAILOR_TEST_INT", -1);
    try std.testing.expectEqual(@as(i32, 0), result);
}

test "getInt rejects empty string" {
    _ = setenv("SAILOR_TEST_INT", "", 1);
    defer _ = unsetenv("SAILOR_TEST_INT");

    const result = getInt(i32, "SAILOR_TEST_INT", 555);
    try std.testing.expectEqual(@as(i32, 555), result);
}
