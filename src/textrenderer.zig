/// This entire file was written by AI.
/// I have no clue what I'm doing.
/// AI actually writes this comment as well.
const std = @import("std");
const sdl = @import("sdl3");
const ft = @import("freetype");
library: ft.Library,
allocator: std.mem.Allocator,
const Self = @This();
pub fn init(allocator: std.mem.Allocator) !Self {
    const library = try ft.Library.init(allocator);

    return Self{
        .library = library,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.library.deinit();
}

/// Creates an SDL texture from text using a pre-loaded FreeType face.
///
/// Parameters:
/// - self: TextRenderer instance
/// - renderer: SDL renderer to create the texture with
/// - face: Pre-loaded FreeType face with font and size already set
/// - text: Text string to render
/// - color: RGBA color for the text
///
/// Returns: SDL texture containing the rendered text
///
/// Note: The caller is responsible for calling deinit() on the returned texture.
/// All temporary memory allocations are cleaned up automatically.
pub fn createTextTexture(
    self: *Self,
    renderer: sdl.render.Renderer,
    face: ft.Face,
    text: []const u8,
    color: sdl.pixels.Color,
) !sdl.render.Texture {
    // Get font size from face (assuming it's already set)
    const font_size = @as(u32, @intCast(face.ft_face.*.size.*.metrics.height >> 6));

    // Calculate text dimensions
    var text_width: i32 = 0;
    var text_height: i32 = 0;
    var max_ascent: i32 = 0;
    var max_descent: i32 = 0;

    // First pass: calculate dimensions
    for (text) |char| {
        // Load and render character
        var glyph = try face.getGlyph(char);
        defer glyph.deinit();
        const bitmap_glyph = try glyph.glyphBitmap();
        const bitmap = bitmap_glyph.*.bitmap;

        // For monospace font, use fixed advance based on font size
        // Monospace characters are typically 60% of font size in width
        text_width += @divTrunc(@as(i32, @intCast(font_size)) * 6, 10);

        const glyph_height = @as(i32, @intCast(bitmap.rows));
        const bearing_y = bitmap_glyph.*.top;

        max_ascent = @max(max_ascent, bearing_y);
        max_descent = @max(max_descent, glyph_height - bearing_y);
    }

    text_height = max_ascent + max_descent;

    if (text_width == 0 or text_height == 0) {
        return error.InvalidTextDimensions;
    }

    // Create bitmap buffer
    const bitmap_size = @as(usize, @intCast(text_width * text_height));
    const bitmap = try self.allocator.alloc(u8, bitmap_size);
    defer self.allocator.free(bitmap);

    // Clear bitmap
    @memset(bitmap, 0);

    // Second pass: render characters
    var x_pos: i32 = 0;
    const baseline = max_ascent;

    for (text) |char| {
        // Load and render character
        var glyph = try face.getGlyph(char);
        defer glyph.deinit();
        const bitmap_glyph = try glyph.glyphBitmap();
        const ft_bitmap = bitmap_glyph.*.bitmap;

        // Handle space character specially - no bitmap to render
        if (char == ' ') {
            x_pos += @divTrunc(@as(i32, @intCast(font_size)) * 6, 10);
            continue;
        }

        if (ft_bitmap.buffer == null) continue;

        // Calculate glyph position
        const glyph_x = x_pos + bitmap_glyph.*.left;
        const glyph_y = baseline - bitmap_glyph.*.top;

        // Copy glyph bitmap to main bitmap
        const glyph_width = @as(i32, @intCast(ft_bitmap.width));
        const glyph_height = @as(i32, @intCast(ft_bitmap.rows));

        var y: i32 = 0;
        while (y < glyph_height) : (y += 1) {
            const dst_y = glyph_y + y;
            if (dst_y >= 0 and dst_y < text_height) {
                var x: i32 = 0;
                while (x < glyph_width) : (x += 1) {
                    const dst_x = glyph_x + x;
                    if (dst_x >= 0 and dst_x < text_width) {
                        const src_idx = @as(usize, @intCast(y * glyph_width + x));
                        const dst_idx = @as(usize, @intCast(dst_y * text_width + dst_x));
                        bitmap[dst_idx] = ft_bitmap.buffer.?[src_idx];
                    }
                }
            }
        }

        // Advance to next character position for non-space characters
        x_pos += @divTrunc(@as(i32, @intCast(font_size)) * 6, 10);
    }

    // Convert grayscale bitmap to RGBA with specified color
    const rgba_size = bitmap_size * 4;
    const rgba_data = try self.allocator.alloc(u8, rgba_size);
    defer self.allocator.free(rgba_data);

    for (bitmap, 0..) |gray_pixel, i| {
        const alpha = gray_pixel;
        // Use the specified color with grayscale as alpha
        rgba_data[i * 4 + 0] = @as(u8, @intCast((@as(u32, color.r) * alpha) / 255)); // R
        rgba_data[i * 4 + 1] = @as(u8, @intCast((@as(u32, color.g) * alpha) / 255)); // G
        rgba_data[i * 4 + 2] = @as(u8, @intCast((@as(u32, color.b) * alpha) / 255)); // B
        rgba_data[i * 4 + 3] = alpha; // A - use grayscale as alpha
    }

    // Create surface
    const surface = try sdl.surface.Surface.initFrom(@intCast(text_width), @intCast(text_height), .packed_rgba_8_8_8_8, rgba_data);
    defer surface.deinit();

    // Create texture from surface
    const texture = try renderer.createTextureFromSurface(surface);

    return texture;
}
