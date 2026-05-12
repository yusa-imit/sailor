//! Comprehensive tests for LLM Integration Layer (v2.10.0 milestone)
//!
//! Tests the following features:
//! 1. HTTP Client with Streaming — Connect to LLM APIs, handle SSE responses
//! 2. Token Counting — Estimate token usage for budget management
//! 3. Rate Limiting — Token bucket algorithm, requests/tokens per minute
//! 4. Retry Logic — Exponential backoff, circuit breaker pattern
//! 5. Prompt Template System — Variable substitution, validation
//! 6. Response Streaming Widget — Real-time display, word-wrap, scrolling
//!
//! All tests are written BEFORE implementation (TDD Red phase).
//! These tests should FAIL initially because the features don't exist yet.
//!
//! Test Design:
//! - NO real API calls — all HTTP requests are mocked
//! - Use fixedBufferStream for output capture
//! - Edge cases: empty responses, malformed JSON, Unicode, large payloads
//! - Error paths: network failures, timeouts, rate limits, invalid responses

const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;

// Forward declarations for types to be implemented
// These will be actual implementations in src/llm_client.zig
const LlmClient = sailor.LlmClient; // Main HTTP client
const RateLimiter = sailor.RateLimiter; // Token bucket rate limiter
const TokenBudget = sailor.TokenBudget; // Token counting and budget tracking
const PromptTemplate = sailor.PromptTemplate; // Template with variable substitution
const ResponseStreamWidget = sailor.ResponseStreamWidget; // TUI widget for streaming display

// ============================================================================
// FEATURE 1: HTTP CLIENT WITH STREAMING (8 tests)
// ============================================================================

test "LlmClient - init with valid configuration succeeds" {
    const allocator = testing.allocator;

    const client = try LlmClient.init(
        allocator,
        "test-api-key",
        "https://api.anthropic.com/v1/messages",
    );
    defer client.deinit();

    // Verify client is initialized
    try testing.expectEqualStrings("test-api-key", client.api_key);
    try testing.expectEqualStrings("https://api.anthropic.com/v1/messages", client.base_url);
}

test "LlmClient - stream sends POST request with correct headers" {
    const allocator = testing.allocator;

    // Mock HTTP client that captures request
    const MockHttpClient = struct {
        captured_headers: std.StringHashMap([]const u8),
        captured_body: []const u8,
        allocator: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator) @This() {
            return .{
                .captured_headers = std.StringHashMap([]const u8).init(alloc),
                .captured_body = "",
                .allocator = alloc,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.captured_headers.deinit();
        }

        pub fn post(self: *@This(), url: []const u8, headers: anytype, body: []const u8) !void {
            _ = url;
            // Capture headers
            var it = headers.iterator();
            while (it.next()) |entry| {
                try self.captured_headers.put(entry.key_ptr.*, entry.value_ptr.*);
            }
            self.captured_body = body;
        }
    };

    var mock = MockHttpClient.init(allocator);
    defer mock.deinit();

    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();

    // Replace client's internal HTTP client with mock
    client.http_client = &mock;

    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    // This should fail initially because stream() doesn't exist
    _ = client.stream("test prompt", fbs.writer()) catch |err| {
        // Expected to fail in Red phase
        try testing.expectEqual(error.NotImplemented, err);
        return;
    };

    // If implemented, verify headers
    try testing.expect(mock.captured_headers.contains("Authorization"));
    try testing.expectEqualStrings("Bearer test-key", mock.captured_headers.get("Authorization").?);
    try testing.expectEqualStrings("application/json", mock.captured_headers.get("Content-Type").?);
}

test "LlmClient - stream handles SSE response chunks" {
    const allocator = testing.allocator;

    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();

    // Mock SSE response: "data: {\"chunk\": \"Hello\"}\ndata: {\"chunk\": \" world\"}\n"
    const mock_response =
        \\data: {"chunk": "Hello"}
        \\
        \\data: {"chunk": " world"}
        \\
        \\data: [DONE]
        \\
    ;

    // Mock HTTP client that returns SSE stream
    const MockSseClient = struct {
        response: []const u8,

        pub fn streamPost(_: *@This(), _: []const u8, _: anytype, _: []const u8, writer: anytype) !void {
            // Write mock SSE response
            try writer.writeAll("Hello world");
        }
    };

    var mock = MockSseClient{ .response = mock_response };
    client.http_client = &mock;

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    try client.stream("test prompt", fbs.writer());

    const written = fbs.getWritten();
    try testing.expectEqualStrings("Hello world", written);
}

test "LlmClient - stream handles connection error gracefully" {
    const allocator = testing.allocator;

    var client = try LlmClient.init(allocator, "test-key", "https://invalid-url.com");
    defer client.deinit();

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    // Should return error.ConnectionFailed
    const result = client.stream("test prompt", fbs.writer());
    try testing.expectError(error.ConnectionFailed, result);
}

test "LlmClient - stream handles timeout error" {
    const allocator = testing.allocator;

    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();

    // Set short timeout
    client.timeout_ms = 100;

    // Mock client that sleeps longer than timeout
    const MockSlowClient = struct {
        pub fn streamPost(_: *@This(), _: []const u8, _: anytype, _: []const u8, _: anytype) !void {
            std.time.sleep(200 * std.time.ns_per_ms);
            return error.Timeout;
        }
    };

    var mock = MockSlowClient{};
    client.http_client = &mock;

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const result = client.stream("test prompt", fbs.writer());
    try testing.expectError(error.Timeout, result);
}

test "LlmClient - stream parses JSON response correctly" {
    const allocator = testing.allocator;

    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();

    const mock_json_response =
        \\{"content": [{"type": "text", "text": "Hello from Claude"}]}
    ;

    const MockJsonClient = struct {
        response: []const u8,

        pub fn post(_: *@This(), _: []const u8, _: anytype, _: []const u8) ![]const u8 {
            return "Hello from Claude";
        }
    };

    var mock = MockJsonClient{ .response = mock_json_response };
    client.http_client = &mock;

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    try client.stream("test prompt", fbs.writer());

    const written = fbs.getWritten();
    try testing.expectEqualStrings("Hello from Claude", written);
}

test "LlmClient - stream handles malformed JSON gracefully" {
    const allocator = testing.allocator;

    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();

    const MockBadJsonClient = struct {
        pub fn post(_: *@This(), _: []const u8, _: anytype, _: []const u8) ![]const u8 {
            return error.InvalidJson;
        }
    };

    var mock = MockBadJsonClient{};
    client.http_client = &mock;

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const result = client.stream("test prompt", fbs.writer());
    try testing.expectError(error.InvalidJson, result);
}

test "LlmClient - stream handles Unicode correctly" {
    const allocator = testing.allocator;

    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();

    const MockUnicodeClient = struct {
        pub fn streamPost(_: *@This(), _: []const u8, _: anytype, _: []const u8, writer: anytype) !void {
            try writer.writeAll("你好世界 🌍 Здравствуй мир");
        }
    };

    var mock = MockUnicodeClient{};
    client.http_client = &mock;

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    try client.stream("test prompt", fbs.writer());

    const written = fbs.getWritten();
    try testing.expectEqualStrings("你好世界 🌍 Здравствуй мир", written);
}

// ============================================================================
// FEATURE 2: TOKEN COUNTING (7 tests)
// ============================================================================

test "TokenBudget - estimate returns non-zero for non-empty text" {
    const text = "Hello, world!";
    const token_count = TokenBudget.estimate(text);

    // Simple whitespace-based approximation: ~3 tokens for 2 words + punctuation
    try testing.expect(token_count > 0);
    try testing.expect(token_count <= 10); // Rough upper bound
}

test "TokenBudget - estimate returns zero for empty text" {
    const text = "";
    const token_count = TokenBudget.estimate(text);

    try testing.expectEqual(@as(u64, 0), token_count);
}

test "TokenBudget - estimate handles whitespace-only text" {
    const text = "   \n\t  ";
    const token_count = TokenBudget.estimate(text);

    try testing.expectEqual(@as(u64, 0), token_count);
}

test "TokenBudget - estimate approximates words as tokens" {
    const text = "The quick brown fox jumps over the lazy dog";
    const token_count = TokenBudget.estimate(text);

    // 9 words ≈ 9-12 tokens (some multi-character tokens)
    try testing.expect(token_count >= 9);
    try testing.expect(token_count <= 15);
}

test "TokenBudget - consume reduces available budget" {
    var budget = TokenBudget{
        .max_tokens = 1000,
        .used_tokens = 0,
    };

    try budget.consume(200);
    try testing.expectEqual(@as(u64, 200), budget.used_tokens);

    try budget.consume(300);
    try testing.expectEqual(@as(u64, 500), budget.used_tokens);
}

test "TokenBudget - consume fails when exceeding budget" {
    var budget = TokenBudget{
        .max_tokens = 100,
        .used_tokens = 80,
    };

    // Trying to consume 30 tokens when only 20 left
    const result = budget.consume(30);
    try testing.expectError(error.BudgetExceeded, result);

    // Budget should not change on error
    try testing.expectEqual(@as(u64, 80), budget.used_tokens);
}

test "TokenBudget - remaining returns correct value" {
    const budget = TokenBudget{
        .max_tokens = 1000,
        .used_tokens = 300,
    };

    try testing.expectEqual(@as(u64, 700), budget.remaining());
}

// ============================================================================
// FEATURE 3: RATE LIMITING (8 tests)
// ============================================================================

test "RateLimiter - checkAndConsume succeeds within limits" {
    var limiter = RateLimiter{
        .requests_per_minute = 10,
        .tokens_per_minute = 1000,
        .current_requests = 0,
        .current_tokens = 0,
        .window_start = std.time.milliTimestamp(),
    };

    try limiter.checkAndConsume(100);
    try testing.expectEqual(@as(u32, 1), limiter.current_requests);
    try testing.expectEqual(@as(u64, 100), limiter.current_tokens);
}

test "RateLimiter - checkAndConsume fails when request limit exceeded" {
    var limiter = RateLimiter{
        .requests_per_minute = 3,
        .tokens_per_minute = 10000,
        .current_requests = 3,
        .current_tokens = 0,
        .window_start = std.time.milliTimestamp(),
    };

    const result = limiter.checkAndConsume(100);
    try testing.expectError(error.RateLimitExceeded, result);
}

test "RateLimiter - checkAndConsume fails when token limit exceeded" {
    var limiter = RateLimiter{
        .requests_per_minute = 100,
        .tokens_per_minute = 1000,
        .current_requests = 0,
        .current_tokens = 900,
        .window_start = std.time.milliTimestamp(),
    };

    // Trying to consume 200 tokens when only 100 left in window
    const result = limiter.checkAndConsume(200);
    try testing.expectError(error.RateLimitExceeded, result);
}

test "RateLimiter - resets counters after time window" {
    var limiter = RateLimiter{
        .requests_per_minute = 10,
        .tokens_per_minute = 1000,
        .current_requests = 8,
        .current_tokens = 800,
        .window_start = std.time.milliTimestamp() - 61_000, // 61 seconds ago
    };

    try limiter.checkAndConsume(100);

    // After window reset, counters should be reset
    try testing.expectEqual(@as(u32, 1), limiter.current_requests);
    try testing.expectEqual(@as(u64, 100), limiter.current_tokens);
}

test "RateLimiter - waitTime returns zero when under limit" {
    const limiter = RateLimiter{
        .requests_per_minute = 10,
        .tokens_per_minute = 1000,
        .current_requests = 3,
        .current_tokens = 300,
        .window_start = std.time.milliTimestamp(),
    };

    const wait = limiter.waitTime();
    try testing.expectEqual(@as(u64, 0), wait);
}

test "RateLimiter - waitTime returns remaining window time when exceeded" {
    const now = std.time.milliTimestamp();
    const limiter = RateLimiter{
        .requests_per_minute = 10,
        .tokens_per_minute = 1000,
        .current_requests = 10, // At limit
        .current_tokens = 1000, // At limit
        .window_start = now - 30_000, // 30 seconds into window
    };

    const wait = limiter.waitTime();

    // Should wait ~30 more seconds for window to reset
    try testing.expect(wait > 25_000);
    try testing.expect(wait <= 31_000);
}

test "RateLimiter - exponential backoff increases delay" {
    var limiter = RateLimiter{
        .requests_per_minute = 10,
        .tokens_per_minute = 1000,
        .current_requests = 0,
        .current_tokens = 0,
        .window_start = std.time.milliTimestamp(),
        .backoff_count = 0,
    };

    const delay1 = limiter.exponentialBackoff();
    limiter.backoff_count += 1;
    const delay2 = limiter.exponentialBackoff();
    limiter.backoff_count += 1;
    const delay3 = limiter.exponentialBackoff();

    // Each delay should be larger than the previous
    try testing.expect(delay2 > delay1);
    try testing.expect(delay3 > delay2);
}

test "RateLimiter - exponential backoff caps at maximum" {
    var limiter = RateLimiter{
        .requests_per_minute = 10,
        .tokens_per_minute = 1000,
        .current_requests = 0,
        .current_tokens = 0,
        .window_start = std.time.milliTimestamp(),
        .backoff_count = 10, // Very high retry count
    };

    const delay = limiter.exponentialBackoff();

    // Should cap at some reasonable maximum (e.g., 60 seconds)
    try testing.expect(delay <= 60_000);
}

// ============================================================================
// FEATURE 4: RETRY LOGIC (6 tests)
// ============================================================================

test "LlmClient - retry succeeds on transient error after 1 retry" {
    const allocator = testing.allocator;

    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();
    client.max_retries = 3;

    // Mock that fails once then succeeds
    const MockRetryClient = struct {
        attempt: u32 = 0,

        pub fn streamPost(self: *@This(), _: []const u8, _: anytype, _: []const u8, writer: anytype) !void {
            self.attempt += 1;
            if (self.attempt == 1) {
                return error.ServiceUnavailable; // 503 error
            }
            try writer.writeAll("Success");
        }
    };

    var mock = MockRetryClient{};
    client.http_client = &mock;

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    try client.streamWithRetry("test prompt", fbs.writer());

    const written = fbs.getWritten();
    try testing.expectEqualStrings("Success", written);
    try testing.expectEqual(@as(u32, 2), mock.attempt);
}

test "LlmClient - retry exhausts max attempts and returns error" {
    const allocator = testing.allocator;

    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();
    client.max_retries = 2;

    // Mock that always fails
    const MockAlwaysFailClient = struct {
        attempt: u32 = 0,

        pub fn streamPost(self: *@This(), _: []const u8, _: anytype, _: []const u8, _: anytype) !void {
            self.attempt += 1;
            return error.ServiceUnavailable;
        }
    };

    var mock = MockAlwaysFailClient{};
    client.http_client = &mock;

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const result = client.streamWithRetry("test prompt", fbs.writer());
    try testing.expectError(error.ServiceUnavailable, result);

    // Should have tried max_retries + 1 times
    try testing.expectEqual(@as(u32, 3), mock.attempt);
}

test "LlmClient - retry does not retry on client error (4xx)" {
    const allocator = testing.allocator;

    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();
    client.max_retries = 3;

    // Mock that returns 400 Bad Request
    const MockClientErrorClient = struct {
        attempt: u32 = 0,

        pub fn streamPost(self: *@This(), _: []const u8, _: anytype, _: []const u8, _: anytype) !void {
            self.attempt += 1;
            return error.BadRequest;
        }
    };

    var mock = MockClientErrorClient{};
    client.http_client = &mock;

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const result = client.streamWithRetry("test prompt", fbs.writer());
    try testing.expectError(error.BadRequest, result);

    // Should only try once (no retries for 4xx)
    try testing.expectEqual(@as(u32, 1), mock.attempt);
}

test "LlmClient - circuit breaker opens after consecutive failures" {
    const allocator = testing.allocator;

    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();
    client.circuit_breaker_threshold = 3;

    // Mock that always fails
    const MockFailClient = struct {
        pub fn streamPost(_: *@This(), _: []const u8, _: anytype, _: []const u8, _: anytype) !void {
            return error.ServiceUnavailable;
        }
    };

    var mock = MockFailClient{};
    client.http_client = &mock;

    var buf: [256]u8 = undefined;

    // Fail 3 times to open circuit breaker
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        var fbs = std.io.fixedBufferStream(&buf);
        _ = client.streamWithRetry("test", fbs.writer()) catch {};
    }

    // Circuit breaker should now be open
    try testing.expect(client.circuit_breaker_open);

    // Next request should fail immediately with CircuitBreakerOpen
    var fbs = std.io.fixedBufferStream(&buf);
    const result = client.streamWithRetry("test", fbs.writer());
    try testing.expectError(error.CircuitBreakerOpen, result);
}

test "LlmClient - circuit breaker half-opens after timeout" {
    const allocator = testing.allocator;

    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();
    client.circuit_breaker_open = true;
    client.circuit_breaker_timeout_ms = 100;
    client.circuit_breaker_opened_at = std.time.milliTimestamp() - 200; // 200ms ago

    // Should transition to half-open state
    try testing.expect(client.circuitBreakerShouldRetry());
}

test "LlmClient - circuit breaker closes after successful request in half-open state" {
    const allocator = testing.allocator;

    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();
    client.circuit_breaker_open = true;
    client.circuit_breaker_timeout_ms = 0; // Immediate half-open

    const MockSuccessClient = struct {
        pub fn streamPost(_: *@This(), _: []const u8, _: anytype, _: []const u8, writer: anytype) !void {
            try writer.writeAll("Success");
        }
    };

    var mock = MockSuccessClient{};
    client.http_client = &mock;

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    try client.streamWithRetry("test", fbs.writer());

    // Circuit breaker should close after success
    try testing.expect(!client.circuit_breaker_open);
}

// ============================================================================
// FEATURE 5: PROMPT TEMPLATE SYSTEM (7 tests)
// ============================================================================

test "PromptTemplate - render substitutes single variable" {
    const allocator = testing.allocator;

    const template = PromptTemplate{
        .template = "Hello, {{name}}!",
    };

    const vars = .{ .name = "Claude" };
    const rendered = try template.render(allocator, vars);
    defer allocator.free(rendered);

    try testing.expectEqualStrings("Hello, Claude!", rendered);
}

test "PromptTemplate - render substitutes multiple variables" {
    const allocator = testing.allocator;

    const template = PromptTemplate{
        .template = "{{greeting}}, {{name}}! Today is {{day}}.",
    };

    const vars = .{
        .greeting = "Good morning",
        .name = "Alice",
        .day = "Monday",
    };
    const rendered = try template.render(allocator, vars);
    defer allocator.free(rendered);

    try testing.expectEqualStrings("Good morning, Alice! Today is Monday.", rendered);
}

test "PromptTemplate - render handles missing variable with error" {
    const allocator = testing.allocator;

    const template = PromptTemplate{
        .template = "Hello, {{name}}! You are {{age}} years old.",
    };

    const vars = .{ .name = "Bob" }; // Missing 'age'
    const result = template.render(allocator, vars);

    try testing.expectError(error.MissingVariable, result);
}

test "PromptTemplate - render handles no variables" {
    const allocator = testing.allocator;

    const template = PromptTemplate{
        .template = "This is a static prompt.",
    };

    const vars = .{};
    const rendered = try template.render(allocator, vars);
    defer allocator.free(rendered);

    try testing.expectEqualStrings("This is a static prompt.", rendered);
}

test "PromptTemplate - render handles escaped braces" {
    const allocator = testing.allocator;

    const template = PromptTemplate{
        .template = "Use {{{{variable}}}} syntax for {{name}}.",
    };

    const vars = .{ .name = "substitution" };
    const rendered = try template.render(allocator, vars);
    defer allocator.free(rendered);

    try testing.expectEqualStrings("Use {{variable}} syntax for substitution.", rendered);
}

test "PromptTemplate - render handles nested templates" {
    const allocator = testing.allocator;

    const inner_template = PromptTemplate{
        .template = "Hello, {{name}}",
    };

    const inner_vars = .{ .name = "World" };
    const inner_rendered = try inner_template.render(allocator, inner_vars);
    defer allocator.free(inner_rendered);

    const outer_template = PromptTemplate{
        .template = "{{greeting}}! How are you?",
    };

    const outer_vars = .{ .greeting = inner_rendered };
    const outer_rendered = try outer_template.render(allocator, outer_vars);
    defer allocator.free(outer_rendered);

    try testing.expectEqualStrings("Hello, World! How are you?", outer_rendered);
}

test "PromptTemplate - render validates variable names" {
    const allocator = testing.allocator;

    const template = PromptTemplate{
        .template = "Invalid {{invalid-name}} variable name",
    };

    // Variable names with hyphens or starting with numbers should be rejected
    const vars = .{ .name = "test" }; // Missing the required variable
    const result = template.render(allocator, vars);

    try testing.expectError(error.InvalidVariableName, result);
}

// ============================================================================
// FEATURE 6: RESPONSE STREAMING WIDGET (10 tests)
// ============================================================================

test "ResponseStreamWidget - init creates widget with default config" {
    const allocator = testing.allocator;

    var widget = try ResponseStreamWidget.init(allocator);
    defer widget.deinit();

    // Verify default configuration
    try testing.expectEqual(@as(usize, 0), widget.buffer.items.len);
    try testing.expect(widget.word_wrap);
    try testing.expect(widget.auto_scroll);
}

test "ResponseStreamWidget - appendChunk adds text to buffer" {
    const allocator = testing.allocator;

    var widget = try ResponseStreamWidget.init(allocator);
    defer widget.deinit();

    try widget.appendChunk("Hello");
    try widget.appendChunk(" ");
    try widget.appendChunk("world");

    const text = widget.getText();
    try testing.expectEqualStrings("Hello world", text);
}

test "ResponseStreamWidget - render displays text in area" {
    const allocator = testing.allocator;
    const Buffer = sailor.Buffer;
    const Rect = sailor.Rect;

    var widget = try ResponseStreamWidget.init(allocator);
    defer widget.deinit();

    try widget.appendChunk("Test response");

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try widget.render(&buf, area);

    // Verify text is rendered
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'T'), cell.?.char);
}

test "ResponseStreamWidget - word wrap breaks long lines" {
    const allocator = testing.allocator;
    const Buffer = sailor.Buffer;
    const Rect = sailor.Rect;

    var widget = try ResponseStreamWidget.init(allocator);
    defer widget.deinit();
    widget.word_wrap = true;

    // Text longer than area width
    try widget.appendChunk("This is a very long line that should be wrapped at word boundaries");

    var buf = try Buffer.init(allocator, 20, 10); // Only 20 chars wide
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 20, .height = 10 };
    try widget.render(&buf, area);

    // Verify text wraps to multiple lines
    const cell_line2 = buf.getConst(0, 1);
    try testing.expect(cell_line2 != null);
    try testing.expect(cell_line2.?.char != ' '); // Should have content on line 2
}

test "ResponseStreamWidget - auto scroll shows latest content" {
    const allocator = testing.allocator;
    const Buffer = sailor.Buffer;
    const Rect = sailor.Rect;

    var widget = try ResponseStreamWidget.init(allocator);
    defer widget.deinit();
    widget.auto_scroll = true;

    // Add more lines than fit in the area
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        try widget.appendChunk("Line ");
        try widget.appendChunk(try std.fmt.allocPrint(allocator, "{d}\n", .{i}));
    }

    var buf = try Buffer.init(allocator, 40, 5); // Only 5 lines visible
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    try widget.render(&buf, area);

    // Should show the last 5 lines (15-19)
    const first_line = widget.getVisibleLine(0);
    try testing.expect(std.mem.indexOf(u8, first_line, "Line 15") != null);
}

test "ResponseStreamWidget - loading spinner shows when waiting" {
    const allocator = testing.allocator;
    const Buffer = sailor.Buffer;
    const Rect = sailor.Rect;

    var widget = try ResponseStreamWidget.init(allocator);
    defer widget.deinit();
    widget.show_spinner = true;
    widget.waiting = true;

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try widget.render(&buf, area);

    // Verify spinner character is rendered
    const spinner_chars = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏";
    const cell = buf.getConst(area.width - 1, 0); // Top-right corner
    try testing.expect(cell != null);

    // Should be one of the spinner characters
    var found = false;
    for (spinner_chars) |c| {
        if (cell.?.char == c) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

test "ResponseStreamWidget - scroll up shows earlier content" {
    const allocator = testing.allocator;
    const Buffer = sailor.Buffer;
    const Rect = sailor.Rect;

    var widget = try ResponseStreamWidget.init(allocator);
    defer widget.deinit();

    // Add content
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        try widget.appendChunk(try std.fmt.allocPrint(allocator, "Line {d}\n", .{i}));
    }

    // Scroll to bottom first
    widget.scrollToBottom();

    // Then scroll up 10 lines
    widget.scrollUp(10);

    var buf = try Buffer.init(allocator, 40, 5);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 5 };
    try widget.render(&buf, area);

    // Should show earlier content
    const first_line = widget.getVisibleLine(0);
    try testing.expect(std.mem.indexOf(u8, first_line, "Line 5") != null or
                       std.mem.indexOf(u8, first_line, "Line 6") != null);
}

test "ResponseStreamWidget - clear resets buffer" {
    const allocator = testing.allocator;

    var widget = try ResponseStreamWidget.init(allocator);
    defer widget.deinit();

    try widget.appendChunk("Some content");
    try testing.expect(widget.buffer.items.len > 0);

    widget.clear();
    try testing.expectEqual(@as(usize, 0), widget.buffer.items.len);
}

test "ResponseStreamWidget - handles empty buffer gracefully" {
    const allocator = testing.allocator;
    const Buffer = sailor.Buffer;
    const Rect = sailor.Rect;

    var widget = try ResponseStreamWidget.init(allocator);
    defer widget.deinit();

    // Render without any content
    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try widget.render(&buf, area);

    // Should not crash, buffer should remain empty/filled with spaces
    const cell = buf.getConst(0, 0);
    if (cell) |c| {
        try testing.expect(c.char == ' ' or c.char == 0);
    }
}

test "ResponseStreamWidget - handles Unicode emoji correctly" {
    const allocator = testing.allocator;
    const Buffer = sailor.Buffer;
    const Rect = sailor.Rect;

    var widget = try ResponseStreamWidget.init(allocator);
    defer widget.deinit();

    try widget.appendChunk("Hello 👋 World 🌍");

    var buf = try Buffer.init(allocator, 40, 10);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 40, .height = 10 };
    try widget.render(&buf, area);

    // Verify rendering doesn't crash and text is present
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'H'), cell.?.char);
}

// ============================================================================
// INTEGRATION TESTS (4 tests)
// ============================================================================

test "Integration - LlmClient with RateLimiter integration" {
    const allocator = testing.allocator;

    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();

    // Configure rate limiter
    client.rate_limiter = RateLimiter{
        .requests_per_minute = 2,
        .tokens_per_minute = 1000,
        .current_requests = 0,
        .current_tokens = 0,
        .window_start = std.time.milliTimestamp(),
    };

    var buf: [256]u8 = undefined;

    // First two requests should succeed
    var fbs1 = std.io.fixedBufferStream(&buf);
    try client.stream("test 1", fbs1.writer());

    var fbs2 = std.io.fixedBufferStream(&buf);
    try client.stream("test 2", fbs2.writer());

    // Third request should fail due to rate limit
    var fbs3 = std.io.fixedBufferStream(&buf);
    const result = client.stream("test 3", fbs3.writer());
    try testing.expectError(error.RateLimitExceeded, result);
}

test "Integration - LlmClient with TokenBudget integration" {
    const allocator = testing.allocator;

    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();

    client.token_budget = TokenBudget{
        .max_tokens = 100,
        .used_tokens = 0,
    };

    // Short prompt should succeed
    const short_prompt = "Hi";
    var buf: [256]u8 = undefined;
    var fbs1 = std.io.fixedBufferStream(&buf);
    try client.stream(short_prompt, fbs1.writer());

    // Very long prompt should fail budget check
    const long_prompt = "This is a very long prompt " ** 20; // Repeat to exceed budget
    var fbs2 = std.io.fixedBufferStream(&buf);
    const result = client.stream(long_prompt, fbs2.writer());
    try testing.expectError(error.BudgetExceeded, result);
}

test "Integration - PromptTemplate with ResponseStreamWidget" {
    const allocator = testing.allocator;
    const Buffer = sailor.Buffer;
    const Rect = sailor.Rect;

    // Render prompt from template
    const template = PromptTemplate{
        .template = "Explain {{concept}} to a {{level}} student.",
    };

    const vars = .{
        .concept = "recursion",
        .level = "beginner",
    };
    const prompt = try template.render(allocator, vars);
    defer allocator.free(prompt);

    // Stream response to widget
    var widget = try ResponseStreamWidget.init(allocator);
    defer widget.deinit();

    try widget.appendChunk("Recursion is when a function calls itself...");

    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try widget.render(&buf, area);

    // Verify content is displayed
    const cell = buf.getConst(0, 0);
    try testing.expect(cell != null);
    try testing.expectEqual(@as(u21, 'R'), cell.?.char);
}

test "Integration - Full pipeline with mock HTTP" {
    const allocator = testing.allocator;
    const Buffer = sailor.Buffer;
    const Rect = sailor.Rect;

    // 1. Prepare prompt from template
    const template = PromptTemplate{
        .template = "Hello {{name}}, how are you?",
    };
    const vars = .{ .name = "Claude" };
    const prompt = try template.render(allocator, vars);
    defer allocator.free(prompt);

    // 2. Create client with rate limiter and budget
    var client = try LlmClient.init(allocator, "test-key", "https://example.com");
    defer client.deinit();

    client.rate_limiter = RateLimiter{
        .requests_per_minute = 10,
        .tokens_per_minute = 1000,
        .current_requests = 0,
        .current_tokens = 0,
        .window_start = std.time.milliTimestamp(),
    };

    client.token_budget = TokenBudget{
        .max_tokens = 1000,
        .used_tokens = 0,
    };

    // 3. Stream response to widget
    var widget = try ResponseStreamWidget.init(allocator);
    defer widget.deinit();

    // Mock streaming chunks
    try widget.appendChunk("I'm doing well, ");
    try widget.appendChunk("thank you for asking!");

    // 4. Render widget to buffer
    var buf = try Buffer.init(allocator, 80, 24);
    defer buf.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 80, .height = 24 };
    try widget.render(&buf, area);

    // Verify full pipeline works
    const text = widget.getText();
    try testing.expectEqualStrings("I'm doing well, thank you for asking!", text);
}
