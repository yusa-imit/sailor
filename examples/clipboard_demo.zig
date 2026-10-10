//! Clipboard Demo — Demonstrates sailor's clipboard integration capabilities
//!
//! Features:
//! - OSC 52 clipboard write (copy to the system clipboard)
//! - Paste splitting (safe multi-line paste handling)
//! - Clipboard history (most recent first)
//! - Terminal emulator and capability detection
//!
//! The demo is non-interactive: it detects the terminal, builds the OSC 52 sequence a copy would
//! send, splits a sample multi-line paste, and prints a summary panel.
//!
//! Run with: zig build example-clipboard_demo

const std = @import("std");
const sailor = @import("sailor");
const support = @import("support.zig");

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const Rect = sailor.tui.Rect;
const Color = sailor.tui.Color;
const Style = sailor.tui.Style;
const Clipboard = sailor.clipboard.Clipboard;
const ClipboardHistory = sailor.clipboard.ClipboardHistory;
const Selection = sailor.clipboard.Selection;
const PasteHandler = sailor.paste.PasteHandler;
const TerminalInfo = sailor.terminal_detect.TerminalInfo;
const Capabilities = sailor.terminal_caps.Capabilities;

const sample_paste = "first line\nsecond line\nthird line";
const summary_bytes_max = 1024;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // Detect the terminal emulator and what it supports.
    const info = TerminalInfo.detect(init.environ_map);
    const caps = Capabilities.detect(init.environ_map);

    // Build the OSC 52 sequence a copy of the sample text would send.
    var osc_storage: [256]u8 = undefined;
    var osc_writer = std.Io.Writer.fixed(&osc_storage);
    try Clipboard.write(&osc_writer, sample_paste, Selection.clipboard);
    const osc_len = osc_writer.buffered().len;

    // Split the sample paste into lines, the way a bracketed paste would be handled.
    const lines = try PasteHandler.splitLines(gpa, sample_paste);
    defer gpa.free(lines);

    // Keep the pasted lines in the history; index 0 is the most recent.
    var history = try ClipboardHistory.init(gpa);
    defer history.deinit();

    for (lines) |line| {
        try history.push(line);
    }

    var summary_storage: [summary_bytes_max]u8 = undefined;
    const summary = try std.fmt.bufPrint(
        &summary_storage,
        "Terminal:          {s}\nClipboard (OSC 52): {}\nBracketed paste:   {}\n" ++
            "OSC 52 sequence:   {d} bytes\nPasted lines:      {d}\nMost recent entry: {s}",
        .{ info.name, caps.clipboard, caps.bracketed_paste, osc_len, lines.len, try history.get(0) },
    );

    var buffer = try Buffer.init(gpa, 60, 10);
    defer buffer.deinit();

    const area = Rect{ .x = 0, .y = 0, .width = 60, .height = 10 };
    var block = Block{
        .title = "Clipboard Demo",
        .borders = .all,
        .border_style = Style{ .fg = Color{ .indexed = 14 } },
    };
    block.render(&buffer, area);
    support.renderText(&buffer, block.inner(area), summary, .left, .{});

    var out_buf: [4096]u8 = undefined;
    var fw = std.Io.File.stdout().writer(io, &out_buf);
    const stdout = &fw.interface;
    try support.renderBuffer(gpa, buffer, stdout);
    try stdout.flush();
}
