const std = @import("std");
const ft = @import("freetype");
const sdl = @import("sdl3");

const helpers = @import("../SDL_helpers.zig");
const View = @import("../view.zig");

//
// new block -> internal.
// update ->
const Self = @This();
blocks: std.hash_map.AutoHashMap(*anyopaque, Block),
byte_bg: sdl.render.Texture,
/// used to make textures for block
renderer: ?sdl.render.Renderer, // an optional to allow "headless" structs
default_font: ft.Face,
allocator: std.mem.Allocator,
draw_scale: usize = 50, //scale between struct rect and texture rect
area: sdl.rect.IRect,
bg_texture: ?sdl.render.Texture,

pub const Block = struct {
    rect: sdl.rect.IRect,
    fields: std.ArrayList(Field) = .{},
    updated: bool = false,
    texture_cache: ?sdl.render.Texture,
    design: Design,
    allocator: std.mem.Allocator,

    ///initiallize a block by giving it a struct
    /// parameters:
    /// val - the value from which the block is created
    /// design - visual properties
    /// allocator - allocator used to allocate fields
    /// pos - initial position of block
    pub fn init(val: anytype, design: Design, allocator: std.mem.Allocator, pos: sdl.rect.IPoint) Block {
        var fields = std.ArrayList(Field){};
        appendFields(val, &fields, allocator);
        const top_width = blk: {
            var top: usize = 0;
            for (fields.items) |field| {
                top = @max(top, field.size);
            }
            break :blk top;
        };

        return Block{
            .rect = .{ .x = pos.x, .y = pos.y, .h = @intCast(fields.items.len), .w = @intCast(top_width) },
            .fields = fields,
            .texture_cache = null,
            .design = design,
            .allocator = allocator,
        };
    }

    //A function is used to append all the fields.
    //This function uses recursion therefor cannot be embeded in the init function.
    fn appendFields(val: anytype, fields: *std.ArrayList(Field), allocator: std.mem.Allocator) void {
        switch (@typeInfo(@TypeOf(val))) {
            .@"struct" => {
                inline for (std.meta.fields(@TypeOf(val))) |field| {
                    appendFields(@field(val, field.name), fields, allocator);
                }
            },
            .pointer => |ptr| {
                if (ptr.size == .slice) {
                    if (ptr.child == u8) {
                        fields.append(allocator, Field.init(val, allocator) catch @panic("field init failure"), null) catch @panic("alloc error");
                    } else {
                        for (val) |elm| {
                            appendFields(elm, fields, allocator);
                        }
                    }
                } else if (ptr.size == .one) {
                    const fld = Field.init(@as(*anyopaque, @ptrCast(val)), allocator, null) catch @panic("field init failure");
                    fields.append(allocator, fld) catch @panic("alloc error");
                }
            },
            .optional => {
                if (val) |real| {
                    appendFields(real, fields, allocator);
                } else {
                    fields.append(
                        allocator,
                        Field.init(
                            @as([]const u8, "null"),
                            allocator,
                            @sizeOf(@typeInfo(@TypeOf(val)).optional.child),
                        ) catch @panic("field init failure"),
                    ) catch @panic("alloc error");
                }
            },
            else => {
                // Handles other simple types
                fields.append(Field.init(val, allocator, null) catch @panic("field init failure")) catch @panic("alloc error");
            },
        }
    }

    pub fn draw(self: *Block, renderer: sdl.render.Renderer, block_texture: sdl.render.Texture, view: ?View, scale: usize) !void {
        if (self.updated or self.texture_cache == null) {
            self.texture_cache = try self.makeTexture(renderer, block_texture, scale);
        }

        var rect = Self.scaleRect(self.rect, scale);
        if (view) |v| rect = v.convertRect(sdl.rect.IntegerType, rect);
        try renderer.renderTexture(self.texture_cache.?, null, rect.asOtherRect(sdl.rect.FloatingType));
    }

    fn makeTexture(self: *Block, renderer: sdl.render.Renderer, bg_texture: sdl.render.Texture, scale: usize) !sdl.render.Texture {
        const texture = try sdl.render.Texture.init(renderer, .packed_rgba_8_8_8_8, .target, @as(usize, @intCast(self.rect.w)) * scale, @as(usize, @intCast(self.rect.h)) * scale);
        const last_target = renderer.getTarget();
        defer renderer.setTarget(last_target) catch {
            @panic("failed to restore renderer target");
        };
        try renderer.setTarget(texture);

        for (self.fields.items, 0..) |field, i| {
            const field_texture = try field.MakeTexture(renderer, scale, self.design.font, self.design.text_color, bg_texture);
            defer field_texture.deinit();

            const field_rect =
                sdl.rect.Rect(usize){
                    .x = 0,
                    .y = i * scale,
                    .w = field.size * scale,
                    .h = scale,
                };
            try renderer.renderTexture(field_texture, null, field_rect.asOtherRect(sdl.rect.FloatingType));
        }

        return texture;
    }

    pub fn deinit(self: *Block) void {
        if (self.texture_cache) |texture| texture.deinit();
        for (self.fields.items) |field| {
            self.allocator.free(field.val);
        }
        self.fields.clearAndFree(self.allocator);
    }

    pub fn deepCopy(self: *const Block, allocator: std.mem.Allocator) Block {
        // copy all field strings
        var new_fields = std.ArrayList(Field).initCapacity(allocator, self.fields.items.len) catch @panic("alloc error");
        for (self.fields.items) |*field| {
            new_fields.appendAssumeCapacity(.{ .size = field.size, .val = allocator.dupe(u8, field.val) catch @panic("alloc error"), .ptr = field.ptr });
        }

        return Block{
            .rect = self.rect,
            .fields = new_fields,
            .texture_cache = null,
            .design = self.design,
            .allocator = self.allocator,
        };
    }
};

pub fn scaleRect(rect: sdl.rect.IRect, scale: usize) sdl.rect.IRect {
    var scaled_rect = rect;
    scaled_rect.x *= @intCast(scale);
    scaled_rect.y *= @intCast(scale);
    scaled_rect.w *= @intCast(scale);
    scaled_rect.h *= @intCast(scale);
    return scaled_rect;
}

pub fn push(self: *Self, ptr: *anyopaque, block: Block) !void {
    try self.blocks.put(ptr, block);
}

pub fn create(self: *Self, val: anytype, position: sdl.rect.IRect) void {
    var it = self.blocks.iterator();
    // create block
    const block = Block.init(val, .{ .font = self.default_font, .text_color = .{ .r = 255, .g = 0, .b = 0, .a = 255 } }, self.allocator, position);
    while (it.next()) |entry| {
        entry.value_ptr.*.deinit(self.allocator);
        const rect: sdl.rect.IRect = entry.value_ptr.*.rect;
        if (block.rect.getIntersection(rect)) {
            block.deinit(self.allocator);
            return;
        }
    }

    // Allocate memory for a clone of the block using self.allocator
    const block_ptr = self.allocator.create(Block) catch unreachable;
    // Copy the block data
    block_ptr.* = block;
    // Add a pointer to it in the blocks member
    self.blocks.put(@ptrCast(&val), block_ptr.*) catch unreachable;
}

pub fn destroy(self: *Self, ptr: *anyopaque) void {
    if (self.blocks.getPtr(ptr)) |block| {
        block.deinit();
        if (self.blocks.remove(ptr) == false)
            @panic("tried to destroy non allocated memory");
    } else @panic("tried to destoy non existing memory");
}

pub fn override(self: *Self, ptr: *anyopaque, block: Block) void {
    const block_ptr = self.blocks.getPtr(ptr) orelse @panic("writing to non allocated memory");
    for (block.fields.items) |*field| {
        field.pointerToPos(self.blocks, self.allocator);
    }
    block_ptr.deinit();
    block_ptr.* = block;
}

fn convertPoint(self: *Self, point: sdl.rect.FPoint) sdl.rect.IPoint {
    const as_ipoint = point.asOtherPoint(sdl.rect.IntegerType);
    const converted = sdl.rect.IPoint{
        .x = @divTrunc((as_ipoint.x - self.area.x), @as(sdl.rect.IntegerType, @intCast(self.draw_scale))) + 2, //for some reason there is an offset of 2.
        .y = @divTrunc((as_ipoint.y - self.area.y), @as(sdl.rect.IntegerType, @intCast(self.draw_scale))),
    };
    return converted;
}

pub fn printBlockOnPoint(self: *Self, point: sdl.rect.FPoint) void {
    var it = self.blocks.iterator();
    const converted = self.convertPoint(point);
    while (it.next()) |entry| {
        if (entry.value_ptr.rect.pointIn(converted.asOtherPoint(sdl.rect.IntegerType))) {
            for (entry.value_ptr.fields.items) |*field| {
                std.debug.print("{s}\n", .{field.val});
            }
        }
    }
}

pub fn init(allocator: std.mem.Allocator, renderer: sdl.render.Renderer, area: sdl.rect.IRect, bg_texture_path: []const u8, block_texture_path: []const u8, font: ft.Face) !Self {
    return Self{
        .blocks = std.hash_map.AutoHashMap(*anyopaque, Block).init(allocator),
        .area = area,
        .byte_bg = helpers.loadImage(renderer, block_texture_path, allocator) catch {
            @panic("failed to load byte background texture");
        },
        .bg_texture = helpers.loadImage(renderer, bg_texture_path, allocator) catch {
            @panic("failed to load byte background texture");
        },
        .renderer = renderer,
        .default_font = font,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    var it = self.blocks.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    self.blocks.deinit();
    self.byte_bg.deinit();
}

pub fn draw(self: *Self, renderer: sdl.render.Renderer, view: ?View) !void {
    if (self.bg_texture) |bg| {
        var rect = Self.scaleRect(self.area, self.draw_scale);
        if (view) |v| rect = v.convertRect(sdl.rect.IntegerType, rect);
        try renderer.renderTexture(bg, null, rect.asOtherRect(sdl.rect.FloatingType));
    }
    var it = self.blocks.iterator();
    while (it.next()) |entry| {
        try entry.value_ptr.draw(renderer, self.byte_bg, view, self.draw_scale);
    }
}

const Field = struct {
    size: usize,
    val: []u8,
    ptr: ?*anyopaque, // ptrs needs to be reserved because they are transformed to coordinates later on.

    pub fn init(val: anytype, allocator: std.mem.Allocator, comptime size_override: ?usize) !Field {
        const val_size = size_override orelse @sizeOf(@TypeOf(val));
        const size_str = std.fmt.comptimePrint("{d}", .{val_size});
        const fmt = switch (@TypeOf(val)) {
            u8 => "{c}",
            []u8 => "{s}",
            []const u8 => "{s}",
            *anyopaque => "{any}",
            else => "{: ^" ++ size_str ++ "}",
        };

        const formatted_val = try std.fmt.allocPrint(allocator, fmt, .{val});
        return Field{
            .size = val_size,
            .val = formatted_val,
            .ptr = if (@TypeOf(val) == *anyopaque) val else null,
        };
    }
    pub fn MakeTexture(self: *const Field, renderer: sdl.render.Renderer, scale: usize, font: ft.Face, text_color: sdl.pixels.Color, bg: sdl.render.Texture) !sdl.render.Texture {
        const texture = try sdl.render.Texture.init(renderer, .packed_rgba_8_8_8_8, .target, @as(usize, @intCast(self.size)) * scale, scale);

        const last_target = renderer.getTarget();
        defer renderer.setTarget(last_target) catch {
            @panic("failed to restore renderer target");
        };
        try renderer.setTarget(texture);

        for (0..self.size) |i| {
            const rect = sdl.rect.FRect{
                .x = @as(f32, @floatFromInt(i * scale)),
                .y = 0,
                .w = @as(f32, @floatFromInt(scale)),
                .h = @as(f32, @floatFromInt(scale)),
            };
            try renderer.renderTexture(bg, null, rect);
        }

        const final_length = @min(self.val.len, self.size);
        const starting_point = if (final_length < self.size) (self.size - final_length) / 2 else 0;
        const text_texture = try helpers.createTextureFromText(font, self.val[0..final_length], text_color, renderer);

        try renderer.renderTexture(
            text_texture,
            null,
            .{
                .x = @floatFromInt(scale * starting_point),
                .y = 0,
                .w = @floatFromInt(scale * final_length),
                .h = @floatFromInt(scale),
            },
        );

        return texture;
    }

    fn pointerToPos(self: *Field, blocks: std.hash_map.AutoHashMap(*anyopaque, Block), allocator: std.mem.Allocator) void {
        const ptr = self.ptr orelse return;
        allocator.free(self.val);
        const coords: sdl.rect.IPoint = if (blocks.get(ptr)) |blk| .{ .x = blk.rect.x, .y = blk.rect.y } else .{ .x = 0, .y = 0 };
        self.val = std.fmt.allocPrint(allocator, "{d}|{d}", coords) catch @panic("alloc error");
    }
};

pub const Design = struct {
    font: ft.Face,
    text_color: sdl.pixels.Color,
};

pub fn areaRelativeRect(self: *Self, rect: sdl.rect.IRect) sdl.rect.IRect {
    var ret = rect;
    ret.x += self.are.x;
    ret.y += self.are.y;
}

pub fn absoluteRect(self: *Self, rect: sdl.rect.IRect) sdl.rect.IRect {
    var ret = rect;
    ret.x -= self.are.x;
    ret.y -= self.are.y;
}
