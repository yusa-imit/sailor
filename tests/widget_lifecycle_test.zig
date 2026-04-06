//! Widget lifecycle standardization tests
//!
//! This test suite enforces consistent lifecycle patterns across all widgets.
//! Tests will FAIL until all widgets conform to one of these patterns:
//!
//! 1. Stateless: No init/deinit, direct construction `Widget{ .field = value }`
//! 2. Allocating: `init(allocator) -> Widget`, `deinit(self: *Widget) void`
//! 3. Data-driven: `init(items: []const T) -> Widget`, no deinit if no allocations
//!
//! Current status: EXPECTED TO FAIL (v1.37.0 not yet implemented)

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

// Import all widgets for reflection
const Block = sailor.tui.widgets.Block;
const List = sailor.tui.widgets.List;
const Table = sailor.tui.widgets.Table;
const Tree = sailor.tui.widgets.Tree;
const TextArea = sailor.tui.widgets.TextArea;
const Editor = sailor.tui.widgets.Editor;
const VirtualList = sailor.tui.widgets.VirtualList;
const Paragraph = sailor.tui.widgets.Paragraph;
const Gauge = sailor.tui.widgets.Gauge;
const Input = sailor.tui.widgets.Input;

// Widget lifecycle categories
const LifecyclePattern = enum {
    stateless, // No allocator, no deinit
    allocating, // Takes allocator in init, has deinit
    data_driven, // Takes data in init, no allocations
    invalid, // Inconsistent pattern (should not exist)
};

/// Comptime reflection to audit widget lifecycle patterns
fn detectLifecyclePattern(comptime Widget: type) LifecyclePattern {
    const has_init = @hasDecl(Widget, "init");
    const has_deinit = @hasDecl(Widget, "deinit");

    if (!has_init and !has_deinit) {
        return .stateless;
    }

    if (has_init) {
        const init_fn = @field(Widget, "init");
        const init_info = @typeInfo(@TypeOf(init_fn));

        if (init_info != .@"fn") return .invalid;

        const params = init_info.@"fn".params;
        if (params.len == 0) return .invalid;

        // Check if first parameter is Allocator
        const first_param_type = params[0].type orelse return .invalid;
        const is_allocator = first_param_type == std.mem.Allocator;

        if (is_allocator and has_deinit) {
            return .allocating;
        } else if (!is_allocator and !has_deinit) {
            return .data_driven;
        } else {
            return .invalid;
        }
    }

    // has_deinit but no init - invalid
    return .invalid;
}

test "widget lifecycle pattern detection" {
    // These should pass once standardization is complete
    try testing.expectEqual(LifecyclePattern.stateless, detectLifecyclePattern(Block));
    try testing.expectEqual(LifecyclePattern.data_driven, detectLifecyclePattern(List));
    try testing.expectEqual(LifecyclePattern.data_driven, detectLifecyclePattern(Table));
    try testing.expectEqual(LifecyclePattern.allocating, detectLifecyclePattern(Editor));
    try testing.expectEqual(LifecyclePattern.data_driven, detectLifecyclePattern(VirtualList));
}

test "stateless widgets have no init or deinit" {
    // Block should be stateless - direct construction
    const block = Block{
        .borders = sailor.tui.widgets.Borders.all,
        .title = "Test Block",
    };

    // Should compile and be usable immediately
    _ = block;

    // Should NOT have init() or deinit()
    const has_init = @hasDecl(Block, "init");
    const has_deinit = @hasDecl(Block, "deinit");

    try testing.expect(!has_init);
    try testing.expect(!has_deinit);
}

test "data-driven widgets init without allocator" {
    // List should take data in init, no allocator
    const items = [_][]const u8{ "Item 1", "Item 2", "Item 3" };
    const list = List.init(&items);

    _ = list;

    // Should have init() but NO deinit()
    const has_init = @hasDecl(List, "init");
    const has_deinit = @hasDecl(List, "deinit");

    try testing.expect(has_init);
    try testing.expect(!has_deinit);

    // Init should NOT take Allocator as first parameter
    const init_info = @typeInfo(@TypeOf(List.init)).@"fn";
    const first_param = init_info.params[0].type.?;
    try testing.expect(first_param != std.mem.Allocator);
}

test "allocating widgets have init with allocator and deinit" {
    const allocator = testing.allocator;

    // Editor should take allocator and have deinit
    var editor = Editor.init(allocator);
    defer editor.deinit();

    // Should have both init() and deinit()
    const has_init = @hasDecl(Editor, "init");
    const has_deinit = @hasDecl(Editor, "deinit");

    try testing.expect(has_init);
    try testing.expect(has_deinit);

    // Init should take Allocator as first parameter
    const init_info = @typeInfo(@TypeOf(Editor.init)).@"fn";
    const first_param = init_info.params[0].type.?;
    try testing.expectEqual(std.mem.Allocator, first_param);
}

test "allocating widgets properly free memory in deinit" {
    const allocator = testing.allocator;

    // Test Editor lifecycle - should not leak
    var editor = Editor.init(allocator);
    defer editor.deinit();

    // Add some content that requires allocation
    try editor.setText("Line 1\nLine 2\nLine 3");

    // Insert characters
    try editor.insertChar('H');
    try editor.insertChar('i');

    // Deinit should free all allocations
    // If this leaks, testing.allocator will catch it
}

test "allocating widgets handle multiple lifecycle rounds" {
    const allocator = testing.allocator;

    // Multiple init/deinit cycles should not leak
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var editor = Editor.init(allocator);
        try editor.setText("Test content");
        editor.deinit();
    }
}

test "allocating widgets cleanup on init error" {
    const allocator = testing.allocator;

    // This test verifies error handling during init
    // If init fails partway through, it should clean up partial allocations

    // Create a failing allocator that fails after N allocations
    var fail_allocator = testing.FailingAllocator.init(allocator, .{ .fail_index = 2 });
    const failing = fail_allocator.allocator();

    // Editor.init should handle allocation failures gracefully
    const result = Editor.init(failing);

    // Even if init succeeds with partial allocations, deinit must work
    if (@TypeOf(result) == Editor) {
        var editor = result;
        editor.deinit();
    }
}

test "data-driven widgets handle empty data" {
    // List with no items should work
    const empty: []const []const u8 = &.{};
    const list = List.init(empty);

    try testing.expectEqual(@as(usize, 0), list.items.len);
    try testing.expectEqual(@as(?usize, null), list.selected);
}

test "data-driven widgets handle large datasets without allocation" {
    // VirtualList should handle massive item counts without allocating
    const allocator = testing.allocator;
    _ = allocator; // Should NOT be needed for init

    const huge_list = VirtualList.init(1_000_000);

    try testing.expectEqual(@as(usize, 1_000_000), huge_list.total_items);

    // Should not leak (no allocations to track)
}

test "stateless widgets are copyable" {
    // Stateless widgets should be trivially copyable
    const block1 = Block{
        .borders = sailor.tui.widgets.Borders.all,
        .title = "Original",
    };

    const block2 = block1; // Should be a simple copy

    try testing.expectEqualStrings(block1.title.?, block2.title.?);
}

test "allocating widgets are NOT copyable without allocator" {
    // Allocating widgets should not be accidentally copyable
    // (This test documents the expected behavior)

    const allocator = testing.allocator;
    var editor1 = Editor.init(allocator);
    defer editor1.deinit();

    // This would be DANGEROUS - double free
    // var editor2 = editor1; // Should not compile or should be explicitly unsafe

    // Instead, widgets with allocations should have explicit clone() methods
    // that take an allocator

    // Verify editor has allocator field (documenting ownership)
    try testing.expect(@hasField(Editor, "allocator"));
}

test "widget builder pattern preserves lifecycle safety" {
    // Data-driven widgets often use builder pattern
    // Ensure it doesn't violate lifecycle rules

    const items = [_][]const u8{ "A", "B", "C" };
    const list = List.init(&items)
        .withSelected(1)
        .withHighlightSymbol("→ ");

    try testing.expectEqual(@as(?usize, 1), list.selected);

    // Builder methods should return copies (stateless/data-driven)
    // or updated references (allocating)
}

test "allocating widgets deinit is idempotent safe" {
    const allocator = testing.allocator;

    var editor = Editor.init(allocator);
    editor.deinit();

    // Second deinit should not crash (though not recommended)
    // This tests defensive programming in deinit()
    // Uncomment if implementing idempotent deinit:
    // editor.deinit();
}

test "no widget has allocator field without deinit" {
    // If a widget stores an allocator, it MUST have deinit()
    // This is a critical safety rule

    // Test various widgets
    inline for (.{
        Block,
        List,
        Table,
        Tree,
        TextArea,
        VirtualList,
        Paragraph,
        Gauge,
    }) |Widget| {
        const has_allocator_field = @hasField(Widget, "allocator");
        const has_deinit = @hasDecl(Widget, "deinit");

        if (has_allocator_field) {
            try testing.expect(has_deinit);
        }
    }
}

test "widgets with deinit have allocator field or justification" {
    // If a widget has deinit(), it should have an allocator field
    // (or document why it doesn't)

    inline for (.{ Editor }) |Widget| {
        const has_deinit = @hasDecl(Widget, "deinit");
        const has_allocator_field = @hasField(Widget, "allocator");

        if (has_deinit) {
            // Either has allocator field, or is a special case
            // (e.g., manages resources other than memory)
            try testing.expect(has_allocator_field);
        }
    }
}

test "comprehensive widget audit" {
    // Audit all widgets and categorize them
    // This test documents the current state

    const WidgetAudit = struct {
        name: []const u8,
        pattern: LifecyclePattern,
    };

    const audits = [_]WidgetAudit{
        .{ .name = "Block", .pattern = detectLifecyclePattern(Block) },
        .{ .name = "List", .pattern = detectLifecyclePattern(List) },
        .{ .name = "Table", .pattern = detectLifecyclePattern(Table) },
        .{ .name = "Tree", .pattern = detectLifecyclePattern(Tree) },
        .{ .name = "TextArea", .pattern = detectLifecyclePattern(TextArea) },
        .{ .name = "Editor", .pattern = detectLifecyclePattern(Editor) },
        .{ .name = "VirtualList", .pattern = detectLifecyclePattern(VirtualList) },
        .{ .name = "Paragraph", .pattern = detectLifecyclePattern(Paragraph) },
        .{ .name = "Gauge", .pattern = detectLifecyclePattern(Gauge) },
        .{ .name = "Input", .pattern = detectLifecyclePattern(Input) },
    };

    // Count invalid patterns
    var invalid_count: usize = 0;
    for (audits) |audit| {
        if (audit.pattern == .invalid) {
            std.debug.print("INVALID: {s}\n", .{audit.name});
            invalid_count += 1;
        }
    }

    // Once standardization is complete, this should be 0
    try testing.expectEqual(@as(usize, 0), invalid_count);
}

test "allocating widgets handle setText with empty string" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    try editor.setText("");

    // Should have at least one empty line
    try testing.expect(editor.lines.items.len >= 1);
}

test "allocating widgets handle setText with long text" {
    const allocator = testing.allocator;
    var editor = Editor.init(allocator);
    defer editor.deinit();

    const long_text = try allocator.alloc(u8, 10_000);
    defer allocator.free(long_text);

    @memset(long_text, 'x');

    try editor.setText(long_text);

    // Should handle large texts without issues
    try testing.expect(editor.lines.items.len > 0);
}

test "data-driven widgets handle null/optional data" {
    // Table with empty columns/rows
    const empty_cols: []const sailor.tui.widgets.Column = &.{};
    const empty_rows: []const sailor.tui.widgets.Row = &.{};
    const table = Table.init(empty_cols, empty_rows);

    try testing.expectEqual(@as(usize, 0), table.columns.len);
    try testing.expectEqual(@as(usize, 0), table.rows.len);
}

test "lifecycle patterns are documented in widget source" {
    // Each widget should document its lifecycle pattern in comments
    // This is a manual check, but critical for maintainability

    // Example expected documentation:
    // /// Lifecycle: Stateless - no init/deinit needed
    // /// Lifecycle: Allocating - requires init(allocator) and deinit()
    // /// Lifecycle: Data-driven - init with data, no deinit
}

test "no widget mixes lifecycle patterns" {
    // A widget should not be partially allocating
    // Either it allocates (and has deinit) or it doesn't

    // Bad pattern: init() takes allocator but no deinit()
    // Bad pattern: init() doesn't take allocator but has deinit()

    inline for (.{
        Block,
        List,
        Table,
        Tree,
        TextArea,
        VirtualList,
        Paragraph,
        Gauge,
        Editor,
        Input,
    }) |Widget| {
        const pattern = detectLifecyclePattern(Widget);
        if (pattern == .invalid) {
            std.debug.print("\nInvalid lifecycle pattern detected in: {s}\n", .{@typeName(Widget)});
        }
        try testing.expect(pattern != .invalid);
    }
}

test "allocating widgets support clone operation" {
    // Widgets with allocations should provide explicit clone() method
    // to avoid accidental shallow copies

    const allocator = testing.allocator;
    var editor1 = Editor.init(allocator);
    defer editor1.deinit();

    try editor1.setText("Original content");

    // Clone should be explicit and take allocator
    // const editor2 = try editor1.clone(allocator);
    // defer editor2.deinit();

    // Uncomment when clone() is implemented
}

test "widget deinit handles null/uninitialized fields safely" {
    // Deinit should be defensive and handle partially initialized state

    const allocator = testing.allocator;
    var editor = Editor.init(allocator);

    // Even with minimal setup, deinit should work
    editor.deinit();
}

test "no memory leaks in nested widget composition" {
    const allocator = testing.allocator;

    // Complex widgets may compose other widgets
    // Ensure no leaks in the composition chain

    var editor = Editor.init(allocator);
    defer editor.deinit();

    // Editor internally uses ArrayList for lines and undo stack
    try editor.setText("Line 1\nLine 2");
    try editor.insertChar('x');

    // All nested allocations should be freed by editor.deinit()
}

test "virtuallist lifecycle with callback pattern" {
    // VirtualList uses callback for item rendering
    // Ensure callback pattern doesn't introduce lifecycle issues

    const vlist = VirtualList.init(100);
    try testing.expectEqual(@as(usize, 100), vlist.total_items);

    // Callback is stateless function pointer - no lifecycle concerns
    // Rendering happens in Buffer which has its own lifecycle
}
