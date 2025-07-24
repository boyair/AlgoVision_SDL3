const std = @import("std");
const sdl = @import("sdl3");

pub const Line = struct {
    start: sdl.rect.FPoint,
    end: sdl.rect.FPoint,
    const Self = @This();

    pub fn length(self: Self) f32 {
        const xdiff = std.math.pow(f32, self.end.x - self.start.x, 2);
        const ydiff = std.math.pow(f32, self.end.y - self.start.y, 2);
        return std.math.sqrt(xdiff + ydiff);
    }

    pub inline fn diffx(self: Self) f32 {
        return self.end.x - self.start.x;
    }

    pub inline fn diffy(self: Self) f32 {
        return self.end.y - self.start.y;
    }
};
