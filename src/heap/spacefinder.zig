const sdl = @import("sdl3");
const std = @import("std");

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
const Direction = enum(i8) { up = 1, down = -1, left = 2, right = -2, none = 0 }; //switch direction by multiplying by -1

pub fn spaceFinder(rect_type: type, gap: comptime_int) type {
    const TYPE = sdl.rect.Rect(rect_type);
    if (gap < 0)
        @compileError("gap size cannot be negative");
    return struct {
        const Self = @This();

        area: TYPE,
        existing_rects: std.ArrayList(RectInfo),

        pub fn init(allocator: std.mem.Allocator, initial_capacity: usize, area: TYPE) !Self {
            return Self{
                .area = area,
                .existing_rects = try std.ArrayList(RectInfo).initCapacity(allocator, initial_capacity),
            };
        }

        pub fn deinit(self: *Self) void {
            self.existing_rects.deinit();
        }

        ///appends to list and maintains order based on x dimension.
        /// array capacity growth is exponential to save reallocations.
        pub fn append(self: *Self, rect: TYPE) !void {
            const rects = &self.existing_rects;

            if (rects.capacity == rects.items.len) {
                const new_cap: usize = @intFromFloat(@as(f32, @floatFromInt(rects.capacity)) * 1.5);
                try rects.ensureTotalCapacity(new_cap);
            }
            const gapped_rect = gappedRect(rect);
            try rects.append(.{ .rect = gapped_rect, .visited = false });
            std.sort.insertion(RectInfo, rects.items, {}, RectInfo.islessthanX);
        }
        pub fn getFreeSpace(self: *Self, size: sdl.rect.Point(rect_type)) TYPE {
            for (self.existing_rects.items) |*strct| {
                strct.visited = false;
            }
            const base_rect: TYPE = .{ .x = self.area.x + @divTrunc(self.area.w, 2), .y = self.area.y + @divTrunc(self.area.h, 2), .w = size.x, .h = size.y };
            return findEmptySpace(base_rect, base_rect, self.existing_rects, .none);
        }
        pub fn remove(self: *Self, rect: TYPE) void {
            for (self.existing_rects.items, 0..) |strct, idx| {
                if (rect.x != strct.rect.x) continue;
                if (rect.y != strct.rect.y) continue;
                if (rect.w != strct.rect.w) continue;
                if (rect.h != strct.rect.h) continue;

                _ = self.existing_rects.orderedRemove(idx);
                return;
            }
        }

        const directed_rects = struct {
            up: TYPE,
            down: TYPE,
            left: TYPE,
            right: TYPE,
        };
        const bad_rect = TYPE{
            .x = std.math.sqrt(std.math.maxInt(rect_type)) / 4,
            .y = std.math.sqrt(std.math.maxInt(rect_type)) / 4,
            .w = 0,
            .h = 0,
        };

        fn findEmptySpace(
            original: TYPE,
            current: TYPE,
            Xlist: std.ArrayList(RectInfo),
            blocked: Direction,
        ) TYPE {
            for (Xlist.items, 0..) |*strct, idx| {
                const rect = strct.rect;
                if (rect.hasIntersection(current)) {
                    if (strct.visited) {
                        //return something that cant be nearest to start point
                        return bad_rect;
                    }
                    strct.visited = true;

                    const diffed: directed_rects = .{
                        .down = .{
                            .x = current.x,
                            .y = rect.y + rect.h,
                            .w = current.w,
                            .h = current.h,
                        },
                        .right = .{
                            .x = rect.x + rect.w,
                            .y = current.y,
                            .w = current.w,
                            .h = current.h,
                        },
                        .left = .{
                            .x = rect.x - current.w,
                            .y = current.y,
                            .w = current.w,
                            .h = current.h,
                        },
                        .up = .{
                            .x = current.x,
                            .y = rect.y - current.h,
                            .w = current.w,
                            .h = current.h,
                        },
                    };

                    // const diff_right_distance = std.math.pow(sdl.rect.IntegerType, diffed.right.x - original.x, 2) + std.math.pow(sdl.rect.IntegerType, diffed.right.y - original.y, 2);
                    // const diff_left_distance = std.math.pow(sdl.rect.IntegerType, diffed.left.x - original.x, 2) + std.math.pow(sdl.rect.IntegerType, diffed.left.y - original.y, 2);
                    // const diff_down_distance = std.math.pow(sdl.rect.IntegerType, diffed.down.x - original.x, 2) + std.math.pow(sdl.rect.IntegerType, diffed.down.y - original.y, 2);
                    // const diff_up_distance = std.math.pow(sdl.rect.IntegerType, diffed.up.x - original.x, 2) + std.math.pow(sdl.rect.IntegerType, diffed.up.y - original.y, 2);
                    const allowed_idx_right = min: {
                        if (blocked == .right) break :min 0;
                        var index = idx;
                        while (index > 0) : (index -= 1) {
                            const rct = Xlist.items[index];
                            if (rct.rect.x + rct.rect.w < diffed.right.x) break;
                        }
                        break :min index;
                    };

                    const res: directed_rects = .{
                        //the directions that decrease list should be first
                        .right = if (blocked == .right) bad_rect else findEmptySpace(original, diffed.right, std.ArrayList(RectInfo).fromOwnedSlice(Xlist.allocator, Xlist.items[allowed_idx_right..]), .left),
                        .down = if (blocked == .down) bad_rect else findEmptySpace(original, diffed.down, Xlist, blocked),
                        .up = if (blocked == .up) bad_rect else findEmptySpace(original, diffed.up, Xlist, blocked),
                        .left = if (blocked == .left) bad_rect else findEmptySpace(original, diffed.left, Xlist, .right),
                    };

                    const right_distance = std.math.pow(sdl.rect.IntegerType, res.right.x - original.x, 2) + std.math.pow(sdl.rect.IntegerType, res.right.y - original.y, 2);
                    // if (diff_down_distance < right_distance) {
                    //     res.down = if (blocked == .down) bad_rect else findEmptySpace(original, diffed.down, Xlist, blocked, reps);
                    // }
                    const down_distance = std.math.pow(sdl.rect.IntegerType, res.down.x - original.x, 2) + std.math.pow(sdl.rect.IntegerType, res.down.y - original.y, 2);
                    // if (diff_down_distance < right_distance) {
                    //     res.down = if (blocked == .down) bad_rect else findEmptySpace(original, diffed.down, Xlist, blocked, reps);
                    // }
                    const left_distance = std.math.pow(sdl.rect.IntegerType, res.left.x - original.x, 2) + std.math.pow(sdl.rect.IntegerType, res.left.y - original.y, 2);
                    const up_distance = std.math.pow(sdl.rect.IntegerType, res.up.x - original.x, 2) + std.math.pow(sdl.rect.IntegerType, res.up.y - original.y, 2);
                    const min_distance = @min(right_distance, down_distance, up_distance, left_distance);
                    if (min_distance == right_distance) {
                        return res.right;
                    } else if (min_distance == down_distance) {
                        return res.down;
                    } else if (min_distance == left_distance) {
                        return res.left;
                    } else {
                        return res.up;
                    }
                }
            }
            return current;
        }

        fn gappedRect(rect: TYPE) sdl.rect.IRect {
            return sdl.rect.IRect{
                .x = rect.x - gap,
                .y = rect.y - gap,
                .w = rect.w + gap * 2,
                .h = rect.h + gap * 2,
            };
        }
    };
}
