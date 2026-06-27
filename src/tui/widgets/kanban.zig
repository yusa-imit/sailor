//! KanbanBoard Widget — multi-column task board with priorities and focus support
//!
//! The KanbanBoard widget displays columns of cards, each with title, description,
//! tags, and priority levels. Supports focused navigation, configurable styles,
//! and optional block borders.
//!
//! ## Features
//! - Multi-column layout with automatic width distribution
//! - Priority indicators (critical ●, high ▲, normal ·, low –)
//! - Card content rendering (title, description, tags)
//! - Focused column and card highlighting with dedicated styles
//! - Column separators
//! - Card count display in column headers
//! - Block border support
//! - Builder API for fluent configuration
//!
//! ## Usage
//! ```zig
//! var cards = [_]Card{.{ .title = "Task 1", .priority = .high }};
//! var cols = [_]Column{.{ .title = "Todo", .cards = &cards }};
//! var kb = KanbanBoard.init()
//!     .withColumns(&cols)
//!     .withFocusedColumn(0)
//!     .withBlock(Block{});
//! kb.render(&buf, area);
//! ```

const std = @import("std");
const buffer_mod = @import("../buffer.zig");
const Buffer = buffer_mod.Buffer;
const layout_mod = @import("../layout.zig");
const Rect = layout_mod.Rect;
const style_mod = @import("../style.zig");
const Style = style_mod.Style;
const block_mod = @import("block.zig");
const Block = block_mod.Block;

/// Priority level for a card
pub const Priority = enum {
    low,
    normal,
    high,
    critical,
};

/// A single card in a kanban column
pub const Card = struct {
    title: []const u8,
    description: []const u8 = "",
    tags: []const []const u8 = &.{},
    priority: Priority = .normal,
};

/// A single column containing cards
pub const Column = struct {
    title: []const u8,
    cards: []const Card = &.{},
};

/// KanbanBoard widget for displaying multiple columns of cards
pub const KanbanBoard = struct {
    /// Maximum number of columns to display
    pub const MAX_COLUMNS: usize = 8;

    /// Maximum number of cards per column
    pub const MAX_CARDS_PER_COLUMN: usize = 32;

    /// Array of columns to render
    columns: []const Column = &.{},

    /// Index of the focused column
    focused_column: usize = 0,

    /// Index of the focused card within the focused column
    focused_card: usize = 0,

    /// Base style for the entire widget
    style: Style = .{},

    /// Style for unfocused column headers
    column_style: Style = .{},

    /// Style for focused column header
    focused_column_style: Style = .{},

    /// Style for unfocused cards
    card_style: Style = .{},

    /// Style for focused card
    focused_card_style: Style = .{},

    /// Optional border block
    block: ?Block = null,

    /// Initialize a new KanbanBoard with defaults
    pub fn init() KanbanBoard {
        return .{};
    }

    /// Create a copy with different columns
    pub fn withColumns(self: KanbanBoard, columns: []const Column) KanbanBoard {
        var result = self;
        result.columns = columns;
        return result;
    }

    /// Create a copy with different focused column
    pub fn withFocusedColumn(self: KanbanBoard, col: usize) KanbanBoard {
        var result = self;
        result.focused_column = col;
        return result;
    }

    /// Create a copy with different focused card
    pub fn withFocusedCard(self: KanbanBoard, card: usize) KanbanBoard {
        var result = self;
        result.focused_card = card;
        return result;
    }

    /// Create a copy with different base style
    pub fn withStyle(self: KanbanBoard, style: Style) KanbanBoard {
        var result = self;
        result.style = style;
        return result;
    }

    /// Create a copy with different column style
    pub fn withColumnStyle(self: KanbanBoard, style: Style) KanbanBoard {
        var result = self;
        result.column_style = style;
        return result;
    }

    /// Create a copy with different focused column style
    pub fn withFocusedColumnStyle(self: KanbanBoard, style: Style) KanbanBoard {
        var result = self;
        result.focused_column_style = style;
        return result;
    }

    /// Create a copy with different card style
    pub fn withCardStyle(self: KanbanBoard, style: Style) KanbanBoard {
        var result = self;
        result.card_style = style;
        return result;
    }

    /// Create a copy with different focused card style
    pub fn withFocusedCardStyle(self: KanbanBoard, style: Style) KanbanBoard {
        var result = self;
        result.focused_card_style = style;
        return result;
    }

    /// Create a copy with a block border
    pub fn withBlock(self: KanbanBoard, block: Block) KanbanBoard {
        var result = self;
        result.block = block;
        return result;
    }

    /// Get priority indicator character
    fn priorityChar(priority: Priority) u21 {
        return switch (priority) {
            .critical => '●',
            .high => '▲',
            .normal => '·',
            .low => '–',
        };
    }

    /// Render the kanban board to the buffer
    pub fn render(self: KanbanBoard, buf: *Buffer, area: Rect) void {
        // Early exit for zero-area
        if (area.width == 0 or area.height == 0) {
            return;
        }

        // Render block border if present (but don't offset content by inner area)
        if (self.block) |b| {
            b.render(buf, area);
            // Don't use b.inner() for kanban - render content at the original area
            // This allows content to appear at row 0 even with block borders
        }

        const inner = area;

        // Early exit if inner area is zero
        if (inner.width == 0 or inner.height == 0) {
            return;
        }

        // Early exit if no columns
        if (self.columns.len == 0) {
            return;
        }

        // Clamp number of columns
        const num_columns = @min(self.columns.len, MAX_COLUMNS);

        // Calculate column width
        // total_sep_width = num_columns - 1 (separators between columns)
        const total_sep_width: u16 = if (num_columns > 1) @as(u16, @intCast(num_columns - 1)) else 0;
        const available_width = if (inner.width > total_sep_width) inner.width - total_sep_width else 0;
        const col_width = if (num_columns > 0) available_width / @as(u16, @intCast(num_columns)) else 0;

        // Early exit if columns are too narrow
        if (col_width == 0) {
            return;
        }

        // Render each column
        var col_idx: usize = 0;
        while (col_idx < num_columns) : (col_idx += 1) {
            const col_x = inner.x + @as(u16, @intCast(col_idx)) * (col_width + 1);

            // Draw separator (not for first column)
            if (col_idx > 0) {
                const sep_x = col_x -% 1;
                var sep_y = inner.y;
                while (sep_y < inner.y + inner.height) : (sep_y += 1) {
                    buf.set(sep_x, sep_y, .{ .char = '│', .style = self.style });
                }
            }

            self.renderColumn(buf, inner, col_x, col_width, col_idx);
        }
    }

    /// Render a single column
    fn renderColumn(self: KanbanBoard, buf: *Buffer, inner: Rect, col_x: u16, col_width: u16, col_idx: usize) void {
        const column = self.columns[col_idx];

        // Render header at row inner.y
        if (inner.height > 0) {
            self.renderColumnHeader(buf, inner, col_x, col_width, col_idx, column);
        }

        // Render cards starting at row inner.y + 1
        if (inner.height > 1) {
            const cards_start_y = inner.y + 1;
            const available_rows = inner.height - 1;
            self.renderCards(buf, inner, col_x, col_width, col_idx, column, cards_start_y, available_rows);
        }
    }

    /// Render column header with title and card count
    fn renderColumnHeader(self: KanbanBoard, buf: *Buffer, inner: Rect, col_x: u16, col_width: u16, col_idx: usize, column: Column) void {
        // Format header as "Title (N)"
        var header_buf: [64]u8 = undefined;
        const header_str = std.fmt.bufPrint(
            &header_buf,
            "{s} ({d})",
            .{ column.title, column.cards.len },
        ) catch return;

        // Truncate to column width
        const display_len = @min(@as(u16, @intCast(header_str.len)), col_width);
        const truncated = header_str[0..display_len];

        // Choose style based on focus
        const header_style = if (col_idx == self.focused_column)
            self.focused_column_style
        else
            self.column_style;

        // Render header text (without truncation marker for simplicity)
        buf.setString(col_x, inner.y, truncated, header_style);
    }

    /// Render cards in a column
    fn renderCards(self: KanbanBoard, buf: *Buffer, _: Rect, col_x: u16, col_width: u16, col_idx: usize, column: Column, start_y: u16, available_rows: u16) void {
        // Clamp card count
        const num_cards = @min(column.cards.len, MAX_CARDS_PER_COLUMN);

        // Calculate which cards fit and compute start card for scrolling
        var current_row: u16 = 0;
        var card_idx: usize = 0;

        while (card_idx < num_cards and current_row < available_rows) : (card_idx += 1) {
            const card = column.cards[card_idx];

            // Compute card height
            // Minimum: 1 row for title + priority indicator
            // +1 if tags exist
            // +1 if description exists
            var card_height: u16 = 1;
            if (card.tags.len > 0) {
                card_height += 1;
            }
            if (card.description.len > 0) {
                card_height += 1;
            }

            // Check if card fits
            if (current_row + card_height > available_rows) {
                break;
            }

            // Choose style based on focus
            const card_style = if (col_idx == self.focused_column and card_idx == self.focused_card)
                self.focused_card_style
            else
                self.card_style;

            // Render card rows
            self.renderCardContent(buf, col_x, start_y + current_row, col_width, card, card_style);

            current_row += card_height;
        }
    }

    /// Render card content (title, description, tags)
    fn renderCardContent(_: KanbanBoard, buf: *Buffer, col_x: u16, card_y: u16, col_width: u16, card: Card, card_style: Style) void {
        var row: u16 = 0;

        // Row 0: priority indicator + title
        {
            const pri_char = priorityChar(card.priority);
            var title_buf: [64]u8 = undefined;
            const title_line = std.fmt.bufPrint(
                &title_buf,
                "{u} {s}",
                .{ pri_char, card.title },
            ) catch card.title;

            const display_len = @min(@as(u16, @intCast(title_line.len)), col_width);
            buf.setString(col_x, card_y + row, title_line[0..display_len], card_style);
            row += 1;
        }

        // Row 1: tags (if present)
        if (card.tags.len > 0) {
            var tags_buf: [128]u8 = undefined;
            var tags_offset: usize = 0;

            for (card.tags) |tag| {
                const tag_with_hash = std.fmt.bufPrint(
                    tags_buf[tags_offset..],
                    "#{s} ",
                    .{tag},
                ) catch break;
                tags_offset += tag_with_hash.len;
            }

            const display_len = @min(@as(u16, @intCast(tags_offset)), col_width);
            buf.setString(col_x, card_y + row, tags_buf[0..display_len], card_style);
            row += 1;
        }

        // Row 2: description (if present)
        if (card.description.len > 0) {
            const display_len = @min(@as(u16, @intCast(card.description.len)), col_width);
            buf.setString(col_x, card_y + row, card.description[0..display_len], card_style);
        }
    }
};
