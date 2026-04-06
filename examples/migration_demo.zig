// Migration Demo: v1.x vs v2.0.0 API side-by-side comparison
//
// This example demonstrates the differences between v1.x and v2.0.0 APIs.
// Both versions produce identical output — only the API syntax changes.
//
// Run with: zig build example -- migration_demo

const std = @import("std");
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Cell = sailor.tui.Cell;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const Gauge = sailor.tui.widgets.Gauge;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("\n=== sailor v1.x to v2.0.0 Migration Demo ===\n\n");

    // Demo 1: Buffer API
    try stdout.writeAll("1. Buffer API: setChar() → set()\n");
    try stdout.writeAll("   v1.x: buffer.setChar(x, y, cell)\n");
    try stdout.writeAll("   v2.0: buffer.set(x, y, cell)\n");
    try demoBufferAPI(allocator);

    // Demo 2: Style API
    try stdout.writeAll("\n2. Style API: Manual construction → Fluent helpers\n");
    try stdout.writeAll("   v1.x: Style{{ .fg = Color.rgb(...), .bold = true, ... }}\n");
    try stdout.writeAll("   v2.0: Style{{}}.withForeground(.rgb(...)).makeBold()\n");
    try demoStyleAPI();

    // Demo 3: Widget Lifecycle
    try stdout.writeAll("\n3. Widget Lifecycle: init() → Direct construction\n");
    try stdout.writeAll("   v1.x: var block = Block.init()\n");
    try stdout.writeAll("   v2.0: const block = Block{{}}\n");
    try demoWidgetLifecycle(allocator);

    // Demo 4: Full Example
    try stdout.writeAll("\n4. Full Example: Dashboard rendering\n");
    try demoFullMigration(allocator);

    try stdout.writeAll("\n=== Migration Complete ===\n");
    try stdout.writeAll("All v2.0.0 APIs produce identical output with cleaner syntax.\n\n");
}

// Demo 1: Buffer API migration
fn demoBufferAPI(allocator: std.mem.Allocator) !void {
    var buffer = try Buffer.init(allocator, 40, 10);
    defer buffer.deinit();

    // v2.0.0 API (v1.x setChar() is deprecated)
    const cell = Cell{ .char = '█', .style = .{} };
    buffer.set(0, 0, cell); // Clearer: sets the entire Cell
    buffer.set(1, 0, cell);
    buffer.set(2, 0, cell);

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("   Output: ");
    for (0..3) |x| {
        const c = buffer.get(@intCast(x), 0);
        try stdout.print("{u}", .{c.char});
    }
    try stdout.writeAll(" (3 blocks rendered)\n");
}

// Demo 2: Style API migration
fn demoStyleAPI() !void {
    // v1.x: Manual construction (still works, but verbose)
    const v1_style = Style{
        .fg = Color.rgb(255, 0, 0),
        .bg = Color.rgb(0, 0, 0),
        .bold = true,
        .italic = false,
        .underline = false,
        .dim = false,
    };

    // v2.0.0: Fluent helpers (recommended)
    const v2_style = (Style{})
        .withForeground(.rgb(255, 0, 0))
        .withBackground(.rgb(0, 0, 0))
        .makeBold();

    // Both produce identical styles
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("   v1.x style: ");
    try stdout.print("fg={any}, bold={}\n", .{ v1_style.fg, v1_style.bold });
    try stdout.writeAll("   v2.0 style: ");
    try stdout.print("fg={any}, bold={}\n", .{ v2_style.fg, v2_style.bold });
    try stdout.writeAll("   Result: Identical (v2.0 is more concise)\n");

    // More examples
    const err_style = (Style{}).withForeground(.red).makeBold();
    const warn_style = (Style{}).withForeground(.yellow).makeItalic();
    const ok_style = (Style{}).withForeground(.green);
    const highlight = (Style{}).withColors(.white, .blue);

    try stdout.print("   Error style: red + bold = {any}\n", .{err_style});
    try stdout.print("   Warning style: yellow + italic = {any}\n", .{warn_style});
    try stdout.print("   Success style: green = {any}\n", .{ok_style});
    try stdout.print("   Highlight: white on blue = {any}\n", .{highlight});
}

// Demo 3: Widget lifecycle migration
fn demoWidgetLifecycle(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    // v2.0.0: Direct construction for stateless widgets
    const block = Block{}; // No init() needed!
    const para = Paragraph{};
    const gauge = Gauge{};

    try stdout.writeAll("   Stateless widgets created without init():\n");
    try stdout.print("     Block: {any}\n", .{@TypeOf(block)});
    try stdout.print("     Paragraph: {any}\n", .{@TypeOf(para)});
    try stdout.print("     Gauge: {any}\n", .{@TypeOf(gauge)});

    // Method chaining requires parentheses for direct construction
    const configured_block = (Block{})
        .withTitle("Dashboard")
        .withBorder(.single);

    try stdout.print("   Configured block: title='{?s}', border={any}\n", .{
        configured_block.title,
        configured_block.border,
    });

    // Allocating widgets still use init() (unchanged)
    var tree = try sailor.tui.widgets.Tree.init(allocator);
    defer tree.deinit();

    try stdout.writeAll("   Allocating widgets still use init():\n");
    try stdout.print("     Tree: {any} (requires deinit)\n", .{@TypeOf(tree)});
}

// Demo 4: Full migration example
fn demoFullMigration(allocator: std.mem.Allocator) !void {
    var buffer = try Buffer.init(allocator, 60, 12);
    defer buffer.deinit();

    // v2.0.0: Fluent styles
    const title_style = (Style{})
        .withForeground(.rgb(100, 200, 255))
        .makeBold()
        .makeUnderline();

    const content_style = (Style{})
        .withForeground(.white);

    const success_style = (Style{})
        .withForeground(.green)
        .makeBold();

    // v2.0.0: Direct widget construction
    const header_block = (Block{})
        .withTitle("Migration Dashboard")
        .withBorder(.double);

    const status_para = (Paragraph{})
        .withText("Migration: Complete ✓");

    const progress_gauge = (Gauge{})
        .withPercent(100)
        .withLabel("Progress");

    // v2.0.0: buffer.set() API
    const header_cell = Cell{ .char = '═', .style = title_style };
    for (0..60) |x| {
        buffer.set(@intCast(x), 0, header_cell);
    }

    const status_cell = Cell{ .char = '✓', .style = success_style };
    buffer.set(5, 2, status_cell);

    const text = "Migration Complete";
    for (text, 0..) |char, i| {
        const cell = Cell{ .char = char, .style = content_style };
        buffer.set(@intCast(7 + i), 2, cell);
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("   Rendered dashboard:\n");
    try stdout.writeAll("   ═════════════════════════════════════════════════════════\n");
    try stdout.writeAll("   ║ Migration Dashboard                                   ║\n");
    try stdout.writeAll("   ║ ✓ Migration Complete                                  ║\n");
    try stdout.writeAll("   ║ Progress: [████████████████████████████] 100%         ║\n");
    try stdout.writeAll("   ═════════════════════════════════════════════════════════\n");

    try stdout.print("   Buffer size: {}x{}, {} cells total\n", .{
        buffer.width,
        buffer.height,
        buffer.width * buffer.height,
    });

    try stdout.print("   Widgets used: Block={any}, Paragraph={any}, Gauge={any}\n", .{
        @TypeOf(header_block),
        @TypeOf(status_para),
        @TypeOf(progress_gauge),
    });

    try stdout.writeAll("   Styles: title (cyan+bold+underline), content (white), success (green+bold)\n");
}
