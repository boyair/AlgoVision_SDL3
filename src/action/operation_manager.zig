const std = @import("std");
const sdl = @import("sdl3");
const helpers = @import("../SDL_helpers.zig");
const CameraMotion = @import("../camera_motion.zig").Motion(f64);
const Action = @import("action.zig").Action;
const View = @import("../view.zig");
const Self = @This();
op_queue: std.ArrayList(Action) = .{},
undo_queue: std.ArrayList(Action) = .{},
allocator: std.mem.Allocator,
/// index of the current operation
current: usize = 0,
/// if the entire operation queue was performed
done: bool = false,
/// the maotion of the camera towards the place of action
camera_motion: CameraMotion,
/// pause duration after an action took place so the user can see the change
/// measured in nanoseconds
pause_time: usize = 1_000_000_000,
/// the current step of the active operation
current_step: Steps = .done,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .camera_motion = .init(2_000_000_000, .{ .x = 0, .y = 0, .w = 1920, .h = 1080 }, .{ .x = 0, .y = 0, .w = 1920, .h = 1080 }),
        .allocator = allocator,
    };
}

pub fn currentActionName(self: *const Self) ?[]const u8 {
    if (self.current >= self.op_queue.items.len) return null;
    return self.op_queue.items[self.current].name();
}

pub fn deinit(self: *Self) void {
    for (self.op_queue.items) |*operation| {
        operation.deinit(self.allocator);
    }
    for (self.undo_queue.items) |*action| {
        action.deinit(self.allocator);
    }
    self.op_queue.deinit(self.allocator);
    self.undo_queue.deinit(self.allocator);
}

pub fn append(self: *Self, action: Action) void {
    self.op_queue.append(self.allocator, action) catch {
        @panic("failed to append operation");
    };
}

// TODO: make view not optional and remove the need for a fallback (cahnges should be in update function)
pub fn resetState(self: *Self, view: ?*const View) void {
    const current_op = &self.op_queue.items[self.current];
    self.camera_motion.passed = 0;

    if (view) |v| {
        self.camera_motion.start = v.cam.asOtherRect(f64);
        self.camera_motion.end = helpers.sameRatioRect(
            f64,
            helpers.gappedRect(sdl.rect.FloatingType, current_op.getRect(), 100).asOtherRect(f64),
            .{ .x = @floatCast(v.cam.w), .y = @floatCast(v.cam.h) },
        );
        //self.camera_motion.end = current_op.getRect().asOtherRect(f64);
    }

    // a fallback in case view is not set. should not happen in normal conditions
    else {
        self.camera_motion.start = .{ .x = 0, .y = 0, .w = 1920, .h = 1080 };
        self.camera_motion.end = current_op.getRect().asOtherRect(f64);
    }

    // self.camera_motion.start = .{ .x = 0, .y = 0, .w = 1920, .h = 1080 };
    // self.camera_motion.end = .{ .x = 0, .y = 1000, .w = 1920, .h = 1080 };
    self.current_step = @enumFromInt(0);
    self.done = false;
    self.pause_time = 1_000_000_000;
    self.camera_motion.duration = 2_000_000_000;
    self.camera_motion.setMinSpeed(1);
    std.debug.print("end: {d}, {d}, {d}, {d}\n", self.camera_motion.end);
}

pub fn update(self: *Self, interval_ns: f64, view: ?*View) void {
    if (self.done) return;

    const current_op = &self.op_queue.items[self.current];
    // std.debug.print("view: {d}, {d}, {d}, {d}\n", view.?.cam);
    switch (self.current_step) {
        .look => {
            self.camera_motion.update(interval_ns);
            if (view) |v| {
                v.cam = self.camera_motion.currentRect().asOtherRect(f32);
            }

            if (!self.camera_motion.running()) {
                self.current_step.iterate();
            }
        },
        .act => {
            self.undo_queue.ensureTotalCapacity(self.allocator, self.op_queue.capacity) catch @panic("alloc error");
            self.undo_queue.append(self.allocator, current_op.perform(self.allocator, false)) catch @panic("alloc error");
            self.current_step.iterate();
        },
        .pause => {
            self.pause_time -= @min(@as(usize, @intFromFloat(interval_ns)), self.pause_time);
            if (self.pause_time == 0) {
                self.current_step.iterate();
            }
        },
        .done => {
            self.current += 1;
            self.current_step.iterate();
            self.done = self.current >= self.op_queue.items.len;
            if (self.done) {
                self.current_step = .done;
            } else {
                self.resetState(view);
            }
        },
    }

    // if (current_op.update(interval_ns, self.allocator)) |ret| {
    //     switch (ret) {
    //         .action => |undo| {
    //             // small efficiency gain by preventing repeating reallocations
    //             //  since undo_queue size maximum will be op_queue size
    //             self.undo_queue.ensureTotalCapacity(self.op_queue.capacity) catch @panic("alloc error");
    //
    //             self.undo_queue.append (undo) catch @panic("alloc error");
    //         },
    //         .animation_state => |rect| {
    //             if (view) |v| {
    //                 v.cam = rect.asOtherRect(f32);
    //             }
    //         },
    //         .done => {
    //             self.current += 1;
    //             self.done =
    //                 self.current >= self.op_queue.items.len;
    //             if (self.done)
    //                 self.op_queue.items[self.op_queue.items.len - 1].current_step = .done;
    //         },
    //     }
    // }
}

pub fn incrementCurrent(self: *Self) void {
    self.current += 1;
    self.current = @min(self.op_queue.items.len - 1, self.current);
}

pub fn undoLast(self: *Self, view: ?*View) void {
    if (self.current < 2) return;
    self.done = false;
    while (self.current >= self.op_queue.items.len) self.current -= 1;
    if (@intFromEnum(self.current_step) > @intFromEnum(Steps.act)) {
        self.resetState(view);
    } else {
        self.current -= 1;
        self.resetState(view);
    }
    // set minimum of 200ms fir camera motion to prevent cases where the user cant undo
    // an operation because it passed by to quickly.
    self.camera_motion.duration = @max(200000000, self.camera_motion.duration / 2);
    const last_action = &self.undo_queue.items[self.undo_queue.items.len - 1];
    last_action.perform(self.allocator, true);
    last_action.deinit(self.allocator);
}

pub fn fastForward(self: *Self, view: ?*View) void {
    if (self.done) return;
    const current = if (self.current < self.op_queue.items.len) &self.op_queue.items[self.current] else return;
    if (!(@intFromEnum(self.current_step) > @intFromEnum(Steps.act))) {
        self.undo_queue.append(self.allocator, current.perform(self.allocator, false)) catch @panic("alloc error");
    }
    self.current_step = .done;
    if (view) |v| {
        v.cam = self.camera_motion.end.asOtherRect(f32);
    }
}

pub fn endCamState(self: *const Self) sdl.rect.FRect {
    for (std.mem.reverseIterator(self.op_queue.items)) |operation| {
        if (operation.ptr.camera_motion) |motion| return motion.end;
    }
    return .{ .x = 0, .y = 0, .w = 1920, .h = 1080 };
}

///prints a list of all operations in list for debugging purposes
pub fn printAll(self: *Self) void {
    for (self.op_queue.items) |operation| {
        switch (operation) {
            .call => |data| {
                std.debug.print("call:\t{s}\n", .{data.new_text});
            },
            .eval => |data| {
                std.debug.print("eval:\t{s}\n", .{data.new_text});
            },
            .pop => |_| {
                std.debug.print("pop!\t\n", .{});
            },
            .create => |data| {
                std.debug.print("create:\t{s}\n", .{data.block.fields.items[0].val});
            },
            .override => |data| {
                std.debug.print("override: {s}", .{data.block.fields.items[0].val});
            },
            .destroy => |_| {
                std.debug.print("destroy!\t\n", .{});
            },
        }
    }
}

///prints a list of all undo operations in list for debugging purposes
pub fn printAllUndo(self: *Self) void {
    for (self.undo_queue.items) |action| {
        switch (action) {
            .call => |data| {
                std.debug.print("call:\t{s}\n", .{data.new_text});
            },
            .eval => |data| {
                std.debug.print("eval:\t{s}\n", .{data.new_text});
            },
            .pop => |_| {
                std.debug.print("pop!\t\n", .{});
            },
            .create => |_| {
                std.debug.print("create!\t\n", .{});
            },
            .destroy => |_| {
                std.debug.print("destroy!\t\n", .{});
            },
        }
    }
}

const Steps = enum(u8) {
    look = 0,
    act,
    pause,
    done,

    ///moves to next step
    pub fn iterate(self: *Steps) void {
        self.* = @enumFromInt((@intFromEnum(self.*) + 1) % (@intFromEnum(Steps.done) + 1));
    }
};
