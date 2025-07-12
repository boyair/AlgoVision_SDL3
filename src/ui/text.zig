const std = @import("std");
const ui = @import("UI.zig");
const ft = @import("freetype");
const sdl = @import("sdl3");
const helpers = @import("../SDL_helpers.zig");

const Design = struct {
    font: ft.Face,
    color: sdl.pixels.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    pub fn deinit(self: *Design) void {
        _ = self;
    }
};

pub const Text = ui.interactiveElement(
    []const u8,
    Design,
    makeTexture,
    null,
);

fn makeTexture(value: []const u8, design: Design, renderer: sdl.render.Renderer) sdl.render.Texture {
    return helpers.createTextureFromText(design.font, value, design.color, renderer) catch unreachable;
}
