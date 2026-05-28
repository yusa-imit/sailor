//! Comprehensive tests for sailor's Undo/Redo middleware (v2.13.0)
//!
//! Tests for UndoStore(State, Action) - undo/redo capability with state history.
//!
//! Coverage:
//! - UndoStore init with history limit
//! - UndoStore dispatch adds to history
//! - UndoStore undo() restores previous state
//! - UndoStore redo() restores next state
//! - canUndo() returns false when at start
//! - canRedo() returns false when at end
//! - Multiple undo/redo sequences
//! - Undo at initial state returns false
//! - Redo at latest state returns false
//! - History limit prevents excessive memory
//! - New dispatch clears redo history
//! - getState() always returns current state
//! - Subscribers notified on undo/redo
//! - Complex state types with history
//! - Edge case: undo all, then new dispatch

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");
const store_mod = sailor.store;

// ============================================================================
// Example State & Action Types
// ============================================================================

const EditorState = struct {
    text: []const u8,
    cursor_pos: u32,
    line_count: u32,
};

const EditorAction = union(enum) {
    insert: []const u8,
    delete,
    move_cursor: u32,
    clear,
};

fn editorReducer(state: EditorState, action: EditorAction, allocator: std.mem.Allocator) !EditorState {
    _ = allocator;
    switch (action) {
        .insert => |text| return .{
            .text = text,
            .cursor_pos = state.cursor_pos + 1,
            .line_count = state.line_count,
        },
        .delete => return .{
            .text = if (state.text.len > 0) state.text[0 .. state.text.len - 1] else "",
            .cursor_pos = if (state.cursor_pos > 0) state.cursor_pos - 1 else 0,
            .line_count = state.line_count,
        },
        .move_cursor => |pos| return .{
            .text = state.text,
            .cursor_pos = pos,
            .line_count = state.line_count,
        },
        .clear => return .{
            .text = "",
            .cursor_pos = 0,
            .line_count = 0,
        },
    }
}

// ============================================================================
// UndoStore Lifecycle Tests
// ============================================================================

test "UndoStore init creates with initial state" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        100, // history_limit
    );
    defer undo_store.deinit(allocator);

    const state = undo_store.getState();
    try testing.expectEqualStrings("", state.text);
    try testing.expectEqual(@as(u32, 0), state.cursor_pos);
}

test "UndoStore deinit cleans up memory" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );

    undo_store.deinit(allocator);
    // testing.allocator detects leaks automatically
}

// ============================================================================
// Dispatch & History Tests
// ============================================================================

test "UndoStore dispatch adds state to history" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    try undo_store.dispatch(EditorAction{ .insert = "hello" });

    const state = undo_store.getState();
    try testing.expectEqualStrings("hello", state.text);
}

test "UndoStore canUndo false at initial state" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    try testing.expectEqual(false, undo_store.canUndo());
}

test "UndoStore canUndo true after dispatch" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    try undo_store.dispatch(EditorAction{ .insert = "hello" });

    try testing.expectEqual(true, undo_store.canUndo());
}

// ============================================================================
// Undo Tests
// ============================================================================

test "UndoStore undo restores previous state" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    try undo_store.dispatch(EditorAction{ .insert = "hello" });
    try testing.expectEqualStrings("hello", undo_store.getState().text);

    const result = undo_store.undo();
    try testing.expectEqual(true, result);
    try testing.expectEqualStrings("", undo_store.getState().text);
}

test "UndoStore undo returns false at initial state" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    const result = undo_store.undo();
    try testing.expectEqual(false, result);
}

test "UndoStore multiple undo operations" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    try undo_store.dispatch(EditorAction{ .insert = "a" });
    try undo_store.dispatch(EditorAction{ .insert = "b" });
    try undo_store.dispatch(EditorAction{ .insert = "c" });

    try testing.expectEqualStrings("c", undo_store.getState().text);

    _ = undo_store.undo();
    try testing.expectEqualStrings("b", undo_store.getState().text);

    _ = undo_store.undo();
    try testing.expectEqualStrings("a", undo_store.getState().text);

    _ = undo_store.undo();
    try testing.expectEqualStrings("", undo_store.getState().text);
}

// ============================================================================
// Redo Tests
// ============================================================================

test "UndoStore canRedo false at latest state" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    try testing.expectEqual(false, undo_store.canRedo());
}

test "UndoStore canRedo true after undo" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    try undo_store.dispatch(EditorAction{ .insert = "hello" });
    _ = undo_store.undo();

    try testing.expectEqual(true, undo_store.canRedo());
}

test "UndoStore redo restores next state" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    try undo_store.dispatch(EditorAction{ .insert = "hello" });
    _ = undo_store.undo();

    try testing.expectEqualStrings("", undo_store.getState().text);

    const result = undo_store.redo();
    try testing.expectEqual(true, result);
    try testing.expectEqualStrings("hello", undo_store.getState().text);
}

test "UndoStore redo returns false at latest state" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    const result = undo_store.redo();
    try testing.expectEqual(false, result);
}

test "UndoStore multiple redo operations" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    try undo_store.dispatch(EditorAction{ .insert = "a" });
    try undo_store.dispatch(EditorAction{ .insert = "b" });
    try undo_store.dispatch(EditorAction{ .insert = "c" });

    _ = undo_store.undo();
    _ = undo_store.undo();
    _ = undo_store.undo();

    try testing.expectEqualStrings("", undo_store.getState().text);

    _ = undo_store.redo();
    try testing.expectEqualStrings("a", undo_store.getState().text);

    _ = undo_store.redo();
    try testing.expectEqualStrings("b", undo_store.getState().text);

    _ = undo_store.redo();
    try testing.expectEqualStrings("c", undo_store.getState().text);
}

// ============================================================================
// Undo/Redo Sequence Tests
// ============================================================================

test "UndoStore undo then dispatch clears redo" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    try undo_store.dispatch(EditorAction{ .insert = "a" });
    try undo_store.dispatch(EditorAction{ .insert = "b" });

    _ = undo_store.undo();
    try testing.expectEqual(true, undo_store.canRedo());

    try undo_store.dispatch(EditorAction{ .insert = "c" });
    try testing.expectEqual(false, undo_store.canRedo());

    const state = undo_store.getState();
    try testing.expectEqualStrings("c", state.text);
}

test "UndoStore complex undo/redo sequence" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    // dispatch a, b
    try undo_store.dispatch(EditorAction{ .insert = "a" });
    try undo_store.dispatch(EditorAction{ .insert = "b" });

    // undo b
    _ = undo_store.undo();
    try testing.expectEqualStrings("a", undo_store.getState().text);

    // undo a
    _ = undo_store.undo();
    try testing.expectEqualStrings("", undo_store.getState().text);

    // redo a
    _ = undo_store.redo();
    try testing.expectEqualStrings("a", undo_store.getState().text);

    // dispatch c (should clear redo history)
    try undo_store.dispatch(EditorAction{ .insert = "c" });
    try testing.expectEqual(false, undo_store.canRedo());

    // undo c -> a
    _ = undo_store.undo();
    try testing.expectEqualStrings("a", undo_store.getState().text);
}

// ============================================================================
// History Limit Tests
// ============================================================================

test "UndoStore respects history limit" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    const history_limit = 3;
    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        history_limit,
    );
    defer undo_store.deinit(allocator);

    // Dispatch 5 times (exceeds limit of 3)
    try undo_store.dispatch(EditorAction{ .insert = "a" });
    try undo_store.dispatch(EditorAction{ .insert = "b" });
    try undo_store.dispatch(EditorAction{ .insert = "c" });
    try undo_store.dispatch(EditorAction{ .insert = "d" });
    try undo_store.dispatch(EditorAction{ .insert = "e" });

    // Now undo as much as possible
    var undo_count: u32 = 0;
    while (undo_store.undo()) {
        undo_count += 1;
    }

    // Should only be able to undo ~3 times due to history limit
    try testing.expectEqual(true, undo_count <= history_limit);
}

// ============================================================================
// Subscriber Notification Tests
// ============================================================================

test "UndoStore notifies subscribers on dispatch" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    var notification_count: i32 = 0;
    const notify = struct {
        fn callback(_: EditorState, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    _ = try undo_store.subscribe(&notification_count, notify);

    try undo_store.dispatch(EditorAction{ .insert = "hello" });
    try testing.expectEqual(@as(i32, 1), notification_count);
}

test "UndoStore notifies subscribers on undo" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    var notification_count: i32 = 0;
    const notify = struct {
        fn callback(_: EditorState, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    _ = try undo_store.subscribe(&notification_count, notify);

    try undo_store.dispatch(EditorAction{ .insert = "hello" });
    try testing.expectEqual(@as(i32, 1), notification_count);

    _ = undo_store.undo();
    try testing.expectEqual(@as(i32, 2), notification_count);
}

test "UndoStore notifies subscribers on redo" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    var notification_count: i32 = 0;
    const notify = struct {
        fn callback(_: EditorState, ctx: ?*anyopaque) void {
            const ptr: *i32 = @ptrCast(@alignCast(ctx.?));
            ptr.* += 1;
        }
    }.callback;

    _ = try undo_store.subscribe(&notification_count, notify);

    try undo_store.dispatch(EditorAction{ .insert = "hello" });
    _ = undo_store.undo();
    try testing.expectEqual(@as(i32, 2), notification_count);

    _ = undo_store.redo();
    try testing.expectEqual(@as(i32, 3), notification_count);
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "UndoStore clear action followed by undo" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "initial",
        .cursor_pos = 7,
        .line_count = 1,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    try testing.expectEqualStrings("initial", undo_store.getState().text);

    try undo_store.dispatch(.clear);
    try testing.expectEqualStrings("", undo_store.getState().text);

    _ = undo_store.undo();
    try testing.expectEqualStrings("initial", undo_store.getState().text);
}

test "UndoStore single element history" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        1, // history limit of 1
    );
    defer undo_store.deinit(allocator);

    try undo_store.dispatch(EditorAction{ .insert = "a" });
    try undo_store.dispatch(EditorAction{ .insert = "b" });

    // With history limit 1, should not be able to undo past most recent
    _ = undo_store.undo();
    // Should be at "a" or close to it
}

test "UndoStore getState always returns current" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    var state = undo_store.getState();
    try testing.expectEqualStrings("", state.text);

    try undo_store.dispatch(EditorAction{ .insert = "test" });
    state = undo_store.getState();
    try testing.expectEqualStrings("test", state.text);

    _ = undo_store.undo();
    state = undo_store.getState();
    try testing.expectEqualStrings("", state.text);

    _ = undo_store.redo();
    state = undo_store.getState();
    try testing.expectEqualStrings("test", state.text);
}

test "UndoStore alternating undo/redo preserves state" {
    const allocator = testing.allocator;
    const initial_state: EditorState = .{
        .text = "",
        .cursor_pos = 0,
        .line_count = 0,
    };

    var undo_store = try sailor.undo_middleware.UndoStore(EditorState, EditorAction).init(
        allocator,
        initial_state,
        editorReducer,
        10,
    );
    defer undo_store.deinit(allocator);

    try undo_store.dispatch(EditorAction{ .insert = "a" });

    _ = undo_store.undo();
    try testing.expectEqualStrings("", undo_store.getState().text);

    _ = undo_store.redo();
    try testing.expectEqualStrings("a", undo_store.getState().text);

    _ = undo_store.undo();
    try testing.expectEqualStrings("", undo_store.getState().text);

    _ = undo_store.redo();
    try testing.expectEqualStrings("a", undo_store.getState().text);
}
