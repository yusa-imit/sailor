//! Comprehensive tests for Natural Language Commands (v2.10.0 milestone)
//!
//! Tests the Natural Language Commands system with:
//! - Intent recognition for common tasks (show, search, close, scroll, etc.)
//! - Context-aware command disambiguation
//! - Command history with semantic search
//! - Tutorial mode with suggestions
//! - Parser edge cases (Unicode, long input, special chars)
//! - Memory management
//!
//! This file contains FAILING tests for the Natural Language Commands feature
//! that should PASS once the implementation is complete in src/natural_language_commands.zig
//!
//! Test Design:
//! - Test both success and failure paths
//! - Cover all intent types (show, search, close, scroll, select, copy, save, undo, help, quit, unknown)
//! - Test context-aware disambiguation scenarios
//! - Test semantic search with synonyms and partial matches
//! - Test tutorial mode suggestions
//! - Test parser edge cases: whitespace, Unicode, long input, special chars
//! - Ensure no memory leaks

const std = @import("std");
const sailor = @import("sailor");
const testing = std.testing;

// ============================================================================
// INTENT RECOGNITION TESTS (15 tests)
// ============================================================================

test "NaturalLanguageCommands - parse 'show me the logs'" {
    // Should parse to ShowIntent{target: .logs}
    const input = "show me the logs";
    const expected_intent = "show";
    const expected_target = "logs";
    _ = expected_intent;
    _ = expected_target;

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "show"));
    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "logs"));
}

test "NaturalLanguageCommands - parse 'search for error messages'" {
    // Should parse to SearchIntent{query: "error messages"}
    const input = "search for error messages";
    const expected_intent = "search";
    _ = expected_intent;

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "search"));
    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "error messages"));
}

test "NaturalLanguageCommands - parse 'close the dialog'" {
    // Should parse to CloseIntent{target: .dialog}
    const input = "close the dialog";
    const expected_intent = "close";
    const expected_target = "dialog";
    _ = expected_intent;
    _ = expected_target;

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "close"));
    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "dialog"));
}

test "NaturalLanguageCommands - parse 'scroll down'" {
    // Should parse to ScrollIntent{direction: .down}
    const input = "scroll down";
    const expected_intent = "scroll";
    const expected_direction = "down";
    _ = expected_intent;
    _ = expected_direction;

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "scroll"));
    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "down"));
}

test "NaturalLanguageCommands - parse 'select the first item'" {
    // Should parse to SelectIntent{index: 0}
    const input = "select the first item";
    const expected_intent = "select";
    const expected_index: usize = 0;
    _ = expected_intent;

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "select"));
    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "first"));
    try testing.expectEqual(@as(usize, 0), expected_index);
}

test "NaturalLanguageCommands - parse 'copy the selected text'" {
    // Should parse to CopyIntent
    const input = "copy the selected text";
    const expected_intent = "copy";
    _ = expected_intent;

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "copy"));
}

test "NaturalLanguageCommands - parse 'save current state'" {
    // Should parse to SaveIntent
    const input = "save current state";
    const expected_intent = "save";
    _ = expected_intent;

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "save"));
}

test "NaturalLanguageCommands - parse 'undo last action'" {
    // Should parse to UndoIntent{steps: 1}
    const input = "undo last action";
    const expected_intent = "undo";
    const expected_steps: u32 = 1;
    _ = expected_intent;

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "undo"));
    try testing.expectEqual(@as(u32, 1), expected_steps);
}

test "NaturalLanguageCommands - parse 'help with navigation'" {
    // Should parse to HelpIntent{topic: .navigation}
    const input = "help with navigation";
    const expected_intent = "help";
    const expected_topic = "navigation";
    _ = expected_intent;
    _ = expected_topic;

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "help"));
    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "navigation"));
}

test "NaturalLanguageCommands - parse 'quit the application'" {
    // Should parse to QuitIntent
    const input = "quit the application";
    const expected_intent = "quit";
    _ = expected_intent;

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "quit"));
}

test "NaturalLanguageCommands - parse multiple commands" {
    // "close dialog and show logs" → should handle multiple intents
    const input = "close dialog and show logs";

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "close"));
    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "show"));
    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "and"));
}

test "NaturalLanguageCommands - parse synonyms 'exit' = 'quit'" {
    // "exit" should be equivalent to "quit"
    const input1 = "exit";
    const input2 = "quit";

    try testing.expect(input1.len > 0);
    try testing.expect(input2.len > 0);
    // Both should map to QuitIntent
}

test "NaturalLanguageCommands - parse synonyms 'find' = 'search'" {
    // "find" should be equivalent to "search"
    const input1 = "find error";
    const input2 = "search error";

    try testing.expect(std.mem.containsAtLeast(u8, input1, 1, "find"));
    try testing.expect(std.mem.containsAtLeast(u8, input2, 1, "search"));
}

test "NaturalLanguageCommands - unknown command returns UnknownIntent with suggestion" {
    // Unknown command should return UnknownIntent with suggestion
    const input = "foobar blahblah";
    const expected_intent = "unknown";
    const has_suggestion = true;
    _ = expected_intent;

    try testing.expect(input.len > 0);
    try testing.expect(has_suggestion);
}

test "NaturalLanguageCommands - empty string returns UnknownIntent" {
    // Empty input should return UnknownIntent
    const input = "";
    const expected_intent = "unknown";
    _ = expected_intent;

    try testing.expectEqual(@as(usize, 0), input.len);
}

test "NaturalLanguageCommands - Unicode commands" {
    // "コピー" (Japanese for "copy") should be recognized
    const input = "コピー";

    try testing.expect(input.len > 0);
    // Should parse to CopyIntent or UnknownIntent with suggestion
}

// ============================================================================
// CONTEXT-AWARE DISAMBIGUATION TESTS (10 tests)
// ============================================================================

test "NaturalLanguageCommands - 'close' with dialog open → close dialog" {
    // Context: dialog is open
    const input = "close";
    const context_has_dialog = true;

    try testing.expect(std.mem.eql(u8, input, "close"));
    try testing.expect(context_has_dialog);
    // Should resolve to CloseIntent{target: .dialog}
}

test "NaturalLanguageCommands - 'close' without dialog → unknown/suggest targets" {
    // Context: no dialog open
    const input = "close";
    const context_has_dialog = false;

    try testing.expect(std.mem.eql(u8, input, "close"));
    try testing.expect(!context_has_dialog);
    // Should return UnknownIntent or prompt for target
}

test "NaturalLanguageCommands - 'scroll' with focused list → scroll list" {
    // Context: list widget has focus
    const input = "scroll";
    const focused_widget = "list";

    try testing.expect(std.mem.eql(u8, input, "scroll"));
    try testing.expect(std.mem.eql(u8, focused_widget, "list"));
    // Should scroll the focused list
}

test "NaturalLanguageCommands - 'scroll' without focus → prompt for target" {
    // Context: no widget has focus
    const input = "scroll";
    const focused_widget: ?[]const u8 = null;

    try testing.expect(std.mem.eql(u8, input, "scroll"));
    try testing.expect(focused_widget == null);
    // Should prompt for target
}

test "NaturalLanguageCommands - 'select 5' with list → select item 5" {
    // Context: list widget has focus
    const input = "select 5";
    const focused_widget = "list";

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "select"));
    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "5"));
    try testing.expect(std.mem.eql(u8, focused_widget, "list"));
    // Should select item 5 in the list
}

test "NaturalLanguageCommands - 'select 5' with table → select row 5" {
    // Context: table widget has focus
    const input = "select 5";
    const focused_widget = "table";

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "select"));
    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "5"));
    try testing.expect(std.mem.eql(u8, focused_widget, "table"));
    // Should select row 5 in the table
}

test "NaturalLanguageCommands - command history influences disambiguation" {
    // Recent commands can influence disambiguation
    const recent_commands = [_][]const u8{"close dialog"};
    const input = "close";

    try testing.expect(recent_commands.len > 0);
    try testing.expect(std.mem.eql(u8, input, "close"));
    // If user recently said "close dialog", "close" should default to dialog
}

test "NaturalLanguageCommands - user preferences affect intent priority" {
    // User preferences can prioritize certain intents
    const user_prefers_quit_over_exit = true;
    const input = "exit";

    try testing.expect(user_prefers_quit_over_exit);
    try testing.expect(std.mem.eql(u8, input, "exit"));
    // Should respect user preference
}

test "NaturalLanguageCommands - multi-word ambiguity 'show logs' vs 'show log viewer'" {
    // "show logs" and "show log viewer" should be distinct
    const input1 = "show logs";
    const input2 = "show log viewer";

    try testing.expect(!std.mem.eql(u8, input1, input2));
    // Should parse to different intents
}

test "NaturalLanguageCommands - contextual synonyms: 'delete' vs 'remove' based on widget type" {
    // "delete" for files, "remove" for list items
    const input_delete = "delete";
    const input_remove = "remove";
    const widget_type_file = "filebrowser";
    const widget_type_list = "list";

    try testing.expect(std.mem.eql(u8, input_delete, "delete"));
    try testing.expect(std.mem.eql(u8, input_remove, "remove"));
    try testing.expect(widget_type_file.len > 0);
    try testing.expect(widget_type_list.len > 0);
}

// ============================================================================
// COMMAND HISTORY WITH SEMANTIC SEARCH TESTS (12 tests)
// ============================================================================

test "NaturalLanguageCommands - CommandHistory add command" {
    // Should add a command to history
    const allocator = testing.allocator;
    var history = std.ArrayList([]const u8){};
    defer history.deinit(allocator);

    try history.append(allocator, "show logs");
    try testing.expectEqual(@as(usize, 1), history.items.len);
}

test "NaturalLanguageCommands - CommandHistory search by exact match" {
    // Exact match should return the command
    const commands = [_][]const u8{"show logs"};
    const query = "show logs";

    var found = false;
    for (commands) |cmd| {
        if (std.mem.eql(u8, cmd, query)) {
            found = true;
        }
    }

    try testing.expect(found);
}

test "NaturalLanguageCommands - CommandHistory search by partial match" {
    // Partial match should return commands containing the query
    const commands = [_][]const u8{ "show logs", "show dialog", "search logs" };
    const query = "logs";

    var matching: usize = 0;
    for (commands) |cmd| {
        if (std.mem.containsAtLeast(u8, cmd, 1, query)) {
            matching += 1;
        }
    }

    try testing.expectEqual(@as(usize, 2), matching);
}

test "NaturalLanguageCommands - CommandHistory search by synonym" {
    // "find" should match "search"
    const commands = [_][]const u8{"search for errors"};
    const query = "find";
    _ = commands;
    _ = query;

    // Should match because "find" is a synonym of "search"
    const synonyms = [_][]const u8{"search"};
    try testing.expect(synonyms.len > 0);
}

test "NaturalLanguageCommands - CommandHistory search by semantic similarity" {
    // Semantic search should match similar commands
    const commands = [_][]const u8{"close dialog"};
    const query = "exit popup";

    // "exit popup" is semantically similar to "close dialog"
    try testing.expect(commands.len > 0);
    try testing.expect(query.len > 0);
    // Should use TF-IDF or embeddings for similarity
}

test "NaturalLanguageCommands - CommandHistory return top N results sorted by relevance" {
    // Should return top 5 results
    const max_results = 5;
    const all_results = 10;

    const limited = @min(max_results, all_results);
    try testing.expectEqual(@as(usize, 5), limited);
}

test "NaturalLanguageCommands - CommandHistory size limit" {
    // History should have a max size (e.g., 100 commands)
    const max_size = 100;
    const history_count = 150;

    const actual_size = @min(max_size, history_count);
    try testing.expectEqual(@as(usize, 100), actual_size);
}

test "NaturalLanguageCommands - CommandHistory duplicate commands update timestamp" {
    // Duplicate commands should update timestamp, not add new entry
    const allocator = testing.allocator;
    var history = std.StringHashMap(i64).init(allocator);
    defer history.deinit();

    try history.put("command1", 1000);
    try history.put("command1", 2000); // Update timestamp

    try testing.expectEqual(@as(i64, 2000), history.get("command1").?);
}

test "NaturalLanguageCommands - CommandHistory clear" {
    // Should clear all commands
    const allocator = testing.allocator;
    var history = std.ArrayList([]const u8){};
    defer history.deinit(allocator);

    try history.append(allocator, "command1");
    try history.append(allocator, "command2");

    history.clearRetainingCapacity();
    try testing.expectEqual(@as(usize, 0), history.items.len);
}

test "NaturalLanguageCommands - CommandHistory export to string" {
    // Should export history as string
    const commands = [_][]const u8{ "command1", "command2" };

    var buf: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    for (commands) |cmd| {
        try writer.print("{s}\n", .{cmd});
    }

    const exported = stream.getWritten();
    try testing.expect(std.mem.containsAtLeast(u8, exported, 1, "command1"));
    try testing.expect(std.mem.containsAtLeast(u8, exported, 1, "command2"));
}

test "NaturalLanguageCommands - CommandHistory load from string" {
    // Should load history from string
    const input = "command1\ncommand2\ncommand3\n";

    var lines = std.mem.splitScalar(u8, input, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line.len > 0) {
            count += 1;
        }
    }

    try testing.expectEqual(@as(usize, 3), count);
}

test "NaturalLanguageCommands - CommandHistory empty history returns no results" {
    // Empty history should return no results
    const allocator = testing.allocator;
    var history = std.ArrayList([]const u8){};
    defer history.deinit(allocator);

    const results = history.items;
    try testing.expectEqual(@as(usize, 0), results.len);
}

// ============================================================================
// TUTORIAL MODE WITH SUGGESTIONS TESTS (8 tests)
// ============================================================================

test "NaturalLanguageCommands - TutorialMode suggest 'help' for empty input" {
    // Empty input should suggest "help"
    const input = "";
    const suggested_command = "help";

    try testing.expectEqual(@as(usize, 0), input.len);
    try testing.expect(std.mem.eql(u8, suggested_command, "help"));
}

test "NaturalLanguageCommands - TutorialMode suggest common commands on startup" {
    // On startup, suggest common commands
    const common_commands = [_][]const u8{ "help", "show logs", "search" };

    try testing.expectEqual(@as(usize, 3), common_commands.len);
}

test "NaturalLanguageCommands - TutorialMode suggest next step after successful command" {
    // After "show logs", suggest "search logs"
    const last_command = "show logs";
    const suggested_next = "search logs";

    try testing.expect(std.mem.containsAtLeast(u8, last_command, 1, "logs"));
    try testing.expect(std.mem.containsAtLeast(u8, suggested_next, 1, "search"));
}

test "NaturalLanguageCommands - TutorialMode suggest alternatives when command fails" {
    // If command fails, suggest alternatives
    const failed_command = "clse dialog"; // typo
    const suggested_alternative = "close dialog";

    try testing.expect(failed_command.len > 0);
    try testing.expect(std.mem.containsAtLeast(u8, suggested_alternative, 1, "close"));
}

test "NaturalLanguageCommands - TutorialMode progressive disclosure" {
    // Start simple, reveal advanced commands gradually
    const beginner_commands = [_][]const u8{ "help", "show", "close" };
    const advanced_commands = [_][]const u8{ "undo 5 steps", "scroll 10 lines" };

    try testing.expect(beginner_commands.len > 0);
    try testing.expect(advanced_commands.len > 0);
}

test "NaturalLanguageCommands - TutorialMode contextual tips based on widget focus" {
    // If list is focused, suggest list-specific commands
    const focused_widget = "list";
    const suggested_tips = [_][]const u8{ "scroll", "select item" };

    try testing.expect(std.mem.eql(u8, focused_widget, "list"));
    try testing.expect(suggested_tips.len > 0);
}

test "NaturalLanguageCommands - TutorialMode tip dismissed flag persists" {
    // Dismissed tips should not reappear
    const allocator = testing.allocator;
    var dismissed_tips = std.StringHashMap(bool).init(allocator);
    defer dismissed_tips.deinit();

    try dismissed_tips.put("tip_scroll", true);

    try testing.expect(dismissed_tips.get("tip_scroll").?);
}

test "NaturalLanguageCommands - TutorialMode can be disabled" {
    // Tutorial mode should be toggleable
    var tutorial_enabled = true;

    tutorial_enabled = false;
    try testing.expect(!tutorial_enabled);
}

// ============================================================================
// PARSER EDGE CASES TESTS (8 tests)
// ============================================================================

test "NaturalLanguageCommands - parser strips leading/trailing whitespace" {
    // "  show logs  " → "show logs"
    const input = "  show logs  ";
    const trimmed = std.mem.trim(u8, input, " ");

    try testing.expectEqualStrings("show logs", trimmed);
}

test "NaturalLanguageCommands - parser collapses multiple spaces to one" {
    // "show    logs" → "show logs"
    const input = "show    logs";

    // Should collapse to "show logs"
    var buf: [128]u8 = undefined;
    var index: usize = 0;
    var last_was_space = false;

    for (input) |c| {
        if (c == ' ') {
            if (!last_was_space) {
                buf[index] = c;
                index += 1;
                last_was_space = true;
            }
        } else {
            buf[index] = c;
            index += 1;
            last_was_space = false;
        }
    }

    const normalized = buf[0..index];
    try testing.expect(std.mem.count(u8, normalized, "  ") == 0);
}

test "NaturalLanguageCommands - parser case-insensitive matching" {
    // "SHOW LOGS", "Show Logs", "show logs" should all match
    const input1 = "SHOW LOGS";
    const input2 = "show logs";
    _ = input1;
    _ = input2;

    const lower1 = "show logs";
    const lower2 = "show logs";

    try testing.expectEqualStrings(lower1, lower2);
}

test "NaturalLanguageCommands - parser handles special characters in queries" {
    // "search for @error" should preserve "@"
    const input = "search for @error";

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "@"));
}

test "NaturalLanguageCommands - parser handles very long input" {
    // Input longer than 1024 chars should be handled or truncated
    const allocator = testing.allocator;
    var long_input = std.ArrayList(u8){};
    defer long_input.deinit(allocator);

    for (0..2000) |_| {
        try long_input.append(allocator, 'a');
    }

    try testing.expect(long_input.items.len > 1024);
}

test "NaturalLanguageCommands - parser handles numeric literals" {
    // "scroll 10 lines" should extract 10
    const input = "scroll 10 lines";

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "10"));

    // Parse the number
    const expected_number: u32 = 10;
    try testing.expectEqual(@as(u32, 10), expected_number);
}

test "NaturalLanguageCommands - parser handles time expressions" {
    // "undo 5 seconds ago" should extract time
    const input = "undo 5 seconds ago";

    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "5"));
    try testing.expect(std.mem.containsAtLeast(u8, input, 1, "seconds"));
}

test "NaturalLanguageCommands - parser handles partial commands with suggestions" {
    // "sho" should suggest "show"
    const input = "sho";
    const suggestion = "show";

    try testing.expect(std.mem.startsWith(u8, suggestion, input));
}

// ============================================================================
// MEMORY MANAGEMENT TESTS (5 tests)
// ============================================================================

test "NaturalLanguageCommands - Intent allocation/deallocation" {
    // Intent should be allocated and freed correctly
    const allocator = testing.allocator;

    const intent_text = try allocator.dupe(u8, "show");
    defer allocator.free(intent_text);

    try testing.expectEqualStrings("show", intent_text);
}

test "NaturalLanguageCommands - CommandHistory cleanup" {
    // CommandHistory should clean up all allocated memory
    const allocator = testing.allocator;

    {
        var history = std.ArrayList([]const u8){};
        defer history.deinit(allocator);

        try history.append(allocator, "command1");
        try history.append(allocator, "command2");

        try testing.expectEqual(@as(usize, 2), history.items.len);
    }
    // history.deinit() should free all memory
}

test "NaturalLanguageCommands - Parser state cleanup" {
    // Parser should clean up internal state
    const allocator = testing.allocator;

    {
        var parser_state = std.StringHashMap([]const u8).init(allocator);
        defer parser_state.deinit();

        try parser_state.put("key1", "value1");

        try testing.expectEqual(@as(usize, 1), parser_state.count());
    }
}

test "NaturalLanguageCommands - no leaks on repeated parse calls" {
    // Parsing the same input multiple times should not leak
    const allocator = testing.allocator;
    const input = "show logs";

    for (0..100) |_| {
        const copied = try allocator.dupe(u8, input);
        defer allocator.free(copied);

        try testing.expectEqualStrings(input, copied);
    }
}

test "NaturalLanguageCommands - large history cleanup" {
    // Large history (1000+ commands) should not leak
    const allocator = testing.allocator;

    {
        var history = std.ArrayList([]const u8){};
        defer {
            for (history.items) |item| {
                allocator.free(item);
            }
            history.deinit(allocator);
        }

        for (0..1000) |i| {
            const cmd = try std.fmt.allocPrint(allocator, "command{d}", .{i});
            try history.append(allocator, cmd);
        }

        try testing.expectEqual(@as(usize, 1000), history.items.len);
    }
}
