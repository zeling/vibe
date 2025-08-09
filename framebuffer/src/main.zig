const std = @import("std");
const c = @cImport({
    @cInclude("stb_truetype.h");
    @cInclude("stb_image_write.h");
    @cInclude("sys/ioctl.h");
    @cInclude("stdio.h");
});
const os = std.os;

const FBIOGET_VSCREENINFO = 0x4600;
const FBIOGET_FSCREENINFO = 0x4602;

const PROT_READ = 1;
const PROT_WRITE = 2;
const MAP_SHARED = 1;

extern "c" fn mmap(addr: ?*anyopaque, len: usize, prot: i32, flags: i32, fd: i32, offset: i64) ?*anyopaque;
extern "c" fn munmap(addr: ?*anyopaque, len: usize) i32;

const fb_bitfield = extern struct {
    offset: u32,
    length: u32,
    msb_right: u32,
};

const fb_var_screeninfo = extern struct {
    xres: u32,
    yres: u32,
    xres_virtual: u32,
    yres_virtual: u32,
    xoffset: u32,
    yoffset: u32,
    bits_per_pixel: u32,
    grayscale: u32,
    red: fb_bitfield,
    green: fb_bitfield,
    blue: fb_bitfield,
    transp: fb_bitfield,
    nonstd: u32,
    activate: u32,
    height: u32,
    width: u32,
    accel_flags: u32,
    pixclock: u32,
    left_margin: u32,
    right_margin: u32,
    upper_margin: u32,
    lower_margin: u32,
    hsync_len: u32,
    vsync_len: u32,
    sync: u32,
    vmode: u32,
    rotate: u32,
    colorspace: u32,
    reserved: [4]u32,
};

const fb_fix_screeninfo = extern struct {
    id: [16]u8,
    smem_start: usize,
    smem_len: u32,
    type: u32,
    type_aux: u32,
    visual: u32,
    xpanstep: u16,
    ypanstep: u16,
    ywrapstep: u16,
    line_length: u32,
    mmio_start: usize,
    mmio_len: u32,
    accel: u32,
    capabilities: u16,
    reserved: [2]u16,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var font_path: ?[]const u8 = null;
    var text: ?[]const u8 = null;
    var fb_path: []const u8 = "/dev/fb0";
    var font_size: f32 = 24.0;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--font")) {
            i += 1;
            if (i < args.len) {
                font_path = args[i];
            } else {
                std.log.err("missing argument for --font", .{});
                return;
            }
        } else if (std.mem.eql(u8, arg, "--text")) {
            i += 1;
            if (i < args.len) {
                text = args[i];
            } else {
                std.log.err("missing argument for --text", .{});
                return;
            }
        } else if (std.mem.eql(u8, arg, "--fb")) {
            i += 1;
            if (i < args.len) {
                fb_path = args[i];
            } else {
                std.log.err("missing argument for --fb", .{});
                return;
            }
        } else if (std.mem.eql(u8, arg, "--font-size")) {
            i += 1;
            if (i < args.len) {
                font_size = try std.fmt.parseFloat(f32, args[i]);
            } else {
                std.log.err("missing argument for --font-size", .{});
                return;
            }
        }
    }

    if (font_path == null) {
        std.log.err("missing --font argument", .{});
        return;
    }

    if (text == null) {
        std.log.err("missing --text argument", .{});
        return;
    }

    const font_buffer = try std.fs.cwd().readFileAlloc(allocator, font_path.?, 10 * 1024 * 1024);
    defer allocator.free(font_buffer);

    std.log.info("font path: {s}", .{font_path.?});
    std.log.info("text: {s}", .{text.?});
    std.log.info("framebuffer path: {s}", .{fb_path});

    var font_info: c.stbtt_fontinfo = undefined;
    _ = c.stbtt_InitFont(&font_info, font_buffer.ptr, 0);

    const font_height_val: f32 = font_size;
    const scale = c.stbtt_ScaleForPixelHeight(&font_info, font_height_val);

    var text_width: f32 = 0;
    var text_height: f32 = 0;
    var ascent: i32 = undefined;
    var descent: i32 = undefined;
    var line_gap: i32 = undefined;

    c.stbtt_GetFontVMetrics(&font_info, &ascent, &descent, &line_gap);

    const scaled_ascent = @as(f32, @floatFromInt(ascent)) * scale;
    const scaled_descent = @as(f32, @floatFromInt(descent)) * scale;

    text_height = scaled_ascent - scaled_descent;

    var prev_codepoint: i32 = 0;
    for (text.?) |codepoint| {
        var advance_width: i32 = undefined;
        var left_side_bearing: i32 = undefined;
        c.stbtt_GetCodepointHMetrics(&font_info, codepoint, &advance_width, &left_side_bearing);

        text_width += @as(f32, @floatFromInt(advance_width)) * scale;

        if (prev_codepoint != 0) {
            text_width += @as(f32, @floatFromInt(c.stbtt_GetCodepointKernAdvance(&font_info, prev_codepoint, codepoint))) * scale;
        }
        prev_codepoint = codepoint;
    }

    const bitmap_width = @as(u32, @intFromFloat(text_width)) + 1;
    const bitmap_height = @as(u32, @intFromFloat(text_height)) + 1;
    // const bitmap_stride = bitmap_width;

    const bitmap_size = bitmap_width * bitmap_height;
    const bitmap_buffer = try allocator.alloc(u8, bitmap_size);
    defer allocator.free(bitmap_buffer);
    @memset(bitmap_buffer, 0);

    std.log.info("bitmap dimensions: {d}x{d}", .{ bitmap_width, bitmap_height });

    // --- Rendering and Framebuffer writing will go here ---

    const fb_fd = try std.fs.openFileAbsolute(fb_path, .{ .mode = .read_write });
    defer fb_fd.close();

    var vinfo: fb_var_screeninfo = undefined;
    var finfo: fb_fix_screeninfo = undefined;

    if (c.ioctl(fb_fd.handle, FBIOGET_VSCREENINFO, &vinfo) < 0) {
        std.log.err("failed to get variable screen info", .{});
        return;
    }

    if (c.ioctl(fb_fd.handle, FBIOGET_FSCREENINFO, &finfo) < 0) {
        std.log.err("failed to get fixed screen info", .{});
        return;
    }

    std.log.info("screen resolution: {d}x{d}", .{ vinfo.xres, vinfo.yres });
    std.log.info("bits per pixel: {d}", .{vinfo.bits_per_pixel});
    std.log.info("line length: {d}", .{finfo.line_length});

    const screen_size = vinfo.xres * vinfo.yres * vinfo.bits_per_pixel / 8;
    std.log.info("got screen size: {d}", .{screen_size});
    const fb_ptr = mmap(null, screen_size, PROT_READ | PROT_WRITE, MAP_SHARED, fb_fd.handle, 0) orelse {
        std.log.err("failed to mmap framebuffer", .{});
        return;
    };
    std.log.info("got mmap ptr {x}", .{
        fb_ptr,
    });
    defer _ = munmap(fb_ptr, screen_size);

    const framebuffer = @as([*]u8, @ptrCast(fb_ptr))[0..screen_size];
    std.log.info("fb len: {d}", .{framebuffer.len});

    // Clear the screen
    @memset(framebuffer, 0);

    var x_pos: f32 = 0;
    const y_pos = scaled_ascent; // Baseline for the text

    prev_codepoint = 0;
    for (text.?) |codepoint| {
        var x0: i32 = undefined;
        var y0: i32 = undefined;
        var x1: i32 = undefined;
        var y1: i32 = undefined;

        c.stbtt_GetCodepointBitmapBox(&font_info, codepoint, scale, scale, &x0, &y0, &x1, &y1);

        const char_bitmap_width = @as(usize, @intFromFloat(@as(f32, @floatFromInt(x1 - x0))));
        const char_bitmap_height = @as(usize, @intFromFloat(@as(f32, @floatFromInt(y1 - y0))));

        const char_bitmap_buffer = try allocator.alloc(u8, @intCast(char_bitmap_width * char_bitmap_height));
        defer allocator.free(char_bitmap_buffer);
        @memset(char_bitmap_buffer, 0);

        c.stbtt_MakeCodepointBitmap(&font_info, char_bitmap_buffer.ptr, @as(c_int, @intCast(char_bitmap_width)), @as(c_int, @intCast(char_bitmap_height)), @as(c_int, @intCast(char_bitmap_width)), scale, scale, codepoint);

        // Copy character bitmap to main bitmap_buffer
        const char_x_offset = @as(u32, @intFromFloat(x_pos + @as(f32, @floatFromInt(x0))));
        const char_y_offset = @as(u32, @intFromFloat(y_pos + @as(f32, @floatFromInt(y0))));

        for (0..@as(usize, char_bitmap_height)) |row| {
            for (0..@as(usize, char_bitmap_width)) |col| {
                const bitmap_val = char_bitmap_buffer[row * char_bitmap_width + col];
                if (bitmap_val > 0) {
                    const target_x = char_x_offset + col;
                    const target_y = char_y_offset + row;

                    if (target_x < bitmap_width and target_y < bitmap_height) {
                        bitmap_buffer[target_y * bitmap_width + target_x] = bitmap_val;
                    }
                }
            }
        }

        var advance_width: i32 = undefined;
        var left_side_bearing: i32 = undefined;
        c.stbtt_GetCodepointHMetrics(&font_info, codepoint, &advance_width, &left_side_bearing);
        x_pos += @as(f32, @floatFromInt(advance_width)) * scale;

        if (prev_codepoint != 0) {
            x_pos += @as(f32, @floatFromInt(c.stbtt_GetCodepointKernAdvance(&font_info, prev_codepoint, codepoint))) * scale;
        }
        prev_codepoint = codepoint;
    }

    // if (c.stbi_write_bmp("/opt/output.bmp", @intCast(bitmap_width), @intCast(bitmap_height), 1, @ptrCast(bitmap_buffer.ptr)) != 0) {
    //     std.process.exit(1);
    // }

    // for (0..4096) |col| {
    //     framebuffer[col] = 1;
    // }
    // Write rendered bitmap to framebuffer
    for (0..bitmap_height) |row| {
        for (0..bitmap_width) |col| {
            const pixel_val = bitmap_buffer[row * bitmap_width + col];
            if (pixel_val > 0) {
                const idx = row * vinfo.xres + col;
                var byte = framebuffer[idx / 8];
                byte |= @as(u8, 1) << @intCast(idx % 8);
                framebuffer[idx / 8] = byte;
                // framebuffer[row * vinfo.xres + col] = 1;
            }
        }
    }
}
