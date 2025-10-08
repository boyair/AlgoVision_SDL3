const std = @import("std");
const sdl = @import("sdl3");

const Self = @This();
texture: sdl.render.Texture,
renderer: sdl.render.Renderer,
/// rect is used as a part of the window. 1 = all width/height, 0.5 = half width/height etc. . .
rect: sdl.rect.FRect,
active: bool = false,
tick_update: *fn (self: *Self, delta: f32, event: sdl.events.Event) void,

fn init(texture_res: sdl.rect.Point(u32), rect: sdl.rect.FRect, renderer: sdl.render.Renderer) Self {
    return .{
        .texture = sdl.render.Texture.init(renderer, .packed_rgba_8_8_8_8, .target, texture_res.x, texture_res.y),
        .rect = .rect,
        .active = false,
        .renderer = renderer,
        .update = null,
    };
}

fn target(self: *Self, renderer: sdl.render.Renderer) void {
    renderer.setTarget(self.texture);
}

fn update(self: *Self, delta: f32, event: sdl.events.Event) void {
    if (self.active) {
        self.tick_update(self, delta, event);
    }
}

fn deinit(self: *Self) void {
    self.texture.destroy();
}
