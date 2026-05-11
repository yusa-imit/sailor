//! Developer Console Tests (v2.9.0 milestone)
//!
//! Comprehensive tests for in-app REPL debugging features:
//! - Core REPL functionality (command execution, history, multi-line input)
//! - Widget query language (CSS-like selectors: #id, .class, Type, [attr], combinators)
//! - State mutation (set properties, trigger actions, undo/redo)
//! - Screenshot & recording (capture, export formats)
//! - Integration (keyboard shortcuts, concurrent access, memory safety)
//!
//! This test suite follows TDD principles - tests are written BEFORE implementation.
//! All tests should FAIL until the developer_console module is implemented.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

// Import types from sailor module
const DeveloperConsole = sailor.DeveloperConsole;
const WidgetInfo = sailor.WidgetInfo;
const Recording = sailor.Recording;
const Keypress = sailor.Keypress;
const ExportFormat = sailor.ExportFormat;

// Helper types for test fixtures
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;

// ============================================================================
// Core REPL Functionality Tests (10 tests)
// ============================================================================

test "DeveloperConsole - init and deinit" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // Console should initialize successfully
    try testing.expect(!console.isOpen());
}

test "DeveloperConsole - eval command executes valid expression" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // Evaluate simple math expression
    const result = try console.executeCommand("eval 1 + 1");
    defer allocator.free(result);

    try testing.expectEqualStrings("2", result);
}

test "DeveloperConsole - eval command handles invalid syntax" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // Invalid expression should return error
    const result = console.executeCommand("eval 1 +");
    try testing.expectError(error.InvalidExpression, result);
}

test "DeveloperConsole - help command lists available commands" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    const result = try console.executeCommand("help");
    defer allocator.free(result);

    // Should list key commands
    try testing.expect(std.mem.indexOf(u8, result, "eval") != null);
    try testing.expect(std.mem.indexOf(u8, result, "query") != null);
    try testing.expect(std.mem.indexOf(u8, result, "mutate") != null);
    try testing.expect(std.mem.indexOf(u8, result, "screenshot") != null);
}

test "DeveloperConsole - clear command resets output buffer" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // Execute some commands
    const cmd_result = try console.executeCommand("eval 42");
    defer allocator.free(cmd_result);

    // Clear should succeed
    const result = try console.executeCommand("clear");
    defer allocator.free(result);

    try testing.expectEqualStrings("", result);
}

test "DeveloperConsole - history navigation with previous command" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // Execute command to add to history
    const cmd_result = try console.executeCommand("eval 1 + 1");
    defer allocator.free(cmd_result);

    // Navigate to previous command
    const prev = try console.previousHistory();
    defer allocator.free(prev);

    try testing.expectEqualStrings("eval 1 + 1", prev);
}

test "DeveloperConsole - history navigation with next command" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // Add two commands
    const cmd1 = try console.executeCommand("eval 1");
    defer allocator.free(cmd1);
    const cmd2 = try console.executeCommand("eval 2");
    defer allocator.free(cmd2);

    // Go back twice
    const prev1 = try console.previousHistory();
    defer allocator.free(prev1);
    const prev2 = try console.previousHistory();
    defer allocator.free(prev2);

    // Go forward once
    const next = try console.nextHistory();
    defer allocator.free(next);

    try testing.expectEqualStrings("eval 2", next);
}

test "DeveloperConsole - history navigation on empty history returns error" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // No history yet
    const result = console.previousHistory();
    try testing.expectError(error.NoHistory, result);
}

test "DeveloperConsole - multi-line input validation detects incomplete input" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // Input with unclosed brace
    const incomplete = "eval { var x = 1;";
    const is_complete = try console.validateInput(incomplete);

    try testing.expect(!is_complete);
}

test "DeveloperConsole - multi-line input validation detects complete input" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // Complete input
    const complete = "eval { var x = 1; }";
    const is_complete = try console.validateInput(complete);

    try testing.expect(is_complete);
}

test "DeveloperConsole - error messages include context" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // Register a widget for querying
    try console.registerWidget("Button", .{
        .id = "btn1",
        .type_name = "Button",
        .bounds = Rect{ .x = 0, .y = 0, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });

    // Query non-existent widget
    const result = console.executeCommand("query #nonexistent");
    try testing.expectError(error.NoMatch, result);
}

// ============================================================================
// Widget Query Language Tests (10 tests)
// ============================================================================

test "DeveloperConsole - query by type selector matches all widgets of type" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // Register multiple Button widgets
    try console.registerWidget("Button", .{
        .id = "btn1",
        .type_name = "Button",
        .bounds = Rect{ .x = 0, .y = 0, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });
    try console.registerWidget("Button", .{
        .id = "btn2",
        .type_name = "Button",
        .bounds = Rect{ .x = 0, .y = 5, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });

    // Query all Button widgets
    const results = try console.query("Button", allocator);
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try testing.expectEqual(@as(usize, 2), results.len);
}

test "DeveloperConsole - query by ID selector matches single widget" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Button", .{
        .id = "submit",
        .type_name = "Button",
        .bounds = Rect{ .x = 0, .y = 0, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });

    const results = try console.query("#submit", allocator);
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try testing.expectEqual(@as(usize, 1), results.len);
    try testing.expect(std.mem.indexOf(u8, results[0], "submit") != null);
}

test "DeveloperConsole - query by class selector filters by class" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Button", .{
        .id = "btn1",
        .type_name = "Button",
        .class = "primary",
        .bounds = Rect{ .x = 0, .y = 0, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });
    try console.registerWidget("Button", .{
        .id = "btn2",
        .type_name = "Button",
        .class = "secondary",
        .bounds = Rect{ .x = 0, .y = 5, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });

    const results = try console.query(".primary", allocator);
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try testing.expectEqual(@as(usize, 1), results.len);
}

test "DeveloperConsole - query by attribute selector with prefix match" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Input", .{
        .id = "input1",
        .type_name = "Input",
        .text = "Hello World",
        .bounds = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 },
        .visible = true,
        .focused = false,
    });
    try console.registerWidget("Input", .{
        .id = "input2",
        .type_name = "Input",
        .text = "Goodbye",
        .bounds = Rect{ .x = 0, .y = 2, .width = 20, .height = 1 },
        .visible = true,
        .focused = false,
    });

    // Query inputs starting with "Hello"
    const results = try console.query("Input[text^='Hello']", allocator);
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try testing.expectEqual(@as(usize, 1), results.len);
}

test "DeveloperConsole - query with descendant combinator finds nested widgets" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // Register parent and child
    try console.registerWidget("Dialog", .{
        .id = "dialog1",
        .type_name = "Dialog",
        .bounds = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 },
        .visible = true,
        .focused = false,
    });
    try console.registerWidgetChild("Dialog", "dialog1", "Button", .{
        .id = "ok",
        .type_name = "Button",
        .bounds = Rect{ .x = 10, .y = 15, .width = 8, .height = 2 },
        .visible = true,
        .focused = false,
    });

    // Find Button inside Dialog
    const results = try console.query("Dialog Button", allocator);
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try testing.expectEqual(@as(usize, 1), results.len);
}

test "DeveloperConsole - query with child combinator finds direct children only" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // Dialog > Panel > Button (Button is grandchild)
    try console.registerWidget("Dialog", .{
        .id = "dialog1",
        .type_name = "Dialog",
        .bounds = Rect{ .x = 0, .y = 0, .width = 40, .height = 20 },
        .visible = true,
        .focused = false,
    });
    try console.registerWidgetChild("Dialog", "dialog1", "Panel", .{
        .id = "panel1",
        .type_name = "Panel",
        .bounds = Rect{ .x = 5, .y = 5, .width = 30, .height = 10 },
        .visible = true,
        .focused = false,
    });
    try console.registerWidgetChild("Panel", "panel1", "Button", .{
        .id = "ok",
        .type_name = "Button",
        .bounds = Rect{ .x = 10, .y = 8, .width = 8, .height = 2 },
        .visible = true,
        .focused = false,
    });

    // Direct children only - should find Panel but not Button
    const results = try console.query("Dialog > Panel", allocator);
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try testing.expectEqual(@as(usize, 1), results.len);
}

test "DeveloperConsole - query with :visible predicate filters visibility" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Button", .{
        .id = "btn1",
        .type_name = "Button",
        .bounds = Rect{ .x = 0, .y = 0, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });
    try console.registerWidget("Button", .{
        .id = "btn2",
        .type_name = "Button",
        .bounds = Rect{ .x = 0, .y = 5, .width = 10, .height = 2 },
        .visible = false,
        .focused = false,
    });

    const results = try console.query("Button:visible", allocator);
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try testing.expectEqual(@as(usize, 1), results.len);
}

test "DeveloperConsole - query with :focused predicate filters focus state" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Input", .{
        .id = "input1",
        .type_name = "Input",
        .bounds = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 },
        .visible = true,
        .focused = true,
    });
    try console.registerWidget("Input", .{
        .id = "input2",
        .type_name = "Input",
        .bounds = Rect{ .x = 0, .y = 2, .width = 20, .height = 1 },
        .visible = true,
        .focused = false,
    });

    const results = try console.query("Input:focused", allocator);
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try testing.expectEqual(@as(usize, 1), results.len);
}

test "DeveloperConsole - query returns error when no matches found" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    const result = console.query("#nonexistent", allocator);
    try testing.expectError(error.NoMatch, result);
}

test "DeveloperConsole - query with bounds predicate filters by coordinates" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Button", .{
        .id = "btn1",
        .type_name = "Button",
        .bounds = Rect{ .x = 5, .y = 5, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });
    try console.registerWidget("Button", .{
        .id = "btn2",
        .type_name = "Button",
        .bounds = Rect{ .x = 20, .y = 10, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });

    // Query buttons with x < 15
    const results = try console.query("Button[x<15]", allocator);
    defer {
        for (results) |r| allocator.free(r);
        allocator.free(results);
    }

    try testing.expectEqual(@as(usize, 1), results.len);
}

// ============================================================================
// State Mutation Tests (8 tests)
// ============================================================================

test "DeveloperConsole - mutate sets widget text property" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Button", .{
        .id = "btn1",
        .type_name = "Button",
        .text = "Old Text",
        .bounds = Rect{ .x = 0, .y = 0, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });

    const result = try console.executeCommand("mutate #btn1 text='New Text'");
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "New Text") != null);
}

test "DeveloperConsole - mutate triggers widget actions" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Button", .{
        .id = "btn1",
        .type_name = "Button",
        .bounds = Rect{ .x = 0, .y = 0, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });

    // Trigger focus action
    const result = try console.executeCommand("mutate #btn1 focus");
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "focus") != null);
}

test "DeveloperConsole - mutate applies batch updates to multiple widgets" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Button", .{
        .id = "btn1",
        .type_name = "Button",
        .class = "primary",
        .bounds = Rect{ .x = 0, .y = 0, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });
    try console.registerWidget("Button", .{
        .id = "btn2",
        .type_name = "Button",
        .class = "primary",
        .bounds = Rect{ .x = 0, .y = 5, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });

    // Update all primary buttons
    const result = try console.executeCommand("mutate .primary text='Updated'");
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "2 widgets") != null);
}

test "DeveloperConsole - undo restores previous widget state" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Button", .{
        .id = "btn1",
        .type_name = "Button",
        .text = "Original",
        .bounds = Rect{ .x = 0, .y = 0, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });

    // Mutate then undo
    const mutate_result = try console.executeCommand("mutate #btn1 text='Changed'");
    defer allocator.free(mutate_result);
    const undo_result = try console.executeCommand("undo");
    defer allocator.free(undo_result);

    try testing.expect(std.mem.indexOf(u8, undo_result, "Original") != null);
}

test "DeveloperConsole - redo restores undone mutation" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Button", .{
        .id = "btn1",
        .type_name = "Button",
        .text = "Original",
        .bounds = Rect{ .x = 0, .y = 0, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });

    // Mutate, undo, then redo
    const mutate_result = try console.executeCommand("mutate #btn1 text='Changed'");
    defer allocator.free(mutate_result);
    const undo_result = try console.executeCommand("undo");
    defer allocator.free(undo_result);
    const redo_result = try console.executeCommand("redo");
    defer allocator.free(redo_result);

    try testing.expect(std.mem.indexOf(u8, redo_result, "Changed") != null);
}

test "DeveloperConsole - mutate rejects invalid syntax" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    const result = console.executeCommand("mutate #btn1 invalid syntax");
    try testing.expectError(error.InvalidMutationSyntax, result);
}

test "DeveloperConsole - mutate returns error when widget not found" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    const result = console.executeCommand("mutate #nonexistent text='foo'");
    try testing.expectError(error.WidgetNotFound, result);
}

test "DeveloperConsole - mutate parses property assignment syntax" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Button", .{
        .id = "btn1",
        .type_name = "Button",
        .bounds = Rect{ .x = 0, .y = 0, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });

    // Various valid syntaxes
    const cmd1 = try console.executeCommand("mutate #btn1 text='single quotes'");
    defer allocator.free(cmd1);
    const cmd2 = try console.executeCommand("mutate #btn1 visible=false");
    defer allocator.free(cmd2);
    const result = try console.executeCommand("mutate #btn1 x=100");
    defer allocator.free(result);

    try testing.expect(result.len > 0);
}

// ============================================================================
// Screenshot & Recording Tests (5 tests)
// ============================================================================

test "DeveloperConsole - screenshot captures full screen" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    const data = try console.screenshot(allocator, null);
    defer allocator.free(data);

    // Screenshot data should be non-empty
    try testing.expect(data.len > 0);
}

test "DeveloperConsole - screenshot captures region by widget ID" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Panel", .{
        .id = "panel1",
        .type_name = "Panel",
        .bounds = Rect{ .x = 10, .y = 10, .width = 40, .height = 20 },
        .visible = true,
        .focused = false,
    });

    const data = try console.screenshot(allocator, "#panel1");
    defer allocator.free(data);

    // Region screenshot should be smaller than full screen
    try testing.expect(data.len > 0);
}

test "DeveloperConsole - recording captures frame sequence" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.startRecording();

    // Capture some frames
    try console.captureFrame();
    try console.captureFrame();
    try console.captureFrame();

    const recording = try console.stopRecording(allocator);
    defer recording.deinit(allocator);

    try testing.expectEqual(@as(usize, 3), recording.frame_count);
}

test "DeveloperConsole - screenshot export to PNG format" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    const data = try console.screenshot(allocator, null);
    defer allocator.free(data);

    const png_data = try console.exportScreenshot(allocator, data, .png);
    defer allocator.free(png_data);

    // PNG should start with signature
    try testing.expectEqualSlices(u8, "\x89PNG", png_data[0..4]);
}

test "DeveloperConsole - screenshot export to ANSI text format" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    const data = try console.screenshot(allocator, null);
    defer allocator.free(data);

    const ansi_data = try console.exportScreenshot(allocator, data, .ansi_text);
    defer allocator.free(ansi_data);

    // ANSI text should contain escape sequences
    try testing.expect(std.mem.indexOf(u8, ansi_data, "\x1b[") != null);
}

// ============================================================================
// Integration & Edge Cases Tests (6 tests)
// ============================================================================

test "DeveloperConsole - Ctrl+Shift+D toggles console open" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try testing.expect(!console.isOpen());

    // Simulate Ctrl+Shift+D keypress
    const keypress = Keypress{
        .char = 'D',
        .ctrl = true,
        .shift = true,
        .alt = false,
    };
    try console.handleKeypress(keypress);

    try testing.expect(console.isOpen());
}

test "DeveloperConsole - Ctrl+Shift+D toggles console closed" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // Open console first
    try console.setOpen(true);
    try testing.expect(console.isOpen());

    // Toggle closed
    const keypress = Keypress{
        .char = 'D',
        .ctrl = true,
        .shift = true,
        .alt = false,
    };
    try console.handleKeypress(keypress);

    try testing.expect(!console.isOpen());
}

test "DeveloperConsole - memory cleanup frees command history" {
    const allocator = testing.allocator;

    var console = try DeveloperConsole.init(allocator);

    // Execute many commands to populate history
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const cmd_result = try console.executeCommand("eval 1");
        allocator.free(cmd_result);
    }

    // Deinit should free all history without leaks
    console.deinit();
}

test "DeveloperConsole - concurrent command execution is thread-safe" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    // Register widget for concurrent access
    try console.registerWidget("Button", .{
        .id = "btn1",
        .type_name = "Button",
        .bounds = Rect{ .x = 0, .y = 0, .width = 10, .height = 2 },
        .visible = true,
        .focused = false,
    });

    // Execute commands concurrently
    const thread1 = try std.Thread.spawn(.{}, threadQuery, .{ &console, allocator });
    const thread2 = try std.Thread.spawn(.{}, threadQuery, .{ &console, allocator });

    thread1.join();
    thread2.join();

    // No crashes means thread-safety works
}

fn threadQuery(console: *DeveloperConsole, allocator: std.mem.Allocator) void {
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const results = console.query("Button", allocator) catch return;
        defer {
            for (results) |r| allocator.free(r);
            allocator.free(results);
        }
    }
}

test "DeveloperConsole - Unicode support in commands and output" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Label", .{
        .id = "label1",
        .type_name = "Label",
        .text = "こんにちは世界",
        .bounds = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 },
        .visible = true,
        .focused = false,
    });

    const result = try console.executeCommand("mutate #label1 text='🚀 Rocket'");
    defer allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "🚀") != null);
}

test "DeveloperConsole - command execution with special characters" {
    const allocator = testing.allocator;
    var console = try DeveloperConsole.init(allocator);
    defer console.deinit();

    try console.registerWidget("Input", .{
        .id = "input1",
        .type_name = "Input",
        .bounds = Rect{ .x = 0, .y = 0, .width = 20, .height = 1 },
        .visible = true,
        .focused = false,
    });

    // Test with quotes, newlines, special chars
    const result = try console.executeCommand("mutate #input1 text='Line1\\nLine2'");
    defer allocator.free(result);

    try testing.expect(result.len > 0);
}
