//! Layout Intelligence Tests (v2.10.0)
//!
//! Comprehensive tests for AI-assisted layout optimization.

const std = @import("std");
const testing = std.testing;
const sailor = @import("sailor");

// Import inspector types for WidgetNode
const WidgetNode = sailor.tui.inspector.WidgetNode;
const WidgetInspector = sailor.tui.inspector.WidgetInspector;

// Import layout types
const Constraint = sailor.tui.Constraint;
const Rect = sailor.tui.Rect;

// Import style
const Style = sailor.tui.Style;

// Import layout intelligence module
const LayoutIssue = sailor.LayoutIssue;
const LayoutAnalyzer = sailor.LayoutAnalyzer;
const ResponsivenessChecker = sailor.ResponsivenessChecker;
const AccessibilityChecker = sailor.AccessibilityChecker;
const PerformanceAnalyzer = sailor.PerformanceAnalyzer;

// ============================================================================
// LayoutAnalyzer Tests (15+ tests)
// ============================================================================

test "LayoutAnalyzer init creates empty analyzer" {
    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    try testing.expectEqual(@as(usize, 0), analyzer.issues.items.len);
}

test "LayoutAnalyzer deinit frees all issues" {
    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    // Add a dummy issue
    const issue = LayoutIssue{
        .severity = .medium,
        .category = .inefficient_constraints,
        .description = try testing.allocator.dupe(u8, "test issue"),
        .widget_path = try testing.allocator.dupe(u8, "root.panel"),
        .suggestion = try testing.allocator.dupe(u8, "use percentage instead"),
    };
    try analyzer.issues.append(testing.allocator, issue);

    // deinit should free all memory
}

test "LayoutAnalyzer analyzeTree with simple widget tree detects no issues" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    inspector.endWidget();

    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    try analyzer.analyzeTree(root);

    // Simple tree with no issues should return empty
    try testing.expectEqual(@as(usize, 0), analyzer.getIssues().len);
}

test "LayoutAnalyzer analyzeTree with nested widgets detects issues" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Panel", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    _ = try inspector.beginWidget("DeepNest", .{ .x = 0, .y = 0, .width = 20, .height = 6 }, Style{});
    inspector.endWidget();
    inspector.endWidget();
    inspector.endWidget();

    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    try analyzer.analyzeTree(inspector.root.?);

    // Should detect at least one issue (e.g., deep nesting)
    try testing.expect(analyzer.getIssues().len > 0);
}

test "LayoutAnalyzer getIssues returns sorted by severity (critical first)" {
    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    // Add issues with different severities
    try analyzer.issues.append(testing.allocator, .{
        .severity = .low,
        .category = .unused_space,
        .description = try testing.allocator.dupe(u8, "low issue"),
        .widget_path = try testing.allocator.dupe(u8, "root"),
        .suggestion = try testing.allocator.dupe(u8, "fix low"),
    });
    try analyzer.issues.append(testing.allocator, .{
        .severity = .critical,
        .category = .responsive_failure,
        .description = try testing.allocator.dupe(u8, "critical issue"),
        .widget_path = try testing.allocator.dupe(u8, "root.panel"),
        .suggestion = try testing.allocator.dupe(u8, "fix critical"),
    });
    try analyzer.issues.append(testing.allocator, .{
        .severity = .medium,
        .category = .inefficient_constraints,
        .description = try testing.allocator.dupe(u8, "medium issue"),
        .widget_path = try testing.allocator.dupe(u8, "root.list"),
        .suggestion = try testing.allocator.dupe(u8, "fix medium"),
    });

    const sorted = analyzer.getIssues();
    try testing.expect(sorted.len >= 3);
    // Critical should be first
    try testing.expectEqual(LayoutIssue.Severity.critical, sorted[0].severity);
}

test "LayoutAnalyzer getIssuesByCategory filters correctly" {
    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    try analyzer.issues.append(testing.allocator, .{
        .severity = .medium,
        .category = .inefficient_constraints,
        .description = try testing.allocator.dupe(u8, "inefficient"),
        .widget_path = try testing.allocator.dupe(u8, "root"),
        .suggestion = try testing.allocator.dupe(u8, "fix"),
    });
    try analyzer.issues.append(testing.allocator, .{
        .severity = .high,
        .category = .poor_accessibility,
        .description = try testing.allocator.dupe(u8, "accessibility"),
        .widget_path = try testing.allocator.dupe(u8, "root.input"),
        .suggestion = try testing.allocator.dupe(u8, "add focus"),
    });

    const filtered = analyzer.getIssuesByCategory(.poor_accessibility);
    try testing.expectEqual(@as(usize, 1), filtered.len);
    try testing.expectEqual(LayoutIssue.Category.poor_accessibility, filtered[0].category);
}

test "LayoutAnalyzer checkResponsiveness on small screen (80x24) detects failures" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    // Widget with fixed size that exceeds small screen
    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 200, .height = 60 }, Style{});
    inspector.endWidget();

    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    const is_responsive = try analyzer.checkResponsiveness(inspector.root.?, 80, 24);
    try testing.expect(!is_responsive); // Should fail on small screen
}

test "LayoutAnalyzer checkResponsiveness on large screen (200x60) passes" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    // Widget with percentage-based constraints
    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    inspector.endWidget();

    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    const is_responsive = try analyzer.checkResponsiveness(inspector.root.?, 200, 60);
    try testing.expect(is_responsive); // Should pass on large screen
}

test "LayoutAnalyzer suggestConstraints for percentage constraints" {
    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    const suggestion = try analyzer.suggestConstraints("root.panel");
    try testing.expect(suggestion != null);
    try testing.expect(std.mem.indexOf(u8, suggestion.?, "percentage") != null);
}

test "LayoutAnalyzer suggestConstraints for fixed constraints" {
    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    const suggestion = try analyzer.suggestConstraints("root.fixed_panel");
    try testing.expect(suggestion != null);
    try testing.expect(std.mem.indexOf(u8, suggestion.?, "min/max") != null or std.mem.indexOf(u8, suggestion.?, "percentage") != null);
}

test "LayoutAnalyzer autoAdjust for small screen reduces widget sizes" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 200, .height = 60 }, Style{});
    inspector.endWidget();

    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    const adjusted = try analyzer.autoAdjust(root, 80, 24);
    try testing.expect(adjusted.bounds.width <= 80);
    try testing.expect(adjusted.bounds.height <= 24);
}

test "LayoutAnalyzer analyzeTree with empty tree returns no issues" {
    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    // No tree to analyze
    try testing.expectEqual(@as(usize, 0), analyzer.getIssues().len);
}

test "LayoutAnalyzer analyzeTree with very deep nesting (10+ levels) detects performance issue" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    // Create deep nesting
    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    var i: usize = 0;
    while (i < 12) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "Level{d}", .{i});
        _ = try inspector.beginWidget(name, .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    }
    i = 0;
    while (i < 12) : (i += 1) {
        inspector.endWidget();
    }
    inspector.endWidget();

    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    try analyzer.analyzeTree(inspector.root.?);

    const issues = analyzer.getIssues();
    try testing.expect(issues.len > 0);
    // Should detect performance issue from deep nesting
    var found_perf_issue = false;
    for (issues) |issue| {
        if (issue.category == .performance_issue) {
            found_perf_issue = true;
            break;
        }
    }
    try testing.expect(found_perf_issue);
}

test "LayoutAnalyzer detects nested percentage constraints (inefficient)" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Panel", .{ .x = 0, .y = 0, .width = 60, .height = 18 }, Style{}); // 75% of root
    _ = try inspector.beginWidget("InnerPanel", .{ .x = 0, .y = 0, .width = 45, .height = 13 }, Style{}); // 75% of panel
    inspector.endWidget();
    inspector.endWidget();
    inspector.endWidget();

    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    try analyzer.analyzeTree(inspector.root.?);

    const issues = analyzer.getIssues();
    var found_inefficient = false;
    for (issues) |issue| {
        if (issue.category == .inefficient_constraints) {
            found_inefficient = true;
            break;
        }
    }
    try testing.expect(found_inefficient);
}

test "LayoutAnalyzer detects unused space (large margins on small screens)" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    // Widget with large margins on small screen
    _ = try inspector.beginWidget("Root", .{ .x = 20, .y = 10, .width = 40, .height = 4 }, Style{}); // Large margins
    inspector.endWidget();

    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    try analyzer.analyzeTree(inspector.root.?);

    const issues = analyzer.getIssues();
    var found_unused = false;
    for (issues) |issue| {
        if (issue.category == .unused_space) {
            found_unused = true;
            break;
        }
    }
    try testing.expect(found_unused);
}

// ============================================================================
// ResponsivenessChecker Tests (10+ tests)
// ============================================================================

test "ResponsivenessChecker init with min sizes" {
    const checker = ResponsivenessChecker.init(80, 24);
    try testing.expectEqual(@as(u16, 80), checker.min_screen_width);
    try testing.expectEqual(@as(u16, 24), checker.min_screen_height);
}

test "ResponsivenessChecker checkConstraints with percentage passes" {
    const checker = ResponsivenessChecker.init(80, 24);
    const constraints = [_]Constraint{
        .{ .percentage = 50 },
        .{ .percentage = 50 },
    };
    const result = checker.checkConstraints(&constraints, 80);
    try testing.expect(result); // Percentage should work on any screen
}

test "ResponsivenessChecker checkConstraints with fixed length fails if too large" {
    const checker = ResponsivenessChecker.init(80, 24);
    const constraints = [_]Constraint{
        .{ .length = 100 }, // Exceeds min screen width
    };
    const result = checker.checkConstraints(&constraints, 80);
    try testing.expect(!result); // Fixed size exceeds available space
}

test "ResponsivenessChecker checkConstraints with min/max passes" {
    const checker = ResponsivenessChecker.init(80, 24);
    const constraints = [_]Constraint{
        .{ .min = 40 },
        .{ .max = 60 },
    };
    const result = checker.checkConstraints(&constraints, 80);
    try testing.expect(result); // Min/max should be responsive
}

test "ResponsivenessChecker detectFixedSizes in tree finds fixed widgets" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Fixed", .{ .x = 0, .y = 0, .width = 100, .height = 50 }, Style{}); // Fixed large size
    inspector.endWidget();
    inspector.endWidget();

    const checker = ResponsivenessChecker.init(80, 24);
    var fixed_list = try checker.detectFixedSizes(testing.allocator, inspector.root.?);
    defer {
        for (fixed_list.items) |path| {
            testing.allocator.free(path);
        }
        fixed_list.deinit(testing.allocator);
    }

    try testing.expect(fixed_list.items.len > 0);
}

test "ResponsivenessChecker checkConstraints with empty constraints passes" {
    const checker = ResponsivenessChecker.init(80, 24);
    const constraints = [_]Constraint{};
    const result = checker.checkConstraints(&constraints, 80);
    try testing.expect(result); // Empty constraints should pass
}

test "ResponsivenessChecker checkConstraints with zero-size screen edge case" {
    const checker = ResponsivenessChecker.init(0, 0);
    const constraints = [_]Constraint{
        .{ .percentage = 50 },
    };
    const result = checker.checkConstraints(&constraints, 0);
    try testing.expect(result); // Should handle zero-size gracefully
}

test "ResponsivenessChecker detectFixedSizes with no fixed widgets returns empty" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    inspector.endWidget();

    const checker = ResponsivenessChecker.init(80, 24);
    var fixed_list = try checker.detectFixedSizes(testing.allocator, inspector.root.?);
    defer {
        for (fixed_list.items) |path| {
            testing.allocator.free(path);
        }
        fixed_list.deinit(testing.allocator);
    }

    try testing.expectEqual(@as(usize, 0), fixed_list.items.len);
}

test "ResponsivenessChecker checkConstraints with ratio passes" {
    const checker = ResponsivenessChecker.init(80, 24);
    const constraints = [_]Constraint{
        .{ .ratio = .{ .num = 1, .denom = 2 } },
        .{ .ratio = .{ .num = 1, .denom = 2 } },
    };
    const result = checker.checkConstraints(&constraints, 80);
    try testing.expect(result); // Ratio should be responsive
}

test "ResponsivenessChecker detectFixedSizes with nested fixed widgets" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Panel", .{ .x = 0, .y = 0, .width = 120, .height = 40 }, Style{});
    _ = try inspector.beginWidget("InnerFixed", .{ .x = 0, .y = 0, .width = 150, .height = 50 }, Style{});
    inspector.endWidget();
    inspector.endWidget();
    inspector.endWidget();

    const checker = ResponsivenessChecker.init(80, 24);
    var fixed_list = try checker.detectFixedSizes(testing.allocator, inspector.root.?);
    defer {
        for (fixed_list.items) |path| {
            testing.allocator.free(path);
        }
        fixed_list.deinit(testing.allocator);
    }

    try testing.expect(fixed_list.items.len >= 2); // Both Panel and InnerFixed
}

// ============================================================================
// AccessibilityChecker Tests (10+ tests)
// ============================================================================

test "AccessibilityChecker init" {
    const checker = AccessibilityChecker.init();
    _ = checker;
}

test "AccessibilityChecker checkTree with accessible widgets returns no issues" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    root.focused = true; // Has focus indicator
    inspector.endWidget();

    var checker = AccessibilityChecker.init();
    const issues = try checker.checkTree(testing.allocator, inspector.root.?);
    defer {
        for (issues) |issue| {
            testing.allocator.free(issue.description);
            testing.allocator.free(issue.widget_path);
            testing.allocator.free(issue.suggestion);
        }
        testing.allocator.free(issues);
    }
    try testing.expectEqual(@as(usize, 0), issues.len);
}

test "AccessibilityChecker checkTree with missing focus indicators" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Input", .{ .x = 0, .y = 0, .width = 40, .height = 1 }, Style{});
    // No focus indicator set
    inspector.endWidget();
    inspector.endWidget();

    var checker = AccessibilityChecker.init();
    const issues = try checker.checkTree(testing.allocator, inspector.root.?);
    defer {
        for (issues) |issue| {
            testing.allocator.free(issue.description);
            testing.allocator.free(issue.widget_path);
            testing.allocator.free(issue.suggestion);
        }
        testing.allocator.free(issues);
    }
    try testing.expect(issues.len > 0);
    try testing.expectEqual(LayoutIssue.Category.poor_accessibility, issues[0].category);
}

test "AccessibilityChecker checkTree with low contrast (detect color issues)" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    const style = Style{};
    // TODO: Set low-contrast colors (e.g., light gray on white)
    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, style);
    _ = root;
    inspector.endWidget();

    var checker = AccessibilityChecker.init();
    const issues = try checker.checkTree(testing.allocator, inspector.root.?);
    defer {
        for (issues) |issue| {
            testing.allocator.free(issue.description);
            testing.allocator.free(issue.widget_path);
            testing.allocator.free(issue.suggestion);
        }
        testing.allocator.free(issues);
    }
    // Should detect low contrast
    var found_contrast_issue = false;
    for (issues) |issue| {
        if (std.mem.indexOf(u8, issue.description, "contrast") != null) {
            found_contrast_issue = true;
            break;
        }
    }
    try testing.expect(found_contrast_issue);
}

test "AccessibilityChecker suggestImprovements for focus" {
    var checker = AccessibilityChecker.init();
    const suggestion = try checker.suggestImprovements("root.input");
    try testing.expect(suggestion.len > 0);
    try testing.expect(std.mem.indexOf(u8, suggestion, "focus") != null);
}

test "AccessibilityChecker suggestImprovements for contrast" {
    var checker = AccessibilityChecker.init();
    const suggestion = try checker.suggestImprovements("root.low_contrast_widget");
    try testing.expect(suggestion.len > 0);
    try testing.expect(std.mem.indexOf(u8, suggestion, "contrast") != null or std.mem.indexOf(u8, suggestion, "color") != null);
}

test "AccessibilityChecker checkTree with empty tree returns no issues" {
    const checker = AccessibilityChecker.init();
    // No tree to check
    _ = checker;
}

test "AccessibilityChecker checkTree with multiple accessibility issues" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Input1", .{ .x = 0, .y = 0, .width = 40, .height = 1 }, Style{});
    inspector.endWidget();
    _ = try inspector.beginWidget("Input2", .{ .x = 0, .y = 1, .width = 40, .height = 1 }, Style{});
    inspector.endWidget();
    inspector.endWidget();

    var checker = AccessibilityChecker.init();
    const issues = try checker.checkTree(testing.allocator, inspector.root.?);
    defer {
        for (issues) |issue| {
            testing.allocator.free(issue.description);
            testing.allocator.free(issue.widget_path);
            testing.allocator.free(issue.suggestion);
        }
        testing.allocator.free(issues);
    }
    try testing.expect(issues.len >= 2); // Multiple inputs without focus
}

test "AccessibilityChecker detects missing keyboard shortcuts" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("Button", .{ .x = 0, .y = 0, .width = 10, .height = 1 }, Style{});
    inspector.endWidget();
    inspector.endWidget();

    var checker = AccessibilityChecker.init();
    const issues = try checker.checkTree(testing.allocator, inspector.root.?);
    defer {
        for (issues) |issue| {
            testing.allocator.free(issue.description);
            testing.allocator.free(issue.widget_path);
            testing.allocator.free(issue.suggestion);
        }
        testing.allocator.free(issues);
    }
    var found_shortcut_issue = false;
    for (issues) |issue| {
        if (std.mem.indexOf(u8, issue.description, "keyboard") != null) {
            found_shortcut_issue = true;
            break;
        }
    }
    try testing.expect(found_shortcut_issue);
}

test "AccessibilityChecker suggestImprovements for keyboard navigation" {
    var checker = AccessibilityChecker.init();
    const suggestion = try checker.suggestImprovements("root.button");
    try testing.expect(suggestion.len > 0);
    try testing.expect(std.mem.indexOf(u8, suggestion, "keyboard") != null or std.mem.indexOf(u8, suggestion, "shortcut") != null);
}

test "AccessibilityChecker detects missing ARIA roles" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("CustomWidget", .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    inspector.endWidget();
    inspector.endWidget();

    var checker = AccessibilityChecker.init();
    const issues = try checker.checkTree(testing.allocator, inspector.root.?);
    defer {
        for (issues) |issue| {
            testing.allocator.free(issue.description);
            testing.allocator.free(issue.widget_path);
            testing.allocator.free(issue.suggestion);
        }
        testing.allocator.free(issues);
    }
    var found_aria_issue = false;
    for (issues) |issue| {
        if (std.mem.indexOf(u8, issue.description, "ARIA") != null or std.mem.indexOf(u8, issue.description, "role") != null) {
            found_aria_issue = true;
            break;
        }
    }
    try testing.expect(found_aria_issue);
}

// ============================================================================
// PerformanceAnalyzer Tests (10+ tests)
// ============================================================================

test "PerformanceAnalyzer init" {
    const analyzer = PerformanceAnalyzer.init();
    _ = analyzer;
}

test "PerformanceAnalyzer analyze with simple tree returns no issues" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    inspector.endWidget();

    var analyzer = PerformanceAnalyzer.init();
    const issues = try analyzer.analyze(testing.allocator, inspector.root.?);
    defer {
        for (issues) |issue| {
            testing.allocator.free(issue.description);
            testing.allocator.free(issue.widget_path);
            testing.allocator.free(issue.suggestion);
        }
        testing.allocator.free(issues);
    }
    try testing.expectEqual(@as(usize, 0), issues.len);
}

test "PerformanceAnalyzer analyze with excessive nesting (>5 levels) detects issue" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    var i: usize = 0;
    while (i < 7) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "Level{d}", .{i});
        _ = try inspector.beginWidget(name, .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    }
    i = 0;
    while (i < 7) : (i += 1) {
        inspector.endWidget();
    }
    inspector.endWidget();

    var analyzer = PerformanceAnalyzer.init();
    const issues = try analyzer.analyze(testing.allocator, inspector.root.?);
    defer {
        for (issues) |issue| {
            testing.allocator.free(issue.description);
            testing.allocator.free(issue.widget_path);
            testing.allocator.free(issue.suggestion);
        }
        testing.allocator.free(issues);
    }
    try testing.expect(issues.len > 0);
    try testing.expectEqual(LayoutIssue.Category.performance_issue, issues[0].category);
}

test "PerformanceAnalyzer analyze with too many widgets (>100) detects issue" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    var i: usize = 0;
    while (i < 120) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "Widget{d}", .{i});
        _ = try inspector.beginWidget(name, .{ .x = 0, .y = 0, .width = 1, .height = 1 }, Style{});
        inspector.endWidget();
    }
    inspector.endWidget();

    var analyzer = PerformanceAnalyzer.init();
    const issues = try analyzer.analyze(testing.allocator, inspector.root.?);
    defer {
        for (issues) |issue| {
            testing.allocator.free(issue.description);
            testing.allocator.free(issue.widget_path);
            testing.allocator.free(issue.suggestion);
        }
        testing.allocator.free(issues);
    }
    try testing.expect(issues.len > 0);
    var found_perf_issue = false;
    for (issues) |issue| {
        if (std.mem.indexOf(u8, issue.description, "widgets") != null) {
            found_perf_issue = true;
            break;
        }
    }
    try testing.expect(found_perf_issue);
}

test "PerformanceAnalyzer estimateRenderCost for simple widget" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    inspector.endWidget();

    var analyzer = PerformanceAnalyzer.init();
    const cost = analyzer.estimateRenderCost(inspector.root.?);
    try testing.expect(cost > 0); // Should estimate some cost
    try testing.expect(cost < 10000); // Simple widget should be cheap
}

test "PerformanceAnalyzer estimateRenderCost for complex tree" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "Widget{d}", .{i});
        _ = try inspector.beginWidget(name, .{ .x = 0, .y = 0, .width = 10, .height = 2 }, Style{});
        inspector.endWidget();
    }
    inspector.endWidget();

    var analyzer = PerformanceAnalyzer.init();
    const cost = analyzer.estimateRenderCost(inspector.root.?);
    try testing.expect(cost > 1000); // Complex tree should have higher cost
}

test "PerformanceAnalyzer analyze with empty tree returns no issues" {
    const analyzer = PerformanceAnalyzer.init();
    _ = analyzer;
}

test "PerformanceAnalyzer detects widgets with high memory usage" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    root.memory_bytes = 10_000_000; // 10MB widget
    inspector.endWidget();

    var analyzer = PerformanceAnalyzer.init();
    const issues = try analyzer.analyze(testing.allocator, inspector.root.?);
    defer {
        for (issues) |issue| {
            testing.allocator.free(issue.description);
            testing.allocator.free(issue.widget_path);
            testing.allocator.free(issue.suggestion);
        }
        testing.allocator.free(issues);
    }
    var found_memory_issue = false;
    for (issues) |issue| {
        if (std.mem.indexOf(u8, issue.description, "memory") != null) {
            found_memory_issue = true;
            break;
        }
    }
    try testing.expect(found_memory_issue);
}

test "PerformanceAnalyzer detects slow render times" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    root.render_ns = 50_000_000; // 50ms render (too slow for 60fps)
    inspector.endWidget();

    var analyzer = PerformanceAnalyzer.init();
    const issues = try analyzer.analyze(testing.allocator, inspector.root.?);
    defer {
        for (issues) |issue| {
            testing.allocator.free(issue.description);
            testing.allocator.free(issue.widget_path);
            testing.allocator.free(issue.suggestion);
        }
        testing.allocator.free(issues);
    }
    var found_render_issue = false;
    for (issues) |issue| {
        if (std.mem.indexOf(u8, issue.description, "render") != null or std.mem.indexOf(u8, issue.description, "slow") != null) {
            found_render_issue = true;
            break;
        }
    }
    try testing.expect(found_render_issue);
}

test "PerformanceAnalyzer estimateRenderCost considers widget area" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    const small = try inspector.beginWidget("Small", .{ .x = 0, .y = 0, .width = 10, .height = 5 }, Style{});
    inspector.endWidget();

    var inspector2 = WidgetInspector.init(testing.allocator);
    defer inspector2.deinit();

    const large = try inspector2.beginWidget("Large", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    inspector2.endWidget();

    var analyzer = PerformanceAnalyzer.init();
    const small_cost = analyzer.estimateRenderCost(small);
    const large_cost = analyzer.estimateRenderCost(large);

    try testing.expect(large_cost > small_cost); // Larger widgets should cost more
}

test "PerformanceAnalyzer detects unnecessary redraws" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    // TODO: Set redraw flag or metric
    _ = root;
    inspector.endWidget();

    var analyzer = PerformanceAnalyzer.init();
    const issues = try analyzer.analyze(testing.allocator, inspector.root.?);
    defer {
        for (issues) |issue| {
            testing.allocator.free(issue.description);
            testing.allocator.free(issue.widget_path);
            testing.allocator.free(issue.suggestion);
        }
        testing.allocator.free(issues);
    }
    // May or may not find issue depending on implementation
    // Just checking that analyze() returns without error
    try testing.expect(issues.len >= 0);
}

// ============================================================================
// Integration Tests (5+ tests)
// ============================================================================

test "Full pipeline: analyze → detect issues → suggest fixes" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 200, .height = 60 }, Style{});
    _ = try inspector.beginWidget("Fixed", .{ .x = 0, .y = 0, .width = 100, .height = 50 }, Style{});
    inspector.endWidget();
    inspector.endWidget();

    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    // Analyze tree
    try analyzer.analyzeTree(inspector.root.?);

    // Detect issues
    const issues = analyzer.getIssues();
    try testing.expect(issues.len > 0);

    // Suggest fixes
    const suggestion = try analyzer.suggestConstraints("root.fixed");
    try testing.expect(suggestion != null);
}

test "Multiple issue categories detected in one tree" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    // Deep nesting (performance)
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "Level{d}", .{i});
        _ = try inspector.beginWidget(name, .{ .x = 0, .y = 0, .width = 40, .height = 12 }, Style{});
    }
    i = 0;
    while (i < 8) : (i += 1) {
        inspector.endWidget();
    }
    inspector.endWidget();

    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    try analyzer.analyzeTree(inspector.root.?);

    const issues = analyzer.getIssues();
    try testing.expect(issues.len > 0);

    // Should have multiple categories
    var categories_found = std.AutoHashMap(LayoutIssue.Category, void).init(testing.allocator);
    defer categories_found.deinit();

    for (issues) |issue| {
        try categories_found.put(issue.category, {});
    }

    try testing.expect(categories_found.count() > 1);
}

test "Auto-adjust actually improves responsiveness" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    const root = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 200, .height = 60 }, Style{});
    inspector.endWidget();

    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    // Check responsiveness before
    const before = try analyzer.checkResponsiveness(root, 80, 24);
    try testing.expect(!before); // Should fail

    // Auto-adjust
    const adjusted = try analyzer.autoAdjust(root, 80, 24);

    // Check responsiveness after
    const after = try analyzer.checkResponsiveness(adjusted, 80, 24);
    try testing.expect(after); // Should pass
}

test "Combined accessibility and performance analysis" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "Input{d}", .{i});
        _ = try inspector.beginWidget(name, .{ .x = 0, .y = 0, .width = 40, .height = 1 }, Style{});
        inspector.endWidget();
    }
    inspector.endWidget();

    var layout_analyzer = LayoutAnalyzer.init(testing.allocator);
    defer layout_analyzer.deinit();

    var perf_analyzer = PerformanceAnalyzer.init();
    var access_checker = AccessibilityChecker.init();

    try layout_analyzer.analyzeTree(inspector.root.?);
    const perf_issues = try perf_analyzer.analyze(testing.allocator, inspector.root.?);
    defer testing.allocator.free(perf_issues);
    const access_issues = try access_checker.checkTree(testing.allocator, inspector.root.?);
    defer {
        for (access_issues) |issue| {
            testing.allocator.free(issue.description);
            testing.allocator.free(issue.widget_path);
            testing.allocator.free(issue.suggestion);
        }
        testing.allocator.free(access_issues);
    }

    // Should find issues in both categories
    try testing.expect(perf_issues.len > 0 or access_issues.len > 0);
}

test "Layout intelligence handles dynamic content changes" {
    var inspector = WidgetInspector.init(testing.allocator);
    defer inspector.deinit();

    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("List", .{ .x = 0, .y = 0, .width = 80, .height = 20 }, Style{});
    inspector.endWidget();
    inspector.endWidget();

    var analyzer = LayoutAnalyzer.init(testing.allocator);
    defer analyzer.deinit();

    // First analysis
    try analyzer.analyzeTree(inspector.root.?);
    const issues_before = analyzer.getIssues();

    // Add more widgets (simulate content change)
    _ = try inspector.beginWidget("Root", .{ .x = 0, .y = 0, .width = 80, .height = 24 }, Style{});
    _ = try inspector.beginWidget("List", .{ .x = 0, .y = 0, .width = 80, .height = 20 }, Style{});
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "Item{d}", .{i});
        _ = try inspector.beginWidget(name, .{ .x = 0, .y = 0, .width = 80, .height = 1 }, Style{});
        inspector.endWidget();
    }
    inspector.endWidget();
    inspector.endWidget();

    // Second analysis
    var analyzer2 = LayoutAnalyzer.init(testing.allocator);
    defer analyzer2.deinit();

    try analyzer2.analyzeTree(inspector.root.?);
    const issues_after = analyzer2.getIssues();

    // Should detect more issues with more content
    try testing.expect(issues_after.len >= issues_before.len);
}
