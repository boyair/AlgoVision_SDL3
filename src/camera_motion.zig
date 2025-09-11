///moves camera from one state to another over a time duration
const std = @import("std");
const sdl = @import("sdl3");
const helpers = @import("SDL_helpers.zig");
pub fn Motion(rect_type: type) type {
    return struct {
        const Self = @This();
        duration: rect_type,
        passed: rect_type = 0,
        minimum_speed: rect_type,
        start: sdl.rect.Rect(rect_type),
        end: sdl.rect.Rect(rect_type),

        pub fn init(duration: rect_type, start: sdl.rect.Rect(rect_type), end: sdl.rect.Rect(rect_type)) Self {
            return Self{
                .duration = duration,
                .minimum_speed = 0,
                .start = start,
                .end = end,
            };
        }

        pub fn update(self: *Self, interval_ns: rect_type) void {
            self.passed += interval_ns;
        }

        /// sets minimum speed for camera motion.
        /// adjusts duration to fit minimum speed.
        /// WARNING: resets passed time!
        /// distance is calculated based on top left points of start and end states.
        pub fn setMinSpeed(self: *Self, min_speed: rect_type) void {
            self.minimum_speed = min_speed;
            const start_pos: sdl.rect.Point(rect_type) = .{ .x = self.start.x, .y = self.start.y };
            const end_pos: sdl.rect.Point(rect_type) = .{ .x = self.end.x, .y = self.end.y };
            const distance = helpers.calculateDistance(rect_type, start_pos, end_pos);
            const speed_per_ms = min_speed / 1_000_000;
            if (distance / (self.duration - self.passed) < speed_per_ms) {
                self.duration = distance / speed_per_ms;
            }
            self.passed = 0;
        }
        pub fn running(self: *const Self) bool {
            return self.passed < self.duration;
        }

        pub fn reset(self: *Self) void {
            self.passed = 0;
        }

        pub fn currentRect(self: *const Self) sdl.rect.Rect(rect_type) {
            if (!self.running())
                return self.end;
            const fraction_passed: rect_type = self.passed / self.duration;
            return .{
                .x = @floatCast((self.end.x - self.start.x) * fraction_passed + self.start.x),
                .y = @floatCast((self.end.y - self.start.y) * fraction_passed + self.start.y),
                .w = @floatCast((self.end.w - self.start.w) * fraction_passed + self.start.w),
                .h = @floatCast((self.end.h - self.start.h) * fraction_passed + self.start.h),
            };
        }
    };
}
