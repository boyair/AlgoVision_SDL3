const std = @import("std");
const sdl = @import("sdl3");
const ft = @import("freetype");
const View = @import("../view.zig");
const helpers = @import("../SDL_helpers.zig");
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
    fields: std.ArrayList(Field),
    updated: bool = false,
    texture_cache: ?sdl.render.Texture,
    design: Design,

    pub fn init(val: anytype, design: Design, allocator: std.mem.Allocator, pos: sdl.rect.IPoint) Block {
        var fields = std.ArrayList(Field).init(allocator);
        appendFields(val, &fields, allocator);
        const top_width = blk: {
            var top: usize = 0;
            for (fields.items) |field| {
                top = @max(top, field.val.len);
            }
            break :blk top;
        };

        return Block{
            .rect = .{ .x = pos.x, .y = pos.y, .h = @intCast(fields.items.len), .w = @intCast(top_width) },
            .fields = fields,
            .texture_cache = null,
            .design = design,
        };
    }

    //A function used to append all the fields.
    //This function uses recursion and therefor may not be embeded in the init function.
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
                        fields.append(Field.init(val, allocator) catch @panic("field init failure")) catch @panic("alloc error");
                    } else {
                        for (val) |elm| {
                            appendFields(elm, fields, allocator);
                        }
                    }
                } else if (ptr.size == .one) {
                    const fld = Field.init(@intFromPtr(val), allocator) catch @panic("field init failure");
                    fields.append(fld) catch @panic("alloc error");
                }
            },
            .optional => {
                if (val) |real| {
                    appendFields(real, fields, allocator);
                } else {
                    fields.append(Field.init(@as([]const u8, "null"), allocator) catch @panic("field init failure")) catch @panic("alloc error");
                }
            },
            else => { // Handles pointers and other simple types
                fields.append(Field.init(val, allocator) catch @panic("field init failure")) catch @panic("alloc error");
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
        const texture = try renderer.createTexture(.packed_rgba_8_8_8_8, .target, @as(usize, @intCast(self.rect.w)) * scale, @as(usize, @intCast(self.rect.h)) * scale);
        const last_target = renderer.getTarget();
        defer renderer.setTarget(last_target) catch {
            @panic("failed to restore renderer target");
        };
        try renderer.setTarget(texture);

        //       Draw background texture tiled

        //     Draw each field's text
        for (self.fields.items, 0..) |field, i| {
            const text_texture = try helpers.createTextureFromText(self.design.font, field.val, self.design.text_color, renderer);
            defer text_texture.deinit();

            for (0..@max(field.val.len, field.size)) |width| {
                try renderer.renderTexture(bg_texture, null, (sdl.rect.Rect(usize){ .x = width * scale, .y = i * scale, .w = scale, .h = scale }).asOtherRect(sdl.rect.FloatingType));
            }
            const text_rect =
                sdl.rect.FRect{ .x = 0, .y = @as(f32, @floatFromInt(i * scale)), .w = @as(f32, @floatFromInt(field.val.len * scale)), .h = @as(f32, @floatFromInt(scale)) };
            try renderer.renderTexture(text_texture, null, text_rect);
        }

        return texture;
    }

    pub fn deinit(self: *const Block, allocator: std.mem.Allocator) void {
        if (self.texture_cache) |texture| texture.deinit();
        for (self.fields.items) |field| {
            allocator.free(field.val);
        }
        self.fields.deinit();
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
    if (self.blocks.get(ptr)) |*block| {
        block.deinit(self.allocator);
        if (self.blocks.remove(ptr) == false)
            @panic("tried to destroy non allocated memory");
    } else @panic("tried to destoy non existing memory");
}

pub fn override(self: *Self, ptr: *anyopaque, block: Block) void {
    const block_ptr = self.blocks.getPtr(ptr) orelse @panic("writing to non allocated memory");
    for (block.fields.items) |*field| {
        field.pointerToPos(self.blocks, self.allocator);
    }
    block_ptr.deinit(self.allocator);
    block_ptr.* = block;
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
        entry.value_ptr.deinit(self.allocator);
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
    ptr: ?*anyopaque,
    pub fn init(val: anytype, allocator: std.mem.Allocator) !Field {
        const val_size = @sizeOf(@TypeOf(val));
        // std.debug.print("val size: {d}\n", .{val_size});
        const size_str = std.fmt.comptimePrint("{d}", .{val_size});
        const fmt = switch (@TypeOf(val)) {
            u8 => "{c}",
            []u8 => "{s}",
            []const u8 => "{s}",
            *anyopaque => "PPP{x}",
            else => "{: ^" ++ size_str ++ "}",
        };

        const formatted_val = try std.fmt.allocPrint(allocator, fmt, .{val});
        // std.debug.print("{s}", .{formatted_val});
        return Field{
            .size = val_size,
            .val = formatted_val,
            .ptr = if (@TypeOf(val) == *anyopaque) val else null,
        };
    }
    fn pointerToPos(self: *Field, blocks: std.hash_map.AutoHashMap(*anyopaque, Block), allocator: std.mem.Allocator) void {
        const ptr = self.ptr orelse return;
        allocator.free(self.val);
        const coords: sdl.rect.IPoint = if (blocks.get(ptr)) |blk| .{ .x = blk.rect.x, .y = blk.rect.y } else .{ .x = 0, .y = 0 };
        self.val = std.fmt.allocPrint(allocator, "{d} , {d}", coords) catch @panic("alloc error");
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
