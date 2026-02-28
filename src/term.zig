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
