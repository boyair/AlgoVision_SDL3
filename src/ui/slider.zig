const std = @import("std");
const ui = @import("UI.zig");
const sdl = @import("sdl3");
const ft = @import("freetype");
const helpers = @import("../SDL_helpers.zig");

//TODO: rename to proeprties here and in UI
const Design = struct {
    range: struct {
        min: f32,
        max: f32,
        pub fn size(self: @This()) f32 {
            return self.max - self.min;
        }
    } = .{ .min = 0, .max = 1 },
    resolution: sdl.rect.IPoint = .{ .x = 400, .y = 100 },
    slider_color: sdl.pixels.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
    frame_thickness: f32 = 10,
    frame_color: sdl.pixels.Color = .{ .r = 127, .g = 127, .b = 127, .a = 255 },
    show_text: bool = false,
    text_color: sdl.pixels.Color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
    text_font: ?ft.Face = null,
    text_convert: ?*const fn (value: f32, buff: []u8) ?[]const u8 = null,
    pub fn deinit(self: *Design) void {
        _ = self;
    }
};

pub const Slider = ui.interactiveElement(
    f32,
    Design,
    makeTexture,
    handleEvent,
);

fn makeTexture(value: f32, design: Design, renderer: sdl.render.Renderer) sdl.render.Texture {
    const fres = design.resolution.asOtherPoint(sdl.rect.FloatingType);

    //renderer restore
    const prev_target = renderer.getTarget();
    defer renderer.setTarget(prev_target) catch {
        @panic(sdl.errors.get() orelse unreachable);
    };
    const prev_color = renderer.getDrawColor() catch {
        @panic(sdl.errors.get() orelse unreachable);
    };
    defer renderer.setDrawColor(prev_color) catch {
        @panic(sdl.errors.get() orelse unreachable);
    };

    const texture = sdl.render.Texture.init(renderer, sdl.pixels.Format.packed_rgba_4_4_4_4, .target, @intCast(design.resolution.x), @intCast(design.resolution.y)) catch {
        @panic(sdl.errors.get() orelse unreachable);
    };
    renderer.setTarget(texture) catch {
        @panic(sdl.errors.get() orelse unreachable);
    };
    renderer.setDrawColor(design.frame_color) catch {
        @panic(sdl.errors.get() orelse unreachable);
    };
    renderer.renderFillRect(.{ .x = 0, .y = 0, .w = design.frame_thickness, .h = fres.y }) catch {
        @panic(sdl.errors.get() orelse unreachable);
    };

    //Draw frame
    renderer.renderFillRect(.{ .x = 0, .y = 0, .w = fres.x, .h = design.frame_thickness }) catch {
        @panic(sdl.errors.get() orelse unreachable);
    };
    renderer.renderFillRect(.{ .x = fres.x - design.frame_thickness, .y = 0, .w = design.frame_thickness, .h = fres.y }) catch {
        @panic(sdl.errors.get() orelse unreachable);
    };
    renderer.renderFillRect(.{ .x = 0, .y = 0, .w = fres.x, .h = design.frame_thickness }) catch {
        @panic(sdl.errors.get() orelse unreachable);
    };
    renderer.renderFillRect(.{ .x = 0, .y = fres.y - design.frame_thickness, .w = fres.x, .h = design.frame_thickness }) catch {
        @panic(sdl.errors.get() orelse unreachable);
    };

    //Draw slider
    renderer.setDrawColor(design.slider_color) catch {
        @panic(sdl.errors.get() orelse unreachable);
    };
    const slider_rect: sdl.rect.FRect = .{
        .x = design.frame_thickness,
        .y = design.frame_thickness,
        .w = (fres.x - 2 * design.frame_thickness) * (value - design.range.min) / design.range.size(),
        .h = (fres.y - 2 * design.frame_thickness),
    };
    renderer.renderFillRect(slider_rect) catch {
        @panic(sdl.errors.get() orelse unreachable);
    };
    if (!design.show_text)
        return texture;

    // draw number
    var buf: [10]u8 = undefined;
    const num_str = if (design.text_convert) |convert| convert(value, &buf) orelse return texture else std.fmt.bufPrintZ(&buf, "{d:.2}", .{value}) catch {
        std.log.debug("could not print slider value!\n", .{});
        return texture;
    };

    const font = design.text_font orelse {
        std.log.debug("could not find text font!\n", .{});
        return texture;
    };
    const num_texture = helpers.createTextureFromText(font, num_str, design.text_color, renderer) catch {
        @panic(sdl.errors.get() orelse unreachable);
    };
    const num_pixel_length = @min(fres.x - design.frame_thickness * 2, @as(sdl.rect.FloatingType, @floatFromInt(num_str.len)) * slider_rect.h / 3);
    const num_texture_rect: sdl.rect.FRect = helpers.centrelizedRect(sdl.rect.FloatingType, .{ .x = 0, .y = 0, .w = fres.x, .h = fres.y }, .{ .x = num_pixel_length, .y = slider_rect.h });

    renderer.renderTexture(num_texture, null, num_texture_rect) catch {
        @panic(sdl.errors.get() orelse unreachable);
    };

    return texture;
}

fn handleEvent(event: *const sdl.events.Event, float: *f32, design: Design, relative_mouse_pos: sdl.rect.FPoint) void {
    // cant use event to check for mouse being held.
    // resort to mouse state :(
    // maybe will use a better solution in the future. . .
    _ = event;

    const fres = design.resolution.asOtherPoint(sdl.rect.FloatingType);
    const real_mouse_pos: sdl.rect.FPoint = .{
        .x = relative_mouse_pos.x * @as(f32, @floatFromInt(design.resolution.x)),
        .y = relative_mouse_pos.y * @as(f32, @floatFromInt(design.resolution.y)),
    }; // mouse position in texture

    const slider_rect: sdl.rect.FRect = .{
        .x = design.frame_thickness,
        .y = design.frame_thickness,
        .w = (fres.x - 2 * design.frame_thickness),
        .h = (fres.y - 2 * design.frame_thickness),
    };

    var slider_relative = real_mouse_pos;
    slider_relative.x -= slider_rect.x;
    slider_relative.x /= slider_rect.w;
    slider_relative.y -= slider_rect.y;
    slider_relative.y /= slider_rect.h;
    if (sdl.mouse.getState().@"0".left) {
        float.* = design.range.min + slider_relative.x * design.range.size();
        float.* = @max(design.range.min, @min(design.range.max, float.*));
    }
}
