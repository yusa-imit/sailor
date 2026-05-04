//! Input validation framework tests for sailor v2.6.0
//! Tests built-in validators, custom regex, length constraints, composition, async validation, and visual feedback
//!
//! All tests are designed to FAIL initially — they expect API that doesn't exist yet.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

// Import validation module that doesn't exist yet
const validation = sailor.validation; // WILL FAIL: module doesn't exist
const Validator = validation.Validator; // WILL FAIL
const ValidatorResult = validation.ValidatorResult; // WILL FAIL
const CombineMode = validation.CombineMode; // WILL FAIL

// ============================================================================
// Basic Validators - Email
// ============================================================================

test "email validator - valid simple email" {
    const validator = Validator.email();
    const result = validator.validateFn("user@example.com");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "email validator - valid email with subdomain" {
    const validator = Validator.email();
    const result = validator.validateFn("user@mail.example.com");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "email validator - valid email with plus sign" {
    const validator = Validator.email();
    const result = validator.validateFn("user+tag@example.com");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "email validator - invalid missing at sign" {
    const validator = Validator.email();
    const result = validator.validateFn("userexample.com");
    try testing.expect(result == .invalid);
    try testing.expect(std.mem.indexOf(u8, result.invalid, "@ sign") != null);
}

test "email validator - invalid missing domain" {
    const validator = Validator.email();
    const result = validator.validateFn("user@");
    try testing.expect(result == .invalid);
    try testing.expect(std.mem.indexOf(u8, result.invalid, "domain") != null);
}

test "email validator - invalid missing local part" {
    const validator = Validator.email();
    const result = validator.validateFn("@example.com");
    try testing.expect(result == .invalid);
}

test "email validator - invalid double at sign" {
    const validator = Validator.email();
    const result = validator.validateFn("user@@example.com");
    try testing.expect(result == .invalid);
}

test "email validator - empty string" {
    const validator = Validator.email();
    const result = validator.validateFn("");
    try testing.expect(result == .invalid);
}

// ============================================================================
// Basic Validators - URL
// ============================================================================

test "url validator - valid http url" {
    const validator = Validator.url();
    const result = validator.validateFn("http://example.com");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "url validator - valid https url" {
    const validator = Validator.url();
    const result = validator.validateFn("https://example.com/path");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "url validator - valid url with query params" {
    const validator = Validator.url();
    const result = validator.validateFn("https://example.com/path?foo=bar&baz=qux");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "url validator - invalid missing protocol" {
    const validator = Validator.url();
    const result = validator.validateFn("example.com");
    try testing.expect(result == .invalid);
    try testing.expect(std.mem.indexOf(u8, result.invalid, "protocol") != null);
}

test "url validator - invalid malformed url" {
    const validator = Validator.url();
    const result = validator.validateFn("ht!tp://exam ple.com");
    try testing.expect(result == .invalid);
}

test "url validator - empty string" {
    const validator = Validator.url();
    const result = validator.validateFn("");
    try testing.expect(result == .invalid);
}

// ============================================================================
// Basic Validators - Phone Number
// ============================================================================

test "phone validator US - valid format with dashes" {
    const validator = Validator.phoneUS();
    const result = validator.validateFn("555-123-4567");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "phone validator US - valid format with parentheses" {
    const validator = Validator.phoneUS();
    const result = validator.validateFn("(555) 123-4567");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "phone validator US - valid format digits only" {
    const validator = Validator.phoneUS();
    const result = validator.validateFn("5551234567");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "phone validator US - invalid too short" {
    const validator = Validator.phoneUS();
    const result = validator.validateFn("123-4567");
    try testing.expect(result == .invalid);
    try testing.expect(std.mem.indexOf(u8, result.invalid, "10 digits") != null);
}

test "phone validator US - invalid too long" {
    const validator = Validator.phoneUS();
    const result = validator.validateFn("1-555-123-4567");
    try testing.expect(result == .invalid);
}

test "phone validator US - invalid contains letters" {
    const validator = Validator.phoneUS();
    const result = validator.validateFn("555-ABC-DEFG");
    try testing.expect(result == .invalid);
}

// ============================================================================
// Custom Regex Validator
// ============================================================================

test "regex validator - valid pattern match" {
    const validator = try Validator.regex("^[0-9]{3}-[0-9]{2}-[0-9]{4}$"); // SSN pattern
    const result = validator.validateFn("123-45-6789");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "regex validator - invalid pattern mismatch" {
    const validator = try Validator.regex("^[0-9]{3}-[0-9]{2}-[0-9]{4}$");
    const result = validator.validateFn("123-456-789");
    try testing.expect(result == .invalid);
}

test "regex validator - empty pattern error" {
    const result = Validator.regex("");
    try testing.expectError(error.EmptyPattern, result);
}

test "regex validator - invalid regex syntax" {
    const result = Validator.regex("[unclosed");
    try testing.expectError(error.InvalidRegex, result);
}

test "regex validator - complex pattern with alternation" {
    const validator = try Validator.regex("^(foo|bar|baz)$");
    const result = validator.validateFn("bar");
    try testing.expectEqual(ValidatorResult.valid, result);
}

// ============================================================================
// Length Constraints
// ============================================================================

test "minLength validator - valid meets minimum" {
    const validator = Validator.minLength(5);
    const result = validator.validateFn("hello");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "minLength validator - valid exceeds minimum" {
    const validator = Validator.minLength(5);
    const result = validator.validateFn("hello world");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "minLength validator - invalid too short" {
    const validator = Validator.minLength(5);
    const result = validator.validateFn("hi");
    try testing.expect(result == .invalid);
    try testing.expect(std.mem.indexOf(u8, result.invalid, "5 characters") != null);
}

test "maxLength validator - valid under maximum" {
    const validator = Validator.maxLength(10);
    const result = validator.validateFn("hello");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "maxLength validator - invalid exceeds maximum" {
    const validator = Validator.maxLength(10);
    const result = validator.validateFn("hello world is too long");
    try testing.expect(result == .invalid);
    try testing.expect(std.mem.indexOf(u8, result.invalid, "10 characters") != null);
}

test "length range validator - valid within range" {
    const min_validator = Validator.minLength(5);
    const max_validator = Validator.maxLength(10);
    const validator = Validator.combine(&.{ min_validator, max_validator }, .all);
    const result = validator.validateFn("hello");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "length range validator - invalid below minimum" {
    const min_validator = Validator.minLength(5);
    const max_validator = Validator.maxLength(10);
    const validator = Validator.combine(&.{ min_validator, max_validator }, .all);
    const result = validator.validateFn("hi");
    try testing.expect(result == .invalid);
}

test "length range validator - invalid above maximum" {
    const min_validator = Validator.minLength(5);
    const max_validator = Validator.maxLength(10);
    const validator = Validator.combine(&.{ min_validator, max_validator }, .all);
    const result = validator.validateFn("this is way too long");
    try testing.expect(result == .invalid);
}

// ============================================================================
// Validator Composition - AND Logic
// ============================================================================

test "combine validators AND mode - all pass" {
    const email_validator = Validator.email();
    const min_validator = Validator.minLength(5);
    const validator = Validator.combine(&.{ email_validator, min_validator }, .all);
    const result = validator.validateFn("user@example.com");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "combine validators AND mode - one fails" {
    const email_validator = Validator.email();
    const min_validator = Validator.minLength(20); // Too long for typical email
    const validator = Validator.combine(&.{ email_validator, min_validator }, .all);
    const result = validator.validateFn("a@b.c"); // Valid email but too short
    try testing.expect(result == .invalid);
}

test "combine validators AND mode - all fail" {
    const email_validator = Validator.email();
    const min_validator = Validator.minLength(20);
    const validator = Validator.combine(&.{ email_validator, min_validator }, .all);
    const result = validator.validateFn("not-an-email");
    try testing.expect(result == .invalid);
}

// ============================================================================
// Validator Composition - OR Logic
// ============================================================================

test "combine validators OR mode - first passes" {
    const email_validator = Validator.email();
    const url_validator = Validator.url();
    const validator = Validator.combine(&.{ email_validator, url_validator }, .any);
    const result = validator.validateFn("user@example.com");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "combine validators OR mode - second passes" {
    const email_validator = Validator.email();
    const url_validator = Validator.url();
    const validator = Validator.combine(&.{ email_validator, url_validator }, .any);
    const result = validator.validateFn("https://example.com");
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "combine validators OR mode - all fail" {
    const email_validator = Validator.email();
    const url_validator = Validator.url();
    const validator = Validator.combine(&.{ email_validator, url_validator }, .any);
    const result = validator.validateFn("not-email-or-url");
    try testing.expect(result == .invalid);
}

// ============================================================================
// Async Validation - Debounced
// ============================================================================

test "async validator - debounced validation" {
    const allocator = testing.allocator;
    var async_validator = try validation.AsyncValidator.init(allocator, Validator.email(), 100); // 100ms debounce
    defer async_validator.deinit();

    // Queue multiple validations rapidly
    try async_validator.queueValidation("user@");
    try async_validator.queueValidation("user@example");
    try async_validator.queueValidation("user@example.com");

    // Only the last one should be validated after debounce period
    std.Thread.sleep(150 * std.time.ns_per_ms);

    const result = try async_validator.getResult();
    try testing.expectEqual(ValidatorResult.valid, result);
}

test "async validator - pending state" {
    const allocator = testing.allocator;
    var async_validator = try validation.AsyncValidator.init(allocator, Validator.email(), 100);
    defer async_validator.deinit();

    try async_validator.queueValidation("user@example.com");

    // Should be pending immediately after queueing
    const result = async_validator.getResultNonBlocking();
    try testing.expectEqual(ValidatorResult.pending, result);
}

test "async validator - timeout handling" {
    const allocator = testing.allocator;

    // Create validator with very slow validation function
    const slow_validator = Validator{
        .validateFn = struct {
            fn validate(_: []const u8) ValidatorResult {
                std.Thread.sleep(500 * std.time.ns_per_ms); // 500ms delay
                return .valid;
            }
        }.validate,
    };

    var async_validator = try validation.AsyncValidator.init(allocator, slow_validator, 50);
    defer async_validator.deinit();

    try async_validator.queueValidation("test");

    // Should timeout before validation completes
    const result = async_validator.getResultWithTimeout(100); // 100ms timeout
    try testing.expectError(error.ValidationTimeout, result);
}

// ============================================================================
// Visual Feedback - Style Application
// ============================================================================

test "visual feedback - error style application" {
    const allocator = testing.allocator;
    const validator = Validator.email();
    const feedback = try validation.VisualFeedback.init(allocator, validator);
    defer feedback.deinit();

    const result = try feedback.validateWithStyle("invalid-email");

    try testing.expect(result.is_valid == false);
    try testing.expect(result.style.fg != null);
    try testing.expectEqual(sailor.tui.Color.red, result.style.fg.?);
}

test "visual feedback - success style application" {
    const allocator = testing.allocator;
    const validator = Validator.email();
    const feedback = try validation.VisualFeedback.init(allocator, validator);
    defer feedback.deinit();

    const result = try feedback.validateWithStyle("user@example.com");

    try testing.expect(result.is_valid == true);
    try testing.expect(result.style.fg != null);
    try testing.expectEqual(sailor.tui.Color.green, result.style.fg.?);
}

test "visual feedback - pending style application" {
    const allocator = testing.allocator;
    const slow_validator = Validator{
        .validateFn = struct {
            fn validate(_: []const u8) ValidatorResult {
                return .pending;
            }
        }.validate,
    };
    const feedback = try validation.VisualFeedback.init(allocator, slow_validator);
    defer feedback.deinit();

    const result = try feedback.validateWithStyle("anything");

    try testing.expect(result.is_valid == null); // Neither valid nor invalid
    try testing.expect(result.style.fg != null);
    try testing.expectEqual(sailor.tui.Color.yellow, result.style.fg.?);
}

test "visual feedback - custom error style" {
    const allocator = testing.allocator;
    const validator = Validator.email();
    var feedback = try validation.VisualFeedback.init(allocator, validator);
    defer feedback.deinit();

    // Set custom error style
    const custom_style = sailor.tui.Style{
        .fg = sailor.tui.Color.magenta,
        .bg = sailor.tui.Color.black,
        .bold = true,
    };
    feedback.setErrorStyle(custom_style);

    const result = try feedback.validateWithStyle("invalid");

    try testing.expectEqual(custom_style.fg.?, result.style.fg.?);
    try testing.expectEqual(custom_style.bg.?, result.style.bg.?);
    try testing.expect(result.style.bold == true);
}

test "visual feedback - custom success style" {
    const allocator = testing.allocator;
    const validator = Validator.email();
    var feedback = try validation.VisualFeedback.init(allocator, validator);
    defer feedback.deinit();

    // Set custom success style
    const custom_style = sailor.tui.Style{
        .fg = sailor.tui.Color.cyan,
        .italic = true,
    };
    feedback.setSuccessStyle(custom_style);

    const result = try feedback.validateWithStyle("user@example.com");

    try testing.expectEqual(custom_style.fg.?, result.style.fg.?);
    try testing.expect(result.style.italic == true);
}

// ============================================================================
// Edge Cases & Error Handling
// ============================================================================

test "validator - null byte in input" {
    const validator = Validator.email();
    const input = "user\x00@example.com";
    const result = validator.validateFn(input);
    try testing.expect(result == .invalid);
}

test "validator - unicode email address" {
    const validator = Validator.email();
    const result = validator.validateFn("user@例え.jp");
    try testing.expectEqual(ValidatorResult.valid, result); // Should support IDN
}

test "validator - very long input" {
    const allocator = testing.allocator;
    const long_input = try allocator.alloc(u8, 10000);
    defer allocator.free(long_input);
    @memset(long_input, 'a');

    const validator = Validator.maxLength(100);
    const result = validator.validateFn(long_input);
    try testing.expect(result == .invalid);
}

test "combine validators - empty validator array" {
    const result = Validator.combine(&.{}, .all);
    // Should return validator that always passes for empty array
    const validation_result = result.validateFn("anything");
    try testing.expectEqual(ValidatorResult.valid, validation_result);
}
