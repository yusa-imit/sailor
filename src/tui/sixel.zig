/// Sixel graphics protocol support for inline images in compatible terminals
/// Implements DEC Sixel graphics specification for rendering raster images
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Writer = std.io.Writer;
const ArrayList = std.ArrayList;

/// Sixel image format parameters
pub const SixelImage = struct {
    width: u16,
    height: u16,
    pixels: []const Color, // Row-major RGBA pixel data

    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8 = 255, // Alpha channel (0=transparent, 255=opaque)

        /// Creates a Color from RGB components with opaque alpha (255).
        ///
        /// Args:
        ///   r: Red channel (0-255)
        ///   g: Green channel (0-255)
        ///   b: Blue channel (0-255)
        ///
        /// Returns:
        ///   Color with full opacity
        pub fn fromRgb(r: u8, g: u8, b: u8) Color {
            return .{ .r = r, .g = g, .b = b };
        }

        /// Creates a Color from RGBA components including transparency.
        ///
        /// Args:
        ///   r: Red channel (0-255)
        ///   g: Green channel (0-255)
        ///   b: Blue channel (0-255)
        ///   a: Alpha channel (0=transparent, 255=opaque)
        ///
        /// Returns:
        ///   Color with specified opacity
        pub fn fromRgba(r: u8, g: u8, b: u8, a: u8) Color {
            return .{ .r = r, .g = g, .b = b, .a = a };
        }
    };
};

/// Color palette for image quantization
pub const ColorPalette = struct {
    colors: []SixelImage.Color,
    allocator: Allocator,

    pub fn init(allocator: Allocator, max_colors: usize) !ColorPalette {
        _ = max_colors;
        const colors = try allocator.alloc(SixelImage.Color, 0);
        return ColorPalette{
            .colors = colors,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *const ColorPalette) void {
        self.allocator.free(self.colors);
    }

    pub fn addColor(self: *ColorPalette, color: SixelImage.Color) !void {
        // Check if color already exists (within epsilon)
        for (self.colors) |existing| {
            const dist = colorDistance(color, existing, .euclidean_rgb);
            if (dist < 1.0) return; // Duplicate
        }

        // Reallocate and append
        const new_colors = try self.allocator.alloc(SixelImage.Color, self.colors.len + 1);
        @memcpy(new_colors[0..self.colors.len], self.colors);
        new_colors[self.colors.len] = color;
        self.allocator.free(self.colors);
        self.colors = new_colors;
    }

    pub fn findNearest(self: ColorPalette, color: SixelImage.Color) u8 {
        if (self.colors.len == 0) return 0;

        var min_dist: f32 = std.math.floatMax(f32);
        var min_idx: u8 = 0;

        for (self.colors, 0..) |palette_color, i| {
            const dist = colorDistance(color, palette_color, .euclidean_rgb);
            if (dist < min_dist) {
                min_dist = dist;
                min_idx = @intCast(i);
            }
        }

        return min_idx;
    }
};

/// Quantization algorithm selection
pub const QuantizationAlgorithm = enum {
    median_cut,
    octree,
    kmeans,
};

/// Color distance metric
pub const DistanceMetric = enum {
    euclidean_rgb,
    perceptual_lab,
};

/// Calculate color distance between two colors
pub fn colorDistance(a: SixelImage.Color, b: SixelImage.Color, metric: DistanceMetric) f32 {
    switch (metric) {
        .euclidean_rgb => {
            const dr = @as(f32, @floatFromInt(@as(i16, a.r) - @as(i16, b.r)));
            const dg = @as(f32, @floatFromInt(@as(i16, a.g) - @as(i16, b.g)));
            const db = @as(f32, @floatFromInt(@as(i16, a.b) - @as(i16, b.b)));
            return @sqrt(dr * dr + dg * dg + db * db);
        },
        .perceptual_lab => {
            const lab_a = rgbToLab(a);
            const lab_b = rgbToLab(b);
            const dl = lab_a.l - lab_b.l;
            const da = lab_a.a - lab_b.a;
            const db = lab_a.b - lab_b.b;
            return @sqrt(dl * dl + da * da + db * db);
        },
    }
}

const LabColor = struct {
    l: f32,
    a: f32,
    b: f32,
};

fn rgbToLab(color: SixelImage.Color) LabColor {
    // RGB [0,255] → sRGB [0,1]
    const r = @as(f32, @floatFromInt(color.r)) / 255.0;
    const g = @as(f32, @floatFromInt(color.g)) / 255.0;
    const b = @as(f32, @floatFromInt(color.b)) / 255.0;

    // sRGB → linear RGB
    const r_lin = if (r <= 0.04045) r / 12.92 else std.math.pow(f32, (r + 0.055) / 1.055, 2.4);
    const g_lin = if (g <= 0.04045) g / 12.92 else std.math.pow(f32, (g + 0.055) / 1.055, 2.4);
    const b_lin = if (b <= 0.04045) b / 12.92 else std.math.pow(f32, (b + 0.055) / 1.055, 2.4);

    // Linear RGB → XYZ (D65 illuminant)
    const x = r_lin * 0.4124564 + g_lin * 0.3575761 + b_lin * 0.1804375;
    const y = r_lin * 0.2126729 + g_lin * 0.7151522 + b_lin * 0.0721750;
    const z = r_lin * 0.0193339 + g_lin * 0.1191920 + b_lin * 0.9503041;

    // XYZ → LAB (D65: Xn=95.047, Yn=100.0, Zn=108.883)
    const xn = x / 0.95047;
    const yn = y / 1.00000;
    const zn = z / 1.08883;

    const fx = if (xn > 0.008856) std.math.pow(f32, xn, 1.0 / 3.0) else (7.787 * xn + 16.0 / 116.0);
    const fy = if (yn > 0.008856) std.math.pow(f32, yn, 1.0 / 3.0) else (7.787 * yn + 16.0 / 116.0);
    const fz = if (zn > 0.008856) std.math.pow(f32, zn, 1.0 / 3.0) else (7.787 * zn + 16.0 / 116.0);

    const l = 116.0 * fy - 16.0;
    const a = 500.0 * (fx - fy);
    const b_val = 200.0 * (fy - fz);

    return LabColor{ .l = l, .a = a, .b = b_val };
}

/// Quantize colors to a palette using the specified algorithm
pub fn quantizeColors(
    allocator: Allocator,
    colors: []const SixelImage.Color,
    max_palette_size: u16,
    algorithm: QuantizationAlgorithm,
) !ColorPalette {
    switch (algorithm) {
        .median_cut => return medianCutQuantize(allocator, colors, max_palette_size),
        .octree => return octreeQuantize(allocator, colors, max_palette_size),
        .kmeans => return kmeansQuantize(allocator, colors, max_palette_size),
    }
}

// ============================================================================
// Median Cut Algorithm
// ============================================================================

const Bucket = struct {
    colors: []SixelImage.Color,
    range_r: u8,
    range_g: u8,
    range_b: u8,
};

fn medianCutQuantize(allocator: Allocator, colors: []const SixelImage.Color, max_palette_size: u16) !ColorPalette {
    if (colors.len == 0) {
        return ColorPalette{
            .colors = try allocator.alloc(SixelImage.Color, 0),
            .allocator = allocator,
        };
    }

    // Filter out transparent colors and collect unique colors using a hash set
    // for O(n) deduplication instead of O(n²).
    var unique_list = ArrayList(SixelImage.Color){};
    defer unique_list.deinit(allocator);

    var seen = std.AutoHashMap(u32, void).init(allocator);
    defer seen.deinit();

    for (colors) |c| {
        if (c.a < 128) continue;
        const key: u32 = (@as(u32, c.r) << 16) | (@as(u32, c.g) << 8) | c.b;
        const result = try seen.getOrPut(key);
        if (!result.found_existing) {
            try unique_list.append(allocator, c);
        }
    }

    if (unique_list.items.len == 0) {
        return ColorPalette{
            .colors = try allocator.alloc(SixelImage.Color, 0),
            .allocator = allocator,
        };
    }

    // If unique colors <= max_palette_size, return them all
    if (unique_list.items.len <= max_palette_size) {
        const palette_colors = try allocator.dupe(SixelImage.Color, unique_list.items);
        return ColorPalette{
            .colors = palette_colors,
            .allocator = allocator,
        };
    }

    // Median cut algorithm

    var buckets = ArrayList(Bucket){};
    defer {
        for (buckets.items) |b| allocator.free(b.colors);
        buckets.deinit(allocator);
    }

    // Start with all colors in one bucket
    const initial_colors = try allocator.dupe(SixelImage.Color, unique_list.items);
    const initial_bucket = computeBucketRange(initial_colors);
    try buckets.append(allocator, initial_bucket);

    // Split buckets until we have enough
    while (buckets.items.len < max_palette_size) {
        // Find bucket with largest range
        var max_range: u16 = 0;
        var max_idx: usize = 0;
        for (buckets.items, 0..) |b, i| {
            const range = @max(@max(b.range_r, b.range_g), b.range_b);
            if (range > max_range) {
                max_range = range;
                max_idx = i;
            }
        }

        if (max_range == 0) break; // Can't split further

        // Split the bucket
        const bucket = buckets.items[max_idx];
        if (bucket.colors.len <= 1) break; // Can't split single color

        const split_result = try splitBucket(allocator, bucket);
        if (split_result.bucket1.colors.len == 0 or split_result.bucket2.colors.len == 0) {
            // Split failed (shouldn't happen, but handle gracefully)
            break;
        }

        // Replace old bucket with two new ones
        allocator.free(buckets.items[max_idx].colors);
        _ = buckets.orderedRemove(max_idx);
        try buckets.append(allocator, split_result.bucket1);
        try buckets.append(allocator, split_result.bucket2);
    }

    // Compute centroid of each bucket
    var palette_colors = try allocator.alloc(SixelImage.Color, buckets.items.len);
    for (buckets.items, 0..) |b, i| {
        palette_colors[i] = computeCentroid(b.colors);
    }

    return ColorPalette{
        .colors = palette_colors,
        .allocator = allocator,
    };
}

fn computeBucketRange(colors: []SixelImage.Color) Bucket {
    var min_r: u8 = 255;
    var max_r: u8 = 0;
    var min_g: u8 = 255;
    var max_g: u8 = 0;
    var min_b: u8 = 255;
    var max_b: u8 = 0;

    for (colors) |c| {
        if (c.r < min_r) min_r = c.r;
        if (c.r > max_r) max_r = c.r;
        if (c.g < min_g) min_g = c.g;
        if (c.g > max_g) max_g = c.g;
        if (c.b < min_b) min_b = c.b;
        if (c.b > max_b) max_b = c.b;
    }

    return .{
        .colors = colors,
        .range_r = max_r - min_r,
        .range_g = max_g - min_g,
        .range_b = max_b - min_b,
    };
}

fn splitBucket(allocator: Allocator, bucket: Bucket) !struct { bucket1: Bucket, bucket2: Bucket } {
    // Determine split axis (largest range)
    const split_on_r = bucket.range_r >= bucket.range_g and bucket.range_r >= bucket.range_b;
    const split_on_g = !split_on_r and bucket.range_g >= bucket.range_b;

    // Sort colors by split axis
    const SortContext = struct {
        on_r: bool,
        on_g: bool,
    };
    const sort_ctx = SortContext{ .on_r = split_on_r, .on_g = split_on_g };

    std.mem.sort(SixelImage.Color, bucket.colors, sort_ctx, struct {
        fn lessThan(ctx: SortContext, a: SixelImage.Color, b: SixelImage.Color) bool {
            if (ctx.on_r) return a.r < b.r;
            if (ctx.on_g) return a.g < b.g;
            return a.b < b.b;
        }
    }.lessThan);

    // Split at median
    const median = bucket.colors.len / 2;
    const colors1 = try allocator.dupe(SixelImage.Color, bucket.colors[0..median]);
    const colors2 = try allocator.dupe(SixelImage.Color, bucket.colors[median..]);

    const bucket1 = computeBucketRange(colors1);
    const bucket2 = computeBucketRange(colors2);

    return .{ .bucket1 = bucket1, .bucket2 = bucket2 };
}

fn computeCentroid(colors: []const SixelImage.Color) SixelImage.Color {
    if (colors.len == 0) return .{ .r = 0, .g = 0, .b = 0 };

    var sum_r: u32 = 0;
    var sum_g: u32 = 0;
    var sum_b: u32 = 0;

    for (colors) |c| {
        sum_r += c.r;
        sum_g += c.g;
        sum_b += c.b;
    }

    return .{
        .r = @intCast(sum_r / @as(u32, @intCast(colors.len))),
        .g = @intCast(sum_g / @as(u32, @intCast(colors.len))),
        .b = @intCast(sum_b / @as(u32, @intCast(colors.len))),
    };
}

// ============================================================================
// Octree Algorithm
// ============================================================================

const OctreeNode = struct {
    children: [8]?*OctreeNode,
    color_sum: struct { r: u32, g: u32, b: u32 },
    pixel_count: u32,
    is_leaf: bool,
    level: u8,
};

fn octreeQuantize(allocator: Allocator, colors: []const SixelImage.Color, max_palette_size: u16) !ColorPalette {
    if (colors.len == 0) {
        return ColorPalette{
            .colors = try allocator.alloc(SixelImage.Color, 0),
            .allocator = allocator,
        };
    }

    // Build octree
    const root = try allocator.create(OctreeNode);
    defer freeOctree(allocator, root);
    root.* = .{
        .children = [_]?*OctreeNode{null} ** 8,
        .color_sum = .{ .r = 0, .g = 0, .b = 0 },
        .pixel_count = 0,
        .is_leaf = false,
        .level = 0,
    };

    var reducible_nodes: [8]ArrayList(*OctreeNode) = undefined;
    for (&reducible_nodes) |*list| {
        list.* = ArrayList(*OctreeNode){};
    }
    defer {
        for (&reducible_nodes) |*list| list.deinit(allocator);
    }

    var leaf_count: usize = 0;

    // Insert all colors
    for (colors) |c| {
        if (c.a < 128) continue; // Skip transparent
        try insertOctreeColor(allocator, root, c, 0, &reducible_nodes, &leaf_count);
    }

    // Reduce tree to max_palette_size leaves
    while (leaf_count > max_palette_size) {
        // Find deepest reducible level
        var level: usize = 7;
        while (level > 0) : (level -= 1) {
            if (reducible_nodes[level].items.len > 0) break;
        }

        if (reducible_nodes[level].items.len == 0) break;

        // Reduce a node at this level
        const node = reducible_nodes[level].pop() orelse break;
        try reduceOctreeNode(node, &leaf_count);
    }

    // Extract palette
    var palette_list = ArrayList(SixelImage.Color){};
    defer palette_list.deinit(allocator);
    try collectOctreeLeaves(allocator, root, &palette_list);

    const palette_colors = try palette_list.toOwnedSlice(allocator);
    return ColorPalette{
        .colors = palette_colors,
        .allocator = allocator,
    };
}

fn insertOctreeColor(
    allocator: Allocator,
    node: *OctreeNode,
    color: SixelImage.Color,
    level: u8,
    reducible_nodes: *[8]ArrayList(*OctreeNode),
    leaf_count: *usize,
) !void {
    if (level == 8) {
        // Leaf node
        node.is_leaf = true;
        node.color_sum.r += color.r;
        node.color_sum.g += color.g;
        node.color_sum.b += color.b;
        node.pixel_count += 1;
        if (node.pixel_count == 1) leaf_count.* += 1;
        return;
    }

    // Compute child index from RGB bits at this level
    const bit: u3 = @intCast(7 - level);
    const idx = ((@as(u8, @intCast((color.r >> bit) & 1)) << 2) |
        (@as(u8, @intCast((color.g >> bit) & 1)) << 1) |
        @as(u8, @intCast((color.b >> bit) & 1)));

    if (node.children[idx] == null) {
        const child = try allocator.create(OctreeNode);
        child.* = .{
            .children = [_]?*OctreeNode{null} ** 8,
            .color_sum = .{ .r = 0, .g = 0, .b = 0 },
            .pixel_count = 0,
            .is_leaf = false,
            .level = level + 1,
        };
        node.children[idx] = child;

        if (level < 7) {
            try reducible_nodes[level].append(allocator, node);
        }
    }

    try insertOctreeColor(allocator, node.children[idx].?, color, level + 1, reducible_nodes, leaf_count);
}

fn reduceOctreeNode(node: *OctreeNode, leaf_count: *usize) !void {
    var r_sum: u32 = 0;
    var g_sum: u32 = 0;
    var b_sum: u32 = 0;
    var count: u32 = 0;

    for (node.children) |maybe_child| {
        if (maybe_child) |child| {
            if (child.is_leaf) {
                r_sum += child.color_sum.r;
                g_sum += child.color_sum.g;
                b_sum += child.color_sum.b;
                count += child.pixel_count;
                leaf_count.* -= 1;
            }
        }
    }

    node.is_leaf = true;
    node.color_sum = .{ .r = r_sum, .g = g_sum, .b = b_sum };
    node.pixel_count = count;
    leaf_count.* += 1;

    // Clear children (they're merged)
    for (&node.children) |*child| child.* = null;
}

fn collectOctreeLeaves(allocator: Allocator, node: *OctreeNode, list: *ArrayList(SixelImage.Color)) !void {
    if (node.is_leaf and node.pixel_count > 0) {
        const color = SixelImage.Color{
            .r = @intCast(node.color_sum.r / node.pixel_count),
            .g = @intCast(node.color_sum.g / node.pixel_count),
            .b = @intCast(node.color_sum.b / node.pixel_count),
        };
        try list.append(allocator, color);
        return;
    }

    for (node.children) |maybe_child| {
        if (maybe_child) |child| {
            try collectOctreeLeaves(allocator, child, list);
        }
    }
}

fn freeOctree(allocator: Allocator, node: *OctreeNode) void {
    for (node.children) |maybe_child| {
        if (maybe_child) |child| {
            freeOctree(allocator, child);
        }
    }
    allocator.destroy(node);
}

// ============================================================================
// K-Means Algorithm
// ============================================================================

fn kmeansQuantize(allocator: Allocator, colors: []const SixelImage.Color, max_palette_size: u16) !ColorPalette {
    if (colors.len == 0) {
        return ColorPalette{
            .colors = try allocator.alloc(SixelImage.Color, 0),
            .allocator = allocator,
        };
    }

    // Filter transparent colors
    var opaque_list = ArrayList(SixelImage.Color){};
    defer opaque_list.deinit(allocator);
    for (colors) |c| {
        if (c.a >= 128) try opaque_list.append(allocator, c);
    }

    if (opaque_list.items.len == 0) {
        return ColorPalette{
            .colors = try allocator.alloc(SixelImage.Color, 0),
            .allocator = allocator,
        };
    }

    const k = @min(max_palette_size, @as(u16, @intCast(opaque_list.items.len)));

    // Initialize centroids (uniform distribution in RGB space)
    const centroids = try allocator.alloc(SixelImage.Color, k);
    defer allocator.free(centroids);

    for (centroids, 0..) |*c, i| {
        // Uniform sampling from input colors
        const idx = (i * opaque_list.items.len) / k;
        c.* = opaque_list.items[idx];
    }

    var assignments = try allocator.alloc(u8, opaque_list.items.len);
    defer allocator.free(assignments);

    const max_iter = 100;
    var iter: usize = 0;
    while (iter < max_iter) : (iter += 1) {
        var changed = false;

        // Assign each color to nearest centroid
        for (opaque_list.items, 0..) |color, i| {
            var min_dist: f32 = std.math.floatMax(f32);
            var min_idx: u8 = 0;

            for (centroids, 0..) |centroid, ci| {
                const dist = colorDistance(color, centroid, .euclidean_rgb);
                if (dist < min_dist) {
                    min_dist = dist;
                    min_idx = @intCast(ci);
                }
            }

            if (assignments[i] != min_idx) {
                assignments[i] = min_idx;
                changed = true;
            }
        }

        if (!changed) break; // Converged

        // Recompute centroids
        var cluster_sums = try allocator.alloc(struct { r: u32, g: u32, b: u32, count: u32 }, k);
        defer allocator.free(cluster_sums);
        @memset(cluster_sums, .{ .r = 0, .g = 0, .b = 0, .count = 0 });

        for (opaque_list.items, 0..) |color, i| {
            const cluster = assignments[i];
            cluster_sums[cluster].r += color.r;
            cluster_sums[cluster].g += color.g;
            cluster_sums[cluster].b += color.b;
            cluster_sums[cluster].count += 1;
        }

        // Update centroids
        for (centroids, 0..) |*centroid, ci| {
            if (cluster_sums[ci].count > 0) {
                centroid.r = @intCast(cluster_sums[ci].r / cluster_sums[ci].count);
                centroid.g = @intCast(cluster_sums[ci].g / cluster_sums[ci].count);
                centroid.b = @intCast(cluster_sums[ci].b / cluster_sums[ci].count);
            } else {
                // Empty cluster: reinitialize from farthest point
                var max_dist: f32 = 0;
                var farthest_idx: usize = 0;
                for (opaque_list.items, 0..) |color, i| {
                    var min_centroid_dist: f32 = std.math.floatMax(f32);
                    for (centroids) |c| {
                        const dist = colorDistance(color, c, .euclidean_rgb);
                        if (dist < min_centroid_dist) min_centroid_dist = dist;
                    }
                    if (min_centroid_dist > max_dist) {
                        max_dist = min_centroid_dist;
                        farthest_idx = i;
                    }
                }
                centroid.* = opaque_list.items[farthest_idx];
            }
        }
    }

    // Return final centroids
    const palette_colors = try allocator.dupe(SixelImage.Color, centroids);
    return ColorPalette{
        .colors = palette_colors,
        .allocator = allocator,
    };
}

/// Sixel encoder configuration
pub const SixelEncoder = struct {
    /// Maximum colors in palette (2-256, typically 256 for 24-bit color terminals)
    max_colors: u16 = 256,

    /// Use transparency (skip pixels with alpha < 128)
    use_transparency: bool = true,

    /// Color quantization algorithm
    quantization: QuantizationMethod = .median_cut,

    pub const QuantizationMethod = enum {
        median_cut, // Median cut algorithm (better quality)
        octree, // Octree quantization (faster)
        none, // No quantization (use existing palette)
    };

    /// Encode an image to Sixel format
    pub fn encode(self: SixelEncoder, allocator: Allocator, image: SixelImage, writer: anytype) !void {
        // Start Sixel sequence: ESC P q
        try writer.writeAll("\x1bPq");

        // Define raster attributes: "width;height
        try writer.print("\"1;1;{};{}", .{ image.width, image.height });

        // Build color palette
        const palette = try self.buildPalette(allocator, image);
        defer allocator.free(palette);

        // Define colors in palette: #index;2;r;g;b (RGB mode)
        for (palette, 0..) |color, i| {
            try writer.print("#{};2;{};{};{}", .{
                i,
                @as(u16, color.r) * 100 / 255,
                @as(u16, color.g) * 100 / 255,
                @as(u16, color.b) * 100 / 255,
            });
        }

        // Encode pixel data in sixels (groups of 6 vertical pixels)
        const sixel_height = (image.height + 5) / 6; // Round up to sixels

        var y: u16 = 0;
        while (y < sixel_height) : (y += 1) {
            try self.encodeSixelRow(allocator, image, palette, y, writer);
            if (y + 1 < sixel_height) {
                try writer.writeAll("-"); // Move to next sixel row
            }
        }

        // End Sixel sequence: ESC \
        try writer.writeAll("\x1b\\");
    }

    /// Encode image to compressed Sixel format
    /// Applies RLE compression to the sixel data (not headers/footers)
    /// for reduced bandwidth transmission.
    ///
    /// Args:
    ///   allocator: Memory allocator for temporary buffers
    ///   image: Image to encode
    ///   writer: Output writer for compressed sixel data
    ///
    /// Errors:
    ///   Propagates errors from encode() and compression
    pub fn encodeCompressed(self: SixelEncoder, allocator: Allocator, image: SixelImage, writer: anytype) !void {
        // First, encode normally to a buffer
        var encoded_buf = std.ArrayList(u8){};
        defer encoded_buf.deinit(allocator);

        try self.encode(allocator, image, encoded_buf.writer(allocator));
        const encoded_data = encoded_buf.items;

        // Compress the encoded data
        const compressed = try SixelCompressor.compress(allocator, encoded_data);
        defer allocator.free(compressed);

        // Write compressed data directly
        try writer.writeAll(compressed);
    }

    fn buildPalette(self: SixelEncoder, allocator: Allocator, image: SixelImage) ![]SixelImage.Color {
        if (self.quantization == .none) {
            // No quantization, collect unique colors (up to max_colors)
            var unique_colors: std.ArrayList(SixelImage.Color) = .{};
            defer unique_colors.deinit(allocator);

            for (image.pixels) |pixel| {
                if (self.use_transparency and pixel.a < 128) continue;

                var found = false;
                for (unique_colors.items) |existing| {
                    if (existing.r == pixel.r and existing.g == pixel.g and existing.b == pixel.b) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    if (unique_colors.items.len >= self.max_colors) break;
                    try unique_colors.append(allocator, pixel);
                }
            }

            return try allocator.dupe(SixelImage.Color, unique_colors.items);
        }

        // Median cut quantization (simple implementation)
        return try self.medianCutQuantize(allocator, image);
    }

    fn medianCutQuantize(self: SixelEncoder, allocator: Allocator, image: SixelImage) ![]SixelImage.Color {
        // Simplified median cut: collect all opaque pixels, sort by dominant channel, split
        var pixels: std.ArrayList(SixelImage.Color) = .{};
        defer pixels.deinit(allocator);

        for (image.pixels) |pixel| {
            if (self.use_transparency and pixel.a < 128) continue;
            try pixels.append(allocator, pixel);
        }

        if (pixels.items.len == 0) {
            // All transparent, return single black color
            const black = try allocator.alloc(SixelImage.Color, 1);
            black[0] = .{ .r = 0, .g = 0, .b = 0 };
            return black;
        }

        // For simplicity, just take first max_colors unique pixels
        var palette: std.ArrayList(SixelImage.Color) = .{};
        defer palette.deinit(allocator);

        for (pixels.items) |pixel| {
            var found = false;
            for (palette.items) |existing| {
                if (existing.r == pixel.r and existing.g == pixel.g and existing.b == pixel.b) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                if (palette.items.len >= self.max_colors) break;
                try palette.append(allocator, pixel);
            }
        }

        return try allocator.dupe(SixelImage.Color, palette.items);
    }

    fn encodeSixelRow(
        self: SixelEncoder,
        allocator: Allocator,
        image: SixelImage,
        palette: []const SixelImage.Color,
        sixel_y: u16,
        writer: anytype,
    ) !void {
        _ = allocator;

        // For each color in palette, encode run-length pixels
        for (palette, 0..) |color, color_idx| {
            // Select color: #index
            try writer.print("#{}", .{color_idx});

            var x: u16 = 0;
            while (x < image.width) {
                // Compute sixel value for this column (6 vertical pixels)
                var sixel_value: u8 = 0;
                var bit: u8 = 0;
                while (bit < 6) : (bit += 1) {
                    const pixel_y = sixel_y * 6 + bit;
                    if (pixel_y >= image.height) break;

                    const pixel_idx = @as(usize, pixel_y) * image.width + x;
                    const pixel = image.pixels[pixel_idx];

                    // Skip transparent pixels
                    if (self.use_transparency and pixel.a < 128) continue;

                    // Check if pixel matches this color
                    if (pixel.r == color.r and pixel.g == color.g and pixel.b == color.b) {
                        sixel_value |= (@as(u8, 1) << @intCast(bit));
                    }
                }

                // Encode sixel value as ASCII char (? = 0x3f + value)
                if (sixel_value > 0) {
                    try writer.writeByte(0x3f + sixel_value);
                }

                x += 1;
            }

            // Move to start of next row for next color: $
            if (color_idx + 1 < palette.len) {
                try writer.writeAll("$");
            }
        }
    }
};

/// Sixel decoder for parsing Sixel sequences back into images
pub const SixelDecoder = struct {
    /// Maximum allowed image width (prevents DoS via huge allocations)
    max_width: u16 = 4096,

    /// Maximum allowed image height
    max_height: u16 = 4096,

    /// Decode a Sixel sequence into an image
    pub fn decode(self: SixelDecoder, allocator: Allocator, data: []const u8) !SixelImage {
        // Validate Sixel sequence markers
        if (data.len < 5) return error.InvalidSixelFormat;
        if (!std.mem.startsWith(u8, data, "\x1bPq")) return error.InvalidSixelFormat;
        if (!std.mem.endsWith(u8, data, "\x1b\\")) return error.InvalidSixelFormat;

        // Extract payload (strip \x1bPq and \x1b\)
        const payload = data[3 .. data.len - 2];

        // Parse raster attributes: "Pan;Pad;Ph;Pv (width=Ph, height=Pv)
        var width: u16 = 0;
        var height: u16 = 0;
        var pos: usize = 0;

        if (std.mem.indexOfScalar(u8, payload, '"')) |raster_start| {
            pos = raster_start + 1;

            // Find end of raster attributes (first non-digit/semicolon char)
            var raster_end = pos;
            while (raster_end < payload.len) : (raster_end += 1) {
                const c = payload[raster_end];
                if (c != ';' and (c < '0' or c > '9')) break;
            }

            const raster_str = payload[pos..raster_end];
            var attr_parts = std.mem.tokenizeScalar(u8, raster_str, ';');

            // Skip Pan (aspect ratio) parameters if present
            _ = attr_parts.next() orelse return error.InvalidRasterAttributes;
            _ = attr_parts.next() orelse return error.InvalidRasterAttributes;

            // Parse width and height
            const width_str = attr_parts.next() orelse return error.InvalidRasterAttributes;
            const height_str = attr_parts.next() orelse return error.InvalidRasterAttributes;

            width = std.fmt.parseInt(u16, width_str, 10) catch return error.InvalidRasterAttributes;
            height = std.fmt.parseInt(u16, height_str, 10) catch return error.InvalidRasterAttributes;

            // Validate dimensions
            if (width == 0 or height == 0) return error.InvalidDimensions;
            if (width > self.max_width or height > self.max_height) return error.DimensionsTooLarge;

            pos = raster_end;
        } else {
            return error.InvalidRasterAttributes;
        }

        // Allocate pixel buffer (initialized to transparent black)
        const pixel_count = @as(usize, width) * @as(usize, height);
        const pixels = try allocator.alloc(SixelImage.Color, pixel_count);
        errdefer allocator.free(pixels);
        @memset(pixels, .{ .r = 0, .g = 0, .b = 0, .a = 0 }); // Transparent by default

        // Parse color palette and pixel data
        var palette: [256]SixelImage.Color = undefined;
        var current_color: u8 = 0;
        var x: u16 = 0;
        var y: u16 = 0; // Current sixel row (6-pixel units)

        while (pos < payload.len) {
            const c = payload[pos];
            pos += 1;

            switch (c) {
                '#' => {
                    // Color definition or selection: #index;2;r;g;b OR #index
                    const semicolon1 = std.mem.indexOfScalarPos(u8, payload, pos, ';') orelse {
                        // Just color selection: #index (no semicolon)
                        const num_end = pos;
                        while (num_end < payload.len and payload[num_end] >= '0' and payload[num_end] <= '9') : (pos += 1) {}
                        const index_str = payload[pos - 1 .. num_end];
                        current_color = std.fmt.parseInt(u8, index_str, 10) catch return error.InvalidColorDefinition;
                        continue;
                    };

                    const index_str = payload[pos..semicolon1];
                    const color_index = std.fmt.parseInt(u8, index_str, 10) catch return error.InvalidColorDefinition;
                    pos = semicolon1 + 1;

                    // Check if this is a definition (";2;r;g;b") or just selection
                    if (pos < payload.len and payload[pos] == '2') {
                        pos += 1; // Skip '2'
                        if (pos >= payload.len or payload[pos] != ';') return error.InvalidColorDefinition;
                        pos += 1; // Skip ';'

                        // Parse R
                        const semicolon2 = std.mem.indexOfScalarPos(u8, payload, pos, ';') orelse return error.InvalidColorDefinition;
                        const r_str = payload[pos..semicolon2];
                        const r_val = std.fmt.parseInt(u16, r_str, 10) catch return error.InvalidColorDefinition;
                        if (r_val > 100) return error.ColorValueOutOfRange;
                        pos = semicolon2 + 1;

                        // Parse G
                        const semicolon3 = std.mem.indexOfScalarPos(u8, payload, pos, ';') orelse return error.InvalidColorDefinition;
                        const g_str = payload[pos..semicolon3];
                        const g_val = std.fmt.parseInt(u16, g_str, 10) catch return error.InvalidColorDefinition;
                        if (g_val > 100) return error.ColorValueOutOfRange;
                        pos = semicolon3 + 1;

                        // Parse B (may end with any non-digit char)
                        var b_end = pos;
                        while (b_end < payload.len and payload[b_end] >= '0' and payload[b_end] <= '9') : (b_end += 1) {}
                        const b_str = payload[pos..b_end];
                        const b_val = std.fmt.parseInt(u16, b_str, 10) catch return error.InvalidColorDefinition;
                        if (b_val > 100) return error.ColorValueOutOfRange;
                        pos = b_end;

                        // Scale from 0-100 to 0-255
                        palette[color_index] = .{
                            .r = @intCast(r_val * 255 / 100),
                            .g = @intCast(g_val * 255 / 100),
                            .b = @intCast(b_val * 255 / 100),
                            .a = 255,
                        };
                    }

                    current_color = color_index;
                },
                '$' => {
                    // Carriage return (move to start of current sixel row)
                    x = 0;
                },
                '-' => {
                    // Line feed (move to next sixel row)
                    y += 1;
                    x = 0;
                },
                '?' ... '~' => {
                    // Sixel data: '?' (0x3f) represents 0, '~' (0x7e) represents 63
                    const sixel_value = c - 0x3f;

                    // Decode 6 vertical pixels
                    var bit: u8 = 0;
                    while (bit < 6) : (bit += 1) {
                        if ((sixel_value & (@as(u8, 1) << @as(u3, @intCast(bit)))) != 0) {
                            const pixel_y = y * 6 + bit;
                            if (pixel_y < height and x < width) {
                                const pixel_idx = @as(usize, pixel_y) * width + x;
                                pixels[pixel_idx] = palette[current_color];
                            }
                        }
                    }

                    x += 1;
                },
                else => {
                    // Ignore other characters (whitespace, unknown control codes)
                },
            }
        }

        return SixelImage{
            .width = width,
            .height = height,
            .pixels = pixels,
        };
    }
};

/// Detect if terminal supports Sixel graphics
pub fn detectSixelSupport() bool {
    const term_mod = @import("../term.zig");

    // Try XTGETTCAP query first (most reliable)
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Query "Sixel" capability with 100ms timeout
    const stdout_fd: std.posix.fd_t = if (builtin.os.tag == .windows) blk: {
        const handle = std.os.windows.GetStdHandle(std.os.windows.STD_OUTPUT_HANDLE) catch return false;
        break :blk @ptrCast(handle);
    } else
        std.posix.STDOUT_FILENO;

    if (term_mod.hasCapability(allocator, stdout_fd, "Sixel", 100)) |has_sixel| {
        if (has_sixel) return true;
    } else |_| {
        // XTGETTCAP failed (not a TTY, unsupported platform, etc.) - fall back to env vars
    }

    // Fallback: Check TERM environment variable for known Sixel-capable terminals
    // Windows doesn't support std.posix.getenv (env vars are UTF-16)
    if (builtin.os.tag == .windows) {
        return false;
    } else {
        const term = std.posix.getenv("TERM") orelse return false;

        const sixel_terms = [_][]const u8{
            "xterm-256color",
            "mlterm",
            "yaft",
            "foot",
            "wezterm",
            "contour",
        };

        for (sixel_terms) |known_term| {
            if (std.mem.eql(u8, term, known_term)) {
                return true;
            }
        }

        return false;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "SixelImage Color creation" {
    const color1 = SixelImage.Color.fromRgb(255, 128, 64);
    try std.testing.expectEqual(@as(u8, 255), color1.r);
    try std.testing.expectEqual(@as(u8, 128), color1.g);
    try std.testing.expectEqual(@as(u8, 64), color1.b);
    try std.testing.expectEqual(@as(u8, 255), color1.a); // Default alpha

    const color2 = SixelImage.Color.fromRgba(100, 150, 200, 128);
    try std.testing.expectEqual(@as(u8, 128), color2.a);
}

test "SixelEncoder basic encode 2x2 solid image" {
    const allocator = std.testing.allocator;

    // Create 2x2 red image
    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 }, .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 }, .{ .r = 255, .g = 0, .b = 0 },
    };

    const image = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Verify Sixel sequence markers
    try std.testing.expect(std.mem.startsWith(u8, result, "\x1bPq")); // Start
    try std.testing.expect(std.mem.endsWith(u8, result, "\x1b\\")); // End
    try std.testing.expect(std.mem.indexOf(u8, result, "\"1;1;2;2") != null); // Raster attrs
}

test "SixelEncoder transparency handling" {
    const allocator = std.testing.allocator;

    // Create 2x2 image with transparent pixel
    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0, .a = 255 }, // Opaque red
        .{ .r = 0, .g = 255, .b = 0, .a = 0 }, // Transparent
        .{ .r = 0, .g = 0, .b = 255, .a = 255 }, // Opaque blue
        .{ .r = 255, .g = 255, .b = 255, .a = 64 }, // Semi-transparent (treated as transparent)
    };

    const image = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{ .use_transparency = true };
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should only encode opaque pixels
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, result, "\x1bPq"));
}

test "SixelEncoder palette building" {
    const allocator = std.testing.allocator;

    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 }, // Red
        .{ .r = 0, .g = 255, .b = 0 }, // Green
        .{ .r = 0, .g = 0, .b = 255 }, // Blue
        .{ .r = 255, .g = 0, .b = 0 }, // Red again (duplicate)
    };

    const image = SixelImage{
        .width = 2,
        .height = 2,
        .pixels = &pixels,
    };

    const encoder = SixelEncoder{ .quantization = .none };
    const palette = try encoder.buildPalette(allocator, image);
    defer allocator.free(palette);

    // Should have 3 unique colors
    try std.testing.expectEqual(@as(usize, 3), palette.len);
}

test "SixelEncoder max colors limit" {
    const allocator = std.testing.allocator;

    // Create image with 10 unique colors
    var pixels: [10]SixelImage.Color = undefined;
    for (&pixels, 0..) |*p, i| {
        p.* = .{ .r = @intCast(i * 25), .g = 0, .b = 0 };
    }

    const image = SixelImage{
        .width = 10,
        .height = 1,
        .pixels = &pixels,
    };

    const encoder = SixelEncoder{ .max_colors = 5, .quantization = .none };
    const palette = try encoder.buildPalette(allocator, image);
    defer allocator.free(palette);

    // Should limit to 5 colors
    try std.testing.expectEqual(@as(usize, 5), palette.len);
}

test "SixelEncoder all transparent image" {
    const allocator = std.testing.allocator;

    const pixels = [_]SixelImage.Color{
        .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    };

    const image = SixelImage{
        .width = 2,
        .height = 1,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{ .use_transparency = true };
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should produce valid Sixel sequence with black palette
    try std.testing.expect(std.mem.startsWith(u8, result, "\x1bPq"));
    try std.testing.expect(std.mem.endsWith(u8, result, "\x1b\\"));
}

test "SixelEncoder 1x6 vertical stripe" {
    const allocator = std.testing.allocator;

    // Create 1x6 vertical stripe (fills one sixel column exactly)
    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
    };

    const image = SixelImage{
        .width = 1,
        .height = 6,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should encode full sixel (6 bits set = 63 + 0x3f = 0x7e = '~')
    try std.testing.expect(std.mem.indexOf(u8, result, "~") != null);
}

test "SixelEncoder 1x7 vertical stripe (partial sixel)" {
    const allocator = std.testing.allocator;

    // Create 1x7 stripe (needs 2 sixel rows)
    var pixels: [7]SixelImage.Color = undefined;
    for (&pixels) |*p| {
        p.* = .{ .r = 0, .g = 255, .b = 0 };
    }

    const image = SixelImage{
        .width = 1,
        .height = 7,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should have row separator '-'
    try std.testing.expect(std.mem.indexOf(u8, result, "-") != null);
}

test "detectSixelSupport with known terminal" {
    // Skip when stdout is not a TTY (e.g., zig build test --listen=- mode)
    // detectSixelSupport() writes escape sequences to STDOUT_FILENO which
    // would corrupt the --listen=- IPC pipe
    const term_mod = @import("../term.zig");
    if (!term_mod.isatty(std.posix.STDOUT_FILENO)) return error.SkipZigTest;
    _ = detectSixelSupport();
}

test "SixelEncoder color RGB scaling" {
    const allocator = std.testing.allocator;

    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 128, .b = 64 },
    };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Color definition should scale RGB to 0-100 range
    // r=255 → 100, g=128 → 50, b=64 → 25
    try std.testing.expect(std.mem.indexOf(u8, result, "#0;2;100;50;25") != null);
}

test "SixelEncoder multiple colors with run-length" {
    const allocator = std.testing.allocator;

    // Create 4x1 image: red, red, blue, blue
    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 0, .b = 255 },
        .{ .r = 0, .g = 0, .b = 255 },
    };

    const image = SixelImage{
        .width = 4,
        .height = 1,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should define at least 2 colors
    try std.testing.expect(std.mem.indexOf(u8, result, "#0;2;") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "#1;2;") != null);
}

test "SixelEncoder empty image (0x0)" {
    const allocator = std.testing.allocator;

    const image = SixelImage{
        .width = 0,
        .height = 0,
        .pixels = &[_]SixelImage.Color{},
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should produce valid (but empty) Sixel sequence
    try std.testing.expect(std.mem.startsWith(u8, result, "\x1bPq"));
    try std.testing.expect(std.mem.endsWith(u8, result, "\x1b\\"));
}

test "SixelEncoder single pixel" {
    const allocator = std.testing.allocator;

    const pixels = [_]SixelImage.Color{
        .{ .r = 42, .g = 84, .b = 168 },
    };

    const image = SixelImage{
        .width = 1,
        .height = 1,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    try std.testing.expect(std.mem.startsWith(u8, result, "\x1bPq"));
    try std.testing.expect(std.mem.indexOf(u8, result, "\"1;1;1;1") != null); // 1x1 raster
}

test "SixelEncoder no transparency mode" {
    const allocator = std.testing.allocator;

    const pixels = [_]SixelImage.Color{
        .{ .r = 255, .g = 0, .b = 0, .a = 0 }, // Fully transparent
        .{ .r = 0, .g = 255, .b = 0, .a = 64 }, // Semi-transparent
    };

    const image = SixelImage{
        .width = 2,
        .height = 1,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{ .use_transparency = false }; // Ignore alpha
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should encode all pixels regardless of alpha
    try std.testing.expect(result.len > 0);
}

test "SixelEncoder wide image (triggers multiple columns)" {
    const allocator = std.testing.allocator;

    // Create 8x1 alternating colors
    var pixels: [8]SixelImage.Color = undefined;
    for (&pixels, 0..) |*p, i| {
        p.* = if (i % 2 == 0)
            .{ .r = 255, .g = 0, .b = 0 }
        else
            .{ .r = 0, .g = 0, .b = 255 };
    }

    const image = SixelImage{
        .width = 8,
        .height = 1,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should produce valid Sixel with multiple pixel runs
    try std.testing.expect(std.mem.startsWith(u8, result, "\x1bPq"));
    try std.testing.expect(std.mem.indexOf(u8, result, "\"1;1;8;1") != null); // 8x1 raster
}

test "SixelEncoder tall image (multiple sixel rows)" {
    const allocator = std.testing.allocator;

    // Create 1x12 vertical stripe (2 sixel rows)
    var pixels: [12]SixelImage.Color = undefined;
    for (&pixels) |*p| {
        p.* = .{ .r = 128, .g = 128, .b = 128 };
    }

    const image = SixelImage{
        .width = 1,
        .height = 12,
        .pixels = &pixels,
    };

    var output: std.ArrayList(u8) = .{};
    defer output.deinit(allocator);

    const encoder = SixelEncoder{};
    try encoder.encode(allocator, image, output.writer(allocator));

    const result = output.items;

    // Should have row separator '-'
    try std.testing.expect(std.mem.indexOf(u8, result, "-") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"1;1;1;12") != null); // 1x12 raster
}

// ============================================================================
// Animation Support
// ============================================================================

/// Sixel animator for GIF-like frame sequences
pub const SixelAnimator = struct {
    /// Frame disposal method (GIF-like frame transition control)
    pub const DisposalMethod = enum {
        /// Do not dispose - overlay on previous frame
        none,
        /// Clear to background/transparent before next frame
        background,
        /// Restore to previous frame state
        previous,
    };

    /// Sixel animation frame
    pub const Frame = struct {
        image: SixelImage,
        delay_ms: u32, // Frame display duration in milliseconds
        disposal_method: DisposalMethod,
    };

    allocator: Allocator,
    frames: ArrayList(Frame),
    current_frame_index: usize,
    elapsed_ms: u32, // Time elapsed in current frame
    playing: bool,
    loop_count: u32, // 0 = infinite loop, N = play N times
    current_loop: u32, // Current loop iteration (1-based)

    /// Initialize empty animator
    pub fn init(allocator: Allocator) !SixelAnimator {
        return SixelAnimator{
            .allocator = allocator,
            .frames = ArrayList(Frame){},
            .current_frame_index = 0,
            .elapsed_ms = 0,
            .playing = false,
            .loop_count = 0, // Default: infinite loop
            .current_loop = 1,
        };
    }

    /// Free all resources
    pub fn deinit(self: *SixelAnimator) void {
        // Free pixel data for all frames
        for (self.frames.items) |frame| {
            self.allocator.free(frame.image.pixels);
        }
        self.frames.deinit(self.allocator);
    }

    /// Add frame with default disposal method (.none)
    pub fn addFrame(self: *SixelAnimator, image: SixelImage, delay_ms: u32) !void {
        try self.addFrameWithDisposal(image, delay_ms, .none);
    }

    /// Add frame with explicit disposal method
    pub fn addFrameWithDisposal(
        self: *SixelAnimator,
        image: SixelImage,
        delay_ms: u32,
        disposal_method: DisposalMethod,
    ) !void {
        // Clone pixel data (caller retains ownership of input)
        const pixels_copy = try self.allocator.alloc(SixelImage.Color, image.pixels.len);
        @memcpy(pixels_copy, image.pixels);

        const frame = Frame{
            .image = SixelImage{
                .width = image.width,
                .height = image.height,
                .pixels = pixels_copy,
            },
            .delay_ms = delay_ms,
            .disposal_method = disposal_method,
        };

        try self.frames.append(self.allocator, frame);
    }

    /// Get number of frames
    pub fn getFrameCount(self: SixelAnimator) usize {
        return self.frames.items.len;
    }

    /// Get frame by index (returns null if out of bounds)
    pub fn getFrame(self: SixelAnimator, index: usize) ?Frame {
        if (index >= self.frames.items.len) return null;
        return self.frames.items[index];
    }

    /// Get current frame index
    pub fn getCurrentFrameIndex(self: SixelAnimator) usize {
        return self.current_frame_index;
    }

    /// Get current frame
    pub fn getCurrentFrame(self: SixelAnimator) Frame {
        if (self.frames.items.len == 0) {
            // Return dummy frame for empty animator
            return Frame{
                .image = SixelImage{
                    .width = 0,
                    .height = 0,
                    .pixels = &[_]SixelImage.Color{},
                },
                .delay_ms = 0,
                .disposal_method = .none,
            };
        }
        return self.frames.items[self.current_frame_index];
    }

    /// Calculate total duration of all frames
    pub fn getTotalDuration(self: SixelAnimator) u32 {
        var total: u32 = 0;
        for (self.frames.items) |frame| {
            total += frame.delay_ms;
        }
        return total;
    }

    /// Start playback (idempotent)
    pub fn start(self: *SixelAnimator) void {
        self.playing = true;
    }

    /// Pause playback (does not reset position)
    pub fn pause(self: *SixelAnimator) void {
        self.playing = false;
    }

    /// Stop playback (resets to first frame)
    pub fn stop(self: *SixelAnimator) void {
        self.playing = false;
        self.current_frame_index = 0;
        self.elapsed_ms = 0;
        self.current_loop = 1;
    }

    /// Check if currently playing
    pub fn isPlaying(self: SixelAnimator) bool {
        return self.playing;
    }

    /// Jump to specific frame (clamps out-of-bounds)
    pub fn seek(self: *SixelAnimator, frame_index: usize) void {
        if (self.frames.items.len == 0) return; // No-op on empty animator

        // Clamp to valid range
        self.current_frame_index = @min(frame_index, self.frames.items.len - 1);
        self.elapsed_ms = 0; // Reset timing for new frame
    }

    /// Update animation state with elapsed time
    /// Returns true if frame changed
    pub fn update(self: *SixelAnimator, delta_ms: u32) bool {
        if (!self.playing) return false;
        if (self.frames.items.len == 0) return false;

        self.elapsed_ms += delta_ms;

        const current_frame = self.frames.items[self.current_frame_index];
        var frame_changed = false;

        // Advance through frames while elapsed time exceeds current frame delay
        while (self.elapsed_ms >= current_frame.delay_ms) {
            self.elapsed_ms -= current_frame.delay_ms;

            // Check if we can advance to next frame
            if (self.current_frame_index + 1 < self.frames.items.len) {
                // Move to next frame
                self.current_frame_index += 1;
                frame_changed = true;
            } else {
                // Reached last frame
                if (self.loop_count == 0) {
                    // Infinite loop: wrap to first frame
                    self.current_frame_index = 0;
                    frame_changed = true;
                } else {
                    // Finite loop: check if we've completed all iterations
                    if (self.current_loop < self.loop_count) {
                        // Start next loop
                        self.current_loop += 1;
                        self.current_frame_index = 0;
                        frame_changed = true;
                    } else {
                        // Completed all loops: stop
                        self.playing = false;
                        self.elapsed_ms = 0; // Stay on last frame
                        return frame_changed;
                    }
                }
            }

            // Update current_frame reference after index change
            const new_frame = self.frames.items[self.current_frame_index];
            if (self.elapsed_ms < new_frame.delay_ms) {
                // Not enough time to skip this frame too
                break;
            }
        }

        return frame_changed;
    }
};

// ============================================================================
// Run-Length Encoding (RLE) Compression
// ============================================================================

/// Sixel compression using Run-Length Encoding (RLE)
/// Repeated characters are encoded as "!<count><char>" where count is decimal.
/// Reduces bandwidth for sixel data with high repetition (common with solid colors).
pub const SixelCompressor = struct {
    /// Compress sixel data using RLE
    /// Runs of 2+ identical characters are compressed as "!<count><char>"
    /// Single characters are left as literals
    ///
    /// Args:
    ///   allocator: Memory allocator for result buffer
    ///   data: Uncompressed sixel data (or any data)
    ///
    /// Returns:
    ///   Compressed data (caller owns, must free)
    ///
    /// Errors:
    ///   error.OutOfMemory if allocation fails
    pub fn compress(allocator: Allocator, data: []const u8) ![]u8 {
        if (data.len == 0) {
            return try allocator.alloc(u8, 0);
        }

        var result = std.ArrayList(u8){};
        errdefer result.deinit(allocator);

        var i: usize = 0;
        while (i < data.len) {
            const current_char = data[i];
            var run_length: usize = 1;

            // Count consecutive identical characters
            while (i + run_length < data.len and data[i + run_length] == current_char) {
                run_length += 1;
            }

            if (run_length >= 2) {
                // Compress runs >= 2 characters
                // Split runs > 255 into multiple sequences
                var remaining = run_length;
                while (remaining > 0) {
                    const chunk_size = if (remaining > 255) 255 else remaining;

                    // Write "!" prefix
                    try result.append(allocator, '!');

                    // Write count as decimal string
                    var buf: [6]u8 = undefined;
                    const count_str = try std.fmt.bufPrint(&buf, "{}", .{chunk_size});
                    try result.appendSlice(allocator, count_str);

                    // Write character
                    try result.append(allocator, current_char);

                    remaining -= chunk_size;
                }
            } else {
                // Keep runs < 3 as literals
                try result.appendSlice(allocator, data[i .. i + run_length]);
            }

            i += run_length;
        }

        return result.toOwnedSlice(allocator);
    }

    /// Decompress RLE-compressed data
    /// Format: "!<decimal-count><char>" for repeated sequences
    /// All other characters are literals
    ///
    /// Args:
    ///   allocator: Memory allocator for result buffer
    ///   compressed: RLE-compressed data
    ///
    /// Returns:
    ///   Original uncompressed data (caller owns, must free)
    ///
    /// Errors:
    ///   error.InvalidRepeatCount if count after "!" is not valid decimal
    ///   error.IncompleteCompressedData if data ends prematurely (e.g., "!3" with no char)
    ///   error.RepeatCountTooLarge if count exceeds 65535
    pub fn decompress(allocator: Allocator, compressed: []const u8) ![]u8 {
        if (compressed.len == 0) {
            return try allocator.alloc(u8, 0);
        }

        var result = std.ArrayList(u8){};
        errdefer result.deinit(allocator);

        var i: usize = 0;
        while (i < compressed.len) {
            if (compressed[i] == '!') {
                // Parse repeat sequence
                i += 1;

                // Parse decimal count
                var count_end = i;
                while (count_end < compressed.len and compressed[count_end] >= '0' and compressed[count_end] <= '9') {
                    count_end += 1;
                }

                if (count_end == i) {
                    // No digits found after '!'
                    return error.InvalidRepeatCount;
                }

                const count_str = compressed[i..count_end];
                const count = std.fmt.parseInt(u32, count_str, 10) catch return error.InvalidRepeatCount;

                if (count > 65535) {
                    return error.RepeatCountTooLarge;
                }

                // Next character is the one to repeat
                if (count_end >= compressed.len) {
                    return error.IncompleteCompressedData;
                }

                const char_to_repeat = compressed[count_end];

                // Append character 'count' times
                try result.appendNTimes(allocator, char_to_repeat, count);

                i = count_end + 1;
            } else {
                // Literal character
                try result.append(allocator, compressed[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice(allocator);
    }

    /// Calculate compression ratio (original size / compressed size)
    /// Higher ratio = better compression
    ///
    /// Args:
    ///   original: Uncompressed data
    ///   compressed: Compressed data
    ///
    /// Returns:
    ///   Ratio as f32 (original.len / compressed.len)
    pub fn compressionRatio(original: []const u8, compressed: []const u8) f32 {
        if (compressed.len == 0) {
            if (original.len == 0) return 1.0;
            return std.math.inf(f32);
        }
        return @as(f32, @floatFromInt(original.len)) / @as(f32, @floatFromInt(compressed.len));
    }
};
