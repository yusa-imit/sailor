//! Win32 console bindings that Zig 0.16's `std.os.windows` no longer ships.
//!
//! Only meaningful on Windows targets; on every other target nothing here is analysed because
//! callers reach it exclusively through `builtin.os.tag == .windows` branches. The thin wrappers
//! keep the shape the pre-0.16 std functions had (`GetStdHandle` and friends returning error
//! unions), while the raw externs return `c_int` so call sites keep comparing against zero.
//! No allocation; no state.

const std = @import("std");
const windows = std.os.windows;

pub const HANDLE = windows.HANDLE;
pub const DWORD = windows.DWORD;
pub const INVALID_HANDLE_VALUE = windows.INVALID_HANDLE_VALUE;
pub const CloseHandle = windows.CloseHandle;

pub const STD_INPUT_HANDLE: DWORD = @bitCast(@as(i32, -10));
pub const STD_OUTPUT_HANDLE: DWORD = @bitCast(@as(i32, -11));
pub const STD_ERROR_HANDLE: DWORD = @bitCast(@as(i32, -12));

const wait_object_0: DWORD = 0;

pub const COORD = extern struct {
    X: i16,
    Y: i16,
};

pub const SMALL_RECT = extern struct {
    Left: i16,
    Top: i16,
    Right: i16,
    Bottom: i16,
};

pub const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
    dwSize: COORD,
    dwCursorPosition: COORD,
    wAttributes: u16,
    srWindow: SMALL_RECT,
    dwMaximumWindowSize: COORD,
};

/// Same layout as `SECURITY_ATTRIBUTES`, but `bInheritHandle` is a plain `c_int`.
pub const SECURITY_ATTRIBUTES = extern struct {
    nLength: DWORD,
    lpSecurityDescriptor: ?*anyopaque,
    bInheritHandle: c_int,
};

pub const kernel32 = struct {
    pub extern "kernel32" fn GetStdHandle(nStdHandle: DWORD) callconv(.winapi) ?HANDLE;
    pub extern "kernel32" fn GetConsoleMode(
        hConsole: HANDLE,
        lpMode: *DWORD,
    ) callconv(.winapi) c_int;
    pub extern "kernel32" fn SetConsoleMode(
        hConsole: HANDLE,
        dwMode: DWORD,
    ) callconv(.winapi) c_int;
    pub extern "kernel32" fn GetConsoleScreenBufferInfo(
        hConsole: HANDLE,
        lpInfo: *CONSOLE_SCREEN_BUFFER_INFO,
    ) callconv(.winapi) c_int;
    pub extern "kernel32" fn ReadFile(
        hFile: HANDLE,
        lpBuffer: [*]u8,
        nNumberOfBytesToRead: DWORD,
        lpNumberOfBytesRead: ?*DWORD,
        lpOverlapped: ?*anyopaque,
    ) callconv(.winapi) c_int;
    pub extern "kernel32" fn WaitForSingleObject(
        hHandle: HANDLE,
        dwMilliseconds: DWORD,
    ) callconv(.winapi) DWORD;
    pub extern "kernel32" fn CreatePipe(
        hReadPipe: *HANDLE,
        hWritePipe: *HANDLE,
        lpPipeAttributes: ?*SECURITY_ATTRIBUTES,
        nSize: DWORD,
    ) callconv(.winapi) c_int;
};

pub const GetStdHandleError = error{ NoStandardHandleAttached, Unexpected };

/// Returns the process standard handle for `handle_id` (one of the `STD_*_HANDLE` constants).
pub fn GetStdHandle(handle_id: DWORD) GetStdHandleError!HANDLE {
    std.debug.assert(handle_id == STD_INPUT_HANDLE or handle_id == STD_OUTPUT_HANDLE or
        handle_id == STD_ERROR_HANDLE);
    const handle = kernel32.GetStdHandle(handle_id) orelse
        return error.NoStandardHandleAttached;
    if (handle == INVALID_HANDLE_VALUE) return error.Unexpected;
    return handle;
}

pub const WaitError = error{ WaitTimeOut, WaitFailed };

/// Waits up to `timeout_ms` for `handle` to become signaled.
pub fn WaitForSingleObject(handle: HANDLE, timeout_ms: DWORD) WaitError!void {
    const result = kernel32.WaitForSingleObject(handle, timeout_ms);
    if (result == wait_object_0) return;
    if (result == 0x102) return error.WaitTimeOut; // WAIT_TIMEOUT.
    return error.WaitFailed;
}

/// Creates an anonymous pipe with the default buffer size.
pub fn CreatePipe(
    read_handle: *HANDLE,
    write_handle: *HANDLE,
    attributes: *SECURITY_ATTRIBUTES,
) error{Unexpected}!void {
    if (kernel32.CreatePipe(read_handle, write_handle, attributes, 0) == 0) {
        return error.Unexpected;
    }
}
