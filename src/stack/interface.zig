const std = @import("std");
const sdl = @import("sdl3");
const helpers = @import("../SDL_helpers.zig");
pub const Internal = @import("internal.zig");
const OperationManager = @import("../action/operation_manager.zig");
const Camera = @import("../camera_motion.zig");
const action = @import("../action/action.zig");
data: Internal,
operations: *OperationManager,
stack_height: usize = 0,

const Self = @This();

pub fn call(self: *Self, function: anytype, args: anytype, comptime name: ?[]const u8) callRetType(function) {
    const allocator = self.operations.allocator;
    const fmt = helpers.functionFormat(name orelse "fn", args);
    var predicted_place = self.data.base_rect;
    predicted_place.y -= predicted_place.h * @as(sdl.rect.FloatingType, @floatFromInt(self.stack_height));
    self.operations.append(
        .{
            .call = .{
                .stack = &self.data,
                .new_text = std.fmt.allocPrint(allocator, fmt, args) catch @panic("alloc error"),
            },
        },
    );
    self.stack_height += 1;
    const ret = @call(.auto, function, args);
    self.stack_height -= 1;
    const ret_str = std.fmt.allocPrint(allocator, "{}", .{ret}) catch unreachable;
    self.operations.append(
        .{
            .eval = .{
                .stack = &self.data,
                .new_text = ret_str,
            },
        },
    );
    self.operations.append(
        .{
            .pop = &self.data,
        },
    );

    return ret;
}

fn callRetType(function: anytype) type {
    const type_info = @typeInfo(@TypeOf(function));
    if (type_info != .@"fn") {
        @compileError("Expected a function");
    }
    return type_info.@"fn".return_type.?;
}
