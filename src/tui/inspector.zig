//! Widget Inspector Module
//!
//! Provides runtime introspection, layout debugging, and event tracing for TUI applications.
//! All operations use writer-based output (no stdout) and follow sailor library principles.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;

const layout_mod = @import("layout.zig");
pub const Rect = layout_mod.Rect;
pub const Constraint = layout_mod.Constraint;
pub const Direction = layout_mod.Direction;

// ============================================================================
// Public Types
// ============================================================================

/// Event types that can be recorded
pub const EventType = enum {
    keyboard,
    mouse_move,
    mouse_click,
    mouse_scroll,
    resize,
};

/// Event data union
pub const EventData = union(EventType) {
    keyboard: u8,
    mouse_move: struct { x: u16, y: u16 },
    mouse_click: struct { x: u16, y: u16, button: MouseButton },
    mouse_scroll: struct { delta: i16 },
    resize: struct { cols: u16, rows: u16 },
};

/// Mouse button enum
pub const MouseButton = enum {
    left,
    right,
    middle,
};

/// Recorded event with timestamp
pub const EventRecord = struct {
    event_type: EventType,
    data: EventData,
    timestamp: i64,
};

/// Constraint record for layout debugging
pub const ConstraintRecord = struct {
    constraint: Constraint,
    direction: Direction,
    available: u16,
};

/// Layout information for a widget
pub const LayoutInfo = struct {
    widget_id: u32,
    constraints: []const ConstraintRecord,
    calculated_area: Rect,
    available_width: u16,
    available_height: u16,

    allocator: Allocator,
    constraint_list: ArrayList(ConstraintRecord),

    /// Free constraint list memory. Must be called to prevent leaks.
    pub fn deinit(self: *LayoutInfo) void {
        self.constraint_list.deinit(self.allocator);
    }
};

/// Widget information with hierarchy
pub const WidgetInfo = struct {
    id: u32,
    name: []const u8,
    area: Rect,
    parent_id: ?u32,
    children: []const u32,
    properties: StringHashMap([]const u8),

    allocator: Allocator,
    name_owned: []u8,
    child_list: ArrayList(u32),

    /// Free all widget info memory including name, children, and properties.
    pub fn deinit(self: *WidgetInfo) void {
        self.allocator.free(self.name_owned);
        self.child_list.deinit(self.allocator);
        var it = self.properties.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.properties.deinit();
    }

    /// Retrieve a custom property value by key. Returns null if not found.
    pub fn getProperty(self: *const WidgetInfo, key: []const u8) ?[]const u8 {
        return self.properties.get(key);
    }
};

/// Tree node for widget hierarchy
pub const WidgetNode = struct {
    name: []const u8,
    id: u32,
    area: Rect,
    children: []const *const WidgetNode,

    allocator: Allocator,
    child_ptrs: ArrayList(*WidgetNode),

    /// Recursively free this node and all child nodes.
    pub fn deinit(self: *WidgetNode, allocator: Allocator) void {
        for (self.child_ptrs.items) |child| {
            child.deinit(allocator);
            allocator.destroy(child);
        }
        self.child_ptrs.deinit(allocator);
    }
};

/// Layout violation detected by inspector
pub const LayoutViolation = struct {
    widget_id: u32,
    violation_type: []const u8,
    description: []const u8,

    allocator: Allocator,
    violation_type_owned: []u8,
    description_owned: []u8,

    /// Free violation type and description strings.
    pub fn deinit(self: *LayoutViolation) void {
        self.allocator.free(self.violation_type_owned);
        self.allocator.free(self.description_owned);
    }
};

/// Frame snapshot for historical tracking
pub const FrameSnapshot = struct {
    frame_number: usize,
    widget_ids: []const u32,

    allocator: Allocator,
    widget_id_list: ArrayList(u32),

    /// Free the widget ID list.
    pub fn deinit(self: *FrameSnapshot) void {
        self.widget_id_list.deinit(self.allocator);
    }
};

// ============================================================================
// Inspector
// ============================================================================

pub const Inspector = struct {
    allocator: Allocator,
    enabled: bool,
    next_widget_id: u32,

    // Widget tracking
    widgets: AutoHashMap(u32, WidgetInfo),
    widget_order: ArrayList(u32), // Insertion order for iteration

    // Layout tracking
    layouts: AutoHashMap(u32, LayoutInfo),

    // Event tracking
    events: ArrayList(EventRecord),
    max_events: usize,

    // Frame tracking
    frames: ArrayList(FrameSnapshot),
    current_frame_widgets: ArrayList(u32),
    frame_started: bool,

    /// Initialize a new inspector instance.
    /// The inspector starts disabled; call `enable()` to activate tracking.
    /// Returns error.OutOfMemory if allocation fails.
    pub fn init(allocator: Allocator) !Inspector {
        return Inspector{
            .allocator = allocator,
            .enabled = false,
            .next_widget_id = 1,
            .widgets = AutoHashMap(u32, WidgetInfo).init(allocator),
            .widget_order = ArrayList(u32){},
            .layouts = AutoHashMap(u32, LayoutInfo).init(allocator),
            .events = ArrayList(EventRecord){},
            .max_events = 1000, // Default max events
            .frames = ArrayList(FrameSnapshot){},
            .current_frame_widgets = ArrayList(u32){},
            .frame_started = false,
        };
    }

    /// Free all resources including widgets, layouts, events, and frame snapshots.
    /// Must be called to prevent memory leaks.
    pub fn deinit(self: *Inspector) void {
        // Clean up widgets
        var widget_it = self.widgets.iterator();
        while (widget_it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.widgets.deinit();
        self.widget_order.deinit(self.allocator);

        // Clean up layouts
        var layout_it = self.layouts.iterator();
        while (layout_it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.layouts.deinit();

        // Clean up events
        self.events.deinit(self.allocator);

        // Clean up frames
        for (self.frames.items) |*frame| {
            frame.deinit();
        }
        self.frames.deinit(self.allocator);
        self.current_frame_widgets.deinit(self.allocator);
    }

    /// Enable widget and event tracking.
    /// When enabled, all record* and track* calls will collect data.
    pub fn enable(self: *Inspector) void {
        self.enabled = true;
    }

    /// Disable widget and event tracking.
    /// When disabled, record* and track* calls become no-ops.
    pub fn disable(self: *Inspector) void {
        self.enabled = false;
    }

    /// Check whether the inspector is currently tracking widgets and events.
    /// Returns true if enabled, false otherwise.
    pub fn isEnabled(self: *const Inspector) bool {
        return self.enabled;
    }

    /// Record a widget with no parent (top-level widget).
    /// Returns a unique widget ID for later reference, or 0 if disabled or allocation fails.
    /// The widget will be tracked in the current frame.
    pub fn recordWidget(self: *Inspector, name: []const u8, area: Rect) u32 {
        if (!self.enabled) return 0;

        const widget_id = self.next_widget_id;
        self.next_widget_id += 1;

        const name_owned = self.allocator.dupe(u8, name) catch return 0;

        const info = WidgetInfo{
            .id = widget_id,
            .name = name_owned,
            .area = area,
            .parent_id = null,
            .children = &[_]u32{},
            .properties = StringHashMap([]const u8).init(self.allocator),
            .allocator = self.allocator,
            .name_owned = name_owned,
            .child_list = ArrayList(u32){},
        };

        self.widgets.put(widget_id, info) catch return 0;
        self.widget_order.append(self.allocator, widget_id) catch {};
        self.current_frame_widgets.append(self.allocator, widget_id) catch {};

        return widget_id;
    }

    /// Record a widget as a child of another widget.
    /// Returns a unique widget ID or 0 if disabled/allocation fails.
    /// The parent's children list will be updated to include this widget.
    pub fn recordWidgetWithParent(self: *Inspector, name: []const u8, area: Rect, parent_id: u32) u32 {
        if (!self.enabled) return 0;

        const widget_id = self.recordWidget(name, area);
        if (widget_id == 0) return 0;

        // Set parent
        if (self.widgets.getPtr(widget_id)) |widget| {
            widget.parent_id = parent_id;
        }

        // Add to parent's children
        if (self.widgets.getPtr(parent_id)) |parent| {
            parent.child_list.append(self.allocator, widget_id) catch {};
            parent.children = parent.child_list.items;
        }

        return widget_id;
    }

    /// Attach a custom key-value property to a widget.
    /// Both key and value are duplicated. If the key already exists, the old value is freed.
    /// Returns error.WidgetNotFound if widget_id doesn't exist.
    pub fn setWidgetProperty(self: *Inspector, widget_id: u32, key: []const u8, value: []const u8) !void {
        if (!self.enabled) return;

        const widget = self.widgets.getPtr(widget_id) orelse return error.WidgetNotFound;

        const key_owned = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_owned);

        const value_owned = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_owned);

        // Free old value if key exists
        if (widget.properties.fetchRemove(key)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value);
        }

        try widget.properties.put(key_owned, value_owned);
    }

    /// Record a layout constraint applied to a widget.
    /// Multiple constraints can be recorded for the same widget.
    /// Updates available_width or available_height based on direction.
    pub fn recordConstraint(self: *Inspector, widget_id: u32, constraint: Constraint, direction: Direction, available: u16) void {
        if (!self.enabled) return;

        const layout = self.layouts.getPtr(widget_id) orelse blk: {
            const new_layout = LayoutInfo{
                .widget_id = widget_id,
                .constraints = &[_]ConstraintRecord{},
                .calculated_area = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
                .available_width = 0,
                .available_height = 0,
                .allocator = self.allocator,
                .constraint_list = ArrayList(ConstraintRecord){},
            };
            self.layouts.put(widget_id, new_layout) catch return;
            break :blk self.layouts.getPtr(widget_id).?;
        };

        const record = ConstraintRecord{
            .constraint = constraint,
            .direction = direction,
            .available = available,
        };

        layout.constraint_list.append(self.allocator, record) catch return;
        layout.constraints = layout.constraint_list.items;

        // Update available dimensions
        if (direction == .horizontal) {
            layout.available_width = available;
        } else {
            layout.available_height = available;
        }
    }

    /// Record the final calculated area for a widget after layout resolution.
    /// Accepts either a u32 widget ID or a string widget name.
    /// If the widget has no layout info yet, creates a new entry.
    pub fn recordLayoutCalculation(self: *Inspector, widget_id_or_name: anytype, area: Rect) void {
        if (!self.enabled) return;

        const T = @TypeOf(widget_id_or_name);
        const widget_id: u32 = if (T == u32)
            widget_id_or_name
        else if (T == []const u8 or comptime std.mem.startsWith(u8, @typeName(T), "*const [")) blk: {
            // Find widget by name
            for (self.widget_order.items) |id| {
                const widget = self.widgets.get(id) orelse continue;
                if (std.mem.eql(u8, widget.name, widget_id_or_name)) {
                    break :blk id;
                }
            }
            return; // Widget not found
        } else {
            @compileError("recordLayoutCalculation expects u32 or string slice");
        };

        const layout = self.layouts.getPtr(widget_id) orelse blk: {
            const new_layout = LayoutInfo{
                .widget_id = widget_id,
                .constraints = &[_]ConstraintRecord{},
                .calculated_area = area,
                .available_width = area.width,
                .available_height = area.height,
                .allocator = self.allocator,
                .constraint_list = ArrayList(ConstraintRecord){},
            };
            self.layouts.put(widget_id, new_layout) catch return;
            break :blk self.layouts.getPtr(widget_id).?;
        };

        layout.calculated_area = area;
    }

    /// Record a terminal event (keyboard, mouse, resize).
    /// Events are timestamped and limited by max_events setting.
    /// Oldest events are automatically pruned when the limit is exceeded.
    pub fn recordEvent(self: *Inspector, data: EventData) void {
        if (!self.enabled) return;

        const event_type: EventType = switch (data) {
            .keyboard => .keyboard,
            .mouse_move => .mouse_move,
            .mouse_click => .mouse_click,
            .mouse_scroll => .mouse_scroll,
            .resize => .resize,
        };

        const record = EventRecord{
            .event_type = event_type,
            .data = data,
            .timestamp = std.time.milliTimestamp(),
        };

        self.events.append(self.allocator, record) catch return;

        // Limit event history
        if (self.events.items.len > self.max_events) {
            // Remove oldest events
            const to_remove = self.events.items.len - self.max_events;
            std.mem.copyForwards(EventRecord, self.events.items, self.events.items[to_remove..]);
            self.events.shrinkRetainingCapacity(self.max_events);
        }
    }

    /// Retrieve widget information by ID.
    /// Returns null if the widget doesn't exist.
    pub fn getWidgetInfo(self: *const Inspector, widget_id: u32) ?*const WidgetInfo {
        return self.widgets.getPtr(widget_id);
    }

    /// Retrieve layout information by widget ID.
    /// Returns null if no layout data has been recorded for this widget.
    pub fn getLayoutInfo(self: *const Inspector, widget_id: u32) ?*const LayoutInfo {
        return self.layouts.getPtr(widget_id);
    }

    /// Get the total number of widgets currently tracked.
    pub fn getWidgetCount(self: *const Inspector) usize {
        return self.widgets.count();
    }

    /// Build and return the widget tree starting from the root widget.
    /// Returns null if no root widget exists (widget with parent_id == null).
    /// Caller must call deinit() on the returned node to free memory.
    pub fn getWidgetTree(self: *const Inspector) ?*const WidgetNode {
        // Find root widget (widget with no parent)
        for (self.widget_order.items) |widget_id| {
            const widget = self.widgets.get(widget_id) orelse continue;
            if (widget.parent_id == null) {
                // Build tree from this root
                return self.buildWidgetNode(widget_id);
            }
        }
        return null;
    }

    fn buildWidgetNode(self: *const Inspector, widget_id: u32) ?*const WidgetNode {
        const widget = self.widgets.get(widget_id) orelse return null;

        var node = self.allocator.create(WidgetNode) catch return null;
        node.* = WidgetNode{
            .name = widget.name,
            .id = widget.id,
            .area = widget.area,
            .children = &[_]*const WidgetNode{},
            .allocator = self.allocator,
            .child_ptrs = ArrayList(*WidgetNode){},
        };

        // Build children recursively
        for (widget.children) |child_id| {
            if (self.buildWidgetNode(child_id)) |child_node| {
                // Need to cast const away temporarily for append
                const mutable_node = @constCast(node);
                mutable_node.child_ptrs.append(self.allocator, @constCast(child_node)) catch continue;
            }
        }

        node.children = node.child_ptrs.items;
        return node;
    }

    /// Calculate the depth of a widget in the hierarchy tree.
    /// Root widgets have depth 0, their children have depth 1, etc.
    pub fn getWidgetDepth(self: *const Inspector, widget_id: u32) usize {
        var depth: usize = 0;
        var current_id = widget_id;

        while (self.widgets.get(current_id)) |widget| {
            if (widget.parent_id) |parent_id| {
                depth += 1;
                current_id = parent_id;
            } else {
                break;
            }
        }

        return depth;
    }

    /// Get all sibling widget IDs (widgets sharing the same parent).
    /// Returns an empty list if the widget has no siblings or no parent.
    /// Caller must call deinit() on the returned ArrayList.
    pub fn getSiblings(self: *const Inspector, allocator: Allocator, widget_id: u32) !ArrayList(u32) {
        var siblings = ArrayList(u32){};
        errdefer siblings.deinit(allocator);

        const widget = self.widgets.get(widget_id) orelse return siblings;
        const parent_id = widget.parent_id orelse return siblings;
        const parent = self.widgets.get(parent_id) orelse return siblings;

        // Filter out the widget itself from siblings
        for (parent.children) |child_id| {
            if (child_id != widget_id) {
                try siblings.append(allocator, child_id);
            }
        }

        return siblings;
    }

    /// Get all recorded events in chronological order.
    /// The returned slice is valid until the next event is recorded or clearEvents() is called.
    pub fn getEvents(self: *const Inspector) []const EventRecord {
        return self.events.items;
    }

    /// Get events filtered by type (keyboard, mouse_move, etc.).
    /// Caller must free the returned slice using the inspector's allocator.
    pub fn getEventsByType(self: *const Inspector, event_type: EventType) ![]const EventRecord {
        var filtered = ArrayList(EventRecord){};
        errdefer filtered.deinit(self.allocator);
        for (self.events.items) |event| {
            if (event.event_type == event_type) {
                try filtered.append(self.allocator, event);
            }
        }
        return try filtered.toOwnedSlice(self.allocator);
    }

    /// Set the maximum number of events to keep in history.
    /// When exceeded, oldest events are automatically pruned.
    /// Default is 1000 events.
    pub fn setMaxEvents(self: *Inspector, max: usize) void {
        self.max_events = max;
    }

    /// Clear all recorded events while retaining allocated capacity.
    pub fn clearEvents(self: *Inspector) void {
        self.events.clearRetainingCapacity();
    }

    /// Detect layout violations such as widgets overflowing parent bounds.
    /// Returns a list of violations; caller must deinit() the ArrayList and each violation's deinit().
    pub fn detectLayoutViolations(self: *const Inspector, allocator: Allocator) !ArrayList(LayoutViolation) {
        var violations = ArrayList(LayoutViolation){};
        errdefer {
            for (violations.items) |v| {
                allocator.free(v.violation_type_owned);
                allocator.free(v.description_owned);
            }
            violations.deinit(allocator);
        }

        for (self.widget_order.items) |widget_id| {
            const widget = self.widgets.get(widget_id) orelse continue;
            const parent_id = widget.parent_id orelse continue;
            const parent = self.widgets.get(parent_id) orelse continue;

            // Check if widget overflows parent bounds
            const child_right = widget.area.x + widget.area.width;
            const child_bottom = widget.area.y + widget.area.height;
            const parent_right = parent.area.x + parent.area.width;
            const parent_bottom = parent.area.y + parent.area.height;

            if (child_right > parent_right or child_bottom > parent_bottom) {
                const violation_type = try allocator.dupe(u8, "overflow");
                errdefer allocator.free(violation_type);

                const description = try std.fmt.allocPrint(
                    allocator,
                    "Widget extends beyond parent bounds",
                    .{},
                );
                errdefer allocator.free(description);

                const violation = LayoutViolation{
                    .widget_id = widget_id,
                    .violation_type = violation_type,
                    .description = description,
                    .allocator = allocator,
                    .violation_type_owned = violation_type,
                    .description_owned = description,
                };

                try violations.append(allocator, violation);
            }
        }

        return violations;
    }

    /// Begin a new rendering frame.
    /// Clears current frame widget list and optionally clears previous frame data.
    pub fn beginFrame(self: *Inspector) void {
        if (!self.enabled) return;

        // Clear current frame
        self.current_frame_widgets.clearRetainingCapacity();

        // Clear widgets from previous frame (not historical frames)
        if (!self.frame_started) {
            var widget_it = self.widgets.iterator();
            while (widget_it.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.widgets.clearRetainingCapacity();
            self.widget_order.clearRetainingCapacity();

            var layout_it = self.layouts.iterator();
            while (layout_it.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.layouts.clearRetainingCapacity();
        }

        self.frame_started = true;
    }

    /// End the current rendering frame.
    /// Saves a snapshot of widgets rendered in this frame for historical tracking.
    pub fn endFrame(self: *Inspector) void {
        if (!self.enabled) return;
        if (!self.frame_started) return;

        // Save frame snapshot
        var snapshot = FrameSnapshot{
            .frame_number = self.frames.items.len,
            .widget_ids = &[_]u32{},
            .allocator = self.allocator,
            .widget_id_list = ArrayList(u32){},
        };

        for (self.current_frame_widgets.items) |id| {
            snapshot.widget_id_list.append(self.allocator, id) catch continue;
        }
        snapshot.widget_ids = snapshot.widget_id_list.items;

        self.frames.append(self.allocator, snapshot) catch {};
        self.frame_started = false;
    }

    /// Get the total number of frames recorded.
    pub fn getFrameCount(self: *const Inspector) usize {
        return self.frames.items.len;
    }

    /// Get widget IDs rendered in a specific frame.
    /// Returns an empty slice if frame_index is out of range.
    pub fn getFrameWidgets(self: *const Inspector, frame_index: usize) []const u32 {
        if (frame_index >= self.frames.items.len) return &[_]u32{};
        return self.frames.items[frame_index].widget_ids;
    }

    // ========================================================================
    // Writer-based output methods
    // ========================================================================

    /// Write the widget hierarchy tree to the given writer in human-readable format.
    /// Shows widget names, dimensions, positions, and IDs with indentation for hierarchy.
    pub fn writeWidgetTree(self: *const Inspector, writer: anytype) !void {
        if (self.getWidgetCount() == 0) {
            try writer.writeAll("(empty widget tree)\n");
            return;
        }

        // Find all root widgets and write trees
        for (self.widget_order.items) |widget_id| {
            const widget = self.widgets.get(widget_id) orelse continue;
            if (widget.parent_id == null) {
                try self.writeWidgetNode(writer, widget_id, 0);
            }
        }
    }

    fn writeWidgetNode(self: *const Inspector, writer: anytype, widget_id: u32, depth: usize) !void {
        const widget = self.widgets.get(widget_id) orelse return;

        // Indentation
        var i: usize = 0;
        while (i < depth) : (i += 1) {
            try writer.writeAll("  ");
        }

        // Widget info
        try writer.print("{s} ({}x{} at {},{}) [id:{}]\n", .{
            widget.name,
            widget.area.width,
            widget.area.height,
            widget.area.x,
            widget.area.y,
            widget.id,
        });

        // Recursively write children
        for (widget.children) |child_id| {
            try self.writeWidgetNode(writer, child_id, depth + 1);
        }
    }

    /// Write detailed layout information for all widgets to the given writer.
    /// Includes areas, available dimensions, calculated dimensions, and constraints.
    pub fn writeLayoutInfo(self: *const Inspector, writer: anytype) !void {
        try writer.writeAll("=== Layout Information ===\n");

        for (self.widget_order.items) |widget_id| {
            const widget = self.widgets.get(widget_id) orelse continue;
            const layout = self.layouts.get(widget_id);

            try writer.print("\nWidget: {s} [id:{}]\n", .{ widget.name, widget.id });
            try writer.print("  Area: {}x{} at ({},{})\n", .{
                widget.area.width,
                widget.area.height,
                widget.area.x,
                widget.area.y,
            });

            if (layout) |lay| {
                try writer.print("  Available: {}w x {}h\n", .{ lay.available_width, lay.available_height });
                try writer.print("  Calculated: {}x{}\n", .{ lay.calculated_area.width, lay.calculated_area.height });

                if (lay.constraints.len > 0) {
                    try writer.writeAll("  Constraints:\n");
                    for (lay.constraints) |constraint| {
                        const dir_str = if (constraint.direction == .horizontal) "horizontal" else "vertical";
                        try writer.print("    {s}: ", .{dir_str});

                        switch (constraint.constraint) {
                            .length => |len| try writer.print("length({})", .{len}),
                            .percentage => |pct| try writer.print("percentage({}%)", .{pct}),
                            .min => |min| try writer.print("min({})", .{min}),
                            .max => |max| try writer.print("max({})", .{max}),
                            .ratio => |r| try writer.print("ratio({}/{})", .{ r.num, r.denom }),
                        }

                        try writer.print(" available={}\n", .{constraint.available});
                    }
                }
            }
        }
    }

    /// Write all recorded events to the given writer in chronological order.
    /// Each event includes timestamp and event-specific details.
    pub fn writeEventLog(self: *const Inspector, writer: anytype) !void {
        try writer.writeAll("=== Event Log ===\n");

        for (self.events.items) |event| {
            try writer.print("[{}] ", .{event.timestamp});

            switch (event.data) {
                .keyboard => |key| try writer.print("keyboard: '{}'\n", .{key}),
                .mouse_move => |pos| try writer.print("mouse move: ({},{})\n", .{ pos.x, pos.y }),
                .mouse_click => |click| try writer.print("mouse click: ({},{}) button={s}\n", .{
                    click.x,
                    click.y,
                    @tagName(click.button),
                }),
                .mouse_scroll => |scroll| try writer.print("mouse scroll: delta={}\n", .{scroll.delta}),
                .resize => |size| try writer.print("resize: {}x{}\n", .{ size.cols, size.rows }),
            }
        }
    }

    /// Write all inspector data (widgets, events) as JSON to the given writer.
    /// Useful for external analysis tools or serializing inspector state.
    pub fn writeJSON(self: *const Inspector, writer: anytype) !void {
        try writer.writeAll("{");

        // Widgets
        try writer.writeAll("\"widgets\":[");
        var first_widget = true;
        for (self.widget_order.items) |widget_id| {
            const widget = self.widgets.get(widget_id) orelse continue;

            if (!first_widget) try writer.writeAll(",");
            first_widget = false;

            try writer.print("{{\"id\":{},\"name\":\"{s}\",\"area\":{{\"x\":{},\"y\":{},\"width\":{},\"height\":{}}}",
                .{ widget.id, widget.name, widget.area.x, widget.area.y, widget.area.width, widget.area.height });

            if (widget.parent_id) |parent_id| {
                try writer.print(",\"parent\":{}", .{parent_id});
            }

            try writer.writeAll("}");
        }
        try writer.writeAll("]");

        // Events
        try writer.writeAll(",\"events\":[");
        var first_event = true;
        for (self.events.items) |event| {
            if (!first_event) try writer.writeAll(",");
            first_event = false;

            try writer.print("{{\"timestamp\":{},\"type\":\"{s}\"", .{ event.timestamp, @tagName(event.event_type) });

            switch (event.data) {
                .keyboard => |key| try writer.print(",\"key\":{}", .{key}),
                .mouse_move => |pos| try writer.print(",\"x\":{},\"y\":{}", .{ pos.x, pos.y }),
                .mouse_click => |click| try writer.print(",\"x\":{},\"y\":{},\"button\":\"{s}\"", .{ click.x, click.y, @tagName(click.button) }),
                .mouse_scroll => |scroll| try writer.print(",\"delta\":{}", .{scroll.delta}),
                .resize => |size| try writer.print(",\"cols\":{},\"rows\":{}", .{ size.cols, size.rows }),
            }

            try writer.writeAll("}");
        }
        try writer.writeAll("]");

        try writer.writeAll("}");
    }
};
