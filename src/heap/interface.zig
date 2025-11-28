const std = @import("std");
const sdl = @import("sdl3");
const SpaceFinder = @import("spacefinder.zig").spaceFinder;
pub const Internal = @import("internal.zig");
const OperationManager = @import("../action/operation_manager.zig");
const Camera = @import("../camera_motion.zig");
const ft = @import("freetype");

const Self = @This();
data: Internal,
operations: *OperationManager,
// data that updated on runtime (when code runs) to keep track and know upfront how to operate based on the past.
existing_rects: std.hash_map.AutoHashMap(*anyopaque, sdl.rect.IRect),
space_finder: SpaceFinder(sdl.rect.IntegerType, 4),

pub fn init(self: *Self, operations: *OperationManager, area: sdl.rect.IRect, allocator: std.mem.Allocator, renderer: sdl.render.Renderer, bg_texture_path: []const u8, block_texture_path: []const u8, font: ft.Face) !void {
    self.data = try Internal.init(allocator, renderer, area, bg_texture_path, block_texture_path, font);
    self.existing_rects = std.hash_map.AutoHashMap(*anyopaque, sdl.rect.IRect).init(allocator);
    self.space_finder = @TypeOf(self.space_finder).init(allocator, 10, area) catch @panic("alloc error");
    errdefer self.data.deinit();
    self.operations = operations;
}

pub fn deinit(self: *Self) void {
    self.data.deinit();
    self.existing_rects.deinit();
    self.space_finder.deinit();
}

pub fn create(self: *Self, val: anytype, allocator: std.mem.Allocator) *@TypeOf(val) {
    const mem = allocator.create(@TypeOf(val)) catch unreachable;
    mem.* = val;

    var block =
        Internal.Block.init(val, .{ .font = self.data.default_font, .text_color = .{ .r = 255, .g = 0, .b = 0, .a = 255 } }, self.operations.allocator, .{ .x = 0, .y = 0 });

    block.rect = self.space_finder.getFreeSpace(.{ .x = block.rect.w, .y = block.rect.h });
    self.space_finder.append(block.rect) catch @panic("alloc error");
    //    const pos = calculateNewPos(self, .{ .x = block.rect.w, .y = block.rect.h });
    //    block.rect.x = pos.x;
    //    block.rect.y = pos.y;

    self.existing_rects.put(@ptrCast(mem), block.rect) catch @panic("alloc error");

    self.operations.append(
        .{
            .create = .{
                .heap = &self.data,
                .block = block,
                .ptr = @ptrCast(mem),
            },
        },
    );
    return mem;
}
pub fn alloc(self: *Self, comptime T: type, size: usize, allocator: std.mem.Allocator) []T {
    switch (@typeInfo(T)) {
        .float => {},
        .int => {},
        else => {
            @compileError("only floats and ints are currently suppurted for arrays");
        },
    }
    const mem = allocator.alloc(T, size) catch @panic("alloc error");
    for (mem) |*elm| {
        elm.* = 0;
    }

    var block = Internal.Block.init(mem, .{ .font = self.data.default_font, .text_color = .{ .r = 255, .g = 0, .b = 0, .a = 255 } }, self.operations.allocator, .{ .x = 0, .y = 0 });

    block.rect = self.space_finder.getFreeSpace(.{ .x = block.rect.w, .y = block.rect.h });
    self.space_finder.append(block.rect) catch @panic("alloc error");

    self.existing_rects.put(@ptrCast(mem.ptr), block.rect) catch @panic("alloc error");

    self.operations.append(
        .{
            .create = .{
                .heap = &self.data,
                .block = block,
                .ptr = @ptrCast(mem),
            },
        },
    );
    return mem;
}

pub fn destroy(self: *Self, ptr: anytype, allocator: std.mem.Allocator) void {
    const is_slice = @typeInfo(@TypeOf(ptr)).pointer.size == .slice;
    const real_ptr = if (is_slice) ptr.ptr else ptr;
    const block_rect = self.existing_rects.get(@ptrCast(real_ptr)) orelse @panic("tried to destroy non alocated memory");

    self.operations.append(
        .{
            .destroy = .{
                .heap = &self.data,
                .ptr = @ptrCast(real_ptr),
            },
        },
    );
    _ = self.existing_rects.remove(real_ptr);
    self.space_finder.remove(block_rect);
    if (is_slice) {
        allocator.free(ptr);
    } else {
        allocator.destroy(ptr);
    }
}

pub fn update(self: *Self, ptr: anytype) void {
    const is_slice = @typeInfo(@TypeOf(ptr)).pointer.size == .slice;
    const real_ptr = if (is_slice) ptr.ptr else ptr;
    const real_value = if (is_slice) ptr else ptr.*;
    const existing_rect = self.existing_rects.getPtr(real_ptr) orelse @panic("updating non allocated memory");
    const block =
        Internal.Block.init(
            real_value,
            .{ .font = self.data.default_font, .text_color = .{ .r = 255, .g = 0, .b = 0, .a = 255 } },
            self.operations.allocator,
            .{ .x = existing_rect.x, .y = existing_rect.y },
        );
    existing_rect.* = block.rect;
    self.operations.append(
        .{
            .override = .{
                .heap = &self.data,
                .block = block,
                .ptr = @ptrCast(real_ptr),
            },
        },
    );
}

fn gappedRect(rect: sdl.rect.IRect, gap: sdl.rect.IntegerType) sdl.rect.IRect {
    return sdl.rect.IRect{
        .x = rect.x - gap,
        .y = rect.y - gap,
        .w = rect.w + gap * 2,
        .h = rect.h + gap * 2,
    };
}

const RectInfo = struct {
    rect: sdl.rect.IRect,
    visited: bool,

    fn islessthanX(context: void, lhs: RectInfo, rhs: RectInfo) bool {
        _ = context;
        return (lhs.rect.x + lhs.rect.w <= rhs.rect.x + rhs.rect.w);
    }
    fn islessthanY(context: void, lhs: RectInfo, rhs: RectInfo) bool {
        _ = context;
        return (lhs.rect.y + lhs.rect.h <= rhs.rect.y + rhs.rect.h);
    }
};

fn calculateNewPos(self: *const Self, size: sdl.rect.IPoint) sdl.rect.IPoint {
    //convert rects to an array for "efficiency" (heap allocation each call is bad)
    var rects = std.ArrayList(RectInfo).initCapacity(self.data.allocator, self.existing_rects.count()) catch @panic("alloc error");
    defer rects.deinit();
    var Xrects = std.ArrayList(RectInfo).initCapacity(self.data.allocator, self.existing_rects.count()) catch @panic("alloc error");
    defer Xrects.deinit();

    //var timer = std.time.Timer.start() catch unreachable;
    var it = self.existing_rects.iterator();
    while (it.next()) |cur| {
        const gapped_rect = gappedRect(cur.value_ptr.*, 0);
        Xrects.append(.{ .rect = gapped_rect, .visited = false }) catch @panic("alloc error");
    }
    std.sort.insertion(RectInfo, Xrects.items, {}, RectInfo.islessthanX);
    const current: sdl.rect.IRect = .{ .x = self.data.area.x, .y = self.data.area.y, .w = size.x, .h = size.y };
    const ret = findEmptySpace(current, current, Xrects);

    return .{ .x = ret.x, .y = ret.y };
}

fn findEmptySpace(
    original: sdl.rect.IRect,
    current: sdl.rect.IRect,
    Xlist: std.ArrayList(RectInfo),
) sdl.rect.IRect {
    for (Xlist.items, 0..) |*strct, idx| {
        const rect = strct.rect;
        if (rect.hasIntersection(current)) {
            if (strct.visited) {
                //return something that cant be nearest to start point
                return sdl.rect.IRect{
                    .x = std.math.sqrt(std.math.maxInt(sdl.rect.IntegerType)) / 4,
                    .y = std.math.sqrt(std.math.maxInt(sdl.rect.IntegerType)) / 4,
                    .w = 0,
                    .h = 0,
                };
            }

            strct.visited = true;

            const finalY = rect.y + rect.h;
            const finalX = rect.x + rect.w;

            const ydiffed_rect: sdl.rect.IRect = .{
                .x = current.x,
                .y = finalY,
                .w = current.w,
                .h = current.h,
            };

            const xdiffed_rect: sdl.rect.IRect = .{
                .x = finalX,
                .y = current.y,
                .w = current.w,
                .h = current.h,
            };

            const allowed_idx = min: {
                var index = idx;
                while (index > 0) : (index -= 1) {
                    const rct = Xlist.items[index];
                    if (rct.rect.x + rct.rect.h < finalX) break;
                }
                break :min index;
            };

            const Yres = findEmptySpace(original, ydiffed_rect, Xlist);
            const Xres = findEmptySpace(original, xdiffed_rect, std.ArrayList(RectInfo).fromOwnedSlice(Xlist.allocator, Xlist.items[allowed_idx..]));
            const xdistance = std.math.pow(sdl.rect.IntegerType, Xres.x - original.x, 2) + std.math.pow(sdl.rect.IntegerType, Xres.y - original.y, 2);
            const ydistance = std.math.pow(sdl.rect.IntegerType, Yres.x - original.x, 2) + std.math.pow(sdl.rect.IntegerType, Yres.y - original.y, 2);
            if (xdistance > ydistance) {
                return Yres;
            } else {
                return Xres;
            }
        }
    }
    return current;
}
