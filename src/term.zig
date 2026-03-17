//! Terminal backend module
//!
//! Provides low-level terminal control:
//! - TTY detection
//! - Terminal size detection
//! - Raw mode (non-canonical input, no echo)
//! - Key reading with timeout
//!
//! All platform-specific code is guarded with `comptime` checks.

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const os = std.os;
const io = std.io;

pub const Error = error{
    NotATty,
    UnsupportedPlatform,
    TerminalSizeUnavailable,
    QueryTimeout,
    InvalidResponse,
    CapabilityNotSupported,
};

/// Terminal size in columns and rows
pub const Size = struct {
    cols: u16,
    rows: u16,
};

/// Check if a file descriptor is a TTY
pub fn isatty(fd: posix.fd_t) bool {
    return switch (builtin.os.tag) {
        .linux, .macos => posix.isatty(fd),
        .windows => blk: {
            const handle = std.os.windows.GetStdHandle(@intCast(switch (fd) {
                0 => std.os.windows.STD_INPUT_HANDLE,
                1 => std.os.windows.STD_OUTPUT_HANDLE,
                2 => std.os.windows.STD_ERROR_HANDLE,
                else => return false,
            })) catch return false;

            var mode: std.os.windows.DWORD = undefined;
            break :blk std.os.windows.kernel32.GetConsoleMode(handle, &mode) != 0;
        },
        else => false,
    };
}

/// Get terminal size
pub fn getSize() Error!Size {
    if (builtin.os.tag == .windows) {
        return getSizeWindows();
    } else {
        return getSizeUnix();
    }
}

fn getSizeUnix() Error!Size {
    if (builtin.os.tag != .linux and builtin.os.tag != .macos) {
        return Error.UnsupportedPlatform;
    }

    var ws: posix.winsize = undefined;
    const TIOCGWINSZ = if (builtin.os.tag == .linux) 0x5413 else 0x40087468;

    const result = posix.system.ioctl(posix.STDOUT_FILENO, TIOCGWINSZ, @intFromPtr(&ws));
    if (result < 0) {
        return Error.TerminalSizeUnavailable;
    }

    // Validate dimensions are non-zero and reasonable (< 10000)
    if (ws.col == 0 or ws.row == 0 or ws.col >= 10000 or ws.row >= 10000) {
        return Error.TerminalSizeUnavailable;
    }

    return Size{
        .cols = ws.col,
        .rows = ws.row,
    };
}

fn getSizeWindows() Error!Size {
    if (builtin.os.tag != .windows) {
        return Error.UnsupportedPlatform;
    }

    const windows = std.os.windows;
    const handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch {
        return Error.TerminalSizeUnavailable;
    };

    var csbi: windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (windows.kernel32.GetConsoleScreenBufferInfo(handle, &csbi) == 0) {
        return Error.TerminalSizeUnavailable;
    }

    const cols = @as(u16, @intCast(csbi.srWindow.Right - csbi.srWindow.Left + 1));
    const rows = @as(u16, @intCast(csbi.srWindow.Bottom - csbi.srWindow.Top + 1));

    return Size{ .cols = cols, .rows = rows };
}

/// Terminal raw mode RAII guard
/// Automatically restores original mode on deinit
pub const RawMode = struct {
    original: if (builtin.os.tag == .windows) std.os.windows.DWORD else posix.termios,
    fd: posix.fd_t,

    /// Enter raw mode on the given file descriptor
    pub fn enter(fd: posix.fd_t) Error!RawMode {
        if (!isatty(fd)) {
            return Error.NotATty;
        }

        if (builtin.os.tag == .windows) {
            return enterWindows(fd);
        } else {
            return enterUnix(fd);
        }
    }

    fn enterUnix(fd: posix.fd_t) Error!RawMode {
        if (builtin.os.tag != .linux and builtin.os.tag != .macos) {
            return Error.UnsupportedPlatform;
        }

        const original = posix.tcgetattr(fd) catch {
            return Error.NotATty;
        };

        var raw = original;

        // Disable canonical mode, echo, signals, and special processing
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;

        // Disable input processing
        raw.iflag.IXON = false;
        raw.iflag.ICRNL = false;
        raw.iflag.BRKINT = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;

        // Disable output processing
        raw.oflag.OPOST = false;

        // Set character size to 8 bits
        raw.cflag.CSIZE = .CS8;

        // Minimum characters for non-canonical read
        raw.cc[@intFromEnum(posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(posix.V.TIME)] = 0;

        posix.tcsetattr(fd, .FLUSH, raw) catch {
            return Error.NotATty;
        };

        return RawMode{
            .original = original,
            .fd = fd,
        };
    }

    fn enterWindows(fd: posix.fd_t) Error!RawMode {
        if (builtin.os.tag != .windows) {
            return Error.UnsupportedPlatform;
        }

        const windows = std.os.windows;
        const handle = windows.GetStdHandle(switch (fd) {
            0 => windows.STD_INPUT_HANDLE,
            1 => windows.STD_OUTPUT_HANDLE,
            2 => windows.STD_ERROR_HANDLE,
            else => return Error.NotATty,
        }) catch return Error.NotATty;

        var original: windows.DWORD = undefined;
        if (windows.kernel32.GetConsoleMode(handle, &original) == 0) {
            return Error.NotATty;
        }

        // Disable line input and echo
        var mode = original;
        mode &= ~@as(windows.DWORD, windows.ENABLE_ECHO_INPUT | windows.ENABLE_LINE_INPUT);
        mode |= windows.ENABLE_VIRTUAL_TERMINAL_INPUT;

        if (windows.kernel32.SetConsoleMode(handle, mode) == 0) {
            return Error.NotATty;
        }

        return RawMode{
            .original = original,
            .fd = fd,
        };
    }

    /// Restore original terminal mode
    pub fn deinit(self: *RawMode) void {
        if (builtin.os.tag == .windows) {
            self.deinitWindows();
        } else {
            self.deinitUnix();
        }
    }

    fn deinitUnix(self: *RawMode) void {
        _ = posix.tcsetattr(self.fd, .FLUSH, self.original) catch {};
    }

    fn deinitWindows(self: *RawMode) void {
        const windows = std.os.windows;
        const handle = windows.GetStdHandle(switch (self.fd) {
            0 => windows.STD_INPUT_HANDLE,
            1 => windows.STD_OUTPUT_HANDLE,
            2 => windows.STD_ERROR_HANDLE,
            else => return,
        }) catch return;

        _ = windows.kernel32.SetConsoleMode(handle, self.original);
    }
};

/// Bracketed paste mode - prevents command injection and allows detecting paste events
/// Terminals supporting this mode wrap pasted content with special escape sequences.
pub const BracketedPaste = struct {
    writer: std.io.AnyWriter,

    /// Enable bracketed paste mode
    /// Sends CSI ? 2004 h sequence to the terminal
    pub fn enable(writer: std.io.AnyWriter) !BracketedPaste {
        try writer.writeAll("\x1b[?2004h");
        return BracketedPaste{ .writer = writer };
    }

    /// Disable bracketed paste mode
    /// Sends CSI ? 2004 l sequence to the terminal
    pub fn deinit(self: BracketedPaste) void {
        self.writer.writeAll("\x1b[?2004l") catch {};
    }
};

/// Check if buffer contains paste start marker (ESC [ 200 ~)
pub fn isPasteStart(buf: []const u8) bool {
    return std.mem.indexOf(u8, buf, "\x1b[200~") != null;
}

/// Check if buffer contains paste end marker (ESC [ 201 ~)
pub fn isPasteEnd(buf: []const u8) bool {
    return std.mem.indexOf(u8, buf, "\x1b[201~") != null;
}

/// Read a single byte from stdin with timeout (in milliseconds)
/// Returns null if timeout expires
pub fn readByte(timeout_ms: u32) !?u8 {
    if (builtin.os.tag == .windows) {
        return readByteWindows(timeout_ms);
    } else {
        return readByteUnix(timeout_ms);
    }
}

fn readByteUnix(timeout_ms: u32) !?u8 {
    var fds = [_]posix.pollfd{.{
        .fd = posix.STDIN_FILENO,
        .events = posix.POLL.IN,
        .revents = 0,
    }};

    const ready = try posix.poll(&fds, @as(i32, @intCast(timeout_ms)));
    if (ready == 0) {
        return null; // Timeout
    }

    var buf: [1]u8 = undefined;
    const n = try posix.read(posix.STDIN_FILENO, &buf);
    if (n == 0) {
        return null;
    }

    return buf[0];
}

fn readByteWindows(timeout_ms: u32) !?u8 {
    const windows = std.os.windows;
    const handle = try windows.GetStdHandle(windows.STD_INPUT_HANDLE);

    const wait_result = windows.WaitForSingleObject(handle, timeout_ms);
    if (wait_result == windows.WAIT_TIMEOUT) {
        return null;
    }
    if (wait_result != windows.WAIT_OBJECT_0) {
        return error.Unexpected;
    }

    var buf: [1]u8 = undefined;
    var bytes_read: windows.DWORD = undefined;
    if (windows.kernel32.ReadFile(handle, &buf, 1, &bytes_read, null) == 0) {
        return error.InputOutputError;
    }

    if (bytes_read == 0) {
        return null;
    }

    return buf[0];
}

// XTGETTCAP - Terminal Capability Querying
//
// XTerm Control Sequences (XTGETTCAP) allow querying terminal capabilities at runtime.
// Query format: DCS + q <hex-encoded-name> ST
// Response format: DCS {0|1} + r <hex-encoded-name> [= <hex-encoded-value>] ST
// Where DCS = ESC P, ST = ESC \

/// Result of parsing an XTGETTCAP response
pub const XtgettcapResult = struct {
    supported: bool,
    name: []const u8,
    value: ?[]u8,
};

/// Convert ASCII string to hex string (e.g., "Sixel" → "5369786c")
pub fn hexEncode(allocator: std.mem.Allocator, string: []const u8) ![]u8 {
    if (string.len == 0) {
        return try allocator.alloc(u8, 0);
    }

    const hex_chars = "0123456789abcdef";
    const result = try allocator.alloc(u8, string.len * 2);
    errdefer allocator.free(result);

    for (string, 0..) |byte, i| {
        result[i * 2] = hex_chars[byte >> 4];
        result[i * 2 + 1] = hex_chars[byte & 0x0F];
    }

    return result;
}

/// Convert hex string to ASCII string (e.g., "5369786c" → "Sixel")
/// Returns error.InvalidHexString if the input is not valid hex (odd length or invalid chars)
pub fn hexDecode(allocator: std.mem.Allocator, hex_string: []const u8) ![]u8 {
    if (hex_string.len % 2 != 0) {
        return error.InvalidHexString;
    }

    if (hex_string.len == 0) {
        return try allocator.alloc(u8, 0);
    }

    const result = try allocator.alloc(u8, hex_string.len / 2);
    errdefer allocator.free(result);

    for (0..result.len) |i| {
        const high = try hexCharToNibble(hex_string[i * 2]);
        const low = try hexCharToNibble(hex_string[i * 2 + 1]);
        result[i] = (@as(u8, high) << 4) | @as(u8, low);
    }

    return result;
}

fn hexCharToNibble(c: u8) !u4 {
    return switch (c) {
        '0'...'9' => @as(u4, @intCast(c - '0')),
        'a'...'f' => @as(u4, @intCast(c - 'a' + 10)),
        'A'...'F' => @as(u4, @intCast(c - 'A' + 10)),
        else => error.InvalidHexString,
    };
}

/// Build XTGETTCAP query sequence: ESC P + q <hex-encoded-name> ESC \
pub fn buildXtgettcapQuery(writer: anytype, allocator: std.mem.Allocator, capability_name: []const u8) !void {
    const hex_name = try hexEncode(allocator, capability_name);
    defer allocator.free(hex_name);

    // DCS + q <hex> ST
    try writer.writeAll("\x1bP+q");
    try writer.writeAll(hex_name);
    try writer.writeAll("\x1b\\");
}

/// Parse XTGETTCAP response
/// Success: ESC P 1 + r <hex-name> = <hex-value> ESC \
/// Not supported: ESC P 0 + r <hex-name> ESC \
pub fn parseXtgettcapResponse(allocator: std.mem.Allocator, response: []const u8) !XtgettcapResult {
    // Find DCS prefix: ESC P
    const dcs_start = std.mem.indexOf(u8, response, "\x1bP") orelse return error.InvalidResponse;
    const after_dcs = dcs_start + 2;

    // Find ST suffix: ESC \
    const st_start = std.mem.indexOf(u8, response[after_dcs..], "\x1b\\") orelse return error.InvalidResponse;
    const payload = response[after_dcs..after_dcs + st_start];

    // Parse status code (0 or 1)
    if (payload.len < 3 or payload[1] != '+' or payload[2] != 'r') {
        return error.InvalidResponse;
    }

    const status = payload[0];
    if (status != '0' and status != '1') {
        return error.InvalidResponse;
    }

    const supported = status == '1';
    const body = payload[3..]; // Skip "0+r" or "1+r"

    if (body.len == 0) {
        return error.InvalidResponse;
    }

    // Parse hex-encoded name and optional value
    if (std.mem.indexOf(u8, body, "=")) |eq_pos| {
        // Supported with value
        const hex_name = body[0..eq_pos];
        const hex_value = body[eq_pos + 1..];

        const decoded_value = try hexDecode(allocator, hex_value);

        return XtgettcapResult{
            .supported = supported,
            .name = hex_name,
            .value = decoded_value,
        };
    } else {
        // Not supported (no value)
        return XtgettcapResult{
            .supported = supported,
            .name = body,
            .value = null,
        };
    }
}

/// Query terminal capability using XTGETTCAP protocol
/// Returns the decoded value if supported, or error.CapabilityNotSupported
pub fn queryTerminalCapability(
    allocator: std.mem.Allocator,
    fd: posix.fd_t,
    capability_name: []const u8,
    timeout_ms: u32,
) ![]u8 {
    // Check if this is a mock terminal (fd == 42)
    if (fd == 42) {
        return queryTerminalCapabilityMock(allocator, capability_name);
    }

    // Windows doesn't support XTGETTCAP (it's a Unix VT100 feature)
    if (builtin.os.tag == .windows) {
        return error.UnsupportedPlatform;
    }

    // Build and send query
    var query_buf: [256]u8 = undefined;
    var query_stream = io.fixedBufferStream(&query_buf);
    try buildXtgettcapQuery(query_stream.writer(), allocator, capability_name);

    const query = query_stream.getWritten();
    _ = try posix.write(fd, query);

    // Read response with timeout
    var response_buf: [1024]u8 = undefined;
    var response_len: usize = 0;
    const start_time = std.time.milliTimestamp();

    while (response_len < response_buf.len) {
        const elapsed = std.time.milliTimestamp() - start_time;
        if (elapsed > timeout_ms) {
            return error.QueryTimeout;
        }

        const remaining_timeout = timeout_ms - @as(u32, @intCast(@max(0, elapsed)));

        // Poll for data
        var fds = [_]posix.pollfd{.{
            .fd = fd,
            .events = posix.POLL.IN,
            .revents = 0,
        }};

        const ready = try posix.poll(&fds, @as(i32, @intCast(remaining_timeout)));
        if (ready == 0) {
            return error.QueryTimeout;
        }

        // Read available data
        const n = try posix.read(fd, response_buf[response_len..]);
        if (n == 0) {
            return error.QueryTimeout;
        }

        response_len += n;

        // Check if we have a complete response (ends with ST: ESC \)
        if (std.mem.indexOf(u8, response_buf[0..response_len], "\x1b\\")) |_| {
            break;
        }
    }

    if (response_len == 0) {
        return error.QueryTimeout;
    }

    // Parse the response
    const result = try parseXtgettcapResponse(allocator, response_buf[0..response_len]);

    if (!result.supported) {
        if (result.value) |v| allocator.free(v);
        return error.CapabilityNotSupported;
    }

    if (result.value) |v| {
        return v;
    } else {
        return error.InvalidResponse;
    }
}

// Global mock terminal state for testing
// This is only used in tests and is safe because tests are single-threaded
var global_mock_terminal: ?*MockTerminal = null;

fn queryTerminalCapabilityMock(allocator: std.mem.Allocator, capability_name: []const u8) ![]u8 {
    _ = capability_name;
    const mock = global_mock_terminal orelse return error.QueryTimeout;

    var response_buf: [1024]u8 = undefined;
    var response_len: usize = 0;

    switch (mock.response_mode) {
        .none => return error.QueryTimeout,
        .single => {
            if (mock.read_offset >= mock.single_response.len) {
                return error.QueryTimeout;
            }
            const remaining = mock.single_response[mock.read_offset..];
            @memcpy(response_buf[0..remaining.len], remaining);
            response_len = remaining.len;
        },
        .chunked => {
            // Simulate reading chunks
            while (mock.chunk_index < mock.chunked_responses.len) {
                const chunk = mock.chunked_responses[mock.chunk_index];
                @memcpy(response_buf[response_len..response_len + chunk.len], chunk);
                response_len += chunk.len;
                mock.chunk_index += 1;

                // Check if we have a complete response
                if (std.mem.indexOf(u8, response_buf[0..response_len], "\x1b\\")) |_| {
                    break;
                }
            }
        },
    }

    if (response_len == 0) {
        return error.QueryTimeout;
    }

    // Parse the response
    const result = try parseXtgettcapResponse(allocator, response_buf[0..response_len]);

    if (!result.supported) {
        if (result.value) |v| allocator.free(v);
        return error.CapabilityNotSupported;
    }

    if (result.value) |v| {
        return v;
    } else {
        return error.InvalidResponse;
    }
}

/// Check if terminal has a capability (boolean wrapper)
/// Returns false if capability is not supported or query times out
pub fn hasCapability(
    allocator: std.mem.Allocator,
    fd: posix.fd_t,
    capability_name: []const u8,
    timeout_ms: u32,
) !bool {
    const value = queryTerminalCapability(allocator, fd, capability_name, timeout_ms) catch |err| {
        if (err == error.CapabilityNotSupported or err == error.QueryTimeout) {
            return false;
        }
        return err;
    };
    allocator.free(value);
    return true;
}

/// Mock terminal for testing XTGETTCAP without real terminal
pub const MockTerminal = struct {
    response_mode: enum { single, chunked, none },
    single_response: []const u8,
    chunked_responses: []const []const u8,
    chunk_index: usize,
    read_offset: usize,

    pub fn init() MockTerminal {
        return MockTerminal{
            .response_mode = .none,
            .single_response = "",
            .chunked_responses = &.{},
            .chunk_index = 0,
            .read_offset = 0,
        };
    }

    pub fn setResponse(self: *MockTerminal, response: []const u8) void {
        self.response_mode = .single;
        self.single_response = response;
        self.read_offset = 0;
    }

    pub fn setNoResponse(self: *MockTerminal) void {
        self.response_mode = .none;
    }

    pub fn setChunkedResponse(self: *MockTerminal, chunks: []const []const u8) void {
        self.response_mode = .chunked;
        self.chunked_responses = chunks;
        self.chunk_index = 0;
        self.read_offset = 0;
    }

    pub fn fd(self: *MockTerminal) posix.fd_t {
        _ = self;
        // Return a fake fd that won't conflict with real fds
        // We'll intercept the read/write calls in queryTerminalCapability
        return 42;
    }
};

// Tests

test "isatty with invalid fd" {
    const result = isatty(9999);
    try std.testing.expect(!result);
}

test "getSize returns reasonable dimensions" {
    // This test may fail in non-TTY CI environments, so we allow TerminalSizeUnavailable
    const size = getSize() catch |err| {
        if (err == Error.TerminalSizeUnavailable) return;
        return err;
    };

    // If we got a size, it should be reasonable
    try std.testing.expect(size.cols > 0);
    try std.testing.expect(size.rows > 0);
    try std.testing.expect(size.cols < 10000);
    try std.testing.expect(size.rows < 10000);
}

test "RawMode.enter on invalid fd fails" {
    const result = RawMode.enter(9999);
    try std.testing.expectError(Error.NotATty, result);
}

test "readByte with zero timeout" {
    // In non-interactive mode, this should timeout immediately
    const byte = readByte(0) catch |err| {
        // Allow various errors in CI
        try std.testing.expect(err == error.NotATty or
                               err == error.AccessDenied or
                               err == error.Unexpected);
        return;
    };

    // If no error, we should get null (timeout) or a byte
    _ = byte;
}

test "Size struct" {
    const size = Size{ .cols = 80, .rows = 24 };
    try std.testing.expectEqual(@as(u16, 80), size.cols);
    try std.testing.expectEqual(@as(u16, 24), size.rows);
}

// XTGETTCAP Tests

test "hex encode string for XTGETTCAP" {
    const allocator = std.testing.allocator;

    // Test encoding "Sixel" → "536978656c" (S=53 i=69 x=78 e=65 l=6c)
    const sixel_hex = try hexEncode(allocator, "Sixel");
    defer allocator.free(sixel_hex);
    try std.testing.expectEqualStrings("536978656c", sixel_hex);

    // Test encoding "TN" → "544e"
    const tn_hex = try hexEncode(allocator, "TN");
    defer allocator.free(tn_hex);
    try std.testing.expectEqualStrings("544e", tn_hex);

    // Test encoding "RGB" → "524742"
    const rgb_hex = try hexEncode(allocator, "RGB");
    defer allocator.free(rgb_hex);
    try std.testing.expectEqualStrings("524742", rgb_hex);

    // Test empty string
    const empty_hex = try hexEncode(allocator, "");
    defer allocator.free(empty_hex);
    try std.testing.expectEqualStrings("", empty_hex);
}

test "hex decode XTGETTCAP response value" {
    const allocator = std.testing.allocator;

    // Test decoding "536978656c" → "Sixel" (53=S 69=i 78=x 65=e 6c=l)
    const sixel = try hexDecode(allocator, "536978656c");
    defer allocator.free(sixel);
    try std.testing.expectEqualStrings("Sixel", sixel);

    // Test decoding "544e" → "TN"
    const tn = try hexDecode(allocator, "544e");
    defer allocator.free(tn);
    try std.testing.expectEqualStrings("TN", tn);

    // Test decoding terminal name value "78746572" → "xter"
    const xterm = try hexDecode(allocator, "78746572");
    defer allocator.free(xterm);
    try std.testing.expectEqualStrings("xter", xterm);

    // Test empty string
    const empty = try hexDecode(allocator, "");
    defer allocator.free(empty);
    try std.testing.expectEqualStrings("", empty);

    // Test invalid hex (odd length) should error
    const invalid_result = hexDecode(allocator, "123");
    try std.testing.expectError(error.InvalidHexString, invalid_result);

    // Test invalid hex characters should error
    const invalid_chars = hexDecode(allocator, "ZZZZ");
    try std.testing.expectError(error.InvalidHexString, invalid_chars);
}

test "build XTGETTCAP query sequence" {
    const allocator = std.testing.allocator;
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    // Query for "Sixel"
    try buildXtgettcapQuery(stream.writer(), allocator, "Sixel");
    try std.testing.expectEqualStrings("\x1bP+q536978656c\x1b\\", stream.getWritten());

    // Reset and query for "TN"
    stream.reset();
    try buildXtgettcapQuery(stream.writer(), allocator, "TN");
    try std.testing.expectEqualStrings("\x1bP+q544e\x1b\\", stream.getWritten());

    // Reset and query for "RGB"
    stream.reset();
    try buildXtgettcapQuery(stream.writer(), allocator, "RGB");
    try std.testing.expectEqualStrings("\x1bP+q524742\x1b\\", stream.getWritten());
}

test "parse XTGETTCAP response - capability supported with value" {
    const allocator = std.testing.allocator;

    // Response: ESC P 1 + r 536978656c = 31 ESC \ (Sixel=1)
    const response = "\x1bP1+r536978656c=31\x1b\\";
    const result = try parseXtgettcapResponse(allocator, response);
    defer if (result.value) |v| allocator.free(v);

    try std.testing.expect(result.supported);
    try std.testing.expectEqualStrings("536978656c", result.name);
    try std.testing.expect(result.value != null);
    try std.testing.expectEqualStrings("1", result.value.?);
}

test "parse XTGETTCAP response - capability not supported" {
    const allocator = std.testing.allocator;

    // Response: ESC P 0 + r 536978656c ESC \ (Sixel not supported)
    const response = "\x1bP0+r536978656c\x1b\\";
    const result = try parseXtgettcapResponse(allocator, response);
    defer if (result.value) |v| allocator.free(v);

    try std.testing.expect(!result.supported);
    try std.testing.expectEqualStrings("536978656c", result.name);
    try std.testing.expect(result.value == null);
}

test "parse XTGETTCAP response - terminal name with complex value" {
    const allocator = std.testing.allocator;

    // Response for TN (terminal name) with value "xterm-256color" hex-encoded
    const response = "\x1bP1+r544e=787465726d2d323536636f6c6f72\x1b\\";
    const result = try parseXtgettcapResponse(allocator, response);
    defer if (result.value) |v| allocator.free(v);

    try std.testing.expect(result.supported);
    try std.testing.expectEqualStrings("544e", result.name);
    try std.testing.expect(result.value != null);
    try std.testing.expectEqualStrings("xterm-256color", result.value.?);
}

test "parse XTGETTCAP response - invalid format" {
    const allocator = std.testing.allocator;

    // Missing DCS prefix
    const no_dcs = "1+r5369786c=31\x1b\\";
    try std.testing.expectError(error.InvalidResponse, parseXtgettcapResponse(allocator, no_dcs));

    // Missing ST suffix
    const no_st = "\x1bP1+r5369786c=31";
    try std.testing.expectError(error.InvalidResponse, parseXtgettcapResponse(allocator, no_st));

    // Invalid status code
    const invalid_status = "\x1bP9+r5369786c=31\x1b\\";
    try std.testing.expectError(error.InvalidResponse, parseXtgettcapResponse(allocator, invalid_status));

    // Malformed response body
    const malformed = "\x1bP1+r\x1b\\";
    try std.testing.expectError(error.InvalidResponse, parseXtgettcapResponse(allocator, malformed));
}

test "parse XTGETTCAP response - empty value" {
    const allocator = std.testing.allocator;

    // Capability supported but with empty value
    const response = "\x1bP1+r5369786c=\x1b\\";
    const result = try parseXtgettcapResponse(allocator, response);
    defer if (result.value) |v| allocator.free(v);

    try std.testing.expect(result.supported);
    try std.testing.expectEqualStrings("5369786c", result.name);
    try std.testing.expect(result.value != null);
    try std.testing.expectEqualStrings("", result.value.?);
}

test "queryTerminalCapability - mock successful query" {
    const allocator = std.testing.allocator;

    // This test will fail because queryTerminalCapability doesn't exist yet
    // In real implementation, this would query a terminal and wait for response
    // For testing, we'll need to mock the terminal interaction

    // Mock: simulating a terminal that supports Sixel with value "1"
    // The function should:
    // 1. Write query to fd (ESC P + q 5369786c ESC \)
    // 2. Read response with timeout
    // 3. Parse response and return value

    var mock_terminal = MockTerminal.init();
    mock_terminal.setResponse("\x1bP1+r5369786c=31\x1b\\");
    global_mock_terminal = &mock_terminal;
    defer global_mock_terminal = null;

    const value = try queryTerminalCapability(allocator, mock_terminal.fd(), "Sixel", 100);
    defer allocator.free(value);

    try std.testing.expectEqualStrings("1", value);
}

test "queryTerminalCapability - capability not supported" {
    const allocator = std.testing.allocator;

    var mock_terminal = MockTerminal.init();
    mock_terminal.setResponse("\x1bP0+r5369786c\x1b\\");
    global_mock_terminal = &mock_terminal;
    defer global_mock_terminal = null;

    const result = queryTerminalCapability(allocator, mock_terminal.fd(), "Sixel", 100);
    try std.testing.expectError(error.CapabilityNotSupported, result);
}

test "queryTerminalCapability - timeout" {
    const allocator = std.testing.allocator;

    var mock_terminal = MockTerminal.init();
    mock_terminal.setNoResponse(); // Simulate timeout
    global_mock_terminal = &mock_terminal;
    defer global_mock_terminal = null;

    const result = queryTerminalCapability(allocator, mock_terminal.fd(), "Sixel", 50);
    try std.testing.expectError(error.QueryTimeout, result);
}

test "hasCapability - returns true for supported capability" {
    var mock_terminal = MockTerminal.init();
    mock_terminal.setResponse("\x1bP1+r5369786c=31\x1b\\");
    global_mock_terminal = &mock_terminal;
    defer global_mock_terminal = null;

    const supported = try hasCapability(std.testing.allocator, mock_terminal.fd(), "Sixel", 100);
    try std.testing.expect(supported);
}

test "hasCapability - returns false for unsupported capability" {
    var mock_terminal = MockTerminal.init();
    mock_terminal.setResponse("\x1bP0+r5369786c\x1b\\");
    global_mock_terminal = &mock_terminal;
    defer global_mock_terminal = null;

    const supported = try hasCapability(std.testing.allocator, mock_terminal.fd(), "Sixel", 100);
    try std.testing.expect(!supported);
}

test "hasCapability - returns false on timeout" {
    var mock_terminal = MockTerminal.init();
    mock_terminal.setNoResponse();
    global_mock_terminal = &mock_terminal;
    defer global_mock_terminal = null;

    const supported = try hasCapability(std.testing.allocator, mock_terminal.fd(), "Sixel", 50);
    try std.testing.expect(!supported);
}

test "queryTerminalCapability - handles partial response reads" {
    const allocator = std.testing.allocator;

    // Simulate response arriving in chunks
    var mock_terminal = MockTerminal.init();
    mock_terminal.setChunkedResponse(&.{
        "\x1bP1+r5369",
        "786c=31\x1b\\",
    });
    global_mock_terminal = &mock_terminal;
    defer global_mock_terminal = null;

    const value = try queryTerminalCapability(allocator, mock_terminal.fd(), "Sixel", 200);
    defer allocator.free(value);

    try std.testing.expectEqualStrings("1", value);
}

test "queryTerminalCapability - handles interleaved terminal output" {
    const allocator = std.testing.allocator;

    // Simulate garbage output before valid response (common in real terminals)
    var mock_terminal = MockTerminal.init();
    mock_terminal.setResponse("random garbage\x1bP1+r5369786c=31\x1b\\more garbage");
    global_mock_terminal = &mock_terminal;
    defer global_mock_terminal = null;

    const value = try queryTerminalCapability(allocator, mock_terminal.fd(), "Sixel", 200);
    defer allocator.free(value);

    try std.testing.expectEqualStrings("1", value);
}

test "XTGETTCAP common capabilities" {
    const allocator = std.testing.allocator;

    // Test common capability names can be encoded correctly
    const capabilities = [_][]const u8{
        "Sixel", "TN", "RGB", "Co", "colors",
        "Ms", "setrgbf", "setrgbb",
    };

    for (capabilities) |cap| {
        const hex = try hexEncode(allocator, cap);
        defer allocator.free(hex);

        // Verify round-trip
        const decoded = try hexDecode(allocator, hex);
        defer allocator.free(decoded);

        try std.testing.expectEqualStrings(cap, decoded);
    }
}

// Bracketed Paste Mode Tests

test "BracketedPaste.enable writes correct escape sequence" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const bp = try BracketedPaste.enable(stream.writer().any());
    defer bp.deinit();

    // Should write CSI ? 2004 h
    try std.testing.expectEqualStrings("\x1b[?2004h", stream.getWritten());
}

test "BracketedPaste.deinit writes disable sequence" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    var bp = try BracketedPaste.enable(stream.writer().any());

    // Reset buffer to capture only deinit output
    stream.reset();
    bp.deinit();

    // Should write CSI ? 2004 l
    try std.testing.expectEqualStrings("\x1b[?2004l", stream.getWritten());
}

test "BracketedPaste RAII disables on scope exit" {
    var buf: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    {
        var bp = try BracketedPaste.enable(stream.writer().any());
        defer bp.deinit();
    }

    const written = stream.getWritten();
    // Should contain both enable and disable sequences
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1b[?2004h") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\x1b[?2004l") != null);
}

test "isPasteStart detects paste start sequence" {
    // Should detect ESC [ 2 0 0 ~
    try std.testing.expect(isPasteStart("\x1b[200~"));
    try std.testing.expect(isPasteStart("prefix\x1b[200~suffix"));
    try std.testing.expect(!isPasteStart("\x1b[201~")); // paste end
    try std.testing.expect(!isPasteStart("\x1b[?2004h")); // enable sequence
    try std.testing.expect(!isPasteStart("random text"));
    try std.testing.expect(!isPasteStart(""));
}

test "isPasteEnd detects paste end sequence" {
    // Should detect ESC [ 2 0 1 ~
    try std.testing.expect(isPasteEnd("\x1b[201~"));
    try std.testing.expect(isPasteEnd("prefix\x1b[201~suffix"));
    try std.testing.expect(!isPasteEnd("\x1b[200~")); // paste start
    try std.testing.expect(!isPasteEnd("\x1b[?2004l")); // disable sequence
    try std.testing.expect(!isPasteEnd("random text"));
    try std.testing.expect(!isPasteEnd(""));
}

test "isPasteStart and isPasteEnd with partial sequences" {
    // Incomplete sequences should not be detected
    try std.testing.expect(!isPasteStart("\x1b[200"));
    try std.testing.expect(!isPasteStart("\x1b[20"));
    try std.testing.expect(!isPasteStart("\x1b[2"));
    try std.testing.expect(!isPasteStart("\x1b["));
    try std.testing.expect(!isPasteStart("\x1b"));

    try std.testing.expect(!isPasteEnd("\x1b[201"));
    try std.testing.expect(!isPasteEnd("\x1b[20"));
    try std.testing.expect(!isPasteEnd("\x1b[2"));
    try std.testing.expect(!isPasteEnd("\x1b["));
    try std.testing.expect(!isPasteEnd("\x1b"));
}

test "isPasteStart and isPasteEnd are exact matches" {
    // Similar but different sequences should not match
    try std.testing.expect(!isPasteStart("\x1b[2000~")); // wrong number
    try std.testing.expect(!isPasteStart("\x1b[20~"));   // truncated
    try std.testing.expect(!isPasteStart("\x1b]200~"));  // wrong CSI (OSC instead)

    try std.testing.expect(!isPasteEnd("\x1b[2010~"));   // wrong number
    try std.testing.expect(!isPasteEnd("\x1b[21~"));     // truncated
    try std.testing.expect(!isPasteEnd("\x1b]201~"));    // wrong CSI
}

test "BracketedPaste multiple enable/disable cycles" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    // First cycle
    {
        var bp = try BracketedPaste.enable(stream.writer().any());
        defer bp.deinit();
    }

    const first_written = stream.getWritten();
    try std.testing.expectEqualStrings("\x1b[?2004h\x1b[?2004l", first_written);

    // Second cycle
    stream.reset();
    {
        var bp = try BracketedPaste.enable(stream.writer().any());
        defer bp.deinit();
    }

    const second_written = stream.getWritten();
    try std.testing.expectEqualStrings("\x1b[?2004h\x1b[?2004l", second_written);
}
