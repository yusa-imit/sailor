const std = @import("std");
const sailor = @import("sailor");

const Buffer = sailor.tui.buffer.Buffer;
const Block = sailor.tui.widgets.Block;
const Paragraph = sailor.tui.widgets.Paragraph;
const Gauge = sailor.tui.widgets.Gauge;
const Rect = sailor.tui.layout.Rect;
const Style = sailor.tui.style.Style;
const Color = sailor.tui.style.Color;
const Span = sailor.tui.style.Span;
const Line = sailor.tui.style.Line;
const Grid = sailor.tui.grid.Grid;
const GridItem = sailor.tui.grid.GridItem;
const Track = sailor.tui.grid.Track;
const OverlayManager = sailor.tui.overlay.OverlayManager;
const SplitPane = sailor.tui.composition.SplitPane;
const Direction = sailor.tui.layout.Direction;
const ScreenSize = sailor.tui.responsive.ScreenSize;
const Constraint = sailor.tui.layout.Constraint;
const layout = sailor.tui.layout;

/// Demonstrates v1.2.0 features: Grid, Overlay, Composition, Responsive
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const term_size = try sailor.term.getSize();
    const width = @min(term_size.cols, 100);
    const height = @min(term_size.rows, 30);

    var buffer = try Buffer.init(allocator, width, height);
    defer buffer.deinit();

    const area = Rect.new(0, 0, width, height);

    // RESPONSIVE: Adapt layout based on terminal width
    const screen_size = ScreenSize.fromWidth(width);
    const is_small = screen_size == .small or screen_size == .tiny;

    // Main layout
    const main_chunks = try layout.split(
        allocator,
        .vertical,
        area,
        &[_]Constraint{
            .{ .length = 3 }, // Title
            .{ .min = 10 }, // Content
        },
    );
    defer allocator.free(main_chunks);

    // Title
    const title = Block{
        .title = "Sailor v1.2.0 — Layout & Composition Features",
        .borders = .all,
        .border_style = Style{ .fg = Color{ .indexed = 14 } },
    };
    title.render(&buffer, main_chunks[0]);

    // GRID: Use CSS Grid-inspired layout for panels
    const grid = if (is_small) Grid{
        // Small screen: 1 column, 3 rows
        .rows = &[_]Track{ .{ .fixed = 8 }, .{ .fixed = 8 }, .{ .fr = 1 } },
        .cols = &[_]Track{.auto},
        .row_gap = 1,
    } else Grid{
        // Normal screen: 2x2 grid
        .rows = &[_]Track{ .{ .fr = 1 }, .{ .fr = 1 } },
        .cols = &[_]Track{ .{ .fr = 1 }, .{ .fr = 1 } },
        .row_gap = 1,
        .col_gap = 1,
    };

    const items = [_]GridItem{
        .{ .row = 1, .col = 1 },
        .{ .row = if (is_small) 2 else 1, .col = if (is_small) 1 else 2 },
        .{ .row = if (is_small) 3 else 2, .col = 1 },
        .{ .row = 2, .col = 2 },
    };

    const panel_count: usize = if (is_small) 3 else 4;
    const panel_areas = try grid.layout(allocator, main_chunks[1], items[0..panel_count]);
    defer allocator.free(panel_areas);

    // Panel 1: Responsive info
    {
        const block = Block{
            .title = "Responsive Breakpoints",
            .borders = .all,
            .border_style = Style{ .fg = Color{ .indexed = 11 } },
        };
        block.render(&buffer, panel_areas[0]);

        const inner = block.inner(panel_areas[0]);
        const size_text = switch (screen_size) {
            .tiny => "TINY (<40 cols)",
            .small => "SMALL (40-79)",
            .medium => "MEDIUM (80-119)",
            .large => "LARGE (120+)",
        };

        const layout_text = if (is_small) "Stacked 1-column" else "2x2 Grid";

        const spans1 = [_]Span{Span.styled(size_text, Style{ .fg = Color{ .indexed = 11 }, .bold = true })};
        const spans2 = [_]Span{Span.styled(layout_text, Style{})};

        const lines = [_]Line{
            Line{ .spans = &spans1 },
            Line{ .spans = &spans2 },
        };
        const para = Paragraph{ .lines = &lines };
        para.render(&buffer, inner);
    }

    // Panel 2: Grid layout info
    {
        const block = Block{
            .title = "Grid Layout",
            .borders = .all,
            .border_style = Style{ .fg = Color{ .indexed = 12 } },
        };
        block.render(&buffer, panel_areas[1]);

        const inner = block.inner(panel_areas[1]);

        const spans1 = [_]Span{Span.raw("CSS Grid-inspired")};
        const spans2 = [_]Span{Span.raw("Track: fixed, fr, auto")};
        const spans3 = [_]Span{Span.raw("Gaps: row/col spacing")};

        const lines = [_]Line{
            Line{ .spans = &spans1 },
            Line{ .spans = &spans2 },
            Line{ .spans = &spans3 },
        };
        const para = Paragraph{ .lines = &lines };
        para.render(&buffer, inner);
    }

    // Panel 3: COMPOSITION - SplitPane
    {
        const panel_idx: usize = 2;
        if (panel_idx < panel_areas.len) {
            const split_pane = SplitPane{
                .direction = .horizontal,
                .ratio = 0.65,
                .gap = 1,
                .min_first = 3,
                .min_second = 3,
            };
            const split_result = split_pane.layout(panel_areas[panel_idx]);

            // Left pane (65%)
            const left_block = Block{
                .title = "Split 65%",
                .borders = .all,
                .border_style = Style{ .fg = Color{ .indexed = 13 } },
            };
            left_block.render(&buffer, split_result.first);

            const left_inner = left_block.inner(split_result.first);
            const left_spans = [_]Span{Span.raw("Composition")};
            const left_lines = [_]Line{Line{ .spans = &left_spans }};
            const left_para = Paragraph{ .lines = &left_lines };
            left_para.render(&buffer, left_inner);

            // Right pane (35%)
            const right_gauge = Gauge{
                .block = Block{
                    .title = "35%",
                    .borders = .all,
                    .border_style = Style{ .fg = Color{ .indexed = 13 } },
                },
                .ratio = 0.65,
                .filled_style = Style{ .fg = Color{ .indexed = 10 } },
            };
            right_gauge.render(&buffer, split_result.second);
        }
    }

    // Panel 4 (if exists): OVERLAY demonstration
    if (panel_areas.len > 3) {
        // Base layer
        const base_block = Block{
            .title = "Overlay System (z-index)",
            .borders = .all,
            .border_style = Style{ .fg = Color{ .indexed = 9 } },
        };
        base_block.render(&buffer, panel_areas[3]);

        // Demonstrate OverlayManager API (without actual rendering)
        var overlay_mgr = OverlayManager.init(allocator);
        defer overlay_mgr.deinit();

        // Add overlays with different z-indices
        const popup_width = @min(panel_areas[3].width -| 4, 25);
        const popup_height = @min(panel_areas[3].height -| 2, 5);

        if (popup_width >= 3 and popup_height >= 3) {
            const popup_x = panel_areas[3].x + (panel_areas[3].width - popup_width) / 2;
            const popup_y = panel_areas[3].y + (panel_areas[3].height - popup_height) / 2;

            const Overlay = sailor.tui.overlay.Overlay;

            try overlay_mgr.add(Overlay{
                .area = Rect.new(popup_x, popup_y, popup_width, popup_height),
                .z_index = 100,
            });

            // Render popup directly on buffer (simpler than compositing)
            const popup_block = Block{
                .title = "Popup z=100",
                .borders = .all,
                .border_style = Style{
                    .fg = Color{ .indexed = 0 },
                    .bg = Color{ .indexed = 11 },
                },
            };
            const popup_area = Rect.new(popup_x, popup_y, popup_width, popup_height);
            popup_block.render(&buffer, popup_area);

            const popup_inner = popup_block.inner(popup_area);
            const popup_spans = [_]Span{Span.raw("Layered!")};
            const popup_lines = [_]Line{Line{ .spans = &popup_spans }};
            const popup_para = Paragraph{ .lines = &popup_lines };
            popup_para.render(&buffer, popup_inner);
        }
    }

    // Render to terminal
    var previous = try Buffer.init(allocator, width, height);
    defer previous.deinit();

    var output_buf: std.ArrayList(u8) = .{};
    defer output_buf.deinit(allocator);
    const writer = output_buf.writer(allocator);

    const diff_ops = try sailor.tui.buffer.diff(allocator, previous, buffer);
    defer allocator.free(diff_ops);
    try sailor.tui.buffer.renderDiff(diff_ops, writer);

    _ = try std.posix.write(std.posix.STDOUT_FILENO, output_buf.items);
}
