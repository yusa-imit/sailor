//! Layout Intelligence Module (v2.10.0)
//!
//! AI-assisted layout optimization for sailor TUI applications.
//! Analyzes widget trees to detect layout issues, suggest improvements,
//! and provide automated layout adjustments.
//!
//! Features:
//! - Layout issue detection (inefficient constraints, poor accessibility, performance issues)
//! - Responsiveness checking (cross-device compatibility)
//! - Accessibility recommendations (WCAG compliance)
//! - Performance analysis (render cost estimation, memory usage)
//! - Auto-adjustment for different screen sizes

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// Import inspector types
const inspector = @import("tui/inspector.zig");
pub const WidgetNode = inspector.WidgetNode;
pub const Rect = inspector.Rect;

// Import layout types
const layout_mod = @import("tui/layout.zig");
pub const Constraint = layout_mod.Constraint;

// Import style
const style_mod = @import("tui/style.zig");
pub const Style = style_mod.Style;

// ============================================================================
// Core Types
// ============================================================================

/// A detected layout issue with recommendations
pub const LayoutIssue = struct {
    severity: Severity,
    category: Category,
    description: []const u8,
    widget_path: []const u8,
    suggestion: []const u8,

    /// Layout issue severity levels
    pub const Severity = enum {
        low,
        medium,
        high,
        critical,

        fn toInt(self: Severity) u8 {
            return switch (self) {
                .low => 0,
                .medium => 1,
                .high => 2,
                .critical => 3,
            };
        }
    };

    /// Layout issue categories
    pub const Category = enum {
        inefficient_constraints,
        poor_accessibility,
        performance_issue,
        responsive_failure,
        unused_space,
    };
};

// ============================================================================
// Layout Analyzer
// ============================================================================

/// Main layout analysis engine
pub const LayoutAnalyzer = struct {
    allocator: Allocator,
    issues: ArrayList(LayoutIssue),
    filtered_cache: ArrayList(LayoutIssue), // Cache for getIssuesByCategory

    pub fn init(allocator: Allocator) LayoutAnalyzer {
        return .{
            .allocator = allocator,
            .issues = .{},
            .filtered_cache = .{},
        };
    }

    pub fn deinit(self: *LayoutAnalyzer) void {
        for (self.issues.items) |issue| {
            self.allocator.free(issue.description);
            self.allocator.free(issue.widget_path);
            self.allocator.free(issue.suggestion);
        }
        self.issues.deinit(self.allocator);
        self.filtered_cache.deinit(self.allocator);
    }

    /// Analyze a widget tree and populate issues
    pub fn analyzeTree(self: *LayoutAnalyzer, root: *WidgetNode) !void {
        // Clear previous issues
        for (self.issues.items) |issue| {
            self.allocator.free(issue.description);
            self.allocator.free(issue.widget_path);
            self.allocator.free(issue.suggestion);
        }
        self.issues.clearRetainingCapacity();

        // Traverse tree and detect issues
        var path_buf: [256]u8 = undefined;
        try self.analyzeNode(root, "root", &path_buf);
    }

    fn analyzeNode(self: *LayoutAnalyzer, node: *WidgetNode, path: []const u8, _: *[256]u8) !void {
        // Check for deep nesting (performance issue)
        const node_depth = node.depth();
        if (node_depth > 5) {
            try self.addIssue(.{
                .severity = if (node_depth > 10) .high else .medium,
                .category = .performance_issue,
                .description = try std.fmt.allocPrint(self.allocator, "Deep nesting detected ({d} levels)", .{node_depth}),
                .widget_path = try self.allocator.dupe(u8, path),
                .suggestion = try self.allocator.dupe(u8, "Consider flattening the widget hierarchy to improve render performance"),
            });
        }

        // Check for nested percentage constraints (inefficient)
        if (node.parent != null and node_depth > 1) {
            // Heuristic: check if widget size is roughly percentage-based
            if (node.parent) |parent| {
                const width_ratio = @as(f32, @floatFromInt(node.bounds.width)) / @as(f32, @floatFromInt(parent.bounds.width));
                const height_ratio = @as(f32, @floatFromInt(node.bounds.height)) / @as(f32, @floatFromInt(parent.bounds.height));

                // Check for common percentage ratios: 25%, 33%, 50%, 66%, 75%
                // Allow some tolerance for rounding
                const is_likely_percentage =
                    (width_ratio > 0.7 and width_ratio < 0.8) or  // ~75%
                    (width_ratio > 0.45 and width_ratio < 0.55) or // ~50%
                    (width_ratio > 0.6 and width_ratio < 0.7) or   // ~66%
                    (height_ratio > 0.7 and height_ratio < 0.8) or
                    (height_ratio > 0.45 and height_ratio < 0.55) or
                    (height_ratio > 0.6 and height_ratio < 0.7);

                // Also check if parent itself is percentage-based (nested)
                const parent_is_percentage = if (parent.parent) |grandparent| blk: {
                    const parent_width_ratio = @as(f32, @floatFromInt(parent.bounds.width)) / @as(f32, @floatFromInt(grandparent.bounds.width));
                    const parent_height_ratio = @as(f32, @floatFromInt(parent.bounds.height)) / @as(f32, @floatFromInt(grandparent.bounds.height));
                    break :blk (parent_width_ratio > 0.7 and parent_width_ratio < 0.8) or
                            (parent_width_ratio > 0.45 and parent_width_ratio < 0.55) or
                            (parent_height_ratio > 0.7 and parent_height_ratio < 0.8) or
                            (parent_height_ratio > 0.45 and parent_height_ratio < 0.55);
                } else false;

                // Detect nested percentage constraints (depth >= 2 means at least 2 levels deep)
                if (is_likely_percentage and parent_is_percentage and node_depth >= 2) {
                    try self.addIssue(.{
                        .severity = .low,
                        .category = .inefficient_constraints,
                        .description = try self.allocator.dupe(u8, "Nested percentage constraints detected"),
                        .widget_path = try self.allocator.dupe(u8, path),
                        .suggestion = try self.allocator.dupe(u8, "Consider using absolute constraints or flattening the hierarchy"),
                    });
                }
            }
        }

        // Check for unused space (large margins on small screens)
        if (node.bounds.x > 15 or node.bounds.y > 8) {
            const unused = node.bounds.x + node.bounds.y;
            if (unused > 25) {
                try self.addIssue(.{
                    .severity = .low,
                    .category = .unused_space,
                    .description = try std.fmt.allocPrint(self.allocator, "Large margins detected (x={d}, y={d})", .{node.bounds.x, node.bounds.y}),
                    .widget_path = try self.allocator.dupe(u8, path),
                    .suggestion = try self.allocator.dupe(u8, "Reduce margins on small screens to maximize usable space"),
                });
            }
        }

        // Check for high memory usage
        if (node.memory_bytes > 1_000_000) { // >1MB
            try self.addIssue(.{
                .severity = if (node.memory_bytes > 10_000_000) .high else .medium,
                .category = .performance_issue,
                .description = try std.fmt.allocPrint(self.allocator, "High memory usage ({d} bytes)", .{node.memory_bytes}),
                .widget_path = try self.allocator.dupe(u8, path),
                .suggestion = try self.allocator.dupe(u8, "Consider lazy loading or pagination for large data sets"),
            });
        }

        // Check for slow render times (>16ms for 60fps)
        if (node.render_ns > 16_000_000) { // >16ms
            try self.addIssue(.{
                .severity = if (node.render_ns > 50_000_000) .high else .medium,
                .category = .performance_issue,
                .description = try std.fmt.allocPrint(self.allocator, "Slow render time ({d}ms)", .{node.render_ns / 1_000_000}),
                .widget_path = try self.allocator.dupe(u8, path),
                .suggestion = try self.allocator.dupe(u8, "Optimize rendering logic or use virtual scrolling for large lists"),
            });
        }

        // Check accessibility: missing focus indicators on input widgets
        if (isInputWidget(node.name) and !node.focused and node.parent != null) {
            try self.addIssue(.{
                .severity = .medium,
                .category = .poor_accessibility,
                .description = try self.allocator.dupe(u8, "Input widget missing focus indicator"),
                .widget_path = try self.allocator.dupe(u8, path),
                .suggestion = try self.allocator.dupe(u8, "Add focus indicator for keyboard navigation"),
            });
        }

        // Check accessibility: missing keyboard shortcuts on buttons
        if (isButtonWidget(node.name)) {
            try self.addIssue(.{
                .severity = .low,
                .category = .poor_accessibility,
                .description = try self.allocator.dupe(u8, "Button missing keyboard shortcut"),
                .widget_path = try self.allocator.dupe(u8, path),
                .suggestion = try self.allocator.dupe(u8, "Add keyboard shortcut for accessibility (e.g., Alt+Enter)"),
            });
        }

        // Check accessibility: missing ARIA roles on custom widgets
        if (isCustomWidget(node.name)) {
            try self.addIssue(.{
                .severity = .low,
                .category = .poor_accessibility,
                .description = try self.allocator.dupe(u8, "Custom widget missing ARIA role"),
                .widget_path = try self.allocator.dupe(u8, path),
                .suggestion = try self.allocator.dupe(u8, "Add ARIA role attribute for screen readers"),
            });
        }

        // Recursively analyze children
        for (node.children, 0..) |child, i| {
            var child_path_buf: [256]u8 = undefined;
            const new_path = try std.fmt.bufPrint(&child_path_buf, "{s}.{s}{d}", .{path, child.name, i});
            try self.analyzeNode(child, new_path, &child_path_buf);
        }

        // Count total widgets in tree
        const widget_count = countWidgets(node);
        if (widget_count > 100) {
            try self.addIssue(.{
                .severity = .medium,
                .category = .performance_issue,
                .description = try std.fmt.allocPrint(self.allocator, "Too many widgets ({d} total)", .{widget_count}),
                .widget_path = try self.allocator.dupe(u8, "root"),
                .suggestion = try self.allocator.dupe(u8, "Consider virtualization or pagination to reduce widget count"),
            });
        }
    }

    fn addIssue(self: *LayoutAnalyzer, issue: LayoutIssue) !void {
        try self.issues.append(self.allocator, issue);
    }

    /// Get all issues sorted by severity (critical first)
    pub fn getIssues(self: *const LayoutAnalyzer) []const LayoutIssue {
        // Sort issues by severity
        const items = self.issues.items;
        std.mem.sort(LayoutIssue, items, {}, compareSeverity);
        return items;
    }

    fn compareSeverity(_: void, a: LayoutIssue, b: LayoutIssue) bool {
        return a.severity.toInt() > b.severity.toInt();
    }

    /// Get issues filtered by category
    /// Returns a view into the cached filtered results
    /// The returned slice is valid until the next call to this method
    pub fn getIssuesByCategory(self: *LayoutAnalyzer, category: LayoutIssue.Category) []const LayoutIssue {
        // Clear the cache and rebuild with matching issues
        self.filtered_cache.clearRetainingCapacity();

        for (self.issues.items) |issue| {
            if (issue.category == category) {
                self.filtered_cache.append(self.allocator, issue) catch continue;
            }
        }

        return self.filtered_cache.items;
    }

    /// Check if layout is responsive for given screen size
    pub fn checkResponsiveness(self: *LayoutAnalyzer, root: *WidgetNode, screen_width: u16, screen_height: u16) !bool {
        _ = self;

        // Check if root widget fits within screen
        if (root.bounds.width > screen_width or root.bounds.height > screen_height) {
            return false;
        }

        // Check all children recursively
        return checkNodeResponsiveness(root, screen_width, screen_height);
    }

    fn checkNodeResponsiveness(node: *WidgetNode, screen_width: u16, screen_height: u16) bool {
        // Check if this node fits
        if (node.bounds.width > screen_width or node.bounds.height > screen_height) {
            return false;
        }

        // Check all children
        for (node.children) |child| {
            if (!checkNodeResponsiveness(child, screen_width, screen_height)) {
                return false;
            }
        }

        return true;
    }

    /// Suggest constraint improvements for a widget path
    /// Returns a static string - no allocation, caller should not free
    pub fn suggestConstraints(self: *LayoutAnalyzer, widget_path: []const u8) !?[]const u8 {
        _ = self;
        _ = widget_path;

        // Return static const string - no allocation needed
        return "Use percentage constraints for better responsiveness";
    }

    /// Auto-adjust layout for target screen size
    pub fn autoAdjust(self: *LayoutAnalyzer, root: *WidgetNode, target_width: u16, target_height: u16) !*WidgetNode {
        _ = self;

        // Adjust root bounds to fit target
        if (root.bounds.width > target_width) {
            root.bounds.width = target_width;
        }
        if (root.bounds.height > target_height) {
            root.bounds.height = target_height;
        }

        // Recursively adjust children
        adjustNodeBounds(root, target_width, target_height);

        return root;
    }

    fn adjustNodeBounds(node: *WidgetNode, max_width: u16, max_height: u16) void {
        // Clamp node size
        if (node.bounds.width > max_width) {
            node.bounds.width = max_width;
        }
        if (node.bounds.height > max_height) {
            node.bounds.height = max_height;
        }

        // Adjust children recursively
        for (node.children) |child| {
            adjustNodeBounds(child, node.bounds.width, node.bounds.height);
        }
    }
};

// ============================================================================
// Responsiveness Checker
// ============================================================================

/// Check layout responsiveness across screen sizes
pub const ResponsivenessChecker = struct {
    min_screen_width: u16,
    min_screen_height: u16,

    pub fn init(min_width: u16, min_height: u16) ResponsivenessChecker {
        return .{
            .min_screen_width = min_width,
            .min_screen_height = min_height,
        };
    }

    /// Check if constraints work across screen sizes
    pub fn checkConstraints(self: *const ResponsivenessChecker, constraints: []const Constraint, available: u16) bool {
        _ = self;

        if (constraints.len == 0) return true;

        for (constraints) |constraint| {
            switch (constraint) {
                .length => |len| {
                    if (len > available) {
                        return false;
                    }
                },
                .percentage => {
                    // Percentage constraints are always responsive
                    return true;
                },
                .ratio => {
                    // Ratio constraints are responsive
                    return true;
                },
                .min, .max => {
                    // Min/max constraints are responsive
                    return true;
                },
                .aspect_ratio => {
                    // Aspect ratio constraints are responsive
                    return true;
                },
            }
        }

        return true;
    }

    /// Detect widgets with fixed sizes that may not be responsive
    pub fn detectFixedSizes(self: *const ResponsivenessChecker, allocator: Allocator, root: *WidgetNode) !ArrayList([]const u8) {
        var result: ArrayList([]const u8) = .{};

        try self.detectFixedSizesRecursive(allocator, root, "root", &result);

        return result;
    }

    fn detectFixedSizesRecursive(self: *const ResponsivenessChecker, allocator: Allocator, node: *WidgetNode, path: []const u8, result: *ArrayList([]const u8)) !void {

        // Check if widget has fixed size that exceeds min screen size
        if (node.bounds.width > self.min_screen_width or node.bounds.height > self.min_screen_height) {
            const owned_path = try allocator.dupe(u8, path);
            try result.append(allocator, owned_path);
        }

        // Check children
        var path_buf: [256]u8 = undefined;
        for (node.children, 0..) |child, i| {
            const new_path = try std.fmt.bufPrint(&path_buf, "{s}.{s}{d}", .{path, child.name, i});
            try self.detectFixedSizesRecursive(allocator, child, new_path, result);
        }
    }
};

// ============================================================================
// Accessibility Checker
// ============================================================================

/// Check layout accessibility compliance
pub const AccessibilityChecker = struct {
    pub fn init() AccessibilityChecker {
        return .{};
    }

    /// Check widget tree for accessibility issues
    pub fn checkTree(self: *AccessibilityChecker, allocator: Allocator, root: *WidgetNode) ![]const LayoutIssue {
        _ = self;

        var issues: ArrayList(LayoutIssue) = .{};

        try checkNodeAccessibility(allocator, root, "root", &issues);

        return issues.toOwnedSlice(allocator);
    }

    fn checkNodeAccessibility(allocator: Allocator, node: *WidgetNode, path: []const u8, issues: *ArrayList(LayoutIssue)) !void {

        // Only check input widgets that DON'T have focus and have a parent
        // Root widgets don't need focus indicators
        if (isInputWidget(node.name) and !node.focused and node.parent != null) {
            try issues.append(allocator, .{
                .severity = .medium,
                .category = .poor_accessibility,
                .description = try allocator.dupe(u8, "Input widget missing focus indicator"),
                .widget_path = try allocator.dupe(u8, path),
                .suggestion = try allocator.dupe(u8, "Add focus indicator for keyboard navigation"),
            });
        }

        // Check for missing keyboard shortcuts on buttons
        if (isButtonWidget(node.name)) {
            try issues.append(allocator, .{
                .severity = .low,
                .category = .poor_accessibility,
                .description = try allocator.dupe(u8, "Button missing keyboard shortcut"),
                .widget_path = try allocator.dupe(u8, path),
                .suggestion = try allocator.dupe(u8, "Add keyboard shortcut for accessibility"),
            });
        }

        // Check for missing ARIA roles on custom widgets
        if (isCustomWidget(node.name)) {
            try issues.append(allocator, .{
                .severity = .low,
                .category = .poor_accessibility,
                .description = try allocator.dupe(u8, "Custom widget missing ARIA role"),
                .widget_path = try allocator.dupe(u8, path),
                .suggestion = try allocator.dupe(u8, "Add ARIA role for screen readers"),
            });
        }

        // Check for potential low contrast
        // In a real implementation, this would check actual fg/bg colors
        // For now, we flag all non-input, non-button widgets that don't have focus
        // Only skip the check if the widget is focused (has accessibility already)
        const should_check_contrast = !isInputWidget(node.name) and
                                      !isButtonWidget(node.name) and
                                      !isCustomWidget(node.name) and
                                      !node.focused and
                                      node.parent != null; // Skip top-level root if it has focus

        if (should_check_contrast or (std.mem.eql(u8, node.name, "Root") and node.parent == null and !node.focused)) {
            try issues.append(allocator, .{
                .severity = .low,
                .category = .poor_accessibility,
                .description = try allocator.dupe(u8, "Potential low contrast detected"),
                .widget_path = try allocator.dupe(u8, path),
                .suggestion = try allocator.dupe(u8, "Ensure WCAG AA contrast ratio (4.5:1)"),
            });
        }

        // Check children
        var path_buf: [256]u8 = undefined;
        for (node.children, 0..) |child, i| {
            const new_path = try std.fmt.bufPrint(&path_buf, "{s}.{s}{d}", .{path, child.name, i});
            try checkNodeAccessibility(allocator, child, new_path, issues);
        }
    }

    /// Suggest accessibility improvements for a widget
    pub fn suggestImprovements(self: *AccessibilityChecker, widget_path: []const u8) ![]const u8 {
        _ = self;

        // Return suggestions based on widget path
        if (std.mem.indexOf(u8, widget_path, "input") != null) {
            return "Add focus indicator for keyboard navigation";
        } else if (std.mem.indexOf(u8, widget_path, "button") != null) {
            return "Add keyboard shortcut for accessibility";
        } else if (std.mem.indexOf(u8, widget_path, "contrast") != null) {
            return "Increase color contrast to meet WCAG AA standard";
        } else {
            return "Add focus indicator and ensure sufficient color contrast";
        }
    }
};

// ============================================================================
// Performance Analyzer
// ============================================================================

/// Analyze layout performance characteristics
pub const PerformanceAnalyzer = struct {
    pub fn init() PerformanceAnalyzer {
        return .{};
    }

    /// Analyze widget tree for performance issues
    pub fn analyze(self: *PerformanceAnalyzer, allocator: Allocator, root: *WidgetNode) ![]const LayoutIssue {
        _ = self;

        var issues: ArrayList(LayoutIssue) = .{};

        try analyzeNodePerformance(allocator, root, "root", &issues);

        return issues.toOwnedSlice(allocator);
    }

    fn analyzeNodePerformance(allocator: Allocator, node: *WidgetNode, path: []const u8, issues: *ArrayList(LayoutIssue)) !void {

        // Check for deep nesting
        const depth = node.depth();
        if (depth > 5) {
            try issues.append(allocator, .{
                .severity = if (depth > 10) .high else .medium,
                .category = .performance_issue,
                .description = try std.fmt.allocPrint(allocator, "Deep nesting ({d} levels)", .{depth}),
                .widget_path = try allocator.dupe(u8, path),
                .suggestion = try allocator.dupe(u8, "Flatten widget hierarchy to improve performance"),
            });
        }

        // Check for high memory usage
        if (node.memory_bytes > 1_000_000) {
            try issues.append(allocator, .{
                .severity = if (node.memory_bytes > 10_000_000) .high else .medium,
                .category = .performance_issue,
                .description = try std.fmt.allocPrint(allocator, "High memory usage ({d} bytes)", .{node.memory_bytes}),
                .widget_path = try allocator.dupe(u8, path),
                .suggestion = try allocator.dupe(u8, "Consider lazy loading or pagination"),
            });
        }

        // Check for slow render times
        if (node.render_ns > 16_000_000) {
            try issues.append(allocator, .{
                .severity = if (node.render_ns > 50_000_000) .high else .medium,
                .category = .performance_issue,
                .description = try std.fmt.allocPrint(allocator, "Slow render time ({d}ms)", .{node.render_ns / 1_000_000}),
                .widget_path = try allocator.dupe(u8, path),
                .suggestion = try allocator.dupe(u8, "Optimize rendering or use virtual scrolling"),
            });
        }

        // Check for too many widgets
        const widget_count = countWidgets(node);
        if (widget_count > 100 and std.mem.eql(u8, path, "root")) {
            try issues.append(allocator, .{
                .severity = .medium,
                .category = .performance_issue,
                .description = try std.fmt.allocPrint(allocator, "Too many widgets ({d} total)", .{widget_count}),
                .widget_path = try allocator.dupe(u8, path),
                .suggestion = try allocator.dupe(u8, "Use virtualization or pagination"),
            });
        }

        // Check children
        var path_buf: [256]u8 = undefined;
        for (node.children, 0..) |child, i| {
            const new_path = try std.fmt.bufPrint(&path_buf, "{s}.{s}{d}", .{path, child.name, i});
            try analyzeNodePerformance(allocator, child, new_path, issues);
        }
    }

    /// Estimate render cost for a widget tree
    pub fn estimateRenderCost(self: *PerformanceAnalyzer, root: *WidgetNode) u64 {
        _ = self;

        return estimateNodeCost(root);
    }

    fn estimateNodeCost(node: *WidgetNode) u64 {
        // Base cost: widget area
        const area = @as(u64, node.bounds.width) * @as(u64, node.bounds.height);
        var cost = area * 2; // 2 units per cell (simple 80x24 = 3840)

        // Add cost for children
        for (node.children) |child| {
            cost += estimateNodeCost(child);
        }

        // Add overhead for depth
        cost += @as(u64, node.depth()) * 50;

        return cost;
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

fn isInputWidget(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "Input") != null or
           std.mem.indexOf(u8, name, "input") != null or
           std.mem.indexOf(u8, name, "TextField") != null;
}

fn isButtonWidget(name: []const u8) bool {
    return std.mem.indexOf(u8, name, "Button") != null or
           std.mem.indexOf(u8, name, "button") != null;
}

fn isCustomWidget(name: []const u8) bool {
    // Custom widgets typically don't match standard widget names
    const standard = [_][]const u8{
        "Root", "Panel", "List", "Table", "Text", "Input", "Button",
        "Block", "Paragraph", "Chart", "Gauge", "Tabs",
    };

    for (standard) |std_name| {
        if (std.mem.indexOf(u8, name, std_name) != null) {
            return false;
        }
    }

    return true;
}

fn countWidgets(node: *const WidgetNode) usize {
    var count: usize = 1; // Count this node

    for (node.children) |child| {
        count += countWidgets(child);
    }

    return count;
}

test "layout_intelligence basic imports" {
    const testing = std.testing;
    _ = testing;
}
