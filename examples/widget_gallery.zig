///! Interactive Widget Gallery for Sailor TUI Framework
///! v1.18.0 Developer Experience Feature
///!
///! This gallery showcases all available widgets with copy-pasteable code examples.
///! Navigate through widgets and view example code for each.

const std = @import("std");
const sailor = @import("sailor");

const Buffer = sailor.tui.Buffer;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const List = sailor.tui.widgets.List;
const Rect = sailor.tui.Rect;
const Style = sailor.tui.Style;
const Color = sailor.tui.Color;

const WidgetExample = struct {
    name: []const u8,
    description: []const u8,
    code: []const u8,
    category: []const u8,
};

const examples = [_]WidgetExample{
    // Core Widgets (Phase 4)
    .{
        .name = "Block",
        .category = "Core Widgets",
        .description = "Container with borders, title, and padding",
        .code =
        \\const block = Block{
        \\    .title = "My Block",
        \\    .borders = .all,
        \\    .border_style = Style{ .fg = Color.cyan },
        \\};
        \\block.render(&buffer, area);
        ,
    },
    .{
        .name = "Paragraph",
        .category = "Core Widgets",
        .description = "Text display with wrapping and alignment",
        .code =
        \\const para = Paragraph{
        \\    .text = "Hello, Sailor TUI!",
        \\    .style = .{ .fg = Color.green },
        \\};
        \\para.render(&buffer, area);
        ,
    },
    .{
        .name = "List",
        .category = "Core Widgets",
        .description = "Selectable item list with highlighting",
        .code =
        \\var list = List.init(allocator);
        \\defer list.deinit();
        \\try list.addItem("Item 1");
        \\try list.addItem("Item 2");
        \\list.selected = 0;
        \\list.render(&buffer, area);
        ,
    },
    .{
        .name = "Gauge",
        .category = "Core Widgets",
        .description = "Progress bar with percentage display",
        .code =
        \\const gauge = Gauge{
        \\    .percent = 75,
        \\    .label = "Loading...",
        \\    .style = .{ .fg = Color.blue },
        \\};
        \\gauge.render(&buffer, area);
        ,
    },
    // Advanced Widgets (Phase 5)
    .{
        .name = "Tree",
        .category = "Advanced Widgets",
        .description = "Hierarchical tree view with expand/collapse",
        .code =
        \\var tree = Tree.init(allocator);
        \\defer tree.deinit();
        \\var root = try tree.addNode("Root", null);
        \\_ = try tree.addNode("Child 1", root);
        \\tree.render(&buffer, area);
        ,
    },
    .{
        .name = "TextArea",
        .category = "Advanced Widgets",
        .description = "Multi-line text editor with cursor",
        .code =
        \\var textarea = TextArea.init(allocator);
        \\defer textarea.deinit();
        \\try textarea.insertText("Line 1\nLine 2");
        \\textarea.render(&buffer, area);
        ,
    },
    .{
        .name = "Calendar",
        .category = "Advanced Widgets (v1.17.0)",
        .description = "Date picker with month/year navigation",
        .code =
        \\const cal = Calendar{
        \\    .year = 2026,
        \\    .month = 3,
        \\    .selected_day = 21,
        \\};
        \\cal.render(&buffer, area);
        ,
    },
    // Data Visualization
    .{
        .name = "BarChart",
        .category = "Data Visualization",
        .description = "Vertical/horizontal bar charts",
        .code =
        \\var chart = BarChart.init(allocator);
        \\defer chart.deinit();
        \\try chart.addBar("A", 10);
        \\try chart.addBar("B", 20);
        \\chart.render(&buffer, area);
        ,
    },
    .{
        .name = "LineChart",
        .category = "Data Visualization",
        .description = "Multi-series line plots",
        .code =
        \\var chart = LineChart.init(allocator);
        \\defer chart.deinit();
        \\try chart.addDataPoint(0, 10.0);
        \\try chart.addDataPoint(1, 20.0);
        \\chart.render(&buffer, area);
        ,
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);
    const stdout = output.writer(allocator);

    try stdout.writeAll("\n");
    try stdout.writeAll("╔═══════════════════════════════════════════════════════════╗\n");
    try stdout.writeAll("║         Sailor TUI Framework - Widget Gallery            ║\n");
    try stdout.writeAll("║                    v1.18.0 Feature                        ║\n");
    try stdout.writeAll("╚═══════════════════════════════════════════════════════════╝\n");
    try stdout.writeAll("\n");

    try stdout.print("Total Widgets: {d}\n\n", .{examples.len});

    // Group by category
    var category_map = std.StringHashMap(std.ArrayList(*const WidgetExample)).init(allocator);
    defer {
        var iter = category_map.valueIterator();
        while (iter.next()) |list| {
            list.deinit(allocator);
        }
        category_map.deinit();
    }

    for (&examples) |*ex| {
        const entry = try category_map.getOrPut(ex.category);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{};
        }
        try entry.value_ptr.append(allocator, ex);
    }

    // Display by category
    var cat_iter = category_map.iterator();
    while (cat_iter.next()) |entry| {
        try stdout.writeAll("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
        try stdout.print("  {s}\n", .{entry.key_ptr.*});
        try stdout.writeAll("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n");

        for (entry.value_ptr.items) |widget| {
            try stdout.print("┌─ {s}\n", .{widget.name});
            try stdout.print("│  {s}\n", .{widget.description});
            try stdout.writeAll("│\n");
            try stdout.writeAll("│  Example Code:\n");

            var iter = std.mem.splitScalar(u8, widget.code, '\n');
            while (iter.next()) |line| {
                try stdout.print("│    {s}\n", .{line});
            }

            try stdout.writeAll("│\n");
        }
        try stdout.writeAll("\n");
    }

    try stdout.writeAll("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    try stdout.writeAll("  For full examples, see: examples/hello.zig, examples/counter.zig\n");
    try stdout.writeAll("  Documentation: https://github.com/yusa-imit/sailor\n");
    try stdout.writeAll("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    try stdout.writeAll("\n");

    // Write to stdout
    _ = try std.posix.write(std.posix.STDOUT_FILENO, output.items);
}
