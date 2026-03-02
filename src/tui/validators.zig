const std = @import("std");

/// Validation result
pub const ValidationResult = union(enum) {
    valid,
    invalid: []const u8, // error message

    pub fn isValid(self: ValidationResult) bool {
        return self == .valid;
    }
};

/// Validator function type
pub const Validator = *const fn (value: []const u8) ValidationResult;

// Basic validators

/// Validates that field is not empty
pub fn notEmpty(value: []const u8) ValidationResult {
    if (value.len == 0) {
        return .{ .invalid = "This field is required" };
    }
    return .valid;
}

/// Validates minimum length
pub fn minLength(comptime min: usize) Validator {
    const validators = struct {
        fn check(value: []const u8) ValidationResult {
            if (value.len < min) {
                return .{ .invalid = "Too short" };
            }
            return .valid;
        }
    };
    return validators.check;
}

/// Validates maximum length
pub fn maxLength(comptime max: usize) Validator {
    const validators = struct {
        fn check(value: []const u8) ValidationResult {
            if (value.len > max) {
                return .{ .invalid = "Too long" };
            }
            return .valid;
        }
    };
    return validators.check;
}

/// Validates exact length
pub fn exactLength(comptime len: usize) Validator {
    const validators = struct {
        fn check(value: []const u8) ValidationResult {
            if (value.len != len) {
                return .{ .invalid = "Invalid length" };
            }
            return .valid;
        }
    };
    return validators.check;
}

// Numeric validators

/// Validates that value contains only digits
pub fn numeric(value: []const u8) ValidationResult {
    if (value.len == 0) {
        return .{ .invalid = "Number is required" };
    }

    for (value) |ch| {
        if (ch < '0' or ch > '9') {
            return .{ .invalid = "Must be a number" };
        }
    }

    return .valid;
}

/// Validates integer (allows negative sign)
pub fn integer(value: []const u8) ValidationResult {
    if (value.len == 0) {
        return .{ .invalid = "Integer is required" };
    }

    for (value, 0..) |ch, i| {
        if (i == 0 and ch == '-') continue; // Allow leading minus
        if (ch < '0' or ch > '9') {
            return .{ .invalid = "Must be an integer" };
        }
    }

    return .valid;
}

/// Validates decimal number (allows decimal point)
pub fn decimal(value: []const u8) ValidationResult {
    if (value.len == 0) {
        return .{ .invalid = "Number is required" };
    }

    var has_dot = false;
    for (value, 0..) |ch, i| {
        if (i == 0 and ch == '-') continue; // Allow leading minus
        if (ch == '.') {
            if (has_dot) {
                return .{ .invalid = "Multiple decimal points" };
            }
            has_dot = true;
            continue;
        }
        if (ch < '0' or ch > '9') {
            return .{ .invalid = "Must be a number" };
        }
    }

    return .valid;
}

/// Validates minimum numeric value
pub fn minValue(comptime min: i64) Validator {
    const validators = struct {
        fn check(value: []const u8) ValidationResult {
            const num = std.fmt.parseInt(i64, value, 10) catch {
                return .{ .invalid = "Invalid number" };
            };
            if (num < min) {
                return .{ .invalid = "Value too small" };
            }
            return .valid;
        }
    };
    return validators.check;
}

/// Validates maximum numeric value
pub fn maxValue(comptime max: i64) Validator {
    const validators = struct {
        fn check(value: []const u8) ValidationResult {
            const num = std.fmt.parseInt(i64, value, 10) catch {
                return .{ .invalid = "Invalid number" };
            };
            if (num > max) {
                return .{ .invalid = "Value too large" };
            }
            return .valid;
        }
    };
    return validators.check;
}

// Pattern validators

/// Validates email format (basic check)
pub fn email(value: []const u8) ValidationResult {
    if (value.len == 0) {
        return .{ .invalid = "Email is required" };
    }

    var has_at = false;
    var has_dot_after_at = false;
    var at_pos: usize = 0;

    for (value, 0..) |ch, i| {
        if (ch == '@') {
            if (has_at) {
                return .{ .invalid = "Multiple @ symbols" };
            }
            if (i == 0) {
                return .{ .invalid = "Email cannot start with @" };
            }
            has_at = true;
            at_pos = i;
        } else if (has_at and ch == '.') {
            if (i > at_pos + 1) {
                has_dot_after_at = true;
            }
        }
    }

    if (!has_at) {
        return .{ .invalid = "Email must contain @" };
    }
    if (!has_dot_after_at) {
        return .{ .invalid = "Email must contain domain" };
    }
    if (value[value.len - 1] == '.') {
        return .{ .invalid = "Email cannot end with ." };
    }

    return .valid;
}

/// Validates URL format (basic check)
pub fn url(value: []const u8) ValidationResult {
    if (value.len == 0) {
        return .{ .invalid = "URL is required" };
    }

    if (std.mem.startsWith(u8, value, "http://") or
        std.mem.startsWith(u8, value, "https://") or
        std.mem.startsWith(u8, value, "ftp://"))
    {
        return .valid;
    }

    return .{ .invalid = "URL must start with http://, https://, or ftp://" };
}

/// Validates IPv4 address
pub fn ipv4(value: []const u8) ValidationResult {
    if (value.len == 0) {
        return .{ .invalid = "IP address is required" };
    }

    var parts: usize = 0;
    var current_num: []const u8 = "";
    var start: usize = 0;

    for (value, 0..) |ch, i| {
        if (ch == '.') {
            parts += 1;
            if (i == start) {
                return .{ .invalid = "Empty octet" };
            }
            current_num = value[start..i];
            const num = std.fmt.parseInt(u8, current_num, 10) catch {
                return .{ .invalid = "Invalid octet" };
            };
            _ = num; // Valid octet (0-255)
            start = i + 1;
        } else if (ch < '0' or ch > '9') {
            return .{ .invalid = "Invalid character in IP" };
        }
    }

    // Check last octet
    if (start >= value.len) {
        return .{ .invalid = "IP cannot end with ." };
    }
    current_num = value[start..];
    _ = std.fmt.parseInt(u8, current_num, 10) catch {
        return .{ .invalid = "Invalid octet" };
    };

    if (parts != 3) {
        return .{ .invalid = "IP must have 4 octets" };
    }

    return .valid;
}

/// Validates hexadecimal string
pub fn hexadecimal(value: []const u8) ValidationResult {
    if (value.len == 0) {
        return .{ .invalid = "Hex value is required" };
    }

    for (value) |ch| {
        if (!((ch >= '0' and ch <= '9') or
            (ch >= 'a' and ch <= 'f') or
            (ch >= 'A' and ch <= 'F')))
        {
            return .{ .invalid = "Must be hexadecimal (0-9, A-F)" };
        }
    }

    return .valid;
}

/// Validates alphanumeric characters only
pub fn alphanumeric(value: []const u8) ValidationResult {
    if (value.len == 0) {
        return .{ .invalid = "Value is required" };
    }

    for (value) |ch| {
        if (!((ch >= 'a' and ch <= 'z') or
            (ch >= 'A' and ch <= 'Z') or
            (ch >= '0' and ch <= '9')))
        {
            return .{ .invalid = "Only letters and numbers allowed" };
        }
    }

    return .valid;
}

/// Validates alphabetic characters only
pub fn alphabetic(value: []const u8) ValidationResult {
    if (value.len == 0) {
        return .{ .invalid = "Value is required" };
    }

    for (value) |ch| {
        if (!((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z'))) {
            return .{ .invalid = "Only letters allowed" };
        }
    }

    return .valid;
}

// Input masks

/// Input mask configuration
pub const Mask = struct {
    pattern: []const u8, // e.g., "###-##-####" for SSN
    placeholder: u8 = '_', // Character shown for unfilled positions

    /// Apply mask to raw input, returns formatted string
    pub fn apply(self: Mask, allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
        var result = std.ArrayList(u8){};
        errdefer result.deinit(allocator);

        var input_idx: usize = 0;

        for (self.pattern) |ch| {
            if (ch == '#') {
                // Digit placeholder
                if (input_idx < input.len) {
                    try result.append(allocator, input[input_idx]);
                    input_idx += 1;
                } else {
                    try result.append(allocator, self.placeholder);
                }
            } else {
                // Literal character
                try result.append(allocator, ch);
            }
        }

        return result.toOwnedSlice(allocator);
    }

    /// Remove mask from formatted input, returns raw digits
    pub fn remove(self: Mask, allocator: std.mem.Allocator, formatted: []const u8) ![]const u8 {
        var result = std.ArrayList(u8){};
        errdefer result.deinit(allocator);

        for (formatted, 0..) |ch, i| {
            if (i < self.pattern.len and self.pattern[i] == '#') {
                if (ch != self.placeholder) {
                    try result.append(allocator, ch);
                }
            }
        }

        return result.toOwnedSlice(allocator);
    }

    /// Common mask patterns
    pub const ssn = Mask{ .pattern = "###-##-####" }; // US Social Security Number
    pub const phone_us = Mask{ .pattern = "(###) ###-####" }; // US Phone number
    pub const date_us = Mask{ .pattern = "##/##/####" }; // MM/DD/YYYY
    pub const date_iso = Mask{ .pattern = "####-##-##" }; // YYYY-MM-DD
    pub const time_24h = Mask{ .pattern = "##:##" }; // HH:MM
    pub const credit_card = Mask{ .pattern = "#### #### #### ####" }; // Credit card
    pub const zip_us = Mask{ .pattern = "#####" }; // US ZIP code
    pub const zip_plus4 = Mask{ .pattern = "#####-####" }; // US ZIP+4
};

// Tests

test "notEmpty" {
    try std.testing.expect(!notEmpty("").isValid());
    try std.testing.expect(notEmpty("hello").isValid());
}

test "minLength" {
    const validate = minLength(5);
    try std.testing.expect(!validate("hi").isValid());
    try std.testing.expect(validate("hello").isValid());
}

test "maxLength" {
    const validate = maxLength(3);
    try std.testing.expect(validate("hi").isValid());
    try std.testing.expect(!validate("hello").isValid());
}

test "exactLength" {
    const validate = exactLength(3);
    try std.testing.expect(!validate("hi").isValid());
    try std.testing.expect(validate("abc").isValid());
    try std.testing.expect(!validate("abcd").isValid());
}

test "numeric" {
    try std.testing.expect(!numeric("").isValid());
    try std.testing.expect(!numeric("abc").isValid());
    try std.testing.expect(numeric("123").isValid());
    try std.testing.expect(!numeric("12.34").isValid());
}

test "integer" {
    try std.testing.expect(!integer("").isValid());
    try std.testing.expect(!integer("abc").isValid());
    try std.testing.expect(integer("123").isValid());
    try std.testing.expect(integer("-456").isValid());
    try std.testing.expect(!integer("12.34").isValid());
}

test "decimal" {
    try std.testing.expect(!decimal("").isValid());
    try std.testing.expect(!decimal("abc").isValid());
    try std.testing.expect(decimal("123").isValid());
    try std.testing.expect(decimal("-456").isValid());
    try std.testing.expect(decimal("12.34").isValid());
    try std.testing.expect(!decimal("12.34.56").isValid());
}

test "minValue" {
    const validate = minValue(10);
    try std.testing.expect(!validate("5").isValid());
    try std.testing.expect(validate("10").isValid());
    try std.testing.expect(validate("15").isValid());
}

test "maxValue" {
    const validate = maxValue(100);
    try std.testing.expect(validate("50").isValid());
    try std.testing.expect(validate("100").isValid());
    try std.testing.expect(!validate("150").isValid());
}

test "email" {
    try std.testing.expect(!email("").isValid());
    try std.testing.expect(!email("invalid").isValid());
    try std.testing.expect(!email("no-domain@").isValid());
    try std.testing.expect(!email("@example.com").isValid());
    try std.testing.expect(!email("user@example.").isValid());
    try std.testing.expect(email("user@example.com").isValid());
}

test "url" {
    try std.testing.expect(!url("").isValid());
    try std.testing.expect(!url("example.com").isValid());
    try std.testing.expect(url("http://example.com").isValid());
    try std.testing.expect(url("https://example.com").isValid());
    try std.testing.expect(url("ftp://ftp.example.com").isValid());
}

test "ipv4" {
    try std.testing.expect(!ipv4("").isValid());
    try std.testing.expect(!ipv4("192.168.1").isValid());
    try std.testing.expect(!ipv4("192.168.1.1.1").isValid());
    try std.testing.expect(!ipv4("192.168.1.").isValid());
    try std.testing.expect(!ipv4("256.0.0.1").isValid());
    try std.testing.expect(ipv4("192.168.1.1").isValid());
    try std.testing.expect(ipv4("0.0.0.0").isValid());
    try std.testing.expect(ipv4("255.255.255.255").isValid());
}

test "hexadecimal" {
    try std.testing.expect(!hexadecimal("").isValid());
    try std.testing.expect(!hexadecimal("xyz").isValid());
    try std.testing.expect(hexadecimal("0123456789").isValid());
    try std.testing.expect(hexadecimal("ABCDEF").isValid());
    try std.testing.expect(hexadecimal("abcdef").isValid());
    try std.testing.expect(hexadecimal("DeadBeef").isValid());
}

test "alphanumeric" {
    try std.testing.expect(!alphanumeric("").isValid());
    try std.testing.expect(!alphanumeric("hello-world").isValid());
    try std.testing.expect(alphanumeric("Hello123").isValid());
}

test "alphabetic" {
    try std.testing.expect(!alphabetic("").isValid());
    try std.testing.expect(!alphabetic("hello123").isValid());
    try std.testing.expect(alphabetic("Hello").isValid());
}

test "Mask: apply SSN" {
    const mask = Mask.ssn;
    const result = try mask.apply(std.testing.allocator, "123456789");
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("123-45-6789", result);
}

test "Mask: apply phone" {
    const mask = Mask.phone_us;
    const result = try mask.apply(std.testing.allocator, "5551234567");
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("(555) 123-4567", result);
}

test "Mask: apply partial" {
    const mask = Mask.phone_us;
    const result = try mask.apply(std.testing.allocator, "555");
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("(555) ___-____", result);
}

test "Mask: remove" {
    const mask = Mask.ssn;
    const result = try mask.remove(std.testing.allocator, "123-45-6789");
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("123456789", result);
}

test "Mask: remove partial" {
    const mask = Mask.phone_us;
    const result = try mask.remove(std.testing.allocator, "(555) ___-____");
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("555", result);
}
