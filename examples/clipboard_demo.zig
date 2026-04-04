//! Clipboard Demo — Demonstrates sailor's clipboard integration capabilities
//!
//! Features:
//! - OSC 52 clipboard write (copy to system clipboard)
//! - Paste bracketing (safe multi-line paste handling)
//! - Terminal emulator detection
//! - Terminal capability detection
//! - Three clipboard selections (clipboard, primary, system)
//! - Interactive text editor with copy/paste shortcuts
//!
//! Usage:
//! - Type text in the input field
//! - Ctrl+C: Copy current text to clipboard
//! - Ctrl+V: Paste from clipboard
//! - Ctrl+X: Cut (copy + clear)
//! - Tab: Switch between clipboard selections
//! - Esc: Quit

const std = @import("std");
const sailor = @import("sailor");

const Terminal = sailor.tui.Terminal;
const Buffer = sailor.tui.buffer.Buffer;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const Clipboard = sailor.clipboard.Clipboard;
const Selection = sailor.clipboard.Selection;
const PasteHandler = sailor.paste.PasteHandler;
const TerminalDetector = sailor.terminal_detect.TerminalDetector;
const TerminalCaps = sailor.terminal_caps.TerminalCaps;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal
    var term = try Terminal.init(allocator);
    defer term.deinit();

    // Detect terminal emulator and capabilities
    const detector = TerminalDetector.detect();
    const caps = try TerminalCaps.detect(allocator);
    defer caps.deinit();

    // App state
    var app = App{
        .input_buffer = std.ArrayList(u8).init(allocator),
        .clipboard_buffer = std.ArrayList(u8).init(allocator),
        .status_message = std.ArrayList(u8).init(allocator),
        .selection = .clipboard,
        .terminal_name = detector.name(),
        .supports_clipboard = caps.clipboard,
        .supports_bracketed_paste = caps.bracketed_paste,
    };
    defer app.input_buffer.deinit();
    defer app.clipboard_buffer.deinit();
    defer app.status_message.deinit();

    // Enable bracketed paste mode
    if (app.supports_bracketed_paste) {
        try term.enableBracketedPaste();
    }

    // Main loop
    try run(&term, &app);

    // Disable bracketed paste mode
    if (app.supports_bracketed_paste) {
        try term.disableBracketedPaste();
    }
}

const App = struct {
    input_buffer: std.ArrayList(u8),
    clipboard_buffer: std.ArrayList(u8),
    status_message: std.ArrayList(u8),
    selection: Selection,
    cursor_pos: usize = 0,
    terminal_name: []const u8,
    supports_clipboard: bool,
    supports_bracketed_paste: bool,
    quit: bool = false,
};

fn run(term: *Terminal, app: *App) !void {
    while (!app.quit) {
        // Draw UI
        try term.draw(struct {
            app: *App,

            pub fn draw(self: @This(), buf: *Buffer, area: Rect) !void {
                try drawUI(buf, area, self.app);
            }
        }{ .app = app });

        // Handle input
        if (try term.pollEvent(100)) |event| {
            try handleEvent(term, app, event);
        }
    }
}

fn drawUI(buf: *Buffer, area: Rect, app: *App) !void {
    // Split layout into sections
    const layout = [_]Rect{
        // Header
        Rect{ .x = area.x, .y = area.y, .width = area.width, .height = 3 },
        // Input field
        Rect{ .x = area.x, .y = area.y + 3, .width = area.width, .height = 5 },
        // Clipboard preview
        Rect{ .x = area.x, .y = area.y + 8, .width = area.width, .height = 5 },
        // Status bar
        Rect{ .x = area.x, .y = area.y + 13, .width = area.width, .height = 3 },
        // Help
        Rect{ .x = area.x, .y = area.y + 16, .width = area.width, .height = area.height -| 16 },
    };

    // Draw header
    {
        const title = try std.fmt.allocPrint(
            buf.allocator,
            "Clipboard Demo — Terminal: {s}",
            .{app.terminal_name},
        );
        defer buf.allocator.free(title);

        const block = Block{
            .title = title,
            .borders = .all,
            .border_style = Style{ .fg = Color{ .indexed = 12 } }, // Blue
        };
        block.render(buf, layout[0]);

        const caps_text = try std.fmt.allocPrint(
            buf.allocator,
            "Clipboard: {s} | Bracketed Paste: {s}",
            .{
                if (app.supports_clipboard) "✓" else "✗",
                if (app.supports_bracketed_paste) "✓" else "✗",
            },
        );
        defer buf.allocator.free(caps_text);

        const inner = layout[0].inner(1);
        buf.setString(inner.x, inner.y, caps_text, Style{});
    }

    // Draw input field
    {
        const selection_name = switch (app.selection) {
            .clipboard => "Clipboard (standard)",
            .primary => "Primary (X11 middle-click)",
            .system => "System (OS-specific)",
        };

        const title = try std.fmt.allocPrint(
            buf.allocator,
            "Input Field — Selection: {s}",
            .{selection_name},
        );
        defer buf.allocator.free(title);

        const block = Block{
            .title = title,
            .borders = .all,
            .border_style = Style{ .fg = Color{ .indexed = 10 } }, // Green
        };
        block.render(buf, layout[1]);

        const inner = layout[1].inner(1);
        const text = app.input_buffer.items;
        buf.setString(inner.x, inner.y, text, Style{});

        // Draw cursor
        const cursor_x = inner.x + @as(u16, @intCast(@min(app.cursor_pos, inner.width - 1)));
        buf.setCursor(cursor_x, inner.y);
    }

    // Draw clipboard preview
    {
        const block = Block{
            .title = "Clipboard Preview (last copied)",
            .borders = .all,
            .border_style = Style{ .fg = Color{ .indexed = 11 } }, // Yellow
        };
        block.render(buf, layout[2]);

        const inner = layout[2].inner(1);
        if (app.clipboard_buffer.items.len > 0) {
            // Show first line only
            const preview = blk: {
                const newline_pos = std.mem.indexOfScalar(u8, app.clipboard_buffer.items, '\n');
                if (newline_pos) |pos| {
                    break :blk app.clipboard_buffer.items[0..pos];
                } else {
                    break :blk app.clipboard_buffer.items;
                }
            };
            const truncated = if (preview.len > inner.width) preview[0..inner.width] else preview;
            buf.setString(inner.x, inner.y, truncated, Style{});
        } else {
            buf.setString(inner.x, inner.y, "(empty)", Style{ .fg = Color{ .indexed = 8 } });
        }
    }

    // Draw status bar
    {
        const block = Block{
            .title = "Status",
            .borders = .all,
        };
        block.render(buf, layout[3]);

        const inner = layout[3].inner(1);
        if (app.status_message.items.len > 0) {
            buf.setString(inner.x, inner.y, app.status_message.items, Style{ .fg = Color{ .indexed = 10 } });
        }
    }

    // Draw help
    {
        const block = Block{
            .title = "Keyboard Shortcuts",
            .borders = .all,
        };
        block.render(buf, layout[4]);

        const inner = layout[4].inner(1);
        const help_lines = [_][]const u8{
            "Ctrl+C: Copy to clipboard",
            "Ctrl+V: Paste from clipboard (simulated - OSC 52 read not widely supported)",
            "Ctrl+X: Cut (copy + clear)",
            "Tab: Switch clipboard selection",
            "Esc: Quit",
        };

        for (help_lines, 0..) |line, i| {
            if (i < inner.height) {
                buf.setString(inner.x, inner.y + @as(u16, @intCast(i)), line, Style{});
            }
        }
    }
}

fn handleEvent(term: *Terminal, app: *App, event: anytype) !void {
    switch (event) {
        .key => |key| {
            try handleKey(term, app, key);
        },
        .resize => {},
        else => {},
    }
}

fn handleKey(term: *Terminal, app: *App, key: anytype) !void {
    // Ctrl+C: Copy
    if (key.char == 'c' and key.ctrl) {
        try copyToClipboard(term, app);
        return;
    }

    // Ctrl+V: Paste (simulated)
    if (key.char == 'v' and key.ctrl) {
        try pasteFromClipboard(app);
        return;
    }

    // Ctrl+X: Cut
    if (key.char == 'x' and key.ctrl) {
        try cutToClipboard(term, app);
        return;
    }

    // Tab: Switch selection
    if (key.char == '\t') {
        app.selection = switch (app.selection) {
            .clipboard => .primary,
            .primary => .system,
            .system => .clipboard,
        };
        try setStatus(app, "Switched clipboard selection");
        return;
    }

    // Esc: Quit
    if (key.char == 0x1B) {
        app.quit = true;
        return;
    }

    // Backspace
    if (key.char == 0x7F or key.char == '\x08') {
        if (app.cursor_pos > 0 and app.input_buffer.items.len > 0) {
            _ = app.input_buffer.orderedRemove(app.cursor_pos - 1);
            app.cursor_pos -= 1;
        }
        return;
    }

    // Regular character input
    if (std.ascii.isPrint(key.char)) {
        try app.input_buffer.insert(app.cursor_pos, key.char);
        app.cursor_pos += 1;
    }
}

fn copyToClipboard(term: *Terminal, app: *App) !void {
    if (app.input_buffer.items.len == 0) {
        try setStatus(app, "Nothing to copy");
        return;
    }

    // Write to terminal's clipboard via OSC 52
    const stdout = std.io.getStdOut().writer();
    try Clipboard.write(stdout, app.input_buffer.items, app.selection);

    // Store in local buffer for preview
    app.clipboard_buffer.clearRetainingCapacity();
    try app.clipboard_buffer.appendSlice(app.input_buffer.items);

    try setStatus(app, "Copied to clipboard");
    _ = term;
}

fn pasteFromClipboard(app: *App) !void {
    // NOTE: OSC 52 read (clipboard read) is not widely supported
    // Most terminals don't respond to OSC 52 read requests
    // This is a simulation using the local clipboard buffer

    if (app.clipboard_buffer.items.len == 0) {
        try setStatus(app, "Clipboard is empty");
        return;
    }

    // Handle multi-line paste with PasteHandler
    if (app.supports_bracketed_paste) {
        // In a real scenario, we'd receive bracketed paste from terminal input
        // Here we simulate by processing lines
        var line_count: usize = 0;
        PasteHandler.processLines(app.clipboard_buffer.items, struct {
            fn callback(line: []const u8) void {
                _ = line;
                line_count += 1;
            }
        }.callback);

        try app.input_buffer.appendSlice(app.clipboard_buffer.items);
        app.cursor_pos = app.input_buffer.items.len;

        const status = try std.fmt.allocPrint(
            app.status_message.allocator,
            "Pasted {d} line(s)",
            .{line_count},
        );
        defer app.status_message.allocator.free(status);

        app.status_message.clearRetainingCapacity();
        try app.status_message.appendSlice(status);
    } else {
        try app.input_buffer.appendSlice(app.clipboard_buffer.items);
        app.cursor_pos = app.input_buffer.items.len;
        try setStatus(app, "Pasted from clipboard");
    }
}

fn cutToClipboard(term: *Terminal, app: *App) !void {
    try copyToClipboard(term, app);
    app.input_buffer.clearRetainingCapacity();
    app.cursor_pos = 0;
    try setStatus(app, "Cut to clipboard");
}

fn setStatus(app: *App, message: []const u8) !void {
    app.status_message.clearRetainingCapacity();
    try app.status_message.appendSlice(message);
}
