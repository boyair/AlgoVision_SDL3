const std = @import("std");
const sdl = @import("sdl3");
const stack = @import("../stack/internal.zig");
const heap = @import("../heap/internal.zig");

pub const Action = union(enum) {
    //stack
    call: struct { stack: *stack, new_text: []const u8 },
    eval: struct { stack: *stack, new_text: []const u8 },

    //heap
    create: struct { heap: *heap, block: heap.Block, ptr: *anyopaque },
    destroy: struct { heap: *heap, ptr: *anyopaque },
    override: struct { heap: *heap, block: heap.Block, ptr: *anyopaque },

    pop: *stack,

    ///performs a given action.
    ///returns an action that undo it (allocator used for resources allocation)
    pub fn perform(action: Action, allocator: std.mem.Allocator, comptime is_undo: bool) if (is_undo) void else Action {
        switch (action) {
            .call => |data| {
                data.stack.push(data.new_text) catch @panic("failed to push new text");
                if (!is_undo) return .{ .pop = data.stack };
            },

            .eval => |data| {
                const last_text = data.stack.stack_frame.items[data.stack.stack_frame.items.len - 1].text;
                data.stack.topBlock().setText(data.new_text, data.stack.allocator);
                if (!is_undo) return .{ .eval = .{ .stack = data.stack, .new_text = allocator.dupe(u8, last_text) catch unreachable } };
            },

            .pop => |data| {
                const top_block = data.stack_frame.pop() orelse @panic("pop an empty stack");
                defer top_block.deinit(data.allocator);
                if (!is_undo) return .{ .call = .{ .stack = data, .new_text = allocator.dupe(u8, top_block.text) catch unreachable } };
            },

            .create => |data| {
                data.heap.push(data.ptr, data.block.deepCopy(data.heap.allocator)) catch unreachable;
                if (!is_undo) return .{
                    .destroy = .{
                        .heap = data.heap,
                        .ptr = data.ptr,
                    },
                };
            },

            .destroy => |data| {
                if (is_undo) {
                    data.heap.destroy(data.ptr);
                } else {
                    const ret = data.heap.blocks.get(data.ptr).?.deepCopy(allocator);
                    data.heap.destroy(data.ptr);
                    return .{ .create = .{ .heap = data.heap, .block = ret, .ptr = @ptrCast(data.ptr) } }; // for creation undo, ptr is meaningless so I just assign a unique addess
                }
            },

            .override => |data| {
                if (is_undo) {
                    data.heap.override(data.ptr, data.block.deepCopy(data.heap.allocator));
                } else {
                    const ret = data.heap.blocks.get(data.ptr).?.deepCopy(allocator);
                    data.heap.override(data.ptr, data.block.deepCopy(data.heap.allocator));
                    return .{ .override = .{ .heap = data.heap, .block = ret, .ptr = @ptrCast(data.ptr) } }; // for creation undo, ptr is meaningless so I just assign a unique addess
                }
            },
        }
    }

    ///returns the rectangle related to the action
    pub fn getRect(self: Action) sdl.rect.FRect {
        // _ = self;
        // return .{ .x = 0, .y = 0, .w = 1920, .h = 1080 };
        switch (self) {
            .call => |data| {
                var ret = data.stack.topRect();
                ret.y += data.stack.base_rect.h;
                return ret;
            },
            .pop => |data| {
                return data.topRect();
            },
            .eval => |data| {
                return data.stack.topRect();
            },
            .create => |data| {
                return heap.scaleRect(data.block.rect, data.heap.draw_scale).asOtherRect(sdl.rect.FloatingType);
            },
            .destroy => |data| {
                return heap.scaleRect(data.heap.blocks.get(data.ptr).?.rect, data.heap.draw_scale).asOtherRect(sdl.rect.FloatingType);
            },
            .override => |data| {
                return heap.scaleRect(data.heap.blocks.get(data.ptr).?.rect, data.heap.draw_scale).asOtherRect(sdl.rect.FloatingType);
            },
        }
    }
    pub fn deinit(action: Action, allocator: std.mem.Allocator) void {
        switch (action) {
            .call => |data| {
                allocator.free(data.new_text);
            },

            .eval => |data| {
                allocator.free(data.new_text);
            },

            .pop => |_| {},

            .create => |data| {
                data.block.deinit(allocator);
            },

            .destroy => |_| {},

            .override => |data| {
                data.block.deinit(allocator);
            },
        }
    }

    pub fn name(action: Action) []const u8 {
        return @tagName(std.meta.activeTag(action));
    }
};
