const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("buffer.zig").Buffer;
const Rect = @import("layout.zig").Rect;

/// Z-index layer for rendering order
pub const ZIndex = u8;

/// Overlay layer with z-index for stacking
pub const Overlay = struct {
    /// Area of the overlay
    area: Rect,
    /// Z-index (higher values rendered on top)
    z_index: ZIndex,
    /// Whether this overlay is visible
    visible: bool = true,

    /// Compare overlays by z-index for sorting
    pub fn lessThan(_: void, a: Overlay, b: Overlay) bool {
        return a.z_index < b.z_index;
    }
};

/// Overlay manager for z-index based rendering
pub const OverlayManager = struct {
    overlays: std.ArrayList(Overlay),
    allocator: Allocator,

    /// Initialize overlay manager with empty overlay list.
    pub fn init(allocator: Allocator) OverlayManager {
        return .{
            .overlays = std.ArrayList(Overlay){},
            .allocator = allocator,
        };
    }

    /// Free the overlay list.
    pub fn deinit(self: *OverlayManager) void {
        self.overlays.deinit(self.allocator);
    }

    /// Add an overlay to the manager
    pub fn add(self: *OverlayManager, overlay: Overlay) !void {
        try self.overlays.append(self.allocator, overlay);
        // Keep sorted by z-index
        std.mem.sort(Overlay, self.overlays.items, {}, Overlay.lessThan);
    }

    /// Remove overlay at index
    pub fn remove(self: *OverlayManager, index: usize) void {
        if (index < self.overlays.items.len) {
            _ = self.overlays.orderedRemove(index);
        }
    }

    /// Clear all overlays
    pub fn clear(self: *OverlayManager) void {
        self.overlays.clearRetainingCapacity();
    }

    /// Get overlays sorted by z-index (low to high)
    pub fn getSorted(self: OverlayManager) []const Overlay {
        return self.overlays.items;
    }

    /// Find overlay at position (returns highest z-index)
    pub fn findAt(self: OverlayManager, x: u16, y: u16) ?usize {
        var found: ?usize = null;
        var max_z: ZIndex = 0;

        for (self.overlays.items, 0..) |overlay, i| {
            if (!overlay.visible) continue;
            if (overlay.area.contains(x, y)) {
                if (found == null or overlay.z_index > max_z) {
                    found = i;
                    max_z = overlay.z_index;
                }
            }
        }

        return found;
    }

    /// Check if position is covered by any overlay
    pub fn isCovered(self: OverlayManager, x: u16, y: u16) bool {
        return self.findAt(x, y) != null;
    }

    /// Get overlay count
    pub fn count(self: OverlayManager) usize {
        return self.overlays.items.len;
    }

    /// Set visibility for an overlay
    pub fn setVisible(self: *OverlayManager, index: usize, visible: bool) void {
        if (index < self.overlays.items.len) {
            self.overlays.items[index].visible = visible;
        }
    }

    /// Bring overlay to front (set to highest z-index + 1)
    pub fn bringToFront(self: *OverlayManager, index: usize) void {
        if (index >= self.overlays.items.len) return;

        // Find max z-index
        var max_z: ZIndex = 0;
        for (self.overlays.items) |overlay| {
            if (overlay.z_index > max_z) {
                max_z = overlay.z_index;
            }
        }

        // Set to max + 1 (with overflow check)
        self.overlays.items[index].z_index = if (max_z < 255) max_z + 1 else 255;

        // Re-sort
        std.mem.sort(Overlay, self.overlays.items, {}, Overlay.lessThan);
    }

    /// Send overlay to back (set to lowest z-index - 1)
    pub fn sendToBack(self: *OverlayManager, index: usize) void {
        if (index >= self.overlays.items.len) return;

        // Find min z-index
        var min_z: ZIndex = 255;
        for (self.overlays.items) |overlay| {
            if (overlay.z_index < min_z) {
                min_z = overlay.z_index;
            }
        }

        // Set to min - 1 (with underflow check)
        self.overlays.items[index].z_index = if (min_z > 0) min_z - 1 else 0;

        // Re-sort
        std.mem.sort(Overlay, self.overlays.items, {}, Overlay.lessThan);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Overlay - creation" {
    const overlay = Overlay{
        .area = Rect{ .x = 10, .y = 10, .width = 20, .height = 20 },
        .z_index = 5,
    };

    try std.testing.expectEqual(10, overlay.area.x);
    try std.testing.expectEqual(5, overlay.z_index);
    try std.testing.expect(overlay.visible);
}

test "Overlay - lessThan comparison" {
    const a = Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 1,
    };
    const b = Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 2,
    };

    try std.testing.expect(Overlay.lessThan({}, a, b));
    try std.testing.expect(!Overlay.lessThan({}, b, a));
}

test "OverlayManager - init and deinit" {
    const allocator = std.testing.allocator;
    var manager = OverlayManager.init(allocator);
    defer manager.deinit();

    try std.testing.expectEqual(0, manager.count());
}

test "OverlayManager - add overlays" {
    const allocator = std.testing.allocator;
    var manager = OverlayManager.init(allocator);
    defer manager.deinit();

    const overlay1 = Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 2,
    };
    const overlay2 = Overlay{
        .area = Rect{ .x = 5, .y = 5, .width = 10, .height = 10 },
        .z_index = 1,
    };

    try manager.add(overlay1);
    try manager.add(overlay2);

    try std.testing.expectEqual(2, manager.count());

    // Should be sorted by z-index
    const sorted = manager.getSorted();
    try std.testing.expectEqual(1, sorted[0].z_index);
    try std.testing.expectEqual(2, sorted[1].z_index);
}

test "OverlayManager - remove overlay" {
    const allocator = std.testing.allocator;
    var manager = OverlayManager.init(allocator);
    defer manager.deinit();

    try manager.add(Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 1,
    });
    try manager.add(Overlay{
        .area = Rect{ .x = 5, .y = 5, .width = 10, .height = 10 },
        .z_index = 2,
    });

    manager.remove(0);
    try std.testing.expectEqual(1, manager.count());
}

test "OverlayManager - clear" {
    const allocator = std.testing.allocator;
    var manager = OverlayManager.init(allocator);
    defer manager.deinit();

    try manager.add(Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 1,
    });
    try manager.add(Overlay{
        .area = Rect{ .x = 5, .y = 5, .width = 10, .height = 10 },
        .z_index = 2,
    });

    manager.clear();
    try std.testing.expectEqual(0, manager.count());
}

test "OverlayManager - findAt" {
    const allocator = std.testing.allocator;
    var manager = OverlayManager.init(allocator);
    defer manager.deinit();

    try manager.add(Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 1,
    });
    try manager.add(Overlay{
        .area = Rect{ .x = 5, .y = 5, .width = 15, .height = 15 },
        .z_index = 2,
    });

    // Point in both overlays - should return higher z-index
    const found = manager.findAt(7, 7);
    try std.testing.expect(found != null);
    try std.testing.expectEqual(2, manager.overlays.items[found.?].z_index);

    // Point in only first overlay
    const found2 = manager.findAt(2, 2);
    try std.testing.expect(found2 != null);
    try std.testing.expectEqual(1, manager.overlays.items[found2.?].z_index);

    // Point outside all overlays
    const found3 = manager.findAt(100, 100);
    try std.testing.expectEqual(null, found3);
}

test "OverlayManager - isCovered" {
    const allocator = std.testing.allocator;
    var manager = OverlayManager.init(allocator);
    defer manager.deinit();

    try manager.add(Overlay{
        .area = Rect{ .x = 10, .y = 10, .width = 20, .height = 20 },
        .z_index = 1,
    });

    try std.testing.expect(manager.isCovered(15, 15));
    try std.testing.expect(!manager.isCovered(50, 50));
}

test "OverlayManager - setVisible" {
    const allocator = std.testing.allocator;
    var manager = OverlayManager.init(allocator);
    defer manager.deinit();

    try manager.add(Overlay{
        .area = Rect{ .x = 10, .y = 10, .width = 20, .height = 20 },
        .z_index = 1,
    });

    try std.testing.expect(manager.isCovered(15, 15));

    manager.setVisible(0, false);
    try std.testing.expect(!manager.isCovered(15, 15));

    manager.setVisible(0, true);
    try std.testing.expect(manager.isCovered(15, 15));
}

test "OverlayManager - bringToFront" {
    const allocator = std.testing.allocator;
    var manager = OverlayManager.init(allocator);
    defer manager.deinit();

    try manager.add(Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 1,
    });
    try manager.add(Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 2,
    });

    // Bring first overlay to front
    manager.bringToFront(0);

    const sorted = manager.getSorted();
    // First overlay should now have highest z-index
    try std.testing.expect(sorted[1].z_index > sorted[0].z_index);
}

test "OverlayManager - sendToBack" {
    const allocator = std.testing.allocator;
    var manager = OverlayManager.init(allocator);
    defer manager.deinit();

    try manager.add(Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 5,
    });
    try manager.add(Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 10,
    });

    // Send second overlay to back
    manager.sendToBack(1);

    const sorted = manager.getSorted();
    // Second overlay should now have lowest z-index
    try std.testing.expect(sorted[0].z_index < sorted[1].z_index);
}

test "OverlayManager - z-index overflow" {
    const allocator = std.testing.allocator;
    var manager = OverlayManager.init(allocator);
    defer manager.deinit();

    try manager.add(Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 255,
    });

    // Should not crash on bring to front with max z-index
    manager.bringToFront(0);
    try std.testing.expectEqual(255, manager.overlays.items[0].z_index);
}

test "OverlayManager - z-index underflow" {
    const allocator = std.testing.allocator;
    var manager = OverlayManager.init(allocator);
    defer manager.deinit();

    try manager.add(Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 0,
    });

    // Should not crash on send to back with min z-index
    manager.sendToBack(0);
    try std.testing.expectEqual(0, manager.overlays.items[0].z_index);
}

test "OverlayManager - empty manager operations" {
    const allocator = std.testing.allocator;
    var manager = OverlayManager.init(allocator);
    defer manager.deinit();

    // Should not crash on empty manager
    manager.remove(0);
    manager.setVisible(0, false);
    manager.bringToFront(0);
    manager.sendToBack(0);

    try std.testing.expectEqual(null, manager.findAt(10, 10));
    try std.testing.expect(!manager.isCovered(10, 10));
}

test "OverlayManager - sorting stability" {
    const allocator = std.testing.allocator;
    var manager = OverlayManager.init(allocator);
    defer manager.deinit();

    // Add overlays in reverse z-index order
    try manager.add(Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 3,
    });
    try manager.add(Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 1,
    });
    try manager.add(Overlay{
        .area = Rect{ .x = 0, .y = 0, .width = 10, .height = 10 },
        .z_index = 2,
    });

    const sorted = manager.getSorted();
    try std.testing.expectEqual(1, sorted[0].z_index);
    try std.testing.expectEqual(2, sorted[1].z_index);
    try std.testing.expectEqual(3, sorted[2].z_index);
}
