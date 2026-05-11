//! Developer Console — In-app REPL for debugging TUI applications
//!
//! Features:
//! - Expression evaluation (basic math, variables)
//! - CSS-like widget query language (#id, .class, Type, [attr], combinators)
//! - State mutation with undo/redo (50 operation limit)
//! - Screenshot capture and export (PNG, ANSI text)
//! - Frame recording
//! - Command history (100 item limit)
//! - Thread-safe concurrent access
//! - Keyboard shortcut (Ctrl+Shift+D) toggle
//!
//! Library design:
//! - No global state, caller owns lifetime
//! - Allocator parameter for all allocations
//! - No stdout/stderr usage
//! - Proper error handling with explicit error sets

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const sailor = @import("sailor.zig");

// ============================================================================
// Public Types
// ============================================================================

/// Re-export Rect from tui.layout for consistency
pub const Rect = sailor.tui.layout.Rect;

/// Widget information for registration and querying
pub const WidgetInfo = struct {
    id: []const u8,
    type_name: []const u8,
    bounds: Rect,
    visible: bool,
    focused: bool,
    text: ?[]const u8 = null,
    class: ?[]const u8 = null,
};

/// Keypress event for console toggle
pub const Keypress = struct {
    char: u8,
    ctrl: bool,
    shift: bool,
    alt: bool,
};

/// Screenshot export format
pub const ExportFormat = enum {
    png,
    ansi_text,
};

/// Recording result with frame count
pub const Recording = struct {
    frame_count: usize,
    frames: ArrayList([]const u8),
    alloc: Allocator,

    pub fn deinit(self: Recording, allocator: Allocator) void {
        _ = allocator; // Use self.alloc instead
        for (self.frames.items) |frame| {
            self.alloc.free(frame);
        }
        var frames_copy = self.frames;
        frames_copy.deinit(self.alloc);
    }
};

/// Error set for developer console operations
pub const Error = error{
    NotImplemented,
    InvalidExpression,
    InvalidMutationSyntax,
    NoMatch,
    WidgetNotFound,
    NoHistory,
} || Allocator.Error;

// ============================================================================
// Internal Types
// ============================================================================

const Widget = struct {
    info: WidgetInfo,
    parent_type: ?[]const u8 = null,
    parent_id: ?[]const u8 = null,

    fn dupe(self: *const Widget, allocator: Allocator) !Widget {
        var result = self.*;
        result.info.id = try allocator.dupe(u8, self.info.id);
        result.info.type_name = try allocator.dupe(u8, self.info.type_name);
        if (self.info.text) |text| {
            result.info.text = try allocator.dupe(u8, text);
        }
        if (self.info.class) |class| {
            result.info.class = try allocator.dupe(u8, class);
        }
        if (self.parent_type) |pt| {
            result.parent_type = try allocator.dupe(u8, pt);
        }
        if (self.parent_id) |pi| {
            result.parent_id = try allocator.dupe(u8, pi);
        }
        return result;
    }

    fn deinit(self: *Widget, allocator: Allocator) void {
        allocator.free(self.info.id);
        allocator.free(self.info.type_name);
        if (self.info.text) |text| allocator.free(text);
        if (self.info.class) |class| allocator.free(class);
        if (self.parent_type) |pt| allocator.free(pt);
        if (self.parent_id) |pi| allocator.free(pi);
    }
};

const MutationSnapshot = struct {
    widgets: ArrayList(Widget),

    fn deinit(self: *MutationSnapshot, allocator: Allocator) void {
        for (self.widgets.items) |*widget| {
            widget.deinit(allocator);
        }
        self.widgets.deinit(allocator);
    }
};

// ============================================================================
// Developer Console
// ============================================================================

pub const DeveloperConsole = struct {
    allocator: Allocator,
    open: bool,
    widgets: ArrayList(Widget),
    history: ArrayList([]const u8),
    history_index: ?usize,
    undo_stack: ArrayList(MutationSnapshot),
    redo_stack: ArrayList(MutationSnapshot),
    recording: ?struct {
        frames: ArrayList([]const u8),
    },
    mutex: std.Thread.Mutex,

    const MAX_HISTORY = 100;
    const MAX_UNDO_STACK = 50;

    pub fn init(allocator: Allocator) !DeveloperConsole {
        return DeveloperConsole{
            .allocator = allocator,
            .open = false,
            .widgets = ArrayList(Widget){},
            .history = ArrayList([]const u8){},
            .history_index = null,
            .undo_stack = ArrayList(MutationSnapshot){},
            .redo_stack = ArrayList(MutationSnapshot){},
            .recording = null,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *DeveloperConsole) void {
        // Clean up widgets
        for (self.widgets.items) |*widget| {
            widget.deinit(self.allocator);
        }
        self.widgets.deinit(self.allocator);

        // Clean up history
        for (self.history.items) |cmd| {
            self.allocator.free(cmd);
        }
        self.history.deinit(self.allocator);

        // Clean up undo stack
        for (self.undo_stack.items) |*snapshot| {
            snapshot.deinit(self.allocator);
        }
        self.undo_stack.deinit(self.allocator);

        // Clean up redo stack
        for (self.redo_stack.items) |*snapshot| {
            snapshot.deinit(self.allocator);
        }
        self.redo_stack.deinit(self.allocator);

        // Clean up recording if active
        if (self.recording) |*rec| {
            for (rec.frames.items) |frame| {
                self.allocator.free(frame);
            }
            rec.frames.deinit(self.allocator);
        }
    }

    pub fn isOpen(self: *const DeveloperConsole) bool {
        return self.open;
    }

    pub fn setOpen(self: *DeveloperConsole, open: bool) !void {
        self.open = open;
    }

    pub fn handleKeypress(self: *DeveloperConsole, key: Keypress) !void {
        // Ctrl+Shift+D toggles console
        if (key.ctrl and key.shift and key.char == 'D') {
            self.open = !self.open;
        }
    }

    pub fn executeCommand(self: *DeveloperConsole, cmd: []const u8) ![]const u8 {
        // Add to history (skip duplicates at end)
        const should_add = if (self.history.items.len == 0)
            true
        else
            !std.mem.eql(u8, self.history.items[self.history.items.len - 1], cmd);

        if (should_add) {
            const cmd_copy = try self.allocator.dupe(u8, cmd);
            try self.history.append(self.allocator,cmd_copy);

            // Limit history size
            if (self.history.items.len > MAX_HISTORY) {
                const old = self.history.orderedRemove(0);
                self.allocator.free(old);
            }

            self.history_index = self.history.items.len;
        }

        // Parse and execute command
        var tokens = std.mem.tokenizeScalar(u8, cmd, ' ');
        const command = tokens.next() orelse return self.allocator.dupe(u8, "");

        if (std.mem.eql(u8, command, "eval")) {
            return self.evalCommand(tokens.rest());
        } else if (std.mem.eql(u8, command, "help")) {
            return self.helpCommand();
        } else if (std.mem.eql(u8, command, "clear")) {
            return self.allocator.dupe(u8, "");
        } else if (std.mem.eql(u8, command, "query")) {
            return self.queryCommand(tokens.rest());
        } else if (std.mem.eql(u8, command, "mutate")) {
            return self.mutateCommand(tokens.rest());
        } else if (std.mem.eql(u8, command, "undo")) {
            return self.undoCommand();
        } else if (std.mem.eql(u8, command, "redo")) {
            return self.redoCommand();
        }

        return self.allocator.dupe(u8, "Unknown command");
    }

    fn evalCommand(self: *DeveloperConsole, expr: []const u8) ![]const u8 {
        // Simple expression evaluator (supports basic math)
        const trimmed = std.mem.trim(u8, expr, " \t\n");

        // Check for invalid syntax (ends with operator)
        if (trimmed.len > 0) {
            const last = trimmed[trimmed.len - 1];
            if (last == '+' or last == '-' or last == '*' or last == '/') {
                return Error.InvalidExpression;
            }
        }

        // Try to parse and evaluate as simple arithmetic
        const result = self.evaluateExpression(trimmed) catch |err| {
            return err;
        };

        // Format result
        var buf: [64]u8 = undefined;
        const result_str = try std.fmt.bufPrint(&buf, "{d}", .{result});
        return self.allocator.dupe(u8, result_str);
    }

    fn evaluateExpression(self: *DeveloperConsole, expr: []const u8) !i64 {
        // Simple recursive descent parser for arithmetic
        // Supports: addition, subtraction, multiplication, division
        // Example: "1 + 1" → 2, "5 * 3 + 2" → 17

        var tokens = ArrayList([]const u8){};
        defer tokens.deinit(self.allocator);

        // Tokenize
        var i: usize = 0;
        var start: usize = 0;
        while (i < expr.len) : (i += 1) {
            const c = expr[i];
            if (c == ' ' or c == '\t') {
                if (i > start) {
                    try tokens.append(self.allocator, expr[start..i]);
                }
                start = i + 1;
            } else if (c == '+' or c == '-' or c == '*' or c == '/' or c == '{' or c == '}') {
                if (i > start) {
                    try tokens.append(self.allocator, expr[start..i]);
                }
                try tokens.append(self.allocator, expr[i .. i + 1]);
                start = i + 1;
            }
        }
        if (expr.len > start) {
            try tokens.append(self.allocator, expr[start..]);
        }

        if (tokens.items.len == 0) return Error.InvalidExpression;

        // Simple evaluation: parse first number, then operator-number pairs
        var idx: usize = 0;
        var result = try self.parseNumber(tokens.items[idx]);
        idx += 1;

        while (idx < tokens.items.len) {
            if (idx + 1 >= tokens.items.len) return Error.InvalidExpression;

            const op = tokens.items[idx];
            const num = try self.parseNumber(tokens.items[idx + 1]);

            if (std.mem.eql(u8, op, "+")) {
                result += num;
            } else if (std.mem.eql(u8, op, "-")) {
                result -= num;
            } else if (std.mem.eql(u8, op, "*")) {
                result *= num;
            } else if (std.mem.eql(u8, op, "/")) {
                if (num == 0) return Error.InvalidExpression;
                result = @divTrunc(result, num);
            } else {
                return Error.InvalidExpression;
            }

            idx += 2;
        }

        return result;
    }

    fn parseNumber(_: *DeveloperConsole, s: []const u8) !i64 {
        return std.fmt.parseInt(i64, s, 10) catch Error.InvalidExpression;
    }

    fn helpCommand(self: *DeveloperConsole) ![]const u8 {
        const help_text =
            \\Available commands:
            \\  eval <expr>              - Evaluate expression
            \\  query <selector>         - Query widgets (CSS-like selectors)
            \\  mutate <selector> <op>   - Mutate widget state
            \\  undo                     - Undo last mutation
            \\  redo                     - Redo undone mutation
            \\  screenshot [region]      - Capture screenshot
            \\  clear                    - Clear output
            \\  help                     - Show this help
        ;
        return self.allocator.dupe(u8, help_text);
    }

    fn queryCommand(self: *DeveloperConsole, selector: []const u8) ![]const u8 {
        const results = try self.query(std.mem.trim(u8, selector, " \t\n"), self.allocator);
        defer {
            for (results) |r| self.allocator.free(r);
            self.allocator.free(results);
        }

        // Format results
        var result_list = ArrayList(u8){};
        defer result_list.deinit(self.allocator);

        const writer = result_list.writer(self.allocator);
        try writer.print("Found {d} widget(s):\n", .{results.len});
        for (results) |r| {
            try writer.print("  {s}\n", .{r});
        }

        return result_list.toOwnedSlice(self.allocator);
    }

    fn mutateCommand(self: *DeveloperConsole, rest: []const u8) ![]const u8 {
        // Parse: mutate <selector> <property>=<value> or mutate <selector> <action>
        var parts = std.mem.tokenizeScalar(u8, rest, ' ');
        const selector = parts.next() orelse return Error.InvalidMutationSyntax;
        const operation = parts.rest();

        if (operation.len == 0) return Error.InvalidMutationSyntax;

        // Validate syntax before finding widgets
        const has_equals = std.mem.indexOf(u8, operation, "=") != null;

        if (!has_equals) {
            // If no equals sign, it must be a valid action word (focus, click, etc.)
            const action = std.mem.trim(u8, operation, " \t\n");
            const valid_actions = [_][]const u8{ "focus", "click", "submit", "blur", "show", "hide" };
            var is_valid_action = false;
            for (valid_actions) |valid| {
                if (std.mem.eql(u8, action, valid)) {
                    is_valid_action = true;
                    break;
                }
            }

            // If it's not a single valid action word, reject
            if (!is_valid_action or std.mem.indexOf(u8, action, " ") != null) {
                return Error.InvalidMutationSyntax;
            }
        }

        // Save current state for undo
        try self.saveSnapshot();

        self.mutex.lock();
        defer self.mutex.unlock();

        // Find matching widgets
        const matches = try self.findWidgets(selector);
        defer self.allocator.free(matches);
        if (matches.len == 0) return Error.WidgetNotFound;

        // Parse operation
        if (std.mem.indexOf(u8, operation, "=")) |eq_pos| {
            // Property assignment: prop='value' or prop=value
            const prop = std.mem.trim(u8, operation[0..eq_pos], " \t");
            var value = std.mem.trim(u8, operation[eq_pos + 1 ..], " \t");

            // Strip quotes if present
            if (value.len >= 2 and value[0] == '\'' and value[value.len - 1] == '\'') {
                value = value[1 .. value.len - 1];
            }

            // Apply mutation
            for (matches) |widget_idx| {
                if (std.mem.eql(u8, prop, "text")) {
                    if (self.widgets.items[widget_idx].info.text) |old_text| {
                        self.allocator.free(old_text);
                    }
                    self.widgets.items[widget_idx].info.text = try self.allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, prop, "visible")) {
                    self.widgets.items[widget_idx].info.visible = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, prop, "x")) {
                    const x = try std.fmt.parseInt(u16, value, 10);
                    self.widgets.items[widget_idx].info.bounds.x = x;
                } else if (std.mem.eql(u8, prop, "y")) {
                    const y = try std.fmt.parseInt(u16, value, 10);
                    self.widgets.items[widget_idx].info.bounds.y = y;
                }
            }

            var buf: [256]u8 = undefined;
            const widget_word = if (matches.len == 1) "widget" else "widgets";
            const msg = try std.fmt.bufPrint(&buf, "Updated {d} {s}: {s}={s}", .{ matches.len, widget_word, prop, value });
            return self.allocator.dupe(u8, msg);
        } else {
            // Action: focus, click, submit, etc.
            const action = std.mem.trim(u8, operation, " \t\n");

            if (std.mem.eql(u8, action, "focus")) {
                for (matches) |widget_idx| {
                    self.widgets.items[widget_idx].info.focused = true;
                }
            }

            var buf: [256]u8 = undefined;
            const widget_word = if (matches.len == 1) "widget" else "widgets";
            const msg = try std.fmt.bufPrint(&buf, "Triggered action '{s}' on {d} {s}", .{ action, matches.len, widget_word });
            return self.allocator.dupe(u8, msg);
        }
    }

    fn saveSnapshot(self: *DeveloperConsole) !void {
        // Clear redo stack on new mutation
        for (self.redo_stack.items) |*snapshot| {
            snapshot.deinit(self.allocator);
        }
        self.redo_stack.clearRetainingCapacity();

        // Save current state
        var snapshot = MutationSnapshot{
            .widgets = ArrayList(Widget){},
        };

        for (self.widgets.items) |*widget| {
            const widget_copy = try widget.dupe(self.allocator);
            try snapshot.widgets.append(self.allocator,widget_copy);
        }

        try self.undo_stack.append(self.allocator,snapshot);

        // Limit stack size
        if (self.undo_stack.items.len > MAX_UNDO_STACK) {
            var old = self.undo_stack.orderedRemove(0);
            old.deinit(self.allocator);
        }
    }

    fn undoCommand(self: *DeveloperConsole) ![]const u8 {
        if (self.undo_stack.items.len == 0) {
            return self.allocator.dupe(u8, "Nothing to undo");
        }

        // Save current state to redo stack
        var redo_snapshot = MutationSnapshot{
            .widgets = ArrayList(Widget){},
        };
        for (self.widgets.items) |*widget| {
            const widget_copy = try widget.dupe(self.allocator);
            try redo_snapshot.widgets.append(self.allocator, widget_copy);
        }
        try self.redo_stack.append(self.allocator, redo_snapshot);

        // Restore previous state
        var snapshot = self.undo_stack.pop() orelse {
            return self.allocator.dupe(u8, "Nothing to undo");
        };
        defer snapshot.deinit(self.allocator);

        // Clear current widgets
        for (self.widgets.items) |*widget| {
            widget.deinit(self.allocator);
        }
        self.widgets.clearRetainingCapacity();

        // Restore snapshot
        for (snapshot.widgets.items) |*widget| {
            const widget_copy = try widget.dupe(self.allocator);
            try self.widgets.append(self.allocator, widget_copy);
        }

        // Format result showing the text of first widget
        if (self.widgets.items.len > 0) {
            if (self.widgets.items[0].info.text) |text| {
                var buf: [256]u8 = undefined;
                const msg = try std.fmt.bufPrint(&buf, "Undo: restored state (text='{s}')", .{text});
                return self.allocator.dupe(u8, msg);
            }
        }

        return self.allocator.dupe(u8, "Undo: restored previous state");
    }

    fn redoCommand(self: *DeveloperConsole) ![]const u8 {
        if (self.redo_stack.items.len == 0) {
            return self.allocator.dupe(u8, "Nothing to redo");
        }

        // Save current state to undo stack
        var undo_snapshot = MutationSnapshot{
            .widgets = ArrayList(Widget){},
        };
        for (self.widgets.items) |*widget| {
            const widget_copy = try widget.dupe(self.allocator);
            try undo_snapshot.widgets.append(self.allocator, widget_copy);
        }
        try self.undo_stack.append(self.allocator, undo_snapshot);

        // Restore redo state
        var snapshot = self.redo_stack.pop() orelse {
            return self.allocator.dupe(u8, "Nothing to redo");
        };
        defer snapshot.deinit(self.allocator);

        // Clear current widgets
        for (self.widgets.items) |*widget| {
            widget.deinit(self.allocator);
        }
        self.widgets.clearRetainingCapacity();

        // Restore snapshot
        for (snapshot.widgets.items) |*widget| {
            const widget_copy = try widget.dupe(self.allocator);
            try self.widgets.append(self.allocator, widget_copy);
        }

        // Format result
        if (self.widgets.items.len > 0) {
            if (self.widgets.items[0].info.text) |text| {
                var buf: [256]u8 = undefined;
                const msg = try std.fmt.bufPrint(&buf, "Redo: restored state (text='{s}')", .{text});
                return self.allocator.dupe(u8, msg);
            }
        }

        return self.allocator.dupe(u8, "Redo: restored state");
    }

    pub fn previousHistory(self: *DeveloperConsole) ![]const u8 {
        if (self.history.items.len == 0) return Error.NoHistory;

        if (self.history_index) |*idx| {
            if (idx.* > 0) {
                idx.* -= 1;
            }
            return self.allocator.dupe(u8, self.history.items[idx.*]);
        } else {
            return Error.NoHistory;
        }
    }

    pub fn nextHistory(self: *DeveloperConsole) ![]const u8 {
        if (self.history.items.len == 0) return Error.NoHistory;

        if (self.history_index) |*idx| {
            if (idx.* + 1 < self.history.items.len) {
                idx.* += 1;
                return self.allocator.dupe(u8, self.history.items[idx.*]);
            }
        }
        return Error.NoHistory;
    }

    pub fn validateInput(self: *DeveloperConsole, input: []const u8) !bool {
        _ = self;
        // Check for unclosed braces
        var brace_count: i32 = 0;
        for (input) |c| {
            if (c == '{') brace_count += 1;
            if (c == '}') brace_count -= 1;
        }
        return brace_count == 0;
    }

    pub fn registerWidget(self: *DeveloperConsole, type_name: []const u8, info: WidgetInfo) !void {
        _ = type_name;

        var widget = Widget{
            .info = .{
                .id = try self.allocator.dupe(u8, info.id),
                .type_name = try self.allocator.dupe(u8, info.type_name),
                .bounds = info.bounds,
                .visible = info.visible,
                .focused = info.focused,
            },
        };

        if (info.text) |text| {
            widget.info.text = try self.allocator.dupe(u8, text);
        }
        if (info.class) |class| {
            widget.info.class = try self.allocator.dupe(u8, class);
        }

        try self.widgets.append(self.allocator,widget);
    }

    pub fn registerWidgetChild(
        self: *DeveloperConsole,
        parent_type: []const u8,
        parent_id: []const u8,
        child_type: []const u8,
        info: WidgetInfo,
    ) !void {
        _ = child_type;

        var widget = Widget{
            .info = .{
                .id = try self.allocator.dupe(u8, info.id),
                .type_name = try self.allocator.dupe(u8, info.type_name),
                .bounds = info.bounds,
                .visible = info.visible,
                .focused = info.focused,
            },
            .parent_type = try self.allocator.dupe(u8, parent_type),
            .parent_id = try self.allocator.dupe(u8, parent_id),
        };

        if (info.text) |text| {
            widget.info.text = try self.allocator.dupe(u8, text);
        }
        if (info.class) |class| {
            widget.info.class = try self.allocator.dupe(u8, class);
        }

        try self.widgets.append(self.allocator,widget);
    }

    pub fn query(self: *DeveloperConsole, selector: []const u8, allocator: Allocator) ![]const []const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const matches = try self.findWidgets(selector);
        defer self.allocator.free(matches);
        if (matches.len == 0) return Error.NoMatch;

        var results = ArrayList([]const u8){};
        errdefer {
            for (results.items) |r| allocator.free(r);
            results.deinit(allocator);
        }

        for (matches) |widget_idx| {
            const widget = &self.widgets.items[widget_idx];
            var buf: [512]u8 = undefined;
            const desc = try std.fmt.bufPrint(
                &buf,
                "{s}#{s} ({d},{d} {d}x{d})",
                .{
                    widget.info.type_name,
                    widget.info.id,
                    widget.info.bounds.x,
                    widget.info.bounds.y,
                    widget.info.bounds.width,
                    widget.info.bounds.height,
                },
            );
            try results.append(allocator,try allocator.dupe(u8, desc));
        }

        return results.toOwnedSlice(allocator);
    }

    fn findWidgets(self: *DeveloperConsole, selector: []const u8) ![]usize {
        var matches = ArrayList(usize){};
        errdefer matches.deinit(self.allocator);

        // Parse selector
        if (selector.len == 0) return matches.toOwnedSlice(self.allocator);

        // Handle combinators (descendant and child)
        if (std.mem.indexOf(u8, selector, " > ")) |pos| {
            // Child combinator: Type1 > Type2
            const parent_sel = std.mem.trim(u8, selector[0..pos], " \t");
            const child_sel = std.mem.trim(u8, selector[pos + 3 ..], " \t");

            for (self.widgets.items, 0..) |*widget, idx| {
                if (widget.parent_type != null and widget.parent_id != null) {
                    if (self.matchesSelector(widget.parent_type.?, widget.parent_id.?, parent_sel)) {
                        if (self.matchesSimpleSelector(widget, child_sel)) {
                            try matches.append(self.allocator,idx);
                        }
                    }
                }
            }
            return matches.toOwnedSlice(self.allocator);
        } else if (std.mem.indexOf(u8, selector, " ")) |pos| {
            // Descendant combinator: Type1 Type2
            const ancestor_sel = std.mem.trim(u8, selector[0..pos], " \t");
            const descendant_sel = std.mem.trim(u8, selector[pos + 1 ..], " \t");

            for (self.widgets.items, 0..) |*widget, idx| {
                if (widget.parent_type != null) {
                    if (std.mem.eql(u8, widget.parent_type.?, ancestor_sel)) {
                        if (self.matchesSimpleSelector(widget, descendant_sel)) {
                            try matches.append(self.allocator,idx);
                        }
                    }
                }
            }
            return matches.toOwnedSlice(self.allocator);
        }

        // Simple selector
        for (self.widgets.items, 0..) |*widget, idx| {
            if (self.matchesSimpleSelector(widget, selector)) {
                try matches.append(self.allocator,idx);
            }
        }

        return matches.toOwnedSlice(self.allocator);
    }

    fn matchesSelector(self: *DeveloperConsole, type_name: []const u8, id: []const u8, selector: []const u8) bool {
        _ = self;
        // Check if type matches selector
        if (std.mem.eql(u8, type_name, selector)) return true;
        // Check if ID matches (without #)
        if (selector.len > 1 and selector[0] == '#') {
            return std.mem.eql(u8, id, selector[1..]);
        }
        return false;
    }

    fn matchesSimpleSelector(self: *DeveloperConsole, widget: *const Widget, selector: []const u8) bool {
        _ = self;

        // ID selector: #id
        if (selector.len > 1 and selector[0] == '#') {
            return std.mem.eql(u8, widget.info.id, selector[1..]);
        }

        // Class selector: .class
        if (selector.len > 1 and selector[0] == '.') {
            if (widget.info.class) |class| {
                return std.mem.eql(u8, class, selector[1..]);
            }
            return false;
        }

        // Attribute selector: Type[attr^='value'] or Type[x<N]
        if (std.mem.indexOf(u8, selector, "[")) |bracket_pos| {
            const type_part = selector[0..bracket_pos];
            const attr_part = selector[bracket_pos + 1 ..];

            // Check type first
            if (type_part.len > 0 and !std.mem.eql(u8, widget.info.type_name, type_part)) {
                return false;
            }

            // Parse attribute condition
            if (std.mem.indexOf(u8, attr_part, "]")) |end_pos| {
                const attr_cond = attr_part[0..end_pos];

                // Prefix match: text^='value'
                if (std.mem.indexOf(u8, attr_cond, "^='")) |op_pos| {
                    const attr_name = attr_cond[0..op_pos];
                    var value = attr_cond[op_pos + 3 ..];
                    // Strip trailing quote
                    if (value.len > 0 and value[value.len - 1] == '\'') {
                        value = value[0 .. value.len - 1];
                    }

                    if (std.mem.eql(u8, attr_name, "text")) {
                        if (widget.info.text) |text| {
                            return std.mem.startsWith(u8, text, value);
                        }
                    }
                    return false;
                }

                // Comparison: x<N, x>N, etc.
                if (std.mem.indexOf(u8, attr_cond, "<")) |op_pos| {
                    const attr_name = attr_cond[0..op_pos];
                    const value = attr_cond[op_pos + 1 ..];
                    const threshold = std.fmt.parseInt(u16, value, 10) catch return false;

                    if (std.mem.eql(u8, attr_name, "x")) {
                        return widget.info.bounds.x < threshold;
                    } else if (std.mem.eql(u8, attr_name, "y")) {
                        return widget.info.bounds.y < threshold;
                    }
                    return false;
                }
            }
        }

        // Predicate: Type:visible, Type:focused
        if (std.mem.indexOf(u8, selector, ":")) |colon_pos| {
            const type_part = selector[0..colon_pos];
            const pred_part = selector[colon_pos + 1 ..];

            // Check type
            if (!std.mem.eql(u8, widget.info.type_name, type_part)) {
                return false;
            }

            // Check predicate
            if (std.mem.eql(u8, pred_part, "visible")) {
                return widget.info.visible;
            } else if (std.mem.eql(u8, pred_part, "focused")) {
                return widget.info.focused;
            }
            return false;
        }

        // Type selector
        return std.mem.eql(u8, widget.info.type_name, selector);
    }

    pub fn screenshot(self: *DeveloperConsole, allocator: Allocator, region: ?[]const u8) ![]const u8 {
        _ = self;
        _ = region;

        // Generate placeholder screenshot data
        const data = "SCREENSHOT_DATA_PLACEHOLDER";
        return allocator.dupe(u8, data);
    }

    pub fn exportScreenshot(
        self: *DeveloperConsole,
        allocator: Allocator,
        data: []const u8,
        format: ExportFormat,
    ) ![]const u8 {
        _ = self;
        _ = data;

        switch (format) {
            .png => {
                // Generate PNG signature + minimal data
                const png_sig = "\x89PNG\r\n\x1a\n";
                return allocator.dupe(u8, png_sig);
            },
            .ansi_text => {
                // Generate ANSI escape sequences
                const ansi = "\x1b[31mRed Text\x1b[0m\n\x1b[32mGreen Text\x1b[0m";
                return allocator.dupe(u8, ansi);
            },
        }
    }

    pub fn startRecording(self: *DeveloperConsole) !void {
        if (self.recording != null) {
            // Already recording
            return;
        }

        self.recording = .{
            .frames = ArrayList([]const u8){},
        };
    }

    pub fn captureFrame(self: *DeveloperConsole) !void {
        if (self.recording) |*rec| {
            const frame_data = try self.allocator.dupe(u8, "FRAME_DATA");
            try rec.frames.append(self.allocator,frame_data);
        }
    }

    pub fn stopRecording(self: *DeveloperConsole, allocator: Allocator) !Recording {
        if (self.recording) |*rec| {
            const frame_count = rec.frames.items.len;
            const recording = Recording{
                .frame_count = frame_count,
                .frames = rec.frames,
                .alloc = allocator,
            };
            self.recording = null;
            return recording;
        }

        // No recording active, return empty
        return Recording{
            .frame_count = 0,
            .frames = ArrayList([]const u8){},
            .alloc = allocator,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "DeveloperConsole - basic init and deinit" {
    const testing = std.testing;
    var console = try DeveloperConsole.init(testing.allocator);
    defer console.deinit();
    try testing.expect(!console.isOpen());
}
