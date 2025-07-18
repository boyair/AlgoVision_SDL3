const std = @import("std");
const sdl = @import("sdl3");
const View = @import("../view.zig");

///makes an interactive UI element
///can be used to change values when handling an event
///
/// ## parameters:
/// value_type - type of value connected to the element.
/// design_type - design type for the element.
/// maketexture - function to create the texture of the element.
/// eventHandle - function that handles event when interacting with element.
pub fn interactiveElement(
    value_type: type,
    design_type: type,
    makeTexture: if (design_type == void) fn (current_value: value_type, renderer: sdl.render.Renderer) sdl.render.Texture else fn (current_value: value_type, design: design_type, renderer: sdl.render.Renderer) sdl.render.Texture,
    eventHandle: if (design_type == void) ?fn (event: *const sdl.events.Event, value: *value_type, relative_mouse: sdl.rect.FPoint) void else ?fn (event: *const sdl.events.Event, value: *value_type, design: design_type, relative_mouse: sdl.rect.FPoint) void,
) type {
    if (design_type != void) return struct {
        value: *value_type, // pointer to entangled value.
        cache: value_type, // last value to prevent texture recreation.
        design: design_type, // design of the element.
        texture: ?sdl.render.Texture,
        rect: sdl.rect.FRect, // location of element.

        const Self = @This();
        pub const texFn = makeTexture;
        pub fn init(entangled: *value_type, rect: sdl.rect.FRect, design: design_type) Self {
            return .{
                .value = entangled,
                .cache = entangled.*,
                .design = design,
                .texture = null,
                .rect = rect,
            };
        }

        pub fn draw(self: *Self, view: ?View, renderer: sdl.render.Renderer) !void {
            if (@typeInfo(value_type) == .pointer and @typeInfo(value_type).pointer.size == .slice) {
                if (!std.mem.eql(@typeInfo(value_type).pointer.child, self.value.*, self.cache) or self.texture == null) {
                    self.updateTexture(renderer) catch unreachable;
                    self.cache = self.value.*;
                }
            } else {
                if (self.value.* != self.cache or self.texture == null) {
                    self.updateTexture(renderer) catch unreachable;
                    self.cache = self.value.*;
                }
            }
            const dst_rect = if (view) |v| v.convertRect(sdl.rect.FloatingType, self.rect) else self.rect;
            try renderer.renderTexture(self.texture orelse unreachable, null, dst_rect);
        }

        pub fn handleEvent(self: *Self, event: *const sdl.events.Event, mouse_pos: sdl.rect.FPoint, view: View) void {
            if (eventHandle) |handle| {
                if (self.isHovered(mouse_pos, view)) {
                    const Frect = self.rect.asOtherRect(sdl.rect.FloatingType);
                    var relative_mouse_pos = view.revertPoint(sdl.rect.FloatingType, mouse_pos);
                    relative_mouse_pos.x -= Frect.x;
                    relative_mouse_pos.x /= Frect.w;
                    relative_mouse_pos.y -= Frect.y;
                    relative_mouse_pos.y /= Frect.h;
                    handle(event, self.value, self.design, relative_mouse_pos);
                }
            }
        }

        pub fn updateTexture(self: *Self, renderer: sdl.render.Renderer) !void {
            if (self.texture) |prev_tex| {
                prev_tex.deinit();
            }
            self.texture = makeTexture(self.value.*, self.design, renderer);
        }

        pub fn isHovered(self: *const Self, mouse_pos: sdl.rect.FPoint, view: View) bool {
            const converted_mouse = view.revertPoint(sdl.rect.FloatingType, mouse_pos);
            return self.rect.asOtherRect(sdl.rect.FloatingType).pointIn(converted_mouse);
        }

        ///used to identify items generated from interactiveElement function
        pub fn getParams() struct { type, type, @TypeOf(makeTexture), @TypeOf(eventHandle) } {
            return .{
                value_type,
                design_type,
                makeTexture,
                eventHandle,
            };
        }

        pub fn deinit(self: *Self) void {
            self.design.deinit();
            if (self.texture) |texture| {
                texture.deinit();
            }
        }
    };

    return struct {
        value: *value_type, // pointer to entangled value.
        cache: value_type, // last value to prevent texture recreation.
        texture: ?sdl.render.Texture,
        rect: sdl.rect.FRect, // location of element.

        const Self = @This();
        pub fn init(entangled: *value_type, rect: sdl.rect.FRect) Self {
            return .{
                .value = entangled,
                .cache = entangled.*,
                .texture = null,
                .rect = rect,
            };
        }
        pub fn draw(self: *Self, view: ?View, renderer: sdl.render.Renderer) !void {
            // std.builtin.Type
            if (@typeInfo(value_type) == .pointer and @typeInfo(value_type).pointer.size == .slice) {
                if (std.mem.eql(@typeInfo(value_type).pointer.child, self.value.*, self.cache)) {
                    self.updateTexture(renderer) catch unreachable;
                    self.cache = self.value.*;
                }
            } else {
                if (self.value.* != self.cache or self.texture == null) {
                    self.updateTexture(renderer) catch unreachable;
                    self.cache = self.value.*;
                }
            }
            const dst_rect = if (view) |v| v.convertRect(sdl.rect.FloatingType, self.rect) else self.rect;
            try renderer.renderTexture(self.texture orelse unreachable, null, dst_rect);
        }
        pub fn handleEvent(self: *Self, event: *const sdl.events.Event, mouse_pos: sdl.rect.FPoint, view: View) void {
            if (eventHandle) |handle| {
                if (self.isHovered(mouse_pos, view)) {
                    const Frect = self.rect.asOtherRect(sdl.rect.FloatingType);
                    var relative_mouse_pos = view.revertPoint(sdl.rect.FloatingType, mouse_pos);
                    relative_mouse_pos.x -= Frect.x;
                    relative_mouse_pos.x /= Frect.w;
                    relative_mouse_pos.y -= Frect.y;
                    relative_mouse_pos.y /= Frect.h;
                    handle(event, self.value, relative_mouse_pos);
                }
            }
        }
        pub fn updateTexture(self: *Self, renderer: sdl.render.Renderer) !void {
            if (self.texture) |prev_tex| {
                prev_tex.deinit();
            }
            self.texture = makeTexture(self.value.*, renderer);
        }
        pub fn isHovered(self: *const Self, mouse_pos: sdl.rect.FPoint, view: View) bool {
            const converted_mouse = view.revertPoint(sdl.rect.FloatingType, mouse_pos);
            return self.rect.asOtherRect(sdl.rect.FloatingType).pointIn(converted_mouse);
        }
        ///used to identify items generated from interactiveElement function
        pub fn getParams() struct { type, type, @TypeOf(makeTexture), @TypeOf(eventHandle) } {
            return .{
                value_type,
                design_type,
                makeTexture,
                eventHandle,
            };
        }
        pub fn deinit(self: *Self) void {
            if (self.texture) |texture| {
                texture.deinit();
            }
        }
    };
}

///Takses in a type ant returns if the type is an element
pub fn isElement(Type: type) bool {
    if (@typeInfo(Type) != .@"struct") return false;
    if (@hasDecl(Type, "getParams")) {
        const params = Type.getParams();
        return (interactiveElement(
            params.@"0",
            params.@"1",
            params.@"2",
            params.@"3",
        ) == Type);
    }
    return false;
}

const button = @import("button.zig");
const slider = @import("slider.zig");
const checkbox = @import("checkbox.zig");
const text = @import("text.zig");

pub const Slider = slider.Slider;
pub const Checkbox = checkbox.Checkbox;
pub const Text = text.Text;
pub const Button = button.Button;

pub fn init(renderer: sdl.render.Renderer, allocator: std.mem.Allocator) !void {
    try checkbox.init(renderer, allocator);
}
