const ft = @import("freetype");
pub const Library = ft.Library;
pub const c = @cImport({
    @cInclude("ft2build.h");
    @cInclude("freetype/freetype.h");
});
