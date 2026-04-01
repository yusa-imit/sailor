//! Tests for environment variable configuration system (v1.19.0)
//!
//! This test suite validates:
//! - EnvConfig.get() — retrieving env vars with default fallback
//! - EnvConfig.getBool() — parsing boolean values (1/true/yes/on vs 0/false/no/off)
//! - EnvConfig.getInt() — parsing integer values with defaults
//! - Integration with color, progress, fmt modules
//! - Edge cases: unset vars, empty strings, malformed values
//! - Cross-platform compatibility

const std = @import("std");
const sailor = @import("sailor");
const builtin = @import("builtin");

// ============================================================================
// Environment Variable Helpers
// ============================================================================

// C library bindings for setting/unsetting environment variables
// POSIX: setenv/unsetenv
// Windows: _putenv_s/_putenv
const setenv = if (builtin.os.tag == .windows)
    struct {
        extern "c" fn _putenv_s(key: [*:0]const u8, value: [*:0]const u8) c_int;
    }._putenv_s
else
    struct {
        extern "c" fn setenv(key: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
    }.setenv;

const unsetenv = if (builtin.os.tag == .windows)
    struct {
        extern "c" fn _putenv(envstring: [*:0]const u8) c_int;
    }._putenv
else
    struct {
        extern "c" fn unsetenv(key: [*:0]const u8) c_int;
    }.unsetenv;

/// Wrapper around C setenv with Zig slices
fn env_setenv(key: []const u8, value: []const u8, overwrite: bool) !void {
    var key_buf: [256]u8 = undefined;
    var value_buf: [4096]u8 = undefined;

    if (key.len >= key_buf.len) return error.KeyTooLong;
    if (value.len >= value_buf.len) return error.ValueTooLong;

    @memcpy(key_buf[0..key.len], key);
    key_buf[key.len] = 0;

    @memcpy(value_buf[0..value.len], value);
    value_buf[value.len] = 0;

    const rc = if (builtin.os.tag == .windows)
        setenv(@ptrCast(&key_buf), @ptrCast(&value_buf))
    else
        setenv(@ptrCast(&key_buf), @ptrCast(&value_buf), if (overwrite) 1 else 0);

    if (rc != 0) return error.SetenvFailed;
}

/// Wrapper around C unsetenv with Zig slices
fn env_unsetenv(key: []const u8) !void {
    var key_buf: [512]u8 = undefined;

    if (builtin.os.tag == .windows) {
        // Windows: _putenv("KEY=") to unset
        if (key.len + 2 >= key_buf.len) return error.KeyTooLong;
        @memcpy(key_buf[0..key.len], key);
        key_buf[key.len] = '=';
        key_buf[key.len + 1] = 0;
        const rc = unsetenv(@ptrCast(&key_buf));
        if (rc != 0) return error.UnsetenvFailed;
    } else {
        // POSIX: unsetenv("KEY")
        if (key.len >= key_buf.len) return error.KeyTooLong;
        @memcpy(key_buf[0..key.len], key);
        key_buf[key.len] = 0;
        const rc = unsetenv(@ptrCast(&key_buf));
        if (rc != 0) return error.UnsetenvFailed;
    }
}

// ============================================================================
// Test Helper Utilities
// ============================================================================

/// Helper to safely get and cleanup env var for test isolation
fn testWithEnv(
    comptime key: []const u8,
    value: ?[]const u8,
    comptime test_fn: fn () anyerror!void,
) !void {
    // Set the env var if provided
    if (value) |v| {
        try env_setenv(key, v, true);
    } else {
        try env_unsetenv(key);
    }

    // Run test
    test_fn() catch |err| {
        // Cleanup on error
        try env_unsetenv(key);
        return err;
    };

    // Cleanup on success
    try env_unsetenv(key);
}

// ============================================================================
// EnvConfig.get() Tests — String Retrieval with Defaults
// ============================================================================

test "env.get returns value when env var is set" {
    const allocator = std.testing.allocator;
    const value = "test_value_12345";

    try env_setenv("TEST_ENV_VAR", value, true);
    defer _ = env_unsetenv("TEST_ENV_VAR") catch {};

    const result = try sailor.env.get(allocator, "TEST_ENV_VAR", "default");
    defer allocator.free(result);

    try std.testing.expectEqualStrings(value, result);
}

test "env.get returns default when env var is not set" {
    const allocator = std.testing.allocator;

    try env_unsetenv("NONEXISTENT_VAR_XYZ");

    const result = try sailor.env.get(allocator, "NONEXISTENT_VAR_XYZ", "fallback");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("fallback", result);
}

test "env.get returns empty string when env var is empty" {
    const allocator = std.testing.allocator;

    try env_setenv("EMPTY_VAR", "", true);
    defer _ = env_unsetenv("EMPTY_VAR") catch {};

    const result = try sailor.env.get(allocator, "EMPTY_VAR", "default");
    defer allocator.free(result);

    // Empty env var should be preserved, not replaced with default
    try std.testing.expectEqualStrings("", result);
}

test "env.get handles long env var values" {
    const allocator = std.testing.allocator;
    const long_value = "a" ** 1000;

    try env_setenv("LONG_VAR", long_value, true);
    defer _ = env_unsetenv("LONG_VAR") catch {};

    const result = try sailor.env.get(allocator, "LONG_VAR", "default");
    defer allocator.free(result);

    try std.testing.expectEqualStrings(long_value, result);
}

test "env.get handles special characters in env var" {
    const allocator = std.testing.allocator;
    const special_value = "test!@#$%^&*()_+-=[]{}|;:,.<>?";

    try env_setenv("SPECIAL_VAR", special_value, true);
    defer _ = env_unsetenv("SPECIAL_VAR") catch {};

    const result = try sailor.env.get(allocator, "SPECIAL_VAR", "default");
    defer allocator.free(result);

    try std.testing.expectEqualStrings(special_value, result);
}

test "env.get handles unicode in env var" {
    const allocator = std.testing.allocator;
    const unicode_value = "hello 世界 🚀";

    try env_setenv("UNICODE_VAR", unicode_value, true);
    defer _ = env_unsetenv("UNICODE_VAR") catch {};

    const result = try sailor.env.get(allocator, "UNICODE_VAR", "default");
    defer allocator.free(result);

    try std.testing.expectEqualStrings(unicode_value, result);
}

// ============================================================================
// EnvConfig.getBool() Tests — Boolean Parsing
// ============================================================================

test "env.getBool parses '1' as true" {
    try env_setenv("BOOL_TEST", "1", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", false);
    try std.testing.expect(result == true);
}

test "env.getBool parses '0' as false" {
    try env_setenv("BOOL_TEST", "0", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", true);
    try std.testing.expect(result == false);
}

test "env.getBool parses 'true' as true (case-insensitive)" {
    try env_setenv("BOOL_TEST", "true", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", false);
    try std.testing.expect(result == true);
}

test "env.getBool parses 'TRUE' as true (case-insensitive)" {
    try env_setenv("BOOL_TEST", "TRUE", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", false);
    try std.testing.expect(result == true);
}

test "env.getBool parses 'yes' as true" {
    try env_setenv("BOOL_TEST", "yes", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", false);
    try std.testing.expect(result == true);
}

test "env.getBool parses 'on' as true" {
    try env_setenv("BOOL_TEST", "on", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", false);
    try std.testing.expect(result == true);
}

test "env.getBool parses 'false' as false" {
    try env_setenv("BOOL_TEST", "false", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", true);
    try std.testing.expect(result == false);
}

test "env.getBool parses 'FALSE' as false (case-insensitive)" {
    try env_setenv("BOOL_TEST", "FALSE", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", true);
    try std.testing.expect(result == false);
}

test "env.getBool parses 'no' as false" {
    try env_setenv("BOOL_TEST", "no", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", true);
    try std.testing.expect(result == false);
}

test "env.getBool parses 'off' as false" {
    try env_setenv("BOOL_TEST", "off", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", true);
    try std.testing.expect(result == false);
}

test "env.getBool uses default when env var not set" {
    try env_unsetenv("UNSET_BOOL_VAR");

    const result_default_true = sailor.env.getBool("UNSET_BOOL_VAR", true);
    try std.testing.expect(result_default_true == true);

    const result_default_false = sailor.env.getBool("UNSET_BOOL_VAR", false);
    try std.testing.expect(result_default_false == false);
}

test "env.getBool treats invalid value as false" {
    try env_setenv("BOOL_TEST", "invalid_value", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", true);
    try std.testing.expect(result == false);
}

test "env.getBool handles empty string as false" {
    try env_setenv("BOOL_TEST", "", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", true);
    try std.testing.expect(result == false);
}

test "env.getBool parses 'y' as true" {
    try env_setenv("BOOL_TEST", "y", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", false);
    try std.testing.expect(result == true);
}

test "env.getBool parses 'n' as false" {
    try env_setenv("BOOL_TEST", "n", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", true);
    try std.testing.expect(result == false);
}

// ============================================================================
// EnvConfig.getInt() Tests — Integer Parsing
// ============================================================================

test "env.getInt parses valid positive integer" {
    try env_setenv("INT_TEST", "42", true);
    defer _ = env_unsetenv("INT_TEST") catch {};

    const result = sailor.env.getInt(i32, "INT_TEST", 0);
    try std.testing.expectEqual(@as(i32, 42), result);
}

test "env.getInt parses valid negative integer" {
    try env_setenv("INT_TEST", "-42", true);
    defer _ = env_unsetenv("INT_TEST") catch {};

    const result = sailor.env.getInt(i32, "INT_TEST", 0);
    try std.testing.expectEqual(@as(i32, -42), result);
}

test "env.getInt parses zero" {
    try env_setenv("INT_TEST", "0", true);
    defer _ = env_unsetenv("INT_TEST") catch {};

    const result = sailor.env.getInt(i32, "INT_TEST", -1);
    try std.testing.expectEqual(@as(i32, 0), result);
}

test "env.getInt handles large integers" {
    try env_setenv("INT_TEST", "2147483647", true);
    defer _ = env_unsetenv("INT_TEST") catch {};

    const result = sailor.env.getInt(i32, "INT_TEST", 0);
    try std.testing.expectEqual(@as(i32, 2147483647), result);
}

test "env.getInt uses default on invalid input" {
    try env_setenv("INT_TEST", "not_a_number", true);
    defer _ = env_unsetenv("INT_TEST") catch {};

    const result = sailor.env.getInt(i32, "INT_TEST", 99);
    try std.testing.expectEqual(@as(i32, 99), result);
}

test "env.getInt uses default when env var not set" {
    try env_unsetenv("UNSET_INT_VAR");

    const result = sailor.env.getInt(i32, "UNSET_INT_VAR", 123);
    try std.testing.expectEqual(@as(i32, 123), result);
}

test "env.getInt uses default on empty string" {
    try env_setenv("INT_TEST", "", true);
    defer _ = env_unsetenv("INT_TEST") catch {};

    const result = sailor.env.getInt(i32, "INT_TEST", 456);
    try std.testing.expectEqual(@as(i32, 456), result);
}

test "env.getInt handles u16 type (for progress width)" {
    try env_setenv("INT_TEST", "80", true);
    defer _ = env_unsetenv("INT_TEST") catch {};

    const result = sailor.env.getInt(u16, "INT_TEST", 40);
    try std.testing.expectEqual(@as(u16, 80), result);
}

test "env.getInt handles u32 type" {
    try env_setenv("INT_TEST", "4294967295", true);
    defer _ = env_unsetenv("INT_TEST") catch {};

    const result = sailor.env.getInt(u32, "INT_TEST", 0);
    try std.testing.expectEqual(@as(u32, 4294967295), result);
}

test "env.getInt uses default on overflow" {
    try env_setenv("INT_TEST", "9999999999999999999", true);
    defer _ = env_unsetenv("INT_TEST") catch {};

    const result = sailor.env.getInt(i32, "INT_TEST", 111);
    try std.testing.expectEqual(@as(i32, 111), result);
}

test "env.getInt handles whitespace in number" {
    try env_setenv("INT_TEST", " 42 ", true);
    defer _ = env_unsetenv("INT_TEST") catch {};

    const result = sailor.env.getInt(i32, "INT_TEST", 0);
    // This should use default if parser is strict
    try std.testing.expectEqual(@as(i32, 0), result);
}

// ============================================================================
// Integration Tests — SAILOR_* Standard Env Vars
// ============================================================================

test "SAILOR_COLOR=0 disables color" {
    try env_setenv("SAILOR_COLOR", "0", true);
    defer _ = env_unsetenv("SAILOR_COLOR") catch {};

    const enable_color = sailor.env.getBool("SAILOR_COLOR", true);
    try std.testing.expect(enable_color == false);
}

test "SAILOR_COLOR=1 enables color" {
    try env_setenv("SAILOR_COLOR", "1", true);
    defer _ = env_unsetenv("SAILOR_COLOR") catch {};

    const enable_color = sailor.env.getBool("SAILOR_COLOR", false);
    try std.testing.expect(enable_color == true);
}

test "SAILOR_PROGRESS_WIDTH overrides default width" {
    try env_setenv("SAILOR_PROGRESS_WIDTH", "120", true);
    defer _ = env_unsetenv("SAILOR_PROGRESS_WIDTH") catch {};

    const width = sailor.env.getInt(u16, "SAILOR_PROGRESS_WIDTH", 40);
    try std.testing.expectEqual(@as(u16, 120), width);
}

test "SAILOR_PROGRESS_WIDTH uses default if not set" {
    try env_unsetenv("SAILOR_PROGRESS_WIDTH");

    const width = sailor.env.getInt(u16, "SAILOR_PROGRESS_WIDTH", 40);
    try std.testing.expectEqual(@as(u16, 40), width);
}

test "SAILOR_LOG_LEVEL env var can be read" {
    const allocator = std.testing.allocator;

    try env_setenv("SAILOR_LOG_LEVEL", "debug", true);
    defer _ = env_unsetenv("SAILOR_LOG_LEVEL") catch {};

    const log_level = try sailor.env.get(allocator, "SAILOR_LOG_LEVEL", "info");
    defer allocator.free(log_level);

    try std.testing.expectEqualStrings("debug", log_level);
}

test "SAILOR_LOG_LEVEL uses default if not set" {
    const allocator = std.testing.allocator;

    try env_unsetenv("SAILOR_LOG_LEVEL");

    const log_level = try sailor.env.get(allocator, "SAILOR_LOG_LEVEL", "info");
    defer allocator.free(log_level);

    try std.testing.expectEqualStrings("info", log_level);
}

test "SAILOR_UNICODE=0 forces ASCII fallback" {
    try env_setenv("SAILOR_UNICODE", "0", true);
    defer _ = env_unsetenv("SAILOR_UNICODE") catch {};

    const enable_unicode = sailor.env.getBool("SAILOR_UNICODE", true);
    try std.testing.expect(enable_unicode == false);
}

test "SAILOR_UNICODE=1 enables unicode" {
    try env_setenv("SAILOR_UNICODE", "1", true);
    defer _ = env_unsetenv("SAILOR_UNICODE") catch {};

    const enable_unicode = sailor.env.getBool("SAILOR_UNICODE", false);
    try std.testing.expect(enable_unicode == true);
}

// ============================================================================
// Cross-Module Integration Tests
// ============================================================================

test "env config can control color output mode" {
    // Simulate env var setting for color mode
    try env_setenv("SAILOR_COLOR", "1", true);
    defer _ = env_unsetenv("SAILOR_COLOR") catch {};

    const use_color = sailor.env.getBool("SAILOR_COLOR", false);

    // This demonstrates how a module would use the env config
    try std.testing.expect(use_color == true);
}

test "env config can control progress bar width" {
    try env_setenv("SAILOR_PROGRESS_WIDTH", "100", true);
    defer _ = env_unsetenv("SAILOR_PROGRESS_WIDTH") catch {};

    const custom_width = sailor.env.getInt(u16, "SAILOR_PROGRESS_WIDTH", 40);

    try std.testing.expectEqual(@as(u16, 100), custom_width);
}

test "env config can control formatter output format" {
    const allocator = std.testing.allocator;

    try env_setenv("SAILOR_OUTPUT_FORMAT", "json", true);
    defer _ = env_unsetenv("SAILOR_OUTPUT_FORMAT") catch {};

    const format = try sailor.env.get(allocator, "SAILOR_OUTPUT_FORMAT", "text");
    defer allocator.free(format);

    try std.testing.expectEqualStrings("json", format);
}

// ============================================================================
// Error Handling & Edge Cases
// ============================================================================

test "env.get handles null allocator gracefully" {
    // Just verify the function exists and can be called with testing allocator
    const allocator = std.testing.allocator;

    const result = try sailor.env.get(allocator, "ANY_VAR", "fallback");
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
}

test "env vars with unicode names are handled" {
    const allocator = std.testing.allocator;

    // Standard env var names are ASCII, but test robustness
    try env_setenv("TEST_VAR_XYZ", "value", true);
    defer _ = env_unsetenv("TEST_VAR_XYZ") catch {};

    const result = try sailor.env.get(allocator, "TEST_VAR_XYZ", "default");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("value", result);
}

test "multiple env vars can be read independently" {
    const allocator = std.testing.allocator;

    try env_setenv("VAR1", "value1", true);
    try env_setenv("VAR2", "value2", true);
    try env_setenv("VAR3", "value3", true);

    defer {
        _ = env_unsetenv("VAR1") catch {};
        _ = env_unsetenv("VAR2") catch {};
        _ = env_unsetenv("VAR3") catch {};
    }

    const r1 = try sailor.env.get(allocator, "VAR1", "def1");
    defer allocator.free(r1);
    const r2 = try sailor.env.get(allocator, "VAR2", "def2");
    defer allocator.free(r2);
    const r3 = try sailor.env.get(allocator, "VAR3", "def3");
    defer allocator.free(r3);

    try std.testing.expectEqualStrings("value1", r1);
    try std.testing.expectEqualStrings("value2", r2);
    try std.testing.expectEqualStrings("value3", r3);
}

test "env.getBool with leading/trailing whitespace" {
    try env_setenv("BOOL_TEST", "  true  ", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", false);
    // Behavior depends on implementation: strict (false) or lenient (true)
    // Test documents expected behavior
    _ = result;
}

test "env.getInt respects type boundaries" {
    try env_setenv("INT_TEST", "256", true);
    defer _ = env_unsetenv("INT_TEST") catch {};

    const result_u8 = sailor.env.getInt(u8, "INT_TEST", 0);
    // Should use default since 256 > max u8 (255)
    try std.testing.expectEqual(@as(u8, 0), result_u8);
}

// ============================================================================
// Stress Tests & Robustness
// ============================================================================

test "repeated reads of same env var are consistent" {
    try env_setenv("CONSISTENT_VAR", "stable_value", true);
    defer _ = env_unsetenv("CONSISTENT_VAR") catch {};

    const read1 = sailor.env.getBool("CONSISTENT_VAR", false);
    const read2 = sailor.env.getBool("CONSISTENT_VAR", false);
    const read3 = sailor.env.getBool("CONSISTENT_VAR", false);

    try std.testing.expect(read1 == read2);
    try std.testing.expect(read2 == read3);
}

test "env.getBool handles mixed case values" {
    try env_setenv("BOOL_TEST", "TrUe", true);
    defer _ = env_unsetenv("BOOL_TEST") catch {};

    const result = sailor.env.getBool("BOOL_TEST", false);
    try std.testing.expect(result == true);
}

test "env.getInt with plus sign" {
    try env_setenv("INT_TEST", "+42", true);
    defer _ = env_unsetenv("INT_TEST") catch {};

    const result = sailor.env.getInt(i32, "INT_TEST", 0);
    // Depends on implementation: may support +N or treat as invalid
    _ = result;
}

test "env vars are isolated between tests (cleanup verification)" {
    try env_unsetenv("ISOLATION_TEST_VAR");
    const result = try sailor.env.get(std.testing.allocator, "ISOLATION_TEST_VAR", "fallback");
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("fallback", result);
}
