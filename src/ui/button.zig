const std = @import("std");
const ui = @import("UI.zig");
const sdl = @import("sdl3");
const ft = @import("freetype");
const helpers = @import("../SDL_helpers.zig");

pub const Button = ui.interactiveElement(
    bool,
    Design,
    makeTexture,
    handleEvent,
);

fn makeTexture(value: bool, design: Design, renderer: sdl.render.Renderer) sdl.render.Texture {
    _ = value;

    return helpers.cloneTexture(design.texture, renderer) catch @panic("draw error");
}

fn handleEvent(event: *const sdl.events.Event, value: *bool, design: Design, relative_mouse_pos: sdl.rect.FPoint) void {
    _ = design;
    _ = relative_mouse_pos;
    value.* = false;
    if (event.* == .mouse_button_down and event.mouse_button_down.button == .left)
        value.* = true;
}

const Design = struct {
    texture: sdl.render.Texture,
    size_multiplyer: sdl.rect.FPoint = .{ .x = 1, .y = 1 },
    pub fn deinit(self: *Design) void {
        self.texture.deinit();
    }
};
