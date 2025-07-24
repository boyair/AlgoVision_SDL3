const std = @import("std");
const sdl = @import("sdl3");
const ft = @import("freetype");
const helpers = @import("../SDL_helpers.zig");
const View = @import("../view.zig");
const Self = @This();
stack_frame: std.ArrayList(Block),
block_texture: sdl.render.Texture,
/// used to make textures for block
renderer: sdl.render.Renderer,
default_font: ft.Face,
allocator: std.mem.Allocator,
base_rect: sdl.rect.FRect,
/// current stack height
height: usize = 0,

pub fn init(allocator: std.mem.Allocator, renderer: sdl.render.Renderer, rect: sdl.rect.FRect, block_texture_path: []const u8, font: ft.Face) !Self {
    return Self{
        .stack_frame = std.ArrayList(Block).init(allocator),
        .renderer = renderer,
        .block_texture = helpers.loadImage(renderer, block_texture_path, allocator) catch {
            @panic("failed to load stack block texture");
        },
        .default_font = font,
        .allocator = allocator,
        .base_rect = rect,
    };
}
pub fn deinit(self: *Self) void {
    for (self.stack_frame.items) |block| {
        block.deinit(self.allocator);
    }
    self.stack_frame.deinit();
    self.block_texture.deinit();
    self.default_font.deinit();
}

pub fn draw(self: *Self, renderer: sdl.render.Renderer, view: ?View) !void {
    var cur_rect = self.base_rect;

    for (self.stack_frame.items, 0..) |*block, idx| {
        if (idx >= self.height) break;
        try block.draw(
            renderer,
            if (view) |v| v.convertRect(sdl.rect.FloatingType, cur_rect) else cur_rect,
            self.block_texture,
        );
        cur_rect.y -= self.base_rect.h;
    }
}

pub fn push(self: *Self, text: []const u8) !void {
    try self.stack_frame.append(Block.init(
        text,
        .{
            .font = self.default_font,
            .text_color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        },
        self.allocator,
    ));
    self.height += 1;
}

///returns reference to top block
pub fn topBlock(self: *Self) *Block {
    return &self.stack_frame.items[self.stack_frame.items.len - 1];
}

// INNER TYPES
pub const Block = struct {
    text: []const u8,
    last_text: []const u8,
    texture_cache: ?sdl.render.Texture = null,
    design: Design,

    pub fn init(text: []const u8, design: Design, allocator: std.mem.Allocator) Block {
        return Block{
            .text = allocator.dupe(u8, text) catch unreachable,
            .last_text = allocator.dupe(u8, text) catch unreachable,
            .texture_cache = null,
            .design = design,
        };
    }

    pub fn deinit(self: *const Block, allocator: std.mem.Allocator) void {
        if (self.texture_cache) |texture| texture.deinit();
        allocator.free(self.last_text);
        allocator.free(self.text);
    }

    pub fn setText(self: *Block, text: []const u8, allocator: std.mem.Allocator) void {
        allocator.free(self.last_text);
        self.last_text = self.text;
        self.text = allocator.dupe(u8, text) catch unreachable;
    }

    pub fn draw(self: *Block, renderer: sdl.render.Renderer, rect: sdl.rect.FRect, block_texture: sdl.render.Texture) !void {
        const text_changed = !std.mem.eql(u8, self.text, self.last_text);
        if (text_changed or self.texture_cache == null) {
            self.texture_cache = try self.makeTexture(renderer, block_texture, self.design);
        }
        try renderer.renderTexture(self.texture_cache.?, null, rect);
    }

    fn makeTexture(self: *Block, renderer: sdl.render.Renderer, block_texture: sdl.render.Texture, design: Design) !sdl.render.Texture {
        const texture = try helpers.cloneTexture(block_texture, renderer);
        const texture_size = try texture.getSize();
        const last_target = renderer.getTarget();
        defer renderer.setTarget(last_target) catch {
            @panic("failed to restore renderer target");
        };
        try renderer.setTarget(texture);

        //TODO: replace last 3 characters with "..." if limit reached
        const text_texture = try helpers.createTextureFromText(
            design.font,
            if (design.text_limit) |limit| self.text[0..@min(limit, self.text.len)] else self.text,
            design.text_color,
            renderer,
        );

        const text_rect = helpers.centrelizedRect(
            sdl.rect.FloatingType,
            .{ .x = 0, .y = 0, .w = texture_size.width, .h = texture_size.height },
            .{ .x = @min(@as(sdl.rect.FloatingType, @floatFromInt(self.text.len * 40)), texture_size.width - 50), .y = 100 },
        );
        try renderer.renderTexture(text_texture, null, text_rect);
        return texture;
    }
};

pub const Design = struct {
    font: ft.Face,
    text_color: sdl.pixels.Color,
    text_limit: ?usize = 15, //limits the text length when making texture
};

pub fn topRect(self: *const Self) sdl.rect.FRect {
    if (self.stack_frame.items.len == 0) return self.base_rect;
    return sdl.rect.FRect{
        .x = self.base_rect.x,
        .y = self.base_rect.y - @as(f32, @floatFromInt(self.height)) * self.base_rect.h,
        .w = self.base_rect.w,
        .h = self.base_rect.h,
    };
}
